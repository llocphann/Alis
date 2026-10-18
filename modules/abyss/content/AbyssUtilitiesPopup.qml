pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings
import qs.modules.sidebarRight.nightLight
import qs.modules.abyss.looks

Item {
    id: root

    property string outputName: ""
    property bool wirelessToolAvailable: false
    Process {
        id: wirelessToolProbe
        command: ["/bin/sh", "-c", "command -v gnome-network-displays >/dev/null 2>&1"]
        onExited: exitCode => root.wirelessToolAvailable = exitCode === 0
    }
    Component.onCompleted: wirelessToolProbe.running = true
    property alias currentPage: pages.currentIndex
    readonly property var currentFeature: pages.currentItem?.item ?? null
    readonly property int loadedPageCount: [monitorLoader, displayLoader, audioLoader, nightLoader]
        .filter(loader => loader.active && loader.item !== null).length
    readonly property var pageTitles: [
        "Monitor arrangement", "Display mode", "Sound", "Eye protection"
    ]
    // All Utilities pages share one compact fixed viewport. The 400 px height
    // still fits the monitor-arrangement canvas while avoiding empty lower space
    // on Display, Sound and Eye protection.
    readonly property int panelWidth: 620
    readonly property int panelHeight: 400
    readonly property color utilityInk: Appearance.m3colors.darkmode
        ? AbyssStyle.textColor : "#000000"
    readonly property color utilityMutedInk: Appearance.m3colors.darkmode
        ? AbyssStyle.textColorMuted : "#1a1a1a"

    implicitWidth: panelWidth
    implicitHeight: panelHeight

    // Interactive descendants acquire focus on demand. Pre-focusing this
    // hover-owned surface would hold the shared dismissal lease forever.
    focus: false
    signal closeRequested()

    Keys.onLeftPressed: event => {
        if (pages.currentIndex > 0) pages.currentIndex--
        event.accepted = true
    }
    Keys.onRightPressed: event => {
        if (pages.currentIndex < pages.count - 1) pages.currentIndex++
        event.accepted = true
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            AbyssLabel {
                text: root.pageTitles[pages.currentIndex] ?? "Utilities"
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }

        }

        SwipeView {
            id: pages
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            interactive: true

            Loader {
                id: monitorLoader
                active: Math.abs(SwipeView.index - pages.currentIndex) <= 1
                sourceComponent: monitorPage
            }
            Loader {
                id: displayLoader
                active: Math.abs(SwipeView.index - pages.currentIndex) <= 1
                sourceComponent: displayPage
            }
            Loader {
                id: audioLoader
                active: Math.abs(SwipeView.index - pages.currentIndex) <= 1
                sourceComponent: audioPage
            }
            Loader {
                id: nightLoader
                active: Math.abs(SwipeView.index - pages.currentIndex) <= 1
                sourceComponent: nightPage
            }
        }

        Row {
            objectName: "utilitiesPageIndicators"
            Layout.alignment: Qt.AlignHCenter
            spacing: 8

            Repeater {
                model: pages.count
                delegate: Rectangle {
                    required property int index
                    width: index === pages.currentIndex ? 9 : 7
                    height: width
                    radius: width / 2
                    color: index === pages.currentIndex
                        ? AbyssStyle.accent : Qt.alpha(root.utilityInk, .28)

                    Behavior on width {
                        enabled: AbyssStyle.motionEnabled
                        NumberAnimation { duration: AbyssStyle.motionFast; easing.type: Easing.OutCubic }
                    }
                    Behavior on color {
                        enabled: AbyssStyle.motionEnabled
                        ColorAnimation { duration: AbyssStyle.motionFast }
                    }

                    TapHandler {
                        onTapped: pages.currentIndex = parent.index
                    }
                }
            }
        }
    }

    Component {
        id: monitorPage

        Item {
            Loader {
                anchors.fill: parent
                active: CompositorService.isNiri
                sourceComponent: MonitorVisibilityConfig {
                    embeddedArrangementOnly: true
                    activeSection: "outputs"
                }
            }

            AbyssLabel {
                anchors.centerIn: parent
                width: Math.min(parent.width - 40, 520)
                visible: !CompositorService.isNiri
                horizontalAlignment: Text.AlignHCenter
                text: "Niri only."
                color: root.utilityMutedInk
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }

    Component {
        id: displayPage

        Item {
            ColumnLayout {
                anchors.fill: parent
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    AbyssButton {
                        Layout.fillWidth: true
                        glyph: "view_week"
                        text: "Extend"
                        font.pixelSize: Appearance.font.pixelSize.small
                        checked: DisplayMode.currentMode === "extend"
                        enabled: CompositorService.isNiri && !DisplayMode.applying
                        onClicked: DisplayMode.apply("extend")
                    }
                    AbyssButton {
                        Layout.fillWidth: true
                        glyph: "laptop"
                        text: "Primary only"
                        font.pixelSize: Appearance.font.pixelSize.small
                        checked: DisplayMode.currentMode === "primary-only"
                        enabled: CompositorService.isNiri && !DisplayMode.applying
                        onClicked: DisplayMode.apply("primary-only")
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        AbyssLabel {
                            text: "Second screen"
                            color: root.utilityMutedInk
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                        StyledComboBox {
                            Layout.fillWidth: true
                            enableSettingsSearch: false
                            readonly property var outputIds: DisplayMode.connectedOutputs.filter(
                                output => output !== DisplayMode.primaryOutput)
                            model: outputIds.map(output => DisplayMode.outputLabel(output))
                            currentIndex: Math.max(0, outputIds.indexOf(DisplayMode.selectedSecondary))
                            enabled: outputIds.length > 0 && !DisplayMode.applying
                            onActivated: {
                                const selected = outputIds[currentIndex]
                                if (selected) DisplayMode.selectedSecondary = selected
                            }
                        }
                    }

                    AbyssButton {
                        Layout.alignment: Qt.AlignBottom
                        glyph: "desktop_windows"
                        text: "Second screen only"
                        font.pixelSize: Appearance.font.pixelSize.small
                        checked: DisplayMode.currentMode === "second-only"
                        enabled: CompositorService.isNiri && !DisplayMode.applying
                            && DisplayMode.selectedSecondary.length > 0
                        onClicked: DisplayMode.apply("second-only")
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: mirrorColumn.implicitHeight + 24
                    radius: 18
                    color: Qt.alpha(AbyssStyle.accent, .05)
                    border.width: 1
                    border.color: Qt.alpha(AbyssStyle.accent, .16)

                    ColumnLayout {
                        id: mirrorColumn
                        anchors {
                            fill: parent
                            margins: 12
                        }
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            AbyssLabel {
                                text: "Mirror"
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                Layout.fillWidth: true
                            }
                            AbyssLabel {
                                visible: !DisplayMode.mirrorAvailable
                                text: "Install wl-mirror"
                                color: Appearance.colors.colError
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                AbyssLabel {
                                    text: "Source"
                                    color: root.utilityMutedInk
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                                StyledComboBox {
                                    Layout.fillWidth: true
                                    enableSettingsSearch: false
                                    model: DisplayMode.connectedOutputs.map(output => DisplayMode.outputLabel(output))
                                    currentIndex: Math.max(0, DisplayMode.connectedOutputs.indexOf(DisplayMode.mirrorSource))
                                    enabled: DisplayMode.connectedOutputs.length > 1 && !DisplayMode.applying
                                    onActivated: DisplayMode.setMirrorSource(DisplayMode.connectedOutputs[currentIndex])
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                AbyssLabel {
                                    text: "Target"
                                    color: root.utilityMutedInk
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                                StyledComboBox {
                                    Layout.fillWidth: true
                                    enableSettingsSearch: false
                                    readonly property var outputIds: DisplayMode.connectedOutputs.filter(
                                        output => output !== DisplayMode.mirrorSource)
                                    model: outputIds.map(output => DisplayMode.outputLabel(output))
                                    currentIndex: Math.max(0, outputIds.indexOf(DisplayMode.mirrorTarget))
                                    enabled: outputIds.length > 0 && !DisplayMode.applying
                                    onActivated: DisplayMode.setMirrorTarget(outputIds[currentIndex])
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true }
                            AbyssButton {
                                glyph: DisplayMode.currentMode === "mirror" ? "stop_screen_share" : "screen_share"
                                text: DisplayMode.currentMode === "mirror" ? "Stop mirror" : "Mirror"
                                font.pixelSize: Appearance.font.pixelSize.small
                                enabled: DisplayMode.mirrorAvailable && !DisplayMode.applying
                                    && DisplayMode.mirrorSource.length > 0
                                    && DisplayMode.mirrorTarget.length > 0
                                onClicked: {
                                    if (DisplayMode.currentMode === "mirror") DisplayMode.stopMirror(true)
                                    else DisplayMode.apply("mirror")
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    AbyssLabel {
                        Layout.fillWidth: true
                        text: "Wireless TV · Miracast / Chromecast"
                        color: root.utilityMutedInk
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    AbyssButton {
                        glyph: "cast"
                        text: root.wirelessToolAvailable ? "Find TV" : "Install Network Displays"
                        font.pixelSize: Appearance.font.pixelSize.small
                        enabled: root.wirelessToolAvailable
                        onClicked: Quickshell.execDetached(["gnome-network-displays"])
                    }
                }

                Item { Layout.fillHeight: true }

                AbyssLabel {
                    Layout.fillWidth: true
                    visible: DisplayMode.statusMessage.length > 0 || DisplayMode.lastError.length > 0
                    text: DisplayMode.lastError.length > 0
                        ? DisplayMode.lastError : DisplayMode.statusMessage
                    color: DisplayMode.lastError.length > 0
                        ? Appearance.colors.colError : root.utilityMutedInk
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }
            }
        }
    }

    Component {
        id: audioPage

        Item {
            ColumnLayout {
                anchors.fill: parent
                spacing: 10

                AbyssLabel {
                    Layout.fillWidth: true
                    text: Audio.sink ? "Output · " + Audio.friendlyDeviceName(Audio.sink)
                        : "No active audio output"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    AbyssButton {
                        compact: true
                        glyph: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
                        description: Audio.sink?.audio?.muted ? "Unmute output" : "Mute output"
                        enabled: !!Audio.sink?.audio
                        onClicked: Audio.toggleMute()
                    }

                    AbyssSlider {
                        Layout.fillWidth: true
                        from: 0
                        to: Math.min(2, Audio.hardMaxValue)
                        value: Audio.value
                        unit: "%"
                        enabled: !!Audio.sink?.audio
                        onMoved: Audio.setSinkVolume(value)
                    }
                }

                StyledComboBox {
                    Layout.fillWidth: true
                    enableSettingsSearch: false
                    model: Audio.outputDevices.map(device => Audio.friendlyDeviceName(device))
                    currentIndex: Audio.outputDevices.findIndex(device =>
                        device.id === Audio.sink?.id)
                    enabled: Audio.outputDevices.length > 0
                    onActivated: {
                        const device = Audio.outputDevices[currentIndex]
                        if (device) {
                            ProjectAudio.releaseOwnership()
                            Audio.setDefaultSink(device)
                        }
                    }
                }

                AbyssLabel {
                    Layout.fillWidth: true
                    visible: ProjectAudio.statusMessage.length > 0 || ProjectAudio.lastError.length > 0
                    text: ProjectAudio.lastError.length > 0
                        ? ProjectAudio.lastError : ProjectAudio.statusMessage
                    color: ProjectAudio.lastError.length > 0
                        ? Appearance.colors.colError : root.utilityMutedInk
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Qt.alpha(root.utilityInk, .12)
                }

                AbyssLabel {
                    Layout.fillWidth: true
                    text: Audio.source ? "Input · " + Audio.friendlyDeviceName(Audio.source)
                        : "No active audio input"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    AbyssButton {
                        compact: true
                        glyph: Audio.micMuted ? "mic_off" : "mic"
                        description: Audio.micMuted ? "Unmute input" : "Mute input"
                        enabled: Audio.inputDevices.length > 0 || !!Audio.source?.audio
                        onClicked: Audio.toggleMicMute()
                    }

                    AbyssSlider {
                        Layout.fillWidth: true
                        from: 0
                        to: Math.min(2, Audio.hardMaxValue)
                        value: Audio.micVolume
                        unit: "%"
                        enabled: Audio.inputDevices.length > 0 || !!Audio.source?.audio
                        onMoved: Audio.setSourceVolume(value)
                    }
                }

                StyledComboBox {
                    Layout.fillWidth: true
                    enableSettingsSearch: false
                    model: Audio.inputDevices.map(device => Audio.friendlyDeviceName(device))
                    currentIndex: Audio.inputDevices.findIndex(device =>
                        device.id === Audio.source?.id)
                    enabled: Audio.inputDevices.length > 0
                    onActivated: {
                        const device = Audio.inputDevices[currentIndex]
                        if (device)
                            Audio.setDefaultSource(device)
                    }
                }

                AbyssLabel {
                    Layout.fillWidth: true
                    visible: Audio.outputDevices.length === 0 || Audio.inputDevices.length === 0
                    text: Audio.outputDevices.length === 0 && Audio.inputDevices.length === 0
                        ? "No PipeWire input or output devices are available."
                        : Audio.outputDevices.length === 0
                            ? "No PipeWire output devices are available."
                            : "No PipeWire input devices are available."
                    color: root.utilityMutedInk
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }

                Item { Layout.fillHeight: true }
            }
        }
    }

    Component {
        id: nightPage

        Item {
            NightLightDialog {
                anchors.fill: parent
                embeddedPresentation: true
                show: true
                onDismiss: root.closeRequested()
            }
        }
    }
}
