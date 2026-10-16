pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.bar as Shared
import qs.modules.bar.weather
import qs.modules.abyss.looks
import qs.modules.abyss.content
import qs.modules.screenCorners
import qs.modules.notificationCenter

// Mature feature controls, with popup ownership discovered from this ancestor.
Item {
    id: root
    required property string kind
    required property string outputName
    property var liquidController: null
    property string attachedEdge: "top"
    property string popupJoinedEdge: ""
    property bool vertical: false
    property bool compact: false
    // Presentation-only: false retains the hover target and user data.
    property bool showIcon: true
    signal notesEditorFocusChanged(string outputName, bool focused)
    property real contentScale: 1
    // Physical orientation never chooses another feature implementation.
    // Keep the horizontal design/controls resident and rotate that one item.
    readonly property bool contentVertical: attachedEdge === "left" || attachedEdge === "right"
    readonly property real contentRotation: attachedEdge === "left" ? -90
        : attachedEdge === "right" ? 90 : 0
    readonly property var feature: content.item
    property var companionPopup: null
    function registerCompanionPopup(popup): void {
        if (!companionPopup) companionPopup = popup
    }
    function unregisterCompanionPopup(popup): void {
        if (companionPopup === popup) companionPopup = null
    }
    readonly property real naturalSpan: {
        const item = feature
        if (!item) return 0
        // Timer/Update are conditional indicators. Their old implicitWidth
        // animation must never reserve an empty Edge slot after they hide.
        if ((kind === "timer" || kind === "shellUpdate") && !item.contentAvailable)
            return 0
        if (kind === "activeWindow") return Math.min(item.maxContentWidth ?? 220,
                Math.max(60,item.contentImplicitWidth))
        if (kind === "taskbar") return Math.min(320,Math.max(40,item.dockItems.length*item.itemPitch+item.contentInset))
        return item.implicitWidth
    }
    readonly property bool hovered: hoverTracker.hovered
    signal interaction(real strength)
    signal request(string kind)
    signal hoverRequest(string kind)
    signal hoverState(string kind, bool hovered)
    HoverHandler {
        id: hoverTracker
        onHoveredChanged: root.interaction(hovered ? .35 : -.15)
    }
    PointHandler { acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton; onActiveChanged: root.interaction(active ? 1 : -.3) }
    Loader {
        id: content
        // Explicit real-valued centering avoids anchor-line rounding at
        // fractional extents, which moves a rotated hit rectangle by .5px.
        x: (root.width-width)/2
        y: (root.height-height)/2
        width: (root.contentVertical ? root.height : root.width)/Math.max(.01,root.contentScale)
        height: 32*Appearance.fontSizeScale
        scale: root.contentScale
        rotation: root.contentRotation
        sourceComponent: root.kind === "resources" ? resources
            : root.kind === "clock" ? clock
            : root.kind === "media" ? media
            : root.kind === "battery" ? battery
            : root.kind === "workspaces" ? workspaces : root.kind === "distroIcon" ? distro
            : root.kind === "activeWindow" ? activeWindow : root.kind === "tray" ? tray
            : root.kind === "utilButtons" ? utilities
            : root.kind === "timer" ? timer
            : root.kind === "shellUpdate" ? update : root.kind === "weather" ? weather
            : root.kind === "notesTimers" ? notesTimers
            : root.kind === "notificationActivity" ? notificationActivity : taskbar
    }
    Component { id: resources; Shared.Resources {} }
    Component { id: clock; Shared.ClockWidget { sharedTypography:true; showDate: Config.options?.bar?.verbose ?? true } }
    Component { id: media; Shared.Media { edgeHostedExpansion: true } }
    Component { id: battery; Shared.BatteryIndicator {} }
    // Launcher follows the same ownership model as Battery: the source control
    // owns one mature StyledPopup, and Abyss only rehosts that popup into the
    // output field. No GlobalStates generic-popup handoff is involved.
    Component {
        id: distro
        MouseArea {
            id: launcherAnchor
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            implicitWidth: distroIcon.implicitWidth
            implicitHeight: distroIcon.implicitHeight

            Shared.DistroIcon {
                id: distroIcon
                anchors.fill: parent
            }

            Shared.StyledPopup {
                hoverTarget: launcherAnchor
                liquidPresentationKind: "launcher"

                AbyssLauncherControlsPopup {}
            }
        }
    }
    Component { id: activeWindow; Shared.ActiveWindow {} }
    Component {
        id: tray
        Shared.SysTray {
            vertical: false
            showSeparator: false
            showOverflowMenu: true
            onHoverPopupRequested: kind => root.hoverRequest(kind)
            onConnectivityHoverChanged: (kind, hovered) =>
                root.hoverState(kind, hovered)
        }
    }
    Component {
        id: utilities
        Shared.UtilButtons {
            vertical: false
            compactRequested: false
            showUtilitiesLauncher:
                Config.options?.bar?.utilButtons?.showUtilitiesLauncher ?? true
            onUtilitiesRequested: root.request("utilities")
            onUtilitiesHoverChanged: hovered => {
                root.hoverState("utilities", hovered)
                if (hovered)
                    root.hoverRequest("utilities")
            }
        }
    }
    // ABYSS-R15: these are launchers, not new feature backends. Both mature
    // StyledPopups reuse their existing stores and are rehosted by liquid.
    // The small cross-axis extension reaches the literal physical screen edge.
    // Its compositor mask is correspondingly bounded in AbyssBar.
    component UnifiedEdgeFace: Item {
        required property var moduleRoot
        property string glyph: ""
        property string description: ""
        property Item trigger: hit
        // A live unified module always paints its circular button. Toggling
        // Show icon off in Settings unmounts this launcher and gives hover
        // ownership back to the legacy Screen Corner Edgebar.
        implicitWidth: 36*Appearance.fontSizeScale
        implicitHeight: 32*Appearance.fontSizeScale
        readonly property real iconDiameter: 30*Appearance.fontSizeScale
        MouseArea {
            id: hit
            x: (parent.width-parent.iconDiameter)/2
            y: (parent.height-parent.iconDiameter)/2
            width: parent.iconDiameter
            height: parent.iconDiameter
            enabled: moduleRoot.showIcon
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            Accessible.role: Accessible.Button
            Accessible.name: parent.description
            Rectangle {
                anchors.centerIn: parent
                width: 30*Appearance.fontSizeScale
                height: width
                radius: width/2
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colLayer2
                visible: hit.parent.moduleRoot.showIcon
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: hit.parent.glyph
                    iconSize: 18*Appearance.fontSizeScale
                    rotation: -hit.parent.moduleRoot.contentRotation
                    color: Appearance.colors.colPrimary
                }
            }
            // The popup itself is the hover feedback. No second text tooltip.
        }
    }
    Component {
        id: notesTimers
        UnifiedEdgeFace {
            id: notesFace
            moduleRoot: root
            glyph: "sticky_note_2"
            description: "QuickNotes & Timers"
            // Live Module Icon hover and click are both confined to the
            // painted glyph; Edgebar Hover uses the original corner popup.
            // Click toggles the mature popup's own independent pin state.
            Connections {
                target: notesFace.trigger
                function onClicked() { notesPopup.popupPinned = !notesPopup.popupPinned }
            }
            QuickNotesPopup {
                id: notesPopup
                // Use the module kind for placement; legacy corner IPC
                // offsets must never override the draggable module anchor.
                liquidPresentationKind: "notesTimers"
                strictSourceHover: true
                anchorItem: notesFace.trigger
                cornerAttachmentEdge: root.attachedEdge
                cornerAttachmentThickness: -1
                onEditorFocusedChanged: root.notesEditorFocusChanged(root.outputName, editorFocused)
            }
        }
    }
    Component {
        id: notificationActivity
        UnifiedEdgeFace {
            id: notificationFace
            moduleRoot: root
            glyph: "notifications"
            description: "Notifications & Activities"
            Connections {
                target: notificationFace.trigger
                function onClicked() {
                    if (notificationPopup.presentationActive)
                        notificationPopup.enterKeyboardMode()
                    else
                        GlobalStates.openNotificationCenter(root.outputName)
                }
            }
            NotificationCenterPopup {
                id: notificationPopup
                liquidPresentationKind: "notificationActivity"
                strictSourceHover: true
                anchorItem: notificationFace.trigger
                outputName: root.outputName
                moduleAnchorMode: true
                cornerAttachmentEdge: root.attachedEdge
                cornerAttachmentThickness: -1
            }
        }
    }
    Component { id: timer; Shared.TimerIndicator { vertical: false } }
    Component { id: update; Shared.ShellUpdateIndicator { vertical: false } }
    Component { id: weather; WeatherBar { vertical: false } }
    Component {
        id: workspaces
        Shared.Workspaces {
            vertical: false
            MouseArea {
                anchors.fill: parent; acceptedButtons: Qt.RightButton
                onPressed: GlobalStates.toggleOverview(root.outputName)
            }
        }
    }
    Component { id: taskbar; Shared.BarTaskbar { vertical: false; barPosition: root.attachedEdge; parentWindow: root.QsWindow.window; slotSize: 32 } }

}
