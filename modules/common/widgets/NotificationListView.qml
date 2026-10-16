pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell

StyledListView { // Scrollable window
    id: root
    // Compatibility flag for transient toast callers. New surfaces can choose
    // history/transient data independently from popup/embedded presentation.
    property bool popup: false
    property string dataMode: popup ? "transient" : "history"
    property bool popupPresentation: popup
    // Optional presentation-only closing snapshot. Normal popup, history and
    // Waffle callers leave both null and continue using live Notifications.
    property var transientAppNamesOverride: null
    property var transientGroupsOverride: null
    // History surfaces may prefer full notification content. Overflow belongs
    // to the ListView, so cards are not collapsed merely because they share a
    // group; the user can still collapse a group explicitly.
    property bool preferExpanded: false
    property bool modernCards: false
    property bool compactCards: false
    property bool compactActions: false
    // History-only filter; popups are never filtered.
    property string filterQuery: ""
    signal externalLinkOpened()
    signal notificationActionInvoked()

    spacing: modernCards ? (compactCards ? 6 : 8) : 3

    // Sidebar: full transitions with pop-in; Popup: lightweight entrance only
    popin: !popupPresentation
    animateAppearance: !popupPresentation

    // Popup entrance: opacity fade + horizontal slide (no height change to avoid Wayland stair-stepping)
    add: Transition {
        enabled: root.popupPresentation || root.animateAppearance
        NumberAnimation {
            property: "opacity"
            from: 0; to: 1
            duration: root.popupPresentation ? Appearance.animation.elementMoveFast.duration : Appearance.animation.elementMove.duration
            easing.type: root.popupPresentation ? Appearance.animation.elementMoveFast.type : Appearance.animation.elementMove.type
            easing.bezierCurve: root.popupPresentation ? Appearance.animation.elementMoveFast.bezierCurve : Appearance.animation.elementMove.bezierCurve
        }
        NumberAnimation {
            property: root.popupPresentation ? "x" : "scale"
            from: root.popupPresentation ? 24 : 0; to: root.popupPresentation ? 0 : 1
            duration: root.popupPresentation ? Appearance.animation.elementMoveFast.duration : Appearance.animation.elementMove.duration
            easing.type: root.popupPresentation ? Appearance.animation.elementMoveFast.type : Appearance.animation.elementMove.type
            easing.bezierCurve: root.popupPresentation ? Appearance.animation.elementMoveFast.bezierCurve : Appearance.animation.elementMove.bezierCurve
        }
    }

    // Custom removeDisplaced for popup mode: smooth gap-filling when a group is dismissed.
    // Uses elementMoveFast for snappy feel without Wayland stair-stepping.
    removeDisplaced: Transition {
        enabled: root.popupPresentation
        NumberAnimation {
            property: "y"
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
        NumberAnimation {
            property: "opacity"
            to: 1
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    model: ScriptModel {
        values: root.dataMode === "transient"
            ? (root.transientAppNamesOverride ?? Notifications.popupAppNameList)
            : Notifications.appNamesMatching(root.filterQuery)
    }
    delegate: NotificationGroup {
        required property int index
        required property var modelData
        popup: root.popupPresentation
        expandedByDefault: root.preferExpanded
        modernLayout: root.modernCards
        compactLayout: root.compactCards
        compactActions: root.compactActions
        anchors.left: parent?.left
        anchors.right: parent?.right
        notificationGroup: root.dataMode === "transient"
            ? (root.transientGroupsOverride ?? Notifications.popupGroupsByAppName)[modelData]
            : Notifications.groupsByAppName[modelData]
        onExternalLinkOpened: root.externalLinkOpened()
        onNotificationActionInvoked: root.notificationActionInvoked()
    }
}
