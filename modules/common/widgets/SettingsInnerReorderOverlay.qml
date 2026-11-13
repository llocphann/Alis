import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    objectName: "settingsInnerReorderOverlay"

    required property Item targetLayout
    property string containerId: ""
    property bool activeInSettings: false
    property bool activeInBentoEditMode: false
    property bool isGroupContainer: false

    z: 22
    visible: root.activeInSettings && SettingsLayoutManager.editMode && (SettingsLayoutManager.innerEditMode || root.activeInBentoEditMode)

    property var _defaultKeys: []
    property var _itemByKey: ({})
    property var _visibleItems: []
    property string _visibleItemsSignature: ""
    property var _customWidthItems: []
    property var _customAlignedItems: []
    property bool _hasAppliedOrder: false
    property bool _isApplyingOrder: false

    Item {
        id: reorderPark
        visible: false
        width: 0
        height: 0
    }

    function _slug(val) {
        return String(val || "")
            .trim()
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, "-")
            .replace(/^-+|-+$/g, "");
    }

    function _extractItemLabel(item, index) {
        if (!item)
            return "item-" + index;
        if (item.title && typeof item.title === "string")
            return item.title;
        if (item.text && typeof item.text === "string")
            return item.text;
        if (item.settingsSearchLabel && typeof item.settingsSearchLabel === "string")
            return item.settingsSearchLabel;
        if (item.objectName && typeof item.objectName === "string")
            return item.objectName + "-" + index;
        return "item-" + index;
    }

    function _isReorderableItem(item) {
        if (!item || item === root || item === reorderPark)
            return false;
        if (item.width === undefined || item.height === undefined)
            return false;
        // Skip internal Repeater/Loader placeholders with 0 height when inactive
        const cls = String(item);
        if (cls.indexOf("QQuickRepeater") >= 0)
            return false;
        return true;
    }

    function syncChildrenAndOrder() {
        if (root._isApplyingOrder || !root.targetLayout || !root.activeInSettings || !root.containerId)
            return;
        const hasCustom = SettingsLayoutManager.hasInnerCustomizations(root.containerId);
        if (!root.visible
            && !hasCustom
            && !root._hasAppliedOrder
            && root._customWidthItems.length === 0
            && root._customAlignedItems.length === 0) {
            return;
        }

        const rawChildren = root.targetLayout.children || [];
        const items = [];
        for (let i = 0; i < rawChildren.length; i++) {
            const ch = rawChildren[i];
            if (root._isReorderableItem(ch))
                items.push(ch);
        }
        if (items.length === 0) {
            if (root._visibleItems.length > 0) {
                root._visibleItems = [];
                root._visibleItemsSignature = "";
            }
            return;
        }

        // Assign stable keys to any newly discovered children
        const nextMap = Object.assign({}, root._itemByKey);
        const nextDefaults = root._defaultKeys.slice();
        for (let j = 0; j < items.length; j++) {
            const item = items[j];
            let key = "";
            for (const existingKey of Object.keys(nextMap)) {
                if (nextMap[existingKey] === item) {
                    key = existingKey;
                    break;
                }
            }
            if (!key) {
                const baseSlug = root._slug(root._extractItemLabel(item, j)) || ("item-" + j);
                key = baseSlug;
                let suffix = 2;
                while (nextMap[key] && nextMap[key] !== item) {
                    key = baseSlug + "-" + suffix;
                    suffix++;
                }
                nextMap[key] = item;
                if (nextDefaults.indexOf(key) < 0)
                    nextDefaults.push(key);
            }
        }
        root._itemByKey = nextMap;
        root._defaultKeys = nextDefaults;

        // Check desired order from SettingsLayoutManager
        const desiredKeys = SettingsLayoutManager.getInnerOrder(root.containerId, root._defaultKeys);
        const currentKeys = [];
        for (let k = 0; k < items.length; k++) {
            for (const mk of Object.keys(nextMap)) {
                if (nextMap[mk] === items[k]) {
                    currentKeys.push(mk);
                    break;
                }
            }
        }

        const filteredDesired = desiredKeys.filter(dk => currentKeys.indexOf(dk) >= 0);
        for (let m = 0; m < currentKeys.length; m++) {
            if (filteredDesired.indexOf(currentKeys[m]) < 0)
                filteredDesired.push(currentKeys[m]);
        }

        let orderDiffers = false;
        if (filteredDesired.length === currentKeys.length) {
            for (let n = 0; n < filteredDesired.length; n++) {
                if (filteredDesired[n] !== currentKeys[n]) {
                    orderDiffers = true;
                    break;
                }
            }
        }

        if (orderDiffers && filteredDesired.length > 1) {
            root._isApplyingOrder = true;
            const orderedItems = [];
            for (let p = 0; p < filteredDesired.length; p++) {
                const it = nextMap[filteredDesired[p]];
                if (it)
                    orderedItems.push(it);
            }
            for (let q = 0; q < orderedItems.length; q++)
                orderedItems[q].parent = reorderPark;
            for (let r = 0; r < orderedItems.length; r++)
                orderedItems[r].parent = root.targetLayout;
            root._isApplyingOrder = false;
            root._hasAppliedOrder = true;
        } else if (!hasCustom) {
            root._hasAppliedOrder = false;
        }

        // Apply per-item width ratio and alignment customizations
        const visList = [];
        const sigParts = [];
        const finalChildren = root.targetLayout.children || [];
        for (let s = 0; s < finalChildren.length; s++) {
            const fch = finalChildren[s];
            if (!root._isReorderableItem(fch))
                continue;
            let fKey = "";
            for (const fk of Object.keys(nextMap)) {
                if (nextMap[fk] === fch) {
                    fKey = fk;
                    break;
                }
            }
            if (!fKey)
                continue;

            const itemFullId = root.containerId + "::" + fKey;
            const itemCfg = SettingsLayoutManager.getInnerItemConfig(itemFullId);
            if (itemCfg.widthRatio > 0 && root.targetLayout.width > 40) {
                const targetW = Math.max(120, Math.round(root.targetLayout.width * itemCfg.widthRatio));
                fch.Layout.fillWidth = false;
                fch.Layout.preferredWidth = targetW;
                fch.Layout.maximumWidth = targetW;
                if (!root._customWidthItems.includes(fch)) {
                    const nextCw = root._customWidthItems.slice();
                    nextCw.push(fch);
                    root._customWidthItems = nextCw;
                }
            } else if (itemCfg.widthRatio === 0 && fch.Layout.preferredWidth > 0 && root._customWidthItems.includes(fch)) {
                fch.Layout.fillWidth = true;
                fch.Layout.preferredWidth = -1;
                fch.Layout.maximumWidth = 16777215;
                root._customWidthItems = root._customWidthItems.filter(it => it !== fch);
            }

            if (itemCfg.alignment === "center" || itemCfg.alignment === "right" || itemCfg.alignment === "left") {
                fch.Layout.alignment = itemCfg.alignment === "center"
                    ? Qt.AlignHCenter
                    : (itemCfg.alignment === "right" ? Qt.AlignRight : Qt.AlignLeft);
                if (!root._customAlignedItems.includes(fch)) {
                    const nextCa = root._customAlignedItems.slice();
                    nextCa.push(fch);
                    root._customAlignedItems = nextCa;
                }
            } else if (root._customAlignedItems.includes(fch)) {
                fch.Layout.alignment = 0;
                root._customAlignedItems = root._customAlignedItems.filter(it => it !== fch);
            }

            if (fch.visible && (fch.height > 8 || fch.implicitHeight > 8)) {
                visList.push({
                    key: fKey,
                    fullId: itemFullId,
                    item: fch,
                    index: visList.length,
                    widthRatio: itemCfg.widthRatio,
                    alignment: itemCfg.alignment
                });
                sigParts.push(itemFullId + ":" + itemCfg.widthRatio + ":" + itemCfg.alignment);
            }
        }
        const nextSig = sigParts.join("|");
        let itemsDiffer = (nextSig !== root._visibleItemsSignature || visList.length !== root._visibleItems.length);
        if (!itemsDiffer) {
            for (let v = 0; v < visList.length; v++) {
                if (root._visibleItems[v]?.item !== visList[v].item) {
                    itemsDiffer = true;
                    break;
                }
            }
        }
        if (itemsDiffer) {
            root._visibleItemsSignature = nextSig;
            root._visibleItems = visList;
        }
    }

    Connections {
        target: SettingsLayoutManager
        function onLayoutRevisionChanged() {
            syncTimer.restart();
        }
        function onEditModeChanged() {
            syncTimer.restart();
        }
        function onInnerEditModeChanged() {
            syncTimer.restart();
        }
    }

    Connections {
        target: root.targetLayout
        function onChildrenChanged() {
            if (!root._isApplyingOrder)
                syncTimer.restart();
        }
        function onWidthChanged() {
            if (root._customWidthItems.length > 0)
                syncTimer.restart();
        }
    }

    Timer {
        id: syncTimer
        interval: 0
        repeat: false
        onTriggered: root.syncChildrenAndOrder()
    }

    onVisibleChanged: {
        if (root.visible)
            syncTimer.restart();
    }

    Component.onCompleted: syncTimer.restart()

    Repeater {
        model: (root.visible && root._visibleItems.length > 0) ? root._visibleItems : []

        delegate: Item {
            id: handleDelegate
            required property var modelData
            required property int index

            readonly property Item targetItem: modelData.item
            readonly property string itemKey: modelData.key
            readonly property string itemFullId: modelData.fullId
            readonly property bool isNestedGroup: {
                const s = String(targetItem);
                return s.indexOf("SettingsGroup") >= 0 || s.indexOf("ContentSubsection") >= 0;
            }

            HoverHandler {
                id: delegateHover
            }

            readonly property bool isRowActive: delegateHover.hovered
                || chipHover.hovered
                || rowDragMouse.pressed
                || upMouse.containsMouse
                || downMouse.containsMouse
                || widthMouse.containsMouse
                || alignMouse.containsMouse

            // Skip showing leaf width controls on a SettingsGroup wrapper if the group itself has its own inner overlay,
            // unless there are multiple groups/subsections in the card that can be reordered!
            visible: targetItem && targetItem.visible && (!isNestedGroup || root._visibleItems.length > 1)
            x: targetItem ? targetItem.x : 0
            y: targetItem ? targetItem.y : 0
            width: targetItem ? targetItem.width : 0
            height: targetItem ? targetItem.height : 0

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.small
                color: rowDragMouse.pressed
                    ? Qt.alpha(Appearance.colors.colPrimary, 0.10)
                    : "transparent"
                border.width: (handleDelegate.isRowActive || modelData.widthRatio > 0) ? 1 : 0
                border.color: Qt.alpha(Appearance.colors.colPrimary, rowDragMouse.pressed ? 0.7 : 0.35)
            }

            Rectangle {
                id: controlChip
                objectName: "innerItemControlChip"
                visible: handleDelegate.isRowActive
                anchors.left: parent.left
                anchors.top: handleDelegate.isNestedGroup ? parent.top : undefined
                anchors.verticalCenter: handleDelegate.isNestedGroup ? undefined : parent.verticalCenter
                anchors.leftMargin: handleDelegate.isNestedGroup ? 4 : -6
                anchors.topMargin: handleDelegate.isNestedGroup ? 2 : 0
                height: 20
                width: chipRow.implicitWidth + 6
                radius: 10
                color: Appearance.colors.colLayer3
                border.width: 1
                border.color: Qt.alpha(Appearance.colors.colPrimary, 0.5)

                HoverHandler {
                    id: chipHover
                }

                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 1

                    // Drag handle for reordering inner item
                    Rectangle {
                        visible: root._visibleItems.length > 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        radius: 8
                        color: rowDragMouse.pressed ? Qt.alpha(Appearance.colors.colPrimary, 0.28) : "transparent"

                        MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "drag_indicator"
                            iconSize: 12
                            color: Appearance.colors.colPrimary
                        }

                        MouseArea {
                            id: rowDragMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                            property real startSceneY: 0

                            onPressed: mouse => {
                                const pt = rowDragMouse.mapToItem(null, mouse.x, mouse.y);
                                startSceneY = pt.y;
                            }

                            onPositionChanged: mouse => {
                                if (!pressed)
                                    return;
                                const pt = rowDragMouse.mapToItem(null, mouse.x, mouse.y);
                                const dy = pt.y - startSceneY;
                                const stepThreshold = Math.max(24, Math.min(56, handleDelegate.height * 0.65));
                                if (Math.abs(dy) >= stepThreshold) {
                                    const dir = dy > 0 ? 1 : -1;
                                    startSceneY = pt.y;
                                    SettingsLayoutManager.moveInnerItem(
                                        root.containerId,
                                        handleDelegate.itemKey,
                                        dir,
                                        root._defaultKeys
                                    );
                                }
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: rowDragMouse.containsMouse && !rowDragMouse.pressed
                            text: Translation.tr("Drag vertically to reorder this setting row")
                        }
                    }

                    // Move Up button
                    Rectangle {
                        visible: root._visibleItems.length > 1 && handleDelegate.index > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        radius: 8
                        color: upMouse.containsMouse ? Qt.alpha(Appearance.colors.colPrimary, 0.22) : "transparent"

                        MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "keyboard_arrow_up"
                            iconSize: 12
                            color: Appearance.colors.colOnLayer2
                        }

                        MouseArea {
                            id: upMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SettingsLayoutManager.moveInnerItem(
                                root.containerId,
                                handleDelegate.itemKey,
                                -1,
                                root._defaultKeys
                            )
                        }

                        StyledToolTip {
                            extraVisibleCondition: upMouse.containsMouse
                            text: Translation.tr("Move setting row up")
                        }
                    }

                    // Move Down button
                    Rectangle {
                        visible: root._visibleItems.length > 1 && handleDelegate.index < root._visibleItems.length - 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        radius: 8
                        color: downMouse.containsMouse ? Qt.alpha(Appearance.colors.colPrimary, 0.22) : "transparent"

                        MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "keyboard_arrow_down"
                            iconSize: 12
                            color: Appearance.colors.colOnLayer2
                        }

                        MouseArea {
                            id: downMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SettingsLayoutManager.moveInnerItem(
                                root.containerId,
                                handleDelegate.itemKey,
                                1,
                                root._defaultKeys
                            )
                        }

                        StyledToolTip {
                            extraVisibleCondition: downMouse.containsMouse
                            text: Translation.tr("Move setting row down")
                        }
                    }

                    // Cycle item width ratio (100% -> 75% -> 50% -> 100%)
                    Rectangle {
                        visible: !handleDelegate.isNestedGroup
                        anchors.verticalCenter: parent.verticalCenter
                        width: modelData.widthRatio > 0 ? 28 : 16
                        height: 16
                        radius: 8
                        color: widthMouse.containsMouse || modelData.widthRatio > 0
                            ? Qt.alpha(Appearance.colors.colPrimary, 0.20)
                            : "transparent"

                        StyledText {
                            visible: modelData.widthRatio > 0
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: `${Math.round(modelData.widthRatio * 100)}%`
                            font.pixelSize: 9
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colPrimary
                        }

                        MaterialSymbol {
                            visible: modelData.widthRatio <= 0
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "width_normal"
                            iconSize: 11
                            color: Appearance.colors.colSubtext
                        }

                        MouseArea {
                            id: widthMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const cur = modelData.widthRatio || 0;
                                let nextRatio = 0.75;
                                if (Math.abs(cur - 0.75) < 0.05)
                                    nextRatio = 0.5;
                                else if (Math.abs(cur - 0.5) < 0.05)
                                    nextRatio = 0;
                                SettingsLayoutManager.updateInnerItemConfig(handleDelegate.itemFullId, {
                                    widthRatio: nextRatio
                                });
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: widthMouse.containsMouse
                            text: Translation.tr("Cycle row width ratio (100% / 75% / 50%)")
                        }
                    }

                    // Alignment cycle when widthRatio < 1.0 (left -> center -> right)
                    Rectangle {
                        visible: !handleDelegate.isNestedGroup && modelData.widthRatio > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        radius: 8
                        color: alignMouse.containsMouse ? Qt.alpha(Appearance.colors.colPrimary, 0.22) : "transparent"

                        MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: modelData.alignment === "center"
                                ? "format_align_center"
                                : (modelData.alignment === "right" ? "format_align_right" : "format_align_left")
                            iconSize: 11
                            color: Appearance.colors.colPrimary
                        }

                        MouseArea {
                            id: alignMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const curA = modelData.alignment || "fill";
                                const nextA = curA === "left" || curA === "fill"
                                    ? "center"
                                    : (curA === "center" ? "right" : "left");
                                SettingsLayoutManager.updateInnerItemConfig(handleDelegate.itemFullId, {
                                    alignment: nextA
                                });
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: alignMouse.containsMouse
                            text: Translation.tr("Cycle horizontal alignment (Left / Center / Right)")
                        }
                    }
                }
            }
        }
    }
}
