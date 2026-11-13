import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    default property alias contentData: content.data
    property alias spacing: content.spacing

    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumWidth: 0
    implicitHeight: content.implicitHeight + SettingsMaterialPreset.groupPadding * 2

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
            fill: parent
            margins: SettingsMaterialPreset.groupPadding
        }
        spacing: SettingsMaterialPreset.groupSpacing
    }

    SettingsInnerReorderOverlay {
        anchors.fill: content
        targetLayout: content
        containerId: root.groupLayoutId
        activeInSettings: root._inSettingsCard && root.groupLayoutId.length > 0
        isGroupContainer: true
    }
}
