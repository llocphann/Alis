pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    objectName: "audioSettings"
    settingsPageName: Translation.tr("Sound")

    readonly property bool outputMuted: Boolean(Audio.sink?.audio?.muted)
    readonly property int outputPercent: Math.round((Audio.osdSinkVolume ?? Audio.value ?? 0) * 100)
    readonly property int inputPercent: Math.round((Audio.micVolume ?? 0) * 100)

    SettingsCardSection {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: true
        expanded: true
        icon: "volume_up"
        title: Translation.tr("Output")

        SettingsGroup {
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                RippleButton {
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    toggled: root.outputMuted
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: Audio.toggleMute()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.outputMuted ? "volume_off" : "volume_up"
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.outputMuted ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                    }

                    StyledToolTip {
                        text: root.outputMuted ? Translation.tr("Unmute output") : Translation.tr("Mute output")
                    }
                }

                SettingsSliderRow {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    icon: ""
                    text: Translation.tr("Output volume")
                    from: 0
                    to: (Config.options?.audio?.protection?.enable ?? false)
                        ? (Config.options?.audio?.protection?.maxAllowed ?? 100)
                        : 150
                    stepSize: 1
                    value: root.outputPercent
                    displayValue: root.outputMuted ? Translation.tr("Muted") : (root.outputPercent + "%")
                    onMoved: nextVal => Audio.setSinkVolume(nextVal / 100.0)
                }
            }

            SettingsDivider {
                visible: Audio.outputDevices.length > 0
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: Audio.outputDevices.length > 0

                Repeater {
                    model: Audio.outputDevices

                    delegate: RippleButton {
                        id: sinkRow
                        required property var modelData
                        readonly property bool isDefault: (Audio.defaultSink?.id ?? -1) === (modelData?.id ?? -2)
                            || (Audio.sink?.id ?? -1) === (modelData?.id ?? -2)

                        Layout.fillWidth: true
                        implicitHeight: 42
                        buttonRadius: Appearance.rounding.small
                        colBackground: isDefault
                            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
                            : Appearance.colors.colLayer2
                        colBackgroundHover: isDefault
                            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                            : Appearance.colors.colLayer2Hover
                        onClicked: Audio.setDefaultSink(modelData)

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            MaterialSymbol {
                                text: sinkRow.isDefault ? "radio_button_checked" : "speaker"
                                iconSize: Appearance.font.pixelSize.normal
                                color: sinkRow.isDefault ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: Audio.friendlyDeviceName(sinkRow.modelData)
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: sinkRow.isDefault ? Font.DemiBold : Font.Normal
                                color: sinkRow.isDefault ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }

                            StyledText {
                                visible: sinkRow.isDefault
                                text: Translation.tr("Active")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Medium
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsCardSection {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: true
        expanded: true
        icon: "mic"
        title: Translation.tr("Input")

        SettingsGroup {
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                RippleButton {
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    toggled: Audio.micMuted
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: Audio.toggleMicMute()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: Audio.micMuted ? "mic_off" : "mic"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Audio.micMuted ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                    }

                    StyledToolTip {
                        text: Audio.micMuted ? Translation.tr("Unmute microphone") : Translation.tr("Mute microphone")
                    }
                }

                SettingsSliderRow {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    icon: ""
                    text: Translation.tr("Input volume")
                    from: 0
                    to: 150
                    stepSize: 1
                    value: root.inputPercent
                    displayValue: Audio.micMuted ? Translation.tr("Muted") : (root.inputPercent + "%")
                    onMoved: nextVal => Audio.setSourceVolume(nextVal / 100.0)
                }
            }

            SettingsDivider {
                visible: Audio.inputDevices.length > 0
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: Audio.inputDevices.length > 0

                Repeater {
                    model: Audio.inputDevices

                    delegate: RippleButton {
                        id: sourceRow
                        required property var modelData
                        readonly property bool isDefault: (Audio.source?.id ?? -1) === (modelData?.id ?? -2)

                        Layout.fillWidth: true
                        implicitHeight: 42
                        buttonRadius: Appearance.rounding.small
                        colBackground: isDefault
                            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
                            : Appearance.colors.colLayer2
                        colBackgroundHover: isDefault
                            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                            : Appearance.colors.colLayer2Hover
                        onClicked: Audio.setDefaultSource(modelData)

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            MaterialSymbol {
                                text: sourceRow.isDefault ? "radio_button_checked" : "mic"
                                iconSize: Appearance.font.pixelSize.normal
                                color: sourceRow.isDefault ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: Audio.friendlyDeviceName(sourceRow.modelData)
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: sourceRow.isDefault ? Font.DemiBold : Font.Normal
                                color: sourceRow.isDefault ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }

                            StyledText {
                                visible: sourceRow.isDefault
                                text: Translation.tr("Active")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Medium
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsCardSection {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: true
        expanded: true
        icon: "tune"
        title: Translation.tr("App Volume Mixer")

        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                visible: Audio.outputAppNodes.length === 0
                text: Translation.tr("No applications playing audio")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            Repeater {
                model: Audio.outputAppNodes

                delegate: ColumnLayout {
                    id: appStreamItem
                    required property var modelData
                    required property int index
                    readonly property bool streamMuted: Boolean(modelData?.audio?.muted)
                    readonly property int streamPercent: Math.round((modelData?.audio?.volume ?? 0) * 100)

                    Layout.fillWidth: true
                    spacing: 6

                    SettingsDivider {
                        visible: appStreamItem.index > 0
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        RippleButton {
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            toggled: appStreamItem.streamMuted
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            onClicked: {
                                if (appStreamItem.modelData?.audio)
                                    appStreamItem.modelData.audio.muted = !appStreamItem.streamMuted
                            }

                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: appStreamItem.streamMuted ? "volume_off" : "graphic_eq"
                                iconSize: Appearance.font.pixelSize.normal
                                color: appStreamItem.streamMuted ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                            }
                        }

                        SettingsSliderRow {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            icon: ""
                            text: Audio.appNodeDisplayName(appStreamItem.modelData)
                            from: 0
                            to: 150
                            stepSize: 1
                            value: appStreamItem.streamPercent
                            displayValue: appStreamItem.streamMuted ? Translation.tr("Muted") : (appStreamItem.streamPercent + "%")
                            onMoved: nextVal => {
                                if (appStreamItem.modelData?.audio)
                                    appStreamItem.modelData.audio.volume = nextVal / 100.0
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsCardSection {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        visible: true
        expanded: true
        icon: "hearing"
        title: Translation.tr("Volume Protection & Event Sounds")

        SettingsGroup {
            SettingsSwitch {
                Layout.fillWidth: true
                buttonIcon: "hearing"
                text: Translation.tr("Earbang protection")
                checked: Config.options?.audio?.protection?.enable ?? false
                onCheckedChanged: Config.setNestedValue("audio.protection.enable", checked)
            }

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    enabled: Config.options?.audio?.protection?.enable ?? false
                    icon: "vertical_align_top"
                    text: Translation.tr("Max volume (%)")
                    value: Config.options?.audio?.protection?.maxAllowed ?? 100
                    from: 20
                    to: 154
                    stepSize: 2
                    onValueChanged: Config.setNestedValue("audio.protection.maxAllowed", value)
                }

                ConfigSpinBox {
                    enabled: Config.options?.audio?.protection?.enable ?? false
                    icon: "trending_up"
                    text: Translation.tr("Max step (%)")
                    value: Config.options?.audio?.protection?.maxAllowedIncrease ?? 10
                    from: 2
                    to: 50
                    stepSize: 2
                    onValueChanged: Config.setNestedValue("audio.protection.maxAllowedIncrease", value)
                }
            }

            SettingsSliderRow {
                icon: "notification_sound"
                text: Translation.tr("System sound volume")
                from: 0
                to: 1
                stepSize: 0.05
                value: Config.options?.sounds?.volume ?? 0.5
                displayValue: Math.round((Config.options?.sounds?.volume ?? 0.5) * 100) + "%"
                onMoved: nextVal => Config.setNestedValue("sounds.volume", nextVal)
            }
        }
    }
}
