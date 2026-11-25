import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ContentPage {
    id: root

    property string tabId: SettingsLayoutManager.activeCustomTabId
    customTabId: root.tabId
    settingsPageIndex: -1
    settingsPageName: {
        const ct = typeof SettingsLayoutManager.getCustomTab === "function"
            ? SettingsLayoutManager.getCustomTab(root.customTabId)
            : null;
        return ct ? ct.label : Translation.tr("Custom Tab");
    }

    readonly property bool hasHostedModules: false

    Rectangle {
        visible: !root.hasHostedModules
        Layout.fillWidth: true
        implicitHeight: emptyCol.implicitHeight + 48
        radius: SettingsMaterialPreset.cardRadius
        color: SettingsMaterialPreset.cardColor
        border.width: 1
        border.color: SettingsMaterialPreset.cardBorderColor

        ColumnLayout {
            id: emptyCol
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 460)
            spacing: 10

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "dashboard_customize"
                iconSize: 36
                color: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.settingsPageName
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurface
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Translation.tr("This custom view has no assigned sections.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }
    }
}
