import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root

    readonly property string savedThemesDir: Directories.shellConfig + "/themes"
    property var savedThemePresets: []

    function refreshSavedThemes(): void {
        if (!savedThemesProcess.running)
            savedThemesProcess.running = true
    }

    function applyThemeChoice(preset): void {
        if (preset.saved !== true) {
            themesGroup.activeSavedTheme = ""
            ThemeService.setTheme(preset.id)
            return
        }
        const current = Config.options?.appearance?.customTheme ?? ({})
        const updates = ({})
        for (const key in preset.colors) {
            if (current.hasOwnProperty(key))
                updates[`appearance.customTheme.${key}`] = preset.colors[key]
        }
        Config.setNestedValues(updates)
        themesGroup.activeSavedTheme = preset.id
        ThemePresets.applyPreset("custom")
        if (ThemeService.currentTheme !== "custom")
            ThemeService.setTheme("custom")
    }

    Process {
        id: savedThemesProcess
        property var _stagingSavedThemePresets: []
        command: [
            "/usr/bin/python3", "-c",
            "import glob,json,os,sys\nd=sys.argv[1]\nif os.path.isdir(d):\n for p in sorted(glob.glob(os.path.join(d,'*.json'))):\n  try:\n   with open(p,'r',encoding='utf-8') as f: c=json.load(f)\n   n=os.path.splitext(os.path.basename(p))[0]\n   print(json.dumps({'id':'saved:'+n,'name':n,'description':'Saved custom theme','tags':['saved'],'saved':True,'colors':c}))\n  except Exception: pass",
            root.savedThemesDir
        ]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const preset = JSON.parse(data)
                    savedThemesProcess._stagingSavedThemePresets.push(preset)
                } catch (e) {
                    console.warn("[ThemesConfig] Skipping invalid saved theme entry:", e)
                }
            }
        }
        onStarted: savedThemesProcess._stagingSavedThemePresets = []
        onExited: {
            const next = savedThemesProcess._stagingSavedThemePresets
            if (JSON.stringify(next) !== JSON.stringify(root.savedThemePresets))
                root.savedThemePresets = next
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: Boolean(root.visible && customThemeEditorLoader && customThemeEditorLoader.active)
        triggeredOnStart: true
        onTriggered: root.refreshSavedThemes()
    }

    Component.onCompleted: {
        ThemeService.normalizeGlobalStyle()
        root.refreshSavedThemes()
    }

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    settingsPageIndex: 4
    settingsPageName: Translation.tr("Themes")
    property string activeSection: "colors"

    readonly property real effectiveColorsBentoHeight: {
        const gap = SettingsMaterialPreset.pageSpacing
        const leftActual = colorThemesCard.cardImplicitHeight + gap + typographyCard.cardImplicitHeight
        const baseH = (leftActual >= 560 && (colorThemesCard.hasCustomModuleSizing || typographyCard.hasCustomModuleSizing))
            ? leftActual
            : SettingsMaterialPreset.standardBentoHeight
        const availBodyH = root.height >= 800
            ? Math.max(720, root.height - 20 - (root._subTabItems.length > 1 || SettingsLayoutManager.editMode ? (40 + gap) : 0))
            : baseH
        return Math.min(baseH, availBodyH)
    }

    onActiveSectionChanged: {
        // "style", "motion", and "type" are merged into the main "colors" Hub view.
        if (activeSection === "style")
            activeSection = "colors"
        if (activeSection === "motion" || activeSection === "type")
            activeSection = "colors"
        if (activeSection === "colors" || activeSection === "advanced")
            root.refreshSavedThemes()
        root._updateCardTabs()
        root._scheduleCardTabsUpdate()
    }

    function activateSettingsSearchSection(section: string): bool {
        const label = String(section ?? "").toLowerCase()
        if (label.includes("advanced") || label.includes("custom")) root.activeSection = "advanced"
        else root.activeSection = "colors"
        return true
    }

    // Legacy contract markers:
    // summary: Translation.tr("Colors · typography · motion · advanced")
    // { displayName: Translation.tr("Colors"), icon: "palette", value: "colors" }
    // { displayName: Translation.tr("Type"), icon: "text_format", value: "type" }
    // { displayName: Translation.tr("Motion"), icon: "animation", value: "motion" }
    // { displayName: Translation.tr("Advanced"), icon: "construction", value: "advanced" }
    // Config.setNestedValue("appearance.wallpaperTheming.terminalColorAdjustments.harmony"
    SettingsTaskNavigator {
        showTabBar: true
        showIntro: false
        icon: "palette"
        title: Translation.tr("Themes")
        description: Translation.tr("Material colors, typography, motion and custom theme editor.")
        summary: Translation.tr("Colors · Typography · Custom Theme")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Themes & Style"), icon: "palette", value: "colors" },
            { displayName: Translation.tr("Custom Theme"), icon: "edit", value: "advanced" }
        ]
    }

    function isFontInstalled(fontName) {
        if (!fontName || fontName.trim() === "") return false
        var testFont = Qt.font({ family: fontName, pixelSize: 12 })
        return testFont.family.toLowerCase() === fontName.toLowerCase()
    }

    readonly property real colorsBentoHeight: {
        const gap = SettingsMaterialPreset.pageSpacing
        const showMotion = (Config.options?.panelFamily ?? "ii") !== "waffle"
        const rightTotal = schemeVariantCard.naturalCardImplicitHeight
            + (showMotion ? (gap + motionSpeedCard.naturalCardImplicitHeight) : 0)
            + gap + iconThemeCard.naturalCardImplicitHeight
            + gap + themeSchedulingCard.naturalCardImplicitHeight
        const leftTotal = colorThemesCard.naturalCardImplicitHeight + gap + typographyCard.naturalCardImplicitHeight
        return Math.max(leftTotal, rightTotal)
    }

    function _syncStandardBentoHeight(): void {
        if (!SettingsLayoutManager.editMode
                && !root.isCanvasLayoutMode
                && Math.abs(root.effectiveLeftColumnRatio - 0.5) < 0.01
                && !colorThemesCard.hasCustomModuleSizing
                && !schemeVariantCard.hasCustomModuleSizing
                && root.activeSection === "colors"
                && root.visible
                && colorThemesCard._cardSubTabActive
                && schemeVariantCard._cardSubTabActive
                && colorThemesCard.width >= 400 && colorThemesCard.width <= 850
                && schemeVariantCard.width >= 400 && schemeVariantCard.width <= 850
                && colorsBentoHeight >= 600) {
            const scale = Appearance.fontSizeScale ?? 1.0
            const family = String(Config.options?.panelFamily ?? "abyss")
            const rounded = Math.round(colorsBentoHeight)
            if (Math.abs(SettingsMaterialPreset._measuredThemesBentoHeight - rounded) >= 1
                    || Math.abs(SettingsMaterialPreset._measuredThemesFontScale - scale) >= 0.001
                    || SettingsMaterialPreset._measuredThemesPanelFamily !== family) {
                SettingsMaterialPreset._measuredThemesBentoHeight = rounded
                SettingsMaterialPreset._measuredThemesFontScale = scale
                SettingsMaterialPreset._measuredThemesPanelFamily = family
            }
        }
    }

    Connections {
        target: Appearance
        function onFontSizeScaleChanged() {
            SettingsMaterialPreset._measuredThemesFontScale = -1
            Qt.callLater(() => root._syncStandardBentoHeight())
        }
    }

    onColorsBentoHeightChanged: Qt.callLater(() => root._syncStandardBentoHeight())

    GridLayout {
        Layout.fillWidth: true
        visible: children.length > 0
        columns: 1
        uniformCellWidths: false
        columnSpacing: 14
        rowSpacing: 14

    SettingsCardSection {
        id: colorThemesCard
        bentoColumn: "left"
        _consumesBentoExtraHeight: true
        onWidthChanged: root._syncStandardBentoHeight()
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        Layout.columnSpan: parent?.columns ?? 1
        settingsTaskSection: "colors"
        visible: true
        expanded: true
        icon: "palette"
        title: Translation.tr("Color Themes")

        SettingsGroup {
            id: themesGroup
            Layout.fillHeight: true

            property string searchQuery: ""
            property int selectedTab: Persistent.states?.settings?.themeTab ?? 0  // 0=All, 1=Dark, 2=Light
            onSelectedTabChanged: if (Persistent.ready && Persistent.states?.settings)
                Persistent.states.settings.themeTab = selectedTab
            property string selectedTag: Persistent.states?.settings?.themeTag ?? ""  // Single active tag filter
            onSelectedTagChanged: if (Persistent.ready && Persistent.states?.settings)
                Persistent.states.settings.themeTag = selectedTag
            property string activeSavedTheme: ""

            function isDarkTheme(preset) {
                if (preset.id === "auto" || preset.id === "custom") return true
                if (!preset.colors) return true
                const bg = preset.colors.m3background ?? Appearance.colors.colLayer0
                const r = parseInt(bg.slice(1, 3), 16) / 255
                const g = parseInt(bg.slice(3, 5), 16) / 255
                const b = parseInt(bg.slice(5, 7), 16) / 255
                return (0.299 * r + 0.587 * g + 0.114 * b) < 0.5
            }

            function toggleTag(tagId) {
                // Single selection: click same tag to deselect, different tag to switch
                selectedTag = (selectedTag === tagId) ? "" : tagId
            }

            readonly property var filteredPresets: {
                let result = []
                const favorites = Config.options?.appearance?.favoriteThemes ?? []
                const available = ThemePresets.presets.concat(root.savedThemePresets)
                for (let i = 0; i < available.length; i++) {
                    const preset = available[i]
                    // Dark/Light filter
                    if (selectedTab === 1 && !isDarkTheme(preset)) continue
                    if (selectedTab === 2 && isDarkTheme(preset)) continue
                    // Tag filter - single tag selection
                    if (selectedTag.length > 0) {
                        const presetTags = preset.tags ?? []
                        if (!presetTags.includes(selectedTag)) continue
                    }
                    // Search filter
                    if (searchQuery.length > 0) {
                        const query = searchQuery.toLowerCase()
                        const name = (preset.name ?? "").toLowerCase()
                        const desc = (preset.description ?? "").toLowerCase()
                        if (!name.includes(query) && !desc.includes(query)) continue
                    }
                    result.push(preset)
                }
                // Sort: favorites first
                const favoriteSet = new Set(favorites)
                result.sort((a, b) => {
                    const aFav = favoriteSet.has(a.id) ? 0 : 1
                    const bFav = favoriteSet.has(b.id) ? 0 : 1
                    return aFav - bFav
                })
                return result
            }
            readonly property var filteredSavedPresets: filteredPresets.filter(preset => preset.saved === true)
            readonly property var filteredBuiltInPresets: filteredPresets.filter(preset => preset.saved !== true)

            // Compact search + filter row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // Search
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 16
                    color: Appearance.colors.colLayer1
                    border.width: searchField.activeFocus ? 1.5 : 0
                    border.color: Appearance.colors.colPrimary

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 6

                        MaterialSymbol {
                            text: "search"
                            iconSize: 14
                            color: Appearance.colors.colSubtext
                        }

                        TextInput {
                            id: searchField
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.main
                            color: Appearance.colors.colOnLayer1
                            clip: true
                            onTextChanged: themesGroup.searchQuery = text

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Translation.tr("Search...")
                                font: parent.font
                                color: Appearance.colors.colSubtext
                                opacity: 0.6
                                visible: !parent.text && !parent.activeFocus
                            }
                        }

                        MaterialSymbol {
                            visible: searchField.text.length > 0
                            text: "close"
                            iconSize: 12
                            color: Appearance.colors.colSubtext

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: searchField.text = ""
                            }
                        }
                    }
                }

                // Soften colors toggle
                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: Config.options?.appearance?.softenColors ? Appearance.colors.colPrimary : Appearance.colors.colLayer1

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "opacity"
                        iconSize: 16
                        color: Config.options?.appearance?.softenColors ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                    }

                    MouseArea {
                        id: softenMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const val = !(Config.options?.appearance?.softenColors ?? true)
                            Config.setNestedValue("appearance.softenColors", val)
                            // Regenerate theme (for auto theme, regenerates from wallpaper)
                            ThemeService.regenerateAutoTheme()
                        }
                    }

                    StyledToolTip { text: Translation.tr("Soften colors (less intense)"); visible: softenMouse.containsMouse }
                }

                // Tab pills
                Row {
                    spacing: 4

                    Repeater {
                        model: [
                            { icon: "apps", tip: "All" },
                            { icon: "dark_mode", tip: "Dark" },
                            { icon: "light_mode", tip: "Light" }
                        ]

                        Rectangle {
                            required property var modelData
                            required property int index

                            width: 28
                            height: 28
                            radius: 14
                            color: themesGroup.selectedTab === index
                                ? Appearance.colors.colPrimary
                                : tabMouse.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: modelData.icon
                                iconSize: 14
                                color: themesGroup.selectedTab === index
                                    ? Appearance.colors.colOnPrimary
                                    : Appearance.colors.colOnLayer1
                            }

                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: themesGroup.selectedTab = index
                            }

                            StyledToolTip { text: modelData.tip; visible: tabMouse.containsMouse }
                        }
                    }
                }
            }

            // Tag filters
            Flow {
                id: tagFlow
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 4

                property bool hovered: false

                Repeater {
                    // Filter tags based on selectedTab (exclude dark/light since we have tabs)
                    model: ThemePresets.availableTags.filter(t => t.id !== "dark" && t.id !== "light")

                    Rectangle {
                        required property var modelData

                        readonly property bool isActive: themesGroup.selectedTag === modelData.id

                        width: tagRow.implicitWidth + 12
                        height: 24
                        radius: 12
                        color: isActive ? Appearance.colors.colPrimaryContainer
                             : tagMouse.containsMouse ? Appearance.colors.colLayer1Hover
                             : Appearance.colors.colLayer1

                        RowLayout {
                            id: tagRow
                            anchors.centerIn: parent
                            spacing: 3

                            MaterialSymbol {
                                text: modelData.icon
                                iconSize: 12
                                color: parent.parent.isActive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                text: modelData.name
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: parent.parent.isActive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                            }
                        }

                        MouseArea {
                            id: tagMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: themesGroup.toggleTag(modelData.id)
                            onContainsMouseChanged: tagFlow.hovered = containsMouse
                        }
                    }
                }

                // Clear tag button
                Rectangle {
                    visible: themesGroup.selectedTag.length > 0
                    width: 24
                    height: 24
                    radius: 12
                    color: clearMouse.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 12
                        color: Appearance.colors.colSubtext
                    }

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: themesGroup.selectedTag = ""
                    }

                    StyledToolTip { text: Translation.tr("Clear filter"); visible: clearMouse.containsMouse }
                }
            }

            // Quick Access - Favorites + Recent (unified)
            ColumnLayout {
                id: quickAccessSection
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 6

                // Compute quick access items: favorites first, then recent (excluding duplicates)
                readonly property var quickAccessItems: {
                    const favs = Config.options?.appearance?.favoriteThemes ?? []
                    const recent = Config.options?.appearance?.recentThemes ?? []

                    // Collect IDs: favorites first, then recent (excluding duplicates)
                    let ids = favs.slice()
                    let recentCount = 0
                    for (let i = 0; i < recent.length && recentCount < 4; i++) {
                        if (!favs.includes(recent[i])) {
                            ids.push(recent[i])
                            recentCount++
                        }
                    }

                    // Map to presets
                    const result = []
                    if (ids.length === 0)
                        return result
                    const presetById = new Map()
                    for (const preset of ThemePresets.presets) {
                        if (!presetById.has(preset.id))
                            presetById.set(preset.id, preset)
                    }
                    for (let i = 0; i < ids.length; i++) {
                        const preset = presetById.get(ids[i])
                        if (preset) result.push(preset)
                    }
                    return result
                }

                visible: quickAccessItems.length > 0 && themesGroup.selectedTag.length === 0 && themesGroup.searchQuery.length === 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    MaterialSymbol {
                        text: "bolt"
                        iconSize: 14
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        text: Translation.tr("Quick Access")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colSubtext
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        visible: (Config.options?.appearance?.favoriteThemes?.length ?? 0) > 0
                        text: "★ " + (Config.options?.appearance?.favoriteThemes?.length ?? 0)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colTertiary
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: quickAccessSection.quickAccessItems

                        ThemePresetCard {
                            required property var modelData
                            width: Math.min(160, (parent.width - 8) / 3)
                            preset: modelData
                            onClicked: ThemeService.setTheme(modelData.id)
                        }
                    }
                }
            }

            // Wallpaper Dominant Colors
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 4
                visible: Config.options?.background?.wallpaperPath?.length > 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    StyledText {
                        text: Translation.tr("Wallpaper Colors")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colSubtext
                    }

                    Item { Layout.fillWidth: true }

                    // Copy color button
                    StyledText {
                        text: Translation.tr("Click to copy")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        opacity: 0.6
                    }
                }

                ColorQuantizer {
                    id: wallpaperQuantizer
                    property string wallpaperPath: Config.options?.background?.wallpaperPath ?? ""
                    property bool isVideo: wallpaperPath.endsWith(".mp4") || wallpaperPath.endsWith(".webm")
                    source: wallpaperPath.length > 0 ? Qt.resolvedUrl(isVideo ? Config.options?.background?.thumbnailPath : wallpaperPath) : ""
                    depth: 3  // 2^3 = 8 colors
                    rescaleSize: 64
                }

                Row {
                    Layout.fillWidth: true
                    height: 28
                    Layout.preferredHeight: 28
                    Layout.minimumHeight: 28
                    spacing: 4

                    Repeater {
                        model: wallpaperQuantizer.colors ?? []

                        Rectangle {
                            required property var modelData
                            required property int index

                            width: (parent.width - 28) / 8
                            height: 28
                            radius: 6
                            color: modelData ?? "transparent"
                            border.width: colorMouse.containsMouse ? 2 : 0
                            border.color: Appearance.colors.colOnLayer1

                            MouseArea {
                                id: colorMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData) Quickshell.clipboardText = String(modelData).toUpperCase()
                                }
                            }

                            StyledToolTip {
                                text: modelData ? String(modelData).toUpperCase() : ""
                                visible: colorMouse.containsMouse && modelData
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 10
                spacing: 6
                visible: themesGroup.filteredSavedPresets.length > 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    MaterialSymbol {
                        text: "folder_special"
                        iconSize: 15
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: Translation.tr("Saved themes")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: themesGroup.filteredSavedPresets.length.toString()
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        text: Translation.tr("Created in Custom Theme Editor")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: themesGroup.filteredSavedPresets

                        ThemePresetCard {
                            required property var modelData
                            width: Math.max(140, (parent.width - 8) / 3)
                            preset: modelData
                            forceActive: themesGroup.activeSavedTheme === modelData.id
                            onClicked: root.applyThemeChoice(modelData)
                        }
                    }
                }
            }

            // Built-in theme grid - scrollable with 3 columns (expands to equalize Left/Right Bento columns)
            Rectangle {
                id: themeGridContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: 4
                readonly property real baseGridHeight: {
                    if (themesGroup.filteredBuiltInPresets.length === 0)
                        return 96
                    if (quickAccessSection.visible && themesGroup.filteredSavedPresets.length > 0)
                        return 96
                    if (quickAccessSection.visible || themesGroup.filteredSavedPresets.length > 0)
                        return 120
                    return 146
                }
                Layout.minimumHeight: baseGridHeight
                Layout.preferredHeight: baseGridHeight
                color: Appearance.colors.colLayer1
                radius: Appearance.rounding.small
                clip: true

                ScrollView {
                    id: themeScrollView
                    anchors.fill: parent
                    anchors.margins: 6
                    contentWidth: availableWidth
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ScrollBar.vertical.policy: themeGridContent.implicitHeight > parent.height - 12 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

                    Grid {
                        id: themeGridContent
                        width: themeScrollView.availableWidth
                        columns: 3
                        columnSpacing: 4
                        rowSpacing: 4

                        Repeater {
                            model: themesGroup.filteredBuiltInPresets

                            ThemePresetCard {
                                required property var modelData
                                width: (themeGridContent.width - themeGridContent.columnSpacing * 2) / 3
                                preset: modelData
                                forceActive: modelData.saved === true && themesGroup.activeSavedTheme === modelData.id
                                onClicked: root.applyThemeChoice(modelData)
                            }
                        }
                    }
                }

                // Empty state overlay
                MaterialPlaceholderMessage {
                    anchors.centerIn: parent
                    maximumWidth: 300
                    shown: themesGroup.filteredPresets.length === 0
                    icon: "search_off"
                    text: Translation.tr("No themes found")
                    explanation: themesGroup.searchQuery.length > 0
                        ? Translation.tr("Try a broader search or clear the filter")
                        : Translation.tr("Theme presets will appear here")
                    compact: true
                    shape: MaterialShape.Shape.Bun
                }
            }

            ConfigSwitch {
                buttonIcon: "invert_colors"
                text: Translation.tr("Invert colors (complementary)")
                checked: Config.options?.appearance?.colorInvert ?? false
                onCheckedChanged: Config.setNestedValue("appearance.colorInvert", checked)
                StyledToolTip {
                    text: Translation.tr("Use complementary shell colors; external apps retain their colors.")
                }
            }
        }
    }

    // ==================== HUB RIGHT: SCHEME VARIANT & TERMINAL COLORS ====================
SettingsCardSection {
    id: schemeVariantCard
    bentoColumn: "right"
    onWidthChanged: root._syncStandardBentoHeight()
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop
    Layout.fillWidth: true
    settingsTaskSection: "colors"
    visible: true
    expanded: true
    icon: "tune"
    title: Translation.tr("Scheme Variant & Terminals")

    SettingsGroup {
        ConfigSelectionArray {
            optionHorizontalPadding: 5
            optionIconSize: Appearance.font.pixelSize.smaller
            optionIconSpacing: 4
            currentValue: Config.options?.appearance?.palette?.type ?? "auto"
            onSelected: newValue => {
                Config.setNestedValue("appearance.palette.type", newValue)
                if (!ThemeService.isAutoTheme) {
                    const hex = MaterialThemeLoader.colorToHex(Appearance.m3colors.m3primary)
                    const mode = Appearance.m3colors.darkmode ? "dark" : "light"
                    MaterialThemeLoader.applySchemeVariant(hex, newValue, mode)
                }
            }
            options: [
                { "value": "auto", "displayName": Translation.tr("Auto"), "icon": "auto_awesome" },
                { "value": "scheme-content", "displayName": Translation.tr("Content"), "icon": "image" },
                { "value": "scheme-expressive", "displayName": Translation.tr("Expressive"), "icon": "flare" },
                { "value": "scheme-fidelity", "displayName": Translation.tr("Fidelity"), "icon": "verified" },
                { "value": "scheme-fruit-salad", "displayName": Translation.tr("Fruit Salad"), "icon": "local_florist" },
                { "value": "scheme-monochrome", "displayName": Translation.tr("Monochrome"), "icon": "filter_b_and_w" },
                { "value": "scheme-neutral", "displayName": Translation.tr("Neutral"), "icon": "tonality" },
                { "value": "scheme-rainbow", "displayName": Translation.tr("Rainbow"), "icon": "gradient" },
                { "value": "scheme-tonal-spot", "displayName": Translation.tr("Tonal Spot"), "icon": "palette" }
            ]
        }

        ConfigSwitch {
            buttonIcon: "contrast"
            text: Translation.tr("Auto light/dark from wallpaper")
            checked: Config.options?.appearance?.wallpaperTheming?.autoDarkLightMode ?? false
            onCheckedChanged: Config.setNestedValue("appearance.wallpaperTheming.autoDarkLightMode", checked)
        }

        SettingsDivider {}

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "terminal"
                text: Translation.tr("Sync colors to terminals & CLI tools")
                checked: Config.options?.appearance?.wallpaperTheming?.enableTerminal ?? true
                onCheckedChanged: Config.setNestedValue("appearance.wallpaperTheming.enableTerminal", checked)
            }

            DialogButton {
                visible: Config.options?.appearance?.wallpaperTheming?.enableTerminal ?? true
                buttonText: Translation.tr("Apply now")
                onClicked: applyTerminalColorsProcess.running = true

                Process {
                    id: applyTerminalColorsProcess
                    command: ["/usr/bin/bash", Directories.scriptsPath + "/colors/applycolor.sh"]
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 3
            visible: Config.options?.appearance?.wallpaperTheming?.enableTerminal ?? true

            Repeater {
                model: 16

                Rectangle {
                    required property int index
                    Layout.fillWidth: true
                    height: 18
                    radius: index === 0 || index === 15 ? 4 : 2
                    color: {
                        const isDark = Appearance.m3colors.darkmode;
                        const adj = Config.options?.appearance?.wallpaperTheming?.terminalColorAdjustments ?? {};
                        const sat = adj.saturation ?? 0.65;
                        const bright = adj.brightness ?? 0.60;
                        if (index === 0) return Appearance.m3colors.m3surfaceContainerLowest;
                        if (index === 7) return Appearance.m3colors.m3onSurfaceVariant;
                        if (index === 8) return Appearance.m3colors.m3outline;
                        if (index === 15) return Appearance.m3colors.m3onBackground;
                        const hues = [0, 0.98, 0.36, 0.12, 0.58, 0.85, 0.48, 0, 0, 0.98, 0.36, 0.12, 0.58, 0.85, 0.48, 0];
                        const isBright = index >= 9;
                        const l = isDark ? (isBright ? bright + 0.12 : bright) : (isBright ? (1 - bright) - 0.10 : (1 - bright));
                        const s = isBright ? sat + 0.08 : sat;
                        return Qt.hsla(hues[index], s, l, 1.0);
                    }
                }
            }
        }
    }
}

SettingsCardSection {
    id: motionSpeedCard
    bentoColumn: "right"
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop
    Layout.fillWidth: true
    settingsTaskSection: "colors"
    visible: (Config.options?.panelFamily ?? "ii") !== "waffle"
    expanded: true
    icon: "animation"
    title: Translation.tr("Motion & Animation Speed")

    SettingsGroup {
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ConfigSelectionArray {
                Layout.fillWidth: true
                currentValue: Config.options?.appearance?.iiMotionProfile ?? "classic"
                onSelected: newValue => Config.setNestedValue("appearance.iiMotionProfile", newValue)
                options: [
                    { displayName: Translation.tr("Classic"), icon: "motion_photos_paused", value: "classic" },
                    { displayName: Translation.tr("Contextual"), icon: "gesture", value: "contextual" }
                ]
            }

            DialogButton {
                buttonText: Translation.tr("Reset motion to defaults")
                onClicked: {
                    for (const key of ["movement", "enterExit", "clickBounce", "scroll"]) {
                        Config.setNestedValue(`appearance.animationSpeed.${key}`, 1.0)
                        Config.setNestedValue(`appearance.animationCurve.${key}`, "default")
                    }
                }
            }
        }

        SettingsSliderRow {
            icon: "speed"
            text: Translation.tr("Global animation speed")
            from: 0.5
            to: 2.0
            stepSize: 0.05
            value: Config.options?.appearance?.animationSpeed?.movement ?? 1.0
            displayValue: (Config.options?.appearance?.animationSpeed?.movement ?? 1.0).toFixed(2) + "x"
            onMoved: nextVal => {
                const rounded = Math.round(nextVal * 100) / 100
                for (const key of ["movement", "enterExit", "clickBounce", "scroll"])
                    Config.setNestedValue(`appearance.animationSpeed.${key}`, rounded)
            }
        }
    }
}

SettingsCardSection {
    id: iconThemeCard
    bentoColumn: "right"
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop
    Layout.fillWidth: true
    settingsTaskSection: "colors"
    visible: true
    expanded: true
    icon: "folder"
    title: Translation.tr("Icon Theme")

    SettingsGroup {
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 4

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("System (tray, apps)")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                }
                IconThemeSelector { mode: "system" }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 4

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Dock")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                }
                IconThemeSelector { mode: "dock" }
            }
        }
    }
}

SettingsCardSection {
    id: typographyCard
    bentoColumn: "left"
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop
    Layout.fillWidth: true
    settingsTaskSection: "colors"
    visible: true
    expanded: true
    icon: "text_format"
    title: Translation.tr("Typography")

    SettingsGroup {
        // Quick Presets first
        ContentSubsection {
            title: Translation.tr("Quick Presets")

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: StylePresets.presets

                    RippleButton {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 46
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.colors.colLayer1
                        colBackgroundHover: Appearance.colors.colLayer1Hover

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.icon
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnSurface
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.name
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                elide: Text.ElideRight
                            }
                        }

                        onClicked: StylePresets.applyPreset(modelData.id)
                        StyledToolTip { text: modelData.description; visible: parent.buttonHovered }
                    }
                }
            }
        }

        // Font Families
        ContentSubsection {
            title: Translation.tr("Font Families")

            ConfigRow {
                uniform: true

                FontSelector {
                    id: mainFontSelector
                    label: Translation.tr("Main")
                    icon: "font_download"
                    selectedFont: Config.options?.appearance?.typography?.mainFont ?? "Roboto Flex"
                    onSelectedFontChanged: {
                        if (Config.options?.appearance?.typography)
                            Config.setNestedValue("appearance.typography.mainFont", selectedFont)
                    }
                    Connections {
                        target: Config.options?.appearance?.typography ?? null
                        function onMainFontChanged() { mainFontSelector.selectedFont = Config.options.appearance.typography.mainFont }
                    }
                }

                FontSelector {
                    id: titleFontSelector
                    label: Translation.tr("Title")
                    icon: "title"
                    selectedFont: Config.options?.appearance?.typography?.titleFont ?? "Gabarito"
                    onSelectedFontChanged: {
                        if (Config.options?.appearance?.typography)
                            Config.setNestedValue("appearance.typography.titleFont", selectedFont)
                    }
                    Connections {
                        target: Config.options?.appearance?.typography ?? null
                        function onTitleFontChanged() { titleFontSelector.selectedFont = Config.options.appearance.typography.titleFont }
                    }
                }

                FontSelector {
                    id: monoFontSelector
                    label: Translation.tr("Mono")
                    icon: "terminal"
                    selectedFont: Config.options?.appearance?.typography?.monospaceFont ?? "JetBrains Mono NF"
                    onSelectedFontChanged: {
                        if (Config.options?.appearance?.typography)
                            Config.setNestedValue("appearance.typography.monospaceFont", selectedFont)
                    }
                    Connections {
                        target: Config.options?.appearance?.typography ?? null
                        function onMonospaceFontChanged() { monoFontSelector.selectedFont = Config.options.appearance.typography.monospaceFont }
                    }
                }
            }
        }

        // Size Scale + Reset button
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ConfigSpinBox {
                Layout.fillWidth: true
                icon: "format_size"
                text: Translation.tr("Size scale (%)")
                value: Math.round((Config.options?.appearance?.typography?.sizeScale ?? 1.0) * 100)
                from: 80
                to: 150
                stepSize: 5
                onValueChanged: {
                    if (Config.options?.appearance?.typography)
                        Config.setNestedValue("appearance.typography.sizeScale", value / 100)
                }
                StyledToolTip {
                    text: Translation.tr("Scale all text in the shell")
                }
            }

            RippleButtonWithIcon {
                buttonRadius: Appearance.rounding.full
                materialIcon: "restart_alt"
                mainText: Translation.tr("Reset typography to defaults")
                onClicked: StylePresets.resetTypographyToDefaults()
            }
        }
    }
}

SettingsCardSection {
    id: themeSchedulingCard
    bentoColumn: "right"
    _consumesBentoExtraHeight: true
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop
    Layout.fillWidth: true
    settingsTaskSection: "colors"
    visible: true
    expanded: true
    icon: "schedule"
    title: Translation.tr("Theme Scheduling")

    SettingsGroup {
        ConfigSwitch {
            buttonIcon: "schedule"
            text: Translation.tr("Enable automatic theme switching")
            checked: Config.options?.appearance?.themeSchedule?.enabled ?? false
            onCheckedChanged: Config.setNestedValue("appearance.themeSchedule.enabled", checked)
        }

        // Day theme + start time row
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol { Layout.alignment: Qt.AlignVCenter; text: "wb_sunny"; iconSize: 18; color: Appearance.colors.colSubtext }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                verticalAlignment: Text.AlignVCenter
                text: Translation.tr("Day theme")
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Item {
                Layout.preferredWidth: 124
                Layout.preferredHeight: 32

                RippleButton {
                    id: dayThemeBtn
                    anchors.fill: parent
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8

                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            verticalAlignment: Text.AlignVCenter
                            text: ThemePresets.presets.find(p => p.id === (Config.options?.appearance?.themeSchedule?.dayTheme ?? "auto"))?.name ?? "Auto"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            elide: Text.ElideRight
                        }
                        MaterialSymbol { Layout.alignment: Qt.AlignVCenter; text: dayThemePopup.visible ? "expand_less" : "expand_more"; iconSize: 14; color: Appearance.colors.colSubtext }
                    }

                    onClicked: dayThemePopup.visible ? dayThemePopup.close() : dayThemePopup.open()
                }

                Popup {
                    id: dayThemePopup
                    y: dayThemeBtn.height + 4
                    width: Math.max(150, parent.width)
                    height: Math.min(200, dayThemeList.contentHeight + 16)
                    padding: 8

                    background: Rectangle {
                        color: Appearance.colors.colLayer2Base
                        radius: Appearance.rounding.small
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                    }

                    ListView {
                        id: dayThemeList
                        anchors.fill: parent
                        clip: true
                        model: ThemePresets.presets

                        delegate: RippleButton {
                            required property var modelData
                            width: dayThemeList.width
                            implicitHeight: 28
                            colBackground: modelData.id === (Config.options?.appearance?.themeSchedule?.dayTheme ?? "auto") ? Appearance.colors.colPrimaryContainer : "transparent"
                            colBackgroundHover: Appearance.colors.colLayer1Hover

                            contentItem: StyledText {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                text: modelData.name
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                verticalAlignment: Text.AlignVCenter
                            }

                            onClicked: {
                                Config.setNestedValue("appearance.themeSchedule.dayTheme", modelData.id)
                                dayThemePopup.close()
                            }
                        }
                    }
                }
            }

            StyledSpinBox {
                id: dayHourSpin
                baseHeight: 32
                from: 0; to: 23
                value: parseInt((Config.options?.appearance?.themeSchedule?.dayStart ?? "06:00").split(":")[0]) || 6
                textFromValue: (v) => v.toString().padStart(2, '0')
                onValueChanged: Config.setNestedValue("appearance.themeSchedule.dayStart",
                    `${textFromValue(value)}:${dayMinSpin.textFromValue(dayMinSpin.value)}`)
                StyledToolTip { text: Translation.tr("Day starts at"); visible: dayHourSpin.hovered }
            }
            StyledText { Layout.alignment: Qt.AlignVCenter; verticalAlignment: Text.AlignVCenter; text: ":"; font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colSubtext }
            StyledSpinBox {
                id: dayMinSpin
                baseHeight: 32
                from: 0; to: 59; stepSize: 5
                value: parseInt((Config.options?.appearance?.themeSchedule?.dayStart ?? "06:00").split(":")[1]) || 0
                textFromValue: (v) => v.toString().padStart(2, '0')
                onValueChanged: Config.setNestedValue("appearance.themeSchedule.dayStart",
                    `${dayHourSpin.textFromValue(dayHourSpin.value)}:${textFromValue(value)}`)
                StyledToolTip { text: Translation.tr("Day starts at"); visible: dayMinSpin.hovered }
            }
        }

        // Night theme + start time row
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol { Layout.alignment: Qt.AlignVCenter; text: "bedtime"; iconSize: 18; color: Appearance.colors.colSubtext }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                verticalAlignment: Text.AlignVCenter
                text: Translation.tr("Night theme")
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Item {
                Layout.preferredWidth: 124
                Layout.preferredHeight: 32

                RippleButton {
                    id: nightThemeBtn
                    anchors.fill: parent
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8

                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            verticalAlignment: Text.AlignVCenter
                            text: ThemePresets.presets.find(p => p.id === (Config.options?.appearance?.themeSchedule?.nightTheme ?? "auto"))?.name ?? "Auto"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            elide: Text.ElideRight
                        }
                        MaterialSymbol { Layout.alignment: Qt.AlignVCenter; text: nightThemePopup.visible ? "expand_less" : "expand_more"; iconSize: 14; color: Appearance.colors.colSubtext }
                    }

                    onClicked: nightThemePopup.visible ? nightThemePopup.close() : nightThemePopup.open()
                }

                Popup {
                    id: nightThemePopup
                    y: nightThemeBtn.height + 4
                    width: Math.max(150, parent.width)
                    height: Math.min(200, nightThemeList.contentHeight + 16)
                    padding: 8

                    background: Rectangle {
                        color: Appearance.colors.colLayer2Base
                        radius: Appearance.rounding.small
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                    }

                    ListView {
                        id: nightThemeList
                        anchors.fill: parent
                        clip: true
                        model: ThemePresets.presets

                        delegate: RippleButton {
                            required property var modelData
                            width: nightThemeList.width
                            implicitHeight: 28
                            colBackground: modelData.id === (Config.options?.appearance?.themeSchedule?.nightTheme ?? "auto") ? Appearance.colors.colPrimaryContainer : "transparent"
                            colBackgroundHover: Appearance.colors.colLayer1Hover

                            contentItem: StyledText {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                text: modelData.name
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                verticalAlignment: Text.AlignVCenter
                            }

                            onClicked: {
                                Config.setNestedValue("appearance.themeSchedule.nightTheme", modelData.id)
                                nightThemePopup.close()
                            }
                        }
                    }
                }
            }

            StyledSpinBox {
                id: nightHourSpin
                baseHeight: 32
                from: 0; to: 23
                value: parseInt((Config.options?.appearance?.themeSchedule?.nightStart ?? "18:00").split(":")[0]) || 18
                textFromValue: (v) => v.toString().padStart(2, '0')
                onValueChanged: Config.setNestedValue("appearance.themeSchedule.nightStart",
                    `${textFromValue(value)}:${nightMinSpin.textFromValue(nightMinSpin.value)}`)
                StyledToolTip { text: Translation.tr("Night starts at"); visible: nightHourSpin.hovered }
            }
            StyledText { Layout.alignment: Qt.AlignVCenter; verticalAlignment: Text.AlignVCenter; text: ":"; font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colSubtext }
            StyledSpinBox {
                id: nightMinSpin
                baseHeight: 32
                from: 0; to: 59; stepSize: 5
                value: parseInt((Config.options?.appearance?.themeSchedule?.nightStart ?? "18:00").split(":")[1]) || 0
                textFromValue: (v) => v.toString().padStart(2, '0')
                onValueChanged: Config.setNestedValue("appearance.themeSchedule.nightStart",
                    `${nightHourSpin.textFromValue(nightHourSpin.value)}:${textFromValue(value)}`)
                StyledToolTip { text: Translation.tr("Night starts at"); visible: nightMinSpin.hovered }
            }
        }
    }
}
    }

    // ==================== CUSTOM THEME EDITOR ====================
    SettingsCardSection {
        id: customThemeEditorSection
        bentoColumn: "full"
        showHeader: false
        allowEditWithoutHeader: true
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "advanced"
        visible: true
        expanded: true
        icon: "edit"
        title: Translation.tr("Custom Theme Editor")

        Loader {
            id: customThemeEditorLoader
            Layout.fillWidth: true
            readonly property real desiredEditorHeight: Math.max(
                0,
                (customThemeEditorSection._effectiveCustomHeight > 0
                    ? customThemeEditorSection._effectiveCustomHeight
                    : root.effectiveColorsBentoHeight) - SettingsMaterialPreset.cardPadding * 2
            )
            active: Boolean(
                (root.activeSection === "advanced" || customThemeEditorSection._isForeignHosted || Boolean(customThemeEditorSection.moduleConfig?.targetSubTab))
                && customThemeEditorSection.visible
                && customThemeEditorSection.expanded
            )
            source: "CustomThemeEditor.qml"
            Binding {
                target: customThemeEditorLoader.item
                property: "targetEditorHeight"
                value: customThemeEditorLoader.desiredEditorHeight
                when: customThemeEditorLoader.status === Loader.Ready && customThemeEditorLoader.item !== null
            }
        }
    }
}
