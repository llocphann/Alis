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
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args)
    }

    settingsPageIndex: 4
    settingsPageName: Translation.tr("Themes")
    property string activeSection: "colors"

    onActiveSectionChanged: {
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

    // 01: Style & Presets
    SettingsCardSection {
        id: colorThemesCard
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "colors"
        visible: true
        expanded: true
        icon: "palette"
        title: Translation.tr("Color Themes")

        SettingsGroup {
            id: themesGroup

            property string searchQuery: ""
            property int selectedTab: Persistent.states?.settings?.themeTab ?? 0  // 0=All, 1=Dark, 2=Light
            onSelectedTabChanged: if (Persistent.ready && Persistent.states?.settings)
                Persistent.states.settings.themeTab = selectedTab
            property string selectedTag: Persistent.states?.settings?.themeTag ?? ""
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
                selectedTag = (selectedTag === tagId) ? "" : tagId
            }

            readonly property var filteredPresets: {
                let result = []
                const favorites = Config.options?.appearance?.favoriteThemes ?? []
                const available = ThemePresets.presets.concat(root.savedThemePresets)
                for (let i = 0; i < available.length; i++) {
                    const preset = available[i]
                    if (selectedTab === 1 && !isDarkTheme(preset)) continue
                    if (selectedTab === 2 && isDarkTheme(preset)) continue
                    if (selectedTag.length > 0) {
                        const presetTags = preset.tags ?? []
                        if (!presetTags.includes(selectedTag)) continue
                    }
                    if (searchQuery.length > 0) {
                        const query = searchQuery.toLowerCase()
                        const name = (preset.name ?? "").toLowerCase()
                        const desc = (preset.description ?? "").toLowerCase()
                        if (!name.includes(query) && !desc.includes(query)) continue
                    }
                    result.push(preset)
                }
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

            // iRiS Scheme row: Dark / Light / Auto mode + filter
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: "Color scheme"
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurface
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Filter curated presets or follow wallpaper brightness automatically"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }
                }

                Rectangle {
                    implicitWidth: schemeButtonsRow.implicitWidth + 6
                    implicitHeight: 34
                    radius: 10
                    color: SettingsMaterialPreset.controlSurface
                    border.width: 1
                    border.color: SettingsMaterialPreset.controlBorderColor

                    Row {
                        id: schemeButtonsRow
                        anchors.centerIn: parent
                        spacing: 3

                        Repeater {
                            model: [
                                { icon: "dark_mode", label: "Dark", tabIndex: 1 },
                                { icon: "light_mode", label: "Light", tabIndex: 2 },
                                { icon: "auto_awesome", label: "Auto", tabIndex: 0 }
                            ]

                            RippleButton {
                                required property var modelData
                                readonly property bool chosen: themesGroup.selectedTab === modelData.tabIndex
                                implicitWidth: schemeSegRow.implicitWidth + 18
                                implicitHeight: 28
                                buttonRadius: 7
                                toggled: chosen
                                colBackground: "transparent"
                                colBackgroundHover: SettingsMaterialPreset.controlSurfaceHover
                                colBackgroundToggled: SettingsMaterialPreset.pillSelectedColor
                                colBackgroundToggledHover: SettingsMaterialPreset.pillSelectedHoverColor
                                onClicked: themesGroup.selectedTab = modelData.tabIndex

                                contentItem: Item {
                                    implicitWidth: schemeSegRow.implicitWidth
                                    implicitHeight: schemeSegRow.implicitHeight
                                    Row {
                                        id: schemeSegRow
                                        anchors.centerIn: parent
                                        spacing: 5
                                        MaterialSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.icon
                                            iconSize: 14
                                            color: chosen ? SettingsMaterialPreset.pillSelectedTextColor : SettingsMaterialPreset.textColor
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.label
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: chosen ? Font.DemiBold : Font.Medium
                                            color: chosen ? SettingsMaterialPreset.pillSelectedTextColor : SettingsMaterialPreset.textColor
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            SettingsDivider {}

            // Search + Soften toggle + Tag pills
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: 10
                    color: SettingsMaterialPreset.controlSurface
                    border.width: searchField.activeFocus ? 1.5 : 1
                    border.color: searchField.activeFocus ? Appearance.colors.colPrimary : SettingsMaterialPreset.controlBorderColor

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 6

                        MaterialSymbol {
                            text: "search"
                            iconSize: 15
                            color: Appearance.colors.colSubtext
                        }

                        TextInput {
                            id: searchField
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.main
                            color: SettingsMaterialPreset.textColor
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
                            iconSize: 13
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

                RippleButton {
                    id: softenBtn
                    implicitWidth: softenBtnRow.implicitWidth + 20
                    implicitHeight: 34
                    buttonRadius: 10
                    toggled: Config.options?.appearance?.softenColors ?? true
                    colBackground: SettingsMaterialPreset.controlSurface
                    colBackgroundHover: SettingsMaterialPreset.controlSurfaceHover
                    colBackgroundToggled: SettingsMaterialPreset.pillSelectedColor
                    colBackgroundToggledHover: SettingsMaterialPreset.pillSelectedHoverColor
                    onClicked: {
                        const val = !(Config.options?.appearance?.softenColors ?? true)
                        Config.setNestedValue("appearance.softenColors", val)
                        ThemeService.regenerateAutoTheme()
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: softenBtn.buttonEffectiveRadius
                        color: "transparent"
                        border.width: 1
                        border.color: softenBtn.toggled ? SettingsMaterialPreset.accentBorder : SettingsMaterialPreset.controlBorderColor
                        z: 1
                    }
                    contentItem: Item {
                        implicitWidth: softenBtnRow.implicitWidth
                        implicitHeight: softenBtnRow.implicitHeight
                        Row {
                            id: softenBtnRow
                            anchors.centerIn: parent
                            spacing: 5
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "opacity"
                                iconSize: 15
                                color: softenBtn.toggled
                                    ? SettingsMaterialPreset.pillSelectedTextColor
                                    : SettingsMaterialPreset.textColor
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Translation.tr("Soften")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: softenBtn.toggled ? Font.DemiBold : Font.Medium
                                color: softenBtn.toggled
                                    ? SettingsMaterialPreset.pillSelectedTextColor
                                    : SettingsMaterialPreset.textColor
                            }
                        }
                    }
                    StyledToolTip { text: Translation.tr("Soften colors (less intense)"); visible: parent.buttonHovered }
                }
            }

            Rectangle {
                id: tagTrack
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                implicitHeight: tagFlow.implicitHeight + 6
                radius: 10
                color: SettingsMaterialPreset.controlSurface
                border.width: 1
                border.color: SettingsMaterialPreset.controlBorderColor

                readonly property var filterTags: [
                    { id: "", name: Translation.tr("All"), icon: "apps" }
                ].concat(ThemePresets.availableTags.filter(t => t.id !== "dark" && t.id !== "light"))

                TextMetrics {
                    id: tagMetrics
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    text: {
                        let longest = ""
                        const items = tagTrack.filterTags
                        for (let i = 0; i < items.length; ++i) {
                            const lbl = String(items[i]?.name ?? "")
                            if (lbl.length > longest.length)
                                longest = lbl
                        }
                        return longest
                    }
                }

                Flow {
                    id: tagFlow
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: 3
                    }
                    spacing: 3

                    readonly property int tagCount: Math.max(1, tagTrack.filterTags.length)
                    readonly property int availWidth: Math.max(tagCount, Math.floor(width))
                    readonly property real minTagWidth: Math.max(
                        Math.round(58 * Appearance.fontSizeScale),
                        Math.ceil(tagMetrics.advanceWidth) + 13 + 4 + 16
                    )
                    readonly property int rowCount: {
                        const maxFit = Math.max(1, Math.floor((availWidth + spacing) / (minTagWidth + spacing)))
                        return Math.max(1, Math.ceil(tagCount / maxFit))
                    }

                    Repeater {
                        model: tagTrack.filterTags

                        RippleButton {
                            id: tagBtn
                            required property var modelData
                            required property int index
                            readonly property bool isActive: modelData.id === ""
                                ? themesGroup.selectedTag.length === 0
                                : themesGroup.selectedTag === modelData.id

                            width: {
                                const count = tagFlow.tagCount
                                const rows = tagFlow.rowCount
                                const basePerRow = Math.floor(count / rows)
                                const extraRows = count % rows
                                const cutoff = extraRows * (basePerRow + 1)
                                let itemsInRow = basePerRow
                                let posInRow = 0
                                if (index < cutoff) {
                                    itemsInRow = basePerRow + 1
                                    posInRow = index % itemsInRow
                                } else {
                                    itemsInRow = Math.max(1, basePerRow)
                                    posInRow = (index - cutoff) % itemsInRow
                                }
                                const avail = Math.max(itemsInRow, tagFlow.availWidth - tagFlow.spacing * (itemsInRow - 1))
                                const base = Math.floor(avail / itemsInRow)
                                return posInRow === itemsInRow - 1
                                    ? Math.max(1, avail - base * (itemsInRow - 1))
                                    : Math.max(1, base)
                            }
                            implicitHeight: Math.round(28 * Appearance.fontSizeScale)
                            buttonRadius: 7
                            toggled: isActive
                            colBackground: "transparent"
                            colBackgroundHover: SettingsMaterialPreset.controlSurfaceHover
                            colBackgroundToggled: SettingsMaterialPreset.pillSelectedColor
                            colBackgroundToggledHover: SettingsMaterialPreset.pillSelectedHoverColor
                            onClicked: {
                                if (modelData.id === "")
                                    themesGroup.selectedTag = ""
                                else
                                    themesGroup.toggleTag(modelData.id)
                            }

                            contentItem: Item {
                                implicitWidth: tagRow.implicitWidth
                                implicitHeight: tagRow.implicitHeight
                                Row {
                                    id: tagRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: tagBtn.modelData.icon
                                        iconSize: 13
                                        color: tagBtn.isActive ? SettingsMaterialPreset.pillSelectedTextColor : SettingsMaterialPreset.textColor
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: tagBtn.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: tagBtn.isActive ? Font.DemiBold : Font.Medium
                                        color: tagBtn.isActive ? SettingsMaterialPreset.pillSelectedTextColor : SettingsMaterialPreset.textColor
                                        elide: Text.ElideRight
                                        width: Math.min(implicitWidth, Math.max(20, tagBtn.width - 28))
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Quick Access - Favorites + Recent
            ColumnLayout {
                id: quickAccessSection
                Layout.fillWidth: true
                spacing: 6

                readonly property var quickAccessItems: {
                    const favs = Config.options?.appearance?.favoriteThemes ?? []
                    const recent = Config.options?.appearance?.recentThemes ?? []

                    let ids = favs.slice()
                    let recentCount = 0
                    for (let i = 0; i < recent.length && recentCount < 4; i++) {
                        if (!favs.includes(recent[i])) {
                            ids.push(recent[i])
                            recentCount++
                        }
                    }

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

                Grid {
                    id: quickAccessGrid
                    Layout.fillWidth: true
                    columns: width >= 600 ? 3 : 2
                    columnSpacing: 6
                    rowSpacing: 6

                    Repeater {
                        model: quickAccessSection.quickAccessItems

                        ThemePresetCard {
                            required property var modelData
                            required property int index
                            readonly property real _baseW: Math.floor((quickAccessGrid.width - quickAccessGrid.columnSpacing * (quickAccessGrid.columns - 1)) / quickAccessGrid.columns)
                            width: (index % quickAccessGrid.columns === quickAccessGrid.columns - 1)
                                ? Math.max(_baseW, Math.floor(quickAccessGrid.width) - quickAccessGrid.columnSpacing * (quickAccessGrid.columns - 1) - _baseW * (quickAccessGrid.columns - 1))
                                : _baseW
                            preset: modelData
                            onClicked: ThemeService.setTheme(modelData.id)
                        }
                    }
                }
            }

            // Wallpaper Dominant Colors
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: (Config.options?.background?.wallpaperPath?.length ?? 0) > 0

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
                    depth: 3
                    rescaleSize: 64
                }

                Row {
                    Layout.fillWidth: true
                    height: 28
                    Layout.preferredHeight: 28
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

            // Saved custom themes
            ColumnLayout {
                Layout.fillWidth: true
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

                Grid {
                    id: savedThemesGrid
                    Layout.fillWidth: true
                    columns: width >= 600 ? 3 : 2
                    columnSpacing: 6
                    rowSpacing: 6

                    Repeater {
                        model: themesGroup.filteredSavedPresets

                        ThemePresetCard {
                            required property var modelData
                            required property int index
                            readonly property real _baseW: Math.floor((savedThemesGrid.width - savedThemesGrid.columnSpacing * (savedThemesGrid.columns - 1)) / savedThemesGrid.columns)
                            width: (index % savedThemesGrid.columns === savedThemesGrid.columns - 1)
                                ? Math.max(_baseW, Math.floor(savedThemesGrid.width) - savedThemesGrid.columnSpacing * (savedThemesGrid.columns - 1) - _baseW * (savedThemesGrid.columns - 1))
                                : _baseW
                            preset: modelData
                            forceActive: themesGroup.activeSavedTheme === modelData.id
                            onClicked: root.applyThemeChoice(modelData)
                        }
                    }
                }
            }

            SettingsDivider {}

            // Curated presets specimen grid — full natural height, zero inner scroll trap
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    text: "Style › Presets"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Medium
                    color: Appearance.colors.colSubtext
                }

                Grid {
                    id: themeGridContent
                    Layout.fillWidth: true
                    visible: themesGroup.filteredBuiltInPresets.length > 0
                    columns: width >= 600 ? 3 : 2
                    columnSpacing: 6
                    rowSpacing: 6

                    Repeater {
                        model: themesGroup.filteredBuiltInPresets

                        ThemePresetCard {
                            required property var modelData
                            required property int index
                            readonly property real _baseW: Math.floor((themeGridContent.width - themeGridContent.columnSpacing * (themeGridContent.columns - 1)) / themeGridContent.columns)
                            width: (index % themeGridContent.columns === themeGridContent.columns - 1)
                                ? Math.max(_baseW, Math.floor(themeGridContent.width) - themeGridContent.columnSpacing * (themeGridContent.columns - 1) - _baseW * (themeGridContent.columns - 1))
                                : _baseW
                            preset: modelData
                            forceActive: modelData.saved === true && themesGroup.activeSavedTheme === modelData.id
                            onClicked: root.applyThemeChoice(modelData)
                        }
                    }
                }

                MaterialPlaceholderMessage {
                    Layout.alignment: Qt.AlignHCenter
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

            SettingsDivider {}

            GridLayout {
                Layout.fillWidth: true
                columns: width >= 460 ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: 12
                rowSpacing: 8

                ConfigSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    buttonIcon: "contrast"
                    text: Translation.tr("Auto light/dark from wallpaper")
                    checked: Config.options?.appearance?.wallpaperTheming?.autoDarkLightMode ?? false
                    onCheckedChanged: Config.setNestedValue("appearance.wallpaperTheming.autoDarkLightMode", checked)
                }

                ConfigSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
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
    }

    // 02: Palette Generation & Terminals
    SettingsCardSection {
        id: schemeVariantCard
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "colors"
        visible: true
        expanded: true
        icon: "tune"
        title: Translation.tr("Scheme Variant & Terminals")

        SettingsGroup {
            id: schemeVariantGroup

            ContentSubsection {
                title: Translation.tr("Palette generation")

                ConfigSelectionArray {
                    fillWidthSegments: true
                    optionHorizontalPadding: 6
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
            }

            ConfigSwitch {
                buttonIcon: "format_color_fill"
                text: Translation.tr("Extra surface tint")
                checked: Config.options?.appearance?.extraBackgroundTint ?? true
                onCheckedChanged: Config.setNestedValue("appearance.extraBackgroundTint", checked)
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
                            const isDark = Appearance.m3colors.darkmode
                            const adj = Config.options?.appearance?.wallpaperTheming?.terminalColorAdjustments ?? {}
                            const sat = adj.saturation ?? 0.65
                            const bright = adj.brightness ?? 0.60
                            if (index === 0) return Appearance.m3colors.m3surfaceContainerLowest
                            if (index === 7) return Appearance.m3colors.m3onSurfaceVariant
                            if (index === 8) return Appearance.m3colors.m3outline
                            if (index === 15) return Appearance.m3colors.m3onBackground
                            const hues = [0, 0.98, 0.36, 0.12, 0.58, 0.85, 0.48, 0, 0, 0.98, 0.36, 0.12, 0.58, 0.85, 0.48, 0]
                            const isBright = index >= 9
                            const l = isDark ? (isBright ? bright + 0.12 : bright) : (isBright ? (1 - bright) - 0.10 : (1 - bright))
                            const s = isBright ? sat + 0.08 : sat
                            return Qt.hsla(hues[index], s, l, 1.0)
                        }
                    }
                }
            }

            Grid {
                id: terminalTargetsGrid
                Layout.fillWidth: true
                enabled: Config.options?.appearance?.wallpaperTheming?.enableTerminal ?? true
                opacity: enabled ? 1.0 : 0.5
                columns: width >= 460 ? 3 : 2
                columnSpacing: 6
                rowSpacing: 6

                Repeater {
                    model: [
                        { key: "kitty", label: "Kitty", icon: "terminal" },
                        { key: "foot", label: "Foot", icon: "terminal" },
                        { key: "ghostty", label: "Ghostty", icon: "terminal" },
                        { key: "alacritty", label: "Alacritty", icon: "terminal" },
                        { key: "wezterm", label: "WezTerm", icon: "terminal" },
                        { key: "konsole", label: "Konsole", icon: "terminal" },
                        { key: "starship", label: "Starship", icon: "rocket_launch" },
                        { key: "btop", label: "btop", icon: "monitoring" },
                        { key: "yazi", label: "Yazi", icon: "folder" }
                    ]

                    RippleButton {
                        required property var modelData
                        required property int index
                        readonly property bool targetEnabled: Config.options?.appearance?.wallpaperTheming?.terminals?.[modelData.key] ?? true
                        readonly property real _baseW: Math.floor((terminalTargetsGrid.width - terminalTargetsGrid.columnSpacing * (terminalTargetsGrid.columns - 1)) / terminalTargetsGrid.columns)
                        width: (index % terminalTargetsGrid.columns === terminalTargetsGrid.columns - 1)
                            ? Math.max(_baseW, Math.floor(terminalTargetsGrid.width) - terminalTargetsGrid.columnSpacing * (terminalTargetsGrid.columns - 1) - _baseW * (terminalTargetsGrid.columns - 1))
                            : _baseW
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.verysmall
                        toggled: targetEnabled
                        colBackground: targetEnabled ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
                        colBackgroundHover: targetEnabled ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
                        onClicked: Config.setNestedValue(`appearance.wallpaperTheming.terminals.${modelData.key}`, !targetEnabled)

                        contentItem: Item {
                            implicitWidth: termChipRow.implicitWidth
                            implicitHeight: termChipRow.implicitHeight
                            Row {
                                id: termChipRow
                                anchors.centerIn: parent
                                spacing: 5
                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: targetEnabled ? "check_circle" : modelData.icon
                                    iconSize: 14
                                    color: targetEnabled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: targetEnabled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 03: Typography
    SettingsCardSection {
        id: typographyCard
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "colors"
        visible: true
        expanded: true
        icon: "text_format"
        title: Translation.tr("Typography")

        SettingsGroup {
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

            SettingsDivider {}

            ContentSubsection {
                title: Translation.tr("Font Families")

                GridLayout {
                    id: familyGrid
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    columnSpacing: 8
                    rowSpacing: 8
                    uniformCellWidths: columns === 3 && width >= 3 * Math.max(mainFontSelector.readableWidth,
                        titleFontSelector.readableWidth, monoFontSelector.readableWidth) + 2 * columnSpacing
                    readonly property real firstPairWidth: mainFontSelector.readableWidth
                        + titleFontSelector.readableWidth + columnSpacing
                    columns: width >= firstPairWidth + monoFontSelector.readableWidth + columnSpacing ? 3
                        : width >= firstPairWidth ? 2 : 1

                    component FamilySelector: FontSelector {
                        // FontSelector's trigger places its content inside 12px and 8px side margins.
                        readonly property real readableWidth: implicitWidth + 20
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: readableWidth

                        HoverHandler { id: fontHover }
                        StyledToolTip {
                            extraVisibleCondition: false
                            alternativeVisibleCondition: fontHover.hovered && parent.width < parent.readableWidth
                            text: parent.selectedFont
                        }
                    }

                    FamilySelector {
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

                    FamilySelector {
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

                    FamilySelector {
                        id: monoFontSelector
                        Layout.columnSpan: familyGrid.columns === 2 ? 2 : 1
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

            SettingsDivider {}

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
                    onValueModified: v => {
                        if (Config.options?.appearance?.typography)
                            Config.setNestedValue("appearance.typography.sizeScale", v / 100)
                    }
                    StyledToolTip {
                        text: Translation.tr("Scale all text in the shell")
                    }
                }

                RippleButtonWithIcon {
                    buttonRadius: Appearance.rounding.full
                    materialIcon: "restart_alt"
                    mainText: Translation.tr("Reset defaults")
                    onClicked: StylePresets.resetTypographyToDefaults()
                }
            }
        }
    }

    // 04: Motion & Animation Speed
    SettingsCardSection {
        id: motionSpeedCard
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
                    fillWidthSegments: true
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

            SettingsDivider {}

            SettingsPresetRow {
                icon: "speed"
                text: Translation.tr("Global animation speed")
                from: 0.5
                to: 2.0
                stepSize: 0.05
                value: Config.options?.appearance?.animationSpeed?.movement ?? 1.0
                displayValue: Number(liveValue).toFixed(2) + "×"
                presets: [
                    { label: "0.5×", value: 0.5 },
                    { label: "0.75×", value: 0.75 },
                    { label: "1.0×", value: 1.0 },
                    { label: "1.25×", value: 1.25 },
                    { label: "1.5×", value: 1.5 },
                    { label: "2.0×", value: 2.0 }
                ]
                onMoved: nextVal => {
                    const rounded = Math.round(nextVal * 100) / 100
                    for (const key of ["movement", "enterExit", "clickBounce", "scroll"])
                        Config.setNestedValue(`appearance.animationSpeed.${key}`, rounded)
                }
            }
        }
    }

    // 05: Icon Theme
    SettingsCardSection {
        id: iconThemeCard
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
                spacing: 12

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

    // 06: Theme Scheduling
    SettingsCardSection {
        id: themeSchedulingCard
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

            SettingsDivider {}

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol { Layout.alignment: Qt.AlignVCenter; text: "wb_sunny"; iconSize: 18; color: Appearance.colors.colSubtext }
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Translation.tr("Day theme")
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Item {
                    Layout.preferredWidth: 164
                    Layout.preferredHeight: 32

                    RippleButton {
                        id: dayThemeBtn
                        anchors.fill: parent
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
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
                        width: Math.max(164, parent.width)
                        height: Math.min(220, dayThemeList.contentHeight + 16)
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

            SettingsDivider {}

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol { Layout.alignment: Qt.AlignVCenter; text: "bedtime"; iconSize: 18; color: Appearance.colors.colSubtext }
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Translation.tr("Night theme")
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Item {
                    Layout.preferredWidth: 164
                    Layout.preferredHeight: 32

                    RippleButton {
                        id: nightThemeBtn
                        anchors.fill: parent
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
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
                        width: Math.max(164, parent.width)
                        height: Math.min(220, nightThemeList.contentHeight + 16)
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

    // Custom Theme Editor ("advanced" tab) — full natural height, zero inner Flickable clamp
    SettingsCardSection {
        id: customThemeEditorSection
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
            active: Boolean(
                (root.activeSection === "advanced" || customThemeEditorSection._isForeignHosted || Boolean(customThemeEditorSection.moduleConfig?.targetSubTab))
                && customThemeEditorSection.visible
                && customThemeEditorSection.expanded
            )
            source: "CustomThemeEditor.qml"
        }
    }
}
