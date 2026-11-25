pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings
import qs.services

Item {
    id: root
    objectName: "irisPrismHero"

    property int pageIndex: 2
    property var pageSpec: null
    property Item currentPageItem: null
    property bool canGoBack: false
    property bool canGoForward: false
    property bool railOpen: false

    signal backClicked()
    signal forwardClicked()
    signal homeClicked()
    signal railToggleClicked()

    readonly property string clusterLabel: {
        const clusters = SettingsPageRegistryData.irisClusters ?? []
        for (let i = 0; i < clusters.length; i++) {
            const cl = clusters[i]
            if ((cl?.pages ?? []).indexOf(root.pageIndex) >= 0)
                return String(cl.label ?? "")
        }
        return Translation.tr("SETTINGS")
    }

    readonly property string areaTitle: String(root.pageSpec?.name ?? Translation.tr("Settings"))

    readonly property string areaSubtitle: String(root.pageSpec?.desc ?? "")

    readonly property string areaIcon: String(root.pageSpec?.icon ?? "settings")

    readonly property string statusSummary: {
        const key = String(root.pageSpec?.key ?? "")
        switch (key) {
        case "abyss":
        case "bar":
            return Config.options?.panelFamily === "abyss"
                ? Translation.tr("Abyss Liquid Perimeter")
                : (Config.options?.panelFamily === "waffle" ? Translation.tr("Waffle Taskbar") : Translation.tr("Material II Bar"))
        case "themes":
            return (Appearance.m3colors?.darkmode ?? true) ? Translation.tr("Dark scheme") : Translation.tr("Light scheme")
        case "wallpaper": {
            const blurOn = Boolean(Config.options?.background?.effects?.enableBlur ?? false)
            return blurOn ? Translation.tr("Blur enabled") : Translation.tr("Crisp backdrop")
        }
        case "effects":
            return Appearance.animationsEnabled ? Translation.tr("Motion active") : Translation.tr("Reduced motion")
        case "companion":
            return (Config.options?.abyss?.companion?.enabled ?? false) ? Translation.tr("Companion active") : Translation.tr("Companion paused")
        case "ai":
            return (Config.options?.policies?.ai ?? 1) !== 0 ? Translation.tr("Assistant ready") : Translation.tr("AI disabled")
        case "compositor":
            return Translation.tr("%1 display(s)").arg(String(Quickshell.screens?.length ?? 1))
        case "system":
            return Math.round((Audio.value ?? 0) * 100) + "% · " + (Notifications.silent ? Translation.tr("DND") : Translation.tr("Alerts on"))
        case "abyss-popups":
            return Notifications.silent ? Translation.tr("Do not disturb") : Translation.tr("Live popups")
        case "dock":
            return (Config.options?.dock?.enable ?? true) ? Translation.tr("Dock enabled") : Translation.tr("Dock hidden")
        case "about":
            return SystemInfo.distroName || "Linux"
        default: {
            const count = root.currentPageItem?.irisSectionGroups?.length ?? 0
            return count > 0 ? Translation.tr("%1 sections").arg(String(count)) : ""
        }
        }
    }

    readonly property var primaryAction: {
        const key = String(root.pageSpec?.key ?? "")
        switch (key) {
        case "wallpaper":
            return { icon: "wallpaper", label: Translation.tr("Change wallpaper"), kind: "wallpaper" }
        case "themes":
            return {
                icon: (Appearance.m3colors?.darkmode ?? true) ? "light_mode" : "dark_mode",
                label: (Appearance.m3colors?.darkmode ?? true) ? Translation.tr("Light mode") : Translation.tr("Dark mode"),
                kind: "toggleTheme"
            }
        case "abyss":
        case "bar":
        case "shell-layout":
            return Config.options?.panelFamily === "abyss"
                ? { icon: "edit", label: Translation.tr("Edit Abyss layout"), kind: "abyssEdit" }
                : null
        case "system":
            return { icon: "lock", label: Translation.tr("Lock now"), kind: "lock" }
        case "companion":
            return {
                icon: (Config.options?.abyss?.companion?.enabled ?? false) ? "pause_circle" : "play_circle",
                label: (Config.options?.abyss?.companion?.enabled ?? false) ? Translation.tr("Pause Companion") : Translation.tr("Enable Companion"),
                kind: "toggleCompanion"
            }
        default:
            return null
        }
    }

    function _triggerPrimaryAction(): void {
        const act = root.primaryAction
        if (!act)
            return
        switch (act.kind) {
        case "wallpaper":
            Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "ipc", "call", "wallpaperSelector", "toggle"])
            break
        case "toggleTheme":
            IrisState.triggerTile("darkMode")
            break
        case "abyssEdit":
            if (Config.options?.panelFamily === "abyss" && typeof GlobalStates.startAbyssEditing === "function")
                GlobalStates.startAbyssEditing()
            break
        case "lock":
            GlobalStates.settingsOverlayOpen = false
            Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "lock", "activate"])
            break
        case "toggleCompanion":
            IrisState.triggerTile("companion")
            break
        default:
            break
        }
    }

    readonly property real innerWidth: Math.min(Math.max(320, root.width - 40), IrisTheme.pageMaxWidth)
    implicitHeight: mainCol.implicitHeight + 14

    ColumnLayout {
        id: mainCol
        anchors.top: parent.top
        anchors.topMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.innerWidth
        spacing: 8

        // ── Breadcrumb & Navigation Utility Row ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            // Back / Forward buttons
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 26
                height: 26
                radius: 8
                opacity: root.canGoBack ? 1.0 : 0.38
                color: backMouse.containsMouse && root.canGoBack ? IrisTheme.plateHover : IrisTheme.plate
                border.width: 1
                border.color: IrisTheme.hairline

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: 15
                    color: IrisTheme.text
                }

                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    enabled: root.canGoBack
                    hoverEnabled: true
                    cursorShape: root.canGoBack ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.backClicked()
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 26
                height: 26
                radius: 8
                opacity: root.canGoForward ? 1.0 : 0.38
                color: fwdMouse.containsMouse && root.canGoForward ? IrisTheme.plateHover : IrisTheme.plate
                border.width: 1
                border.color: IrisTheme.hairline

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_forward"
                    iconSize: 15
                    color: IrisTheme.text
                }

                MouseArea {
                    id: fwdMouse
                    anchors.fill: parent
                    enabled: root.canGoForward
                    hoverEnabled: true
                    cursorShape: root.canGoForward ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.forwardClicked()
                }
            }

            // Sub-view back pill when inside a drilled-down sub-view
            Rectangle {
                visible: Boolean(root.currentPageItem?.isSubViewActive)
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: subBackRow.implicitWidth + 14
                implicitHeight: 26
                radius: 13
                color: subBackMouse.containsMouse ? IrisTheme.accentTintHover : IrisTheme.accentTint
                border.width: 1
                border.color: IrisTheme.accentBorder

                Row {
                    id: subBackRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "chevron_left"
                        iconSize: 15
                        color: IrisTheme.accent
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.areaTitle
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: IrisTheme.accent
                    }
                }

                MouseArea {
                    id: subBackMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.currentPageItem && typeof root.currentPageItem.exitSubView === "function")
                            root.currentPageItem.exitSubView()
                    }
                }
            }

            // Breadcrumb eyebrow: Home › CLUSTER › Area
            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.leftMargin: 4
                spacing: 5

                StyledText {
                    text: Translation.tr("HOME")
                    font.pixelSize: Appearance.font.pixelSize.smallest - 1
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                    color: homeCrumbMouse.containsMouse ? IrisTheme.accent : IrisTheme.textDim

                    MouseArea {
                        id: homeCrumbMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.homeClicked()
                    }
                }

                StyledText {
                    text: "›"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: IrisTheme.textDim
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.clusterLabel + " · " + root.areaTitle.toUpperCase()
                    font.pixelSize: Appearance.font.pixelSize.smallest - 1
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                    color: IrisTheme.textMuted
                }
            }

            // Right Context Rail Toggle Button
            Rectangle {
                id: railToggleBtn
                objectName: "irisRailToggleButton"
                Layout.alignment: Qt.AlignVCenter
                width: 28
                height: 26
                radius: 8
                color: root.railOpen
                    ? IrisTheme.accentTint
                    : (railToggleMouse.containsMouse ? IrisTheme.plateHover : IrisTheme.plate)
                border.width: 1
                border.color: root.railOpen ? IrisTheme.accentBorder : IrisTheme.hairline

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "dock_to_left"
                    iconSize: 16
                    color: root.railOpen ? IrisTheme.accent : IrisTheme.textMuted
                }

                MouseArea {
                    id: railToggleMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.railToggleClicked()
                }

                StyledToolTip {
                    extraVisibleCondition: railToggleMouse.containsMouse
                    text: root.railOpen ? Translation.tr("Hide context rail") : Translation.tr("Show context rail")
                }
            }
        }

        // ── Prism Refraction Light-Wash Hero Card ──
        Rectangle {
            id: heroCard
            Layout.fillWidth: true
            implicitHeight: heroRow.implicitHeight + 24
            radius: IrisTheme.radiusCard
            color: IrisTheme.plate
            border.width: 1
            border.color: IrisTheme.hairline
            clip: true

            // Subtle horizontal Abyss-accented Prism wash (zero ShaderEffect/FBO cost)
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: IrisTheme.heroWashStart }
                    GradientStop { position: 0.48; color: IrisTheme.heroWashMid }
                    GradientStop { position: 1.0; color: IrisTheme.heroWashEnd }
                }
            }

            RowLayout {
                id: heroRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 14

                // Area Glyph Plate
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: Math.round(42 * IrisTheme.scale)
                    height: Math.round(42 * IrisTheme.scale)
                    radius: Math.round(12 * IrisTheme.scale)
                    color: IrisTheme.accentTint
                    border.width: 1
                    border.color: IrisTheme.accentBorder

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.areaIcon === "Tune" ? "tune" : root.areaIcon
                        rotation: Number(root.pageSpec?.iconRotation ?? 0)
                        iconSize: Math.round(22 * IrisTheme.scale)
                        color: IrisTheme.accent
                    }
                }

                // Title + 1-line concise subtitle
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        StyledText {
                            Layout.minimumWidth: 0
                            text: Boolean(root.currentPageItem?.isSubViewActive)
                                ? String(root.currentPageItem?.activeSubViewTitle || root.areaTitle)
                                : root.areaTitle
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.weight: Font.Bold
                            color: IrisTheme.text
                        }

                        Rectangle {
                            visible: root.statusSummary.length > 0 && heroCard.width >= 520
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: statusText.implicitWidth + 14
                            implicitHeight: Math.round(20 * IrisTheme.scale)
                            radius: Math.round(implicitHeight / 2)
                            color: Qt.alpha(Appearance.colors.colLayer2Base, 0.55)
                            border.width: 1
                            border.color: IrisTheme.hairline

                            StyledText {
                                id: statusText
                                anchors.centerIn: parent
                                text: root.statusSummary
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: IrisTheme.textSecondary
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    StyledText {
                        visible: root.areaSubtitle.length > 0
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: root.areaSubtitle
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: IrisTheme.textMuted
                        maximumLineCount: 1
                    }
                }

                // Contextual Primary Action Pill
                Rectangle {
                    visible: heroCard.width >= 440 && root.primaryAction !== null
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: actionBtnRow.implicitWidth + 20
                    implicitHeight: Math.round(32 * IrisTheme.scale)
                    radius: Math.round(implicitHeight / 2)
                    color: heroActionMouse.containsMouse ? IrisTheme.accentTintHover : IrisTheme.accentTint
                    border.width: 1
                    border.color: IrisTheme.accentBorder

                    Row {
                        id: actionBtnRow
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(root.primaryAction?.icon ?? "tune").toLowerCase()
                            iconSize: 16
                            color: IrisTheme.accent
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(root.primaryAction?.label ?? "")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: IrisTheme.accent
                        }
                    }

                    MouseArea {
                        id: heroActionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root._triggerPrimaryAction()
                    }
                }
            }
        }
    }
}
