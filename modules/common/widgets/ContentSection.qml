import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property string title
    property string icon: ""
    property int irisSectionNumber: 0
    property int irisSectionTotal: 0
    readonly property string irisNumberText: (root.irisSectionNumber > 0 && root.irisSectionTotal > 0)
        ? ((root.irisSectionNumber < 10 ? "0" : "") + String(root.irisSectionNumber) + " / " + (root.irisSectionTotal < 10 ? "0" : "") + String(root.irisSectionTotal))
        : ""
    property var _registeredPage: null
    default property alias contentData: sectionContent.data
    
    // Settings search integration
    property bool enableSettingsSearch: true
    property int settingsSearchOptionId: -1

    Layout.fillWidth: true
    spacing: 6

    function _findSettingsContext() {
        var page = null;
        var p = root.parent;
        while (p) {
            if (!page && p.hasOwnProperty("settingsPageIndex")) {
                page = p;
                break;
            }
            p = p.parent;
        }
        return { page: page };
    }

    function focusFromSettingsSearch() {
        root.forceActiveFocus();
    }

    Component.onCompleted: {
        var ctx = _findSettingsContext();
        var page = ctx.page;
        if (page && typeof page.registerContentSection === "function") {
            root._registeredPage = page;
            page.registerContentSection(root);
        }

        if (!enableSettingsSearch || !root.title)
            return;
        if (typeof SettingsSearchRegistry === "undefined")
            return;

        settingsSearchOptionId = SettingsSearchRegistry.registerOption({
            control: root,
            pageIndex: page && page.settingsPageIndex !== undefined ? page.settingsPageIndex : -1,
            pageName: page && page.settingsPageName ? page.settingsPageName : "",
            section: root.title,
            label: root.title,
            description: "",
            keywords: []
        });
    }

    Component.onDestruction: {
        if (root._registeredPage && typeof root._registeredPage.unregisterContentSection === "function") {
            root._registeredPage.unregisterContentSection(root);
        }
        if (typeof SettingsSearchRegistry !== "undefined") {
            SettingsSearchRegistry.unregisterControl(root);
        }
    }

    onVisibleChanged: {
        if (root._registeredPage && !root._registeredPage._isDestroying && typeof root._registeredPage.notifyCardEligibilityChanged === "function") {
            root._registeredPage.notifyCardEligibilityChanged();
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 9

        Rectangle {
            visible: !SettingsMaterialPreset.waffle && root.icon && root.icon.length > 0
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Math.round(26 * Appearance.fontSizeScale)
            implicitHeight: implicitWidth
            radius: 8
            color: SettingsMaterialPreset.accentTint
            border.width: 1
            border.color: SettingsMaterialPreset.accentBorder

            MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.icon
                iconSize: Math.round(15 * Appearance.fontSizeScale)
                color: Appearance.colors.colPrimary
            }
        }

        OptionalMaterialSymbol {
            visible: SettingsMaterialPreset.waffle && root.icon && root.icon.length > 0
            icon: root.icon
            iconSize: Appearance.font.pixelSize.larger
            color: SettingsMaterialPreset.iconExpandedColor
        }
        StyledText {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: root.title
            font.family: SettingsMaterialPreset.fontFamily
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
            color: SettingsMaterialPreset.titleExpandedColor
        }
    }

    ColumnLayout {
        id: sectionContent
        Layout.fillWidth: true
        spacing: 4

    }
}
