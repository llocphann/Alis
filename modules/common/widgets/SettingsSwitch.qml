import qs.modules.common
import qs.modules.common.widgets

ConfigSwitch {
    colBackground: "transparent"
    colBackgroundHover: SettingsMaterialPreset.waffle ? SettingsMaterialPreset.navHoverColor : SettingsMaterialPreset.controlSurfaceHover
    colRipple: SettingsMaterialPreset.controlSurfaceActive
}
