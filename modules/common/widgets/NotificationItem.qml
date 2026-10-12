import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Services.Notifications

Item { // Notification item area
    id: root
    property var notificationObject
    property bool expanded: false
    property bool popup: false
    property bool modernLayout: false
    property bool compactActions: false
    signal externalLinkOpened()
    signal notificationActionInvoked()
    property bool onlyNotification: false
    property real fontSize: Appearance.font.pixelSize.small
    property real padding: modernLayout
        ? (compactActions ? 8 : 10)
        : (onlyNotification ? 0 : 8)
    property real summaryElideRatio: 0.85

    // Animation tokens — use fast timing for dismiss in all modes
    readonly property QtObject _contentAnim: Appearance.animation.elementMoveFast

    property real dragConfirmThreshold: 70 // Drag to discard notification
    property real dismissOvershoot: 58 // Account for gaps and bouncy animations (was notificationIcon.implicitWidth + 20)
    property var qmlParent: root?.parent?.parent // There's something between this and the parent ListView
    property var parentDragIndex: qmlParent?.dragIndex ?? -1
    property var parentDragDistance: qmlParent?.dragDistance ?? 0
    property var dragIndexDiff: Math.abs(parentDragIndex - index)
    property real xOffset: dragIndexDiff == 0 ? parentDragDistance : 0

    readonly property bool notificationCritical: {
        const value = root.notificationObject?.urgency
        if (value === undefined || value === null)
            return false
        return value === NotificationUrgency.Critical
            || String(value).toLowerCase() === "critical"
    }

    readonly property string notificationSummaryText: String(root.notificationObject?.summary ?? "")
    readonly property bool hasNotificationActions: (root.notificationObject?.actions?.length ?? 0) > 0
    readonly property string processedNotificationBodyText: {
        if (!root.notificationObject) return ""
        const body = String(root.notificationObject.body ?? "")
        const source = String(root.notificationObject.appName
            ?? root.notificationObject.summary ?? "")
        return String(NotificationUtils.processNotificationBody(body, source) ?? "")
            .replace(/\n/g, "<br/>")
    }

    implicitHeight: background.implicitHeight

    function destroyWithAnimation(left = false) {
        // An updating ListView may recycle this delegate before its exit
        // animation completes. Preserve the swiped ID, not modelData's
        // mutable QML wrapper reference.
        if (destroyAnimation.running) return
        const id = root.notificationObject?.notificationId
        if (!Number.isInteger(id) || id < 0) return
        destroyAnimation.dismissId = id
        background.anchors.leftMargin = root.xOffset; // Break binding, capture current position
        background.implicitHeight = background.implicitHeight; // Freeze height so it doesn't resize during dismiss
        root.implicitHeight = root.implicitHeight; // Freeze delegate height in ListView
        root.qmlParent.resetDrag()
        destroyAnimation.left = left;
        destroyAnimation.running = true;
    }

    TextMetrics {
        id: summaryTextMetrics
        font.pixelSize: root.fontSize
        text: root.notificationSummaryText
    }

    SequentialAnimation { // Drag finish animation
        id: destroyAnimation
        property bool left: true
        property int dismissId: -1
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
            const id = destroyAnimation.dismissId
            destroyAnimation.dismissId = -1
            if (id >= 0 && Notifications.list.some(notif => notif?.notificationId === id))
                Notifications.discardNotification(id)
        }
    }

    DragManager { // Drag manager
        id: dragManager
        anchors.fill: root
        anchors.leftMargin: root.expanded ? -root.dismissOvershoot : 0
        interactive: expanded
        automaticallyReset: false
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton) {
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

    // Note: App icon for expanded notifications with images is now handled by NotificationAppIcon
    // within the image itself (small corner icon) - no separate icon needed here to avoid duplication

    Rectangle { // Background of notification item
        id: background
        width: parent.width
        anchors.left: parent.left
        radius: root.modernLayout
            ? Appearance.rounding.normal : Appearance.rounding.small
        anchors.leftMargin: root.xOffset

        Behavior on radius {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve }
        }

        Behavior on anchors.leftMargin {
            enabled: !dragManager.dragging && Appearance.animationsEnabled
            NumberAnimation {
                duration: root._contentAnim.duration
                easing.type: root._contentAnim.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }

        color: root.modernLayout
            ? (root.notificationCritical
                ? ColorUtils.mix(Appearance.colors.colSecondaryContainer,
                    Appearance.colors.colLayer2, 0.35)
                : Appearance.colors.colLayer3)
            : ((expanded && !onlyNotification)
                ? (root.notificationCritical
                    ? ColorUtils.mix(Appearance.colors.colSecondaryContainer,
                        Appearance.colors.colLayer2, 0.35)
                    : Appearance.colors.colLayer3)
                : "transparent")
        border.width: 0
        border.color: Appearance.colors.colLayer0Border

        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        Behavior on border.width {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        Behavior on border.color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }

        implicitHeight: (expanded || root.modernLayout)
            ? (contentColumn.implicitHeight + root.padding * 2)
            : summaryRow.implicitHeight
        Behavior on implicitHeight {
            // Sidebar: subtle fast transition; Popup: instant (window resize handled by parent)
            enabled: !root.popup && Appearance.animationsEnabled
            NumberAnimation {
                duration: root._contentAnim.duration / 2
                easing.type: root._contentAnim.type
                easing.bezierCurve: root._contentAnim.bezierCurve
            }
        }

        ColumnLayout { // Content column
            id: contentColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: (root.modernLayout || expanded) ? root.padding : 0
            spacing: 3

            Behavior on anchors.margins {
                // Sidebar: smooth margin transition; Popup: instant
                enabled: !root.popup && Appearance.animationsEnabled
                animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
            }

            RowLayout { // Summary row
                id: summaryRow
                visible: !root.onlyNotification || !root.expanded
                Layout.fillWidth: true
                implicitHeight: summaryText.implicitHeight
                StyledText {
                    id: summaryText
                    Layout.fillWidth: summaryTextMetrics.width >= contentColumn.width * root.summaryElideRatio
                    visible: !root.onlyNotification
                    font.pixelSize: root.fontSize
                    color: Appearance.colors.colOnLayer3
                    Behavior on color {
                        enabled: Appearance.animationsEnabled
                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                    }
                    elide: Text.ElideRight
                    text: root.notificationSummaryText
                }
                StyledText {
                    opacity: !root.expanded ? 1 : 0
                    visible: opacity > 0
                    Layout.fillWidth: true
                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled
                        animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                    }
                    font.pixelSize: root.fontSize
                    color: root.modernLayout
                        ? Appearance.colors.colOnLayer3
                        : Appearance.colors.colSubtext
                    Behavior on color {
                        enabled: Appearance.animationsEnabled
                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                    }
                    elide: Text.ElideRight
                    wrapMode: Text.Wrap // Needed for proper eliding????
                    maximumLineCount: 1
                    textFormat: Text.StyledText
                    text: root.processedNotificationBodyText
                }
            }

            ColumnLayout { // Expanded content
                id: expandedContentColumn
                Layout.fillWidth: true
                opacity: root.expanded ? 1 : 0
                visible: opacity > 0

                StyledText { // Notification body (expanded)
                    id: notificationBodyText
                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled
                        animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                    }
                    Layout.fillWidth: true
                    font.pixelSize: root.fontSize
                    color: root.modernLayout
                        ? Appearance.colors.colOnLayer3
                        : Appearance.colors.colSubtext
                    Behavior on color {
                        enabled: Appearance.animationsEnabled
                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                    }
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    textFormat: Text.RichText
                    text: root.notificationObject
                        ? `<style>img{max-width:100%;}</style>${root.processedNotificationBodyText}`
                        : ""

                    onLinkActivated: (link) => {
                        Qt.openUrlExternally(link)
                        root.externalLinkOpened()
                    }

                    PointingHandLinkHover {}
                }

                Item {
                    Layout.fillWidth: true
                    implicitWidth: actionsFlickable.implicitWidth
                    implicitHeight: actionsFlickable.implicitHeight

                    layer.enabled: !root.modernLayout
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: actionsFlickable.width
                            height: actionsFlickable.height
                            radius: Appearance.rounding.small
                        }
                    }

                    ScrollEdgeFade {
                        target: actionsFlickable
                        vertical: false
                    }

                    StyledFlickable { // Notification actions
                        id: actionsFlickable
                        anchors.fill: parent
                        implicitHeight: actionRowLayout.implicitHeight
                        contentWidth: Math.max(width, actionRowLayout.implicitWidth)

                        Behavior on opacity {
                            enabled: Appearance.animationsEnabled
                            animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                        }
                        Behavior on height {
                            enabled: Appearance.animationsEnabled
                            animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                        }
                        Behavior on implicitHeight {
                            enabled: Appearance.animationsEnabled
                            animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                        }

                        RowLayout {
                            id: actionRowLayout
                            width: Math.max(actionsFlickable.width, implicitWidth)
                            Layout.alignment: Qt.AlignBottom
                            spacing: root.modernLayout ? 6 : 4

                            Item {
                                visible: root.modernLayout
                                Layout.fillWidth: true
                                implicitWidth: 1
                            }

                            NotificationActionButton {
                                Layout.fillWidth: !root.modernLayout
                                buttonText: Translation.tr("Close")
                                urgency: root.notificationObject?.urgency ?? NotificationUrgency.Normal
                                implicitWidth: root.modernLayout
                                    ? (root.compactActions ? 28 : 34)
                                    : (!root.hasNotificationActions
                                        ? (Math.max(0, actionsFlickable.width - actionRowLayout.spacing) / 2)
                                        : ((contentItem?.implicitWidth ?? 0)
                                            + (leftPadding ?? 0) + (rightPadding ?? 0)))

                                implicitHeight: root.modernLayout
                                    && root.compactActions ? 28 : 34

                                onClicked: {
                                    root.destroyWithAnimation()
                                }

                                contentItem: MaterialSymbol {
                                    iconSize: root.compactActions
                                        ? 15 : Appearance.font.pixelSize.larger
                                    horizontalAlignment: Text.AlignHCenter
                                    color: root.notificationCritical
                                        ? Appearance.colors.colOnSecondaryContainer
                                        : Appearance.colors.colOnLayer3
                                    text: "close"
                                }

                                StyledToolTip { text: Translation.tr("Dismiss") }
                            }

                            Repeater {
                                id: actionRepeater
                                model: notificationObject?.actions ?? []
                                NotificationActionButton {
                                    required property var modelData
                                    Layout.fillWidth: !root.modernLayout
                                    implicitHeight: root.modernLayout
                                        && root.compactActions ? 28 : 34
                                    buttonText: String(modelData?.text ?? "")
                                    urgency: root.notificationObject?.urgency ?? NotificationUrgency.Normal
                                    onClicked: {
                                        Notifications.attemptInvokeAction(
                                            notificationObject.notificationId,
                                            modelData.identifier)
                                        root.notificationActionInvoked()
                                    }
                                }
                            }

                            NotificationActionButton {
                                Layout.fillWidth: !root.modernLayout
                                buttonText: Translation.tr("Copy notification")
                                urgency: root.notificationObject?.urgency ?? NotificationUrgency.Normal
                                implicitWidth: root.modernLayout
                                    ? (root.compactActions ? 28 : 34)
                                    : (!root.hasNotificationActions
                                        ? (Math.max(0, actionsFlickable.width - actionRowLayout.spacing) / 2)
                                        : ((contentItem?.implicitWidth ?? 0)
                                            + (leftPadding ?? 0) + (rightPadding ?? 0)))
                                implicitHeight: root.modernLayout
                                    && root.compactActions ? 28 : 34

                                onClicked: {
                                    Quickshell.execDetached(["wl-copy", notificationObject?.body ?? ""])
                                    copyIcon.text = "inventory"
                                    copyIconTimer.restart()
                                }

                                Timer {
                                    id: copyIconTimer
                                    interval: 1500
                                    repeat: false
                                    onTriggered: {
                                        copyIcon.text = "content_copy"
                                    }
                                }

                                contentItem: MaterialSymbol {
                                    id: copyIcon
                                    iconSize: root.compactActions
                                        ? 15 : Appearance.font.pixelSize.larger
                                    horizontalAlignment: Text.AlignHCenter
                                    color: root.notificationCritical
                                        ? Appearance.colors.colOnSecondaryContainer
                                        : Appearance.colors.colOnLayer3
                                    text: "content_copy"
                                }

                                StyledToolTip { text: Translation.tr("Copy") }
                            }

                        }
                    }
                }
            }
        }
    }
}
