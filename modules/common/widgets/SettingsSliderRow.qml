import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RowLayout {
    id: root
    objectName: "settingsSliderRow"

    property string icon: ""
    property string text: ""
    property string description: ""
    property alias value: sliderWidget.value
    property alias from: sliderWidget.from
    property alias to: sliderWidget.to
    property alias stepSize: sliderWidget.stepSize
    property alias liveValue: sliderWidget.liveValue
    property alias pressed: sliderWidget.pressed
    property string unit: ""
    property int decimals: (root.stepSize > 0 && root.stepSize < 1) ? 2 : 0
    property string displayValue: ""
    property string valueText: root.displayValue.length > 0 ? root.displayValue : (Number(root.value).toFixed(root.decimals) + root.unit)
    property real sliderWidth: Math.round(190 * Appearance.fontSizeScale)
    property string settingsSearchLabel: root.text
    property string settingsSearchDescription: root.description
    property string settingsSearchOptionId: ""
    property var settingsSearchKeywords: []

    signal moved(real value)
    signal seekCommitted(real value)

    Layout.fillWidth: true
    spacing: 10
    implicitHeight: Math.max(labelColumn.implicitHeight, sliderWidget.implicitHeight)

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        OptionalMaterialSymbol {
            icon: root.icon
            iconSize: Appearance.font.pixelSize.large
            opacity: root.enabled ? 1 : 0.4
        }

        ColumnLayout {
            id: labelColumn
            Layout.fillWidth: true
            spacing: 1

            StyledText {
                Layout.fillWidth: true
                text: root.text
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurface
                opacity: root.enabled ? 1 : 0.4
                marquee: true
                maximumLineCount: 1
            }

            StyledText {
                visible: root.description.length > 0
                Layout.fillWidth: true
                text: root.description
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                opacity: root.enabled ? 0.9 : 0.4
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    StyledSlider {
        id: sliderWidget
        Layout.fillWidth: false
        Layout.preferredWidth: root.sliderWidth
        Layout.maximumWidth: Math.round(220 * Appearance.fontSizeScale)
        Layout.minimumWidth: Math.round(120 * Appearance.fontSizeScale)
        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
        configuration: StyledSlider.Configuration.S
        tooltipContent: root.valueText
        Accessible.name: root.text
        settingsSearchLabel: root.settingsSearchLabel
        settingsSearchDescription: root.settingsSearchDescription
        settingsSearchOptionId: root.settingsSearchOptionId
        settingsSearchKeywords: root.settingsSearchKeywords
        onMoved: root.moved(sliderWidget.value)
        onSeekCommitted: val => root.seekCommitted(val)
    }

    StyledText {
        visible: root.valueText.length > 0
        Layout.preferredWidth: Math.round(48 * Appearance.fontSizeScale)
        Layout.minimumWidth: Math.round(40 * Appearance.fontSizeScale)
        Layout.alignment: Qt.AlignVCenter
        horizontalAlignment: Text.AlignRight
        text: root.valueText
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.family: Appearance.font.family.numbers
        color: Appearance.colors.colSubtext
        opacity: root.enabled ? 1 : 0.4
    }
}
