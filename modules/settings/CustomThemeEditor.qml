import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

SettingsGroup {
    id: root
    Layout.fillWidth: true

    // Themes directory
    readonly property string themesDir: Directories.shellConfig + "/themes"
    property var savedThemesList: []
    property string saveStatus: "" // "", "saving", "saved", "error"
    property bool detailedColorsExpanded: false
    property string _harmonyScheme: "complementary"
    property real targetEditorHeight: 0
    readonly property real targetGridHeight: Math.max(0, root.targetEditorHeight - SettingsMaterialPreset.groupPadding * 2)
    readonly property real bottomRowsHeight: {
        const row1H = Math.max(secondaryCard.implicitHeight, tertiaryCard.implicitHeight)
        const row2H = Math.max(backgroundsCard.implicitHeight, surfaceContainersCard.implicitHeight)
        const row3H = Math.max(bordersShadowsCard.implicitHeight, statusColorsCard.implicitHeight)
        const dialogsH = (exportDialog.visible ? (exportDialog.implicitHeight + mainGrid.rowSpacing) : 0)
            + (importDialog.visible ? (importDialog.implicitHeight + mainGrid.rowSpacing) : 0)
        return row1H + row2H + row3H + mainGrid.rowSpacing * 3 + dialogsH
    }
    readonly property real rightTopNaturalHeight: quickAdjustCard.implicitHeight + harmonyCard.implicitHeight + accentColorsCard.implicitHeight + rightTopColumn.spacing * 2
    readonly property real targetRow0Height: mainGrid.columns === 2 && root.targetGridHeight > 0
        ? Math.max(rightTopNaturalHeight, root.targetGridHeight - bottomRowsHeight)
        : 0

    Component.onCompleted: {
        // Ensure themes directory exists
        ensureDirProcess.running = true
    }

    Process {
        id: ensureDirProcess
        command: ["/usr/bin/mkdir", "-p", root.themesDir]
        onExited: (exitCode) => {
            if (exitCode === 0) loadThemesList()
        }
    }

    function loadThemesList() {
        listThemesProcess.running = true
    }

    Process {
        id: listThemesProcess
        command: ["/usr/bin/bash", "-c", `/usr/bin/ls -1 "${root.themesDir}"/*.json 2>/dev/null | /usr/bin/xargs -I{} /usr/bin/basename {} .json`]
        stdout: SplitParser {
            onRead: data => {
                if (data.trim()) {
                    root.savedThemesList = [...root.savedThemesList, data.trim()]
                }
            }
        }
        onStarted: root.savedThemesList = []
    }

    function saveTheme(name) {
        name = normalizedThemeName(name)
        if (!name) return
        root.saveStatus = "saving"
        const jsonStr = JSON.stringify(Config.options.appearance.customTheme, null, 2)
        const escaped = jsonStr.replace(/'/g, "'\\''")
        const filePath = `${root.themesDir}/${name}.json`
        saveThemeProcess.command = ["/usr/bin/bash", "-c", `printf '%s' '${escaped}' > "${filePath}"`]
        saveThemeProcess.running = true
    }

    function normalizedThemeName(name) {
        const clean = String(name ?? "").trim().replace(/[^a-zA-Z0-9 _.-]/g, "").replace(/^\.+$/, "")
        return clean.substring(0, 64)
    }

    Process {
        id: saveThemeProcess
        onExited: (exitCode) => {
            if (exitCode === 0) {
                root.saveStatus = "saved"
                loadThemesList()
                saveStatusTimer.restart()
            } else {
                root.saveStatus = "error"
                saveStatusTimer.restart()
            }
        }
    }

    Timer {
        id: saveStatusTimer
        interval: 2000
        onTriggered: root.saveStatus = ""
    }

    function loadTheme(name) {
        loadThemeFileView.path = `${root.themesDir}/${name}.json`
    }

    FileView {
        id: loadThemeFileView
        path: ""
        onLoaded: {
            try {
                const theme = JSON.parse(text())
                const customTheme = Config.options?.appearance?.customTheme ?? {}
                const updates = ({})
                for (let key in theme) {
                    if (customTheme.hasOwnProperty(key))
                        updates[`appearance.customTheme.${key}`] = theme[key]
                }
                Config.setNestedValues(updates)
                root.applyToShell()
            } catch (e) {
                console.error("[CustomThemeEditor] Failed to load theme:", e)
            }
        }
    }

    function deleteTheme(name) {
        deleteThemeProcess.command = ["/usr/bin/rm", "-f", `${root.themesDir}/${name}.json`]
        deleteThemeProcess.running = true
    }

    Process {
        id: deleteThemeProcess
        onExited: loadThemesList()
    }

    function applyToShell() {
        // Force re-application by triggering a change
        ThemePresets.applyPreset("custom")
        // Also ensure ThemeService knows we're on custom
        if (ThemeService.currentTheme !== "custom") {
            ThemeService.setTheme("custom")
        }
    }

    // Invert colors for light/dark mode switch
    function invertColorsForMode(toLightMode) {
        const ct = Config.options?.appearance?.customTheme ?? ({})
        const next = JSON.parse(JSON.stringify(ct))

        // Swap background and foreground colors
        const swaps = [
            ["m3background", "m3onBackground"],
            ["m3surface", "m3onSurface"],
            ["m3surfaceContainerLowest", "m3surfaceContainerHighest"],
            ["m3surfaceContainerLow", "m3surfaceContainerHigh"],
        ]

        swaps.forEach(([a, b]) => {
            const temp = next[a]
            next[a] = next[b]
            next[b] = temp
        })

        // Adjust surface containers to create proper gradient
        if (toLightMode) {
            // Light mode: lighten backgrounds
            next.m3surfaceDim = String(ColorUtils.lighten(next.m3surfaceDim, 0.7))
            next.m3surfaceBright = String(Appearance.colors.colLayer3)
            next.m3surfaceContainer = String(ColorUtils.lighten(next.m3surfaceContainer, 0.6))
        } else {
            // Dark mode: darken backgrounds
            next.m3surfaceDim = String(ColorUtils.darken(next.m3surfaceDim, 0.7))
            next.m3surfaceBright = String(ColorUtils.darken(next.m3surfaceBright, 0.5))
            next.m3surfaceContainer = String(ColorUtils.darken(next.m3surfaceContainer, 0.6))
        }

        next.darkmode = !toLightMode
        const updates = ({})
        for (const key in next)
            updates[`appearance.customTheme.${key}`] = next[key]
        Config.setNestedValues(updates)
        applyToShell()
    }

    // Preset categories for dropdown
    readonly property var presetCategories: [
        { name: "Angel (Dark)", colors: ThemePresets.angelColors },
        { name: "Angel (Light)", colors: ThemePresets.angelLightColors },
        { name: "Regalia", colors: ThemePresets.regaliaColors },
        { name: "Regalia Ivory", colors: ThemePresets.regaliaIvoryColors },
        { name: "Gruvbox Material", colors: ThemePresets.gruvboxMaterialColors },
        { name: "Catppuccin Mocha", colors: ThemePresets.catppuccinMochaColors },
        { name: "Catppuccin Latte", colors: ThemePresets.catppuccinLatteColors },
        { name: "Nord", colors: ThemePresets.nordColors },
        { name: "Material Black", colors: ThemePresets.materialBlackColors },
        { name: "Kanagawa", colors: ThemePresets.kanagawaColors },
        { name: "Kanagawa Dragon", colors: ThemePresets.kanagawaDragonColors },
        { name: "Samurai", colors: ThemePresets.samuraiColors },
        { name: "Tokyo Night", colors: ThemePresets.tokyoNightColors },
        { name: "Sakura", colors: ThemePresets.sakuraColors },
        { name: "Zen Garden", colors: ThemePresets.zenGardenColors }
    ]
    property string selectedPresetName: ""

    // Store original colors for quick adjustments
    property var originalColors: null

    // Debounce timer for quick adjustments
    Timer {
        id: adjustDebounce
        interval: 50
        onTriggered: root.applyQuickAdjustments()
    }

    function captureOriginalColors() {
        if (!originalColors) {
            originalColors = JSON.parse(JSON.stringify(Config.options?.appearance?.customTheme ?? {}))
        }
    }

    function applyQuickAdjustments() {
        captureOriginalColors()
        const satFactor = saturationSlider.value / 100
        const brightDelta = brightnessSlider.value / 100
        const tempDelta = temperatureSlider.value / 100  // -0.5 to 0.5

        // Apply to all color keys
        const colorKeys = Object.keys(originalColors)

        const updates = ({})
        for (const key of colorKeys) {
            if (!key.startsWith("m3"))
                continue
            const original = originalColors[key]
            if (typeof original !== "string" || !original.startsWith("#"))
                continue
            let c = Qt.color(original)
            // Adjust saturation
            let newSat = Math.min(1, Math.max(0, c.hslSaturation * satFactor))
            // Adjust brightness (lightness)
            let newLight = Math.min(1, Math.max(0, c.hslLightness + brightDelta))
            // Adjust temperature (hue shift toward warm/cool)
            let newHue = c.hslHue
            if (tempDelta !== 0) {
                // Warm = shift toward orange (0.08), Cool = shift toward blue (0.58)
                const targetHue = tempDelta > 0 ? 0.08 : 0.58
                const shiftAmount = Math.abs(tempDelta) * 0.15
                newHue = c.hslHue + (targetHue - c.hslHue) * shiftAmount
                if (newHue < 0) newHue += 1
                if (newHue > 1) newHue -= 1
            }
            let newColor = Qt.hsla(newHue, newSat, newLight, c.a)
            updates[`appearance.customTheme.${key}`] = newColor.toString()
        }
        Config.setNestedValues(updates)
        applyToShell()
    }

    function getHarmonyColor(role) {
        const primary = Config.options?.appearance?.customTheme?.m3primary ?? Appearance.m3colors.m3primary
        const scheme = root._harmonyScheme

        if (scheme === "complementary") {
            const comp = ColorUtils.complementary(primary)
            return role === "secondary" ? comp : ColorUtils.shiftHue(comp, 30)
        } else if (scheme === "analogous") {
            const colors = ColorUtils.analogous(primary, 30)
            return role === "secondary" ? colors[0] : colors[1]
        } else if (scheme === "triadic") {
            const colors = ColorUtils.triadic(primary)
            return role === "secondary" ? colors[0] : colors[1]
        } else if (scheme === "split") {
            const colors = ColorUtils.splitComplementary(primary)
            return role === "secondary" ? colors[0] : colors[1]
        }
        return primary
    }

    function applyHarmonyColors(): void {
        const secondary = getHarmonyColor("secondary")
        const tertiary = getHarmonyColor("tertiary")

        Config.setNestedValue('appearance.customTheme.m3secondary', secondary.toString())
        Config.setNestedValue('appearance.customTheme.m3onSecondary', ColorUtils.contrastColor(secondary).toString())
        const secondaryContainer = ColorUtils.colorWithLightness(secondary, (Config.options?.appearance?.customTheme?.darkmode ?? true) ? 0.25 : 0.85)
        Config.setNestedValue('appearance.customTheme.m3secondaryContainer', secondaryContainer.toString())
        Config.setNestedValue('appearance.customTheme.m3onSecondaryContainer', ColorUtils.contrastColor(secondaryContainer).toString())

        Config.setNestedValue('appearance.customTheme.m3tertiary', tertiary.toString())
        Config.setNestedValue('appearance.customTheme.m3onTertiary', ColorUtils.contrastColor(tertiary).toString())
        const tertiaryContainer = ColorUtils.colorWithLightness(tertiary, (Config.options?.appearance?.customTheme?.darkmode ?? true) ? 0.25 : 0.85)
        Config.setNestedValue('appearance.customTheme.m3tertiaryContainer', tertiaryContainer.toString())
        Config.setNestedValue('appearance.customTheme.m3onTertiaryContainer', ColorUtils.contrastColor(tertiaryContainer).toString())

        applyToShell()
    }

    function copyPreset(colors) {
        const updates = ({})
        for (let key in colors) {
            updates[`appearance.customTheme.${key}`] = colors[key]
        }
        Config.setNestedValues(updates)
        originalColors = null
        saturationSlider.value = 100
        brightnessSlider.value = 0
        temperatureSlider.value = 0
        applyToShell()
    }

    function importThemeFromText(text) {
        try {
            const imported = JSON.parse(text)
            if (!imported.m3primary || !imported.m3background) {
                importDialog.importError = Translation.tr("Invalid theme: missing required color properties")
                return false
            }
            const customTheme = Config.options?.appearance?.customTheme ?? {}
            const updates = ({})
            for (let key in imported) {
                if (customTheme.hasOwnProperty(key)) {
                    const value = imported[key]
                    if (typeof value === "string" && (value.startsWith("#") || value === "true" || value === "false")) {
                        updates[`appearance.customTheme.${key}`] = value
                    } else if (typeof value === "boolean") {
                        updates[`appearance.customTheme.${key}`] = value
                    }
                }
            }
            Config.setNestedValues(updates)
            originalColors = null
            saturationSlider.value = 100
            brightnessSlider.value = 0
            temperatureSlider.value = 0
            applyToShell()
            return true
        } catch (e) {
            importDialog.importError = Translation.tr("Invalid JSON format: ") + e.message
            return false
        }
    }

    // Compact 2-column dashboard layout (no vertical scrolling needed)
    GridLayout {
        id: mainGrid
        Layout.fillWidth: true
        columns: width >= 580 ? 2 : 1
        uniformCellWidths: columns === 2
        columnSpacing: 12
        rowSpacing: 10

        // ── LEFT COLUMN: LIVE PREVIEW + PRESETS & SAVED THEMES ──────────────
        ColumnLayout {
            id: leftTopColumn
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            spacing: 10

            // Live Preview Card (expands to match right column height and Themes & Style height)
            Rectangle {
                id: livePreviewCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                readonly property real chromeHeight: previewHeaderRow.implicitHeight
                    + (lightModeWarningRow.visible ? (lightModeWarningRow.implicitHeight + previewColumn.spacing) : 0)
                    + paletteStripRow.implicitHeight
                    + previewColumn.spacing * 2 + 20
                readonly property real targetCardHeight: root.targetRow0Height > 0
                    ? Math.max(chromeHeight + 108, root.targetRow0Height - presetsSaveCard.implicitHeight - leftTopColumn.spacing)
                    : (chromeHeight + 144)
                implicitHeight: targetCardHeight
                Layout.minimumHeight: targetCardHeight
                Layout.preferredHeight: targetCardHeight
                Layout.maximumHeight: targetCardHeight
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                clip: true

                ColumnLayout {
                    id: previewColumn
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    // Header
                    RowLayout {
                        id: previewHeaderRow
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: "preview"
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Live Preview")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Changes preview live; adjust individual colors as needed.")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                        }

                        // Dark/Light segmented button
                        Rectangle {
                            implicitWidth: segmentRow.implicitWidth + 6
                            implicitHeight: 28
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colLayer2

                            RowLayout {
                                id: segmentRow
                                anchors.centerIn: parent
                                spacing: 3

                                FilterChip {
                                    minimumWidth: 56
                                    chipIcon: "light_mode"
                                    text: Translation.tr("Light")
                                    selected: !(Config.options.appearance.customTheme?.darkmode ?? true)
                                    surfaceColor: Appearance.colors.colLayer2
                                    onClicked: {
                                        if (Config.options.appearance.customTheme?.darkmode ?? true) {
                                            root.invertColorsForMode(true)
                                        }
                                    }
                                }

                                FilterChip {
                                    minimumWidth: 56
                                    chipIcon: "dark_mode"
                                    text: Translation.tr("Dark")
                                    selected: Config.options.appearance.customTheme?.darkmode ?? true
                                    surfaceColor: Appearance.colors.colLayer2
                                    onClicked: {
                                        if (!(Config.options.appearance.customTheme?.darkmode ?? true)) {
                                            root.invertColorsForMode(false)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Light mode warning
                    RowLayout {
                        id: lightModeWarningRow
                        Layout.fillWidth: true
                        spacing: 6
                        visible: !(Config.options.appearance.customTheme?.darkmode ?? true)

                        MaterialSymbol {
                            text: "warning"
                            iconSize: 14
                            color: Appearance.m3colors.m3error
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Light mode is experimental; start with a light preset (Angel Light, Latte or Sakura).")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.WordWrap
                        }
                    }

                    // Mini UI Preview
                    Rectangle {
                        id: miniUiPreview
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        readonly property real targetPreviewHeight: Math.max(108, livePreviewCard.targetCardHeight - livePreviewCard.chromeHeight)
                        Layout.minimumHeight: targetPreviewHeight
                        Layout.preferredHeight: targetPreviewHeight
                        Layout.maximumHeight: targetPreviewHeight
                        implicitHeight: targetPreviewHeight
                        radius: Appearance.rounding.small
                        color: Appearance.m3colors.m3background
                        clip: true

                        // Simulated bar
                        Rectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 24
                            color: Appearance.m3colors.m3surfaceContainerLow

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 5
                                spacing: 5

                                Repeater {
                                    model: 4
                                    Rectangle {
                                        required property int index
                                        width: 15
                                        height: 15
                                        radius: Appearance.rounding.unsharpen
                                        color: index === 0 ? Appearance.m3colors.m3primary : Appearance.m3colors.m3surfaceContainer

                                        StyledText {
                                            anchors.centerIn: parent
                                            text: (index + 1).toString()
                                            font.pixelSize: Appearance.font.pixelSize.smallest - 1
                                            color: index === 0 ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurface
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                StyledText {
                                    text: "12:34"
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.m3colors.m3onSurface
                                }

                                Repeater {
                                    model: ["wifi", "volume_up", "battery_full"]
                                    MaterialSymbol {
                                        required property string modelData
                                        text: modelData
                                        iconSize: 12
                                        color: Appearance.m3colors.m3onSurfaceVariant
                                    }
                                }
                            }
                        }

                        // Simulated content area
                        RowLayout {
                            anchors.fill: parent
                            anchors.topMargin: 28
                            anchors.margins: 6
                            spacing: 6

                            Rectangle {
                                Layout.preferredWidth: 68
                                Layout.fillHeight: true
                                radius: Appearance.rounding.unsharpenmore
                                color: Appearance.m3colors.m3surfaceContainerLow

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    spacing: 3

                                    Repeater {
                                        model: ["search", "chat", "translate"]
                                        Rectangle {
                                            required property int index
                                            required property string modelData
                                            Layout.fillWidth: true
                                            implicitHeight: 16
                                            radius: Appearance.rounding.unsharpen
                                            color: index === 0 ? Appearance.m3colors.m3secondaryContainer : "transparent"

                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: modelData
                                                iconSize: 11
                                                color: index === 0 ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurfaceVariant
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Appearance.rounding.unsharpenmore
                                color: Appearance.m3colors.m3surfaceContainer

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 4

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 9
                                        radius: Appearance.rounding.unsharpen
                                        color: Appearance.m3colors.m3onSurface
                                        opacity: 0.8
                                        Layout.rightMargin: parent.width * 0.4
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 6
                                        radius: Appearance.rounding.unsharpen
                                        color: Appearance.m3colors.m3onSurfaceVariant
                                        opacity: 0.5
                                        Layout.rightMargin: parent.width * 0.2
                                    }

                                    Item { Layout.fillHeight: true }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        Rectangle {
                                            implicitWidth: 42
                                            implicitHeight: 16
                                            radius: Appearance.rounding.verysmall
                                            color: Appearance.m3colors.m3primary

                                            StyledText {
                                                anchors.centerIn: parent
                                                text: "OK"
                                                font.pixelSize: Appearance.font.pixelSize.smallest - 1
                                                color: Appearance.m3colors.m3onPrimary
                                            }
                                        }

                                        Rectangle {
                                            implicitWidth: 46
                                            implicitHeight: 16
                                            radius: Appearance.rounding.verysmall
                                            color: Appearance.m3colors.m3secondaryContainer

                                            StyledText {
                                                anchors.centerIn: parent
                                                text: Translation.tr("Cancel")
                                                font.pixelSize: Appearance.font.pixelSize.smallest - 1
                                                color: Appearance.m3colors.m3onSecondaryContainer
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Compact 1-row Accent + Palette Strip
                    RowLayout {
                        id: paletteStripRow
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: [
                                { key: "m3primary", onKey: "m3onPrimary", label: Translation.tr("Primary"), sides: 12 },
                                { key: "m3secondary", onKey: "m3onSecondary", label: Translation.tr("Secondary"), sides: 9 },
                                { key: "m3tertiary", onKey: "m3onTertiary", label: Translation.tr("Tertiary"), sides: 7 }
                            ]

                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 28
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer2

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6
                                    spacing: 5

                                    MaterialCookie {
                                        implicitSize: 18
                                        sides: modelData.sides
                                        color: Config.options?.appearance?.customTheme?.[modelData.key] ?? Appearance.m3colors[modelData.key]
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        text: (Config.options?.appearance?.customTheme?.[modelData.key] ?? Appearance.m3colors[modelData.key]).toString().toUpperCase().substring(0, 7)
                                        font.pixelSize: Appearance.font.pixelSize.smallest - 1
                                        font.family: Appearance.font.family.monospace
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }

                        Repeater {
                            model: [
                                { color: "m3error", label: "E" },
                                { color: "m3success", label: "✓" },
                                { color: "m3background", label: "BG" },
                                { color: "m3surface", label: "SF" }
                            ]

                            MaterialCookie {
                                required property var modelData
                                implicitSize: 22
                                sides: 6
                                color: Appearance.m3colors[modelData.color] ?? Appearance.colors.colOutline

                                StyledText {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.pixelSize: Appearance.font.pixelSize.smallest - 1
                                    font.weight: Font.Medium
                                    color: ColorUtils.contrastColor(parent.color)
                                }
                            }
                        }
                    }
                }
            }

            // Combined Base Preset + Export/Import + Saved Themes Card
            Rectangle {
                id: presetsSaveCard
                Layout.fillWidth: true
                implicitHeight: presetSaveColumn.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: presetSaveColumn
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    // Header row: Base Preset & Saved Themes title + status indicator
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: "folder_special"
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            text: Translation.tr("Presets & Saved Themes")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: "~/.config/alis/themes/"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            font.family: Appearance.font.family.monospace
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            visible: root.saveStatus !== ""
                            implicitWidth: statusRow.implicitWidth + 10
                            implicitHeight: 22
                            radius: Appearance.rounding.small
                            color: root.saveStatus === "saved" ? Appearance.colors.colSuccessContainer
                                 : root.saveStatus === "error" ? Appearance.colors.colErrorContainer
                                 : Appearance.colors.colLayer2

                            RowLayout {
                                id: statusRow
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialSymbol {
                                    text: root.saveStatus === "saved" ? "check"
                                        : root.saveStatus === "error" ? "error"
                                        : "sync"
                                    iconSize: 13
                                    color: root.saveStatus === "saved" ? Appearance.colors.colOnSuccessContainer
                                         : root.saveStatus === "error" ? Appearance.colors.colOnErrorContainer
                                         : Appearance.colors.colOnLayer2
                                }

                                StyledText {
                                    text: root.saveStatus === "saved" ? Translation.tr("Saved!")
                                        : root.saveStatus === "error" ? Translation.tr("Error")
                                        : Translation.tr("Saving...")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: root.saveStatus === "saved" ? Appearance.colors.colOnSuccessContainer
                                         : root.saveStatus === "error" ? Appearance.colors.colOnErrorContainer
                                         : Appearance.colors.colOnLayer2
                                }
                            }
                        }
                    }

                    // Row 1: Base Preset selector + Export + Import inline
                    RowLayout {
                        id: actionsRow
                        Layout.fillWidth: true
                        spacing: 6

                        Item {
                            id: presetSelectorHost
                            Layout.fillWidth: true
                            implicitHeight: 34

                            RippleButton {
                                id: presetButton
                                anchors.fill: parent
                                implicitHeight: 34
                                colBackground: Appearance.colors.colLayer2
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active

                                contentItem: RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    MaterialSymbol {
                                        text: "palette"
                                        iconSize: 15
                                        color: Appearance.colors.colSubtext
                                    }

                                    Row {
                                        spacing: 3
                                        visible: root.selectedPresetName !== ""
                                        Repeater {
                                            model: {
                                                let preset = root.presetCategories.find(p => p.name === root.selectedPresetName)
                                                return preset ? [preset.colors.m3primary, preset.colors.m3secondary, preset.colors.m3tertiary] : []
                                            }
                                            Rectangle {
                                                required property string modelData
                                                width: 10
                                                height: 10
                                                radius: 5
                                                color: modelData
                                            }
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.selectedPresetName || Translation.tr("Base Preset...")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        elide: Text.ElideRight
                                        color: root.selectedPresetName ? Appearance.colors.colOnSurface : Appearance.colors.colSubtext
                                    }

                                    MaterialSymbol {
                                        text: presetPopup.visible ? "expand_less" : "expand_more"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colSubtext
                                    }
                                }

                                onClicked: presetPopup.visible ? presetPopup.close() : presetPopup.open()
                            }

                            Popup {
                                id: presetPopup
                                y: presetSelectorHost.height + 4
                                width: Math.max(220, presetSelectorHost.width)
                                height: Math.min(280, presetListView.contentHeight + presetSearchField.height + 24)
                                padding: 8

                                background: Rectangle {
                                    color: Appearance.alisEverywhere ? Appearance.alis.colLayer2
                                         : Appearance.colors.colLayer2Base
                                    radius: Appearance.alisEverywhere ? Appearance.alis.roundingNormal : Appearance.rounding.normal
                                    border.width: 1
                                    border.color: Appearance.alisEverywhere ? Appearance.alis.colBorder
                                                : Appearance.colors.colLayer0Border
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 6

                                    TextField {
                                        id: presetSearchField
                                        Layout.fillWidth: true
                                        placeholderText: Translation.tr("Search presets...")
                                        renderType: Text.NativeRendering
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        background: Rectangle {
                                            color: Appearance.colors.colLayer1
                                            radius: Appearance.rounding.small
                                        }
                                        color: Appearance.colors.colOnSurface
                                        placeholderTextColor: Appearance.colors.colSubtext
                                    }

                                    ListView {
                                        id: presetListView
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        model: {
                                            let search = presetSearchField.text.toLowerCase()
                                            if (search) {
                                                return root.presetCategories.filter(p => p.name.toLowerCase().includes(search))
                                            }
                                            return root.presetCategories
                                        }

                                        delegate: RippleButton {
                                            required property var modelData
                                            required property int index
                                            width: presetListView.width
                                            implicitHeight: 32
                                            colBackground: modelData.name === root.selectedPresetName
                                                ? Appearance.colors.colPrimaryContainer
                                                : "transparent"
                                            colBackgroundHover: Appearance.colors.colLayer1Hover
                                            colRipple: Appearance.colors.colLayer1Active

                                            contentItem: RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                spacing: 8

                                                Row {
                                                    spacing: 3
                                                    Repeater {
                                                        model: [modelData.colors.m3primary, modelData.colors.m3secondary, modelData.colors.m3tertiary]
                                                        Rectangle {
                                                            required property string modelData
                                                            width: 12
                                                            height: 12
                                                            radius: 6
                                                            color: modelData
                                                        }
                                                    }
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: modelData.name
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    elide: Text.ElideRight
                                                    color: modelData.name === root.selectedPresetName
                                                        ? Appearance.colors.colOnPrimaryContainer
                                                        : Appearance.colors.colOnSurface
                                                }
                                            }

                                            onClicked: {
                                                root.selectedPresetName = modelData.name
                                                copyPreset(modelData.colors)
                                                presetPopup.close()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        RippleButton {
                            implicitWidth: exportBtnRow.implicitWidth + 18
                            implicitHeight: 34
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active
                            onClicked: exportDialog.open()

                            contentItem: Item {
                                Row {
                                    id: exportBtnRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "upload"
                                        iconSize: 15
                                        color: Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Translation.tr("Export")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }
                                }
                            }
                        }

                        RippleButton {
                            implicitWidth: importBtnRow.implicitWidth + 18
                            implicitHeight: 34
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active
                            onClicked: importDialog.open()

                            contentItem: Item {
                                Row {
                                    id: importBtnRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "download"
                                        iconSize: 15
                                        color: Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Translation.tr("Import")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }
                                }
                            }
                        }
                    }

                    // Row 2: Save theme name input + Save button
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 34
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2
                            border.width: saveNameInput.activeFocus ? 1.5 : 0
                            border.color: Appearance.colors.colPrimary

                            TextInput {
                                id: saveNameInput
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                                clip: true

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    text: Translation.tr("Enter theme name to save...")
                                    font: parent.font
                                    color: Appearance.colors.colSubtext
                                    visible: !parent.text && !parent.activeFocus
                                }

                                Keys.onReturnPressed: {
                                    if (saveNameInput.text.trim().length > 0) {
                                        root.saveTheme(saveNameInput.text.trim())
                                        saveNameInput.text = ""
                                    }
                                }
                            }
                        }

                        Rectangle {
                            implicitWidth: 34
                            implicitHeight: 34
                            radius: Appearance.rounding.small
                            color: saveNameInput.text.trim().length > 0
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colLayer2

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "save"
                                iconSize: 18
                                color: saveNameInput.text.trim().length > 0
                                    ? Appearance.colors.colOnPrimary
                                    : Appearance.colors.colSubtext
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: saveNameInput.text.trim().length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    const name = saveNameInput.text.trim()
                                    if (!name) return
                                    root.saveTheme(name)
                                    saveNameInput.text = ""
                                }
                            }
                        }
                    }

                    // Row 3: Saved themes list chips
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: root.savedThemesList.length > 0

                        Repeater {
                            model: root.savedThemesList

                            InputChip {
                                required property string modelData
                                text: modelData
                                chipIcon: "palette"
                                onActivated: root.loadTheme(modelData)
                                onRemoved: root.deleteTheme(modelData)
                            }
                        }
                    }
                }
            }
        }

        // ── RIGHT COLUMN: QUICK ADJUSTMENTS + COLOR HARMONY + ACCENT COLORS ──
        ColumnLayout {
            id: rightTopColumn
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            spacing: 10

            // Quick Adjustments - Global sliders for the entire palette
            Rectangle {
                id: quickAdjustCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: quickAdjustColumn.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: quickAdjustColumn
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: "tune"
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Quick Adjustments")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                        }

                        RippleButton {
                            implicitWidth: 26
                            implicitHeight: 26
                            buttonRadius: 13
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "restart_alt"
                                iconSize: 15
                                color: Appearance.colors.colOnLayer2
                            }

                            onClicked: {
                                saturationSlider.value = 100
                                brightnessSlider.value = 0
                                temperatureSlider.value = 0
                            }

                            StyledToolTip { text: Translation.tr("Reset adjustments"); visible: parent.buttonHovered }
                        }
                    }

                    // Saturation slider
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: "palette"
                            iconSize: 15
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            text: Translation.tr("Saturation")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            Layout.preferredWidth: 68
                        }

                        StyledSlider {
                            id: saturationSlider
                            Layout.fillWidth: true
                            Layout.preferredWidth: -1
                            Layout.maximumWidth: 16777215
                            from: 0
                            to: 200
                            value: 100
                            stepSize: 5
                            configuration: StyledSlider.Configuration.S

                            onMoved: { root.captureOriginalColors(); adjustDebounce.restart() }
                        }

                        StyledText {
                            text: Math.round(saturationSlider.value) + "%"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colSubtext
                            Layout.preferredWidth: 34
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    // Brightness slider
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: "brightness_6"
                            iconSize: 15
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            text: Translation.tr("Brightness")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            Layout.preferredWidth: 68
                        }

                        StyledSlider {
                            id: brightnessSlider
                            Layout.fillWidth: true
                            Layout.preferredWidth: -1
                            Layout.maximumWidth: 16777215
                            from: -50
                            to: 50
                            value: 0
                            stepSize: 5
                            configuration: StyledSlider.Configuration.S

                            onMoved: { root.captureOriginalColors(); adjustDebounce.restart() }
                        }

                        StyledText {
                            text: (brightnessSlider.value >= 0 ? "+" : "") + Math.round(brightnessSlider.value)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colSubtext
                            Layout.preferredWidth: 34
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    // Temperature slider
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: "thermostat"
                            iconSize: 15
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            text: Translation.tr("Temperature")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            Layout.preferredWidth: 68
                        }

                        StyledSlider {
                            id: temperatureSlider
                            Layout.fillWidth: true
                            Layout.preferredWidth: -1
                            Layout.maximumWidth: 16777215
                            from: -50
                            to: 50
                            value: 0
                            stepSize: 5
                            configuration: StyledSlider.Configuration.S

                            onMoved: { root.captureOriginalColors(); adjustDebounce.restart() }
                        }

                        StyledText {
                            text: temperatureSlider.value > 0 ? Translation.tr("Warm") : (temperatureSlider.value < 0 ? Translation.tr("Cool") : "0")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.monospace
                            color: temperatureSlider.value > 0 ? Appearance.colors.colTertiary
                                 : (temperatureSlider.value < 0 ? Appearance.colors.colPrimary
                                 : Appearance.colors.colSubtext)
                            Layout.preferredWidth: 34
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }

            // Color Harmony - Compact card with inline preview & Apply in header
            Rectangle {
                id: harmonyCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: harmonyColumn.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: harmonyColumn
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: "auto_fix"
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Color Harmony")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                        }

                        // Primary (source)
                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            color: Config.options?.appearance?.customTheme?.m3primary ?? Appearance.m3colors.m3primary
                            border.width: 1.5
                            border.color: Appearance.colors.colOnLayer1
                            MouseArea { id: primaryMouse; anchors.fill: parent; hoverEnabled: true }
                            StyledToolTip { text: Translation.tr("Primary (source)"); visible: primaryMouse.containsMouse }
                        }

                        MaterialSymbol {
                            text: "arrow_forward"
                            iconSize: 12
                            color: Appearance.colors.colSubtext
                        }

                        // Generated secondary
                        Rectangle {
                            id: previewSecondary
                            width: 18
                            height: 18
                            radius: 9
                            color: root.getHarmonyColor("secondary")
                            MouseArea { id: secondaryMouse; anchors.fill: parent; hoverEnabled: true }
                            StyledToolTip { text: Translation.tr("Secondary (generated)"); visible: secondaryMouse.containsMouse }
                        }

                        // Generated tertiary
                        Rectangle {
                            id: previewTertiary
                            width: 18
                            height: 18
                            radius: 9
                            color: root.getHarmonyColor("tertiary")
                            MouseArea { id: tertiaryMouse; anchors.fill: parent; hoverEnabled: true }
                            StyledToolTip { text: Translation.tr("Tertiary (generated)"); visible: tertiaryMouse.containsMouse }
                        }

                        RippleButton {
                            implicitWidth: applyRow.implicitWidth + 16
                            implicitHeight: 26
                            buttonRadius: 13
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            onClicked: root.applyHarmonyColors()

                            contentItem: Item {
                                Row {
                                    id: applyRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "auto_awesome"
                                        iconSize: 13
                                        color: Appearance.colors.colOnPrimary
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Translation.tr("Apply")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colOnPrimary
                                    }
                                }
                            }
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        uniformCellWidths: true
                        columnSpacing: 6
                        rowSpacing: 6

                        Repeater {
                            model: [
                                { id: "complementary", name: Translation.tr("Complementary"), detail: Translation.tr("Bold, clear contrast"), icon: "contrast" },
                                { id: "analogous", name: Translation.tr("Analogous"), detail: Translation.tr("Calm, closely related colors"), icon: "gradient" },
                                { id: "triadic", name: Translation.tr("Triadic"), detail: Translation.tr("Balanced and colorful"), icon: "change_history" },
                                { id: "split", name: Translation.tr("Split"), detail: Translation.tr("Contrast with less tension"), icon: "call_split" }
                            ]

                            RippleButton {
                                required property var modelData
                                required property int index

                                Layout.fillWidth: true
                                implicitHeight: 34
                                buttonRadius: Appearance.rounding.small
                                toggled: root._harmonyScheme === modelData.id
                                colBackground: toggled ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                                colBackgroundHover: toggled ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                                onClicked: root._harmonyScheme = modelData.id

                                contentItem: Item {
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 5

                                        MaterialSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.icon
                                            iconSize: 15
                                            color: root._harmonyScheme === modelData.id ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                                        }

                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.name
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: Font.Medium
                                            color: root._harmonyScheme === modelData.id ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                                        }
                                    }
                                }

                                StyledToolTip { text: modelData.detail; visible: parent.buttonHovered }
                            }
                        }
                    }
                }
            }

            // Accent Colors Card
            ColorPaletteCard {
                id: accentColorsCard
                Layout.fillHeight: true
                title: Translation.tr("Accent Colors")
                icon: "palette"
                description: Translation.tr("Buttons, links, active states, and highlights")
                accentKey: "m3primary"
                colors: [
                    { label: "Accent", key: "m3primary", tip: "Main accent for buttons and links" },
                    { label: "Text", key: "m3onPrimary", tip: "Text color on accent buttons", contrastAgainst: "m3primary" },
                    { label: "Soft BG", key: "m3primaryContainer", tip: "Subtle accent backgrounds" },
                    { label: "Soft Text", key: "m3onPrimaryContainer", tip: "Text on subtle backgrounds", contrastAgainst: "m3primaryContainer" }
                ]
            }
        }

        // ── EXPORT / IMPORT DIALOGS (FULL WIDTH WHEN OPEN) ──────────────────
        Rectangle {
            id: exportDialog
            visible: false
            Layout.fillWidth: true
            Layout.columnSpan: mainGrid.columns
            implicitHeight: exportDialogColumn.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 2
            border.color: Appearance.colors.colPrimary

            function open() { visible = true }
            function close() { visible = false; exportCopied = false }
            property bool exportCopied: false

            ColumnLayout {
                id: exportDialogColumn
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        text: "upload"
                        iconSize: 18
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Export Theme")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }

                    MaterialSymbol {
                        text: "close"
                        iconSize: 18
                        color: Appearance.colors.colSubtext
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: exportDialog.close()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 96
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    clip: true

                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: 8

                        TextArea {
                            id: exportTextArea
                            readOnly: true
                            text: JSON.stringify(Config.options.appearance.customTheme, null, 2)
                            renderType: Text.NativeRendering
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnLayer2
                            wrapMode: TextArea.Wrap
                            selectByMouse: true
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: Appearance.rounding.small
                    color: exportDialog.exportCopied ? Appearance.colors.colSuccessContainer : Appearance.colors.colPrimary

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: exportDialog.exportCopied ? "check" : "content_copy"
                            iconSize: 16
                            color: exportDialog.exportCopied ? Appearance.colors.colOnSuccessContainer : Appearance.colors.colOnPrimary
                        }

                        StyledText {
                            text: exportDialog.exportCopied ? Translation.tr("Copied to clipboard!") : Translation.tr("Copy to Clipboard")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: exportDialog.exportCopied ? Appearance.colors.colOnSuccessContainer : Appearance.colors.colOnPrimary
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.clipboardText = exportTextArea.text
                            exportDialog.exportCopied = true
                        }
                    }
                }
            }
        }

        Rectangle {
            id: importDialog
            visible: false
            Layout.fillWidth: true
            Layout.columnSpan: mainGrid.columns
            implicitHeight: importDialogColumn.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 2
            border.color: Appearance.colors.colSecondary

            function open() { visible = true; importTextArea.text = "" }
            function close() { visible = false; importError = "" }
            property string importError: ""

            ColumnLayout {
                id: importDialogColumn
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        text: "download"
                        iconSize: 18
                        color: Appearance.colors.colSecondary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Import Theme")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }

                    MaterialSymbol {
                        text: "close"
                        iconSize: 18
                        color: Appearance.colors.colSubtext
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: importDialog.close()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 96
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    border.width: importDialog.importError ? 2 : 0
                    border.color: Appearance.colors.colError
                    clip: true

                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: 8

                        TextArea {
                            id: importTextArea
                            placeholderText: Translation.tr("Paste theme JSON here...")
                            renderType: Text.NativeRendering
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnLayer2
                            wrapMode: TextArea.Wrap
                        }
                    }
                }

                StyledText {
                    visible: importDialog.importError !== ""
                    Layout.fillWidth: true
                    text: importDialog.importError
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colError
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: "content_paste"
                                iconSize: 16
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                text: Translation.tr("Paste from Clipboard")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: importTextArea.text = Quickshell.clipboardText
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: Appearance.rounding.small
                        color: importTextArea.text.trim() ? Appearance.colors.colPrimary : Appearance.colors.colLayer2

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: "check"
                                iconSize: 16
                                color: importTextArea.text.trim() ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                            }

                            StyledText {
                                text: Translation.tr("Apply Theme")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: importTextArea.text.trim() ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: importTextArea.text.trim() ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (!importTextArea.text.trim()) return
                                if (root.importThemeFromText(importTextArea.text)) {
                                    importDialog.close()
                                }
                            }
                        }
                    }
                }
            }
        }

        ColorPaletteCard {
            id: secondaryCard
            visible: true
            title: Translation.tr("Secondary")
            icon: "filter_2"
            description: Translation.tr("Chips, tags, less prominent actions")
            accentKey: "m3secondary"
            colors: [
                { label: "Color", key: "m3secondary", tip: "Secondary accent color" },
                { label: "Text", key: "m3onSecondary", tip: "Text on secondary", contrastAgainst: "m3secondary" },
                { label: "Soft BG", key: "m3secondaryContainer", tip: "Chip and tag backgrounds" },
                { label: "Soft Text", key: "m3onSecondaryContainer", tip: "Text on chips and tags", contrastAgainst: "m3secondaryContainer" }
            ]
        }

        ColorPaletteCard {
            id: tertiaryCard
            visible: true
            title: Translation.tr("Tertiary")
            icon: "filter_3"
            description: Translation.tr("Complementary accent for variety")
            accentKey: "m3tertiary"
            colors: [
                { label: "Color", key: "m3tertiary", tip: "Third accent color" },
                { label: "Text", key: "m3onTertiary", tip: "Text on tertiary", contrastAgainst: "m3tertiary" },
                { label: "Soft BG", key: "m3tertiaryContainer", tip: "Tertiary backgrounds" },
                { label: "Soft Text", key: "m3onTertiaryContainer", tip: "Text on tertiary bg", contrastAgainst: "m3tertiaryContainer" }
            ]
        }

        ColorPaletteCard {
            id: backgroundsCard
            visible: true
            title: Translation.tr("Backgrounds")
            icon: "layers"
            description: Translation.tr("Main backgrounds and text colors")
            accentKey: "m3surface"
            colors: [
                { label: "Base BG", key: "m3background", tip: "Deepest background layer" },
                { label: "Surface", key: "m3surface", tip: "Card and panel backgrounds" },
                { label: "Main Text", key: "m3onSurface", tip: "Primary text color", contrastAgainst: "m3surface" },
                { label: "BG Text", key: "m3onBackground", tip: "Text on base background", contrastAgainst: "m3background" }
            ]
        }

        // Surface Containers (collapsible)
        Rectangle {
            id: surfaceContainersCard
            visible: true
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: surfaceContainersColumn.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            ColumnLayout {
                id: surfaceContainersColumn
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                RowLayout {
                    id: surfaceContainersHeader
                    Layout.fillWidth: true
                    spacing: 8

                    property bool surfaceContainersExpanded: false

                    TapHandler {
                        onTapped: surfaceContainersHeader.surfaceContainersExpanded =
                            !surfaceContainersHeader.surfaceContainersExpanded
                    }

                    Rectangle {
                        width: 28
                        height: 28
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colSurfaceContainer

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "stacks"
                            iconSize: 16
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Surface Containers")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }

                    MaterialSymbol {
                        text: surfaceContainersHeader.surfaceContainersExpanded
                            ? "expand_less" : "expand_more"
                        iconSize: 20
                        color: Appearance.colors.colSubtext
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Repeater {
                        model: [
                            { key: "m3surfaceContainerLowest", label: "Lowest" },
                            { key: "m3surfaceContainerLow", label: "Low" },
                            { key: "m3surfaceContainer", label: "Base" },
                            { key: "m3surfaceContainerHigh", label: "High" },
                            { key: "m3surfaceContainerHighest", label: "Highest" }
                        ]

                        Rectangle {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            implicitHeight: 32
                            radius: index === 0 ? Appearance.rounding.small : (index === 4 ? Appearance.rounding.small : 0)
                            color: Config.options.appearance.customTheme?.[modelData.key] ?? Appearance.colors.colOutline

                            StyledText {
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: ColorUtils.contrastColor(parent.color)
                            }
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 4
                    visible: surfaceContainersHeader.surfaceContainersExpanded

                    Repeater {
                        model: [
                            { label: "Lowest", key: "m3surfaceContainerLowest" },
                            { label: "Low", key: "m3surfaceContainerLow" },
                            { label: "Container", key: "m3surfaceContainer" },
                            { label: "High", key: "m3surfaceContainerHigh" },
                            { label: "Highest", key: "m3surfaceContainerHighest" },
                            { label: "Dim", key: "m3surfaceDim" },
                            { label: "Bright", key: "m3surfaceBright" },
                            { label: "Variant", key: "m3surfaceVariant" }
                        ]

                        ColorPickerRow {
                            required property var modelData
                            Layout.fillWidth: true
                            label: modelData.label
                            colorKey: modelData.key
                            onColorChanged: root.applyToShell()
                        }
                    }
                }
            }
        }

        ColorPaletteCard {
            id: bordersShadowsCard
            visible: true
            title: Translation.tr("Borders & Shadows")
            icon: "border_style"
            description: Translation.tr("Dividers, borders, and overlay effects")
            accentKey: "m3outline"
            colors: [
                { label: "Border", key: "m3outline", tip: "Main border color" },
                { label: "Subtle", key: "m3outlineVariant", tip: "Subtle dividers" },
                { label: "Shadow", key: "m3shadow", tip: "Drop shadow color" },
                { label: "Overlay", key: "m3scrim", tip: "Modal overlay background" }
            ]
        }

        ColorPaletteCard {
            id: statusColorsCard
            visible: true
            title: Translation.tr("Status Colors")
            icon: "info"
            description: Translation.tr("Error messages and success indicators")
            accentKey: "m3error"
            colors: [
                { label: "Error", key: "m3error", tip: "Error and warning color" },
                { label: "Error Text", key: "m3onError", tip: "Text on error backgrounds" },
                { label: "Success", key: "m3success", tip: "Success and confirmation" },
                { label: "Success Text", key: "m3onSuccess", tip: "Text on success backgrounds" }
            ]
        }
    }

    // Color palette card component - with inline color picker
    component ColorPaletteCard: Rectangle {
        id: paletteCard
        required property string title
        required property string icon
        property string description: ""
        required property string accentKey
        required property var colors

        Layout.fillWidth: true
        implicitHeight: paletteColumn.implicitHeight + 16
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1

        ColumnLayout {
            id: paletteColumn
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            // Header with description
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialCookie {
                    width: 24
                    height: 24
                    implicitSize: 24
                    sides: paletteCard.accentKey === "m3primary" ? 12
                        : paletteCard.accentKey === "m3secondary" ? 9
                        : paletteCard.accentKey === "m3tertiary" ? 7 : 6
                    color: Config.options.appearance.customTheme?.[paletteCard.accentKey] ?? Appearance.colors.colOutline

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: paletteCard.icon
                        iconSize: 14
                        color: ColorUtils.contrastColor(parent.color)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    StyledText {
                        text: paletteCard.title
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        visible: paletteCard.description !== ""
                        text: paletteCard.description
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            // Horizontal color swatches (FontSelector style)
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: paletteCard.colors

                    Item {
                        id: swatchItem
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: swatchColumn.implicitHeight

                        // Contrast calculation
                        readonly property string contrastKey: modelData.contrastAgainst ?? ""
                        readonly property color fgColor: Config.options.appearance.customTheme?.[modelData.key] ?? Appearance.colors.colOutline
                        readonly property color bgColor: contrastKey ? (Config.options.appearance.customTheme?.[contrastKey] ?? Appearance.colors.colLayer0) : Appearance.colors.colLayer0
                        readonly property real ratio: contrastKey ? ColorUtils.contrastRatio(fgColor, bgColor) : 0
                        readonly property bool showContrast: contrastKey !== ""

                        ColumnLayout {
                            id: swatchColumn
                            anchors.fill: parent
                            spacing: 3

                            // Label with contrast indicator
                            RowLayout {
                                spacing: 4

                                StyledText {
                                    text: modelData.label
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }

                                // Contrast badge
                                Rectangle {
                                    id: contrastBadgeFrame
                                    visible: swatchItem.showContrast
                                    implicitWidth: contrastBadge.implicitWidth + 6
                                    implicitHeight: 14
                                    radius: 7
                                    color: swatchItem.ratio >= 4.5 ? Appearance.colors.colSuccessContainer : swatchItem.ratio >= 3 ? Appearance.colors.colWarningContainer : Appearance.colors.colErrorContainer

                                    RowLayout {
                                        id: contrastBadge
                                        anchors.centerIn: parent
                                        spacing: 2

                                        MaterialSymbol {
                                            text: swatchItem.ratio >= 4.5 ? "check" : "warning"
                                            iconSize: 8
                                            color: swatchItem.ratio >= 4.5 ? Appearance.colors.colOnSuccessContainer : swatchItem.ratio >= 3 ? Appearance.colors.colOnWarningContainer : Appearance.colors.colOnErrorContainer
                                        }

                                        StyledText {
                                            text: swatchItem.ratio.toFixed(1)
                                            font.pixelSize: 8
                                            font.family: Appearance.font.family.monospace
                                            color: swatchItem.ratio >= 4.5 ? Appearance.colors.colOnSuccessContainer : swatchItem.ratio >= 3 ? Appearance.colors.colOnWarningContainer : Appearance.colors.colOnErrorContainer
                                        }
                                    }

                                    StyledToolTip {
                                        text: swatchItem.ratio >= 4.5 ? Translation.tr("WCAG AA ✓ Good contrast")
                                            : swatchItem.ratio >= 3 ? Translation.tr("Low contrast - may be hard to read")
                                            : Translation.tr("Poor contrast - fails accessibility")
                                        visible: contrastBadgeHover.hovered && contrastBadgeFrame.visible
                                    }
                                    HoverHandler { id: contrastBadgeHover }
                                }
                            }

                            // Color button (like FontSelector dropdown)
                            RippleButton {
                                id: swatchButton
                                Layout.fillWidth: true
                                implicitHeight: 32
                                colBackground: Appearance.colors.colLayer2
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active

                                contentItem: RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6
                                    spacing: 6

                                    // Color preview circle
                                    MaterialCookie {
                                        width: 16
                                        height: 16
                                        implicitSize: 16
                                        sides: index % 3 === 0 ? 12 : (index % 3 === 1 ? 9 : 7)
                                        color: Config.options.appearance.customTheme?.[modelData.key] ?? Appearance.colors.colOutline
                                    }

                                    // Hex value
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: (Config.options.appearance.customTheme?.[modelData.key] ?? Appearance.colors.colOutline).toString().toUpperCase().substring(0, 7)
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.family: Appearance.font.family.monospace
                                        elide: Text.ElideRight
                                    }

                                    // Edit icon (only visible on hover)
                                    MaterialSymbol {
                                        text: "edit"
                                        iconSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colSubtext
                                        opacity: swatchButton.buttonHovered ? 1 : 0
                                        Behavior on opacity {
                                            enabled: Appearance.animationsEnabled
                                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                        }
                                    }
                                }

                                onClicked: {
                                    paletteCard.dialogKey = modelData.key
                                    paletteCard.dialogColor = Config.options.appearance.customTheme?.[modelData.key] ?? Appearance.colors.colOutline
                                    colorPicker.open()
                                }

                                StyledToolTip {
                                    text: modelData.tip ?? ""
                                    visible: parent.buttonHovered && (modelData.tip ?? "").length > 0
                                }
                            }
                        }
                    }
                }
            }

        }

        // Color dialog
        property string dialogKey: ""
        property color dialogColor: Appearance.colors.colOutline

        ColorDialog {
            id: colorPicker
            selectedColor: paletteCard.dialogColor
            onAccepted: {
                if (paletteCard.dialogKey !== "") {
                    Config.setNestedValue(`appearance.customTheme.${paletteCard.dialogKey}`, selectedColor.toString())
                    root.applyToShell()
                }
            }
        }

        SettingsNativeDialogGuard {
            dialog: colorPicker
            dialogKey: "custom-theme-palette-color"
        }
    }
}
