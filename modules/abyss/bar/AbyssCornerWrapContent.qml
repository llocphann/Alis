pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.bar as Shared
import qs.modules.bar.weather
import qs.modules.mediaControls
import qs.modules.abyss.looks
import qs.modules.abyss.content

// Native curved corner-wrap presentation for Screen Edge modules.
// Arranges each module's live interactive elements along a smooth 90-degree
// rounded corner spine (horizontal arm -> circular arc -> vertical arm).
Item {
    id: root
    required property string kind
    required property string outputName
    property bool editing: GlobalStates.abyssEditing
        && (GlobalStates.abyssEditorTargetOutput === "" || GlobalStates.abyssEditorTargetOutput === root.outputName)
    property string wrapCorner: "topLeft"
    property real wrapThickness: 32 * Appearance.fontSizeScale
    property real wrapArcRadius: 22
    property real contentScale: 1
    // Inherits rotation from parent Loader -> AbyssBarModule without coupling files.
    property int moduleRotation: Number(parent?.parent?.moduleRotation ?? -1)
    readonly property bool contentAvailable: kindLoader.item
        ? (kindLoader.item.contentAvailable ?? true)
        : (root.editing || (root.kind !== "timer" && root.kind !== "shellUpdate"))
    signal request(string kind)
    signal hoverRequest(string kind)
    signal hoverState(string kind, bool hovered)

    readonly property bool mirrorX: wrapCorner === "topRight" || wrapCorner === "bottomRight"
    readonly property bool mirrorY: wrapCorner === "bottomLeft" || wrapCorner === "bottomRight"
    readonly property real halfT: root.kind === "cava"
        ? Math.max(4, Math.max(10, Math.min(30, Number(Config.options?.bar?.cava?.height ?? 22))) * root.contentScale * 0.5 + 1.5)
        : Math.max(4, wrapThickness * 0.5)
    readonly property real safeRadius: Math.max(6, Math.min(wrapArcRadius, Math.min(width, height) - halfT - 6))
    readonly property real endPad: Math.max(4, halfT * 0.55)
    readonly property real segH: Math.max(0, (width - endPad) - (halfT + safeRadius))
    readonly property real segArc: Math.PI * 0.5 * safeRadius
    readonly property real segV: Math.max(0, (height - endPad) - (halfT + safeRadius))
    readonly property real totalPathLength: Math.max(1, segH + segArc + segV)

    // Parametric position, inward unit normal, and tangent angle along the
    // corner spine for t in [0, 1] (0 = horizontal arm tip, 0.5 ~= corner apex, 1 = vertical arm tip).
    function pointAt(t: real): var {
        const clamped = Math.max(0, Math.min(1, Number(t) || 0))
        const s = clamped * totalPathLength
        let lx = halfT
        let ly = halfT
        let nx = 0
        let ny = 1
        if (s <= segH) {
            lx = (width - endPad) - s
            ly = halfT
            nx = 0
            ny = 1
        } else if (s <= segH + segArc && safeRadius > 0.01) {
            const a = Math.max(0, Math.min(Math.PI * 0.5, (s - segH) / safeRadius))
            lx = halfT + safeRadius - safeRadius * Math.sin(a)
            ly = halfT + safeRadius - safeRadius * Math.cos(a)
            nx = Math.sin(a)
            ny = Math.cos(a)
        } else {
            const s2 = Math.max(0, s - segH - segArc)
            lx = halfT
            ly = halfT + safeRadius + s2
            nx = 1
            ny = 0
        }
        const x = mirrorX ? (width - lx) : lx
        const y = mirrorY ? (height - ly) : ly
        const inX = mirrorX ? -nx : nx
        const inY = mirrorY ? -ny : ny
        const radialDeg = Math.atan2(inY, inX) * 180 / Math.PI - 90
        return { x: x, y: y, nx: inX, ny: inY, angle: radialDeg }
    }

    readonly property var cornerPoint: pointAt((segH + segArc * 0.5) / totalPathLength)
    // Distinct names (never shadow QQuickItem's FINAL horizontalCenter/verticalCenter).
    // Start straight arm content cleanly past the corner arc so arm labels never collide with corner apex icons.
    readonly property var hArmCenter: {
        const armStart = Math.min(width - endPad - 16, halfT + safeRadius + 2)
        const start = Math.max(halfT + 14, armStart)
        const span = Math.max(16, (width - endPad * 0.5) - start)
        const lx = start + span * 0.5
        return { x: mirrorX ? (width - lx) : lx, y: mirrorY ? (height - halfT) : halfT, span: span }
    }
    readonly property var vArmCenter: {
        const armStart = Math.min(height - endPad - 16, halfT + safeRadius + 2)
        const start = Math.max(halfT + 14, armStart)
        const span = Math.max(16, (height - endPad * 0.5) - start)
        const ly = start + span * 0.5
        return { x: mirrorX ? (width - halfT) : halfT, y: mirrorY ? (height - ly) : ly, span: span }
    }

    // L-shaped hit-testing helper so the empty inner desktop quadrant never
    // steals hover or clicks when another AbyssPerimeter popup overlaps it.
    function containsArmPoint(px: real, py: real): bool {
        if (width <= 0 || height <= 0 || px < 0 || py < 0 || px > width || py > height)
            return false
        const strip = Math.max(24, wrapThickness) + 3
        const inHorizontalArm = mirrorY ? (py >= height - strip) : (py <= strip)
        const inVerticalArm = mirrorX ? (px >= width - strip) : (px <= strip)
        return inHorizontalArm || inVerticalArm
    }

    QtObject {
        id: armContainmentMask
        function contains(point: point): bool {
            return root.containsArmPoint(point.x, point.y)
        }
    }

    containmentMask: armContainmentMask

    Loader {
        id: kindLoader
        anchors.fill: parent
        sourceComponent: root.kind === "cava" ? cavaComp
            : root.kind === "workspaces" ? workspacesComp
            : root.kind === "resources" ? resourcesComp
            : root.kind === "clock" ? clockComp
            : root.kind === "media" ? mediaComp
            : root.kind === "battery" ? batteryComp
            : root.kind === "weather" ? weatherComp
            : root.kind === "activeWindow" ? activeWindowComp
            : root.kind === "utilButtons" ? utilButtonsComp
            : root.kind === "taskbar" ? taskbarComp
            : root.kind === "tray" ? trayComp
            : root.kind === "distroIcon" ? distroComp
            : root.kind === "timer" ? timerComp
            : root.kind === "shellUpdate" ? updateComp
            : fallbackComp
    }

    // ─── Cava Equalizer: Radial symmetric stereo bars curving around the 90° corner ───
    Component {
        id: cavaComp
        Item {
            id: cavaWrap
            anchors.fill: parent
            objectName: "cornerWrapCavaModule"
            readonly property int configuredWidth: Math.max(48, Math.min(480, Number(Config.options?.bar?.cava?.width ?? 120)))
            readonly property int configuredHeight: Math.max(10, Math.min(30, Number(Config.options?.bar?.cava?.height ?? 22)))
            readonly property int barSpacing: Math.max(1, Math.min(6, Number(Config.options?.bar?.cava?.barSpacing ?? 2)))
            readonly property int barRadius: Math.max(0, Math.min(6, Number(Config.options?.bar?.cava?.barRadius ?? 2)))
            readonly property bool mirrorBars: Boolean(Config.options?.bar?.cava?.mirror ?? false)
            // Rotation 180° flips bar growth: from screen edges inward toward the desktop.
            readonly property bool invertBars: root.moduleRotation === 180
            readonly property bool stereoSource: Config.options?.appearance?.cava?.stereo ?? true
            readonly property int configuredBarCount: Math.max(0, Math.min(200, Number(Config.options?.appearance?.cava?.bars ?? 0)))

            readonly property real pathSpan: Math.max(24, root.totalPathLength)
            readonly property int autoBarCount: Math.max(6, Math.min(72, Math.floor((pathSpan + barSpacing * root.contentScale) / ((4 + barSpacing) * root.contentScale))))
            readonly property int effectiveBarCount: configuredBarCount > 0
                ? Math.max(1, Math.min(configuredBarCount, Math.max(1, Math.floor((pathSpan + barSpacing) / (2 + barSpacing)))))
                : autoBarCount
            readonly property real barWidth: {
                const count = Math.max(1, effectiveBarCount)
                const gapTotal = Math.max(0, count - 1) * barSpacing * Math.min(1.2, root.contentScale)
                return Math.max(1.5, Math.min(10, (pathSpan - gapTotal) / count))
            }
            readonly property real maxBarHeight: Math.max(6, Math.min(root.wrapThickness * 0.88, configuredHeight * root.contentScale))
            readonly property bool audioActive: MprisController.anyAudioPlaying || Audio.hasActivePlayback
            readonly property var paletteColors: {
                const pal = CavaTheme.visualizerColors
                if (pal && pal.length > 0) return pal
                return [Appearance.colors.colPrimary, Appearance.colors.colSecondary, Appearance.colors.colTertiary]
            }

            // Precompute bar palette once per count/theme change to avoid per-frame Qt.rgba() churn.
            readonly property var cachedBarColors: {
                const count = Math.max(1, cavaWrap.effectiveBarCount)
                const pal = cavaWrap.paletteColors
                const out = new Array(count)
                if (!pal || pal.length === 0) {
                    out.fill(Appearance.colors.colPrimary)
                    return out
                }
                if (pal.length === 1) {
                    out.fill(pal[0])
                    return out
                }
                const symmetric = cavaWrap.stereoSource
                for (let idx = 0; idx < count; ++idx) {
                    const linear = count > 1 ? idx / (count - 1) : 0
                    const t = symmetric ? (1.0 - Math.abs(linear * 2.0 - 1.0)) : linear
                    const scaled = t * (pal.length - 1)
                    const lo = Math.min(pal.length - 1, Math.floor(scaled))
                    const hi = Math.min(pal.length - 1, lo + 1)
                    const f = scaled - lo
                    const a = Qt.color(pal[lo])
                    const b = Qt.color(pal[hi])
                    out[idx] = Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, a.a + (b.a - a.a) * f)
                }
                return out
            }

            function barColorForIndex(idx: int, count: int): color {
                const cached = cavaWrap.cachedBarColors
                if (cached && idx >= 0 && idx < cached.length)
                    return cached[idx]
                return Appearance.colors.colPrimary
            }

            property var _scratchA: []
            property var _scratchB: []
            property bool _scratchFlip: false
            readonly property var _idleNormalized: {
                const count = Math.max(1, cavaWrap.effectiveBarCount)
                const out = new Array(count)
                out.fill(0)
                return out
            }

            // Upstream symmetric stereo presentation: CAVA outputs mirrored stereo
            // [L_high..L_low, R_low..R_high] so mapping samples directly across bars
            // places bass symmetrically at the center / corner apex and highs toward both tips.
            function _fillNormalizedBars(pts, ceilingValue, barCount, isStereo, signalActive, out): var {
                const count = Math.max(1, Number(barCount) || 1)
                out.length = count
                const len = pts ? pts.length : 0
                if (!signalActive || len <= 0) {
                    for (let i = 0; i < count; ++i) out[i] = 0
                    return out
                }
                const ceiling = Math.max(1, Number(ceilingValue) || 20)
                const upsample = count > len && len > 1
                for (let idx = 0; idx < count; ++idx) {
                    let level = 0
                    if (upsample) {
                        const pos = (idx / Math.max(1, count - 1)) * (len - 1)
                        const lo = Math.floor(pos)
                        const hi = Math.min(len - 1, lo + 1)
                        const frac = pos - lo
                        const vLo = Math.max(0, Number(pts[lo] || 0))
                        const vHi = Math.max(0, Number(pts[hi] || 0))
                        level = vLo * (1 - frac) + vHi * frac
                    } else {
                        const binStart = Math.floor((idx * len) / count)
                        const binEnd = Math.min(len, Math.max(binStart + 1, Math.ceil(((idx + 1) * len) / count)))
                        let sum = 0
                        let peak = 0
                        let cnt = 0
                        for (let k = binStart; k < binEnd; ++k) {
                            const v = Math.max(0, Number(pts[k] || 0))
                            sum += v
                            if (v > peak) peak = v
                            cnt++
                        }
                        const avg = cnt > 0 ? (sum / cnt) : 0
                        level = avg * 0.62 + peak * 0.38
                    }
                    const norm = Math.max(0, Math.min(1, level / ceiling))
                    out[idx] = norm > 0.002 ? Math.pow(norm, 0.82) : 0
                }
                return out
            }

            function computeNormalizedBars(pts, ceilingValue, barCount, isStereo, signalActive): var {
                return cavaWrap._fillNormalizedBars(pts, ceilingValue, barCount, isStereo, signalActive, new Array(Math.max(1, Number(barCount) || 1)))
            }

            CavaProcess {
                id: cornerCavaProc
                active: cavaWrap.visible && cavaWrap.audioActive
                sampleCount: Math.max(32, cavaWrap.effectiveBarCount)
                onPointsChanged: cavaWrap._rebuildTargetNormalized()
                onAudioSignalActiveChanged: cavaWrap._rebuildTargetNormalized()
            }

            // Imperative double-buffered frame rebuild avoids self-mutating QML
            // binding loops and redundant ceiling-decay recomputation.
            property var targetNormalized: cavaWrap._idleNormalized

            function _rebuildTargetNormalized(): void {
                if (!cavaWrap.visible || !cornerCavaProc.audioSignalActive) {
                    if (cavaWrap.targetNormalized !== cavaWrap._idleNormalized)
                        cavaWrap.targetNormalized = cavaWrap._idleNormalized
                    return
                }
                cavaWrap._scratchFlip = !cavaWrap._scratchFlip
                const buf = cavaWrap._scratchFlip ? cavaWrap._scratchA : cavaWrap._scratchB
                cavaWrap.targetNormalized = cavaWrap._fillNormalizedBars(
                    cornerCavaProc.points,
                    cornerCavaProc.normalizationCeiling,
                    cavaWrap.effectiveBarCount,
                    cavaWrap.stereoSource,
                    true,
                    buf
                )
            }

            onVisibleChanged: cavaWrap._rebuildTargetNormalized()
            onEffectiveBarCountChanged: cavaWrap._rebuildTargetNormalized()
            onStereoSourceChanged: cavaWrap._rebuildTargetNormalized()
            Component.onCompleted: cavaWrap._rebuildTargetNormalized()

            Repeater {
                model: cavaWrap.effectiveBarCount
                delegate: Item {
                    id: barNode
                    required property int index
                    readonly property real t: cavaWrap.effectiveBarCount > 1 ? index / (cavaWrap.effectiveBarCount - 1) : 0.5
                    readonly property var pt: root.pointAt(t)
                    property real level: (index < cavaWrap.targetNormalized.length)
                        ? cavaWrap.targetNormalized[index] : 0
                    Behavior on level {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
                    }
                    readonly property real barH: Math.max(2, Math.round(2 + Math.max(0, Math.min(1, level)) * Math.max(2, cavaWrap.maxBarHeight - 2)))
                    x: pt.x
                    y: pt.y
                    width: 0
                    height: 0
                    rotation: pt.angle

                    Rectangle {
                        objectName: "cornerWrapCavaBar"
                        x: -cavaWrap.barWidth * 0.5
                        y: cavaWrap.mirrorBars
                            ? (-barNode.barH * 0.5)
                            : cavaWrap.invertBars
                                ? (-cavaWrap.maxBarHeight * 0.5)
                                : (cavaWrap.maxBarHeight * 0.5 - barNode.barH)
                        width: cavaWrap.barWidth
                        height: barNode.barH
                        radius: Math.min(cavaWrap.barWidth * 0.5, cavaWrap.barRadius * root.contentScale)
                        color: cavaWrap.barColorForIndex(barNode.index, cavaWrap.effectiveBarCount)
                        opacity: cornerCavaProc.audioSignalActive ? 0.96 : 0.34
                    }
                }
            }
        }
    }

    // ─── Workspaces: Clickable workspace indicators curving around the corner ───
    Component {
        id: workspacesComp
        Item {
            id: wsWrap
            anchors.fill: parent
            readonly property color activeColor: {
                const autoColor = Config.options?.bar?.workspaces?.automaticIndicatorColor ?? true
                const custom = String(Config.options?.bar?.workspaces?.indicatorColor ?? "")
                if (!autoColor && custom.length > 0) {
                    const parsed = Qt.color(custom)
                    if (parsed.valid) return parsed
                }
                return Appearance.colors.colPrimary
            }
            readonly property var workspaceList: {
                if (CompositorService.isNiri) {
                    const perMon = Config.options?.bar?.workspaces?.perMonitor ?? true
                    const all = NiriService.allWorkspaces ?? []
                    const list = perMon ? all.filter(w => w.output === root.outputName) : all
                    return list.slice(0, 10)
                }
                const count = Math.max(1, Math.min(10, Number(Config.options?.bar?.workspaces?.shown ?? 5)))
                const focusedId = CompositorService.isHyprland ? Number(Hyprland.focusedWorkspace?.id ?? 1) : 1
                const out = []
                for (let i = 1; i <= count; ++i)
                    out.push({ id: i, idx: i, is_active: i === focusedId })
                return out
            }

            Repeater {
                model: wsWrap.workspaceList
                delegate: Item {
                    id: wsNode
                    required property var modelData
                    required property int index
                    readonly property int count: Math.max(1, wsWrap.workspaceList.length)
                    readonly property real t: count > 1 ? (index + 0.5) / count : 0.5
                    readonly property var pt: root.pointAt(t)
                    readonly property bool isActive: Boolean(modelData?.is_active || modelData?.is_focused)
                    x: pt.x - width * 0.5
                    y: pt.y - height * 0.5
                    width: isActive ? 22 * root.contentScale : 14 * root.contentScale
                    height: 14 * root.contentScale
                    rotation: pt.angle

                    Rectangle {
                        anchors.centerIn: parent
                        width: wsNode.isActive ? 18 * root.contentScale : 8 * root.contentScale
                        height: 8 * root.contentScale
                        radius: height * 0.5
                        color: wsNode.isActive
                            ? wsWrap.activeColor
                            : (wsMouse.containsMouse ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer1Inactive)
                        Behavior on width {
                            enabled: Appearance.animationsEnabled
                            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                    }

                    MouseArea {
                        id: wsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                GlobalStates.toggleOverview(root.outputName)
                                return
                            }
                            if (CompositorService.isNiri && wsNode.modelData?.id !== undefined)
                                NiriService.switchToWorkspaceById(wsNode.modelData.id)
                            else if (CompositorService.isHyprland && wsNode.modelData?.id !== undefined)
                                Hyprland.dispatch("workspace " + wsNode.modelData.id)
                        }
                    }
                }
            }
        }
    }

    // ─── System Resources: Telemetry chips curved around the corner ───
    Component {
        id: resourcesComp
        MouseArea {
            id: resWrap
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            containmentMask: armContainmentMask

            property QtObject resourceMonitor: ResourceUsageMonitor {
                network: false
                histories: false
                target: resWrap
                active: !GameMode.active
            }

            readonly property var entries: {
                const list = []
                if (Config.options?.bar?.resources?.showMemoryIndicator ?? true)
                    list.push({ icon: "memory", pct: Math.round((ResourceUsage.memoryUsedPercentage ?? 0) * 100) })
                if (Config.options?.bar?.resources?.showTempIndicator ?? true)
                    list.push({ icon: "thermostat", pct: Math.round((ResourceUsage.tempPercentage ?? 0) * 100) })
                if (Config.options?.bar?.resources?.showCpuIndicator ?? true)
                    list.push({ icon: "planner_review", pct: Math.round((ResourceUsage.cpuUsage ?? 0) * 100) })
                if (Config.options?.bar?.resources?.showGpuIndicator ?? true)
                    list.push({ icon: "memory_alt", pct: Math.round((ResourceUsage.gpuUsage ?? 0) * 100) })
                return list
            }

            Repeater {
                model: resWrap.entries
                delegate: Item {
                    required property var modelData
                    required property int index
                    readonly property int count: Math.max(1, resWrap.entries.length)
                    readonly property real t: count > 1 ? (index + 0.5) / count : 0.5
                    readonly property var pt: root.pointAt(t)
                    x: pt.x - width * 0.5
                    y: pt.y - height * 0.5
                    width: 28 * root.contentScale
                    height: 24 * root.contentScale

                    Column {
                        anchors.centerIn: parent
                        spacing: 0
                        MaterialSymbol {
                            anchors.horizontalCenter: parent.horizontalCenter
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData.icon
                            iconSize: 13 * Appearance.fontSizeScale * root.contentScale
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData.pct + "%"
                            font.pixelSize: 9 * Appearance.fontSizeScale * root.contentScale
                            font.features: ({ "tnum": 1 })
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            Shared.ResourcesPopup {
                hoverTarget: resWrap
            }
        }
    }

    // ─── Clock: Time on horizontal arm, dot at corner bend, date on vertical arm ───
    Component {
        id: clockComp
        MouseArea {
            id: clockWrap
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            containmentMask: armContainmentMask

            // Horizontal arm: Time
            StyledText {
                x: root.hArmCenter.x - width * 0.5
                y: root.hArmCenter.y - height * 0.5
                width: Math.max(24, root.hArmCenter.span - 4)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: DateTime.timeDisplay
                font.pixelSize: Appearance.font.pixelSize.normal * root.contentScale
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
                color: Appearance.colors.colOnLayer1
            }

            // Corner apex accent dot
            Rectangle {
                x: root.cornerPoint.x - width * 0.5
                y: root.cornerPoint.y - height * 0.5
                width: 6 * root.contentScale
                height: width
                radius: width * 0.5
                color: Appearance.colors.colPrimary
            }

            // Vertical arm: Date (compact stacked lines)
            Column {
                x: root.vArmCenter.x - width * 0.5
                y: root.vArmCenter.y - height * 0.5
                spacing: 1
                Repeater {
                    model: String(DateTime.date ?? "").split(/[\s,]+/).filter(s => s.length > 0).slice(0, 3)
                    delegate: StyledText {
                        required property string modelData
                        anchors.horizontalCenter: parent.horizontalCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.length > 5 ? modelData.slice(0, 5) : modelData
                        font.pixelSize: 10 * Appearance.fontSizeScale * root.contentScale
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            Shared.ClockCalendarPopup {
                hoverTarget: clockWrap
            }
        }
    }

    // ─── Media: Corner play/pause badge + title on horizontal arm + prev/next on vertical arm ───
    Component {
        id: mediaComp
        MouseArea {
            id: mediaWrap
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            containmentMask: armContainmentMask
            readonly property MprisPlayer activePlayer: MprisController.activePlayer
            readonly property bool playing: activePlayer?.playbackState === MprisPlaybackState.Playing
            readonly property string trackTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")

            // Corner apex: Play/Pause circle button
            Rectangle {
                x: root.cornerPoint.x - width * 0.5
                y: root.cornerPoint.y - height * 0.5
                width: 24 * root.contentScale
                height: width
                radius: width * 0.5
                color: Qt.alpha(Appearance.colors.colPrimary, playMouse.containsMouse ? 0.30 : 0.18)

                MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: mediaWrap.playing ? "pause" : "play_arrow"
                    fill: 1
                    iconSize: 15 * Appearance.fontSizeScale * root.contentScale
                    color: Appearance.colors.colPrimary
                }
                MouseArea {
                    id: playMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: MprisController.togglePlaying()
                }
            }

            // Horizontal arm: Track title
            StyledText {
                x: root.hArmCenter.x - width * 0.5
                y: root.hArmCenter.y - height * 0.5
                width: Math.max(24, root.hArmCenter.span - 6)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: mediaWrap.trackTitle
                font.pixelSize: 11 * Appearance.fontSizeScale * root.contentScale
                color: Appearance.colors.colOnLayer1
            }

            // Vertical arm: Prev / Next transport controls
            Column {
                x: root.vArmCenter.x - width * 0.5
                y: root.vArmCenter.y - height * 0.5
                spacing: 4
                MaterialSymbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: "skip_previous"
                    iconSize: 15 * Appearance.fontSizeScale * root.contentScale
                    color: prevMouse.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                    MouseArea {
                        id: prevMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MprisController.previous()
                    }
                }
                MaterialSymbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: "skip_next"
                    iconSize: 15 * Appearance.fontSizeScale * root.contentScale
                    color: nextMouse.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                    MouseArea {
                        id: nextMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MprisController.next()
                    }
                }
            }

            Shared.StyledPopup {
                id: cornerMediaPopup
                hoverTarget: mediaWrap
                hoverActivates: true
                popupBackgroundMargin: 0
                BarMediaPopup {
                    presentationActive: cornerMediaPopup.presentationActive
                }
            }
        }
    }

    // ─── Battery: Corner glyph + % on horizontal arm + state on vertical arm ───
    Component {
        id: batteryComp
        MouseArea {
            id: batWrap
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            containmentMask: armContainmentMask
            readonly property int pct: Math.round((Battery.percentage ?? 0) * 100)
            readonly property bool low: (Battery.percentage ?? 1) <= (Config.options?.battery?.low ?? 20) / 100

            MaterialSymbol {
                x: root.cornerPoint.x - width * 0.5
                y: root.cornerPoint.y - height * 0.5
                horizontalAlignment: Text.AlignHCenter
                text: Battery.isCharging ? "battery_charging_full" : "battery_full"
                fill: 1
                iconSize: 17 * Appearance.fontSizeScale * root.contentScale
                color: (batWrap.low && !Battery.isCharging) ? Appearance.colors.colError : Appearance.colors.colPrimary
            }

            StyledText {
                x: root.hArmCenter.x - width * 0.5
                y: root.hArmCenter.y - height * 0.5
                horizontalAlignment: Text.AlignHCenter
                text: batWrap.pct + "%"
                font.pixelSize: 11 * Appearance.fontSizeScale * root.contentScale
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
                color: Appearance.colors.colOnLayer1
            }

            MaterialSymbol {
                x: root.vArmCenter.x - width * 0.5
                y: root.vArmCenter.y - height * 0.5
                horizontalAlignment: Text.AlignHCenter
                text: Battery.isCharging ? "bolt" : "eco"
                iconSize: 14 * Appearance.fontSizeScale * root.contentScale
                color: Appearance.colors.colSubtext
            }

            Shared.BatteryPopup {
                hoverTarget: batWrap
            }
        }
    }

    // ─── Weather: Corner glyph + temp on horizontal arm + feels-like on vertical arm ───
    Component {
        id: weatherComp
        MouseArea {
            id: weatherWrap
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.RightButton
            containmentMask: armContainmentMask
            onClicked: Weather.forceRefresh()

            MaterialSymbol {
                x: root.cornerPoint.x - width * 0.5
                y: root.cornerPoint.y - height * 0.5
                horizontalAlignment: Text.AlignHCenter
                text: Icons.getWeatherIcon(Weather.data?.wCode, Weather.isNightNow()) ?? "cloud"
                iconSize: 17 * Appearance.fontSizeScale * root.contentScale
                color: Appearance.colors.colPrimary
            }

            StyledText {
                x: root.hArmCenter.x - width * 0.5
                y: root.hArmCenter.y - height * 0.5
                horizontalAlignment: Text.AlignHCenter
                text: Weather.data?.temp ?? "--°"
                font.pixelSize: 11 * Appearance.fontSizeScale * root.contentScale
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                x: root.vArmCenter.x - width * 0.5
                y: root.vArmCenter.y - height * 0.5
                horizontalAlignment: Text.AlignHCenter
                text: Weather.data?.tempFeelsLike ?? ""
                font.pixelSize: 9 * Appearance.fontSizeScale * root.contentScale
                color: Appearance.colors.colSubtext
            }

            WeatherPopup {
                hoverTarget: weatherWrap
            }
        }
    }

    // ─── Active Window: Icon at corner + title along horizontal arm + rotated app name on vertical arm ───
    Component {
        id: activeWindowComp
        Item {
            anchors.fill: parent
            readonly property string appName: CompositorService.isNiri
                ? String(NiriService.activeWindow?.app_id ?? "")
                : String(ToplevelManager.activeToplevel?.appId ?? "")
            readonly property string winTitle: CompositorService.isNiri
                ? String(NiriService.activeWindow?.title ?? Translation.tr("Desktop"))
                : String(ToplevelManager.activeToplevel?.title ?? Translation.tr("Desktop"))

            MaterialSymbol {
                x: root.cornerPoint.x - width * 0.5
                y: root.cornerPoint.y - height * 0.5
                horizontalAlignment: Text.AlignHCenter
                text: "web_asset"
                iconSize: 16 * Appearance.fontSizeScale * root.contentScale
                color: Appearance.colors.colPrimary
            }

            StyledText {
                x: root.hArmCenter.x - width * 0.5
                y: root.hArmCenter.y - height * 0.5
                width: Math.max(24, root.hArmCenter.span - 6)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: winTitle
                font.pixelSize: 11 * Appearance.fontSizeScale * root.contentScale
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                x: root.vArmCenter.x - width * 0.5
                y: root.vArmCenter.y - height * 0.5
                width: Math.max(24, root.vArmCenter.span - 6)
                rotation: root.mirrorX ? 90 : -90
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: appName.split(".").pop() || "Alis"
                font.pixelSize: 9 * Appearance.fontSizeScale * root.contentScale
                color: Appearance.colors.colSubtext
            }
        }
    }

    // ─── Quick Actions (UtilButtons): Configured action icons curving around the corner ───
    Component {
        id: utilButtonsComp
        Item {
            id: utilWrap
            anchors.fill: parent
            readonly property var defaultOrder: [
                "screenSnip", "screenRecord", "colorPicker", "notepad", "keyboard",
                "keyboardLayout", "mic", "screenCast", "darkMode", "performance", "utilities"
            ]
            readonly property var actions: {
                const cfg = Config.options?.bar?.utilButtons ?? {}
                const configured = cfg.order ?? []
                const ordered = []
                for (const id of configured) {
                    if (defaultOrder.includes(id) && !ordered.includes(id))
                        ordered.push(id)
                }
                for (const id of defaultOrder) {
                    if (!ordered.includes(id))
                        ordered.push(id)
                }
                const out = []
                for (const id of ordered) {
                    if (id === "screenSnip" && (cfg.showScreenSnip ?? true))
                        out.push({ id: id, icon: "screenshot_region", tip: Translation.tr("Take screenshot"), danger: false })
                    else if (id === "screenRecord" && (cfg.showScreenRecord ?? true))
                        out.push({ id: id, icon: "videocam", tip: RecorderStatus.isRecording ? Translation.tr("Stop screen recording") : Translation.tr("Start screen recording"), danger: RecorderStatus.isRecording })
                    else if (id === "colorPicker" && (cfg.showColorPicker ?? false))
                        out.push({ id: id, icon: "colorize", tip: Translation.tr("Pick color"), danger: false })
                    else if (id === "notepad" && (cfg.showNotepad ?? true))
                        out.push({ id: id, icon: "edit_note", tip: Translation.tr("Open notepad"), danger: false })
                    else if (id === "keyboard" && (cfg.showKeyboardToggle ?? true))
                        out.push({ id: id, icon: "keyboard", tip: Translation.tr("Toggle on-screen keyboard"), danger: false })
                    else if (id === "keyboardLayout" && (cfg.showKeyboardLayoutSwitch ?? false) && CompositorService.isNiri && NiriService.hasMultipleKeyboardLayouts)
                        out.push({ id: id, icon: "language", tip: Translation.tr("Switch keyboard layout"), danger: false })
                    else if (id === "mic" && ((cfg.showMicToggle ?? false) || Privacy.micActive || (Audio?.micBeingAccessed ?? false)))
                        out.push({ id: id, icon: Audio.micMuted ? "mic_off" : "mic", tip: Audio.micMuted ? Translation.tr("Unmute microphone") : Translation.tr("Mute microphone"), danger: !Audio.micMuted && (Privacy.micActive || (Audio?.micBeingAccessed ?? false)) })
                    else if (id === "screenCast" && (cfg.showScreenCast ?? false) && CompositorService.isNiri)
                        out.push({ id: id, icon: "cast", tip: Persistent.states.screenCast.active ? Translation.tr("Stop screen casting") : Translation.tr("Start screen casting"), danger: Boolean(Persistent.states.screenCast.active) })
                    else if (id === "darkMode" && (cfg.showDarkModeToggle ?? true))
                        out.push({ id: id, icon: Appearance.m3colors.darkmode ? "light_mode" : "dark_mode", tip: Appearance.m3colors.darkmode ? Translation.tr("Switch to light mode") : Translation.tr("Switch to dark mode"), danger: false })
                    else if (id === "performance" && (cfg.showPerformanceProfileToggle ?? false))
                        out.push({ id: id, icon: PowerProfiles.profile === PowerProfile.PowerSaver ? "energy_savings_leaf" : PowerProfiles.profile === PowerProfile.Performance ? "local_fire_department" : "settings_slow_motion", tip: Translation.tr("Change power profile"), danger: false })
                    else if (id === "utilities" && (cfg.showUtilitiesLauncher ?? true))
                        out.push({ id: id, icon: "tune", tip: Translation.tr("Utilities"), danger: false })
                }
                return out.length > 0 ? out.slice(0, 7) : [{ id: "utilities", icon: "tune", tip: Translation.tr("Utilities"), danger: false }]
            }

            Repeater {
                model: utilWrap.actions
                delegate: Rectangle {
                    id: actBtn
                    required property var modelData
                    required property int index
                    readonly property int count: Math.max(1, utilWrap.actions.length)
                    readonly property real t: count > 1 ? (index + 0.5) / count : 0.5
                    readonly property var pt: root.pointAt(t)
                    x: pt.x - width * 0.5
                    y: pt.y - height * 0.5
                    width: 24 * root.contentScale
                    height: width
                    radius: width * 0.5
                    color: actMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"

                    MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: actBtn.modelData.icon
                        iconSize: 15 * Appearance.fontSizeScale * root.contentScale
                        color: actBtn.modelData.danger
                            ? Appearance.colors.colError
                            : (actMouse.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1)
                    }

                    MouseArea {
                        id: actMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: {
                            if (actBtn.modelData.id === "utilities") {
                                root.hoverState("utilities", containsMouse)
                                if (containsMouse) root.hoverRequest("utilities")
                            }
                        }
                        onClicked: {
                            const aid = actBtn.modelData.id
                            if (aid === "utilities") {
                                root.request("utilities")
                            } else if (aid === "screenSnip") {
                                Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "region", "screenshot"])
                            } else if (aid === "screenRecord") {
                                const args = ["/usr/bin/bash", Directories.recordScriptPath]
                                if (RecorderStatus.isRecording) args.push("--stop")
                                else args.push("--fullscreen", "--sound")
                                Quickshell.execDetached(args)
                                RecorderStatus.scheduleQuickCheck()
                            } else if (aid === "colorPicker") {
                                ColorPickerService.start()
                            } else if (aid === "notepad") {
                                GlobalStates.sidebarRightRequestedWidget = "notepad"
                                GlobalStates.openSidebarRight(root.outputName)
                            } else if (aid === "keyboard") {
                                GlobalStates.oskOpen = !GlobalStates.oskOpen
                            } else if (aid === "keyboardLayout") {
                                NiriService.switchLayout()
                            } else if (aid === "mic") {
                                Audio.toggleMicMute()
                            } else if (aid === "screenCast") {
                                const output = Config.options?.bar?.utilButtons?.screenCastOutput ?? "HDMI-A-1"
                                if (Persistent.states.screenCast.active) {
                                    Quickshell.execDetached(["niri", "msg", "action", "clear-dynamic-cast-target"])
                                    Persistent.states.screenCast.active = false
                                } else {
                                    Quickshell.execDetached(["niri", "msg", "action", "set-dynamic-cast-monitor", output])
                                    Persistent.states.screenCast.active = true
                                }
                            } else if (aid === "darkMode") {
                                MaterialThemeLoader.setDarkMode(!Appearance.m3colors.darkmode)
                            } else if (aid === "performance") {
                                if (PowerProfiles.hasPerformanceProfile) {
                                    if (PowerProfiles.profile === PowerProfile.PowerSaver) PowerProfiles.profile = PowerProfile.Balanced
                                    else if (PowerProfiles.profile === PowerProfile.Balanced) PowerProfiles.profile = PowerProfile.Performance
                                    else PowerProfiles.profile = PowerProfile.PowerSaver
                                } else {
                                    PowerProfiles.profile = PowerProfiles.profile === PowerProfile.Balanced ? PowerProfile.PowerSaver : PowerProfile.Balanced
                                }
                            }
                        }
                    }

                    StyledToolTip {
                        extraVisibleCondition: actMouse.containsMouse && actBtn.modelData.id !== "utilities"
                        text: actBtn.modelData.tip
                    }
                }
            }
        }
    }

    // ─── Taskbar: Running window icons curving around the corner (Niri & ToplevelManager) ───
    Component {
        id: taskbarComp
        Item {
            id: tbWrap
            anchors.fill: parent
            readonly property var windowEntries: {
                if (CompositorService.isNiri && (NiriService.windows?.length ?? 0) > 0) {
                    return NiriService.windows.slice(0, 8).map(w => ({
                        niriId: w.id,
                        appId: String(w.app_id ?? ""),
                        toplevel: null
                    }))
                }
                const list = Array.from(ToplevelManager.toplevels?.values ?? [])
                return list.slice(0, 8).map(tl => ({
                    niriId: -1,
                    appId: String(tl?.appId ?? ""),
                    toplevel: tl
                }))
            }
            Repeater {
                model: tbWrap.windowEntries
                delegate: Item {
                    id: tbNode
                    required property var modelData
                    required property int index
                    readonly property int count: Math.max(1, tbWrap.windowEntries.length)
                    readonly property real t: count > 1 ? (index + 0.5) / count : 0.5
                    readonly property var pt: root.pointAt(t)
                    x: pt.x - width * 0.5
                    y: pt.y - height * 0.5
                    width: 24 * root.contentScale
                    height: width

                    SmartAppIcon {
                        anchors.centerIn: parent
                        icon: tbNode.modelData.appId
                        iconSize: 18 * root.contentScale
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (tbNode.modelData.niriId >= 0)
                                NiriService.focusWindow(tbNode.modelData.niriId)
                            else if (tbNode.modelData.toplevel?.activate)
                                tbNode.modelData.toplevel.activate()
                        }
                    }
                }
            }
            MaterialSymbol {
                visible: tbWrap.windowEntries.length === 0
                x: root.cornerPoint.x - width * 0.5
                y: root.cornerPoint.y - height * 0.5
                horizontalAlignment: Text.AlignHCenter
                text: "view_week"
                iconSize: 16 * Appearance.fontSizeScale * root.contentScale
                color: Appearance.colors.colSubtext
            }
        }
    }

    // ─── System Tray: Tray items curving around the corner ───
    Component {
        id: trayComp
        Item {
            id: trayWrap
            anchors.fill: parent
            readonly property var items: TrayService.deduplicateItems(SystemTray.items.values).slice(0, 8)
            Repeater {
                model: trayWrap.items
                delegate: Item {
                    id: trayNode
                    required property var modelData
                    required property int index
                    readonly property int count: Math.max(1, trayWrap.items.length)
                    readonly property real t: count > 1 ? (index + 0.5) / count : 0.5
                    readonly property var pt: root.pointAt(t)
                    x: pt.x - width * 0.5
                    y: pt.y - height * 0.5
                    width: 22 * root.contentScale
                    height: width

                    Shared.SysTrayItem {
                        anchors.fill: parent
                        item: trayNode.modelData
                    }
                }
            }
            MaterialSymbol {
                visible: trayWrap.items.length === 0
                x: root.cornerPoint.x - width * 0.5
                y: root.cornerPoint.y - height * 0.5
                horizontalAlignment: Text.AlignHCenter
                text: "dock_to_bottom"
                iconSize: 16 * Appearance.fontSizeScale * root.contentScale
                color: Appearance.colors.colSubtext
            }
        }
    }

    Component {
        id: distroComp
        MouseArea {
            id: distroWrap
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            containmentMask: armContainmentMask
            Shared.DistroIcon {
                x: root.cornerPoint.x - width * 0.5
                y: root.cornerPoint.y - height * 0.5
            }
            Shared.StyledPopup {
                hoverTarget: distroWrap
                liquidPresentationKind: "launcher"
                AbyssLauncherControlsPopup {}
            }
        }
    }

    // ─── Timer: Live pomodoro / countdown / stopwatch readout along corner ───
    Component {
        id: timerComp
        MouseArea {
            id: timerWrap
            anchors.fill: parent
            hoverEnabled: !timerWrap.showEditPreview
            cursorShape: timerWrap.showEditPreview ? Qt.ArrowCursor : Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            containmentMask: armContainmentMask
            readonly property bool pinnedToBar: Persistent.states?.timer?.pinnedToBar ?? false
            readonly property bool pomodoroRunning: TimerService?.pomodoroRunning ?? false
            readonly property bool countdownRunning: TimerService?.countdownRunning ?? false
            readonly property bool stopwatchRunning: TimerService?.stopwatchRunning ?? false
            readonly property bool pomodoroActive: pomodoroRunning || (TimerService?.pomodoroSecondsLeft ?? 0) < (TimerService?.pomodoroLapDuration ?? 0)
            readonly property bool countdownFinished: !countdownRunning && (TimerService?.countdownSecondsLeft ?? 0) <= 0 && (TimerService?.countdownDuration ?? 0) > 0
            readonly property bool countdownActive: !countdownFinished && (countdownRunning || (TimerService?.countdownSecondsLeft ?? 0) < (TimerService?.countdownDuration ?? 0))
            readonly property bool stopwatchActive: stopwatchRunning || (TimerService?.stopwatchTime ?? 0) > 0 || ((TimerService?.stopwatchLaps?.length ?? 0) > 0)
            readonly property bool anyActive: pomodoroActive || countdownActive || stopwatchActive
            readonly property bool showPinnedIdle: pinnedToBar && !anyActive
            readonly property bool showEditPreview: root.editing && !anyActive && !showPinnedIdle
            readonly property bool contentAvailable: anyActive || showPinnedIdle || showEditPreview
            readonly property bool useHourglass: !showPinnedIdle
                && (pomodoroActive || countdownActive || showEditPreview)
            readonly property real activeProgress: pomodoroActive
                ? (TimerService.pomodoroSecondsLeft / Math.max(1, TimerService.pomodoroLapDuration))
                : (countdownActive
                    ? (TimerService.countdownSecondsLeft / Math.max(1, TimerService.countdownDuration))
                    : (showEditPreview ? 0.65 : 1.0))
            readonly property bool isRunning: pomodoroActive
                ? (pomodoroRunning && !(TimerService?.pomodoroPaused ?? false))
                : (countdownActive
                    ? (countdownRunning && !(TimerService?.countdownPaused ?? false))
                    : (stopwatchActive && stopwatchRunning && !(TimerService?.stopwatchPaused ?? false)))
            readonly property bool paused: anyActive && !isRunning
            readonly property color glyphColor: paused
                ? Appearance.colors.colOnLayer1Inactive
                : ((pomodoroActive && (TimerService?.pomodoroBreak ?? false))
                    ? Appearance.colors.colTertiary
                    : (countdownActive
                        ? Appearance.colors.colSecondary
                        : ((anyActive || showEditPreview) ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1)))
            visible: contentAvailable
            readonly property string timeText: {
                if (pomodoroActive) {
                    const secs = TimerService?.pomodoroSecondsLeft ?? 0
                    return `${Math.floor(secs / 60).toString().padStart(2, '0')}:${Math.floor(secs % 60).toString().padStart(2, '0')}`
                }
                if (countdownActive) {
                    const secs = TimerService?.countdownSecondsLeft ?? 0
                    return `${Math.floor(secs / 60).toString().padStart(2, '0')}:${Math.floor(secs % 60).toString().padStart(2, '0')}`
                }
                if (stopwatchActive) {
                    const secs = Math.floor((TimerService?.stopwatchTime ?? 0) / 100)
                    return `${Math.floor(secs / 60).toString().padStart(2, '0')}:${(secs % 60).toString().padStart(2, '0')}`
                }
                if (showEditPreview)
                    return "25:00"
                if (showPinnedIdle)
                    return Translation.tr("Timer")
                return ""
            }
            onClicked: mouse => {
                if (timerWrap.showEditPreview)
                    return
                if (mouse.button === Qt.MiddleButton && anyActive) {
                    if (pomodoroActive) TimerService.togglePomodoro()
                    else if (countdownActive) TimerService.toggleCountdown()
                    else if (stopwatchActive) TimerService.toggleStopwatch()
                    return
                }
                GlobalStates.openSidebarRight(root.outputName)
            }

            MaterialSymbol {
                visible: !timerWrap.useHourglass
                x: root.cornerPoint.x - width * 0.5
                y: root.cornerPoint.y - height * 0.5
                horizontalAlignment: Text.AlignHCenter
                text: timerWrap.showPinnedIdle ? "schedule" : "timer"
                iconSize: 16 * Appearance.fontSizeScale * root.contentScale
                color: timerWrap.glyphColor
            }

            HourglassBarIcon {
                objectName: "cornerWrapTimerHourglass"
                visible: timerWrap.useHourglass
                x: root.cornerPoint.x - width * 0.5
                y: root.cornerPoint.y - height * 0.5
                visualStyle: TimerService?.visualStyle ?? "turned"
                progress: timerWrap.activeProgress
                paused: timerWrap.paused
                color: timerWrap.glyphColor
                iconSize: Math.round(16 * Appearance.fontSizeScale * root.contentScale)
            }

            StyledText {
                objectName: "cornerWrapTimerLabel"
                x: root.hArmCenter.x - width * 0.5
                y: root.hArmCenter.y - height * 0.5
                width: Math.max(12, root.hArmCenter.span - 4)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: timerWrap.timeText
                font.pixelSize: 11 * Appearance.fontSizeScale * root.contentScale
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
                color: timerWrap.paused ? Appearance.colors.colOnLayer1Inactive : Appearance.colors.colOnLayer1
            }

            MaterialSymbol {
                visible: timerWrap.anyActive || timerWrap.showEditPreview
                x: root.vArmCenter.x - width * 0.5
                y: root.vArmCenter.y - height * 0.5
                horizontalAlignment: Text.AlignHCenter
                text: (timerWrap.isRunning || timerWrap.showEditPreview) ? "play_arrow" : "pause"
                iconSize: 13 * Appearance.fontSizeScale * root.contentScale
                color: (timerWrap.isRunning || timerWrap.showEditPreview) ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
        }
    }

    // ─── Updates: Live ShellUpdates indicator + overlay launch / dismiss ───
    Component {
        id: updateComp
        MouseArea {
            id: updWrap
            anchors.fill: parent
            hoverEnabled: !updWrap.showEditPreview
            cursorShape: (updWrap.showEditPreview || ShellUpdates.isUpdating) ? Qt.ArrowCursor : Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            containmentMask: armContainmentMask
            readonly property bool liveContentAvailable: ShellUpdates.showUpdate || ShellUpdates.isUpdating
            readonly property bool showEditPreview: root.editing && !liveContentAvailable
            readonly property bool contentAvailable: liveContentAvailable || showEditPreview
            visible: contentAvailable
            onClicked: mouse => {
                if (updWrap.showEditPreview || ShellUpdates.isUpdating) return
                if (mouse.button === Qt.RightButton) ShellUpdates.dismiss()
                else ShellUpdates.openOverlay()
            }

            MaterialSymbol {
                x: root.cornerPoint.x - width * 0.5
                y: root.cornerPoint.y - height * 0.5
                horizontalAlignment: Text.AlignHCenter
                text: ShellUpdates.isUpdating ? "settings" : "upgrade"
                iconSize: 16 * Appearance.fontSizeScale * root.contentScale
                color: (updWrap.liveContentAvailable || updWrap.showEditPreview) ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }

            StyledText {
                objectName: "cornerWrapUpdateLabel"
                x: root.hArmCenter.x - width * 0.5
                y: root.hArmCenter.y - height * 0.5
                width: Math.max(12, root.hArmCenter.span - 4)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: ShellUpdates.isUpdating
                    ? Translation.tr("Updating")
                    : Translation.tr("Update")
                font.pixelSize: 10 * Appearance.fontSizeScale * root.contentScale
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                objectName: "cornerWrapUpdateBadge"
                x: root.vArmCenter.x - width * 0.5
                y: root.vArmCenter.y - height * 0.5
                width: Math.max(12, root.vArmCenter.span - 4)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                visible: text !== ""
                text: {
                    if (ShellUpdates.isUpdating) {
                        return (ShellUpdates.updateStep > 0 && ShellUpdates.updateTotalSteps > 0)
                            ? (ShellUpdates.updateStep + "/" + ShellUpdates.updateTotalSteps)
                            : ""
                    }
                    if (updWrap.showEditPreview)
                        return "3"
                    return ShellUpdates.commitsBehind > 0 ? String(ShellUpdates.commitsBehind) : "!"
                }
                font.pixelSize: 11 * Appearance.fontSizeScale * root.contentScale
                font.weight: Font.DemiBold
                color: Appearance.colors.colPrimary
            }
        }
    }

    Component {
        id: fallbackComp
        Item {
            anchors.fill: parent
            MaterialSymbol {
                x: root.cornerPoint.x - width * 0.5
                y: root.cornerPoint.y - height * 0.5
                horizontalAlignment: Text.AlignHCenter
                text: "widgets"
                iconSize: 16 * Appearance.fontSizeScale * root.contentScale
                color: Appearance.colors.colPrimary
            }
        }
    }
}
