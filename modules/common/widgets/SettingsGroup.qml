import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    default property alias contentData: content.data
    property alias spacing: content.spacing

    Layout.fillWidth: true
    Layout.fillHeight: false
    Layout.minimumWidth: 0
    implicitHeight: content.implicitHeight + SettingsMaterialPreset.groupPadding * 2

    function _nodeWantsVerticalExpand(ch, depth) {
        if (!ch || !ch.visible || !ch.Layout || !ch.Layout.fillHeight || (depth || 0) > 8)
            return false;
        if (ch.objectName === "settingsInnerReorderOverlay")
            return false;
        if (ch._hasFillHeightChild !== undefined)
            return Boolean(ch._hasFillHeightChild);
        var isRow = (ch instanceof RowLayout) || String(ch).indexOf("QQuickRowLayout") === 0;
        var isLayout = isRow
            || (ch instanceof ColumnLayout)
            || (ch instanceof GridLayout)
            || (ch instanceof StackLayout)
            || String(ch).indexOf("Layout") >= 0;
        if (isLayout) {
            var sub = ch.children || [];
            for (var i = 0; i < sub.length; i++) {
                var child = sub[i];
                if (isRow && child && !(child instanceof Flickable) && String(child).indexOf("ScrollView") < 0 && !(child instanceof ColumnLayout) && child.implicitWidth !== undefined && child.implicitWidth <= 4 && child.width <= 4)
                    continue;
                if (root._nodeWantsVerticalExpand(child, (depth || 0) + 1))
                    return true;
            }
            return false;
        }
        return true;
    }

    readonly property bool _hasFillHeightChild: {
        var kids = content.children;
        for (var i = 0; i < kids.length; i++) {
            if (root._nodeWantsVerticalExpand(kids[i], 0))
                return true;
        }
        return false;
    }

    radius: SettingsMaterialPreset.groupRadius
    color: SettingsMaterialPreset.groupColor
    border.width: 0
    border.color: SettingsMaterialPreset.groupBorderColor

    Behavior on color {
        enabled: Appearance.animationsEnabled
        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
    }
    Behavior on border.color {
        enabled: Appearance.animationsEnabled
        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
    }
    Behavior on border.width {
        enabled: Appearance.animationsEnabled
        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
    }

    property string groupLayoutId: ""
    property string _autoGroupLayoutId: ""
    property bool _inSettingsCard: false
    property Item _owningCard: null

    function _resolveGroupLayoutId() {
        var card = null;
        var page = null;
        var subTitle = "";
        var idx = 0;
        if (root.parent && root.parent.children) {
            for (var i = 0; i < root.parent.children.length; i++) {
                if (root.parent.children[i] === root) {
                    idx = i;
                    break;
                }
            }
        }
        var p = root.parent;
        while (p) {
            if (!card && p.hasOwnProperty("moduleId") && p.hasOwnProperty("bentoColumn"))
                card = p;
            else if (!card && !subTitle && p.hasOwnProperty("subsectionLayoutId") && p.title)
                subTitle = String(p.title);
            if (!page && p.hasOwnProperty("settingsPageIndex"))
                page = p;
            p = p.parent;
        }
        root._owningCard = card;
        root._inSettingsCard = (card !== null || page !== null);
        if (root._inSettingsCard && (!root.groupLayoutId || root.groupLayoutId === root._autoGroupLayoutId)) {
            var pageIdx = page && page.settingsPageIndex !== undefined ? page.settingsPageIndex : -1;
            var prefix = (card && card.moduleId)
                ? card.moduleId
                : (card && card.title
                    ? SettingsLayoutManager.makeModuleId(pageIdx, card.title, card._declarationOrder)
                    : ("p" + pageIdx));
            var subSlug = subTitle
                ? subTitle.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
                : "";
            var nextId = prefix + (subSlug ? (":" + subSlug) : "") + ":group-" + idx;
            root._autoGroupLayoutId = nextId;
            root.groupLayoutId = nextId;
        }
    }

    Connections {
        target: root._owningCard
        ignoreUnknownSignals: true
        function onModuleIdChanged() {
            root._resolveGroupLayoutId();
        }
        function onTitleChanged() {
            root._resolveGroupLayoutId();
        }
    }

    Component.onCompleted: root._resolveGroupLayoutId()

    function ensureControlOnActiveSubTab(control) {
        // Pagination is handled at ContentPage level.
    }

    ColumnLayout {
        id: content
        objectName: "settingsGroupContent"
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: SettingsMaterialPreset.groupPadding
            rightMargin: SettingsMaterialPreset.groupPadding
            topMargin: SettingsMaterialPreset.groupPadding
        }
        height: (root.Layout.fillHeight && root._hasFillHeightChild)
            ? Math.max(implicitHeight, root.height - SettingsMaterialPreset.groupPadding * 2)
            : implicitHeight
        spacing: SettingsMaterialPreset.groupSpacing
    }

    Loader {
        id: groupInnerReorderLoader
        anchors.fill: content
        z: 22
        active: root._inSettingsCard && root.groupLayoutId.length > 0
            && (SettingsLayoutManager.editMode
                || SettingsLayoutManager.hasInnerCustomizations(root.groupLayoutId))
        sourceComponent: SettingsInnerReorderOverlay {
            anchors.fill: parent
            targetLayout: content
            containerId: root.groupLayoutId
            activeInSettings: root._inSettingsCard && root.groupLayoutId.length > 0
            isGroupContainer: true
        }
    }
}
