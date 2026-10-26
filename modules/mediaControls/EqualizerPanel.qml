pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services.deferred

Item {
    id: root

    property bool active: false
    property bool compactLayout: false
    property bool _registered: false
    property int _editingBand: -1
    // Keep the integrated CAVA + DSP graph, but restore the original
    // electric-current connector language on top of it.
    property real eqLightningHighlight: 0.0
    // The resting sentinel is outside the visible preset sweep.
    property real eqPresetSweepProgress: -0.12

    readonly property color eqAccentColor: Appearance.colors.colPrimary
    readonly property bool showTransportStatus: EqualizerService.busy
        || !EqualizerService.dspControlAvailable
    readonly property int presetStripHeight:
        root.compactLayout ? 20 : 22
    implicitHeight: root.compactLayout
        ? (root.showTransportStatus ? 184 : 154)
        : (root.showTransportStatus ? 210 : 180)
    clip: root.compactLayout

    function syncRegistration(): void {
        if (root.active && !root._registered) {
            EqualizerService.registerConsumer()
            root._registered = true
        } else if (!root.active && root._registered) {
            EqualizerService.unregisterConsumer()
            root._registered = false
        }
    }

    function statusText(): string {
        if (EqualizerService.busy)
            return "Applying…"
        if (EqualizerService.dspControlAvailable)
            return EqualizerService.dspPresetName || "Custom"
        switch (EqualizerService.error) {
        case "backend-not-running":
            return "EasyEffects stopped"
        case "backend-unavailable":
            return "EasyEffects unavailable"
        case "transport-unavailable":
        case "transport-probe-failed":
            return "EQ transport unavailable"
        case "dsp-unavailable":
            return "10-band DSP unavailable"
        case "dsp-state-read-failed":
        case "malformed-dsp-state":
            return "DSP state unavailable"
        case "dsp-apply-failed":
            return "Apply failed"
        default:
            return EqualizerService.error.length > 0
                ? EqualizerService.error : "Loading…"
        }
    }

    function gainToY(gain, height): real {
        const clamped = Math.max(
            EqualizerService.dspMinimumBandGain,
            Math.min(EqualizerService.dspMaximumBandGain,
                     Number(gain) || 0))
        const range = EqualizerService.dspMaximumBandGain
            - EqualizerService.dspMinimumBandGain
        if (range <= 0)
            return height / 2

        // Match the real Slider handle-center travel, so dB guide lines,
        // fallback curve points and draggable nodes share exactly one y scale.
        const inset = root.compactLayout ? 11.5 : 13.5
        const usableHeight = Math.max(1, height - inset * 2)
        return inset
            + (EqualizerService.dspMaximumBandGain - clamped)
                / range * usableHeight
    }

    function requestGraphPaint(): void {
        analyzerCanvas.requestPaint()
    }

    function triggerEqLightning(): void {
        eqLightningAnim.restart()
    }

    function triggerPresetSweep(): void {
        presetSweepAnim.restart()
    }

    function beginBandLightning(index, gain): void {
        eqLightningAnim.stop()
        root._editingBand = index
        root.eqLightningHighlight = 1.0
        analyzerCanvas.requestPaint()
    }

    function previewBandLightning(index, gain): void {
        root.eqLightningHighlight = 1.0
        analyzerCanvas.requestPaint()
    }

    function endBandLightning(index, gain): void {
        root._editingBand = -1
        root.triggerEqLightning()
        analyzerCanvas.requestPaint()
    }

    function applyPreset(name): void {
        if (EqualizerService.applyDspPreset(name)) {
            root.triggerPresetSweep()
            analyzerCanvas.requestPaint()
        }
    }

    onEqLightningHighlightChanged: analyzerCanvas.requestPaint()
    onEqPresetSweepProgressChanged: analyzerCanvas.requestPaint()

    SequentialAnimation {
        id: presetSweepAnim
        running: false

        ScriptAction {
            script: root.eqPresetSweepProgress = -0.12
        }

        NumberAnimation {
            target: root
            property: "eqPresetSweepProgress"
            from: -0.12
            to: 1.16
            duration: Appearance.animationsEnabled ? 860 : 1
            easing.type: Easing.InOutCubic
        }

        ScriptAction {
            script: root.eqPresetSweepProgress = -0.12
        }
    }

    SequentialAnimation {
        id: eqLightningAnim
        running: false

        ScriptAction {
            script: root.eqLightningHighlight = 1.0
        }

        PauseAnimation {
            duration: 120
        }

        NumberAnimation {
            target: root
            property: "eqLightningHighlight"
            from: 1.0
            to: 0.0
            duration: Appearance.animationsEnabled ? 720 : 1
            easing.type: Easing.OutCubic
        }
    }

    onActiveChanged: {
        root.syncRegistration()
        if (active)
            analyzerCanvas.requestPaint()
    }

    Connections {
        target: EqualizerService

        function onDspBandsChanged(): void {
            analyzerCanvas.requestPaint()
        }
    }

    Component.onCompleted: {
        root.syncRegistration()
        analyzerCanvas.requestPaint()
    }

    Component.onDestruction: {
        if (root._registered)
            EqualizerService.unregisterConsumer()
    }

    // The DSP surface is also a CAVA consumer. CavaProcess is only a lightweight
    // subscription wrapper; CavaService still owns the single shared process.
    // This lets every EqualizerPanel render the same real audio spectrum without
    // creating a second analyzer subprocess.
    CavaProcess {
        id: eqCava
        active: root.active
        sampleCount: 64
    }

    Connections {
        target: eqCava

        function onPointsChanged(): void {
            analyzerCanvas.requestPaint()
        }

        function onNormalizationCeilingChanged(): void {
            analyzerCanvas.requestPaint()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: root.compactLayout ? 6 : 8

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Appearance.colors.colLayer2
            opacity: 0.45
        }

        RowLayout {
            visible: root.showTransportStatus
            Layout.fillWidth: true
            Layout.leftMargin: root.compactLayout ? 6 : 8
            Layout.rightMargin: root.compactLayout ? 6 : 8
            spacing: root.compactLayout ? 6 : 8

            Item {
                Layout.fillWidth: true
            }

            RippleButton {
                visible: EqualizerService.error === "backend-not-running"
                implicitWidth: 52
                implicitHeight: 24
                buttonText: "Start"
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer1Hover
                onClicked: EqualizerService.startBackend()
            }

            Rectangle {
                implicitWidth: Math.max(48, statusLabel.implicitWidth + 14)
                implicitHeight: 24
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colLayer2

                StyledText {
                    id: statusLabel
                    anchors.centerIn: parent
                    text: root.statusText()
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    color: EqualizerService.dspControlAvailable
                        ? Appearance.colors.colSubtext
                        : Appearance.colors.colError
                }
            }
        }

        Rectangle {
            id: graphFrame
            Layout.fillWidth: true
            Layout.preferredHeight: root.compactLayout ? 112 : 132
            Layout.leftMargin: root.compactLayout ? 3 : 4
            Layout.rightMargin: root.compactLayout ? 3 : 4
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colLayer2
            clip: true

            readonly property real leftGutter:
                root.compactLayout ? 40 : 44
            readonly property real rightGutter: 5
            readonly property real topGutter: 6
            readonly property real bottomGutter:
                root.compactLayout ? 17 : 19

            Item {
                id: plotArea
                x: graphFrame.leftGutter
                y: graphFrame.topGutter
                width: Math.max(1, graphFrame.width
                    - graphFrame.leftGutter - graphFrame.rightGutter)
                height: Math.max(1, graphFrame.height
                    - graphFrame.topGutter - graphFrame.bottomGutter)

                Canvas {
                    id: analyzerCanvas
                    anchors.fill: parent
                    z: 0

                    Timer {
                        interval: 33
                        running: root.active && analyzerCanvas.visible
                        repeat: true
                        onTriggered: analyzerCanvas.requestPaint()
                    }

                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onVisibleChanged: if (visible) requestPaint()

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        if (width <= 0 || height <= 0)
                            return

                        const bands = EqualizerService.dspBands ?? []

                        function yForGain(gain) {
                            return root.gainToY(gain, height)
                        }

                        // Real CAVA spectrum. Two restrained passes give each
                        // bar enough presence behind the response curve without
                        // turning the DSP control into a second visualizer card.
                        const spectrum = eqCava.points ?? []
                        const ceiling = Math.max(
                            1, Number(eqCava.normalizationCeiling) || 1)
                        if (spectrum.length > 0) {
                            const slot = width / spectrum.length
                            const haloWidth = Math.max(1, slot * 0.82)
                            const coreWidth = Math.max(1, slot * 0.52)

                            ctx.fillStyle = root.eqAccentColor
                            for (let i = 0; i < spectrum.length; ++i) {
                                const amplitude = Math.max(0, Math.min(1,
                                    (Number(spectrum[i]) || 0) / ceiling))
                                const barHeight = Math.max(
                                    1, amplitude * height * 0.94)
                                const center = (i + 0.5) * slot

                                ctx.globalAlpha = 0.07 + amplitude * 0.10
                                ctx.fillRect(center - haloWidth / 2,
                                    height - barHeight, haloWidth, barHeight)

                                ctx.globalAlpha = 0.18 + amplitude * 0.28
                                ctx.fillRect(center - coreWidth / 2,
                                    height - barHeight, coreWidth, barHeight)
                            }
                        }

                        // Shared dB/frequency grid.
                        ctx.strokeStyle = Appearance.colors.colLayer2
                        ctx.lineWidth = 1
                        ctx.globalAlpha = 0.48
                        const gridGains = [12, 6, 0, -6, -12]
                        for (let i = 0; i < gridGains.length; ++i) {
                            const y = yForGain(gridGains[i])
                            ctx.beginPath()
                            ctx.moveTo(0, y)
                            ctx.lineTo(width, y)
                            ctx.stroke()
                        }
                        for (let i = 0; i < 10; ++i) {
                            const x = (i + 0.5) * width / 10
                            ctx.beginPath()
                            ctx.moveTo(x, 0)
                            ctx.lineTo(x, height)
                            ctx.stroke()
                        }

                        // Read the actual rendered EQ handles so the response
                        // curve and the draggable nodes can never drift apart.
                        const points = []
                        for (let i = 0; i < 10; ++i) {
                            const delegate = bandRepeater.itemAt(i)
                            if (delegate) {
                                const mapped = delegate.curvePoint()
                                points.push({ x: mapped.x, y: mapped.y })
                            } else {
                                const gain = Number(bands[i]?.gain) || 0
                                points.push({
                                    x: (i + 0.5) * width / 10,
                                    y: yForGain(gain)
                                })
                            }
                        }

                        const highlight = Math.max(
                            0, Math.min(1, root.eqLightningHighlight))
                        const sweep = root.eqPresetSweepProgress
                        const now = Date.now() / 1000

                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"

                        const sweepActive =
                            sweep > -0.12 && sweep <= 1.16

                        function strokeSampledTrace(stroke, capture) {
                            const samples = capture ? [] : null
                            const firstX = points[0].x
                            const firstY = points[0].y
                            ctx.beginPath()
                            ctx.moveTo(firstX, firstY)
                            if (capture)
                                samples.push({ x: firstX, y: firstY })

                            for (let i = 0; i < points.length - 1; ++i) {
                                const p1 = points[i]
                                const p2 = points[i + 1]
                                const steps = stroke === 2 ? 6 : 8
                                for (let j = 1; j <= steps; ++j) {
                                    const t = j / steps
                                    const envelope = Math.sin(t * Math.PI)
                                    const x = p1.x + (p2.x - p1.x) * t
                                    const y = p1.y + (p2.y - p1.y) * t
                                    const amplitudeX = stroke === 0 ? 2.2
                                        : (stroke === 1 ? 1.2 : 0.55)
                                    const amplitudeY = stroke === 0 ? 2.8
                                        : (stroke === 1 ? 1.55 : 0.7)
                                    const noiseX = Math.sin(
                                        now * (6.5 + stroke) + i + j)
                                        * Math.cos(now * 5.2 - i + j)
                                        * amplitudeX * envelope
                                    const noiseY = Math.cos(
                                        now * (6.1 - stroke * 0.4) + i - j)
                                        * Math.sin(now * 4.8 + i - j)
                                        * amplitudeY * envelope
                                    const sampleX = x + noiseX
                                    const sampleY = y + noiseY
                                    ctx.lineTo(sampleX, sampleY)
                                    if (capture)
                                        samples.push({ x: sampleX, y: sampleY })
                                }
                            }
                            ctx.stroke()
                            return samples
                        }

                        // Three compact strokes recreate the original Alis
                        // electric-wire connector while staying inside this
                        // single CAVA + DSP graph. The normal 33 ms paint path
                        // draws directly; sample arrays exist only during the
                        // short preset sweep that needs to replay segments.
                        const traces = sweepActive ? [] : null
                        for (let stroke = 0; stroke < 3; ++stroke) {
                            if (stroke === 0) {
                                ctx.lineWidth = 5.5
                                ctx.strokeStyle = root.eqAccentColor
                                ctx.globalAlpha = 0.16 + highlight * 0.14
                            } else if (stroke === 1) {
                                ctx.lineWidth = 2.4
                                ctx.strokeStyle = Qt.lighter(
                                    root.eqAccentColor,
                                    1.12 + highlight * 0.28)
                                ctx.globalAlpha = 0.40 + highlight * 0.34
                            } else {
                                ctx.lineWidth = 1.0
                                ctx.strokeStyle = "#ffffff"
                                ctx.globalAlpha = 0.55 + highlight * 0.45
                            }

                            const samples =
                                strokeSampledTrace(stroke, sweepActive)
                            if (sweepActive)
                                traces.push(samples)
                        }

                        // Preset changes send the old left-to-right charge
                        // sweep through the exact same wire geometry.
                        if (sweepActive) {
                            const sweepTail = 0.22
                            const sweepLead = 0.035

                            for (let stroke = 0;
                                    stroke < traces.length; ++stroke) {
                                const samples = traces[stroke]
                                ctx.lineWidth = stroke === 0 ? 5.5
                                    : (stroke === 1 ? 2.4 : 1.0)
                                ctx.strokeStyle = stroke === 2
                                    ? "#ffffff"
                                    : Qt.lighter(root.eqAccentColor,
                                        stroke === 0 ? 1.28 : 1.55)

                                for (let i = 1;
                                        i < samples.length; ++i) {
                                    const p1 = samples[i - 1]
                                    const p2 = samples[i]
                                    const segmentPosition =
                                        ((p1.x + p2.x) * 0.5)
                                            / Math.max(1, width)
                                    const distance =
                                        sweep - segmentPosition
                                    let pulse = 0

                                    if (distance >= -sweepLead
                                            && distance <= sweepTail) {
                                        if (distance < 0) {
                                            pulse = 1
                                                - (-distance / sweepLead)
                                        } else {
                                            pulse = Math.pow(
                                                1 - distance / sweepTail,
                                                1.6)
                                        }
                                    }

                                    if (pulse <= 0)
                                        continue

                                    ctx.beginPath()
                                    ctx.moveTo(p1.x, p1.y)
                                    ctx.lineTo(p2.x, p2.y)
                                    ctx.globalAlpha = pulse
                                        * (stroke === 0 ? 0.38
                                            : (stroke === 1
                                                ? 0.78 : 0.95))
                                    ctx.stroke()
                                }
                            }
                        }

                        ctx.globalAlpha = 1.0
                    }
                }

                Row {
                    id: bandControlRow
                    anchors.fill: parent
                    spacing: 0
                    z: 2

                    Repeater {
                        id: bandRepeater
                        model: EqualizerService.dspBands

                        delegate: Item {
                            id: bandDelegate
                            required property var modelData
                            required property int index
                            width: parent.width / 10
                            height: parent.height
                            readonly property real backendGain:
                                Number(modelData?.gain) || 0

                            function curvePoint() {
                                const handleItem = bandSlider.handle
                                if (!handleItem) {
                                    return Qt.point(
                                        bandDelegate.width / 2
                                            + bandDelegate.x,
                                        bandDelegate.height / 2)
                                }
                                return handleItem.mapToItem(
                                    analyzerCanvas,
                                    handleItem.width / 2,
                                    handleItem.height / 2)
                            }

                            Rectangle {
                                id: responseStem
                                z: 1
                                width: 1
                                radius: 0.5
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: bandSlider.handle
                                    ? bandSlider.handle.y
                                        + bandSlider.handle.height / 2
                                    : parent.height / 2
                                height: Math.max(0, parent.height - y)
                                color: Appearance.colors.colPrimary
                                opacity: bandSlider.enabled ? 0.24 : 0.10
                            }

                            Slider {
                                id: bandSlider
                                property bool userMoved: false
                                z: 2
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    horizontalCenter: parent.horizontalCenter
                                }
                                width: root.compactLayout ? 20 : 24
                                orientation: Qt.Vertical
                                from: EqualizerService.dspMinimumBandGain
                                to: EqualizerService.dspMaximumBandGain
                                stepSize: 1
                                snapMode: Slider.SnapAlways
                                hoverEnabled: true
                                enabled: EqualizerService.dspControlAvailable
                                    && !EqualizerService.busy
                                topPadding: root.compactLayout ? 6 : 7
                                bottomPadding: topPadding
                                leftPadding: 0
                                rightPadding: 0
                                value: bandDelegate.backendGain

                                onPressedChanged: {
                                    if (pressed) {
                                        userMoved = false
                                        root.beginBandLightning(
                                            bandDelegate.index, value)
                                    } else if (userMoved && enabled) {
                                        userMoved = false
                                        const rounded = Math.round(value)
                                        EqualizerService.setDspBandGain(
                                            bandDelegate.index, rounded)
                                        root.endBandLightning(
                                            bandDelegate.index, rounded)
                                    }
                                }

                                onMoved: {
                                    value = Math.round(value)
                                    userMoved = pressed
                                    // Keyboard/wheel changes emit moved without
                                    // a pointer press. Backend/model/visibility
                                    // updates never emit this user-only signal.
                                    if (!pressed)
                                        EqualizerService.setDspBandGain(
                                            bandDelegate.index, value)
                                    root.previewBandLightning(
                                        bandDelegate.index, value)
                                }

                                Connections {
                                    target: EqualizerService
                                    function onDspBandsChanged(): void {
                                        if (!bandSlider.pressed)
                                            bandSlider.value =
                                                bandDelegate.backendGain
                                        analyzerCanvas.requestPaint()
                                    }
                                }

                                background: Item {}

                                handle: Rectangle {
                                    x: bandSlider.leftPadding
                                        + (bandSlider.availableWidth - width) / 2
                                    y: bandSlider.topPadding
                                        + bandSlider.visualPosition
                                            * (bandSlider.availableHeight - height)
                                    implicitWidth:
                                        root.compactLayout ? 11 : 13
                                    implicitHeight: implicitWidth
                                    radius: width / 2
                                    color: bandSlider.pressed
                                        ? Appearance.colors.colPrimary
                                        : Appearance.colors.colLayer0
                                    border.width: 1
                                    border.color: Appearance.colors.colPrimary
                                    scale: bandSlider.pressed ? 1.16
                                        : (bandSlider.hovered ? 1.08 : 1.0)

                                    HoverHandler {
                                        cursorShape: bandSlider.enabled
                                            ? (bandSlider.pressed
                                                ? Qt.ClosedHandCursor
                                                : Qt.SizeVerCursor)
                                            : Qt.ArrowCursor
                                    }

                                    Behavior on scale {
                                        enabled: Appearance.animationsEnabled
                                        NumberAnimation {
                                            duration:
                                                Appearance.animation
                                                    .elementMoveFast.duration
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Repeater {
                model: [12, 6, 0, -6, -12]

                delegate: StyledText {
                    required property real modelData
                    x: 2
                    width: graphFrame.leftGutter - 8
                    y: plotArea.y
                        + root.gainToY(modelData, plotArea.height)
                        - height / 2
                    text: modelData === 0 ? "0 dB"
                        : modelData > 0 ? "+" + modelData : String(modelData)
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    opacity: 0.78
                }
            }

            Row {
                x: plotArea.x
                y: plotArea.y + plotArea.height
                width: plotArea.width
                height: graphFrame.bottomGutter
                spacing: 0

                Repeater {
                    model: EqualizerService.dspBands

                    delegate: Item {
                        required property var modelData
                        width: parent.width / 10
                        height: parent.height

                        StyledText {
                            anchors.centerIn: parent
                            text: modelData?.label ?? ""
                            font.pixelSize:
                                Appearance.font.pixelSize.smallest
                            font.weight: Font.Medium
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            Rectangle {
                anchors {
                    top: parent.top
                    right: parent.right
                    topMargin: 6
                    rightMargin: 6
                }
                implicitWidth: root.compactLayout ? 42 : 46
                implicitHeight: 20
                radius: height / 2
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer2
                z: 5

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    Rectangle {
                        Layout.preferredWidth: 6
                        Layout.preferredHeight: 6
                        Layout.alignment: Qt.AlignVCenter
                        radius: 3
                        color: Appearance.colors.colPrimary
                        opacity: eqCava.audioSignalActive ? 1.0 : 0.35
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: "Live"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Medium
                        verticalAlignment: Text.AlignVCenter
                        color: Appearance.colors.colPrimary
                        opacity: eqCava.audioSignalActive ? 1.0 : 0.58
                    }
                }
            }
        }

        // Presets read as a compact mode strip, not a second button grid.
        // Inactive choices stay visually quiet; only the active curve becomes
        // a filled capsule. Eight equal slots fit the media popup in one row.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: root.compactLayout ? 3 : 5
            Layout.rightMargin: root.compactLayout ? 3 : 5
            Layout.topMargin: 1
            spacing: root.compactLayout ? 2 : 3

            Repeater {
                model: ["Flat", "Bass", "Treble", "Vocal",
                        "Pop", "Rock", "Jazz", "Classic"]

                delegate: RippleButton {
                    id: presetButton
                    required property string modelData
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredHeight: root.presetStripHeight
                    implicitHeight: root.presetStripHeight
                    horizontalPadding: 1
                    buttonText: modelData
                    buttonRadius: height / 2
                    enabled: EqualizerService.dspControlAvailable
                        && !EqualizerService.busy
                    toggled: EqualizerService.dspPresetName === modelData
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colBackgroundToggled:
                        Appearance.colors.colPrimaryContainer
                    colBackgroundToggledHover:
                        Appearance.colors.colPrimaryContainerHover
                    onClicked: root.applyPreset(modelData)

                    contentItem: StyledText {
                        anchors.fill: parent
                        text: presetButton.modelData
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: presetButton.toggled
                            ? Font.DemiBold : Font.Medium
                        color: presetButton.toggled
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
