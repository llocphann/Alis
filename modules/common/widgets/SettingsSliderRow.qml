import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

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
    // A positive value requests a fixed track. Otherwise the layout shares
    // the available width between the label and track, up to the desktop cap.
    property real sliderWidth: 0
    property string settingsSearchLabel: root.text
    property string settingsSearchDescription: root.description
    property string settingsSearchOptionId: ""
    property var settingsSearchKeywords: []

    signal moved(real value)
    signal seekCommitted(real value)

    Layout.fillWidth: true
    Layout.minimumWidth: 0
    spacing: 10
    implicitHeight: Math.max(labelColumn.implicitHeight, sliderWidget.implicitHeight)

    RowLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredWidth: Math.max(80, labelColumn.implicitWidth + (root.icon.length > 0 ? Appearance.font.pixelSize.large + 8 : 0))
        Layout.maximumWidth: Math.round((root.description.length > 0 ? 360 : 280) * Appearance.fontSizeScale)
        Layout.horizontalStretchFactor: 2
        spacing: 8

        OptionalMaterialSymbol {
            Layout.fillWidth: false
            icon: root.icon
            iconSize: Appearance.font.pixelSize.large
            opacity: root.enabled ? 1 : 0.4
        }

        ColumnLayout {
            id: labelColumn
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            clip: true
            spacing: 1

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
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
                Layout.minimumWidth: 0
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
        readonly property real requestedWidth: customLength > 0 ? customLength : root.sliderWidth
        Layout.fillWidth: !isVertical && requestedWidth <= 0
        Layout.horizontalStretchFactor: Layout.fillWidth ? 6 : -1
        Layout.preferredWidth: sliderWidget.isVertical
            ? sliderWidget.implicitWidth
            : (requestedWidth > 0 ? requestedWidth : Math.round(280 * Appearance.fontSizeScale))
        Layout.maximumWidth: sliderWidget.isVertical
            ? sliderWidget.implicitWidth
            : (requestedWidth > 0 ? requestedWidth : 16777215)
        Layout.minimumWidth: sliderWidget.isVertical
            ? sliderWidget.implicitWidth
            : Math.min(sliderWidget.customLength > 0 ? sliderWidget.customLength : Math.round(96 * Appearance.fontSizeScale), Math.round(96 * Appearance.fontSizeScale))
        Layout.preferredHeight: sliderWidget.isVertical ? sliderWidget.implicitHeight : -1
        Layout.minimumHeight: sliderWidget.isVertical ? sliderWidget.implicitHeight : -1
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
