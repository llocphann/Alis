pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
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
    property bool editing: GlobalStates.abyssEditing
        && (GlobalStates.abyssEditorTargetOutput === "" || GlobalStates.abyssEditorTargetOutput === root.outputName)
    // Presentation-only: false retains the hover target and user data.
    property bool showIcon: true
    signal notesEditorFocusChanged(string outputName, bool focused)
    property real contentScale: 1
    property int moduleRotation: -1
    property bool cornerWrap: false
    property string wrapCorner: "topLeft"
    property real wrapThickness: 32 * Appearance.fontSizeScale
    property real wrapArcRadius: 22
    property bool detached: false
    property string detachedShape: "pill"
    property real innerSpan: 0
    property real innerCross: 0
    readonly property int effectiveRotation: moduleRotation >= 0
        ? ((Math.round(moduleRotation / 90) * 90) % 360 + 360) % 360
        : (attachedEdge === "left" ? 270 : attachedEdge === "right" ? 90 : 0)
    // Physical orientation never chooses another feature implementation.
    // Keep the horizontal design/controls resident and rotate that one item.
    readonly property bool contentVertical: effectiveRotation === 90 || effectiveRotation === 270
    readonly property real contentRotation: effectiveRotation === 270 ? -90 : effectiveRotation
    readonly property var feature: content.item
    property var companionPopup: null
    function registerCompanionPopup(popup): void {
        if (!companionPopup) companionPopup = popup
    }
    function unregisterCompanionPopup(popup): void {
        if (companionPopup === popup) companionPopup = null
    }
    readonly property bool contentAvailable: {
        if (root.cornerWrap)
            return cornerWrapLoader.item ? (cornerWrapLoader.item.contentAvailable ?? true)
                : (root.editing || (root.kind !== "timer" && root.kind !== "shellUpdate"))
        const item = feature
        if (!item) return root.editing || (root.kind !== "timer" && root.kind !== "shellUpdate")
        if (root.kind === "timer" || root.kind === "shellUpdate")
            return Boolean(item.contentAvailable)
        return true
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
    function containsPointerPoint(px: real, py: real): bool {
        if (width <= 0 || height <= 0 || px < 0 || py < 0 || px > width || py > height)
            return false
        if (!root.cornerWrap)
            return true
        if (cornerWrapLoader.item)
            return cornerWrapLoader.item.containsArmPoint(px, py)
        const strip = Math.max(24, root.wrapThickness) + 3
        const mirrorX = root.wrapCorner === "topRight" || root.wrapCorner === "bottomRight"
        const mirrorY = root.wrapCorner === "bottomLeft" || root.wrapCorner === "bottomRight"
        const inHorizontalArm = mirrorY ? (py >= height - strip) : (py <= strip)
        const inVerticalArm = mirrorX ? (px >= width - strip) : (px <= strip)
        return inHorizontalArm || inVerticalArm
    }
    containmentMask: QtObject {
        function contains(point: point): bool {
            return root.containsPointerPoint(point.x, point.y)
        }
    }
    HoverHandler {
        id: hoverTracker
        onHoveredChanged: root.interaction(hovered ? .35 : -.15)
    }
    PointHandler { acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton; onActiveChanged: root.interaction(active ? 1 : -.3) }

    // Detached floating circle / rounded pill surface (iNiR iRiS island aesthetic).
    // Lives strictly outside AbyssField localSurfaces so it never melts back into the screen edge.
    StyledRectangularShadow {
        target: detachedPillBg
        radius: detachedPillBg.radius
        visible: root.detached && !root.cornerWrap && root.contentAvailable
            && !Appearance.gameModeMinimal
            && AbyssStyle.quality !== "performance"
            && (Config.options?.appearance?.screenEdge?.physicalShadow?.enabled ?? true)
        blur: Math.max(4, Math.min(20, Math.round((Config.options?.appearance?.screenEdge?.physicalShadow?.size ?? 15) * 0.75)))
        spread: 0
        offset: Qt.vector2d(0, 2)
        color: Qt.alpha(Appearance.m3colors.m3shadow, Math.max(0.18, Math.min(0.65, Number(Config.options?.appearance?.screenEdge?.physicalShadow?.opacity ?? 0.70) * 0.65)))
    }
    Rectangle {
        id: detachedPillBg
        objectName: "abyssDetachedPillSurface"
        anchors.fill: parent
        visible: root.detached && !root.cornerWrap && root.contentAvailable
        radius: Math.min(width, height) * 0.5
        readonly property real surfaceAlpha: AbyssStyle.surfaceOpacity >= 0.999 ? 1.0 : AbyssStyle.surfaceOpacity
        color: root.hovered
            ? Qt.alpha(ColorUtils.mix(AbyssStyle.surfaceDeep, AbyssStyle.accent, 0.08), detachedPillBg.surfaceAlpha)
            : AbyssStyle.surface
        border.width: 1
        border.color: root.hovered
            ? Qt.alpha(AbyssStyle.accent, 0.56)
            : Qt.alpha(AbyssStyle.specular, Appearance.m3colors.darkmode ? 0.16 : 0.24)
        Behavior on color { enabled: AbyssStyle.motionEnabled; ColorAnimation { duration: AbyssStyle.motionFast } }
        Behavior on border.color { enabled: AbyssStyle.motionEnabled; ColorAnimation { duration: AbyssStyle.motionFast } }

        // Subtle inner hairline rim matching Abyss / iRiS floating island sheen
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, parent.radius - 1)
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(AbyssStyle.specular, root.hovered ? 0.20 : 0.10)
            visible: Appearance.effectsEnabled && AbyssStyle.quality !== "performance"
        }
    }

    Loader {
        id: content
        active: !root.cornerWrap
        visible: !root.cornerWrap
        // Explicit real-valued centering avoids anchor-line rounding at
        // fractional extents, which moves a rotated hit rectangle by .5px.
        x: (root.width-width)/2
        y: (root.height-height)/2
        readonly property real designWidthPx: root.detached
            ? ((root.contentVertical === root.vertical)
                ? (root.innerSpan > 0 ? root.innerSpan : root.width)
                : (root.innerCross > 0 ? root.innerCross : root.height))
            : (root.contentVertical ? root.height : root.width)
        width: designWidthPx/Math.max(.01,root.contentScale)
        height: 32*Appearance.fontSizeScale
        scale: root.contentScale
        rotation: root.contentRotation
        sourceComponent: root.kind === "resources" ? resources
            : root.kind === "clock" ? clock
            : root.kind === "media" ? media
            : root.kind === "cava" ? cava
            : root.kind === "battery" ? battery
            : root.kind === "workspaces" ? workspaces : root.kind === "distroIcon" ? distro
            : root.kind === "activeWindow" ? activeWindow : root.kind === "tray" ? tray
            : root.kind === "utilButtons" ? utilities
            : root.kind === "timer" ? timer
            : root.kind === "shellUpdate" ? update : root.kind === "weather" ? weather
            : root.kind === "notesTimers" ? notesTimers
            : root.kind === "notificationActivity" ? notificationActivity : taskbar
    }
    Loader {
        id: cornerWrapLoader
        objectName: "abyssCornerWrapContentLoader"
        anchors.fill: parent
        active: root.cornerWrap
        visible: root.cornerWrap
        sourceComponent: AbyssCornerWrapContent {
            kind: root.kind
            outputName: root.outputName
            editing: root.editing
            wrapCorner: root.wrapCorner
            wrapThickness: root.wrapThickness
            wrapArcRadius: root.wrapArcRadius
            contentScale: root.contentScale
            onRequest: k => root.request(k)
            onHoverRequest: k => root.hoverRequest(k)
            onHoverState: (k, h) => root.hoverState(k, h)
        }
    }
    Component { id: resources; Shared.Resources { contentRotation: root.contentRotation } }
    Component { id: clock; Shared.ClockWidget { sharedTypography:true; showDate: Config.options?.bar?.verbose ?? true; contentRotation: root.contentRotation } }
    Component { id: media; Shared.Media { edgeHostedExpansion: true; contentRotation: root.contentRotation } }
    Component { id: cava; Shared.BarCavaEqualizerModule { vertical: false; contentRotation: root.contentRotation } }
    Component { id: battery; Shared.BatteryIndicator { contentRotation: root.contentRotation } }
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
                contentRotation: root.contentRotation
            }

            Shared.StyledPopup {
                hoverTarget: launcherAnchor
                liquidPresentationKind: "launcher"

                AbyssLauncherControlsPopup {}
            }
        }
    }
    Component { id: activeWindow; Shared.ActiveWindow { contentRotation: root.contentRotation } }
    Component {
        id: tray
        Shared.SysTray {
            vertical: false
            contentRotation: root.contentRotation
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
            contentRotation: root.contentRotation
            compactRequested: false
            abyssMicMeterEnabled: true
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
                color: hit.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                border.width: 0
                border.color: "transparent"
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
    Component { id: timer; Shared.TimerIndicator { vertical: false; contentRotation: root.contentRotation; editPreview: root.editing } }
    Component { id: update; Shared.ShellUpdateIndicator { vertical: false; contentRotation: root.contentRotation; editPreview: root.editing } }
    Component { id: weather; WeatherBar { vertical: false; contentRotation: root.contentRotation } }
    Component {
        id: workspaces
        Shared.Workspaces {
            vertical: false
            contentRotation: root.contentRotation
            popupVertical: root.contentVertical
            MouseArea {
                anchors.fill: parent; acceptedButtons: Qt.RightButton
                onPressed: GlobalStates.toggleOverview(root.outputName)
            }
        }
    }
    Component { id: taskbar; Shared.BarTaskbar { vertical: false; contentRotation: root.contentRotation; barPosition: root.attachedEdge; parentWindow: root.QsWindow.window; slotSize: 32 } }

}
