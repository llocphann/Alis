pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Simple polled resource usage service with RAM, Swap, CPU usage, and temperatures.
 */
Singleton {
    id: root

    property bool _runningRequested: false
    property bool _initRequested: false
    property int _persistentConsumers: 0
    property int _historyConsumers: 0
    property double _historyTransientUntilMs: 0
    property int _networkConsumers: 0
    property double _networkTransientUntilMs: 0

    // Auto-stop polling when nothing requested it recently.
    // This prevents the service from running forever after briefly opening a panel.
    // Persistent consumers (bar, vertical bar) prevent auto-stop entirely.
    readonly property int _autoStopDelayMs: Config.options?.resources?.autoStopDelay ?? 15000
    readonly property int _diskUpdateIntervalMs: 30000
    readonly property int _configuredUpdateIntervalMs: {
        const configured = Number(Config.options?.resources?.updateInterval ?? 3000)
        return Number.isFinite(configured) ? Math.max(100, Math.round(configured)) : 3000
    }
    readonly property int _effectiveUpdateIntervalMs:
        (Config.options?.performance?.lowPower ?? false)
            ? Math.max(6000, root._configuredUpdateIntervalMs)
            : root._configuredUpdateIntervalMs
    // nvidia-smi and intel_gpu_top spawn helper processes and are much more
    // expensive than the sysfs path. Keep CPU/RAM responsive while sampling
    // process-backed GPU usage at a lower cadence.
    readonly property int _expensiveGpuUpdateIntervalMs:
        (Config.options?.performance?.lowPower ?? false)
            ? Math.max(15000, root._effectiveUpdateIntervalMs)
            : Math.max(6000, root._effectiveUpdateIntervalMs)
    property real _lastExpensiveGpuPollMs: 0
    // 0 + zero-guard avoids fake "100%" before first poll.
    property real memoryTotal: 0
    property real memoryFree: 0
    property real memoryUsed: memoryTotal - memoryFree
    property real memoryUsedPercentage: memoryTotal > 0 ? (memoryUsed / memoryTotal) : 0
    property real swapTotal: 0
    property real swapFree: 0
    property real swapUsed: swapTotal - swapFree
    property real swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0
    property real cpuUsage: 0
    property var previousCpuStats
    property real gpuUsage: 0
    property real networkRxBytesPerSec: 0
    property real networkTxBytesPerSec: 0
    property real _lastNetworkRxBytes: 0
    property real _lastNetworkTxBytes: 0
    property real _lastNetworkSampleMs: 0

    // Temperature properties (in Celsius)
    property int cpuTemp: 0
    property int gpuTemp: 0
    property int maxTemp: Math.max(cpuTemp, gpuTemp)
    property real tempPercentage: Math.min(maxTemp / 100, 1.0)  // Normalized to 100°C max
    property real gpuTempPercentage: Math.min(gpuTemp / 100, 1.0)  // Normalized to 100°C max
    property int tempWarningThreshold: 80  // Warning at 80°C

    // Disk usage (root partition)
    property real diskTotal: 1
    property real diskUsed: 0
    property real diskUsedPercentage: diskTotal > 0 ? diskUsed / diskTotal : 0

    property string maxAvailableMemoryString: kbToGbString(ResourceUsage.memoryTotal)
    property string maxAvailableSwapString: kbToGbString(ResourceUsage.swapTotal)
    property string maxAvailableCpuString: "--"
    property string maxAvailableGpuString: "100%"

    readonly property int historyLength: Config.options?.resources?.historyLength ?? 60
    property list<real> cpuUsageHistory: []
    property list<real> gpuUsageHistory: []
    property list<real> gpuTempHistory: []
    property list<real> memoryUsageHistory: []
    property list<real> swapUsageHistory: []

    function kbToGbString(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    function updateMemoryUsageHistory() {
        memoryUsageHistory = [...memoryUsageHistory, memoryUsedPercentage];
        if (memoryUsageHistory.length > historyLength) {
            memoryUsageHistory.shift();
        }
    }

    Process {
        id: detectGpuUsageSource
        property bool startObserved: false
        // NVIDIA GPUs are detected first by vendor ID (0x10de) and prefer nvidia-smi,
        // because their sysfs gpu_busy_percent can exist but always return 0.
        // AMD/Intel use the native DRM sysfs counter. Fall back to nvidia-smi otherwise.
        command: ["/usr/bin/bash", "-c", `
            nvidia_path=""
            if command -v nvidia-smi >/dev/null 2>&1; then
                nvidia_path=$(command -v nvidia-smi)
            fi

            is_nvidia=""
            for vendor_file in /sys/class/drm/card*/device/vendor; do
                [ -f "$vendor_file" ] || continue
                vendor=$(cat "$vendor_file" 2>/dev/null)
                [ "$vendor" = "0x10de" ] && is_nvidia=1 && break
            done

            if [ -n "$is_nvidia" ] && [ -n "$nvidia_path" ]; then
                echo "nvidia-smi:$nvidia_path"
                exit 0
            fi

            for card in /sys/class/drm/card*; do
                path="$card/device/gpu_busy_percent"
                if [ -f "$path" ]; then
                    echo "sysfs:$path"
                    exit 0
                fi
            done

            # Intel (i915/xe) has no global sysfs busy counter — utilization only via the
            # i915 PMU, which intel_gpu_top reads. Probe it once: it succeeds only when the
            # PMU is accessible (perf_event_paranoid <= 1, CAP_PERFMON, or render-group access).
            # If the probe can't read busy data we fall through rather than spawn it every poll.
            is_intel=""
            for vendor_file in /sys/class/drm/card*/device/vendor; do
                [ -f "$vendor_file" ] || continue
                [ "$(cat "$vendor_file" 2>/dev/null)" = "0x8086" ] && is_intel=1 && break
            done
            if [ -n "$is_intel" ] && command -v intel_gpu_top >/dev/null 2>&1; then
                igt_path=$(command -v intel_gpu_top)
                if timeout 2 "$igt_path" -J -s 500 2>/dev/null | grep -q '"busy"'; then
                    echo "intel:$igt_path"
                    exit 0
                fi
            fi

            if [ -n "$nvidia_path" ]; then
                echo "nvidia-smi:$nvidia_path"
                exit 0
            fi

            echo "none"
        `]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("sysfs:")) {
                    root._gpuUsageSource = "sysfs";
                    root._gpuUsagePath = line.slice(6);
                } else if (line.startsWith("nvidia-smi:")) {
                    root._gpuUsageSource = "nvidia-smi";
                    root._nvidiaSmiPath = line.slice(11);
                } else if (line.startsWith("intel:")) {
                    root._gpuUsageSource = "intel";
                    root._intelGpuTopPath = line.slice(6);
                } else if (line === "none") {
                    root._gpuUsageSource = "none";
                }
            }
        }
        onRunningChanged: {
            if (detectGpuUsageSource.running) {
                detectGpuUsageSource.startObserved = false
                return
            }
            if (detectGpuUsageSource.startObserved)
                return

            root._gpuUsageSource = "none"
            root._gpuUsagePath = ""
            root._nvidiaSmiPath = ""
            root._intelGpuTopPath = ""
            root._releaseInitRequest("GPU usage source")
        }
        onStarted: detectGpuUsageSource.startObserved = true
    }

    Process {
        id: nvidiaGpuProc
        // Query utilization and temperature together for efficiency.
        // temperature.gpu returns the hotspot/junction temp matching what btop shows.
        command: ["/usr/bin/bash", "-c", root._nvidiaSmiPath + " --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -n 1"]
        running: false
        stdout: StdioCollector {
            id: nvidiaGpuCollector
            onStreamFinished: {
                const parts = nvidiaGpuCollector.text.trim().split(",").map(s => s.trim());
                const rawUsage = parseInt(parts[0]);
                const rawTemp = parseInt(parts[1]);
                root.gpuUsage = !isNaN(rawUsage) ? root.clampPercentToUnit(rawUsage / 100) : 0;
                if (!isNaN(rawTemp))
                    root.gpuTemp = rawTemp;
            }
        }
    }

    Process {
        id: intelGpuProc
        // One short PMU sample (~one 500ms period, killed by timeout). intel_gpu_top -J emits
        // per-engine "busy" percentages; aggregate GPU usage = the busiest engine this window.
        command: ["/usr/bin/bash", "-c", "timeout 1 " + root._intelGpuTopPath + " -J -s 500 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            id: intelGpuCollector
            onStreamFinished: {
                const re = /"busy"\s*:\s*([\d.]+)/g;
                let m, maxBusy = -1;
                while ((m = re.exec(intelGpuCollector.text)) !== null) {
                    const v = parseFloat(m[1]);
                    if (!isNaN(v) && v > maxBusy)
                        maxBusy = v;
                }
                root.gpuUsage = maxBusy < 0 ? 0 : root.clampPercentToUnit(maxBusy / 100);
            }
        }
    }
    function updateSwapUsageHistory() {
        swapUsageHistory = [...swapUsageHistory, swapUsedPercentage];
        if (swapUsageHistory.length > historyLength) {
            swapUsageHistory.shift();
        }
    }
    function updateCpuUsageHistory() {
        cpuUsageHistory = [...cpuUsageHistory, cpuUsage];
        if (cpuUsageHistory.length > historyLength) {
            cpuUsageHistory.shift();
        }
    }
    function updateGpuUsageHistory() {
        gpuUsageHistory = [...gpuUsageHistory, gpuUsage];
        if (gpuUsageHistory.length > historyLength) {
            gpuUsageHistory.shift();
        }
    }
    function updateGpuTempHistory() {
        gpuTempHistory = [...gpuTempHistory, gpuTempPercentage];
        if (gpuTempHistory.length > historyLength) {
            gpuTempHistory.shift();
        }
    }
    function updateHistories() {
        if (root._historyConsumers <= 0 && Date.now() >= root._historyTransientUntilMs)
            return
        updateMemoryUsageHistory();
        updateSwapUsageHistory();
        updateCpuUsageHistory();
        updateGpuUsageHistory();
        updateGpuTempHistory();
    }

    function clampPercentToUnit(value: real): real {
        return Math.max(0, Math.min(1, value));
    }

    function _expensiveGpuPollDue(nowMs: real): bool {
        return root._lastExpensiveGpuPollMs <= 0
            || (nowMs - root._lastExpensiveGpuPollMs) >= root._expensiveGpuUpdateIntervalMs
    }

    function _releaseInitRequest(stage: string): void {
        root._initRequested = false
        console.warn("[ResourceUsage] Failed to start " + stage + " probe; initialization can retry on the next consumer request")
    }

    function ensureRunning(withHistory, withNetwork): void {
        const historyWanted = withHistory === undefined ? true : !!withHistory
        const networkWanted = withNetwork === undefined ? true : !!withNetwork
        const nowMs = Date.now()
        if (historyWanted)
            root._historyTransientUntilMs = nowMs + root._autoStopDelayMs
        if (networkWanted)
            root._networkTransientUntilMs = nowMs + root._autoStopDelayMs
        root._runningRequested = true;
        if (!root._initRequested) {
            root._initRequested = true;
            detectTempSensors.running = true;
            detectGpuUsageSource.running = true;
            detectHybridGpu.running = true;
            findCpuMaxFreqProc.running = true;
        }
        if (root._persistentConsumers === 0)
            autoStopTimer.restart();
        if (!pollTimer.running)
            pollTimer.restart();
        // Prime values now instead of waiting one updateInterval — but only once.
        // Multiple consumers calling ensureRunning() in their Component.onCompleted
        // would race their reload() ops and drop in-flight reads (FileView warnings).
        if (!root._primed) {
            root._primed = true;
            root._pollSensors();
            root._pollDisk();
        }
    }

    property bool _primed: false

    // Register a persistent consumer (always-visible panel like bar).
    // While any persistent consumer is registered, auto-stop is disabled.
    function keepAlive(withHistory, withNetwork): void {
        const historyWanted = withHistory === undefined ? true : !!withHistory
        const networkWanted = withNetwork === undefined ? true : !!withNetwork
        root._persistentConsumers++
        if (historyWanted)
            root._historyConsumers++
        if (networkWanted) {
            if (root._networkConsumers === 0)
                root._lastNetworkSampleMs = 0
            root._networkConsumers++
        }
        autoStopTimer.stop()
        ensureRunning(false, false)
    }

    function releaseKeepAlive(withHistory, withNetwork): void {
        const historyWanted = withHistory === undefined ? true : !!withHistory
        const networkWanted = withNetwork === undefined ? true : !!withNetwork
        root._persistentConsumers = Math.max(0, root._persistentConsumers - 1)
        if (historyWanted)
            root._historyConsumers = Math.max(0, root._historyConsumers - 1)
        if (networkWanted) {
            root._networkConsumers = Math.max(0, root._networkConsumers - 1)
            if (root._networkConsumers === 0 && Date.now() >= root._networkTransientUntilMs) {
                root._lastNetworkSampleMs = 0
                root.networkRxBytesPerSec = 0
                root.networkTxBytesPerSec = 0
            }
        }
        if (root._persistentConsumers === 0 && root._runningRequested)
            autoStopTimer.restart()
    }

    function stop(): void {
        root._runningRequested = false;
        root._primed = false;
        root._lastNetworkSampleMs = 0;
        root._historyTransientUntilMs = 0;
        root._networkTransientUntilMs = 0;
        root.networkRxBytesPerSec = 0;
        root.networkTxBytesPerSec = 0;
        pollTimer.stop();
        diskPollTimer.stop();
        autoStopTimer.stop();
    }

    Timer {
        id: autoStopTimer
        interval: root._autoStopDelayMs
        repeat: false
        onTriggered: {
            if (root._persistentConsumers === 0)
                root.stop();
        }
    }

    function _pollSensors(): void {
        // Polling is not a consumer request. Renewing autoStopTimer here keeps a
        // transient ensureRunning() lease alive forever because this function runs
        // more often than the idle timeout. Only ensureRunning()/releaseKeepAlive()
        // may start that timeout.
        // Determine whether GPU polling should be skipped this cycle.
        // On hybrid (iGPU+dGPU) systems, querying GPU data via nvidia-smi or hwmon
        // prevents the discrete GPU from entering runtime suspend, wasting ~9-10W at idle.
        // Reading runtime_status is a pure kernel sysfs read — it does NOT wake the hardware.
        const gpuMonitorEnabled = Config.options?.resources?.monitorGpu ?? true;
        let skipGpu = !gpuMonitorEnabled;
        if (!skipGpu && root._dGpuRuntimeStatusPath !== "") {
            if (fileDGpuRuntimeStatus.text() !== "")
                fileDGpuRuntimeStatus.reload();
            skipGpu = fileDGpuRuntimeStatus.text().trim() === "suspended";
        }

        // Reload files once their initial FileView read has completed.
        if (fileMeminfo.text() !== "")
            fileMeminfo.reload();
        if (fileStat.text() !== "")
            fileStat.reload();
        if (fileNetDev.text() !== "")
            fileNetDev.reload();
        if (root._cpuTempPath !== "" && fileCpuTemp.text() !== "")
            fileCpuTemp.reload();
        if (!skipGpu) {
            if (root._gpuUsageSource !== "nvidia-smi" && root._gpuTempPath !== "" && fileGpuTemp.text() !== "")
                fileGpuTemp.reload();
            if (root._gpuUsageSource === "sysfs" && root._gpuUsagePath !== "" && fileGpuUsage.text() !== "")
                fileGpuUsage.reload();
        }

        // Empty text() on first call collapses to 0% via the percentage guards.
        const textMeminfo = fileMeminfo.text();
        let nextMemoryTotal = 0
        let nextMemoryFree = 0
        let nextSwapTotal = 0
        let nextSwapFree = 0
        const meminfoLine = /^(MemTotal|MemAvailable|SwapTotal|SwapFree):\s+(\d+)/gm
        let meminfoMatch
        while ((meminfoMatch = meminfoLine.exec(textMeminfo)) !== null) {
            const value = Number(meminfoMatch[2]) || 0
            switch (meminfoMatch[1]) {
            case "MemTotal":
                nextMemoryTotal = value
                break
            case "MemAvailable":
                nextMemoryFree = value
                break
            case "SwapTotal":
                nextSwapTotal = value
                break
            case "SwapFree":
                nextSwapFree = value
                break
            }
        }
        memoryTotal = nextMemoryTotal
        memoryFree = nextMemoryFree
        swapTotal = nextSwapTotal
        swapFree = nextSwapFree

        // /proc/net/dev stays cheaply refreshed with the other proc files, but
        // avoid its split/parse allocations unless a consumer displays throughput.
        const networkDemanded = root._networkConsumers > 0
            || Date.now() < root._networkTransientUntilMs
        if (networkDemanded) {
            const textNetDev = fileNetDev.text();
            let totalRx = 0;
            let totalTx = 0;
            // Match one interface row directly instead of splitting the whole
            // file into lines and then allocating a second fields[] array for
            // every interface. Capture RX bytes and TX bytes only.
            const netLine = /^\s*([^:\s]+):\s*(\d+)(?:\s+\d+){7}\s+(\d+)(?:\s+\d+){7}\s*$/gm
            let match
            while ((match = netLine.exec(textNetDev)) !== null) {
                if (match[1] === "lo")
                    continue
                totalRx += Number(match[2]) || 0
                totalTx += Number(match[3]) || 0
            }

            const networkNowMs = Date.now();
            if (root._lastNetworkSampleMs > 0) {
                const elapsedSeconds = (networkNowMs - root._lastNetworkSampleMs) / 1000;
                if (elapsedSeconds > 0) {
                    root.networkRxBytesPerSec = Math.max(
                        0, (totalRx - root._lastNetworkRxBytes) / elapsedSeconds);
                    root.networkTxBytesPerSec = Math.max(
                        0, (totalTx - root._lastNetworkTxBytes) / elapsedSeconds);
                }
            }
            root._lastNetworkRxBytes = totalRx;
            root._lastNetworkTxBytes = totalTx;
            root._lastNetworkSampleMs = networkNowMs;
        }

        // Parse CPU usage
        const textStat = fileStat.text();
        const cpuLine = textStat.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/);
        if (cpuLine) {
            // Avoid slice/map/reduce allocations in the regular sensor poll.
            // /proc/stat fields here are user,nice,system,idle,iowait,irq,softirq.
            const user = Number(cpuLine[1]) || 0
            const nice = Number(cpuLine[2]) || 0
            const system = Number(cpuLine[3]) || 0
            const idleRaw = Number(cpuLine[4]) || 0
            const iowait = Number(cpuLine[5]) || 0
            const irq = Number(cpuLine[6]) || 0
            const softirq = Number(cpuLine[7]) || 0
            const total = user + nice + system + idleRaw + iowait + irq + softirq
            // idle + iowait = not working
            const idle = idleRaw + iowait

            if (previousCpuStats) {
                const totalDiff = total - previousCpuStats.total;
                const idleDiff = idle - previousCpuStats.idle;
                cpuUsage = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0;
            }

            previousCpuStats = {
                total,
                idle
            };
        }

        // Parse temperatures (millidegrees to degrees)
        const cpuTempRaw = parseInt(fileCpuTemp.text()) || 0;
        cpuTemp = Math.round(cpuTempRaw / 1000);
        // GPU temp: skip when suspended/disabled to avoid hwmon reads waking a suspended dGPU
        if (!skipGpu && root._gpuUsageSource !== "nvidia-smi") {
            const gpuTempRaw = parseInt(fileGpuTemp.text()) || 0;
            gpuTemp = Math.round(gpuTempRaw / 1000);
        }

        // Parse GPU usage — skip entirely when dGPU is suspended or monitoring is disabled
        if (skipGpu) {
            gpuUsage = 0;
        } else if (root._gpuUsageSource === "sysfs") {
            const gpuBusyPercent = parseInt(fileGpuUsage.text());
            if (isNaN(gpuBusyPercent)) {
                gpuUsage = 0;
            } else {
                gpuUsage = root.clampPercentToUnit(gpuBusyPercent / 100);
            }
        } else if (root._gpuUsageSource === "nvidia-smi" && !nvidiaGpuProc.running) {
            const nowMs = Date.now()
            if (root._expensiveGpuPollDue(nowMs)) {
                root._lastExpensiveGpuPollMs = nowMs
                nvidiaGpuProc.running = true
            }
        } else if (root._gpuUsageSource === "intel" && !intelGpuProc.running) {
            const nowMs = Date.now()
            if (root._expensiveGpuPollDue(nowMs)) {
                root._lastExpensiveGpuPollMs = nowMs
                intelGpuProc.running = true
            }
        } else if (root._gpuUsageSource === "none") {
            gpuUsage = 0;
        }

        root.updateHistories();

    }

    function _pollDisk(): void {
        if (!diskProc.running)
            diskProc.running = true;
    }

    Timer {
        id: pollTimer
        interval: root._effectiveUpdateIntervalMs
        running: root._runningRequested
        repeat: true
        onTriggered: root._pollSensors()
    }

    Timer {
        id: diskPollTimer
        interval: root._diskUpdateIntervalMs
        running: root._runningRequested
        repeat: true
        onTriggered: root._pollDisk()
    }

    FileView {
        id: fileMeminfo
        path: "/proc/meminfo"
        onLoaded: {
            if (root._runningRequested && root.memoryTotal <= 0)
                root._pollSensors()
        }
    }
    FileView {
        id: fileStat
        path: "/proc/stat"
    }
    FileView {
        id: fileNetDev
        path: "/proc/net/dev"
    }
    // Temperature sensors - k10temp for AMD CPU, amdgpu for AMD GPU
    // These paths are auto-detected at startup
    FileView {
        id: fileCpuTemp
        path: root._cpuTempPath
        onLoaded: {
            if (root._runningRequested && root.cpuTemp <= 0) {
                const cpuTempRaw = parseInt(fileCpuTemp.text()) || 0
                root.cpuTemp = Math.round(cpuTempRaw / 1000)
            }
        }
    }
    FileView {
        id: fileGpuTemp
        path: root._gpuTempPath
        onLoaded: {
            if (root._runningRequested && root.gpuTemp <= 0 && root._gpuUsageSource !== "nvidia-smi") {
                const gpuTempRaw = parseInt(fileGpuTemp.text()) || 0
                root.gpuTemp = Math.round(gpuTempRaw / 1000)
            }
        }
    }
    FileView {
        id: fileGpuUsage
        path: root._gpuUsagePath
    }
    // Hybrid GPU: runtime PM status of the discrete GPU (kernel-only read, never wakes hardware)
    FileView {
        id: fileDGpuRuntimeStatus
        path: root._dGpuRuntimeStatusPath
    }

    // Auto-detect temperature sensor paths
    property string _cpuTempPath: ""
    property string _gpuTempPath: ""
    property string _gpuUsagePath: ""
    property string _gpuUsageSource: "none"
    property string _nvidiaSmiPath: ""
    property string _intelGpuTopPath: ""
    // Hybrid GPU: path to dGPU power/runtime_status (empty = not hybrid or detection pending)
    property string _dGpuRuntimeStatusPath: ""

    Component.onCompleted: {
        // Lazy: only start monitoring when a panel/widget requests it.
    }

    Process {
        id: detectTempSensors
        property bool startObserved: false
        // Detect CPU and GPU temperature sensors using priority-based selection.
        // On Intel, acpitz/pch report near-constant values; coretemp is the real sensor.
        command: ["/usr/bin/bash", "-c", `
            cpu_path=""
            gpu_path=""
            cpu_priority=0

            for hwmon in /sys/class/hwmon/hwmon*; do
                [ -f "$hwmon/name" ] || continue
                name=$(cat "$hwmon/name" 2>/dev/null)

                temp=""
                # For k10temp/zenpower: prefer Tdie over Tctl (Tctl has artificial offset on some Ryzen)
                if [ "$name" = "k10temp" ] || [ "$name" = "zenpower" ]; then
                    for f in "$hwmon"/temp*_label; do
                        [ -f "$f" ] || continue
                        label=$(cat "$f" 2>/dev/null)
                        if [ "$label" = "Tdie" ]; then
                            temp=$(echo "$f" | sed 's/_label/_input/')
                            break
                        fi
                    done
                fi
                # Fallback: first available temp input
                if [ -z "$temp" ]; then
                    for f in "$hwmon/temp1_input" $hwmon/temp*_input; do
                        [ -f "$f" ] && temp="$f" && break
                    done
                fi
                [ -z "$temp" ] && continue

                # CPU sensors ranked by accuracy
                priority_level=0
                case "$name" in
                    coretemp|k10temp|zenpower|cpu_thermal|fam15h_power|via_cputemp) priority_level=3 ;;
                    thinkpad|dell_smm|hp_wmi|asus_ec|it87|nct6775|w83627ehf|lm75|lm78|lm85) priority_level=2 ;;
                    acpitz|pch_*) priority_level=1 ;;
                esac

                if [ "$priority_level" -gt "$cpu_priority" ]; then
                    cpu_priority=$priority_level
                    cpu_path="$temp"
                fi

                case "$name" in
                    amdgpu|radeon|nvidia|nouveau|i915|xe|panfrost|lima|v3d|vc4)
                        # For amdgpu: prefer 'edge' over 'junction' (junction is hotspot, always higher)
                        if [ -z "$gpu_path" ]; then
                            gpu_edge=""
                            for lf in "$hwmon"/temp*_label; do
                                [ -f "$lf" ] || continue
                                gl=$(cat "$lf" 2>/dev/null)
                                [ "$gl" = "edge" ] && gpu_edge="$lf" && break
                            done
                            if [ -n "$gpu_edge" ]; then
                                gpu_path=$(echo "$gpu_edge" | sed 's/_label/_input/')
                            else
                                gpu_path="$temp"
                            fi
                        fi
                        ;;
                esac
            done

            # Fallback to thermal_zone if hwmon didn't find sensors
            if [ -z "$cpu_path" ] || [ -z "$gpu_path" ]; then
                for tz in /sys/class/thermal/thermal_zone*; do
                    [ -f "$tz/temp" ] || continue
                    type=$(cat "$tz/type" 2>/dev/null | tr '[:upper:]' '[:lower:]')

                    if [ -z "$cpu_path" ]; then
                        case "$type" in
                            *cpu*|x86_pkg_temp|acpitz|*soc*|*core*|*package*|*processor*|int3400*|pch*|b0d4*)
                                cpu_path="$tz/temp" ;;
                        esac
                    fi

                    if [ -z "$gpu_path" ]; then
                        case "$type" in
                            *gpu*|*radeon*|*amdgpu*|*nvidia*)
                                gpu_path="$tz/temp" ;;
                        esac
                    fi
                done
            fi

            [ -n "$cpu_path" ] && echo "cpu:$cpu_path"
            [ -n "$gpu_path" ] && echo "gpu:$gpu_path"
        `]
        stdout: SplitParser {
            onRead: line => {
                const parts = line.split(":");
                if (parts.length === 2) {
                    const [type, path] = parts;
                    if (type === "cpu" && !root._cpuTempPath)
                        root._cpuTempPath = path;
                    else if (type === "gpu" && !root._gpuTempPath)
                        root._gpuTempPath = path;
                }
            }
        }
        onRunningChanged: {
            if (detectTempSensors.running) {
                detectTempSensors.startObserved = false
                return
            }
            if (detectTempSensors.startObserved)
                return

            root._cpuTempPath = ""
            root._gpuTempPath = ""
            root._releaseInitRequest("temperature sensor")
        }
        onStarted: detectTempSensors.startObserved = true
    }

    Process {
        id: detectHybridGpu
        property bool startObserved: false
        // Detect iGPU+dGPU hybrid setups by reading DRM boot_vga flags.
        // boot_vga=1 → primary display GPU (iGPU on laptops), boot_vga=0 → secondary (dGPU).
        // On hybrid systems, outputs the dGPU's runtime_status path so the poll loop can
        // check suspend state before issuing any GPU query, preventing unwanted dGPU wake-ups.
        // On non-hybrid desktops (single GPU or no boot_vga support) outputs "none".
        command: ["/usr/bin/bash", "-c", `
            igpu_found=""
            dgpu_runtime=""

            for card in /sys/class/drm/card*/; do
                name=$(basename "$card")
                echo "$name" | grep -qE '^card[0-9]+$' || continue
                bvga_file="\${card}device/boot_vga"
                [ -f "$bvga_file" ] || continue
                bvga=$(cat "$bvga_file" 2>/dev/null)
                if [ "$bvga" = "1" ]; then
                    igpu_found=1
                elif [ "$bvga" = "0" ]; then
                    runtime="\${card}device/power/runtime_status"
                    [ -f "$runtime" ] && dgpu_runtime="$runtime"
                fi
            done

            if [ -n "$igpu_found" ] && [ -n "$dgpu_runtime" ]; then
                echo "dgpu:$dgpu_runtime"
            else
                echo "none"
            fi
        `]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("dgpu:"))
                    root._dGpuRuntimeStatusPath = line.slice(5);
            }
        }
        onRunningChanged: {
            if (detectHybridGpu.running) {
                detectHybridGpu.startObserved = false
                return
            }
            if (detectHybridGpu.startObserved)
                return

            root._dGpuRuntimeStatusPath = ""
            root._releaseInitRequest("hybrid GPU")
        }
        onStarted: detectHybridGpu.startObserved = true
    }

    Process {
        id: findCpuMaxFreqProc
        property bool startObserved: false
        environment: ({
                LANG: "C",
                LC_ALL: "C"
            })
        command: ["/usr/bin/bash", "-c", "/usr/bin/lscpu | /usr/bin/grep 'CPU max MHz' | /usr/bin/awk '{print $4}'"]
        running: false
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                const mhz = parseFloat(outputCollector.text);
                if (isNaN(mhz) || mhz <= 0) {
                    root.maxAvailableCpuString = "--";
                } else {
                    root.maxAvailableCpuString = (mhz / 1000).toFixed(0) + " GHz";
                }
            }
        }
        onRunningChanged: {
            if (findCpuMaxFreqProc.running) {
                findCpuMaxFreqProc.startObserved = false
                return
            }
            if (findCpuMaxFreqProc.startObserved)
                return

            root.maxAvailableCpuString = "--"
            root._releaseInitRequest("CPU max frequency")
        }
        onStarted: findCpuMaxFreqProc.startObserved = true
    }

    Process {
        id: diskProc
        command: ["/usr/bin/df", "-B1", "/"]
        running: false
        stdout: StdioCollector {
            id: diskCollector
            onStreamFinished: {
                const lines = diskCollector.text.trim().split("\n");
                if (lines.length >= 2) {
                    const parts = lines[1].split(/\s+/);
                    if (parts.length >= 4) {
                        root.diskTotal = parseInt(parts[1]) || 1;
                        root.diskUsed = parseInt(parts[2]) || 0;
                    }
                }
            }
        }
    }
}
