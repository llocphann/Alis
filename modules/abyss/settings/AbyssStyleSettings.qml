pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.looks
import "../../common/PanelFamilyPolicy.js" as FamilyPolicy
import "../looks/AbyssWave.js" as Wave

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: root.activeSection === "popups" ? 14 : 10
    property string activeSection: "surface"
    property var sections: ["surface","interaction","performance","spectrum","waves"]
    property real modulesCardMinHeight: 0
    readonly property real modulesCardImplicitHeight: modulesCard.implicitHeight
    property real popupsCardMinHeight: 0
    readonly property real popupsCardImplicitHeight: popupsCard.naturalCardImplicitHeight + root.spacing + popupSurfacesCard.naturalCardImplicitHeight
    readonly property bool unifiedSurfaceWaves: root.sections.includes("surface")
        && root.sections.includes("waves")
    readonly property bool twoColumnSurfacePerformance: root.sections.length === 2
        && root.sections.includes("surface") && root.sections.includes("performance")
    readonly property bool twoColumnWavesSpectrum: root.sections.length === 3
        && root.sections.includes("waves") && root.sections.includes("spectrum")
        && root.sections.includes("interaction")
    readonly property var waveValues: Wave.parameters(Config.options?.abyss?.waves)

    function spectrumChange(key,value): void {
        const options=Config.options?.abyss?.spectrum
        const updates={"abyss.spectrum.configured":true,
            "abyss.spectrum.enabled":options?.configured ? options.enabled : Config.options?.bar?.visualizer?.enable ?? false,
            "abyss.spectrum.multiMonitorMode":options?.configured ? options.multiMonitorMode : Config.options?.bar?.visualizer?.multiMonitorMode ?? "primary"}
        updates["abyss.spectrum."+key]=value
        Config.setNestedValues(updates)
    }
    function waveChange(key,value): void {
        const updates={"abyss.waves.preset":"custom"}
        Object.keys(Wave.presets.balanced).forEach(k => updates["abyss.waves."+k]=waveValues[k])
        updates["abyss.waves."+key]=value
        Config.setNestedValues(updates)
    }

    // Ultra-compact one-line slider row that fits 2 or 3 per row in a GridLayout.
    component CompactSurfaceRow: RowLayout {
        id: row
        property string text: ""
        property real from: 0
        property real to: 1
        property real stepSize: .01
        property real currentValue: 0
        property string valueText: ""
        property string toggleIcon: ""
        property string toggleDescription: ""
        property string toggleObjectName: ""
        property var searchKeywords: []
        property bool toggleChecked: false
        signal moved(real value)
        signal toggledByUser(bool checked)

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: 6
        implicitHeight: Math.round(28 * Appearance.fontSizeScale)

        Item {
            visible: row.toggleIcon.length > 0
            Layout.preferredWidth: Math.round(24 * Appearance.fontSizeScale)
            Layout.preferredHeight: Math.round(24 * Appearance.fontSizeScale)
            Layout.alignment: Qt.AlignVCenter
            IconToolbarButton {
                anchors.centerIn: parent
                width: Math.round(24 * Appearance.fontSizeScale)
                height: width
                visible: row.toggleIcon.length > 0
                objectName: row.toggleObjectName
                text: row.toggleIcon
                toggled: row.toggleChecked
                checked: row.toggleChecked
                buttonText: row.toggleDescription
                Accessible.checkable: true
                Accessible.checked: row.toggleChecked
                onClicked: row.toggledByUser(!row.toggleChecked)
                StyledToolTip {
                    text: row.toggleDescription + (row.toggleChecked ? " · On" : " · Off")
                }
            }
        }

        StyledText {
            Layout.preferredWidth: (row.toggleIcon.length > 0 ? 116 : 140) * Appearance.fontSizeScale
            Layout.minimumWidth: 72 * Appearance.fontSizeScale
            Layout.alignment: Qt.AlignVCenter
            text: row.text
            elide: Text.ElideRight
            color: Appearance.colors.colOnSurface
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        StyledSlider {
            Layout.fillWidth: true
            Layout.minimumWidth: 56 * Appearance.fontSizeScale
            Layout.alignment: Qt.AlignVCenter
            configuration: StyledSlider.Configuration.S
            from: row.from
            to: row.to
            stepSize: row.stepSize
            value: row.currentValue
            tooltipContent: row.valueText
            Accessible.name: row.text
            settingsSearchLabel: row.text
            settingsSearchKeywords: row.searchKeywords
            onMoved: row.moved(value)
        }

        StyledText {
            Layout.preferredWidth: 44 * Appearance.fontSizeScale
            Layout.minimumWidth: 40 * Appearance.fontSizeScale
            Layout.alignment: Qt.AlignVCenter
            text: row.valueText
            horizontalAlignment: Text.AlignRight
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smallest
        }
    }

    component CompactSurfacePercent: CompactSurfaceRow {
        id: control
        required property string configKey
        property real fallback: 0
        property real minimum: 0
        property real maximum: 1
        property string unit: maximum > 4 ? "px" : "%"
        from: minimum
        to: maximum
        stepSize: unit === "%" ? .01 : 1
        currentValue: Config.getNestedValue(configKey, fallback)
        valueText: Math.round(currentValue * (unit === "%" ? 100 : 1))
            + (unit === "%" ? "%" : " px")
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
        icon:"water";title:"Abyss"
        description:"Screen Edge appearance and behavior."
        currentValue:root.activeSection
        onSelected:value=>root.activeSection=value
        visible:options.length > 2 && !root.twoColumnWavesSpectrum && !root.unifiedSurfaceWaves
        showIntro:false
        options:[
            {displayName:"Surface",value:"surface",icon:"opacity"},
            {displayName:"Waves",value:"waves",icon:"waves"},
            {displayName:"Spectrum",value:"spectrum",icon:"graphic_eq"},
            {displayName:"Modules",value:"modules",icon:"widgets"},
            {displayName:"Module behavior",value:"bar",icon:"tune"},
            {displayName:"Dock",value:"dock",icon:"dock_to_bottom"},
            {displayName:"Sidebars",value:"sidebars",icon:"side_navigation"},
            {displayName:"Popups",value:"popups",icon:"chat_bubble"},
            {displayName:"Live Editor",value:"editor",icon:"edit"},
            {displayName:"Interaction",value:"interaction",icon:"touch_app"},
            {displayName:"Performance",value:"performance",icon:"speed"}].filter(option=>root.sections.includes(option.value))
    }

    property real hostPageHeight: 0
    property int hostSubTabCount: 0
    readonly property real targetBentoHeight: {
        const gap = SettingsMaterialPreset.pageSpacing
        const baseH = SettingsMaterialPreset.standardBentoHeight
        const availBodyH = root.hostPageHeight >= 800
            ? Math.max(720, root.hostPageHeight - 20 - (root.hostSubTabCount > 1 || SettingsLayoutManager.editMode ? (40 + gap) : 0))
            : baseH
        return Math.min(baseH, availBodyH)
    }

    // Left Bento Card: Surface & Performance
    SettingsCardSection {
        id: surfaceCard
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        bentoColumn: "left"
        _consumesBentoExtraHeight: true
        title: "Surface & Performance"
        icon: "opacity"
        showHeader: true
        settingsTaskSection: "surface"
        visible: root.activeSection === "surface" || root.activeSection === "performance"
            || root.activeSection === "waves" || root.activeSection === "spectrum"
            || root.activeSection === "interaction"
            || root.twoColumnSurfacePerformance || root.twoColumnWavesSpectrum || root.unifiedSurfaceWaves

        SettingsGroup {
            id: surfacePerfGroup
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ConfigSelectionArray {
                    Layout.fillWidth: true
                    enabled: !(Config.options?.abyss?.autoQuality ?? false)
                    currentValue: Config.options?.abyss?.quality ?? "balanced"
                    options: [
                        {displayName:"Performance",value:"performance"},
                        {displayName:"Balanced",value:"balanced"},
                        {displayName:"Quality",value:"quality"}
                    ]
                    onSelected: value => Config.setNestedValue("abyss.quality", value)
                }

                SettingsSwitch {
                    Layout.fillWidth: false
                    buttonIcon: "speed"
                    text: "Auto quality"
                    autoToggle: false
                    checked: Config.options?.abyss?.autoQuality ?? false
                    onToggledByUser: checked => Config.setNestedValue("abyss.autoQuality", checked)
                    StyledToolTip { text: "Follow power profile" }
                }

                SettingsSwitch {
                    Layout.fillWidth: false
                    buttonIcon: "fullscreen"
                    text: "In fullscreen"
                    autoToggle: false
                    checked: Config.options?.abyss?.perimeter?.visibleInFullscreen ?? false
                    onToggledByUser: checked => Config.setNestedValue("abyss.perimeter.visibleInFullscreen", checked)
                    StyledToolTip { text: "Visible during fullscreen" }
                }
            }

            SettingsDivider {}

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                uniformCellWidths: true
                columnSpacing: 14
                rowSpacing: 6

                CompactSurfacePercent {
                    text:"Surface opacity"
                    configKey:"abyss.surface.opacity";fallback:.78;minimum:0
                    toggleIcon:"opacity"
                    toggleDescription:"Transparent surfaces"
                    searchKeywords:["transparent", "surface", "opacity"]
                    toggleChecked:(Config.options?.abyss?.surface?.opacity ?? .78)<.999
                    onToggledByUser:checked=>Config.setNestedValue("abyss.surface.opacity",checked ? .78 : 1)
                }
                CompactSurfacePercent {
                    text:"Curvature";configKey:"abyss.perimeter.radius"
                    fallback:34;minimum:12;maximum:64
                }
                CompactSurfacePercent {
                    text:"Fusion softness";configKey:"abyss.surface.softness"
                    fallback:24;minimum:4;maximum:48
                }
                CompactSurfacePercent {
                    text:"Blur strength";configKey:"abyss.effects.blur.radius"
                    fallback:10;maximum:24
                    toggleIcon:"blur_on"
                    toggleDescription:"Wallpaper blur"
                    searchKeywords:["wallpaper", "blur", "toggle"]
                    toggleChecked:Config.options?.abyss?.effects?.blur?.enabled ?? true
                    onToggledByUser:checked=>Config.setNestedValue("abyss.effects.blur.enabled",checked)
                }
                CompactSurfaceRow {
                    objectName:"abyssPanelOpacity"
                    text:"Panel opacity";from:0;to:1;stepSize:.01
                    currentValue:AbyssStyle.contentOpacity
                    valueText:Math.round(currentValue*100)+"%"
                    toggleIcon:"link"
                    toggleObjectName:"abyssPanelOpacityFollow"
                    toggleDescription:"Panel and content opacity follows Screen Edge"
                    searchKeywords:["follow", "screen edge", "panel", "content", "opacity"]
                    toggleChecked:(Config.options?.abyss?.content?.opacity ?? -1)<0
                    onToggledByUser:checked=>Config.setNestedValue("abyss.content.opacity",checked ? -1 : AbyssStyle.contentOpacity)
                    onMoved:value=>Config.setNestedValue("abyss.content.opacity",value)
                }
                CompactSurfaceRow {
                    objectName:"abyssPanelBlur"
                    text:"Panel blur";from:0;to:24;stepSize:1
                    currentValue:AbyssStyle.configuredContentBlurRadius
                    valueText:Math.round(currentValue)+" px"
                    toggleIcon:"link"
                    toggleObjectName:"abyssPanelBlurFollow"
                    toggleDescription:"Panel blur follows Screen Edge"
                    searchKeywords:["follow", "screen edge", "panel", "blur"]
                    toggleChecked:(Config.options?.abyss?.content?.blurRadius ?? -1)<0
                    onToggledByUser:checked=>Config.setNestedValue("abyss.content.blurRadius",checked ? -1 : AbyssStyle.configuredContentBlurRadius)
                    onMoved:value=>Config.setNestedValue("abyss.content.blurRadius",value)
                }
                CompactSurfacePercent {
                    objectName:"abyssRimHighlight"
                    text:"Rim highlight";configKey:"abyss.effects.surfaceHighlight"
                    fallback:.45;minimum:0;maximum:1
                    searchKeywords:["rim", "highlight", "specular", "border", "edge"]
                }
                CompactSurfacePercent {
                    objectName:"abyssShadowStrength"
                    text:"Shadows";configKey:"abyss.effects.shadowStrength"
                    fallback:.24;minimum:0;maximum:.5
                    searchKeywords:["shadow", "shadows", "drop shadow", "depth"]
                }
            }
        }

        // Interaction & Motion
        SettingsGroup {
            id: interactionMotionGroup
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: "touch_app"
                    iconSize: Appearance.font.pixelSize.normal
                    color: SettingsMaterialPreset.iconExpandedColor
                }
                StyledText {
                    text: "Interaction & Motion"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: SettingsMaterialPreset.titleExpandedColor
                }

                Item { Layout.fillWidth: true }

                SettingsSwitch {
                    Layout.fillWidth: false
                    buttonIcon: "motion_photos_off"
                    text: "Reduce animations"
                    autoToggle: false
                    checked: Config.options?.performance?.reduceAnimations ?? false
                    onToggledByUser: checked => Config.setNestedValue("performance.reduceAnimations", checked)
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                uniformCellWidths: true
                columnSpacing: 14
                rowSpacing: 4

                CompactSurfacePercent { text:"Hover response";configKey:"abyss.waves.hover";fallback:1 }
                CompactSurfacePercent { text:"Press response";configKey:"abyss.waves.press";fallback:1 }
                CompactSurfacePercent { text:"Opening response";configKey:"abyss.waves.open";fallback:1 }
                CompactSurfacePercent { text:"Closing response";configKey:"abyss.waves.close";fallback:1 }
                CompactSurfacePercent { text:"Drag response";configKey:"abyss.waves.drag";fallback:1 }
                CompactSurfacePercent { text:"Motion intensity";configKey:"abyss.motion.intensity";fallback:.6 }
            }
        }
    }

    // Right Bento Card: Waves & Audio Spectrum
    SettingsCardSection {
        id: wavesCard
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        bentoColumn: "right"
        title: "Waves & Audio Spectrum"
        icon: "waves"
        showHeader: true
        settingsTaskSection: "surface"
        visible: surfaceCard.visible

        SettingsGroup {
            id: wavesTuningGroup
            RowLayout {
                id: wavesHeaderRow
                Layout.fillWidth: true
                spacing: 8

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
                    currentValue: Config.options?.abyss?.waves?.preset ?? "balanced"
                    options: [
                        {displayName:"Calm",value:"calm"},
                        {displayName:"Balanced",value:"balanced"},
                        {displayName:"Fluid",value:"fluid"},
                        {displayName:"Deep",value:"deep"},
                        {displayName:"Custom",value:"custom"}
                    ]
                    onSelected: value => {
                        const updates = {"abyss.waves.preset": value}
                        if (Wave.presets[value])
                            Object.keys(Wave.presets[value]).forEach(k => updates["abyss.waves."+k] = Wave.presets[value][k])
                        Config.setNestedValues(updates)
                    }
                }
            }

            AbyssWavePreview {
                id: wavePreview
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: Math.max(
                    wavesCustomGrid.visible ? 56 : 84,
                    root.targetBentoHeight
                    - wavesCard.chromeImplicitHeight
                    - wavesCard.spacing
                    - audioSpectrumGroup.implicitHeight
                    - (SettingsMaterialPreset.groupPadding * 2
                       + wavesHeaderRow.implicitHeight
                       + SettingsMaterialPreset.groupSpacing
                       + (wavesCustomGrid.visible ? wavesCustomGrid.implicitHeight + SettingsMaterialPreset.groupSpacing : 0))
                )
            }

            GridLayout {
                id: wavesCustomGrid
                Layout.fillWidth: true
                visible: (Config.options?.abyss?.waves?.preset ?? "balanced") === "custom"
                columns: 2
                uniformCellWidths: true
                columnSpacing: 12
                rowSpacing: 4

                CompactSurfaceRow {
                    text: "Strength"; from: 0; to: 4; stepSize: .01
                    currentValue: Wave.bodyStrength(Config.options?.abyss?.waves)
                    valueText: Math.round(currentValue * 100) + "%"
                    onMoved: value => Config.setNestedValue("abyss.waves.strength", value)
                }
                CompactSurfaceRow {
                    text: "Whitewater"; from: 0; to: 1; stepSize: .01
                    currentValue: Config.options?.abyss?.waves?.whitewater ?? .65
                    valueText: Math.round(currentValue * 100) + "%"
                    onMoved: value => Config.setNestedValue("abyss.waves.whitewater", value)
                }
                WaveControl { text: "Wave size"; parameter: "amplitude" }
                WaveControl { text: "Propagation"; parameter: "propagation" }
                WaveControl { text: "Wave speed"; parameter: "speed" }
                WaveControl { text: "Decay"; parameter: "decay" }
                WaveControl { text: "Tension"; parameter: "tension" }
                WaveControl { text: "Viscosity"; parameter: "viscosity" }
                WaveControl { text: "Rebound"; parameter: "rebound" }
                WaveControl { text: "Corner"; parameter: "corner" }
                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "moving"
                    text: "Popup travel"
                    autoToggle: false
                    checked: Config.options?.abyss?.waves?.popupTravel ?? true
                    onToggledByUser: checked => Config.setNestedValue("abyss.waves.popupTravel", checked)
                }
                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "water_drop"
                    text: "Idle ripple"
                    autoToggle: false
                    checked: Config.options?.abyss?.waves?.idle ?? false
                    onToggledByUser: checked => Config.setNestedValue("abyss.waves.idle", checked)
                }
            }
        }

        SettingsGroup {
            id: audioSpectrumGroup
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                SettingsSwitch {
                    Layout.fillWidth: false
                    buttonIcon: "graphic_eq"
                    text: "Audio spectrum"
                    autoToggle: false
                    checked: (Config.options?.abyss?.spectrum?.configured ?? false)
                        ? (Config.options?.abyss?.spectrum?.enabled ?? false)
                        : (Config.options?.bar?.visualizer?.enable ?? false)
                    onToggledByUser: checked => root.spectrumChange("enabled", checked)
                }

                Item { Layout.fillWidth: true }

                SettingsSwitch {
                    Layout.fillWidth: false
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

            CompactSurfaceRow {
                Layout.fillWidth: true
                text: "Spectrum strength"
                from: 0; to: 4; stepSize: .01
                currentValue: Config.getNestedValue("abyss.spectrum.strength", .45)
                valueText: Math.round(currentValue * 100) + "%"
                onMoved: value => root.spectrumChange("strength", value)
            }

            ConfigSelectionArray {
                Layout.fillWidth: true
                currentValue: Config.options?.abyss?.spectrum?.edge ?? "bar"
                options: [
                    {displayName:"Bar",value:"bar"},
                    {displayName:"All",value:"all"},
                    {displayName:"Top",value:"top"},
                    {displayName:"Right",value:"right"},
                    {displayName:"Bottom",value:"bottom"},
                    {displayName:"Left",value:"left"}
                ]
                onSelected: value => Config.setNestedValue("abyss.spectrum.edge", value)
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
    SettingsCardSection {
        id: popupsCard
        _preventBentoReparent: true
        title:"Popup Placement & Size";icon:"chat_bubble";settingsTaskSection:"popups"
        visible:root.activeSection==="popups"
        SettingsGroup {
            ContentSubsectionLabel {
                text: "Edge placement"
            }
            AbyssPositionSettings { compactActions: true }
        }
    }
    SettingsCardSection {
        id: popupSurfacesCard
        _preventBentoReparent: true
        _bentoExtraHeight: expanded ? Math.max(0, root.popupsCardMinHeight - (popupsCard.naturalCardImplicitHeight + root.spacing + naturalCardImplicitHeight)) : 0
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
    SettingsCardSection {
        id: editStageCard
        objectName: "abyssEditStageSettingsCard"
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        bentoColumn: "left"
        title: Translation.tr("Customization Stage (Edit Mode)")
        icon: "picture_in_picture_alt"
        showHeader: true
        settingsTaskSection: "surface"
        visible: surfaceCard.visible || root.activeSection === "editor"

        SettingsGroup {
            GridLayout {
                Layout.fillWidth: true
                columns: width >= 340 ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: 8
                rowSpacing: 4

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

                SettingsSwitch {
                    objectName: "abyssEditStageWallpaper"
                    Layout.fillWidth: true
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
                    enabled: Config.options?.abyss?.editStage?.enable ?? true
                    buttonIcon: "workspaces"
                    text: Translation.tr("Park on empty workspace")
                    autoToggle: false
                    checked: Config.options?.abyss?.editStage?.parkEmptyWorkspace ?? true
                    onToggledByUser: checked => Config.setNestedValue("abyss.editStage.parkEmptyWorkspace", checked)
                    StyledToolTip { text: Translation.tr("Temporarily switch to an empty workspace while editing desktop widgets, edges, or wallpaper") }
                }
            }

            CompactSurfacePercent {
                objectName: "abyssEditStageScale"
                enabled: Config.options?.abyss?.editStage?.enable ?? true
                text: Translation.tr("Desktop stage scale")
                configKey: "abyss.editStage.scale"
                fallback: 0.83
                minimum: 0.72
                maximum: 0.92
                searchKeywords: ["desktop", "stage", "shrink", "scale", "zoom", "edit mode", "wallpaper", "customization"]
            }
        }
    }

    SettingsCardSection {
        title:"Live Editor";icon:"edit";settingsTaskSection:"editor"
        visible:root.activeSection==="editor"
        SettingsGroup {
            SettingsNote { text:"Done saves; Cancel restores. Choose a global or per-output layout." }
        }
    }
}
