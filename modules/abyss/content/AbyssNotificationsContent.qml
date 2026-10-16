pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.notificationCenter
import qs.services

// Keep the mature notification grouping, expansion, images, actions and links.
Item {
    id: root
    property string kind: "popup"
    property string outputName: ""
    signal closeRequested()
    readonly property bool center: kind === "center"
    readonly property real desiredWidth: Appearance.sizes.notificationPopupWidth
    // New notification delegates (notably Recorder's saved-file path) do not
    // have their final ListView.contentHeight on the first Loader frame.
    // Batch measurements before the physical Abyss banner is allowed to open;
    // while it is open, publish only settled changes rather than feeding
    // intermediate card heights into the shared field / placement allocator.
    property real settledPopupHeight: 0
    property bool popupLayoutReady: false
    // A zero-height ListView can predate the asynchronous grouped ScriptModel.
    // Bound retries cover missed early contentHeightChanged signals without
    // allowing an empty/provisional banner to open or spinning indefinitely.
    property int popupMeasureAttempts: 0
    readonly property int popupMeasureAttemptLimit: 10
    readonly property real desiredHeight: root.settledPopupHeight
    // Read-only and only consumed on explicit diagnostic IPC snapshot:
    // distinguish ListView's provisional layout from the committed size.
    readonly property real measuredPopupHeight:
        Number(popupLoader.item?.contentHeight ?? 0)
    function schedulePopupMeasurement(): void {
        if (root.center || !(Notifications.popupList?.length > 0)
                || !popupLoader.item)
            return
        // Schedule even at zero height: the initial change may have preceded
        // Connections binding or the group model may still be materializing.
        popupMeasureTimer.restart()
    }
    function commitPopupMeasurement(): void {
        if (root.center || !(Notifications.popupList?.length > 0))
            return
        const view=popupLoader.item
        if (!view)
            return
        // Request one synchronous model/layout polish before trusting height.
        // The content size, not an estimated timeout fallback, gates visibility.
        view.forceLayout()
        const height=Number(view.contentHeight ?? 0)
        if (!Number.isFinite(height) || height <= 0) {
            if (root.popupMeasureAttempts < root.popupMeasureAttemptLimit) {
                root.popupMeasureAttempts++
                popupMeasureTimer.restart()
            }
            return
        }
        root.popupMeasureAttempts=0
        root.settledPopupHeight=height
        root.popupLayoutReady=true
    }
    Component.onCompleted: {
        if (center) Notifications.markAllRead()
        else Qt.callLater(() => root.schedulePopupMeasurement())
    }
    onCenterChanged: {
        popupMeasureTimer.stop()
        root.popupMeasureAttempts=0
        root.popupLayoutReady=false
        root.settledPopupHeight=0
        if (center) Notifications.markAllRead()
        else Qt.callLater(() => root.schedulePopupMeasurement())
    }
    Connections {
        target: Notifications
        function onPopupListChanged(): void {
            if (Notifications.popupList.length === 0) {
                popupMeasureTimer.stop()
                root.popupMeasureAttempts=0
                root.popupLayoutReady=false
                // Keep the last measured dimensions while the host retracts.
                // Its Loader destroys this content after the closing surface
                // disappears; clearing now snaps a taller banner to the minimum
                // depth before the first closing animation frame is presented.
            } else {
                root.popupMeasureAttempts=0
                root.schedulePopupMeasurement()
            }
        }
        function onPopupAppNameListChanged(): void {
            // A new group can arrive after the content Loader first reported
            // zero height, without a subsequent ListView height notification.
            root.popupMeasureAttempts=0
            root.schedulePopupMeasurement()
        }
    }
    Timer {
        id: popupMeasureTimer
        interval: 75
        repeat: false
        onTriggered: root.commitPopupMeasurement()
    }
    Loader {
        anchors.fill: parent
        active: root.center
        sourceComponent: NotificationCenterContent {}
    }
    Loader {
        id: popupLoader
        anchors.fill: parent
        active: !root.center
        onLoaded: root.schedulePopupMeasurement()
        sourceComponent: NotificationListView { popup: true; clip: true }
    }
    Connections {
        target: popupLoader.item
        function onContentHeightChanged(): void {
            root.schedulePopupMeasurement()
        }
    }
}
