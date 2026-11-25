import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    default property alias contentData: content.data
    property alias spacing: content.rowSpacing
    property int fieldColumns: 1
    property bool flatEmbedded: false
    readonly property int activeColumns: fieldColumns > 1 ? fieldColumns : 1
    readonly property real _pad: root.flatEmbedded ? 0 : SettingsMaterialPreset.groupPadding

    Layout.fillWidth: true
    Layout.fillHeight: false
    Layout.minimumWidth: 0
    implicitHeight: content.implicitHeight + root._pad * 2

    function _nodeWantsVerticalExpand(ch, depth) {
        if (!ch || !ch.visible || !ch.Layout || !ch.Layout.fillHeight || (depth || 0) > 8)
            return false
        if (ch._hasFillHeightChild !== undefined)
            return Boolean(ch._hasFillHeightChild)
        var isRow = (ch instanceof RowLayout) || String(ch).indexOf("QQuickRowLayout") === 0
        var isLayout = isRow
            || (ch instanceof ColumnLayout)
            || (ch instanceof GridLayout)
            || (ch instanceof StackLayout)
            || String(ch).indexOf("Layout") >= 0
        if (isLayout) {
            var sub = ch.children || []
            for (var i = 0; i < sub.length; i++) {
                var child = sub[i]
                if (isRow && child && !(child instanceof Flickable) && String(child).indexOf("ScrollView") < 0 && !(child instanceof ColumnLayout) && child.implicitWidth !== undefined && child.implicitWidth <= 4 && child.width <= 4)
                    continue
                if (root._nodeWantsVerticalExpand(child, (depth || 0) + 1))
                    return true
            }
            return false
        }
        return true
    }

    readonly property bool _hasFillHeightChild: {
        var kids = content.children
        for (var i = 0; i < kids.length; i++) {
            if (root._nodeWantsVerticalExpand(kids[i], 0))
                return true
        }
        return false
    }

    radius: root.flatEmbedded ? 0 : SettingsMaterialPreset.groupRadius
    color: root.flatEmbedded ? "transparent" : SettingsMaterialPreset.groupColor
    border.width: 0
    border.color: "transparent"

    function ensureControlOnActiveSubTab(control) {}

    GridLayout {
        id: content
        columns: root.activeColumns
        uniformCellWidths: columns > 1
        columnSpacing: columns > 1 ? 18 * Appearance.fontSizeScale : 0
        objectName: "settingsGroupContent"
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: root._pad
            rightMargin: root._pad
            topMargin: root._pad
        }
        height: (root.Layout.fillHeight && root._hasFillHeightChild)
            ? Math.max(implicitHeight, root.height - root._pad * 2)
            : implicitHeight
        rowSpacing: SettingsMaterialPreset.groupSpacing
    }
}
