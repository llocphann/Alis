import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property string title: ""
    property string tooltip: ""
    property string settingsTaskSection: ""
    readonly property string subsectionLayoutId: title
    default property alias contentData: sectionContent.data

    Layout.fillWidth: true
    Layout.minimumWidth: 0
    Layout.topMargin: 4
    spacing: 4

    RowLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        visible: (root.title && root.title.length > 0) || (root.tooltip && root.tooltip.length > 0)
        spacing: 6

        ContentSubsectionLabel {
            Layout.minimumWidth: 0
            visible: root.title && root.title.length > 0
            text: root.title
        }
        MaterialSymbol {
            visible: root.tooltip && root.tooltip.length > 0
            text: "info"
            iconSize: Appearance.font.pixelSize.normal
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

    ColumnLayout {
        id: sectionContent
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 4
    }
}
