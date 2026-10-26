import QtQuick
import Quickshell

// Conservative compositor input region for Abyss-connected popups.
//
// The visual SDF may extend a smooth-union fillet outside the body, but pointer
// ownership stays on the actually revealed rounded body only. This deliberately
// replaces the legacy connector-strip approximation for StyledPopup.
Region {
    id: root

    required property var geometry
    required property Item bodyItem
    property bool inputEnabled: true

    readonly property bool active: root.inputEnabled
        && root.geometry?.valid === true
        && Number(root.geometry?.revealProgress ?? root.geometry?.progress ?? 0) > 0
    property rect visibleBodyRect: root.geometry?.visibleBodyRect
        ?? Qt.rect(0, 0, 0, 0)
    readonly property real bodyRadius: Math.min(
        Number(root.geometry?.outerRadius ?? 0),
        root._visibleBodyItem.width / 2,
        root._visibleBodyItem.height / 2)

    property Item _emptyItem: Item {
        parent: root.bodyItem?.parent ?? null
        width: 0
        height: 0
        visible: false
    }

    property Item _visibleBodyItem: Item {
        parent: root.bodyItem?.parent ?? null
        x: root.visibleBodyRect.x
        y: root.visibleBodyRect.y
        width: root.visibleBodyRect.width
        height: root.visibleBodyRect.height
        visible: false
    }

    Region {
        item: root.active ? root._visibleBodyItem : root._emptyItem
        radius: root.bodyRadius
    }
}
