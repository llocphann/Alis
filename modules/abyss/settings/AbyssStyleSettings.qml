pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../common/widgets/SettingsLayoutPolicy.js" as LayoutPolicy
import qs.modules.abyss.looks
import "../../common/PanelFamilyPolicy.js" as FamilyPolicy
import "../looks/AbyssWave.js" as Wave

ColumnLayout {
    id: root
    Layout.fillWidth: true
    Layout.fillHeight: false
    spacing: SettingsMaterialPreset.pageSpacing

    property string activeSection: "surface"
    property var sections: ["surface", "interaction", "performance", "spectrum", "waves"]
    property real modulesCardMinHeight: 0
    readonly property real modulesCardImplicitHeight: modulesCard.implicitHeight
    property real popupsCardMinHeight: 0
    readonly property real popupsCardImplicitHeight: popupsCard.naturalCardImplicitHeight + root.spacing + popupSurfacesCard.naturalCardImplicitHeight
    property real hostPageHeight: 0
    property int hostSubTabCount: 0
    property real hostTargetBentoHeight: 0

    readonly property bool unifiedSurfaceWaves: root.sections.includes("surface")
        && root.sections.includes("waves")
    readonly property bool twoColumnSurfacePerformance: root.sections.length === 2
        && root.sections.includes("surface") && root.sections.includes("performance")
    readonly property bool twoColumnWavesSpectrum: root.sections.length === 3
        && root.sections.includes("waves") && root.sections.includes("spectrum")
        && root.sections.includes("interaction")
    readonly property var waveValues: Wave.parameters(Config.options?.abyss?.waves)
    // Each column needs room for a label, a usable track, and a numeric value.
    readonly property real pairedSliderWidth: 340 * Appearance.fontSizeScale

    function spectrumChange(key, value): void {
        const options = Config.options?.abyss?.spectrum
        const updates = {
            "abyss.spectrum.configured": true,
            "abyss.spectrum.enabled": options?.configured ? options.enabled : Config.options?.bar?.visualizer?.enable ?? false,
            "abyss.spectrum.multiMonitorMode": options?.configured ? options.multiMonitorMode : Config.options?.bar?.visualizer?.multiMonitorMode ?? "primary"
        }
        updates["abyss.spectrum." + key] = value
        Config.setNestedValues(updates)
    }

    function waveChange(key, value): void {
        const updates = { "abyss.waves.preset": "custom" }
        Object.keys(Wave.presets.balanced).forEach(k => updates["abyss.waves." + k] = waveValues[k])
        updates["abyss.waves." + key] = value
        Config.setNestedValues(updates)
    }

    component CompactSurfaceRow: SettingsMetricControl {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.minimumWidth: 0
    }

    component CompactSurfacePercent: CompactSurfaceRow {
        id: control
        required property string configKey
        property real fallback: 0
        property real minimum: 0
        property real maximum: 1
        property string metricUnit: maximum > 4 ? "px" : "%"
        from: minimum
        to: maximum
        stepSize: metricUnit === "%" ? .01 : 1
        currentValue: Config.getNestedValue(configKey, fallback)
        valueText: Math.round(currentValue * (metricUnit === "%" ? 100 : 1))
            + (metricUnit === "%" ? "%" : " px")
        onMoved: value => Config.setNestedValue(configKey, value)
    }

    component WaveControl: CompactSurfaceRow {
        id: control
        required property string parameter
        from: 0
        to: parameter === "amplitude" ? 400 : 100
        stepSize: 1
        visible: (Config.options?.abyss?.waves?.preset ?? "balanced") === "custom"
        currentValue: root.waveValues[parameter] * 100
        valueText: parameter === "amplitude"
            ? Math.round(4 + 32 * currentValue / 100) + " px"
            : Math.round(currentValue) + "%"
        onMoved: value => root.waveChange(parameter, value / 100)
    }

    SettingsTaskNavigator {
        icon: "water"
        title: "Abyss"
        description: "Screen Edge appearance and behavior."
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        visible: options.length > 2 && !root.twoColumnWavesSpectrum && !root.unifiedSurfaceWaves
        showTabBar: visible
        activeNavigator: visible
        showIntro: false
        options: [
            { displayName: "Surface", value: "surface", icon: "opacity" },
            { displayName: "Waves", value: "waves", icon: "waves" },
            { displayName: "Spectrum", value: "spectrum", icon: "graphic_eq" },
            { displayName: "Modules", value: "modules", icon: "widgets" },
            { displayName: "Module behavior", value: "bar", icon: "tune" },
            { displayName: "Dock", value: "dock", icon: "dock_to_bottom" },
            { displayName: "Sidebars", value: "sidebars", icon: "side_navigation" },
            { displayName: "Popups", value: "popups", icon: "chat_bubble" },
            { displayName: "Interaction", value: "interaction", icon: "touch_app" },
            { displayName: "Performance", value: "performance", icon: "speed" }
        ].filter(option => root.sections.includes(option.value))
    }

    function activateSection(section: string): void {
        const raw = String(section ?? "").trim()
        const lower = raw.toLowerCase()
        if (lower === "editmode" || lower === "edit mode" || lower === "editor" || lower === "live editor") {
            root.activeSection = root.sections.includes("bar")
                ? "bar"
                : (root.sections.includes("surface") ? "surface" : (root.sections[0] ?? "surface"))
            return
        }
        if (root.sections.includes(raw))
            root.activeSection = raw
    }

    // 01: Perimeter & Liquid Frame
    SettingsCardSection {
        id: surfaceCard
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        title: "Perimeter & Liquid Frame"
        icon: "opacity"
        showHeader: true
        settingsTaskSection: "surface"
        visible: root.activeSection === "surface" || root.activeSection === "performance"
            || root.activeSection === "waves" || root.activeSection === "spectrum"
            || root.activeSection === "interaction"
            || root.twoColumnSurfacePerformance || root.twoColumnWavesSpectrum
            || (root.unifiedSurfaceWaves && root.activeSection !== "bar" && root.activeSection !== "popups" && root.activeSection !== "dock" && root.activeSection !== "sidebars")

        SettingsGroup {
            id: surfacePerfGroup

            ColumnLayout {
                id: qualityTierHeaderGrid
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: "Rendering quality tier"
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurface
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Glass uses wallpaper, not window capture."
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }
                }

                ConfigSelectionArray {
                    Layout.fillWidth: true
                    fillWidthSegments: true
                    enabled: !(Config.options?.abyss?.autoQuality ?? false)
                    currentValue: Config.options?.abyss?.quality ?? "balanced"
                    options: [
                        { displayName: "Performance", value: "performance" },
                        { displayName: "Balanced", value: "balanced" },
                        { displayName: "Quality", value: "quality" }
                    ]
                    onSelected: value => Config.setNestedValue("abyss.quality", value)
                }
            }

            SettingsDivider {}

            GridLayout {
                id: qualitySwitches
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                columns: width >= 600 * Appearance.fontSizeScale ? 3 : 1
                uniformCellWidths: columns > 1
                columnSpacing: 16
                rowSpacing: 6

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    buttonIcon: "speed"
                    text: "Auto quality"
                    autoToggle: false
                    checked: Config.options?.abyss?.autoQuality ?? false
                    onToggledByUser: checked => Config.setNestedValue("abyss.autoQuality", checked)
                    StyledToolTip { text: "Follow system power profile automatically" }
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    buttonIcon: "energy_savings_leaf"
                    text: "Low power mode"
                    autoToggle: false
                    checked: Config.options?.performance?.lowPower ?? false
                    onToggledByUser: checked => Config.setNestedValue("performance.lowPower", checked)
                    StyledToolTip { text: "Reduce background shell visual overhead" }
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    buttonIcon: "fullscreen"
                    text: "Show in fullscreen"
                    autoToggle: false
                    checked: Config.options?.abyss?.perimeter?.visibleInFullscreen ?? false
                    onToggledByUser: checked => Config.setNestedValue("abyss.perimeter.visibleInFullscreen", checked)
                    StyledToolTip { text: "Keep Screen Edge visible over fullscreen windows" }
                }
            }

            SettingsDivider {}

            ContentSubsectionLabel {
                text: Translation.tr("Material & Glass")
            }

            GridLayout {
                id: materialMetricsGrid
                Layout.fillWidth: true
                columns: width >= 540 * Appearance.fontSizeScale ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: 10
                rowSpacing: 10

                CompactSurfacePercent {
                    text: "Surface opacity"
                    configKey: "abyss.surface.opacity"
                    fallback: .78
                    minimum: 0
                    toggleIcon: "opacity"
                    toggleLabel: Translation.tr("Transparent")
                    toggleDescription: "Transparent surfaces"
                    searchKeywords: ["transparent", "surface", "opacity"]
                    toggleChecked: (Config.options?.abyss?.surface?.opacity ?? .78) < .999
                    onToggledByUser: checked => Config.setNestedValue("abyss.surface.opacity", checked ? .78 : 1)
                }

                CompactSurfaceRow {
                    objectName: "abyssPanelOpacity"
                    text: "Panel & content opacity"
                    from: 0
                    to: 1
                    stepSize: .01
                    currentValue: AbyssStyle.contentOpacity
                    valueText: Math.round(currentValue * 100) + "%"
                    toggleIcon: "link"
                    toggleLabel: Translation.tr("Follow")
                    toggleObjectName: "abyssPanelOpacityFollow"
                    toggleDescription: "Panel and content opacity follows Screen Edge"
                    searchKeywords: ["follow", "screen edge", "panel", "content", "opacity"]
                    toggleChecked: (Config.options?.abyss?.content?.opacity ?? -1) < 0
                    onToggledByUser: checked => Config.setNestedValue("abyss.content.opacity", checked ? -1 : AbyssStyle.contentOpacity)
                    onMoved: value => Config.setNestedValue("abyss.content.opacity", value)
                }

                CompactSurfacePercent {
                    text: "Blur strength"
                    configKey: "abyss.effects.blur.radius"
                    fallback: 10
                    maximum: 24
                    toggleIcon: "blur_on"
                    toggleLabel: Translation.tr("Blur")
                    toggleDescription: "Wallpaper blur"
                    searchKeywords: ["wallpaper", "blur", "toggle"]
                    toggleChecked: Config.options?.abyss?.effects?.blur?.enabled ?? true
                    onToggledByUser: checked => Config.setNestedValue("abyss.effects.blur.enabled", checked)
                }

                CompactSurfaceRow {
                    objectName: "abyssPanelBlur"
                    text: "Panel blur"
                    from: 0
                    to: 24
                    stepSize: 1
                    currentValue: AbyssStyle.configuredContentBlurRadius
                    valueText: Math.round(currentValue) + " px"
                    toggleIcon: "link"
                    toggleLabel: Translation.tr("Follow")
                    toggleObjectName: "abyssPanelBlurFollow"
                    toggleDescription: "Panel blur follows Screen Edge"
                    searchKeywords: ["follow", "screen edge", "panel", "blur"]
                    toggleChecked: (Config.options?.abyss?.content?.blurRadius ?? -1) < 0
                    onToggledByUser: checked => Config.setNestedValue("abyss.content.blurRadius", checked ? -1 : AbyssStyle.configuredContentBlurRadius)
                    onMoved: value => Config.setNestedValue("abyss.content.blurRadius", value)
                }

                CompactSurfacePercent {
                    Layout.columnSpan: materialMetricsGrid.columns
                    text: "Refraction"
                    configKey: "abyss.effects.refraction.strength"
                    fallback: 6
                    minimum: 0
                    maximum: 16
                    toggleIcon: "water_lux"
                    toggleLabel: Translation.tr("Liquid")
                    toggleDescription: "Liquid refraction (Quality tier)"
                    searchKeywords: ["refraction", "glass", "distortion", "liquid"]
                    toggleChecked: Config.options?.abyss?.effects?.refraction?.enabled ?? false
                    onToggledByUser: checked => Config.setNestedValue("abyss.effects.refraction.enabled", checked)
                }
            }

            SettingsDivider {}

            ContentSubsectionLabel {
                text: Translation.tr("Geometry & Lighting")
            }

            GridLayout {
                Layout.fillWidth: true
                columns: width >= 740 * Appearance.fontSizeScale ? 3 : (width >= 480 * Appearance.fontSizeScale ? 2 : 1)
                uniformCellWidths: columns > 1
                columnSpacing: 10
                rowSpacing: 10

                CompactSurfacePercent {
                    text: "Curvature"
                    configKey: "abyss.perimeter.radius"
                    fallback: 34
                    minimum: 12
                    maximum: 64
                }
                CompactSurfacePercent {
                    text: "Fusion softness"
                    configKey: "abyss.surface.softness"
                    fallback: 24
                    minimum: 4
                    maximum: 48
                }
                CompactSurfacePercent {
                    text: "Surface tension"
                    configKey: "abyss.surface.tension"
                    fallback: .5
                    minimum: 0
                    maximum: 1
                    searchKeywords: ["tension", "neck", "liquid", "curve"]
                }
                CompactSurfacePercent {
                    text: "Edge glow"
                    configKey: "abyss.effects.glow.strength"
                    fallback: .08
                    minimum: 0
                    maximum: .3
                    searchKeywords: ["glow", "accent", "edge", "bloom"]
                }
                CompactSurfacePercent {
                    objectName: "abyssRimHighlight"
                    text: "Rim highlight"
                    configKey: "abyss.effects.surfaceHighlight"
                    fallback: .45
                    minimum: 0
                    maximum: 1
                    searchKeywords: ["rim", "highlight", "specular", "border", "edge"]
                }
                CompactSurfacePercent {
                    objectName: "abyssShadowStrength"
                    text: "Shadows"
                    configKey: "abyss.effects.shadowStrength"
                    fallback: .24
                    minimum: 0
                    maximum: .5
                    searchKeywords: ["shadow", "shadows", "drop shadow", "depth"]
                }
            }
        }
    }

    // 02: Edge Waves & Organic Reactivity
    SettingsCardSection {
        id: wavesCard
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        title: "Edge Waves & Organic Reactivity"
        icon: "waves"
        showHeader: true
        settingsTaskSection: "surface"
        visible: surfaceCard.visible

        SettingsGroup {
            id: wavesTuningGroup

            RowLayout {
                id: wavesHeaderRow
                Layout.fillWidth: true
                spacing: 10

                SettingsSwitch {
                    Layout.fillWidth: false
                    buttonIcon: "waves"
                    text: "Waves"
                    autoToggle: false
                    checked: Config.options?.abyss?.waves?.enabled ?? false
                    onToggledByUser: checked => Config.setNestedValue("abyss.waves.enabled", checked)
                }

                ConfigSelectionArray {
                    Layout.fillWidth: true
                    fillWidthSegments: true
                    currentValue: Config.options?.abyss?.waves?.preset ?? "balanced"
                    options: [
                        { displayName: "Calm", value: "calm" },
                        { displayName: "Balanced", value: "balanced" },
                        { displayName: "Fluid", value: "fluid" },
                        { displayName: "Deep", value: "deep" },
                        { displayName: "Custom", value: "custom" }
                    ]
                    onSelected: value => {
                        const updates = { "abyss.waves.preset": value }
                        if (Wave.presets[value])
                            Object.keys(Wave.presets[value]).forEach(k => updates["abyss.waves." + k] = Wave.presets[value][k])
                        Config.setNestedValues(updates)
                    }
                }
            }

            AbyssWavePreview {
                id: wavePreview
                Layout.fillWidth: true
                implicitHeight: Math.round(112 * Appearance.fontSizeScale)
                Layout.preferredHeight: implicitHeight
            }

            GridLayout {
                id: wavesCommonSlidersGrid
                Layout.fillWidth: true
                columns: width >= 480 * Appearance.fontSizeScale ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: 10
                rowSpacing: 10

                CompactSurfaceRow {
                    text: "Strength"
                    from: 0
                    to: 4
                    stepSize: .05
                    currentValue: Wave.bodyStrength(Config.options?.abyss?.waves)
                    valueText: Math.round(currentValue * 100) + "%"
                    onMoved: value => Config.setNestedValue("abyss.waves.strength", value)
                }
                CompactSurfaceRow {
                    text: "Whitewater"
                    from: 0
                    to: 1
                    stepSize: .02
                    currentValue: Config.options?.abyss?.waves?.whitewater ?? .65
                    valueText: Math.round(currentValue * 100) + "%"
                    onMoved: value => Config.setNestedValue("abyss.waves.whitewater", value)
                }
            }

            GridLayout {
                id: wavesCommonSwitchesGrid
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                columns: width >= 640 * Appearance.fontSizeScale ? 3 : 1
                uniformCellWidths: columns > 1
                columnSpacing: 16
                rowSpacing: 6

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    buttonIcon: "moving"
                    text: "Popup travel"
                    autoToggle: false
                    checked: Config.options?.abyss?.waves?.popupTravel ?? true
                    onToggledByUser: checked => Config.setNestedValue("abyss.waves.popupTravel", checked)
                }
                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    buttonIcon: "water_drop"
                    text: "Idle ripple"
                    autoToggle: false
                    checked: Config.options?.abyss?.waves?.idle ?? false
                    onToggledByUser: checked => Config.setNestedValue("abyss.waves.idle", checked)
                }
                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    buttonIcon: "side_navigation"
                    text: "Edge hover sidebars"
                    autoToggle: false
                    checked: Config.options?.abyss?.sidebars?.hoverEnabled ?? true
                    onToggledByUser: checked => Config.setNestedValue("abyss.sidebars.hoverEnabled", checked)
                }
            }

            GridLayout {
                id: wavesCustomGrid
                Layout.fillWidth: true
                visible: (Config.options?.abyss?.waves?.preset ?? "balanced") === "custom"
                columns: width >= 480 * Appearance.fontSizeScale ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: 10
                rowSpacing: 10

                WaveControl { text: "Wave size"; parameter: "amplitude" }
                WaveControl { text: "Propagation"; parameter: "propagation" }
                WaveControl { text: "Wave speed"; parameter: "speed" }
                WaveControl { text: "Decay"; parameter: "decay" }
                WaveControl { text: "Tension"; parameter: "tension" }
                WaveControl { text: "Viscosity"; parameter: "viscosity" }
                WaveControl { text: "Rebound"; parameter: "rebound" }
                WaveControl { text: "Corner"; parameter: "corner" }
            }

            SettingsDivider {}

            ContentSubsectionLabel {
                text: Translation.tr("Interaction Reactivity")
            }

            GridLayout {
                id: interactionReactivityGrid
                Layout.fillWidth: true
                columns: width >= 480 * Appearance.fontSizeScale ? 2 : 1
                uniformCellWidths: columns > 1
                columnSpacing: 10
                rowSpacing: 10

                CompactSurfacePercent { text: "Hover response"; configKey: "abyss.waves.hover"; fallback: 1 }
                CompactSurfacePercent { text: "Press response"; configKey: "abyss.waves.press"; fallback: 1 }
                CompactSurfacePercent { text: "Opening response"; configKey: "abyss.waves.open"; fallback: 1 }
                CompactSurfacePercent { text: "Closing response"; configKey: "abyss.waves.close"; fallback: 1 }
                CompactSurfacePercent {
                    Layout.columnSpan: interactionReactivityGrid.columns
                    text: "Drag response"
                    configKey: "abyss.waves.drag"
                    fallback: 1
                }
            }
        }
    }

    // 03: Audio Spectrum
    SettingsCardSection {
        id: spectrumCard
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        title: "Audio Spectrum"
        icon: "graphic_eq"
        showHeader: true
        settingsTaskSection: "surface"
        visible: surfaceCard.visible

        SettingsGroup {
            id: audioSpectrumGroup

            GridLayout {
                Layout.fillWidth: true
                columns: width >= 500 * Appearance.fontSizeScale ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: 20
                rowSpacing: 6

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    buttonIcon: "graphic_eq"
                    text: "Audio spectrum"
                    autoToggle: false
                    checked: (Config.options?.abyss?.spectrum?.configured ?? false)
                        ? (Config.options?.abyss?.spectrum?.enabled ?? false)
                        : (Config.options?.bar?.visualizer?.enable ?? false)
                    onToggledByUser: checked => root.spectrumChange("enabled", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    buttonIcon: "desktop_windows"
                    text: "All screens"
                    autoToggle: false
                    checked: ((Config.options?.abyss?.spectrum?.configured ?? false)
                        ? Config.options?.abyss?.spectrum?.multiMonitorMode
                        : (Config.options?.bar?.visualizer?.multiMonitorMode ?? "primary")) === "all"
                    onToggledByUser: checked => root.spectrumChange("multiMonitorMode", checked ? "all" : "primary")
                    StyledToolTip { text: "Render audio spectrum on all outputs" }
                }
            }

            SettingsDivider {}

            CompactSurfaceRow {
                Layout.fillWidth: true
                text: "Spectrum strength"
                from: 0
                to: 4
                stepSize: .01
                currentValue: Config.getNestedValue("abyss.spectrum.strength", .45)
                valueText: Math.round(currentValue * 100) + "%"
                onMoved: value => root.spectrumChange("strength", value)
            }

            SettingsDivider {}

            ColumnLayout {
                id: spectrumEdgeRow
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: "Spectrum edge"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }

                ConfigSelectionArray {
                    Layout.fillWidth: true
                    fillWidthSegments: true
                    currentValue: Config.options?.abyss?.spectrum?.edge ?? "bar"
                    options: [
                        { displayName: "Bar", value: "bar" },
                        { displayName: "All", value: "all" },
                        { displayName: "Top", value: "top" },
                        { displayName: "Right", value: "right" },
                        { displayName: "Bottom", value: "bottom" },
                        { displayName: "Left", value: "left" }
                    ]
                    onSelected: value => Config.setNestedValue("abyss.spectrum.edge", value)
                }
            }

            SettingsDivider {}

            GridLayout {
                Layout.fillWidth: true
                columns: width >= 480 * Appearance.fontSizeScale ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: 10
                rowSpacing: 10

                SettingsMetricControl {
                    icon: "width_normal"
                    text: Translation.tr("Cava module width")
                    from: 48
                    to: 480
                    stepSize: 8
                    currentValue: Config.options?.bar?.cava?.width ?? 120
                    valueText: Math.round(liveValue) + " px"
                    onMoved: nextVal => {
                        const v = Math.round(nextVal)
                        if (v !== (Config.options?.bar?.cava?.width ?? 120))
                            Config.setNestedValue("bar.cava.width", v)
                    }
                    StyledToolTip { text: Translation.tr("Width of the Cava Equalizer module on the Bar / Screen Edge (px)") }
                }

                SettingsMetricControl {
                    icon: "space_bar"
                    text: Translation.tr("Cava bar spacing")
                    from: 1
                    to: 6
                    stepSize: 1
                    currentValue: Config.options?.bar?.cava?.barSpacing ?? 2
                    valueText: Math.round(liveValue) + " px"
                    onMoved: nextVal => {
                        const v = Math.round(nextVal)
                        if (v !== (Config.options?.bar?.cava?.barSpacing ?? 2))
                            Config.setNestedValue("bar.cava.barSpacing", v)
                    }
                    StyledToolTip { text: Translation.tr("Gap between equalizer bars inside the module (px)") }
                }
            }
        }
    }

    // 04: Surface Transitions
    SettingsCardSection {
        id: interactionCard
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        title: "Surface Transitions"
        icon: "swap_horiz"
        showHeader: true
        settingsTaskSection: "surface"
        visible: surfaceCard.visible

        SettingsGroup {
            id: interactionMotionGroup

            GridLayout {
                Layout.fillWidth: true
                columns: width >= 500 * Appearance.fontSizeScale ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: 20
                rowSpacing: 6

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    buttonIcon: "swap_horiz"
                    text: "Family transition"
                    autoToggle: false
                    checked: Config.options?.familyTransitionAnimation ?? true
                    onToggledByUser: checked => Config.setNestedValue("familyTransitionAnimation", checked)
                    StyledToolTip { text: "Animate when switching panel families" }
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    buttonIcon: "motion_photos_off"
                    text: "Reduce animations"
                    autoToggle: false
                    checked: Config.options?.performance?.reduceAnimations ?? false
                    onToggledByUser: checked => Config.setNestedValue("performance.reduceAnimations", checked)
                }
            }

            SettingsDivider {}

            SettingsPresetRow {
                icon: "animation"
                text: Translation.tr("Motion intensity")
                from: 0
                to: 1
                stepSize: 0.05
                value: Config.getNestedValue("abyss.motion.intensity", 0.6)
                displayValue: Math.round(liveValue * 100) + "%"
                presets: [
                    { label: "0%", value: 0.0 },
                    { label: "30%", value: 0.3 },
                    { label: "60%", value: 0.6 },
                    { label: "85%", value: 0.85 },
                    { label: "100%", value: 1.0 }
                ]
                onMoved: nextVal => Config.setNestedValue("abyss.motion.intensity", nextVal)
            }
        }
    }

    // 05: Customization Stage (Edit Mode)
    SettingsCardSection {
        id: editStageCard
        objectName: "abyssEditStageSettingsCard"
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        title: Translation.tr("Customization Stage (Edit Mode)")
        icon: "picture_in_picture_alt"
        showHeader: true
        settingsTaskSection: "surface"
        visible: surfaceCard.visible

        SettingsGroup {
            SettingsSwitch {
                objectName: "abyssEditStageEnable"
                Layout.fillWidth: true
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Shrink desktop in Edit mode")
                autoToggle: false
                checked: Config.options?.abyss?.editStage?.enable ?? true
                onToggledByUser: checked => Config.setNestedValue("abyss.editStage.enable", checked)
                StyledToolTip { text: Translation.tr("Zoom out the live desktop stage and mount customization docks outside the bottom edge") }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: width >= 500 * Appearance.fontSizeScale ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: 20
                rowSpacing: 6

                SettingsSwitch {
                    objectName: "abyssEditStageWallpaper"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    enabled: Config.options?.abyss?.editStage?.enable ?? true
                    buttonIcon: "wallpaper"
                    text: Translation.tr("Stage on Change Wallpaper")
                    autoToggle: false
                    checked: Config.options?.abyss?.editStage?.wallpaperPreview ?? true
                    onToggledByUser: checked => Config.setNestedValue("abyss.editStage.wallpaperPreview", checked)
                    StyledToolTip { text: Translation.tr("Shrink the desktop stage when previewing wallpapers from the customization dock") }
                }

                SettingsSwitch {
                    objectName: "abyssEditStagePark"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    enabled: Config.options?.abyss?.editStage?.enable ?? true
                    buttonIcon: "workspaces"
                    text: Translation.tr("Park on empty workspace")
                    autoToggle: false
                    checked: Config.options?.abyss?.editStage?.parkEmptyWorkspace ?? true
                    onToggledByUser: checked => Config.setNestedValue("abyss.editStage.parkEmptyWorkspace", checked)
                    StyledToolTip { text: Translation.tr("Temporarily switch to an empty workspace while editing desktop widgets or edges") }
                }
            }

            SettingsDivider {}

            SettingsPresetRow {
                objectName: "abyssEditStageScale"
                enabled: Config.options?.abyss?.editStage?.enable ?? true
                icon: "zoom_out_map"
                text: Translation.tr("Desktop stage scale")
                from: 0.72
                to: 0.92
                stepSize: 0.01
                value: Config.getNestedValue("abyss.editStage.scale", 0.83)
                displayValue: Math.round(liveValue * 100) + "%"
                presets: [
                    { label: "75%", value: 0.75 },
                    { label: "80%", value: 0.80 },
                    { label: "83%", value: 0.83 },
                    { label: "88%", value: 0.88 },
                    { label: "92%", value: 0.92 }
                ]
                settingsSearchKeywords: ["desktop", "stage", "shrink", "scale", "zoom", "edit mode", "wallpaper", "customization"]
                onMoved: nextVal => Config.setNestedValue("abyss.editStage.scale", nextVal)
            }
        }
    }

    readonly property var sharedSurfaces: [
        { title: Translation.tr("Notification popups"), description: Translation.tr("Transient notification toasts"), icon: "notifications", path: "notifications.screenList" },
        { title: Translation.tr("OSD indicators"), description: Translation.tr("Volume, brightness, media, and keyboard feedback"), icon: "volume_up", path: "osd.screenList" }
    ]

    function connectedScreenNames(): var {
        const screens = Quickshell.screens
        let names = []
        for (let i = 0; i < screens.length; i++) {
            const name = String(screens[i]?.name ?? "")
            if (name.length > 0 && !names.includes(name))
                names.push(name)
        }
        return names
    }

    function primaryScreenName(): string {
        const preferred = Config.options?.display?.primaryMonitor ?? ""
        const names = connectedScreenNames()
        if (preferred && names.includes(preferred))
            return preferred
        return names.length > 0 ? names[0] : ""
    }

    function configuredScreens(path: string): var {
        const raw = Config.getNestedValue(path, [])
        const names = connectedScreenNames()
        let selected = []
        for (let i = 0; i < (raw?.length ?? 0); i++) {
            const name = String(raw[i] ?? "")
            if (name.length > 0 && names.includes(name) && !selected.includes(name))
                selected.push(name)
        }
        return selected
    }

    function allScreensEnabled(path: string): bool {
        const raw = Config.getNestedValue(path, [])
        return !raw || raw.length === 0
    }

    function surfaceEnabled(path: string, screenName: string): bool {
        if (allScreensEnabled(path))
            return true
        return configuredScreens(path).includes(screenName)
    }

    function visibilitySummary(path: string): string {
        if (allScreensEnabled(path))
            return Translation.tr("All monitors")
        const selected = configuredScreens(path)
        if (selected.length === 0)
            return Translation.tr("Saved outputs missing")
        if (selected.length === 1)
            return selected[0]
        return selected.length + Translation.tr(" monitors")
    }

    function setSurfaceAll(path: string): void {
        Config.setNestedValue(path, [])
    }

    function setSurfaceScreen(path: string, screenName: string, enabled: bool): void {
        const names = connectedScreenNames()
        if (!screenName || names.length === 0)
            return

        let current = configuredScreens(path)
        if (current.length === 0 && !enabled)
            current = names.slice()

        if (enabled) {
            if (!current.includes(screenName))
                current.push(screenName)
        } else {
            if (current.length <= 1 && current.includes(screenName))
                return
            current = current.filter(name => name !== screenName)
        }

        if (names.length > 0 && names.every(name => current.includes(name)))
            current = []
        Config.setNestedValue(path, current)
    }

    function setPathsToPrimary(paths: var): void {
        const primary = primaryScreenName()
        if (!primary)
            return
        let updates = {}
        for (let i = 0; i < paths.length; i++)
            updates[paths[i]] = [primary]
        Config.setNestedValues(updates)
    }

    function setPathsToAll(paths: var): void {
        let updates = {}
        for (let i = 0; i < paths.length; i++)
            updates[paths[i]] = []
        Config.setNestedValues(updates)
    }

    function surfacePaths(surfaces: var): var {
        let paths = []
        for (let i = 0; i < surfaces.length; i++)
            paths.push(surfaces[i].path)
        return paths
    }

    component PresetActions: RowLayout {
        required property var paths
        Layout.fillWidth: true
        spacing: Appearance.sizes.spacingSmall

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "filter_1"
            mainText: Translation.tr("Primary only")
            onClicked: root.setPathsToPrimary(paths)
            StyledToolTip {
                text: Translation.tr("Restrict this whole group to the primary monitor.")
            }
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "select_all"
            mainText: Translation.tr("Show everywhere")
            onClicked: root.setPathsToAll(paths)
            StyledToolTip {
                text: Translation.tr("Clear monitor restrictions for this whole group.")
            }
        }
    }

    component SurfaceVisibilityBlock: Rectangle {
        id: surfaceBlock
        required property var surface
        readonly property real leadingWidth: Appearance.font.pixelSize.hugeass + Appearance.sizes.spacingLarge
        readonly property bool allOutputs: root.allScreensEnabled(surface.path)

        Layout.fillWidth: true
        implicitHeight: surfaceLayout.implicitHeight + Appearance.sizes.spacingLarge * 2
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: SettingsMaterialPreset.groupBorderColor

        ColumnLayout {
            id: surfaceLayout
            anchors.fill: parent
            anchors.margins: Appearance.sizes.spacingLarge
            spacing: Appearance.sizes.spacingSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.spacingMedium

                Rectangle {
                    implicitWidth: surfaceBlock.leadingWidth
                    implicitHeight: surfaceBlock.leadingWidth
                    radius: Appearance.rounding.small
                    color: surfaceBlock.allOutputs ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimaryContainer
                    Layout.alignment: Qt.AlignTop

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: surfaceBlock.surface.icon
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: surfaceBlock.allOutputs ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimaryContainer
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.sizes.spacingSmall

                        StyledText {
                            Layout.fillWidth: true
                            text: surfaceBlock.surface.title
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            implicitWidth: summaryText.implicitWidth + Appearance.sizes.spacingMedium
                            implicitHeight: summaryText.implicitHeight + Appearance.sizes.spacingSmall
                            radius: Appearance.rounding.full
                            color: surfaceBlock.allOutputs ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimaryContainer
                            Layout.alignment: Qt.AlignVCenter

                            StyledText {
                                id: summaryText
                                anchors.centerIn: parent
                                text: root.visibilitySummary(surfaceBlock.surface.path)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: surfaceBlock.allOutputs ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimaryContainer
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: surfaceBlock.surface.description
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: surfaceBlock.leadingWidth + Appearance.sizes.spacingMedium
                text: surfaceBlock.surface.selectionLabel ?? Translation.tr("Visible on")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: Appearance.colors.colSubtext
            }

            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: surfaceBlock.leadingWidth + Appearance.sizes.spacingMedium
                spacing: Appearance.sizes.spacingSmall / 2

                SelectionGroupButton {
                    leftmost: true
                    rightmost: true
                    buttonIcon: "select_all"
                    buttonText: Translation.tr("All outputs")
                    toggled: surfaceBlock.allOutputs
                    onClicked: root.setSurfaceAll(surfaceBlock.surface.path)
                }

                Repeater {
                    model: root.connectedScreenNames()

                    SelectionGroupButton {
                        required property var modelData
                        readonly property string screenName: String(modelData ?? "")
                        leftmost: true
                        rightmost: true
                        buttonIcon: "monitor"
                        buttonText: screenName
                        toggled: root.surfaceEnabled(surfaceBlock.surface.path, screenName)
                        onClicked: root.setSurfaceScreen(surfaceBlock.surface.path, screenName, !toggled)
                    }
                }
            }
        }
    }

    Item {
        id: modulesCard
        visible: false
        implicitHeight: 0
    }

    // Popups & OSD section
    SettingsCardSection {
        id: popupsCard
        _preventBentoReparent: true
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.alignment: Qt.AlignTop
        title: "Popups & OSD"
        icon: "chat_bubble"
        settingsTaskSection: "popups"
        visible: root.activeSection === "popups"

        SettingsGroup {
            ContentSubsectionLabel {
                text: "Edge placement"
            }
            AbyssPositionSettings { compactActions: true; compactVertical: width < 480 }

            SettingsDivider {}

            ContentSubsection {
                title: Translation.tr("On-screen display (OSD)")

                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= 540 * Appearance.fontSizeScale ? 2 : 1
                    uniformCellWidths: columns === 2
                    columnSpacing: 20
                    rowSpacing: 8

                    ConfigSwitch {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.minimumWidth: 0
                        buttonIcon: "music_note"
                        text: Translation.tr("Media OSD")
                        checked: Config.options?.osd?.mediaEnabled ?? true
                        onCheckedChanged: Config.setNestedValue("osd.mediaEnabled", checked)
                    }

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.minimumWidth: 0
                        icon: "av_timer"
                        text: Translation.tr("Timeout (ms)")
                        value: Config.options?.osd?.timeout ?? 1500
                        from: 500
                        to: 5000
                        stepSize: 100
                        onValueChanged: Config.setNestedValue("osd.timeout", value)
                    }

                    ConfigSwitch {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.minimumWidth: 0
                        buttonIcon: "keyboard"
                        text: Translation.tr("Keyboard OSD popup")
                        checked: Config.options?.keyboardIndicators?.showPopup ?? true
                        onCheckedChanged: Config.setNestedValue("keyboardIndicators.showPopup", checked)
                    }

                    ConfigSwitch {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.minimumWidth: 0
                        buttonIcon: "keyboard_capslock"
                        enabled: Config.options?.keyboardIndicators?.showPopup ?? true
                        text: Translation.tr("Caps Lock OSD")
                        checked: Config.options?.keyboardIndicators?.popup?.caps ?? true
                        onCheckedChanged: Config.setNestedValue("keyboardIndicators.popup.caps", checked)
                    }

                    ConfigSwitch {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.minimumWidth: 0
                        buttonIcon: "pin"
                        enabled: Config.options?.keyboardIndicators?.showPopup ?? true
                        text: Translation.tr("Num Lock OSD")
                        checked: Config.options?.keyboardIndicators?.popup?.num ?? false
                        onCheckedChanged: Config.setNestedValue("keyboardIndicators.popup.num", checked)
                    }

                    ConfigSwitch {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.minimumWidth: 0
                        buttonIcon: "language"
                        enabled: Config.options?.keyboardIndicators?.showPopup ?? true
                        text: Translation.tr("Layout switch OSD")
                        checked: Config.options?.keyboardIndicators?.popup?.layout ?? true
                        onCheckedChanged: Config.setNestedValue("keyboardIndicators.popup.layout", checked)
                    }
                }
            }

            SettingsDivider {}

            ContentSubsection {
                title: "Edge Bar keyboard indicators"

                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= 440 * Appearance.fontSizeScale ? 2 : 1
                    uniformCellWidths: columns === 2
                    columnSpacing: 20
                    rowSpacing: 8

                    ConfigSwitch {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.minimumWidth: 0
                        buttonIcon: "dock_to_bottom"
                        text: "Panel indicators"
                        checked: Config.options?.keyboardIndicators?.showPanel ?? true
                        onCheckedChanged: Config.setNestedValue("keyboardIndicators.showPanel", checked)
                    }

                    ConfigSwitch {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.minimumWidth: 0
                        buttonIcon: "keyboard_capslock"
                        enabled: Config.options?.keyboardIndicators?.showPanel ?? true
                        text: "Caps Lock badge"
                        checked: Config.options?.keyboardIndicators?.panel?.caps ?? true
                        onCheckedChanged: Config.setNestedValue("keyboardIndicators.panel.caps", checked)
                    }

                    ConfigSwitch {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.minimumWidth: 0
                        buttonIcon: "pin"
                        enabled: Config.options?.keyboardIndicators?.showPanel ?? true
                        text: "Num Lock badge"
                        checked: Config.options?.keyboardIndicators?.panel?.num ?? false
                        onCheckedChanged: Config.setNestedValue("keyboardIndicators.panel.num", checked)
                    }

                    ConfigSwitch {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.minimumWidth: 0
                        buttonIcon: "translate"
                        enabled: Config.options?.keyboardIndicators?.showPanel ?? true
                        text: "Layout badge"
                        checked: Config.options?.keyboardIndicators?.panel?.layout ?? true
                        onCheckedChanged: Config.setNestedValue("keyboardIndicators.panel.layout", checked)
                    }
                }
            }
        }
    }

    SettingsCardSection {
        id: popupSurfacesCard
        _preventBentoReparent: true
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "popups"
        visible: root.activeSection === "popups"
        expanded: true
        icon: "notifications"
        title: Translation.tr("Popups")

        SettingsGroup {
            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "merge"
                text: Translation.tr("These surfaces are shared by both families, so the same monitor choices apply in Material and Waffle.")
            }

            PresetActions {
                paths: root.surfacePaths(root.sharedSurfaces)
            }

            Repeater {
                model: root.sharedSurfaces
                SurfaceVisibilityBlock {
                    required property var modelData
                    surface: modelData
                }
            }
        }
    }
}
