pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.modules.common
import "PowerRenderQuality.js" as Policy

Singleton {
    readonly property string powerProfile: PowerProfiles.profile === PowerProfile.PowerSaver
        ? "power-saver" : PowerProfiles.profile === PowerProfile.Performance
            ? "performance" : "balanced"
    readonly property string abyssQuality: Policy.abyss(Config.options?.abyss?.quality,
        Config.options?.abyss?.autoQuality ?? false,powerProfile)
    readonly property string aquaQuality: Policy.aqua(Config.options?.abyss?.companion?.renderQuality,
        Config.options?.abyss?.companion?.autoQuality ?? false,powerProfile,abyssQuality)
    readonly property string aquaQualityLabel:
        Policy.aquaLabel(aquaQuality)
}
