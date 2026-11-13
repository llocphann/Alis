import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property string title: ""
    property string tooltip: ""
    property string settingsTaskSection: ""
    default property alias contentData: sectionContent.data

    Layout.fillWidth: true
    Layout.minimumWidth: 0
    Layout.topMargin: 4
    spacing: 2

    RowLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        ContentSubsectionLabel {
            Layout.minimumWidth: 0
            visible: root.title && root.title.length > 0
            text: root.title
        }
        MaterialSymbol {
            visible: root.tooltip && root.tooltip.length > 0
            text: "info"
            iconSize: Appearance.font.pixelSize.large
            
            color: Appearance.colors.colSubtext
            MouseArea {
                id: infoMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.WhatsThisCursor
                StyledToolTip {
                    extraVisibleCondition: false
                    alternativeVisibleCondition: infoMouseArea.containsMouse
                    text: root.tooltip
                }
            }
        }
        Item { Layout.fillWidth: true }
    }
    property string subsectionLayoutId: ""
    property string _autoSubsectionLayoutId: ""
    property bool _inSettingsCard: false
    property Item _owningCard: null

    function _resolveSubsectionLayoutId() {
        var card = null;
        var page = null;
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
            if (!page && p.hasOwnProperty("settingsPageIndex"))
                page = p;
            p = p.parent;
        }
        root._owningCard = card;
        root._inSettingsCard = (card !== null || page !== null);
        if (root._inSettingsCard && (!root.subsectionLayoutId || root.subsectionLayoutId === root._autoSubsectionLayoutId)) {
            var pageIdx = page && page.settingsPageIndex !== undefined ? page.settingsPageIndex : -1;
            var prefix = (card && card.moduleId)
                ? card.moduleId
                : (card && card.title
                    ? SettingsLayoutManager.makeModuleId(pageIdx, card.title, card._declarationOrder)
                    : ("p" + pageIdx));
            var slug = String(root.title || ("sub-" + idx))
                .toLowerCase()
                .replace(/[^a-z0-9]+/g, "-")
                .replace(/^-+|-+$/g, "");
            var nextId = prefix + ":sub:" + (slug || ("sub-" + idx));
            root._autoSubsectionLayoutId = nextId;
            root.subsectionLayoutId = nextId;
        }
    }

    Connections {
        target: root._owningCard
        ignoreUnknownSignals: true
        function onModuleIdChanged() {
            root._resolveSubsectionLayoutId();
        }
        function onTitleChanged() {
            root._resolveSubsectionLayoutId();
        }
    }

    onTitleChanged: root._resolveSubsectionLayoutId()
    Component.onCompleted: root._resolveSubsectionLayoutId()

    Item {
        Layout.fillWidth: true
        implicitHeight: sectionContent.implicitHeight

        ColumnLayout {
            id: sectionContent
            width: parent.width
            spacing: 2
        }

        SettingsInnerReorderOverlay {
            anchors.fill: sectionContent
            targetLayout: sectionContent
            containerId: root.subsectionLayoutId
            activeInSettings: root._inSettingsCard && root.subsectionLayoutId.length > 0
        }
    }
}
