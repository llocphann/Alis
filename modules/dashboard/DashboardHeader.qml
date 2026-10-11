import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.looks

/**
 * Dashboard navigation: uptime at left, page dots at center, actions at right.
 */
Item {
    id: root
    implicitHeight: Math.max(32, actions.implicitHeight)

    property bool editMode: false
    property bool showActions: true
    property int currentPage: 0
    property int pageCount: 1
    property var pageIds: ["dashboard", "music"]
    property bool navigationAllowed: true
    readonly property bool narrow: width < 620
    readonly property bool abyss: Config.options?.panelFamily === "abyss"
    signal pageRequested(int index)
    signal editModeRequested
    signal horizontalWheel(var event)
    WheelHandler {
        target: null
        orientation: Qt.Horizontal
        blocking: false
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: root.navigationAllowed && root.pageCount > 1 && !root.editMode
        onWheel: event => root.horizontalWheel(event)
    }
    Keys.onLeftPressed: event => {
        if (root.navigationAllowed && !root.editMode && root.currentPage > 0) {
            root.pageRequested(root.currentPage - 1)
            event.accepted = true
        } else event.accepted = false
    }
    Keys.onRightPressed: event => {
        if (root.navigationAllowed && !root.editMode && root.currentPage < root.pageCount - 1) {
            root.pageRequested(root.currentPage + 1)
            event.accepted = true
        } else event.accepted = false
    }

    readonly property bool inirEverywhere: Appearance.inirEverywhere
    readonly property bool auroraEverywhere: Appearance.auroraEverywhere
    readonly property bool showPowerButtons: Config.options?.dashboard?.showPowerButtons ?? true
    readonly property color colText: abyss ? (Appearance.m3colors.darkmode ? AbyssStyle.textColor : "#000000") : Appearance.angelEverywhere ? Appearance.angel.colText : inirEverywhere ? Appearance.inir.colText : Appearance.colors.colOnLayer0
    readonly property color colSubtext: abyss ? (Appearance.m3colors.darkmode ? AbyssStyle.textColorMuted : Qt.alpha("#000000", .66)) : Appearance.angelEverywhere ? Appearance.angel.colTextSecondary : inirEverywhere ? Appearance.inir.colTextSecondary : Appearance.colors.colSubtext

    component HeaderButton: RippleButton {
        id: headerButton
        property alias iconName: headerSymbol.text
        property string tooltip: ""
        implicitWidth: root.narrow ? 30 : 38
        implicitHeight: root.narrow ? 30 : 38
        buttonRadius: toggled ? Appearance.rounding.normal : Appearance.rounding.full
        colBackground: root.abyss ? Qt.alpha(AbyssStyle.accent, .05) : Appearance.angelEverywhere ? Appearance.angel.colGlassCard : root.inirEverywhere ? Appearance.inir.colLayer1 : root.auroraEverywhere ? Appearance.aurora.colSubSurface : Appearance.colors.colLayer1
        colBackgroundHover: root.abyss ? Qt.alpha(AbyssStyle.accent, .12) : Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover : root.inirEverywhere ? Appearance.inir.colLayer1Hover : root.auroraEverywhere ? Appearance.aurora.colSubSurfaceHover : Appearance.colors.colLayer1Hover
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        Behavior on buttonRadius {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        contentItem: MaterialSymbol {
            id: headerSymbol
            anchors.centerIn: parent
            iconSize: 20
            horizontalAlignment: Text.AlignHCenter
            color: headerButton.toggled ? Appearance.colors.colOnSecondaryContainer : root.colText
        }
        StyledToolTip {
            text: headerButton.tooltip
        }
    }

    RowLayout {
        id: actions
        visible: root.showActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.narrow ? 3 : 8

        HeaderButton {
            enabled: root.pageIds[root.currentPage] === "dashboard"
            iconName: root.editMode ? "done" : "edit"
            tooltip: root.editMode ? Translation.tr("Done editing") : Translation.tr("Edit widgets")
            toggled: root.editMode
            onClicked: root.editModeRequested()
        }
        HeaderButton {
            iconName: "notifications_paused"
            tooltip: Translation.tr("Do Not Disturb")
            toggled: Notifications.silent
            onClicked: Notifications.toggleSilent()
        }
        HeaderButton {
            iconName: "wallpaper"
            tooltip: Translation.tr("Wallpapers")
            onClicked: {
                GlobalStates.dashboardOpen = false;
                GlobalStates.wallpaperSelectorOpen = true;
            }
        }
        HeaderButton {
            iconName: "settings"
            tooltip: Translation.tr("Settings")
            onClicked: {
                GlobalStates.dashboardOpen = false;
                Quickshell.execDetached([Quickshell.shellPath("scripts/inir"), "settings"]);
            }
        }
        HeaderButton {
            visible: root.showPowerButtons
            iconName: "lock"
            tooltip: Translation.tr("Lock")
            onClicked: {
                GlobalStates.dashboardOpen = false;
                GlobalStates.screenLocked = true;
            }
        }
        HeaderButton {
            visible: root.showPowerButtons
            iconName: "power_settings_new"
            tooltip: Translation.tr("Session")
            onClicked: {
                GlobalStates.dashboardOpen = false;
                GlobalStates.sessionOpen = true;
            }
        }
    }
    RowLayout {
        id: pages
        objectName: "dashboardPageDots"
        anchors.centerIn: parent
        spacing: 4
        visible: root.pageCount > 1
        Repeater {
            model: root.pageCount
            delegate: RippleButton {
                required property int index
                objectName: "dashboardPage" + index
                implicitWidth: 24
                implicitHeight: 32
                buttonRadius: 16
                enabled: root.navigationAllowed && !root.editMode
                Accessible.name: root.pageIds[index] === "dashboard" ? Translation.tr("Dashboard")
                    : root.pageIds[index] === "music" ? Translation.tr("Music") : Translation.tr("Weekly Planner")
                colBackground: "transparent"
                colBackgroundHover: Qt.alpha(root.colText, .08)
                contentItem: Item {
                    Rectangle {
                        objectName: "dashboardPageDot" + index
                        anchors.centerIn: parent
                        width: 8
                        height: 8
                        radius: 4
                        color: index === root.currentPage ? root.colText : Qt.alpha(root.colText, .35)
                    }
                }
                onClicked: root.pageRequested(index)
                StyledToolTip {
                    text: parent.Accessible.name
                }
            }
        }
    }
    RowLayout {
        id: uptime
        visible: root.showActions
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Math.max(0, root.width / 2 - pages.width / 2 - 12))
        spacing: 8

        MaterialSymbol {
            text: "timelapse"
            iconSize: 20
            color: root.colSubtext
        }
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: Translation.tr("Uptime: %1").arg(DateTime.uptime)
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.colSubtext
        }
    }
}
