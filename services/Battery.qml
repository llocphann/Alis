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

    property bool available: UPower.displayDevice.isLaptopBattery
    property var chargeState: UPower.displayDevice.state
    property bool isCharging: chargeState == UPowerDeviceState.Charging
    property bool isPluggedIn: isCharging
        || chargeState == UPowerDeviceState.PendingCharge
        || chargeState == UPowerDeviceState.FullyCharged
    // Discharging-based, not !isPluggedIn: FullyCharged on AC must not count as "on battery"
    readonly property bool onBattery: available && (chargeState == UPowerDeviceState.Discharging || chargeState == UPowerDeviceState.PendingDischarge)
    property real percentage: UPower.displayDevice?.percentage ?? 1
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

    property real energyRate: UPower.displayDevice.changeRate
    property real timeToEmpty: UPower.displayDevice.timeToEmpty
    property real timeToFull: UPower.displayDevice.timeToFull

    // The display device aggregates charge state but does not expose cycle
    // count. Use the matching physical UPower battery for health and its
    // native sysfs name for the kernel's cycle_count, when available.
    readonly property var physicalBattery: {
        const devices = UPower.devices?.values ?? []
        for (let i = 0; i < devices.length; ++i) {
            const device = devices[i]
            if (device?.isLaptopBattery && device?.powerSupply && device?.isPresent)
                return device
        }
        return null
    }
    readonly property string cycleCountPath: {
        const name = String(root.physicalBattery?.nativePath ?? "")
        return /^[A-Za-z0-9_-]+$/.test(name)
            ? `/sys/class/power_supply/${name}/cycle_count` : ""
    }
    property int chargeCycles: -1
    onCycleCountPathChanged: root.chargeCycles = -1
    readonly property real wearPercentage: {
        const device = root.physicalBattery
        const health = Number(device?.healthPercentage)
        return device?.healthSupported && Number.isFinite(health)
            && health >= 0 && health <= 100
            ? Math.max(0, 100 - health) : -1
    }

    FileView {
        id: cycleCountFile
        path: root.cycleCountPath
        onLoaded: {
            const raw = cycleCountFile.text().trim()
            root.chargeCycles = /^\d+$/.test(raw) ? Number(raw) : -1
        }
        onLoadFailed: root.chargeCycles = -1
    }

    Timer {
        interval: 15 * 60 * 1000
        running: root.available && root.cycleCountPath.length > 0
            && root.chargeCycles >= 0
        repeat: true
        onTriggered: cycleCountFile.reload()
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
