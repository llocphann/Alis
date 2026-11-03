pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets

RowLayout {
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

    Layout.fillWidth: true
    Layout.minimumWidth: 200
    spacing: 10
    implicitHeight: Math.max(sliderName.implicitHeight, sliderWidget.implicitHeight)

    ContentSubsectionLabel {
        id: sliderName
        visible: root.text.length > 0
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.alignment: Qt.AlignVCenter
        elide: Text.ElideRight
        text: ""
    }

    StyledSlider {
        id: sliderWidget
        Layout.fillWidth: !sliderName.visible
        Layout.preferredWidth: sliderName.visible ? Math.round(185 * Appearance.fontSizeScale) : -1
        Layout.maximumWidth: sliderName.visible ? Math.round(210 * Appearance.fontSizeScale) : -1
        Layout.minimumWidth: Math.round(110 * Appearance.fontSizeScale)
        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
        Accessible.name: root.accessibleName
        configuration: StyledSlider.Configuration.S
        onMoved: root.moved()
    }

    StyledText {
        visible: root.text.length > 0
        Layout.preferredWidth: Math.round(44 * Appearance.fontSizeScale)
        Layout.alignment: Qt.AlignVCenter
        text: root.valueText
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.family: Appearance.font.family.numbers
        horizontalAlignment: Text.AlignRight
    }
}
