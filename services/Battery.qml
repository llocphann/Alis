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
    property int _ueventCycleCount: -1
    property int _fileCycleCount: -1
    property int sysfsChargeStartThreshold: -1
    property int sysfsChargeEndThreshold: -1
    property int liveTelemetryConsumers: 0

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
            cycleCount: cycNum
        }
    }

    function _applyParsedUevent(parsed): void {
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
        root._ueventCycleCount = parsed.cycleCount
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
