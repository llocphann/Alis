pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "AbyssStageWindowLayout.js" as StageWindowLayout

// Captures all visible desktop windows on the active workspace in 1 GPU frame
// before the stage shrinks (focused or unfocused) and applies an OKLab
// palette-remap shader to auto-themed windows so they preview wallpaper theme
// shifts cleanly with zero opening flash.
Item {
    id: root

    property var captureScreen: null
    property string outputName: ""
    property var edgeInsets: ({ left: 0, top: 0, right: 0, bottom: 0 })
    property bool stageVisible: false
    property bool activeSession: false
    property bool captureReady: false
    property bool captureFailed: false
    property var capturedFrame: null
    property bool _captureInFlight: false
    property bool _captureArmed: false

    clip: true

    // Baseline palette frozen at session entry (prior to preview color shifts)
    property color baseBgColor: "#141414"
    property color baseSurfaceColor: "#1c1c1c"
    property color basePrimaryColor: "#80cbc4"
    property bool baseDarkMode: true
    property bool _baselineCaptured: false

    function _captureBaselinePalette(): void {
        if (root._baselineCaptured)
            return
        root._baselineCaptured = true
        const previewBase = MaterialThemeLoader.previewActive
            ? (MaterialThemeLoader._previewBaseline ?? null)
            : null
        if (previewBase && previewBase.m3background) {
            root.baseBgColor = Qt.color(previewBase.m3background)
            root.baseSurfaceColor = Qt.color(previewBase.m3surfaceContainerLow ?? previewBase.m3surface ?? previewBase.m3background)
            root.basePrimaryColor = Qt.color(previewBase.m3primary ?? "#80cbc4")
            root.baseDarkMode = previewBase.darkmode !== undefined ? Boolean(previewBase.darkmode) : Appearance.m3colors.darkmode
        } else {
            root.baseBgColor = Qt.color(Appearance.colors.colLayer0Base)
            root.baseSurfaceColor = Qt.color(Appearance.colors.colLayer1Base)
            root.basePrimaryColor = Qt.color(Appearance.colors.colPrimary)
            root.baseDarkMode = Appearance.m3colors.darkmode
        }
    }

    property color animatedTargetBg: Appearance.colors.colLayer0Base
    property color animatedTargetSurface: Appearance.colors.colLayer1Base
    property color animatedTargetPrimary: Appearance.colors.colPrimary

    Behavior on animatedTargetBg {
        enabled: Appearance.animationsEnabled && root.stageVisible
        ColorAnimation { duration: 220; easing.type: Easing.OutCubic }
    }
    Behavior on animatedTargetSurface {
        enabled: Appearance.animationsEnabled && root.stageVisible
        ColorAnimation { duration: 220; easing.type: Easing.OutCubic }
    }
    Behavior on animatedTargetPrimary {
        enabled: Appearance.animationsEnabled && root.stageVisible
        ColorAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    readonly property var windowItems: {
        if (!CompositorService.isNiri)
            return []
        return StageWindowLayout.layoutNiriWorkspaceWindows(
            NiriService.windows,
            NiriService.allWorkspaces,
            root.outputName,
            root.width,
            root.height,
            root.edgeInsets
        )
    }

    readonly property var hyprlandToplevels: {
        if (CompositorService.isNiri || !CompositorService.isHyprland)
            return []
        return Array.from(ToplevelManager.toplevels?.values ?? [])
    }

    readonly property real themePreviewMix: root.activeSession
        && ((Config.options?.appearance?.theme ?? "auto") === "auto")
        ? 1.0 : 0.0

    function _completeOneFrameCapture(): void {
        if (root.captureReady || root.captureFailed || root._captureInFlight || !screenCopy.hasContent)
            return
        root._captureInFlight = true
        root._captureBaselinePalette()
        const ok = screenCopy.grabToImage(result => {
            root._captureInFlight = false
            if (root.captureFailed)
                return
            if (result && String(result.url).length > 0) {
                root.capturedFrame = result
                root.captureReady = true
            } else {
                root.captureFailed = true
            }
        })
        if (!ok) {
            root._captureInFlight = false
            root.captureFailed = true
        }
    }

    Timer {
        id: captureTimeoutTimer
        interval: root.captureScreen !== null ? 220 : 32
        repeat: false
        running: !root.captureReady && !root.captureFailed
        onTriggered: {
            if (!root.captureReady)
                root.captureFailed = true
        }
    }

    Component.onCompleted: {
        root._captureBaselinePalette()
        Qt.callLater(() => {
            root._captureArmed = true
            if (screenCopy.hasContent)
                root._completeOneFrameCapture()
        })
    }

    ScreencopyView {
        id: screenCopy
        anchors.fill: parent
        captureSource: (root._captureArmed && !root.captureReady && !root.captureFailed) ? root.captureScreen : null
        live: false
        paintCursor: false
        visible: captureSource !== null
        onHasContentChanged: if (hasContent) Qt.callLater(root._completeOneFrameCapture)
        onStopped: {
            if (!root.captureReady && !root._captureInFlight)
                root.captureFailed = true
        }
    }

    Image {
        id: frozenScreenImage
        anchors.fill: parent
        visible: false
        cache: false
        smooth: true
        mipmap: true
        source: root.capturedFrame ? root.capturedFrame.url : ""
    }

    Item {
        id: tilesLayer
        anchors.fill: parent
        visible: root.stageVisible && (root.captureReady || root.captureFailed)

        Repeater {
            model: root.windowItems

            delegate: Item {
                id: winDelegate
                required property var modelData

                x: modelData.x
                y: modelData.y
                width: modelData.width
                height: modelData.height
                z: modelData.z

                readonly property bool autoThemed: StageWindowLayout.isAppAutoThemed(
                    winDelegate.modelData.appId,
                    Config.options?.appearance
                )
                readonly property var uv: StageWindowLayout.subRectUv(
                    winDelegate.x,
                    winDelegate.y,
                    winDelegate.width,
                    winDelegate.height,
                    root.width,
                    root.height
                )

                // Soft window elevation shadow against new preview wallpaper
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -3
                    z: -1
                    radius: 15
                    color: Qt.rgba(0, 0, 0, 0.24)
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.16)
                }

                ShaderEffect {
                    id: windowShader
                    anchors.fill: parent
                    visible: root.captureReady && frozenScreenImage.status === Image.Ready
                    property var screenTex: frozenScreenImage
                    property vector4d uvRect: Qt.vector4d(
                        winDelegate.uv.u0,
                        winDelegate.uv.v0,
                        winDelegate.uv.uw,
                        winDelegate.uv.vh
                    )
                    property vector4d tileSize: Qt.vector4d(
                        Math.max(1, winDelegate.width),
                        Math.max(1, winDelegate.height),
                        12,
                        root.themePreviewMix
                    )
                    property vector4d baseBg: Qt.vector4d(
                        root.baseBgColor.r,
                        root.baseBgColor.g,
                        root.baseBgColor.b,
                        root.baseDarkMode ? 1.0 : 0.0
                    )
                    property vector4d targetBg: Qt.vector4d(
                        root.animatedTargetBg.r,
                        root.animatedTargetBg.g,
                        root.animatedTargetBg.b,
                        Appearance.m3colors.darkmode ? 1.0 : 0.0
                    )
                    property vector4d baseSurface: Qt.vector4d(
                        root.baseSurfaceColor.r,
                        root.baseSurfaceColor.g,
                        root.baseSurfaceColor.b,
                        winDelegate.autoThemed ? 1.0 : 0.0
                    )
                    property vector4d targetSurface: Qt.vector4d(
                        root.animatedTargetSurface.r,
                        root.animatedTargetSurface.g,
                        root.animatedTargetSurface.b,
                        0.0
                    )
                    property vector4d basePrimary: Qt.vector4d(
                        root.basePrimaryColor.r,
                        root.basePrimaryColor.g,
                        root.basePrimaryColor.b,
                        0.0
                    )
                    property vector4d targetPrimary: Qt.vector4d(
                        root.animatedTargetPrimary.r,
                        root.animatedTargetPrimary.g,
                        root.animatedTargetPrimary.b,
                        0.0
                    )
                    fragmentShader: Qt.resolvedUrl("AbyssStageWindowTheme.frag.qsb")
                }

                // Offline / screencopy-denied fallback only (never triggers live Niri clipboard capture)
                Item {
                    id: fallbackVisual
                    anchors.fill: parent
                    visible: !root.captureReady && root.captureFailed

                    readonly property string previewUrl: {
                        if (!fallbackVisual.visible)
                            return ""
                        const cache = WindowPreviewService.previewCache
                        if (!cache?.[winDelegate.modelData.id])
                            return ""
                        return WindowPreviewService.getPreviewUrl(winDelegate.modelData.id)
                    }
                    readonly property var imgGeom: StageWindowLayout.previewImageGeometry(
                        winDelegate.width,
                        winDelegate.height,
                        winImg.implicitWidth,
                        winImg.implicitHeight
                    )

                    Rectangle {
                        anchors.fill: parent
                        visible: !winImg._everReady
                        radius: 12
                        color: Qt.alpha(Appearance.colors.colLayer1Base, 0.94)
                        border.width: 1
                        border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.4)

                        Column {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 32, 320)
                            spacing: 10

                            Image {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 48
                                height: 48
                                asynchronous: true
                                sourceSize: Qt.size(64, 64)
                                fillMode: Image.PreserveAspectFit
                                source: AppSearch.getIconSource(AppSearch.resolveWindowIdentity({
                                    app_id: winDelegate.modelData.appId,
                                    title: winDelegate.modelData.title
                                }))
                            }

                            StyledText {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: winDelegate.modelData.title || winDelegate.modelData.appId
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }

                    Image {
                        id: winImg
                        property bool _everReady: false
                        x: fallbackVisual.imgGeom.x
                        y: fallbackVisual.imgGeom.y
                        width: fallbackVisual.imgGeom.width
                        height: fallbackVisual.imgGeom.height
                        asynchronous: true
                        cache: false
                        retainWhileLoading: true
                        smooth: true
                        mipmap: true
                        fillMode: Image.PreserveAspectFit
                        sourceSize: Qt.size(
                            Math.min(3840, Math.ceil(Math.max(winDelegate.width + 128, 1))),
                            Math.min(2400, Math.ceil(Math.max(winDelegate.height + 128, 1)))
                        )
                        source: fallbackVisual.previewUrl
                        onStatusChanged: if (status === Image.Ready) _everReady = true
                        onSourceChanged: if (String(source).length === 0) _everReady = false
                        visible: false
                    }

                    ShaderEffect {
                        id: fallbackShader
                        x: fallbackVisual.imgGeom.x
                        y: fallbackVisual.imgGeom.y
                        width: fallbackVisual.imgGeom.width
                        height: fallbackVisual.imgGeom.height
                        visible: winImg._everReady
                        property var screenTex: winImg
                        property vector4d uvRect: Qt.vector4d(0, 0, 1, 1)
                        property vector4d tileSize: Qt.vector4d(
                            Math.max(1, fallbackVisual.imgGeom.width),
                            Math.max(1, fallbackVisual.imgGeom.height),
                            fallbackVisual.imgGeom.fillMode === "pad" ? 0 : 12,
                            root.themePreviewMix
                        )
                        property vector4d baseBg: Qt.vector4d(
                            root.baseBgColor.r,
                            root.baseBgColor.g,
                            root.baseBgColor.b,
                            root.baseDarkMode ? 1.0 : 0.0
                        )
                        property vector4d targetBg: Qt.vector4d(
                            root.animatedTargetBg.r,
                            root.animatedTargetBg.g,
                            root.animatedTargetBg.b,
                            Appearance.m3colors.darkmode ? 1.0 : 0.0
                        )
                        property vector4d baseSurface: Qt.vector4d(
                            root.baseSurfaceColor.r,
                            root.baseSurfaceColor.g,
                            root.baseSurfaceColor.b,
                            winDelegate.autoThemed ? 1.0 : 0.0
                        )
                        property vector4d targetSurface: Qt.vector4d(
                            root.animatedTargetSurface.r,
                            root.animatedTargetSurface.g,
                            root.animatedTargetSurface.b,
                            0.0
                        )
                        property vector4d basePrimary: Qt.vector4d(
                            root.basePrimaryColor.r,
                            root.basePrimaryColor.g,
                            root.basePrimaryColor.b,
                            0.0
                        )
                        property vector4d targetPrimary: Qt.vector4d(
                            root.animatedTargetPrimary.r,
                            root.animatedTargetPrimary.g,
                            root.animatedTargetPrimary.b,
                            0.0
                        )
                        fragmentShader: Qt.resolvedUrl("AbyssStageWindowTheme.frag.qsb")
                    }
                }
            }
        }

        Repeater {
            model: root.hyprlandToplevels

            delegate: Item {
                required property var modelData
                anchors.fill: parent
                anchors.leftMargin: Math.max(0, Number(root.edgeInsets?.left ?? 0)) + 15
                anchors.topMargin: Math.max(0, Number(root.edgeInsets?.top ?? 0)) + 15
                anchors.rightMargin: Math.max(0, Number(root.edgeInsets?.right ?? 0)) + 15
                anchors.bottomMargin: Math.max(0, Number(root.edgeInsets?.bottom ?? 0)) + 15

                ScreencopyView {
                    anchors.fill: parent
                    captureSource: modelData
                    live: !RecorderStatus.isRecording && !GameMode.active
                }
            }
        }
    }
}
