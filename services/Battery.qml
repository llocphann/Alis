pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.modules.common
import qs.modules.common.functions
import qs.services

Singleton {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    function _thresholdPercent(value, fallback: real): real {
        const parsed = Number(value)
        return Number.isFinite(parsed) ? Math.max(0, Math.min(100, parsed)) : fallback
    }

    function _fullThresholdPercent(value, fallback: real): real {
        const parsed = Number(value)
        return Number.isFinite(parsed) ? Math.max(0, Math.min(101, parsed)) : fallback
    }

    property bool available: UPower.displayDevice.isLaptopBattery || root._sysfsPresent
    property var chargeState: UPower.displayDevice.state
    property bool isCharging: chargeState == UPowerDeviceState.Charging
        || (root.sysfsStatus === "Charging" && chargeState != UPowerDeviceState.Discharging)
    readonly property bool isNotCharging: root.sysfsStatus === "Not charging"
        || chargeState == UPowerDeviceState.PendingCharge
    readonly property bool isFullyCharged: chargeState == UPowerDeviceState.FullyCharged
        || root.sysfsStatus === "Full"
        || (root.isNotCharging && Math.round(root.percentage * 100) >= 99)
    property bool isPluggedIn: isCharging
        || isNotCharging
        || isFullyCharged
    // Discharging-based, not !isPluggedIn: FullyCharged / Not charging on AC must not count as "on battery"
    readonly property bool onBattery: available && (
        chargeState == UPowerDeviceState.Discharging
        || chargeState == UPowerDeviceState.PendingDischarge
        || (root.sysfsStatus === "Discharging" && !root.isCharging && !root.isNotCharging)
    )
    property real percentage: {
        const up = Number(UPower.displayDevice?.percentage)
        if (UPower.displayDevice?.isLaptopBattery && Number.isFinite(up) && (up > 0 || root._sysfsCapacity < 0))
            return Math.max(0, Math.min(1, up))
        if (root.energyFullWh > 0 && root.energyNowWh >= 0)
            return Math.max(0, Math.min(1, root.energyNowWh / root.energyFullWh))
        if (root._sysfsCapacity >= 0)
            return Math.max(0, Math.min(1, root._sysfsCapacity / 100))
        return 1
    }
    readonly property bool allowAutomaticSuspend: Config.options?.battery?.automaticSuspend ?? true
    readonly property bool notifyFull: Config.options?.battery?.notifyFull ?? true
    readonly property bool soundEnabled: Config.options?.sounds?.battery ?? true

    readonly property real lowThreshold: root._thresholdPercent(Config.options?.battery?.low, 20)
    readonly property real criticalThreshold: Math.min(root.lowThreshold,
        root._thresholdPercent(Config.options?.battery?.critical, 5))
    readonly property real suspendThreshold: Math.min(root.criticalThreshold,
        root._thresholdPercent(Config.options?.battery?.suspend, 3))
    readonly property real fullThreshold: root._fullThresholdPercent(Config.options?.battery?.full, 101)

    property bool isLow: available && (percentage <= (root.lowThreshold / 100))
    property bool isCritical: available && (percentage <= (root.criticalThreshold / 100))
    property bool isSuspending: available && (percentage <= (root.suspendThreshold / 100))
    property bool isFull: available && (percentage >= (root.fullThreshold / 100))

    property bool isLowAndNotCharging: isLow && onBattery
    property bool isCriticalAndNotCharging: isCritical && onBattery
    property bool isSuspendingAndNotCharging: allowAutomaticSuspend && isSuspending && onBattery
    property bool isFullAndCharging: isFull && isCharging

    // Hardware-accurate live metrics (sysfs uevent primary, UPower fallback)
    readonly property real energyRate: {
        if (root._sysfsPowerNowW >= 0)
            return root._sysfsPowerNowW
        const rate = Number(UPower.displayDevice?.changeRate)
        return Number.isFinite(rate) && rate >= 0 ? rate : 0
    }
    readonly property real timeToEmpty: {
        const up = Number(UPower.displayDevice?.timeToEmpty)
        if (Number.isFinite(up) && up > 0)
            return up
        if (root.onBattery && root.energyNowWh > 0 && root.energyRate >= 0.25)
            return Math.round((root.energyNowWh / root.energyRate) * 3600)
        return 0
    }
    readonly property real timeToFull: {
        const up = Number(UPower.displayDevice?.timeToFull)
        if (Number.isFinite(up) && up > 0)
            return up
        if (root.isCharging && root.energyFullWh > 0 && root.energyNowWh >= 0 && root.energyRate >= 0.25) {
            const capRatio = (root.effectiveEndThreshold > 0 && root.effectiveEndThreshold < 100)
                ? (root.effectiveEndThreshold / 100) : 1.0
            const targetWh = root.energyFullWh * capRatio
            const remainingWh = Math.max(0, targetWh - root.energyNowWh)
            return remainingWh > 0.05 ? Math.round((remainingWh / root.energyRate) * 3600) : 0
        }
        return 0
    }

    // The display device aggregates charge state but does not expose cycle
    // count or full kernel uevent metrics. Use the matching physical UPower
    // battery and its sysfs power_supply directory (falling back to BAT0).
    readonly property var physicalBattery: {
        const devices = UPower.devices?.values ?? []
        for (let i = 0; i < devices.length; ++i) {
            const device = devices[i]
            if (device?.isLaptopBattery && device?.powerSupply && device?.isPresent)
                return device
        }
        return null
    }
    readonly property string sysfsDeviceName: {
        const name = String(root.physicalBattery?.nativePath ?? "")
        if (/^[A-Za-z0-9_-]+$/.test(name))
            return name
        return UPower.displayDevice?.isLaptopBattery ? "BAT0" : ""
    }
    readonly property string sysfsBasePath: root.sysfsDeviceName.length > 0
        ? `/sys/class/power_supply/${root.sysfsDeviceName}` : ""
    readonly property string ueventPath: root.sysfsBasePath.length > 0
        ? `${root.sysfsBasePath}/uevent` : ""
    readonly property string cycleCountPath: root.sysfsBasePath.length > 0
        ? `${root.sysfsBasePath}/cycle_count` : ""
    readonly property string endThresholdPath: root.sysfsBasePath.length > 0
        ? `${root.sysfsBasePath}/charge_control_end_threshold` : ""
    readonly property string startThresholdPath: root.sysfsBasePath.length > 0
        ? `${root.sysfsBasePath}/charge_control_start_threshold` : ""

    // Parsed sysfs hardware state
    property bool _sysfsPresent: false
    property bool _applyingUevent: false
    property string sysfsStatus: ""
    property int _sysfsCapacity: -1
    property string capacityLevel: ""
    property real _sysfsEnergyNowWh: -1
    property real _sysfsEnergyFullWh: -1
    property real _sysfsEnergyDesignWh: -1
    property real _sysfsChargeHealthPct: -1
    property real _sysfsPowerNowW: -1
    property real voltageNowV: -1
    property real voltageDesignV: -1
    property string batteryTechnology: ""
    property string batteryManufacturer: ""
    property string batteryModel: ""
    property string batterySerial: ""
    property int _ueventCycleCount: -1
    property int _fileCycleCount: -1
    property int sysfsChargeStartThreshold: -1
    property int sysfsChargeEndThreshold: -1
    property int liveTelemetryConsumers: 0

    readonly property string batteryIdentityKey: {
        const parts = [
            root.sysfsDeviceName,
            root.batteryManufacturer.trim(),
            root.batteryModel.trim(),
            root.batterySerial.trim()
        ].filter(part => part.length > 0)
        return parts.length > 0 ? parts.join(":") : "BAT0"
    }

    readonly property real energyNowWh: {
        if (root._sysfsEnergyNowWh >= 0)
            return root._sysfsEnergyNowWh
        const up = Number(root.physicalBattery?.energy ?? UPower.displayDevice?.energy)
        return Number.isFinite(up) && up >= 0 ? up : -1
    }
    readonly property real energyFullWh: {
        if (root._sysfsEnergyFullWh > 0)
            return root._sysfsEnergyFullWh
        const up = Number(root.physicalBattery?.energyCapacity ?? UPower.displayDevice?.energyCapacity)
        return Number.isFinite(up) && up > 0 ? up : -1
    }
    readonly property real energyDesignWh: root._sysfsEnergyDesignWh

    readonly property int chargeCycles: root._ueventCycleCount >= 0
        ? root._ueventCycleCount : root._fileCycleCount

    readonly property real healthPercentage: {
        if (root._sysfsChargeHealthPct >= 0)
            return root._sysfsChargeHealthPct
        if (root.energyFullWh > 0 && root.energyDesignWh > 0) {
            const ratio = (root.energyFullWh / root.energyDesignWh) * 100
            if (Number.isFinite(ratio) && ratio >= 0)
                return Math.max(0, Math.min(100, ratio))
        }
        const device = root.physicalBattery
        const health = Number(device?.healthPercentage)
        if (device?.healthSupported && Number.isFinite(health) && health >= 0 && health <= 100)
            return health
        return -1
    }

    readonly property real wearPercentage: root.healthPercentage >= 0
        ? Math.max(0, Math.min(100, 100 - root.healthPercentage)) : -1

    readonly property int effectiveEndThreshold: {
        if (root.sysfsChargeEndThreshold > 0 && root.sysfsChargeEndThreshold <= 100)
            return root.sysfsChargeEndThreshold
        if (root.chargeLimitActive && root.currentChargeLimit > 0 && root.currentChargeLimit <= 100)
            return root.currentChargeLimit
        return -1
    }

    readonly property bool isChargeLimited: root.isNotCharging
        && root.effectiveEndThreshold > 0 && root.effectiveEndThreshold < 100
        && Math.round(root.percentage * 100) >= Math.max(1, root.effectiveEndThreshold - 2)

    readonly property string statusText: {
        if (root.isCharging)
            return Translation.tr("Charging")
        if (root.isChargeLimited)
            return Translation.tr("Charge limited")
        if (root.isFullyCharged)
            return Translation.tr("Fully charged")
        if (root.isNotCharging)
            return Translation.tr("On AC · Idle")
        if (root.onBattery)
            return Translation.tr("Discharging")
        return Translation.tr("Battery")
    }

    function _parseMicro(map, key: string, allowSigned: bool): real {
        const raw = map[key]
        if (raw === undefined || raw === "")
            return -1
        const val = Number(raw)
        if (!Number.isFinite(val))
            return -1
        if (allowSigned)
            return Math.abs(val)
        return val >= 0 ? val : -1
    }

    function parseUeventText(rawText: string): var {
        const map = {}
        const lines = String(rawText ?? "").split(/\r?\n/)
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i].trim()
            if (line.length === 0) continue
            const eq = line.indexOf("=")
            if (eq <= 0) continue
            const key = line.slice(0, eq).trim()
            const val = line.slice(eq + 1).trim()
            map[key] = val
        }

        const vNowUv = root._parseMicro(map, "POWER_SUPPLY_VOLTAGE_NOW", false)
        const vMinUv = root._parseMicro(map, "POWER_SUPPLY_VOLTAGE_MIN_DESIGN", false)
        const vNowV = vNowUv > 0 ? (vNowUv / 1e6) : -1
        const vDesignV = vMinUv > 0 ? (vMinUv / 1e6) : -1
        // Rated/design Wh on charge-reporting batteries stays anchored to nominal design
        // voltage (preventing ±15% swings on plug/unplug), while live power uses real-time V_now.
        const vCapV = vDesignV > 0 ? vDesignV : vNowV
        const vLiveV = vNowV > 0 ? vNowV : vDesignV

        const eNowUwh = root._parseMicro(map, "POWER_SUPPLY_ENERGY_NOW", false)
        const eFullUwh = root._parseMicro(map, "POWER_SUPPLY_ENERGY_FULL", false)
        const eDesignUwh = root._parseMicro(map, "POWER_SUPPLY_ENERGY_FULL_DESIGN", false)

        const cNowUah = root._parseMicro(map, "POWER_SUPPLY_CHARGE_NOW", false)
        const cFullUah = root._parseMicro(map, "POWER_SUPPLY_CHARGE_FULL", false)
        const cDesignUah = root._parseMicro(map, "POWER_SUPPLY_CHARGE_FULL_DESIGN", false)

        // Many Linux battery drivers report signed negative CURRENT_NOW / POWER_NOW while discharging.
        const pNowUw = root._parseMicro(map, "POWER_SUPPLY_POWER_NOW", true)
        const iNowUa = root._parseMicro(map, "POWER_SUPPLY_CURRENT_NOW", true)

        const energyNowWh = eNowUwh >= 0 ? (eNowUwh / 1e6)
            : (cNowUah >= 0 && vCapV > 0 ? (cNowUah / 1e6) * vCapV : -1)
        const energyFullWh = eFullUwh >= 0 ? (eFullUwh / 1e6)
            : (cFullUah >= 0 && vCapV > 0 ? (cFullUah / 1e6) * vCapV : -1)
        const energyDesignWh = eDesignUwh >= 0 ? (eDesignUwh / 1e6)
            : (cDesignUah >= 0 && vCapV > 0 ? (cDesignUah / 1e6) * vCapV : -1)
        const chargeHealthPct = (eFullUwh < 0 && cFullUah > 0 && cDesignUah > 0)
            ? Math.max(0, Math.min(100, (cFullUah / cDesignUah) * 100)) : -1
        const powerNowW = pNowUw >= 0 ? (pNowUw / 1e6)
            : (iNowUa >= 0 && vLiveV > 0 ? (iNowUa / 1e6) * vLiveV : -1)

        const capRaw = map["POWER_SUPPLY_CAPACITY"]
        const capNum = (capRaw !== undefined && /^\d+$/.test(capRaw)) ? Number(capRaw) : -1
        const cycRaw = map["POWER_SUPPLY_CYCLE_COUNT"]
        const cycNum = (cycRaw !== undefined && /^\d+$/.test(cycRaw)) ? Number(cycRaw) : -1
        const presentRaw = map["POWER_SUPPLY_PRESENT"]
        const present = presentRaw !== undefined ? (presentRaw === "1") : Object.keys(map).length > 0

        return {
            present: present,
            status: String(map["POWER_SUPPLY_STATUS"] ?? ""),
            capacity: capNum,
            capacityLevel: String(map["POWER_SUPPLY_CAPACITY_LEVEL"] ?? ""),
            energyNowWh: energyNowWh,
            energyFullWh: energyFullWh,
            energyDesignWh: energyDesignWh,
            chargeHealthPct: chargeHealthPct,
            powerNowW: powerNowW,
            voltageNowV: vNowV,
            voltageDesignV: vDesignV,
            technology: String(map["POWER_SUPPLY_TECHNOLOGY"] ?? ""),
            manufacturer: String(map["POWER_SUPPLY_MANUFACTURER"] ?? ""),
            model: String(map["POWER_SUPPLY_MODEL_NAME"] ?? ""),
            serial: String(map["POWER_SUPPLY_SERIAL_NUMBER"] ?? "").trim(),
            cycleCount: cycNum
        }
    }

    function _applyParsedUevent(parsed): void {
        root._applyingUevent = true
        try {
            root._sysfsPresent = Boolean(parsed.present)
            root.sysfsStatus = parsed.status
            root._sysfsCapacity = parsed.capacity
            root.capacityLevel = parsed.capacityLevel
            root._sysfsEnergyNowWh = parsed.energyNowWh
            root._sysfsEnergyFullWh = parsed.energyFullWh
            root._sysfsEnergyDesignWh = parsed.energyDesignWh
            root._sysfsChargeHealthPct = parsed.chargeHealthPct ?? -1
            root._sysfsPowerNowW = parsed.powerNowW
            root.voltageNowV = parsed.voltageNowV
            root.voltageDesignV = parsed.voltageDesignV
            root.batteryTechnology = parsed.technology
            root.batteryManufacturer = parsed.manufacturer
            root.batteryModel = parsed.model
            root.batterySerial = String(parsed.serial ?? "")
            root._ueventCycleCount = parsed.cycleCount
        } finally {
            root._applyingUevent = false
        }
        root._syncActiveHistoryView()
        root._maybeRecordCurrentHealth()
    }

    function refreshTelemetry(): void {
        if (root.ueventPath.length > 0)
            ueventFile.reload()
        if (root.endThresholdPath.length > 0)
            endThresholdFile.reload()
        if (root.startThresholdPath.length > 0)
            startThresholdFile.reload()
        if (root._ueventCycleCount < 0 && root.cycleCountPath.length > 0)
            cycleCountFile.reload()
    }

    onSysfsBasePathChanged: {
        root._sysfsPresent = false
        root.sysfsStatus = ""
        root._sysfsCapacity = -1
        root.capacityLevel = ""
        root._sysfsEnergyNowWh = -1
        root._sysfsEnergyFullWh = -1
        root._sysfsEnergyDesignWh = -1
        root._sysfsChargeHealthPct = -1
        root._sysfsPowerNowW = -1
        root.voltageNowV = -1
        root.voltageDesignV = -1
        root.batteryTechnology = ""
        root.batteryManufacturer = ""
        root.batteryModel = ""
        root.batterySerial = ""
        root._ueventCycleCount = -1
        root._fileCycleCount = -1
        root.sysfsChargeStartThreshold = -1
        root.sysfsChargeEndThreshold = -1
    }

    FileView {
        id: ueventFile
        path: root.ueventPath
        printErrors: false
        onLoaded: root._applyParsedUevent(root.parseUeventText(ueventFile.text()))
        onLoadFailed: {
            root._sysfsPresent = false
            root._sysfsPowerNowW = -1
        }
    }

    FileView {
        id: cycleCountFile
        path: root.cycleCountPath
        printErrors: false
        onLoaded: {
            const raw = cycleCountFile.text().trim()
            root._fileCycleCount = /^\d+$/.test(raw) ? Number(raw) : -1
        }
        onLoadFailed: root._fileCycleCount = -1
    }

    FileView {
        id: endThresholdFile
        path: root.endThresholdPath
        printErrors: false
        onLoaded: {
            const raw = endThresholdFile.text().trim()
            root.sysfsChargeEndThreshold = /^\d+$/.test(raw) ? Number(raw) : -1
        }
        onLoadFailed: root.sysfsChargeEndThreshold = -1
    }

    FileView {
        id: startThresholdFile
        path: root.startThresholdPath
        printErrors: false
        onLoaded: {
            const raw = startThresholdFile.text().trim()
            root.sysfsChargeStartThreshold = /^\d+$/.test(raw) ? Number(raw) : -1
        }
        onLoadFailed: root.sysfsChargeStartThreshold = -1
    }

    Timer {
        id: telemetryPollTimer
        interval: root.liveTelemetryConsumers > 0
            ? 2500
            : (root.onBattery || root.isCharging ? 30000 : 120000)
        running: root.available && root.ueventPath.length > 0
        repeat: true
        onTriggered: root.refreshTelemetry()
    }

    // ─── Charge limit ───
    readonly property bool chargeLimitEnabled: {
        void Config.revision
        return Config.options?.battery?.chargeLimit?.enable ?? false
    }
    readonly property int chargeLimitThreshold: {
        void Config.revision
        return Config.options?.battery?.chargeLimit?.threshold ?? 80
    }
    readonly property bool chargeLimitAvailable: TlpService.available
    readonly property bool chargeLimitSupported: TlpService.supported
    readonly property bool chargeLimitAdjustable: TlpService.adjustable
    readonly property bool chargeLimitStateKnown: TlpService.stateKnown
    readonly property bool chargeLimitActive: TlpService.active
    readonly property bool chargeLimitManaged: TlpService.managed
    readonly property int currentChargeLimit: TlpService.currentLimit
    readonly property int effectiveChargeLimitThreshold: TlpService.effectiveRequestedLimit
    readonly property string chargeLimitKind: TlpService.limitKind
    readonly property bool chargeLimitContinuous: TlpService.continuous
    readonly property bool chargeLimitDiscrete: TlpService.discrete
    readonly property int chargeLimitMinimum: TlpService.minimumLimit
    readonly property int chargeLimitMaximum: TlpService.maximumLimit
    readonly property int chargeLimitStepSize: TlpService.limitStepSize
    readonly property var chargeLimitAllowedValues: TlpService.allowedLimits
    readonly property string chargeLimitStatusReason: TlpService.statusReason
    readonly property bool chargeLimitBusy: TlpService.busy
    readonly property int chargeLimitFixedValue: TlpService.fixedLimit
    readonly property bool chargeLimitInteractive: root.chargeLimitSupported || root.chargeLimitManaged

    function chargeLimitPresetsFor(supported: bool, managed: bool, kind: string, minVal: int, maxVal: int, stepSize: int, allowedValues, fixedVal: int): var {
        if (!supported && !managed)
            return []
        const rawKind = String(kind ?? "none")
        const maxBound = Math.min(100, Math.max(1, Math.round(Number(maxVal) || 100)))
        if (rawKind === "discrete") {
            const seen = ({})
            const list = []
            const src = Array.isArray(allowedValues) ? allowedValues : []
            for (let i = 0; i < src.length; ++i) {
                const n = Math.round(Number(src[i]))
                if (Number.isFinite(n) && n >= 1 && n <= 100 && !seen[n]) {
                    seen[n] = true
                    list.push(n)
                }
            }
            if (maxBound >= 100 && !seen[100])
                list.push(100)
            list.sort((a, b) => a - b)
            return list
        }
        if (rawKind === "fixed" || rawKind === "mode") {
            const fixed = (fixedVal >= 20 && fixedVal < 100) ? Math.round(fixedVal) : 80
            return [fixed, 100]
        }
        const lo = Math.max(1, Math.min(100, Math.round(Number(minVal) || 1)))
        const hi = Math.min(100, Math.max(lo, maxBound))
        const step = Math.max(1, Math.round(Number(stepSize) || 1))
        const seeds = [50, 60, 80, 90, 100]
        const seen = ({})
        const out = []
        for (let i = 0; i < seeds.length; ++i) {
            const clamped = Math.max(lo, Math.min(hi, seeds[i]))
            const snapped = Math.max(lo, Math.min(hi, lo + Math.round((clamped - lo) / step) * step))
            if (!seen[snapped]) {
                seen[snapped] = true
                out.push(snapped)
            }
        }
        if (hi >= 100 && !seen[100])
            out.push(100)
        out.sort((a, b) => a - b)
        return out
    }

    function chargeLimitPresets(): var {
        return root.chargeLimitPresetsFor(
            root.chargeLimitSupported,
            root.chargeLimitManaged,
            root.chargeLimitKind,
            root.chargeLimitMinimum,
            root.chargeLimitMaximum,
            root.chargeLimitStepSize,
            root.chargeLimitAllowedValues,
            root.chargeLimitFixedValue
        )
    }

    function normalizeChargeLimitFor(value: real, kind: string, minVal: int, maxVal: int, stepSize: int, presets): int {
        const raw = Number(value)
        const target = Number.isFinite(raw) ? raw : 80
        const rawKind = String(kind ?? "none")
        if (rawKind === "discrete" || rawKind === "fixed" || rawKind === "mode") {
            const list = Array.isArray(presets) ? presets : []
            if (list.length === 0)
                return 80
            let best = Number(list[0])
            let bestDist = Math.abs(best - target)
            for (let i = 1; i < list.length; ++i) {
                const candidate = Number(list[i])
                const d = Math.abs(candidate - target)
                if (d < bestDist) {
                    best = candidate
                    bestDist = d
                }
            }
            return Math.max(1, Math.min(100, Math.round(best)))
        }
        const lo = Math.max(1, Math.min(100, Math.round(Number(minVal) || 1)))
        const hi = Math.min(100, Math.max(lo, Math.round(Number(maxVal) || 100)))
        const step = Math.max(1, Math.round(Number(stepSize) || 1))
        const clamped = Math.max(lo, Math.min(hi, target))
        const snapped = Math.max(lo, Math.min(hi, lo + Math.round((clamped - lo) / step) * step))
        return Math.max(1, Math.min(100, snapped))
    }

    function normalizeChargeLimit(value: real): int {
        return root.normalizeChargeLimitFor(
            value,
            root.chargeLimitKind,
            root.chargeLimitMinimum,
            root.chargeLimitMaximum,
            root.chargeLimitStepSize,
            root.chargeLimitPresets()
        )
    }

    function setChargeLimitFromPopup(targetPercent: int): void {
        if (!root.chargeLimitInteractive || root.chargeLimitBusy)
            return
        const clamped = root.normalizeChargeLimit(targetPercent)
        if (clamped >= 100) {
            if (root.chargeLimitEnabled || root.chargeLimitManaged)
                Config.setNestedValue("battery.chargeLimit.enable", false)
            return
        }
        if (root.chargeLimitKind === "fixed" || root.chargeLimitKind === "mode") {
            if (!root.chargeLimitEnabled)
                Config.setNestedValue("battery.chargeLimit.enable", true)
            return
        }
        if (!root.chargeLimitEnabled || root.chargeLimitThreshold !== clamped) {
            Config.setNestedValues({
                "battery.chargeLimit.enable": true,
                "battery.chargeLimit.threshold": clamped
            })
        }
    }

    Timer {
        id: postTlpRefreshTimer
        interval: 350
        repeat: false
        onTriggered: root.refreshTelemetry()
    }

    Connections {
        target: TlpService
        function onBusyChanged(): void {
            if (!TlpService.busy) {
                root.refreshTelemetry()
                postTlpRefreshTimer.restart()
            }
        }
        function onCurrentLimitChanged(): void {
            root.refreshTelemetry()
        }
    }

    // ─── Persistent Health History ───
    property string historyFilePath: Directories.batteryHistoryPath
    property var _historyDb: ({ version: 1, batteries: ({}) })
    property bool _historyLoaded: false
    property bool _historyCorrupt: false
    property bool _historyWriteInFlight: false
    property bool _historyPendingWrite: false
    property bool _historyDirReady: false
    property bool _historyDirPending: false
    property int _historyRevision: 0
    property var healthHistory: []

    readonly property var healthHistorySummary: {
        void root._historyRevision
        return root.computeHealthHistorySummary(root.healthHistory, root.healthPercentage, root.chargeCycles)
    }

    function sanitizeHistorySamples(list): var {
        if (!Array.isArray(list))
            return []
        const byTime = ({})
        for (let i = 0; i < list.length; ++i) {
            const item = list[i]
            if (!item || typeof item !== "object")
                continue
            const t = Math.round(Number(item.t))
            const h = Number(item.h)
            if (!Number.isFinite(t) || t <= 0 || !Number.isFinite(h) || h < 1 || h > 100)
                continue
            const rawC = item.c === undefined || item.c === null ? -1 : Number(item.c)
            const c = (Number.isFinite(rawC) && rawC >= 0) ? Math.round(rawC) : -1
            const rawF = item.f === undefined || item.f === null ? -1 : Number(item.f)
            const f = (Number.isFinite(rawF) && rawF >= 0) ? (Math.round(rawF * 100) / 100) : -1
            byTime[String(t)] = {
                t: t,
                h: Math.round(h * 100) / 100,
                c: c,
                f: f
            }
        }
        const keys = Object.keys(byTime)
        const out = []
        for (let i = 0; i < keys.length; ++i)
            out.push(byTime[keys[i]])
        out.sort((a, b) => a.t - b.t)
        return out
    }

    function parseHistoryDocument(rawText: string, fallbackKey: string): var {
        const trimmed = String(rawText ?? "").trim()
        if (trimmed.length === 0)
            return { ok: true, db: { version: 1, batteries: ({}) } }
        let parsed
        try {
            parsed = JSON.parse(trimmed)
        } catch (error) {
            return { ok: false, db: null }
        }
        if (Array.isArray(parsed)) {
            const key = String(fallbackKey ?? "").trim() || "BAT0"
            const db = { version: 1, batteries: ({}) }
            db.batteries[key] = {
                identity: key,
                samples: root.sanitizeHistorySamples(parsed)
            }
            return { ok: true, db: db }
        }
        if (!parsed || typeof parsed !== "object")
            return { ok: false, db: null }
        if (Array.isArray(parsed.samples) && (!parsed.batteries || typeof parsed.batteries !== "object")) {
            const key = String(parsed.identity ?? fallbackKey ?? "").trim() || "BAT0"
            const db = {}
            const topKeys = Object.keys(parsed)
            for (let i = 0; i < topKeys.length; ++i) {
                const k = topKeys[i]
                if (k !== "samples" && k !== "version")
                    db[k] = parsed[k]
            }
            db.version = 1
            db.batteries = ({})
            db.batteries[key] = {
                identity: key,
                samples: root.sanitizeHistorySamples(parsed.samples)
            }
            return { ok: true, db: db }
        }
        const db = {}
        const topKeys = Object.keys(parsed)
        for (let i = 0; i < topKeys.length; ++i) {
            const k = topKeys[i]
            if (k !== "batteries")
                db[k] = parsed[k]
        }
        db.version = Number(parsed.version) > 0 ? Math.round(Number(parsed.version)) : 1
        db.batteries = ({})
        const rawBatteries = parsed.batteries
        if (rawBatteries && typeof rawBatteries === "object" && !Array.isArray(rawBatteries)) {
            const batKeys = Object.keys(rawBatteries)
            for (let i = 0; i < batKeys.length; ++i) {
                const bk = batKeys[i]
                const rawEntry = rawBatteries[bk]
                if (!rawEntry || typeof rawEntry !== "object" || Array.isArray(rawEntry))
                    continue
                const entry = ({})
                const entryKeys = Object.keys(rawEntry)
                for (let j = 0; j < entryKeys.length; ++j)
                    entry[entryKeys[j]] = rawEntry[entryKeys[j]]
                entry.samples = root.sanitizeHistorySamples(rawEntry.samples)
                db.batteries[bk] = entry
            }
        }
        return { ok: true, db: db }
    }

    function shouldRecordHealthSample(samples, nowSec: real, healthPct: real, cycles: int): bool {
        if (!Number.isFinite(healthPct) || healthPct < 1 || healthPct > 100)
            return false
        if (!Number.isFinite(nowSec) || nowSec <= 0)
            return false
        if (!Array.isArray(samples) || samples.length === 0)
            return true
        const last = samples[samples.length - 1]
        const dt = nowSec - Number(last?.t ?? 0)
        if (dt < 0)
            return false
        if (dt >= 86400)
            return true
        const lastCycles = Number(last?.c ?? -1)
        const cycleAdvanced = cycles >= 0 && lastCycles >= 0 && cycles > lastCycles
        const healthDelta = Math.abs(healthPct - Number(last?.h ?? healthPct))
        if (dt >= 21600 && (healthDelta >= 0.05 || cycleAdvanced))
            return true
        if (dt >= 1800 && (healthDelta >= 0.25 || cycleAdvanced))
            return true
        return false
    }

    function compactHealthSamples(samples, maxCount: int): var {
        if (!Array.isArray(samples))
            return []
        const cap = Math.max(4, Math.round(Number(maxCount) || 730))
        if (samples.length <= cap)
            return samples
        const tailCount = Math.min(samples.length - 1, Math.max(1, Math.floor(cap * 0.6)))
        const midTarget = Math.max(0, cap - 1 - tailCount)
        const midStart = 1
        const midEnd = samples.length - tailCount
        const midAvailable = Math.max(0, midEnd - midStart)
        const out = [samples[0]]
        if (midTarget > 0 && midAvailable > 0) {
            const count = Math.min(midTarget, midAvailable)
            for (let i = 0; i < count; ++i) {
                const idx = count === 1
                    ? midStart
                    : (midStart + Math.floor((i * (midAvailable - 1)) / Math.max(1, count - 1)))
                out.push(samples[idx])
            }
        }
        for (let i = midEnd; i < samples.length; ++i)
            out.push(samples[i])
        return out
    }

    function formatHistorySpan(spanSeconds: real): string {
        const s = Math.max(0, Number(spanSeconds) || 0)
        if (s < 3600)
            return Translation.tr("today")
        if (s < 48 * 3600) {
            const h = Math.max(1, Math.round(s / 3600))
            return h === 1 ? Translation.tr("1 hour") : Translation.tr("%1 hours").arg(h)
        }
        if (s < 45 * 86400) {
            const d = Math.max(1, Math.round(s / 86400))
            return d === 1 ? Translation.tr("1 day") : Translation.tr("%1 days").arg(d)
        }
        if (s < 365 * 86400) {
            const m = Math.max(1, Math.round(s / (30.4375 * 86400)))
            return m === 1 ? Translation.tr("1 month") : Translation.tr("%1 months").arg(m)
        }
        const y = s / (365.25 * 86400)
        return y < 1.05 ? Translation.tr("1 year") : Translation.tr("%1 years").arg(y.toFixed(1))
    }

    function computeHealthHistorySummary(samples, liveHealth: real, liveCycles: int): var {
        const list = Array.isArray(samples) ? samples : []
        if (list.length >= 2) {
            const first = list[0]
            const latest = list[list.length - 1]
            const deltaHealth = Number(latest.h) - Number(first.h)
            const roundedDelta = Math.round(deltaHealth * 10) / 10
            const deltaText = roundedDelta > 0
                ? ("+" + roundedDelta.toFixed(1) + "%")
                : (roundedDelta < 0 ? (roundedDelta.toFixed(1) + "%") : "0.0%")
            const spanSeconds = Math.max(0, Number(latest.t) - Number(first.t))
            const spanLabel = root.formatHistorySpan(spanSeconds)
            const spanPhrase = spanSeconds < 3600 ? spanLabel : Translation.tr("over %1").arg(spanLabel)
            const firstCycles = Number(first.c ?? -1)
            const latestCycles = Number(latest.c ?? -1)
            const deltaCycles = (firstCycles >= 0 && latestCycles >= 0) ? Math.max(0, latestCycles - firstCycles) : -1
            const cyclePart = deltaCycles >= 0
                ? (" · +" + deltaCycles + " " + (deltaCycles === 1 ? Translation.tr("cycle") : Translation.tr("cycles")))
                : ""
            const summaryText = `${deltaText} ${Translation.tr("health")} ${spanPhrase}${cyclePart}`
            return {
                hasTrend: true,
                summaryText: summaryText,
                deltaHealth: roundedDelta,
                spanSeconds: spanSeconds,
                deltaCycles: deltaCycles,
                latestHealth: Number(latest.h),
                latestCycles: latestCycles
            }
        }
        if (list.length === 1) {
            const only = list[0]
            const cyc = Number(only.c ?? -1)
            const h = Number(only.h)
            const summaryText = cyc >= 0
                ? Translation.tr("Baseline %1% health · %2 cycles").arg(h.toFixed(1)).arg(cyc)
                : Translation.tr("Baseline %1% health").arg(h.toFixed(1))
            return {
                hasTrend: false,
                summaryText: summaryText,
                deltaHealth: 0,
                spanSeconds: 0,
                deltaCycles: 0,
                latestHealth: h,
                latestCycles: cyc
            }
        }
        const liveH = Number(liveHealth)
        const liveC = Number(liveCycles)
        const summaryText = Number.isFinite(liveH) && liveH >= 0
            ? (Number.isFinite(liveC) && liveC >= 0
                ? Translation.tr("Baseline %1% health · %2 cycles").arg(liveH.toFixed(1)).arg(Math.round(liveC))
                : Translation.tr("Baseline %1% health").arg(liveH.toFixed(1)))
            : ""
        return {
            hasTrend: false,
            summaryText: summaryText,
            deltaHealth: 0,
            spanSeconds: 0,
            deltaCycles: 0,
            latestHealth: Number.isFinite(liveH) ? liveH : -1,
            latestCycles: Number.isFinite(liveC) ? Math.round(liveC) : -1
        }
    }

    function _syncActiveHistoryView(): void {
        const db = root._historyDb
        const key = root.batteryIdentityKey
        const entry = (db && db.batteries && typeof db.batteries === "object") ? db.batteries[key] : null
        root.healthHistory = (entry && Array.isArray(entry.samples)) ? entry.samples : []
        root._historyRevision = root._historyRevision + 1
    }

    function _scheduleHistorySave(): void {
        if (!root._historyLoaded || root._historyCorrupt)
            return
        root._historyPendingWrite = true
        historySaveTimer.restart()
    }

    function _flushHistoryWrite(): void {
        if (!root._historyLoaded || root._historyCorrupt || root._historyWriteInFlight || root._historyDirPending)
            return
        const p = String(root.historyFilePath ?? "").trim()
        if (p.length === 0)
            return
        if (!root._historyDirReady) {
            const slash = p.lastIndexOf("/")
            const dir = slash > 0 ? p.slice(0, slash) : ""
            if (dir.length > 0) {
                root._historyDirPending = true
                ensureHistoryDirProcess.command = ["mkdir", "-p", dir]
                ensureHistoryDirProcess.running = true
                return
            }
            root._historyDirReady = true
        }
        root._historyPendingWrite = false
        root._historyWriteInFlight = true
        batteryHistoryFile.setText(JSON.stringify(root._historyDb, null, 2) + "\n")
    }

    function _maybeRecordCurrentHealth(): void {
        if (!root._historyLoaded || root._historyCorrupt || !root._sysfsPresent)
            return
        const h = Number(root.healthPercentage)
        if (!Number.isFinite(h) || h < 1 || h > 100)
            return
        const nowSec = Math.floor(Date.now() / 1000)
        const cyc = root.chargeCycles >= 0 ? Math.round(root.chargeCycles) : -1
        const key = root.batteryIdentityKey
        const db = (root._historyDb && typeof root._historyDb === "object")
            ? root._historyDb : ({ version: 1, batteries: ({}) })
        if (!db.batteries || typeof db.batteries !== "object")
            db.batteries = ({})
        const prevEntry = (db.batteries[key] && typeof db.batteries[key] === "object")
            ? db.batteries[key] : ({})
        const existing = Array.isArray(prevEntry.samples) ? prevEntry.samples : []
        if (!root.shouldRecordHealthSample(existing, nowSec, h, cyc))
            return
        const fullWh = root.energyFullWh > 0 ? Math.round(root.energyFullWh * 100) / 100 : -1
        const nextSample = {
            t: nowSec,
            h: Math.round(h * 100) / 100,
            c: cyc,
            f: fullWh
        }
        const updated = root.compactHealthSamples(existing.concat([nextSample]), 730)
        const nextEntry = ({})
        const prevKeys = Object.keys(prevEntry)
        for (let i = 0; i < prevKeys.length; ++i)
            nextEntry[prevKeys[i]] = prevEntry[prevKeys[i]]
        nextEntry.identity = key
        nextEntry.designWh = root.energyDesignWh > 0
            ? Math.round(root.energyDesignWh * 100) / 100
            : (Number(prevEntry.designWh) > 0 ? Number(prevEntry.designWh) : -1)
        nextEntry.samples = updated
        db.batteries[key] = nextEntry
        root._historyDb = db
        root._syncActiveHistoryView()
        root._scheduleHistorySave()
    }

    onBatteryIdentityKeyChanged: {
        if (root._applyingUevent)
            return
        root._syncActiveHistoryView()
        root._maybeRecordCurrentHealth()
    }

    onHistoryFilePathChanged: {
        historySaveTimer.stop()
        root._historyLoaded = false
        root._historyCorrupt = false
        root._historyWriteInFlight = false
        root._historyPendingWrite = false
        root._historyDirReady = false
        root._historyDirPending = false
        root._historyDb = ({ version: 1, batteries: ({}) })
        root._syncActiveHistoryView()
        if (String(root.historyFilePath ?? "").trim().length > 0)
            batteryHistoryFile.reload()
    }

    Component.onCompleted: {
        if (String(root.historyFilePath ?? "").trim().length > 0)
            batteryHistoryFile.reload()
    }

    Timer {
        id: historySaveTimer
        interval: 800
        repeat: false
        onTriggered: root._flushHistoryWrite()
    }

    Process {
        id: ensureHistoryDirProcess
        onExited: (exitCode, exitStatus) => {
            root._historyDirPending = false
            if (exitCode === 0) {
                root._historyDirReady = true
                if (root._historyPendingWrite)
                    root._flushHistoryWrite()
            } else {
                root._historyPendingWrite = false
            }
        }
    }

    FileView {
        id: batteryHistoryFile
        path: root.historyFilePath
        printErrors: false
        atomicWrites: true

        onLoaded: {
            if (root._historyWriteInFlight)
                return
            const parsed = root.parseHistoryDocument(batteryHistoryFile.text(), root.batteryIdentityKey)
            if (!parsed.ok) {
                if (!root._historyCorrupt)
                    console.warn("[Battery] Ignoring corrupt battery health history JSON at", root.historyFilePath)
                root._historyCorrupt = true
                root._historyLoaded = true
                return
            }
            root._historyCorrupt = false
            root._historyDb = parsed.db
            root._historyLoaded = true
            root._syncActiveHistoryView()
            root._maybeRecordCurrentHealth()
        }

        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root._historyCorrupt = false
                root._historyDb = ({ version: 1, batteries: ({}) })
                root._historyLoaded = true
                root._syncActiveHistoryView()
                root._maybeRecordCurrentHealth()
            }
        }

        onSaved: {
            root._historyWriteInFlight = false
            if (root._historyPendingWrite)
                historySaveTimer.restart()
        }

        onSaveFailed: error => {
            root._historyWriteInFlight = false
            console.warn("[Battery] Failed to save battery health history:", error)
        }
    }

    // ─── Battery warnings ───
    onIsLowAndNotChargingChanged: {
        if (!root.available || !isLowAndNotCharging) return;
        Notifications.sendInternal({
            summary: Translation.tr("Low battery"),
            body: Translation.tr("Consider plugging in your device"),
            urgency: "critical",
            appName: "Shell",
            transient: true,
        })

        if (root.soundEnabled) Audio.playEvent("batteryLow");
    }

    onIsCriticalAndNotChargingChanged: {
        if (!root.available || !isCriticalAndNotCharging) return;
        const message = root.allowAutomaticSuspend
            ? Translation.tr("Please charge!\nAutomatic suspend triggers at %1%").arg(root.suspendThreshold)
            : Translation.tr("Consider plugging in your device")
        Notifications.sendInternal({
            summary: Translation.tr("Critically low battery"),
            body: message,
            urgency: "critical",
            appName: "Shell",
            transient: true,
        });

        if (root.soundEnabled) Audio.playEvent("batteryCritical");
    }

    onIsSuspendingAndNotChargingChanged: {
        if (root.available && isSuspendingAndNotCharging) {
            Session.suspend()
        }
    }

    onIsFullAndChargingChanged: {
        if (!root.available || !root.notifyFull || !isFullAndCharging) return;
        Notifications.sendInternal({
            summary: Translation.tr("Battery full"),
            body: Translation.tr("Please unplug the charger"),
            appName: "Shell",
            transient: true,
        });

        if (root.soundEnabled) Audio.playEvent("batteryFull");
    }

    onIsPluggedInChanged: {
        if (!root.available || !root.soundEnabled) return;
        if (isPluggedIn) {
            Audio.playEvent("powerPlug")
        } else {
            Audio.playEvent("powerUnplug")
        }
    }
}
