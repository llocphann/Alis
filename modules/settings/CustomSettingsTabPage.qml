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
        const ct = SettingsLayoutManager.getCustomTab(root.customTabId);
        return ct ? ct.label : Translation.tr("Custom Tab");
    }

    readonly property bool hasHostedModules: (root._topBentoCount + root._leftBentoCount + root._rightBentoCount + root._activeCanvasCount) > 0

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
                text: Translation.tr("This custom tab is empty. Drag any Settings module onto this tab in the sidebar, or open the Module Drawer in Edit Layout mode to add modules here.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            RippleButton {
                Layout.alignment: Qt.AlignHCenter
                implicitHeight: 34
                implicitWidth: openEditRow.implicitWidth + 24
                buttonRadius: 17
                colBackground: Appearance.colors.colPrimary
                onClicked: SettingsLayoutManager.editMode = true

                StyledToolTip {
                    text: Translation.tr("Enter Edit Layout mode and open the Module Drawer")
                }

                contentItem: Item {
                    implicitWidth: openEditRow.implicitWidth
                    implicitHeight: openEditRow.implicitHeight

                    Row {
                        id: openEditRow
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "dashboard_customize"
                            iconSize: 16
                            color: Appearance.colors.colOnPrimary
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            verticalAlignment: Text.AlignVCenter
                            text: Translation.tr("Edit Layout & Add Modules")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }
        }
    }
}
