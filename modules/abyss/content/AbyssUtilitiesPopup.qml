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
        "Monitor arrangement", "Project & Cast", "Sound", "Eye protection"
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

            MaterialSymbol {
                visible: pages.currentIndex === 1
                text: "present_to_all"
                iconSize: 18
                color: AbyssStyle.accent
            }
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
            id: displayContent
            property bool showDisplayTargets: false
            readonly property bool hasMultipleExternals: DisplayMode.connectedOutputs.length > 2

            function activateMode(mode): void {
                if (mode === "primary-only") {
                    DisplayMode.apply("primary-only")
                } else if (mode === "mirror") {
                    if (DisplayMode.currentMode === "mirror") DisplayMode.stopMirror(true)
                    else DisplayMode.apply("mirror")
                } else if (mode === "extend") {
                    DisplayMode.apply("extend")
                } else if (mode === "second-only") {
                    DisplayMode.apply("second-only")
                }
            }

            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: displayColumn.implicitHeight + 8
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                ColumnLayout {
                    id: displayColumn
                    width: parent.width
                    spacing: 12

                    AbyssLabel {
                        Layout.fillWidth: true
                        text: "DISPLAY MODE"
                        color: root.utilityMutedInk
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 8
                        rowSpacing: 8

                        Repeater {
                            model: [
                                { key: "primary-only", title: "PC screen only", glyph: "monitor" },
                                { key: "mirror", title: "Duplicate", glyph: "filter_none" },
                                { key: "extend", title: "Extend", glyph: "view_week" },
                                { key: "second-only", title: "Second screen only", glyph: "tv" }
                            ]

                            delegate: Rectangle {
                                id: modeTile
                                required property var modelData
                                readonly property bool selected: DisplayMode.currentMode === modelData.key
                                readonly property bool canApply: CompositorService.isNiri
                                    && !DisplayMode.applying
                                    && (modelData.key === "primary-only"
                                        || (modelData.key === "extend"
                                            && DisplayMode.connectedOutputs.length > 1)
                                        || (modelData.key === "mirror"
                                            && DisplayMode.connectedOutputs.length > 1
                                            && DisplayMode.mirrorAvailable
                                            && DisplayMode.mirrorSource.length > 0
                                            && DisplayMode.mirrorTarget.length > 0)
                                        || (modelData.key === "second-only"
                                            && DisplayMode.selectedSecondary.length > 0))
                                Layout.fillWidth: true
                                Layout.preferredHeight: 52
                                radius: 12
                                opacity: canApply ? 1 : 0.48
                                color: selected ? Qt.alpha(AbyssStyle.accent, .13)
                                    : modeMouse.containsMouse && canApply
                                        ? Qt.alpha(AbyssStyle.accent, .08)
                                        : Qt.alpha(AbyssStyle.accent, .025)
                                border.width: 1
                                border.color: selected ? Qt.alpha(AbyssStyle.accent, .42)
                                    : Qt.alpha(AbyssStyle.accent, .12)

                                Behavior on color {
                                    enabled: AbyssStyle.motionEnabled
                                    ColorAnimation { duration: AbyssStyle.motionFast }
                                }

                                RowLayout {
                                    anchors {
                                        fill: parent
                                        leftMargin: 13
                                        rightMargin: 13
                                    }
                                    spacing: 9

                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: modeTile.modelData.glyph
                                        iconSize: 20
                                        color: modeTile.selected ? AbyssStyle.accent : root.utilityMutedInk
                                    }
                                    AbyssLabel {
                                        Layout.fillWidth: true
                                        text: modeTile.modelData.title
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: modeTile.selected ? Font.DemiBold : Font.Normal
                                        color: modeTile.selected ? root.utilityInk : root.utilityMutedInk
                                        elide: Text.ElideRight
                                        wrapMode: Text.NoWrap
                                    }
                                    MaterialSymbol {
                                        visible: modeTile.selected
                                        Layout.alignment: Qt.AlignVCenter
                                        text: "check"
                                        iconSize: 18
                                        color: AbyssStyle.accent
                                    }
                                }

                                Accessible.role: Accessible.Button
                                Accessible.name: modeTile.modelData.title
                                Accessible.description: modeTile.selected ? "Selected display mode" : ""
                                MouseArea {
                                    id: modeMouse
                                    anchors.fill: parent
                                    enabled: modeTile.canApply
                                    hoverEnabled: true
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: displayContent.activateMode(modeTile.modelData.key)
                                }
                            }
                        }
                    }

                    // Two connected outputs need no extra fields: the primary
                    // panel is the duplicate source and the external is its
                    // target. Keep manual connector selection for 3+ displays.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: displayContent.hasMultipleExternals
                        spacing: 6

                        AbyssLabel {
                            Layout.fillWidth: true
                            text: "Select source and target displays"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: root.utilityMutedInk
                        }
                        AbyssButton {
                            glyph: displayContent.showDisplayTargets ? "expand_less" : "tune"
                            text: displayContent.showDisplayTargets ? "Hide" : "Choose"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            onClicked: displayContent.showDisplayTargets =
                                !displayContent.showDisplayTargets
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: displayContent.hasMultipleExternals
                            && displayContent.showDisplayTargets

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            AbyssLabel {
                                text: "Second screen"
                                color: root.utilityMutedInk
                                font.pixelSize: Appearance.font.pixelSize.smallest
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
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            AbyssLabel {
                                text: "Duplicate"
                                color: root.utilityMutedInk
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }
                            StyledComboBox {
                                Layout.fillWidth: true
                                enableSettingsSearch: false
                                model: DisplayMode.connectedOutputs.map(output => DisplayMode.outputLabel(output))
                                currentIndex: Math.max(0, DisplayMode.connectedOutputs.indexOf(DisplayMode.mirrorSource))
                                enabled: DisplayMode.connectedOutputs.length > 1 && !DisplayMode.applying
                                onActivated: DisplayMode.setMirrorSource(DisplayMode.connectedOutputs[currentIndex])
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

                    AbyssLabel {
                        Layout.fillWidth: true
                        visible: DisplayMode.lastError.length > 0
                            || (DisplayMode.currentMode === "mirror" && DisplayMode.statusMessage.length > 0)
                            || (DisplayMode.applying && DisplayMode.statusMessage.length > 0)
                        text: DisplayMode.lastError.length > 0
                            ? DisplayMode.lastError : DisplayMode.statusMessage
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: DisplayMode.lastError.length > 0
                            ? Appearance.colors.colError : root.utilityMutedInk
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Qt.alpha(root.utilityInk, .10)
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        AbyssLabel {
                            Layout.fillWidth: true
                            text: "WIRELESS DISPLAY"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: root.utilityMutedInk
                        }
                        AbyssButton {
                            glyph: NetworkDisplays.scanning ? "hourglass_top" : "sync"
                            text: NetworkDisplays.scanning ? "Scanning…" : "Scan"
                            outlined: false
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            enabled: !NetworkDisplays.scanning
                            onClicked: NetworkDisplays.scan()
                        }
                    }

                    Rectangle {
                        id: receiverList
                        Layout.fillWidth: true
                        implicitHeight: receiverColumn.implicitHeight + 2
                        radius: 13
                        color: Qt.alpha(AbyssStyle.accent, .025)
                        border.width: 1
                        border.color: Qt.alpha(AbyssStyle.accent, .10)

                        ColumnLayout {
                            id: receiverColumn
                            width: parent.width
                            spacing: 0

                            Repeater {
                                model: NetworkDisplays.displays
                                delegate: Item {
                                    id: receiverRow
                                    required property var modelData
                                    required property int index
                                    readonly property string receiverId: String(modelData.uuid ?? "")
                                    readonly property bool currentSession: NetworkDisplays.activeUuid === receiverId
                                        && NetworkDisplays.phase !== "idle"
                                    readonly property bool canChoose: currentSession
                                        || (!NetworkDisplays.active && !NetworkDisplays.busy
                                            && !NetworkDisplays.scanning && NetworkDisplays.streamReady)
                                    readonly property string receiverState: currentSession
                                        ? NetworkDisplays.phase === "service-active"
                                            ? "Streaming service active"
                                            : NetworkDisplays.phase === "disconnecting"
                                                ? "Disconnecting…" : "Connecting…"
                                        : modelData.state === "error" ? "Error"
                                            : modelData.state === "streaming" ? "In use"
                                            : "Available"
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 61
                                    opacity: canChoose ? 1 : 0.65

                                    Rectangle {
                                        visible: receiverRow.index > 0
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        height: 1
                                        color: Qt.alpha(root.utilityInk, .08)
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        color: receiverMouse.containsMouse && receiverRow.canChoose
                                            ? Qt.alpha(AbyssStyle.accent, .09) : "transparent"
                                        radius: 10
                                    }

                                    RowLayout {
                                        anchors {
                                            fill: parent
                                            leftMargin: 13
                                            rightMargin: 13
                                        }
                                        spacing: 12

                                        MaterialSymbol {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: receiverRow.modelData.protocolId === 3 ? "cast"
                                                : "tv"
                                            iconSize: 21
                                            color: receiverRow.currentSession
                                                ? AbyssStyle.accent : root.utilityMutedInk
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            AbyssLabel {
                                                Layout.fillWidth: true
                                                text: receiverRow.modelData.name
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                color: root.utilityInk
                                                elide: Text.ElideRight
                                                wrapMode: Text.NoWrap
                                            }
                                            AbyssLabel {
                                                Layout.fillWidth: true
                                                text: receiverRow.modelData.protocol
                                                    + " · " + receiverRow.receiverState
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: root.utilityMutedInk
                                                elide: Text.ElideRight
                                                wrapMode: Text.NoWrap
                                            }
                                        }
                                        MaterialSymbol {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: receiverRow.currentSession ? "stop_circle" : "chevron_right"
                                            iconSize: 19
                                            color: receiverRow.currentSession
                                                ? AbyssStyle.accent : root.utilityMutedInk
                                        }
                                    }

                                    Accessible.role: Accessible.Button
                                    Accessible.name: receiverRow.modelData.name
                                    Accessible.description: receiverRow.modelData.protocol
                                        + " " + receiverRow.receiverState
                                    MouseArea {
                                        id: receiverMouse
                                        anchors.fill: parent
                                        enabled: receiverRow.canChoose
                                        hoverEnabled: true
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            if (receiverRow.currentSession) {
                                                NetworkDisplays.disconnect()
                                            } else {
                                                NetworkDisplays.select(receiverRow.receiverId)
                                                NetworkDisplays.connectToSelected()
                                            }
                                        }
                                    }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 60
                                visible: NetworkDisplays.displays.length === 0
                                RowLayout {
                                    anchors {
                                        fill: parent
                                        leftMargin: 13
                                        rightMargin: 13
                                    }
                                    spacing: 10
                                    MaterialSymbol {
                                        text: NetworkDisplays.scanning ? "sync" : "cast"
                                        iconSize: 21
                                        color: root.utilityMutedInk
                                    }
                                    AbyssLabel {
                                        Layout.fillWidth: true
                                        text: NetworkDisplays.scanning
                                            ? "Searching for nearby TVs…"
                                            : "No wireless displays found. Select Scan to search."
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: root.utilityMutedInk
                                    }
                                }
                            }
                        }
                    }

                    AbyssLabel {
                        Layout.fillWidth: true
                        visible: NetworkDisplays.lastError.length > 0
                            || (NetworkDisplays.active && NetworkDisplays.statusMessage.length > 0)
                            || (!NetworkDisplays.streamReady && NetworkDisplays.backendAvailable
                                && NetworkDisplays.displays.length > 0)
                        text: NetworkDisplays.lastError.length > 0
                            ? NetworkDisplays.lastError : NetworkDisplays.statusMessage
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: NetworkDisplays.lastError.length > 0
                            ? Appearance.colors.colError : root.utilityMutedInk
                    }

                    AbyssButton {
                        Layout.alignment: Qt.AlignLeft
                        visible: root.wirelessToolAvailable
                            && !NetworkDisplays.backendAvailable
                            && NetworkDisplays.lastError.length > 0
                        glyph: "open_in_new"
                        text: "Open Network Displays"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        onClicked: Quickshell.execDetached(["gnome-network-displays"])
                    }
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
                    enabled: Audio.outputDevices.length > 0 && !ProjectAudio.busy
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
