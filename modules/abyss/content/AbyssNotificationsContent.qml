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
    // Set by AbyssBodyHost after Loader readiness. This is presentation-only;
    // history and timeout ownership continue to belong to Notifications.
    property var participant: null
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
    readonly property real desiredHeight: root.settledPopupHeight
    // Read-only and only consumed on explicit diagnostic IPC snapshot:
    // distinguish ListView's provisional layout from the committed size.
    readonly property real measuredPopupHeight:
        Number(popupLoader.item?.contentHeight ?? 0)
    // A transient timeout clears live popup groups before the shared Abyss
    // surface has finished retracting. Preserve independent value snapshots
    // so a destroyed transient QtObject cannot be dereferenced mid-close.
    // This snapshot is used only after input has been revoked; all interactive
    // notifications continue to use live service wrappers while open.
    property var closingAppNames: []
    property var closingGroups: ({})
    // Select the last complete card as soon as the live model clears.
    // Avoid a single empty delegate frame before host.open recomputes.
    readonly property bool closingVisualTail: !root.center && root.participant !== null
        && (root.participant.visualResident ?? false)
        && (!root.participant.open || Notifications.popupList.length === 0)
        && root.closingAppNames.length > 0
    function captureClosingSnapshot(): void {
        if (root.center || Notifications.popupList.length === 0)
            return
        const names=Notifications.popupAppNameList
        const groups=Notifications.popupGroupsByAppName
        if (names.length === 0) return
        const copied=Object.create(null)
        for (const name of names) {
            const group=groups[name]
            if (!group) return
            copied[name]={
                appName:String(group.appName ?? name),
                appIcon:String(group.appIcon ?? ""),
                time:Number(group.time ?? 0),
                hasCritical:group.hasCritical === true,
                notifications:(group.notifications ?? []).map(notif => ({
                    notificationId:Number(notif?.notificationId ?? -1),
                    appName:String(notif?.appName ?? name),
                    appIcon:String(notif?.appIcon ?? ""),
                    summary:String(notif?.summary ?? ""),
                    body:String(notif?.body ?? ""),
                    image:String(notif?.image ?? ""),
                    time:Number(notif?.time ?? 0),
                    urgency:notif?.urgency ?? "normal",
                    // No native action/notification reference can outlive a
                    // dismissed transient wrapper. Closing controls have no
                    // input, so retain labels solely to preserve card height.
                    actions:(notif?.actions ?? []).map(action => ({
                        text:String(action?.text ?? ""),
                        identifier:String(action?.identifier ?? "")
                    }))
                }))
            }
        }
        root.closingGroups=copied
        root.closingAppNames=names.slice()
    }
    function schedulePopupMeasurement(): void {
        if (root.center || !(Notifications.popupList?.length > 0))
            return
        if (Number(popupLoader.item?.contentHeight ?? 0) > 0)
            popupMeasureTimer.restart()
    }
    function commitPopupMeasurement(): void {
        if (root.center || !(Notifications.popupList?.length > 0))
            return
        const height=Number(popupLoader.item?.contentHeight ?? 0)
        if (!Number.isFinite(height) || height <= 0)
            return
        root.settledPopupHeight=height
        root.popupLayoutReady=true
    }
    Component.onCompleted: {
        if (center) Notifications.markAllRead()
        else Qt.callLater(() => {
            root.captureClosingSnapshot()
            root.schedulePopupMeasurement()
        })
    }
    onCenterChanged: {
        popupMeasureTimer.stop()
        root.popupLayoutReady=false
        root.settledPopupHeight=0
        root.closingAppNames=[]
        root.closingGroups=({})
        if (center) Notifications.markAllRead()
        else Qt.callLater(() => {
            root.captureClosingSnapshot()
            root.schedulePopupMeasurement()
        })
    }
    Connections {
        target: Notifications
        // These cached groups are published after popupList changes. Snapshot
        // their last COMPLETE nonempty state before the timeout empties the
        // model, without delaying history/unread/notification actions.
        function onPopupAppNameListChanged(): void {
            root.captureClosingSnapshot()
        }
        function onPopupListChanged(): void {
            if (Notifications.popupList.length === 0) {
                popupMeasureTimer.stop()
                root.popupLayoutReady=false
                // Keep the last measured dimensions while the host retracts.
                // Its Loader destroys this content after the closing surface
                // disappears; clearing now snaps a taller banner to the minimum
                // depth before the first closing animation frame is presented.
            } else root.schedulePopupMeasurement()
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
        sourceComponent: NotificationListView {
            popup: true
            clip: true
            // The final live model can become empty while the field is still
            // painting its retract tail. Keep the previous card until the
            // same host's progress reaches zero, then Loader unloads it.
            transientAppNamesOverride: root.closingVisualTail
                ? root.closingAppNames : null
            transientGroupsOverride: root.closingVisualTail
                ? root.closingGroups : null
        }
    }
    Connections {
        target: popupLoader.item
        function onContentHeightChanged(): void {
            root.schedulePopupMeasurement()
        }
    }
}
