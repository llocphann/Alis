pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.services

// Hover suspends a popup's remaining lifetime. Each output owns its hold;
// another output leaving or a delegate disappearing cannot pin it forever.
Scope {
    id: root
    property var notifications: []
    property bool active: false
    property var heldIds: []
    function sync(): void {
        // A debounced popup group can briefly retain deleted QML wrappers.
        // Discard invalid entries so the previous hover holds still release.
        const next = active
            ? Array.from(new Set((notifications ?? [])
                .map(notif => notif?.notificationId)
                .filter(id => typeof id === "number" && Number.isFinite(id)))) : []
        heldIds.forEach(id => {
            if (!next.includes(id)) Notifications.resumeTimeout(id, root)
        })
        next.forEach(id => Notifications.pauseTimeout(id, root))
        heldIds = next
    }
    onActiveChanged: sync()
    onNotificationsChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: heldIds.forEach(id => Notifications.resumeTimeout(id, root))
}
