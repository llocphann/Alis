import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.settings
import "../common/PanelFamilyPolicy.js" as FamilyPolicy
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: modulesPage
    settingsPageIndex: 10
    settingsPageName: "Shell & interface"

    readonly property bool isIi: (Config.options?.panelFamily ?? "abyss") === "ii"
    readonly property bool isAbyss: Config.options?.panelFamily === "abyss"
    readonly property bool isWaffle: Config.options?.panelFamily === "waffle"

    readonly property var defaultPanels: ({
        "abyss": FamilyPolicy.abyssPanels,
        "ii": [
            "iiBar", "iiBackground", "iiBackdrop", "iiCheatsheet", "iiControlPanel", "iiDock", "iiLock",
            "iiMediaControls", "iiNotificationPopup", "iiOnScreenDisplay", "iiOnScreenKeyboard",
            "iiOverlay", "iiOverview", "iiPolkit", "iiRegionSelector", "iiScreenCorners",
            "iiSessionScreen", "iiSidebarLeft", "iiSidebarRight", "iiTilingOverlay", "iiVerticalBar",
            "iiWallpaperSelector", "iiWallpaperLauncher", "iiCoverflowSelector", "iiClipboard", "iiShellUpdate", "iiDashboard"
        ],
        "waffle": [
            "wBar", "wBackground", "wBackdrop", "wStartMenu", "wActionCenter", "wNotificationCenter", "wNotificationPopup", "wOnScreenDisplay", "wWidgets", "wTaskView", "wLock", "wPolkit", "wSessionScreen",
            "iiCheatsheet", "iiOnScreenKeyboard", "iiOverlay", "iiOverview",
            "iiRegionSelector", "iiScreenCorners", "iiWallpaperSelector", "iiWallpaperLauncher", "iiCoverflowSelector", "iiClipboard"
        ]
    })

    function isPanelEnabled(panelId: string): bool {
        return (Config.options?.enabledPanels ?? []).includes(panelId)
    }

    function setPanelEnabled(panelId: string, enabled: bool) {
        let panels = [...(Config.options?.enabledPanels ?? [])]
        const idx = panels.indexOf(panelId)

        if (enabled && idx === -1) {
            panels.push(panelId)
        } else if (!enabled && idx !== -1) {
            panels.splice(idx, 1)
        }

        Config.setNestedValue("enabledPanels", panels)
    }

    function isIiBarEnabled(): bool {
        const panels = Config.options?.enabledPanels ?? []
        return panels.includes("iiBar") || panels.includes("iiVerticalBar")
    }

    function setIiBarEnabled(enabled: bool) {
        let panels = [...(Config.options?.enabledPanels ?? [])]

        const hasBar = panels.includes("iiBar")
        const hasVerticalBar = panels.includes("iiVerticalBar")

        if (enabled) {
            if (!hasBar) panels.push("iiBar")
            if (!hasVerticalBar) panels.push("iiVerticalBar")
        } else {
            panels = panels.filter(panel => panel !== "iiBar" && panel !== "iiVerticalBar")
        }

        Config.setNestedValue("enabledPanels", panels)
    }

    function resetToDefaults() {
        const family = Config.options?.panelFamily ?? "abyss"
        Config.setNestedValue("enabledPanels", [...(defaultPanels[family] ?? [])])
    }

    property string activeSection: "panels"

    function reconcileActiveSection(): void {
        if ((modulesPage.isAbyss && modulesPage.activeSection === "modules")
                || modulesPage.activeSection === "terminal")
            modulesPage.activeSection = "panels"
    }
    onActiveSectionChanged: reconcileActiveSection()
    onIsAbyssChanged: reconcileActiveSection()
    Component.onCompleted: reconcileActiveSection()

    SettingsTaskNavigator {
        showTabBar: !modulesPage.isAbyss
        icon: "extension"
        title: "Shell & interface"
        description: Translation.tr("Manage modules, terminals and interface behavior.")
        summary: Translation.tr("Panels · Modules · Interface")
        currentValue: modulesPage.activeSection
        onSelected: value => modulesPage.activeSection = value
        options: [
            { displayName: Translation.tr("Panels"), icon: "extension", value: "panels" },
            { displayName: Translation.tr("Modules"), icon: "dashboard", value: "modules" },
            { displayName: Translation.tr("Interface"), icon: "tune", value: "interface" }
        ].filter(option => option.value !== "modules" || !modulesPage.isAbyss)
    }

    GridLayout {
        id: modulesTwoColumnGrid
        objectName: "modulesTwoColumnGrid"
        Layout.fillWidth: true
        columns: (modulesPage.isAbyss || modulesPage.activeSection === "panels" || modulesPage.activeSection === "interface") && width >= 620 ? 2 : 1
        uniformCellWidths: columns === 2
        columnSpacing: 14
        rowSpacing: 14
        visible: modulesPage.isAbyss || modulesPage.activeSection === "panels" || modulesPage.activeSection === "interface"

        SettingsCardSection {
            id: panelStyleCard
            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: modulesTwoColumnGrid.columns === 2
                ? Math.max(panelStyleCard.implicitHeight, settingsUiCard.implicitHeight) : 0
            settingsTaskSection: "panels"
            visible: modulesPage.isAbyss || modulesPage.activeSection === "panels"
            expanded: true
            icon: "style"
            title: Translation.tr("Panel Style")

            SettingsGroup {
                ConfigSelectionArray {
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignHCenter
                    currentValue: Config.options?.panelFamily ?? "abyss"
                    onSelected: newValue => Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "panelFamily", "set", newValue])
                    options: [
                        {
                            displayName: "Abyss",
                            icon: "water",
                            value: "abyss"
                        },
                        {
                            displayName: "Waffle",
                            icon: "window",
                            value: "waffle"
                        }
                    ]
                }

                Rectangle {
                    id: panelStylePreview
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: 176
                    radius: Appearance.rounding.normal
                    clip: true
                    color: Appearance.colors.colLayer2
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant

                    readonly property bool isWaffleMode: (Config.options?.panelFamily ?? "abyss") === "waffle"

                    // Desktop wallpaper backdrop
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: Math.max(0, parent.radius - 1)
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.tint(Appearance.colors.colLayer1, Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.14)) }
                            GradientStop { position: 1.0; color: Appearance.colors.colLayer2 }
                        }
                    }

                    // ==================== ABYSS SCREENSHOT PREVIEW ====================
                    Item {
                        id: abyssScreenshotMockup
                        anchors.fill: parent
                        visible: !panelStylePreview.isWaffleMode

                        // Outer Screen Edge frame + top bar
                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.width: 6
                            border.color: Appearance.colors.colLayer0
                            radius: panelStylePreview.radius
                        }

                        // Top integrated Abyss Bar
                        Rectangle {
                            id: abyssTopBarMock
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 24
                            color: Appearance.colors.colLayer0

                            // Left: Launcher + Workspace pills
                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5

                                Rectangle {
                                    width: 12; height: 12; radius: 6
                                    color: Appearance.colors.colPrimary
                                }
                                Rectangle {
                                    width: 18; height: 8; radius: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Appearance.colors.colPrimary
                                }
                                Repeater {
                                    model: 3
                                    Rectangle {
                                        width: 8; height: 8; radius: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: Appearance.colors.colLayer2
                                    }
                                }
                            }

                            // Center: Connected Abyss Clock Notch
                            Rectangle {
                                width: 54
                                height: 20
                                radius: 8
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: 2
                                color: Appearance.colors.colLayer1
                                border.width: 1
                                border.color: Appearance.colors.colOutlineVariant

                                StyledText {
                                    anchors.centerIn: parent
                                    text: "14:20"
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer0
                                }
                            }

                            // Right: System status & resource pills
                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5

                                Rectangle {
                                    width: 28; height: 12; radius: 6
                                    color: Appearance.colors.colLayer2
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 3
                                        Rectangle { width: 5; height: 5; radius: 2.5; color: Appearance.colors.colPrimary }
                                        Rectangle { width: 12; height: 4; radius: 2; anchors.verticalCenter: parent.verticalCenter; color: Appearance.colors.colOnLayer1; opacity: 0.65 }
                                    }
                                }
                                Rectangle {
                                    width: 34; height: 12; radius: 6
                                    color: Appearance.colors.colSecondaryContainer
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 3
                                        Repeater {
                                            model: 3
                                            Rectangle { width: 5; height: 5; radius: 2.5; color: Appearance.colors.colOnSecondaryContainer }
                                        }
                                    }
                                }
                            }
                        }

                        // Inner concave Screen Edge viewport border
                        Rectangle {
                            id: abyssViewportMock
                            anchors.top: abyssTopBarMock.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            anchors.bottomMargin: 6
                            radius: 12
                            color: "transparent"
                            border.width: 1
                            border.color: Appearance.colors.colOutlineVariant

                            // Tiled desktop windows inside workspace
                            RowLayout {
                                anchors.fill: parent
                                anchors.topMargin: 10
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                anchors.bottomMargin: 26
                                spacing: 8

                                // Left tiled window (focused)
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.preferredWidth: 3
                                    radius: 7
                                    color: Appearance.colors.colLayer0
                                    opacity: 0.94
                                    border.width: 1.5
                                    border.color: Appearance.colors.colPrimary

                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 5
                                        Row {
                                            spacing: 4
                                            Rectangle { width: 6; height: 6; radius: 3; color: Appearance.colors.colPrimary }
                                            Rectangle { width: 38; height: 5; radius: 2.5; color: Appearance.colors.colOnLayer1; opacity: 0.45 }
                                        }
                                        Rectangle { width: parent.width * 0.85; height: 5; radius: 2.5; color: Appearance.colors.colLayer2 }
                                        Rectangle { width: parent.width * 0.65; height: 5; radius: 2.5; color: Appearance.colors.colLayer2 }
                                        Rectangle { width: parent.width * 0.75; height: 5; radius: 2.5; color: Appearance.colors.colLayer2 }
                                    }
                                }

                                // Right tiled window
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.preferredWidth: 2
                                    radius: 7
                                    color: Appearance.colors.colLayer0
                                    opacity: 0.88
                                    border.width: 1
                                    border.color: Appearance.colors.colOutlineVariant

                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 5
                                        Rectangle { width: parent.width * 0.55; height: 5; radius: 2.5; color: Appearance.colors.colOnLayer1; opacity: 0.4 }
                                        Rectangle { width: parent.width; height: 22; radius: 4; color: Appearance.colors.colLayer2 }
                                        Rectangle { width: parent.width * 0.8; height: 14; radius: 4; color: Appearance.colors.colLayer2 }
                                    }
                                }
                            }

                            // Bottom connected Abyss Dock
                            Rectangle {
                                width: 112
                                height: 18
                                radius: 9
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: -2
                                color: Appearance.colors.colLayer0
                                border.width: 1
                                border.color: Appearance.colors.colOutlineVariant

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Repeater {
                                        model: 5
                                        Rectangle {
                                            required property int index
                                            width: 11; height: 11; radius: 3.5
                                            color: index === 0
                                                ? Appearance.colors.colPrimary
                                                : (index === 2 ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ==================== WAFFLE SCREENSHOT PREVIEW ====================
                    Item {
                        id: waffleScreenshotMockup
                        anchors.fill: parent
                        visible: panelStylePreview.isWaffleMode

                        // Background desktop window
                        Rectangle {
                            width: parent.width * 0.42
                            height: parent.height * 0.52
                            x: 14
                            y: 12
                            radius: 6
                            color: Appearance.colors.colLayer0
                            opacity: 0.72
                            border.width: 1
                            border.color: Appearance.colors.colOutlineVariant

                            Column {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 5
                                Rectangle { width: parent.width * 0.5; height: 5; radius: 2.5; color: Appearance.colors.colOnLayer1; opacity: 0.35 }
                                Rectangle { width: parent.width * 0.85; height: 5; radius: 2.5; color: Appearance.colors.colLayer2 }
                                Rectangle { width: parent.width * 0.7; height: 5; radius: 2.5; color: Appearance.colors.colLayer2 }
                            }
                        }

                        // Centered floating Waffle Start Menu card
                        Rectangle {
                            id: waffleStartMenuMock
                            width: Math.min(156, parent.width * 0.52)
                            height: Math.min(102, parent.height - waffleTaskbarMock.height - 18)
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: waffleTaskbarMock.top
                            anchors.bottomMargin: 6
                            radius: 8
                            color: Appearance.colors.colLayer0
                            border.width: 1
                            border.color: Appearance.colors.colOutlineVariant

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                // Search pill inside Start menu
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 14
                                    radius: 7
                                    color: Appearance.colors.colLayer2
                                    border.width: 1
                                    border.color: Appearance.colors.colOutlineVariant

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4
                                        Rectangle { width: 5; height: 5; radius: 2.5; color: Appearance.colors.colPrimary }
                                        Rectangle { width: 42; height: 4; radius: 2; anchors.verticalCenter: parent.verticalCenter; color: Appearance.colors.colOnLayer1; opacity: 0.45 }
                                    }
                                }

                                // Pinned app grid (4x2)
                                GridLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    columns: 4
                                    columnSpacing: 6
                                    rowSpacing: 6

                                    Repeater {
                                        model: 8
                                        Rectangle {
                                            required property int index
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: 4
                                            color: index === 0
                                                ? Appearance.colors.colPrimary
                                                : (index % 3 === 0 ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2)
                                        }
                                    }
                                }

                                // Bottom user + power strip
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Rectangle { width: 8; height: 8; radius: 4; color: Appearance.colors.colPrimary }
                                    Rectangle { width: 32; height: 4; radius: 2; color: Appearance.colors.colOnLayer1; opacity: 0.45 }
                                    Item { Layout.fillWidth: true }
                                    Rectangle { width: 7; height: 7; radius: 3.5; color: Appearance.colors.colLayer2 }
                                }
                            }
                        }

                        // Bottom full-width Waffle Taskbar
                        Rectangle {
                            id: waffleTaskbarMock
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 28
                            color: Appearance.colors.colLayer0

                            Rectangle {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 1
                                color: Appearance.colors.colOutlineVariant
                            }

                            // Left: Weather / widget pill
                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Rectangle { width: 10; height: 10; radius: 5; color: Appearance.colors.colSecondaryContainer }
                                Rectangle { width: 20; height: 5; radius: 2.5; anchors.verticalCenter: parent.verticalCenter; color: Appearance.colors.colOnLayer1; opacity: 0.5 }
                            }

                            // Center: Start button + search pill + pinned apps
                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                // 4-tile Start icon
                                Grid {
                                    columns: 2
                                    spacing: 1.5
                                    anchors.verticalCenter: parent.verticalCenter
                                    Repeater {
                                        model: 4
                                        Rectangle { width: 5.5; height: 5.5; radius: 1; color: Appearance.colors.colPrimary }
                                    }
                                }

                                // Taskbar search pill
                                Rectangle {
                                    width: 34; height: 14; radius: 7
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Appearance.colors.colLayer2
                                }

                                // Pinned app icons
                                Repeater {
                                    model: 3
                                    Item {
                                        required property int index
                                        width: 14; height: 18
                                        anchors.verticalCenter: parent.verticalCenter
                                        Rectangle {
                                            width: 12; height: 12; radius: 3
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.top
                                            anchors.topMargin: 1
                                            color: index === 0 ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                                        }
                                        Rectangle {
                                            visible: index === 0
                                            width: 6; height: 2; radius: 1
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.bottom: parent.bottom
                                            color: Appearance.colors.colPrimary
                                        }
                                    }
                                }
                            }

                            // Right: Tray + 2-line clock
                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3
                                    Repeater {
                                        model: 3
                                        Rectangle { width: 4.5; height: 4.5; radius: 2.25; color: Appearance.colors.colOnLayer1; opacity: 0.65 }
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Rectangle { width: 20; height: 4; radius: 2; color: Appearance.colors.colOnLayer0; opacity: 0.8 }
                                    Rectangle { width: 24; height: 3.5; radius: 1.75; color: Appearance.colors.colOnLayer1; opacity: 0.45 }
                                }
                            }
                        }
                    }
                }
            }
        }

        SettingsCardSection {
            id: settingsUiCard
            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: modulesTwoColumnGrid.columns === 2
                ? Math.max(panelStyleCard.implicitHeight, settingsUiCard.implicitHeight) : 0
            settingsTaskSection: "interface"
            visible: modulesPage.isAbyss || modulesPage.activeSection === "interface"
            expanded: true
            icon: "web_asset"
            title: Translation.tr("Settings UI")

            SettingsGroup {
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Overlay opens Settings above the shell for live previews.")
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                    wrapMode: Text.WordWrap
                }

                SettingsSwitch {
                    buttonIcon: "layers"
                    text: Translation.tr("Overlay mode (live preview)")
                    checked: Config.options?.settingsUi?.overlayMode ?? false
                    onCheckedChanged: Config.setNestedValue("settingsUi.overlayMode", checked)
                    StyledToolTip {
                        text: Translation.tr("Overlay replaces the separate Settings window. Restart required.")
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Overlay layout")
                    visible: Config.options?.settingsUi?.overlayMode ?? false

                    ConfigSelectionArray {
                        currentValue: Config.options?.settingsUi?.overlayStyle ?? "rail"
                        options: [
                            { displayName: Translation.tr("Nav rail"), icon: "view_sidebar", value: "rail" },
                            { displayName: Translation.tr("Focus"), icon: "grid_view", value: "focus" }
                        ]
                        onSelected: value => Config.setNestedValue("settingsUi.overlayStyle", value)
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: (Config.options?.settingsUi?.overlayStyle ?? "rail") === "focus"
                            ? Translation.tr("One page at a time: a grid of every settings page, then the page you pick, full width. Escape steps back.")
                            : Translation.tr("A persistent flat tab rail beside the page you are editing.")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        wrapMode: Text.WordWrap
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Overlay appearance")
                    visible: Config.options?.settingsUi?.overlayMode ?? false

                    ConfigSpinBox {
                        icon: "blur_on"
                        text: Translation.tr("Backdrop blur (%)")
                        value: Config.options?.settingsUi?.overlayAppearance?.backdropBlur ?? 0
                        from: 0
                        to: 100
                        stepSize: 10
                        onValueChanged: Config.setNestedValue("settingsUi.overlayAppearance.backdropBlur", value)
                        StyledToolTip {
                            text: Translation.tr("Blur wallpaper behind Settings; 0 disables the effect.")
                        }
                    }

                    ConfigSpinBox {
                        icon: "water"
                        text: Translation.tr("Background dim (%)")
                        value: Config.options?.settingsUi?.overlayAppearance?.scrimDim ?? 35
                        from: 0
                        to: 80
                        stepSize: 5
                        onValueChanged: Config.setNestedValue("settingsUi.overlayAppearance.scrimDim", value)
                        StyledToolTip {
                            text: Translation.tr("How dark the backdrop behind the Settings panel should be (0 = transparent, 80 = very dark)")
                        }
                    }

                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: modeHintRow.implicitHeight + 16
                    radius: Appearance.zzzEverywhere ? Appearance.zzz.cardRadius : Appearance.rounding.small
                    color: Appearance.zzzEverywhere ? "transparent" : Appearance.colors.colSurfaceContainerLow
                    border.width: Appearance.zzzEverywhere ? 0 : 1
                    border.color: Appearance.zzzEverywhere ? "transparent" : Appearance.colors.colLayer0Border
                    Behavior on radius {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
                    }
                    Behavior on color {
                        enabled: Appearance.animationsEnabled
                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                    }
                    Behavior on border.width {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
                    }
                    Behavior on border.color {
                        enabled: Appearance.animationsEnabled
                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                    }

                    ZzzPlate {
                        anchors.fill: parent
                        visible: Appearance.zzzEverywhere
                        fillColor: Appearance.colors.colLayer1
                        strokeColor: Appearance.zzz.hairline
                        radius: Appearance.zzz.cardRadius
                        chamfer: Appearance.zzz.cutCorner * 0.45
                        chamferTopRight: !Appearance.zzz.round
                    }

                    RowLayout {
                        id: modeHintRow
                        anchors {
                            fill: parent
                            margins: 8
                        }
                        spacing: 8

                        MaterialSymbol {
                            text: (Config.options?.settingsUi?.overlayMode ?? false) ? "layers" : "open_in_new"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colPrimary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                text: (Config.options?.settingsUi?.overlayMode ?? false)
                                    ? Translation.tr("Overlay mode")
                                    : Translation.tr("Window mode")
                                font {
                                    pixelSize: Appearance.font.pixelSize.small
                                    weight: Font.Medium
                                }
                                color: Appearance.colors.colOnSurface
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: (Config.options?.settingsUi?.overlayMode ?? false)
                                    ? Translation.tr("Settings will open as a floating panel over the shell. Press Esc or click outside to close.")
                                    : Translation.tr("Settings will open as a separate application window (current behavior).")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }
    }

    // ==================== MATERIAL II ====================
    SettingsCardSection {
        settingsTaskSection: "modules"
        visible: modulesPage.isIi && modulesPage.activeSection === "modules"
        expanded: true
        icon: "dashboard"
        title: Translation.tr("Core")

        SettingsGroup {
            SettingsSwitch {
                buttonIcon: "toolbar"
                text: Translation.tr("Bar")
                checked: modulesPage.isIiBarEnabled()
                onCheckedChanged: modulesPage.setIiBarEnabled(checked)
                StyledToolTip { text: Translation.tr("Main bar module. Orientation (horizontal/vertical) is configured in Bar settings.") }
            }

            SettingsSwitch {
                buttonIcon: "wallpaper"
                text: Translation.tr("Background")
                checked: modulesPage.isPanelEnabled("iiBackground")
                onCheckedChanged: modulesPage.setPanelEnabled("iiBackground", checked)
                StyledToolTip { text: Translation.tr("Desktop wallpaper with parallax effect and widgets") }
            }

            SettingsSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Niri Overview Backdrop")
                checked: modulesPage.isPanelEnabled("iiBackdrop")
                onCheckedChanged: modulesPage.setPanelEnabled("iiBackdrop", checked)
                StyledToolTip { text: Translation.tr("Blurred wallpaper shown in Niri's native overview (Mod+Tab)") }
            }

            SettingsSwitch {
                buttonIcon: "search"
                text: Translation.tr("Overview")
                checked: modulesPage.isPanelEnabled("iiOverview")
                onCheckedChanged: modulesPage.setPanelEnabled("iiOverview", checked)
                StyledToolTip { text: Translation.tr("App launcher, search and workspace grid (Super+Space)") }
            }

            SettingsSwitch {
                buttonIcon: "widgets"
                text: Translation.tr("Floating tools (Super+G)")
                checked: modulesPage.isPanelEnabled("iiOverlay")
                onCheckedChanged: modulesPage.setPanelEnabled("iiOverlay", checked)
                StyledToolTip { text: Translation.tr("Floating image and widgets panel (Super+G)") }
            }

            SettingsSwitch {
                buttonIcon: "left_panel_open"
                text: Translation.tr("Left Sidebar")
                checked: modulesPage.isPanelEnabled("iiSidebarLeft")
                onCheckedChanged: modulesPage.setPanelEnabled("iiSidebarLeft", checked)
                StyledToolTip { text: Translation.tr("AI assistant, translator, image browser") }
            }

            SettingsSwitch {
                buttonIcon: "right_panel_open"
                text: Translation.tr("Right Sidebar")
                checked: modulesPage.isPanelEnabled("iiSidebarRight")
                onCheckedChanged: modulesPage.setPanelEnabled("iiSidebarRight", checked)
                StyledToolTip { text: Translation.tr("Quick settings, notifications, calendar, system info") }
            }
        }
    }

    SettingsCardSection {
        settingsTaskSection: "modules"
        visible: modulesPage.isIi && modulesPage.activeSection === "modules"
        expanded: true
        icon: "notifications"
        title: Translation.tr("Feedback")

        SettingsGroup {
            SettingsSwitch {
                buttonIcon: "notifications"
                text: Translation.tr("Notification Popups")
                checked: modulesPage.isPanelEnabled("iiNotificationPopup")
                onCheckedChanged: modulesPage.setPanelEnabled("iiNotificationPopup", checked)
                StyledToolTip { text: Translation.tr("Toast notifications that appear on screen") }
            }

            SettingsSwitch {
                buttonIcon: "volume_up"
                text: Translation.tr("OSD")
                checked: modulesPage.isPanelEnabled("iiOnScreenDisplay")
                onCheckedChanged: modulesPage.setPanelEnabled("iiOnScreenDisplay", checked)
                StyledToolTip { text: Translation.tr("On-screen display for volume and brightness changes") }
            }

            SettingsSwitch {
                buttonIcon: "music_note"
                text: Translation.tr("Media Controls")
                checked: modulesPage.isPanelEnabled("iiMediaControls")
                onCheckedChanged: modulesPage.setPanelEnabled("iiMediaControls", checked)
                StyledToolTip { text: Translation.tr("Floating media player controls") }
            }
        }
    }

    SettingsCardSection {
        settingsTaskSection: "modules"
        visible: modulesPage.isIi && modulesPage.activeSection === "modules"
        expanded: true
        icon: "build"
        title: Translation.tr("Utilities")

        SettingsGroup {
            SettingsSwitch {
                buttonIcon: "lock"
                text: Translation.tr("Lock Screen")
                checked: modulesPage.isPanelEnabled("iiLock")
                onCheckedChanged: modulesPage.setPanelEnabled("iiLock", checked)
                StyledToolTip { text: Translation.tr("Custom lock screen with clock and password input") }
            }

            SettingsSwitch {
                buttonIcon: "power_settings_new"
                text: Translation.tr("Session Screen")
                checked: modulesPage.isPanelEnabled("iiSessionScreen")
                onCheckedChanged: modulesPage.setPanelEnabled("iiSessionScreen", checked)
                StyledToolTip { text: Translation.tr("Power menu: lock, logout, suspend, reboot, shutdown") }
            }

            SettingsSwitch {
                buttonIcon: "admin_panel_settings"
                text: Translation.tr("Polkit Agent")
                checked: modulesPage.isPanelEnabled("iiPolkit")
                onCheckedChanged: modulesPage.setPanelEnabled("iiPolkit", checked)
                StyledToolTip { text: Translation.tr("Password prompt for administrative actions") }
            }

            SettingsSwitch {
                buttonIcon: "screenshot_region"
                text: Translation.tr("Region Selector")
                checked: modulesPage.isPanelEnabled("iiRegionSelector")
                onCheckedChanged: modulesPage.setPanelEnabled("iiRegionSelector", checked)
                StyledToolTip { text: Translation.tr("Screen capture, OCR text extraction, color picker") }
            }

            SettingsSwitch {
                buttonIcon: "image"
                text: Translation.tr("Wallpaper Selector")
                checked: modulesPage.isPanelEnabled("iiWallpaperSelector")
                onCheckedChanged: modulesPage.setPanelEnabled("iiWallpaperSelector", checked)
                StyledToolTip { text: Translation.tr("File picker for changing wallpaper") }
            }

            SettingsSwitch {
                buttonIcon: "keyboard"
                text: Translation.tr("Cheatsheet")
                checked: modulesPage.isPanelEnabled("iiCheatsheet")
                onCheckedChanged: modulesPage.setPanelEnabled("iiCheatsheet", checked)
                StyledToolTip { text: Translation.tr("Keyboard shortcuts reference overlay") }
            }

            SettingsSwitch {
                buttonIcon: "keyboard_alt"
                text: Translation.tr("On-Screen Keyboard")
                checked: modulesPage.isPanelEnabled("iiOnScreenKeyboard")
                onCheckedChanged: modulesPage.setPanelEnabled("iiOnScreenKeyboard", checked)
                StyledToolTip { text: Translation.tr("Virtual keyboard for touch input") }
            }

            SettingsSwitch {
                buttonIcon: "tab"
                text: Translation.tr("Alt-Tab Switcher")
                checked: false
                enabled: false
                StyledToolTip { text: Translation.tr("Window switcher popup") }
            }

            SettingsSwitch {
                buttonIcon: "content_paste"
                text: Translation.tr("Clipboard History")
                checked: modulesPage.isPanelEnabled("iiClipboard")
                onCheckedChanged: modulesPage.setPanelEnabled("iiClipboard", checked)
                StyledToolTip { text: Translation.tr("Clipboard manager with history") }
            }
        }
    }

    SettingsCardSection {
        settingsTaskSection: "modules"
        visible: modulesPage.isIi && modulesPage.activeSection === "modules"
        expanded: true
        icon: "more_horiz"
        title: Translation.tr("Optional")

        SettingsGroup {
            SettingsSwitch {
                buttonIcon: "dock_to_bottom"
                text: Translation.tr("Dock")
                checked: modulesPage.isPanelEnabled("iiDock")
                onCheckedChanged: modulesPage.setPanelEnabled("iiDock", checked)
                StyledToolTip { text: Translation.tr("macOS-style dock with pinned and running apps") }
            }

            SettingsSwitch {
                buttonIcon: "rounded_corner"
                text: Translation.tr("Screen Corners")
                checked: modulesPage.isPanelEnabled("iiScreenCorners")
                onCheckedChanged: modulesPage.setPanelEnabled("iiScreenCorners", checked)
                StyledToolTip { text: Translation.tr("Allow opening sidebars by interacting with screen corners") }
            }

            SettingsSwitch {
                buttonIcon: "center_focus_strong"
                text: Translation.tr("Crosshair")
                checked: false
                enabled: false
                StyledToolTip { text: Translation.tr("Gaming crosshair overlay for games without built-in crosshair") }
            }
        }
    }

    // ==================== WAFFLE ====================
    SettingsCardSection {
        settingsTaskSection: "modules"
        visible: modulesPage.isWaffle && modulesPage.activeSection === "modules"
        expanded: true
        icon: "window"
        title: Translation.tr("Waffle Core")

        SettingsGroup {
            SettingsSwitch {
                buttonIcon: "toolbar"
                text: Translation.tr("Taskbar")
                checked: modulesPage.isPanelEnabled("wBar")
                onCheckedChanged: modulesPage.setPanelEnabled("wBar", checked)
                StyledToolTip { text: Translation.tr("Windows 11 style taskbar with app icons and system tray") }
            }

            SettingsSwitch {
                buttonIcon: "wallpaper"
                text: Translation.tr("Background")
                checked: modulesPage.isPanelEnabled("wBackground")
                onCheckedChanged: modulesPage.setPanelEnabled("wBackground", checked)
                StyledToolTip { text: Translation.tr("Desktop wallpaper") }
            }

            SettingsSwitch {
                buttonIcon: "grid_view"
                text: Translation.tr("Start Menu")
                checked: modulesPage.isPanelEnabled("wStartMenu")
                onCheckedChanged: modulesPage.setPanelEnabled("wStartMenu", checked)
                StyledToolTip { text: Translation.tr("Windows 11 style start menu with search and pinned apps (Super+Space)") }
            }

            SettingsSwitch {
                buttonIcon: "toggle_on"
                text: Translation.tr("Action Center")
                checked: modulesPage.isPanelEnabled("wActionCenter")
                onCheckedChanged: modulesPage.setPanelEnabled("wActionCenter", checked)
                StyledToolTip { text: Translation.tr("Quick settings panel with toggles and sliders") }
            }

            SettingsSwitch {
                buttonIcon: "notifications"
                text: Translation.tr("Notification Center")
                checked: modulesPage.isPanelEnabled("wNotificationCenter")
                onCheckedChanged: modulesPage.setPanelEnabled("wNotificationCenter", checked)
                StyledToolTip { text: Translation.tr("Notification panel with calendar") }
            }

            SettingsSwitch {
                buttonIcon: "notifications_active"
                text: Translation.tr("Notification Popups")
                checked: modulesPage.isPanelEnabled("wNotificationPopup")
                onCheckedChanged: modulesPage.setPanelEnabled("wNotificationPopup", checked)
                StyledToolTip { text: Translation.tr("Toast notifications that appear on screen (Windows 11 style)") }
            }

            SettingsSwitch {
                buttonIcon: "volume_up"
                text: Translation.tr("OSD")
                checked: modulesPage.isPanelEnabled("wOnScreenDisplay")
                onCheckedChanged: modulesPage.setPanelEnabled("wOnScreenDisplay", checked)
                StyledToolTip { text: Translation.tr("On-screen display for volume and brightness") }
            }

            SettingsSwitch {
                buttonIcon: "widgets"
                text: Translation.tr("Widgets Panel")
                checked: modulesPage.isPanelEnabled("wWidgets")
                onCheckedChanged: modulesPage.setPanelEnabled("wWidgets", checked)
                StyledToolTip { text: Translation.tr("Windows 11 style widgets sidebar") }
            }
        }
    }

    SettingsCardSection {
        settingsTaskSection: "modules"
        visible: modulesPage.isWaffle && modulesPage.activeSection === "modules"
        expanded: true
        icon: "share"
        title: Translation.tr("Shared Modules")

        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Supporting modules used alongside Waffle")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                wrapMode: Text.WordWrap
            }

            SettingsSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Niri Overview Backdrop")
                checked: modulesPage.isPanelEnabled("iiBackdrop")
                onCheckedChanged: modulesPage.setPanelEnabled("iiBackdrop", checked)
                StyledToolTip { text: Translation.tr("Blurred wallpaper shown in Niri's native overview (Mod+Tab)") }
            }

            SettingsSwitch {
                buttonIcon: "search"
                text: Translation.tr("Overview")
                checked: modulesPage.isPanelEnabled("iiOverview")
                onCheckedChanged: modulesPage.setPanelEnabled("iiOverview", checked)
                StyledToolTip { text: Translation.tr("Workspace grid (used by Start Menu)") }
            }

            SettingsSwitch {
                buttonIcon: "widgets"
                text: Translation.tr("Floating tools (Super+G)")
                checked: modulesPage.isPanelEnabled("iiOverlay")
                onCheckedChanged: modulesPage.setPanelEnabled("iiOverlay", checked)
                StyledToolTip { text: Translation.tr("Floating image and widgets panel (Super+G)") }
            }

            SettingsSwitch {
                buttonIcon: "lock"
                text: Translation.tr("Lock Screen")
                checked: modulesPage.isPanelEnabled("wLock")
                onCheckedChanged: modulesPage.setPanelEnabled("wLock", checked)
                StyledToolTip { text: Translation.tr("Custom lock screen with clock and password input") }
            }

            SettingsSwitch {
                buttonIcon: "power_settings_new"
                text: Translation.tr("Session Screen")
                checked: modulesPage.isPanelEnabled("wSessionScreen")
                onCheckedChanged: modulesPage.setPanelEnabled("wSessionScreen", checked)
                StyledToolTip { text: Translation.tr("Power menu: lock, logout, suspend, reboot, shutdown") }
            }

            SettingsSwitch {
                buttonIcon: "admin_panel_settings"
                text: Translation.tr("Polkit Agent")
                checked: modulesPage.isPanelEnabled("wPolkit")
                onCheckedChanged: modulesPage.setPanelEnabled("wPolkit", checked)
                StyledToolTip { text: Translation.tr("Password prompt for administrative actions") }
            }

            SettingsSwitch {
                buttonIcon: "screenshot_region"
                text: Translation.tr("Region Selector")
                checked: modulesPage.isPanelEnabled("iiRegionSelector")
                onCheckedChanged: modulesPage.setPanelEnabled("iiRegionSelector", checked)
                StyledToolTip { text: Translation.tr("Screen capture, OCR text extraction, color picker") }
            }

            SettingsSwitch {
                buttonIcon: "image"
                text: Translation.tr("Wallpaper Selector")
                checked: modulesPage.isPanelEnabled("iiWallpaperSelector")
                onCheckedChanged: modulesPage.setPanelEnabled("iiWallpaperSelector", checked)
                StyledToolTip { text: Translation.tr("File picker for changing wallpaper") }
            }

            SettingsSwitch {
                buttonIcon: "keyboard"
                text: Translation.tr("Cheatsheet")
                checked: modulesPage.isPanelEnabled("iiCheatsheet")
                onCheckedChanged: modulesPage.setPanelEnabled("iiCheatsheet", checked)
                StyledToolTip { text: Translation.tr("Keyboard shortcuts reference overlay") }
            }

            SettingsSwitch {
                buttonIcon: "keyboard_alt"
                text: Translation.tr("On-Screen Keyboard")
                checked: modulesPage.isPanelEnabled("iiOnScreenKeyboard")
                onCheckedChanged: modulesPage.setPanelEnabled("iiOnScreenKeyboard", checked)
                StyledToolTip { text: Translation.tr("Virtual keyboard for touch input") }
            }

            SettingsSwitch {
                buttonIcon: "tab"
                text: Translation.tr("Alt-Tab Switcher")
                checked: false
                enabled: false
                StyledToolTip { text: Translation.tr("Window switcher popup") }
            }

            SettingsSwitch {
                buttonIcon: "content_paste"
                text: Translation.tr("Clipboard History")
                checked: modulesPage.isPanelEnabled("iiClipboard")
                onCheckedChanged: modulesPage.setPanelEnabled("iiClipboard", checked)
                StyledToolTip { text: Translation.tr("Clipboard manager with history") }
            }

            SettingsSwitch {
                buttonIcon: "center_focus_strong"
                text: Translation.tr("Crosshair")
                checked: false
                enabled: false
                StyledToolTip { text: Translation.tr("Gaming crosshair overlay") }
            }
        }
    }
}
