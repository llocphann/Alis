import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

/**
 * A group of notifications from the same app.
 * Similar to Android's notifications.
 *
 * Popup vs Sidebar behavior:
 * - Sidebar: Smooth height animations for expand/collapse (panel doesn't resize)
 * - Popup: Instant height changes to avoid Wayland window resize stair-stepping,
 *   with fast opacity/displacement transitions for polish
 */
MouseArea { // Notification group area
    id: root
    property var notificationGroup
    property var notifications: notificationGroup?.notifications ?? []
    property int notificationCount: notifications.length
    property bool multipleNotifications: notificationCount > 1
    property bool expandedByDefault: false
    property bool modernLayout: false
    property bool compactLayout: false
    property bool compactActions: false
    property bool expanded: expandedByDefault
    property bool popup: false
    signal externalLinkOpened()
    signal notificationActionInvoked()
    property real padding: modernLayout
        ? (compactLayout ? 9 : 12) : 10
    property bool _expandAnimating: false
    implicitHeight: background.implicitHeight

    property real dragConfirmThreshold: 40 // Drag to discard notification
    property real dismissOvershoot: 20 // Account for gaps and bouncy animations
    property var qmlParent: root?.parent?.parent // There's something between this and the parent ListView
    property var parentDragIndex: qmlParent?.dragIndex
    property var parentDragDistance: qmlParent?.dragDistance
    property var dragIndexDiff: Math.abs(parentDragIndex - index)
    property real xOffset: dragIndexDiff == 0 ? parentDragDistance : 0

    // Animation tokens — use fast timing for dismiss in all modes
    readonly property QtObject _contentAnim: Appearance.animation.elementMoveFast

    function destroyWithAnimation(left = false) {
        // Freeze the *identities* at gesture time, not the live group model.
        // Otherwise a notification arriving during the slide could be
        // discarded in place of one the user actually swiped.
        if (destroyAnimation.running) return
        const ids = (root.notifications ?? [])
            .map(notif => notif?.notificationId)
            .filter(id => Number.isInteger(id) && id >= 0)
        if (ids.length === 0) return
        destroyAnimation.dismissIds = Array.from(new Set(ids))
        background.anchors.leftMargin = root.xOffset; // Break binding, capture current position
        background.implicitHeight = background.implicitHeight; // Freeze height during dismiss
        root.implicitHeight = root.implicitHeight; // Freeze delegate height in ListView
        root.qmlParent.resetDrag()
        destroyAnimation.left = left;
        destroyAnimation.running = true;
    }

    hoverEnabled: true
    NotificationTimeoutHold {
        notifications: root.notifications
        active: root.popup && root.containsMouse
    }

    SequentialAnimation { // Drag finish animation
        id: destroyAnimation
        property bool left: true
        property var dismissIds: []
        running: false

        NumberAnimation {
            target: background.anchors
            property: "leftMargin"
            to: (root.width + root.dismissOvershoot) * (destroyAnimation.left ? -1 : 1)
            duration: Number(Appearance.animation?.elementMoveFast?.duration ?? 200)
            easing.type: Number(Appearance.animation?.elementMoveFast?.type ?? Easing.OutCubic)
            easing.bezierCurve: Appearance.animation?.elementMoveFast?.bezierCurve ?? [0.2, 0, 0, 1, 1, 1]
        }
        onFinished: () => {
            const ids = destroyAnimation.dismissIds
            destroyAnimation.dismissIds = []
            for (const id of ids) {
                // Only primitive numeric IDs cross the queued callback.
                // The original QML wrapper can be destroyed while waiting.
                Qt.callLater(() => {
                    if (Notifications.list.some(notif => notif?.notificationId === id))
                        Notifications.discardNotification(id)
                })
            }
        }
    }

    function toggleExpanded() {
        // Sidebar: animate height smoothly (panel doesn't resize, so no stair-stepping)
        // Popup: skip height animation (each frame would force async Wayland window resize)
        if (!root.popup) {
            root._expandAnimating = true;
            _expandAnimateEndTimer.restart();
        }
        root.expanded = !root.expanded;
    }

    Timer {
        id: _expandAnimateEndTimer
        interval: Appearance.calcEffectiveDuration(Appearance.animation.elementMoveFast.duration + 50)
        onTriggered: root._expandAnimating = false
    }

    DragManager { // Drag manager
        id: dragManager
        anchors.fill: parent
        interactive: !expanded
        automaticallyReset: false
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onPressed: (mouse) => {
            if (mouse.button === Qt.RightButton)
                root.toggleExpanded();
        }

        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton && !dragging) {
                root.toggleExpanded();
            } else if (mouse.button === Qt.MiddleButton) {
                root.destroyWithAnimation();
            }
        }

        onDraggingChanged: () => {
            if (dragging) {
                root.qmlParent.dragIndex = root.index ?? root.parent.children.indexOf(root);
            }
        }

        onDragDiffXChanged: () => {
            root.qmlParent.dragDistance = dragDiffX;
        }

        onDragReleased: (diffX, diffY) => {
            if (Math.abs(diffX) > root.dragConfirmThreshold)
                root.destroyWithAnimation(diffX < 0);
            else
                dragManager.resetDrag();
        }
    }

    Rectangle { // Background of the notification
        id: background
        anchors.left: parent.left
        width: parent.width

        color: root.popup
            ? ColorUtils.applyAlpha(Appearance.colors.colLayer2, 1 - Appearance.backgroundTransparency)
            : Appearance.colors.colLayer2
        radius: Appearance.rounding.normal
        border.width: 0
        border.color: "transparent"

        // Preserve smooth Material surface transitions.
        Behavior on radius { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve } }
        Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
        Behavior on border.width { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
        Behavior on border.color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
        anchors.leftMargin: root.xOffset

        Behavior on anchors.leftMargin {
            enabled: !dragManager.dragging
            NumberAnimation {
                duration: root._contentAnim.duration
                easing.type: root._contentAnim.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }

        clip: true

        implicitHeight: root.expanded ?
            row.implicitHeight + padding * 2 :
            Math.min(root.modernLayout
                ? (root.compactLayout ? 86 : 104) : 80,
                row.implicitHeight + padding * 2)

        Behavior on implicitHeight {
            id: implicitHeightAnim
            // Only animate during user-initiated expand/collapse in sidebar mode.
            // Popup skips this to avoid Wayland window resize stair-stepping.
            enabled: root._expandAnimating && !root.popup && Appearance.animationsEnabled
            NumberAnimation {
                duration: root._contentAnim.duration
                easing.type: root._contentAnim.type
                easing.bezierCurve: root._contentAnim.bezierCurve
            }
        }

        RowLayout { // Left column for icon, right column for content
            id: row
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.padding
            spacing: root.modernLayout ? 0 : 10

            NotificationAppIcon { // Legacy leading icon
                visible: !root.modernLayout
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: false
                image: root?.multipleNotifications ? "" : notificationGroup?.notifications[0]?.image ?? ""
                appIcon: root.notificationGroup?.appIcon
                summary: root.notificationGroup?.notifications[root.notificationCount - 1]?.summary
                // Use pre-calculated hasCritical from service
                urgency: root.notificationGroup?.hasCritical ? NotificationUrgency.Critical : NotificationUrgency.Normal
            }

            ColumnLayout { // Content
                Layout.fillWidth: true
                spacing: root.modernLayout
                    ? (root.compactLayout
                        ? (root.expanded ? 6 : 3)
                        : (root.expanded ? 8 : 4))
                    : (expanded ? (root.multipleNotifications
                        ? (notificationGroup?.notifications[root.notificationCount - 1].image != "" ? 35 : 5)
                        : 0) : 0)

                Behavior on spacing {
                    // Sidebar: smooth spacing transition; Popup: instant
                    enabled: !root.popup && Appearance.animationsEnabled
                    animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                }

                Item { // App name (or summary when there's only 1 notif) and time
                    id: topRow
                    Layout.fillWidth: true
                    property real fontSize: Appearance.font.pixelSize.smaller
                    property bool showAppName: root.multipleNotifications
                    implicitHeight: Math.max(
                        topTextRow.implicitHeight,
                        expandButton.implicitHeight,
                        modernHeaderIcon.visible ? modernHeaderIcon.implicitHeight : 0)

                    NotificationAppIcon {
                        id: modernHeaderIcon
                        visible: root.modernLayout
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: root.compactLayout ? 26 : 30
                        image: root.multipleNotifications ? ""
                            : notificationGroup?.notifications[0]?.image ?? ""
                        appIcon: root.notificationGroup?.appIcon
                        summary: root.notificationGroup
                            ?.notifications[root.notificationCount - 1]?.summary
                        urgency: root.notificationGroup?.hasCritical
                            ? NotificationUrgency.Critical : NotificationUrgency.Normal
                    }

                    RowLayout {
                        id: topTextRow
                        anchors.left: root.modernLayout
                            ? modernHeaderIcon.right : parent.left
                        anchors.leftMargin: root.modernLayout ? 8 : 0
                        anchors.right: expandButton.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        StyledText {
                            id: appName
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            text: (topRow.showAppName ?
                                notificationGroup?.appName :
                                notificationGroup?.notifications[0]?.summary) || ""
                            font.pixelSize: topRow.showAppName ?
                                topRow.fontSize :
                                Appearance.font.pixelSize.small
                            color: root.modernLayout
                                ? Appearance.colors.colOnLayer2
                                : (topRow.showAppName
                                    ? Appearance.colors.colSubtext
                                    : Appearance.colors.colOnLayer2)
                        }
                        StyledText {
                            id: timeText
                            Layout.rightMargin: 10
                            horizontalAlignment: Text.AlignLeft
                            text: NotificationUtils.getFriendlyNotifTimeString(notificationGroup?.time)
                            font.pixelSize: topRow.fontSize
                            color: Appearance.colors.colSubtext
                            Behavior on color {
                                enabled: Appearance.animationsEnabled
                                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                            }
                        }
                    }
                    NotificationGroupExpandButton {
                        id: expandButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        count: root.notificationCount
                        expanded: root.expanded
                        fontSize: topRow.fontSize
                        onClicked: { root.toggleExpanded() }
                        altAction: () => { root.toggleExpanded() }
                    }
                }

                StyledListView { // Notification body (expanded)
                    id: notificationsColumn
                    implicitHeight: contentHeight
                    Layout.fillWidth: true
                    spacing: root.modernLayout
                        ? (root.compactLayout ? 4 : 6)
                        : (expanded ? 5 : 3)
                    interactive: false

                    // Disable built-in transitions — we provide custom ones below
                    // to use faster timing for popup and standard for sidebar
                    animateAppearance: false
                    popin: false

                    Behavior on spacing {
                        enabled: !root.popup && Appearance.animationsEnabled
                        animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                    }

                    // Custom removeDisplaced: smooth gap-filling when a notification is dismissed.
                    // Uses fast timing so remaining items slide up promptly after dismiss animation.
                    removeDisplaced: Transition {
                        NumberAnimation {
                            property: "y"
                            duration: root._contentAnim.duration
                            easing.type: root._contentAnim.type
                            easing.bezierCurve: root._contentAnim.bezierCurve
                        }
                        NumberAnimation {
                            property: "opacity"
                            to: 1
                            duration: root._contentAnim.duration
                            easing.type: root._contentAnim.type
                            easing.bezierCurve: root._contentAnim.bezierCurve
                        }
                    }

                    model: ScriptModel {
                        values: root.expanded ? root.notifications.slice().reverse() :
                            root.notifications.slice().reverse().slice(0, 2)
                    }
                    delegate: NotificationItem {
                        required property int index
                        required property var modelData
                        notificationObject: modelData
                        expanded: root.expanded
                        popup: root.popup
                        modernLayout: root.modernLayout
                        compactActions: root.compactActions
                        onlyNotification: (root.notificationCount === 1)
                        opacity: (!root.expanded && index == 1 && root.notificationCount > 2) ? 0.5 : 1
                        visible: root.expanded || (index < 2)
                        anchors.left: parent?.left
                        anchors.right: parent?.right
                        onExternalLinkOpened: root.externalLinkOpened()
                        onNotificationActionInvoked:
                            root.notificationActionInvoked()
                    }
                }

            }
        }
    }
}
