pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets

Column {
    id: root

    property alias text: sliderName.text
    property string accessibleName: root.text
    property string valueText: Number(root.value).toFixed(root.stepSize > 0 && root.stepSize < 1 ? 2 : 0)
    property alias from: sliderWidget.from
    property alias to: sliderWidget.to
    property alias value: sliderWidget.value
    property alias tooltipContent: sliderWidget.tooltipContent
    property alias stopIndicatorValues: sliderWidget.stopIndicatorValues
    property alias scrollable: sliderWidget.scrollable
    property alias stepSize: sliderWidget.stepSize

    signal moved()
    
    Layout.minimumWidth: 220
    spacing: -2
    RowLayout {
        width: parent.width
        spacing: 8
        visible: root.text.length > 0
        ContentSubsectionLabel {
            id: sliderName
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: ""
        }
        StyledText {
            text: root.valueText
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            horizontalAlignment: Text.AlignRight
        }
    }
    StyledSlider {
        id: sliderWidget
        anchors {
            left: parent.left
            right: parent.right
            leftMargin: 4
            rightMargin: 4
        }
        Accessible.name: root.accessibleName
        configuration: StyledSlider.Configuration.S
        onMoved: root.moved()
    }
}
