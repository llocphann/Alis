pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Refined Settings slider row with automatic stacked layout on narrow widths
 * (so labels like "Output volume" / "Input volume" never truncate) and a
 * crisp tabular numeric value pill.
 */
Item {
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
    property real sliderWidth: 0
    property bool compactStacked: false
    property string settingsSearchLabel: root.text
    property string settingsSearchDescription: root.description
    property alias settingsSearchOptionId: sliderWidget.settingsSearchOptionId
    property var settingsSearchKeywords: []

    readonly property bool _useStacked: root.compactStacked || (root.width > 0 && root.width < Math.round(420 * Appearance.fontSizeScale))

    signal moved(real value)
    signal seekCommitted(real value)

    Layout.fillWidth: true
    Layout.minimumWidth: 0
    implicitHeight: root._useStacked ? stackedLayout.implicitHeight : inlineLayout.implicitHeight

    // ── Stacked layout (narrow columns & audio channel cards: ZERO label clipping) ──
    ColumnLayout {
        id: stackedLayout
        visible: root._useStacked
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 8

            OptionalMaterialSymbol {
                visible: root.icon.length > 0
                Layout.fillWidth: false
                icon: root.icon
                iconSize: Appearance.font.pixelSize.normal
                opacity: root.enabled ? 1 : 0.4
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.text
                    font.family: SettingsMaterialPreset.fontFamily
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: SettingsMaterialPreset.textColor
                    opacity: root.enabled ? 1 : 0.4
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                StyledText {
                    visible: root.description.length > 0
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.description
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: SettingsMaterialPreset.secondaryTextColor
                    opacity: root.enabled ? 0.9 : 0.4
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            Rectangle {
                visible: root.valueText.length > 0
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: Math.round(22 * Appearance.fontSizeScale)
                implicitWidth: Math.max(Math.round(46 * Appearance.fontSizeScale), stackedValText.implicitWidth + 14)
                radius: height / 2
                color: SettingsMaterialPreset.controlSurface
                border.width: 1
                border.color: SettingsMaterialPreset.controlBorderColor

                StyledText {
                    id: stackedValText
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.valueText
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.numbers
                    font.features: ({ "tnum": 1 })
                    font.weight: Font.Medium
                    color: SettingsMaterialPreset.textColor
                    opacity: root.enabled ? 1 : 0.4
                }
            }
        }

        Item {
            id: stackedSliderSlot
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            implicitHeight: sliderWidget.implicitHeight
        }
    }

    // ── Inline layout (wide rows: balanced label + track + tabular value pill) ──
    RowLayout {
        id: inlineLayout
        visible: !root._useStacked
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: Math.max(120, labelColumn.implicitWidth + (root.icon.length > 0 ? Appearance.font.pixelSize.large + 8 : 0))
            Layout.maximumWidth: Math.round((root.description.length > 0 ? 340 : 260) * Appearance.fontSizeScale)
            Layout.horizontalStretchFactor: 2
            spacing: 8

            OptionalMaterialSymbol {
                visible: root.icon.length > 0
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
                    font.family: SettingsMaterialPreset.fontFamily
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: SettingsMaterialPreset.textColor
                    opacity: root.enabled ? 1 : 0.4
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                StyledText {
                    visible: root.description.length > 0
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.description
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: SettingsMaterialPreset.secondaryTextColor
                    opacity: root.enabled ? 0.9 : 0.4
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }

        Item {
            id: inlineSliderSlot
            Layout.fillWidth: root.sliderWidth <= 0
            Layout.horizontalStretchFactor: Layout.fillWidth ? 5 : -1
            Layout.preferredWidth: root.sliderWidth > 0 ? root.sliderWidth : Math.round(260 * Appearance.fontSizeScale)
            Layout.minimumWidth: Math.round(110 * Appearance.fontSizeScale)
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: sliderWidget.implicitHeight
        }

        Rectangle {
            visible: root.valueText.length > 0
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: Math.round(24 * Appearance.fontSizeScale)
            implicitWidth: Math.max(Math.round(52 * Appearance.fontSizeScale), inlineValText.implicitWidth + 14)
            radius: height / 2
            color: SettingsMaterialPreset.controlSurface
            border.width: 1
            border.color: SettingsMaterialPreset.controlBorderColor

            StyledText {
                id: inlineValText
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.valueText
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: Appearance.font.family.numbers
                font.features: ({ "tnum": 1 })
                font.weight: Font.Medium
                color: SettingsMaterialPreset.textColor
                opacity: root.enabled ? 1 : 0.4
            }
        }
    }

    // Single slider instance reparented cleanly between stacked and inline slots
    StyledSlider {
        id: sliderWidget
        parent: root._useStacked ? stackedSliderSlot : inlineSliderSlot
        anchors.fill: parent
        configuration: StyledSlider.Configuration.S
        tooltipContent: root.valueText
        Accessible.name: root.text
        settingsSearchLabel: root.settingsSearchLabel
        settingsSearchDescription: root.settingsSearchDescription
        settingsSearchKeywords: root.settingsSearchKeywords
        onMoved: root.moved(sliderWidget.value)
        onSeekCommitted: val => root.seekCommitted(val)
    }
}
