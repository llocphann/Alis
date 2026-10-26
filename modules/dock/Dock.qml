pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.perimeter
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects as GE
import Quickshell.Io
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland

Scope {
    id: root
    property bool pinned: (Config.options?.dock?.pinnedOnStartup ?? false)
        && !(Config.options?.dock?.hoverToReveal ?? false)
    readonly property string position: Config.options?.dock?.position ?? "bottom"
    readonly property bool isVertical: root.position === "left" || root.position === "right"
    readonly property bool isTop: root.position === "top"
    readonly property bool isLeft: root.position === "left"
    readonly property string surfaceDialect: Appearance.surfaceDialectFor("")
    readonly property bool zzzEverywhere: root.surfaceDialect === "zzz"
    readonly property bool regaliaEverywhere: root.surfaceDialect === "regalia"

    readonly property bool barIsVertical: Config.options?.bar?.bottom !== undefined
    property string _positionKey: `${root.position}_${barIsVertical}`

    Variants {
        model: {
            const screens = Quickshell.screens;
            const list = Config.options?.dock?.screenList ?? [];
            if (!list || list.length === 0)
                return screens;
            const matchedScreens = screens.filter(screen => {
                const screenName = screen?.name ?? "";
                return screenName.length > 0 && list.includes(screenName);
            });
            return matchedScreens.length > 0 ? matchedScreens : screens;
        }

        Loader {
            id: panelLoader
            required property var modelData
            active: true

            property string posKey: root._positionKey
            onPosKeyChanged: {
                active = false
                reloadTimer.start()
            }

            Timer {
                id: reloadTimer
                interval: 50
                onTriggered: panelLoader.active = true
            }

            sourceComponent: PanelWindow {
                id: dockRoot
                screen: panelLoader.modelData
                visible: !GlobalStates.screenLocked
                    && !GlobalStates.widgetEditMode

                property bool reveal: !GlobalStates.coverflowSelectorOpen
                    && !(GlobalStates.wallpaperLauncherOpen && root.position === "bottom")
                    && GlobalStates.shellEntryReady
                    && (ShellEditSession.active || root.pinned
                        || (Config.options?.dock?.hoverToReveal && dockMouseArea.containsMouse)
                        || (dockApps?.requestDockShow || dockAppsVertical?.requestDockShow)
                        || (Config.options?.dock?.showOnDesktop !== false
                            && !ToplevelManager.activeToplevel?.activated))

                property real editThicknessPreview: -1
                property real _editResizeBaseline: -1
                readonly property real dockHeight: editThicknessPreview >= 0
                    ? editThicknessPreview
                    : (Config.options?.dock?.height ?? 70)
                readonly property real screenEdgeThickness: Math.max(1, Math.min(32,
                    Math.round(Config.options?.appearance?.screenEdge?.width ?? 10)))
                readonly property bool screenEdgeShadowEnabled:
                    Config.options?.appearance?.screenEdge?.physicalShadow?.enabled ?? true
                readonly property real screenEdgeShadowSize: Math.max(0, Math.min(32,
                    Math.round(Config.options?.appearance?.screenEdge?.physicalShadow?.size ?? 15)))
                readonly property real screenEdgeShadowOpacity: Math.max(0, Math.min(1.0,
                    Number(Config.options?.appearance?.screenEdge?.physicalShadow?.opacity ?? 0.70)))
                readonly property color screenEdgeShadowColor:
                    Qt.alpha(Appearance.m3colors.m3shadow, dockRoot.screenEdgeShadowOpacity)
                readonly property real edgeDecorationMargin: Math.max(
                    Appearance.sizes.elevationMargin,
                    PerimeterTokens.abyssFuseDepth,
                    dockRoot.screenEdgeShadowEnabled ? dockRoot.screenEdgeShadowSize + 2 : 0)

                function beginDockResize(): void {
                    const baseline = Config.options?.dock?.height ?? 70
                    if (!ShellEditSession.beginGesture("iiDock", "resize-thickness",
                            { thickness: baseline }))
                        return
                    dockRoot._editResizeBaseline = baseline
                    dockRoot.editThicknessPreview = baseline
                }

                function updateDockResize(deltaX: real, deltaY: real): void {
                    if (dockRoot._editResizeBaseline < 0)
                        return
                    const towardScreen = root.position === "bottom" ? -deltaY
                        : root.isTop ? deltaY
                        : root.isLeft ? deltaX : -deltaX
                    dockRoot.editThicknessPreview = Math.max(40, Math.min(200,
                        dockRoot._editResizeBaseline + towardScreen))
                }

                function finishDockResize(): void {
                    if (dockRoot.editThicknessPreview >= 0)
                        ShellLayoutController.setProperty("iiDock", "thickness",
                            dockRoot.editThicknessPreview, dockRoot.screen?.name ?? "")
                    dockRoot.editThicknessPreview = -1
                    dockRoot._editResizeBaseline = -1
                    ShellEditSession.finishGesture()
                }

                function cancelDockResize(): void {
                    dockRoot.editThicknessPreview = -1
                    dockRoot._editResizeBaseline = -1
                    ShellEditSession.cancelPending()
                }

                Connections {
                    target: ShellEditSession
                    function onGestureKindChanged(): void {
                        if (ShellEditSession.gestureKind.length > 0)
                            return
                        dockRoot.editThicknessPreview = -1
                        dockRoot._editResizeBaseline = -1
                    }
                }

                anchors {
                    top: root.isTop || root.isVertical
                    bottom: !root.isTop || root.isVertical
                    left: root.isLeft || !root.isVertical
                    right: !root.isLeft || !root.isVertical
                }

                // Visual-only edge surface. Reservation is owned by the
                // separate transparent dock-reservation window below so setting
                // an exclusiveZone can never switch this visual back to Normal
                // exclusion/work-area coordinates.
                implicitWidth: root.isVertical
                    ? (dockHeight + Appearance.sizes.elevationMargin
                        + dockRoot.screenEdgeThickness)
                    : (dockBackground.implicitWidth
                        + dockRoot.edgeDecorationMargin * 2)
                implicitHeight: root.isVertical
                    ? (dockBackground.implicitHeight
                        + dockRoot.edgeDecorationMargin * 2)
                    : (dockHeight + Appearance.sizes.elevationMargin
                        + dockRoot.screenEdgeThickness)

                WlrLayershell.namespace: "quickshell:dock"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                // Physical-output coordinates are required by the connected
                // Abyss geometry. Never assign exclusiveZone on this window.
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"

                readonly property string nativeBlurTopology:
                    !(root.zzzEverywhere && !Appearance.zzz.round)
                    ? Appearance.blurTopology.roundedRectangle
                    : Appearance.blurTopology.unsupported
                readonly property bool nativeBlurActive: Appearance.useCompositorBlur(
                        "dock", dockRoot.nativeBlurTopology)
                    && (Config.options?.dock?.showBackground ?? true)
                    && !Appearance.gameModeMinimal
                readonly property Item nativeBlurItem: dockVisualBackground

                BackgroundEffect.blurRegion: Region {
                    item: dockRoot.nativeBlurActive ? dockRoot.nativeBlurItem : null
                    radius: dockRoot.nativeBlurItem?.radius ?? 0
                }

                mask: Region {
                    item: dockMouseArea
                }

                ConnectedSurfaceAbyssEdgeSurface {
                    id: dockAbyssSurface
                    z: 0
                    anchors.fill: parent
                    visible: dockVisualBackground.visible
                    edge: root.position
                    ownerThickness: dockRoot.screenEdgeThickness
                    paintOverlap: Math.min(
                        PerimeterTokens.seamOverlap,
                        Math.max(0, dockRoot.screenEdgeThickness - 1))
                    outputRect: Qt.rect(0, 0, dockRoot.width, dockRoot.height)
                    bodyRect: Qt.rect(
                        dockMouseArea.x + dockBackground.x + dockConnectedBody.x,
                        dockMouseArea.y + dockBackground.y + dockConnectedBody.y,
                        dockConnectedBody.width,
                        dockConnectedBody.height)
                    bodyRadius: dockVisualBackground.radius
                    fillColor: dockVisualBackground.abyssFillColor
                    borderColor: dockVisualBackground.abyssBorderColor
                    borderWidth: dockVisualBackground.abyssBorderWidth
                    progress: 1
                    shadowEnabled: dockRoot.screenEdgeShadowEnabled
                        && dockRoot.screenEdgeShadowSize > 0
                        && dockRoot.screenEdgeShadowOpacity > 0
                    shadowExtent: dockRoot.screenEdgeShadowSize
                    shadowColor: dockRoot.screenEdgeShadowColor
                }

                MouseArea {
                    id: dockMouseArea
                    z: 1
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton

                    width: root.isVertical
                        ? parent.width
                        : (dockBackground.implicitWidth + Appearance.sizes.elevationMargin * 2)
                    height: root.isVertical
                        ? (dockBackground.implicitHeight + Appearance.sizes.elevationMargin * 2)
                        : parent.height

                    anchors {
                        top: root.position === "bottom" ? parent.top : undefined
                        bottom: root.isTop ? parent.bottom : undefined
                        left: root.position === "right" ? parent.left : undefined
                        right: root.isLeft ? parent.right : undefined
                        horizontalCenter: !root.isVertical ? parent.horizontalCenter : undefined
                        verticalCenter: root.isVertical ? parent.verticalCenter : undefined
                    }

                    property real hideOffset: dockRoot.reveal
                        ? 0
                        : Config.options?.dock?.hoverToReveal
                            ? (dockRoot.implicitHeight - (Config.options?.dock?.hoverRegionHeight ?? 5))
                            : (dockRoot.implicitHeight + 1)
                    property real hideOffsetV: dockRoot.reveal
                        ? 0
                        : Config.options?.dock?.hoverToReveal
                            ? (dockRoot.implicitWidth - (Config.options?.dock?.hoverRegionHeight ?? 5))
                            : (dockRoot.implicitWidth + 1)

                    anchors.topMargin: root.position === "bottom" ? hideOffset : 0
                    anchors.bottomMargin: root.isTop ? hideOffset : 0
                    anchors.leftMargin: root.position === "right" ? hideOffsetV : 0
                    anchors.rightMargin: root.isLeft ? hideOffsetV : 0

                    Behavior on anchors.topMargin {
                        enabled: Appearance.animationsEnabled
                        animation: NumberAnimation {
                            duration: SurfaceMotion.duration
                            easing.type: SurfaceMotion.easingType
                        }
                    }
                    Behavior on anchors.bottomMargin {
                        enabled: Appearance.animationsEnabled
                        animation: NumberAnimation {
                            duration: SurfaceMotion.duration
                            easing.type: SurfaceMotion.easingType
                        }
                    }
                    Behavior on anchors.leftMargin {
                        enabled: Appearance.animationsEnabled
                        animation: NumberAnimation {
                            duration: SurfaceMotion.duration
                            easing.type: SurfaceMotion.easingType
                        }
                    }
                    Behavior on anchors.rightMargin {
                        enabled: Appearance.animationsEnabled
                        animation: NumberAnimation {
                            duration: SurfaceMotion.duration
                            easing.type: SurfaceMotion.easingType
                        }
                    }

                    Item {
                        id: dockHoverRegion
                        anchors.fill: parent

                        Item {
                            id: dockBackground
                            z: 2

                            layer.enabled: Appearance.shouldDesaturate("dock") && dockBackground.visible
                            layer.effect: ShellDesaturationEffect {}

                            anchors {
                                top: !root.isVertical ? parent.top : undefined
                                bottom: !root.isVertical ? parent.bottom : undefined
                                left: root.isVertical ? parent.left : undefined
                                right: root.isVertical ? parent.right : undefined
                                horizontalCenter: !root.isVertical ? parent.horizontalCenter : undefined
                                verticalCenter: root.isVertical ? parent.verticalCenter : undefined
                            }

                            implicitWidth: root.isVertical
                                ? (dockRoot.width - Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut)
                                : (dockRow.implicitWidth + 10)
                            implicitHeight: root.isVertical
                                ? (dockColumn.implicitHeight + 10)
                                : (dockRoot.height - Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut)
                            width: implicitWidth
                            height: implicitHeight

                            // Single connected-body geometry, mirroring the
                            // screenshot controls: one resting rect ends exactly
                            // at the Screen Edge inner boundary. The visual plate
                            // and Abyss field both consume this same item.
                            Item {
                                id: dockConnectedBody
                                anchors.fill: parent
                                anchors.topMargin: root.isTop
                                    ? dockRoot.screenEdgeThickness
                                    : (root.isVertical ? 0 : Appearance.sizes.elevationMargin)
                                anchors.bottomMargin: root.position === "bottom"
                                    ? dockRoot.screenEdgeThickness
                                    : (root.isVertical ? 0 : Appearance.sizes.elevationMargin)
                                anchors.leftMargin: root.isLeft
                                    ? dockRoot.screenEdgeThickness
                                    : (root.isVertical ? Appearance.sizes.elevationMargin : 0)
                                anchors.rightMargin: root.position === "right"
                                    ? dockRoot.screenEdgeThickness
                                    : (root.isVertical ? Appearance.sizes.elevationMargin : 0)
                            }

                            Rectangle {
                                id: dockVisualBackground
                                readonly property bool zzzGlassActive: root.zzzEverywhere
                                    && Appearance.effectsEnabled
                                    && (Config.options?.appearance?.zzz?.glass ?? true)
                                readonly property bool regaliaEverywhere:
                                    root.surfaceDialect === "regalia"
                                readonly property bool angelEverywhere:
                                    root.surfaceDialect === "angel"
                                readonly property bool auroraEverywhere:
                                    root.surfaceDialect === "aurora" || angelEverywhere
                                readonly property bool alisEverywhere:
                                    root.surfaceDialect === "alis"
                                readonly property bool gameModeMinimal:
                                    Appearance.gameModeMinimal
                                // In dark non-glass Material/Alis presentation, use
                                // the same base surface token as the physical Screen
                                // Edge so the joined seam cannot read as two colors.
                                readonly property bool matchDarkPhysicalEdge:
                                    Appearance.m3colors.darkmode
                                    && !auroraEverywhere
                                    && !root.zzzEverywhere
                                    && !regaliaEverywhere
                                // The Abyss field owns the connected silhouette. Some
                                // dialect-specific body plates intentionally use a
                                // transparent Rectangle base, so expose the effective
                                // shell paint separately instead of making the weld
                                // disappear while the body remains visible.
                                readonly property color abyssFillColor: root.zzzEverywhere
                                    ? ColorUtils.applyAlpha(
                                        Appearance.zzz.chromeAlt,
                                        zzzGlassActive
                                            ? (Appearance.zzz.dark ? 0.66 : 0.72)
                                            : 1)
                                    : regaliaEverywhere
                                        ? Appearance.regalia.barSurfaceFloating
                                        : color
                                readonly property color abyssBorderColor: root.zzzEverywhere
                                    ? Appearance.zzz.hairline
                                    : regaliaEverywhere
                                        ? "transparent"
                                        : border.color
                                readonly property real abyssBorderWidth: root.zzzEverywhere
                                    ? 1
                                    : regaliaEverywhere ? 0 : border.width
                                readonly property string wallpaperUrl: {
                                    const _dep1 = WallpaperListener.multiMonitorEnabled
                                    const _dep2 = WallpaperListener.effectivePerMonitor
                                    const _dep3 = Wallpapers.effectiveWallpaperUrl
                                    return WallpaperListener.wallpaperUrlForScreen(dockRoot.screen)
                                }

                                ColorQuantizer {
                                    id: dockWallpaperQuantizer
                                    source: dockVisualBackground.auroraEverywhere
                                        ? dockVisualBackground.wallpaperUrl : ""
                                    depth: 0
                                    rescaleSize: 10
                                }

                                readonly property color wallpaperDominantColor:
                                    dockWallpaperQuantizer?.colors?.[0] ?? Appearance.colors.colPrimary
                                readonly property QtObject blendedColors: AdaptedMaterialScheme {
                                    color: ColorUtils.mix(
                                        dockVisualBackground.wallpaperDominantColor,
                                        Appearance.colors.colPrimaryContainer,
                                        0.8) || Appearance.colors.colSecondaryContainer
                                }

                                anchors.fill: dockConnectedBody

                                visible: (Config.options?.dock?.showBackground ?? true)
                                    && !gameModeMinimal
                                color: root.zzzEverywhere || regaliaEverywhere
                                    ? "transparent"
                                    : auroraEverywhere
                                        ? ColorUtils.applyAlpha(
                                            (blendedColors?.colLayer0
                                                ?? Appearance.colors.colLayer0),
                                            dockRoot.nativeBlurActive ? 0.46 : 1)
                                        : alisEverywhere
                                            ? (matchDarkPhysicalEdge
                                                ? Appearance.colors.colLayer0
                                                : Appearance.alis.colLayer1)
                                            : Appearance.colors.colLayer0
                                border.width: root.zzzEverywhere || regaliaEverywhere
                                    ? 0
                                    : angelEverywhere
                                        ? Appearance.angel.panelBorderWidth : 0
                                border.color: root.zzzEverywhere || regaliaEverywhere
                                    ? "transparent"
                                    : angelEverywhere
                                        ? Appearance.angel.colPanelBorder
                                        : alisEverywhere
                                            ? Appearance.alis.colBorder
                                            : Appearance.colors.colLayer0Border
                                radius: root.zzzEverywhere
                                    ? Appearance.zzz.panelRadius
                                    : regaliaEverywhere
                                        ? Appearance.regalia.roundLarge
                                        : angelEverywhere
                                            ? Appearance.angel.roundingNormal
                                            : alisEverywhere
                                                ? Appearance.alis.roundingNormal
                                                : Appearance.rounding.large
                                // Keep the body plate on the same rounded
                                // rectangle as the Abyss SDF record. Squaring the
                                // edge-facing corners here overpaints the smooth
                                // union fillets and makes Dock read as a detached
                                // island even though the SDF weld is present.

                                Behavior on color {
                                    enabled: Appearance.animationsEnabled
                                    ColorAnimation {
                                        duration: Appearance.animation.elementMoveFast.duration
                                        easing.type: Appearance.animation.elementMoveFast.type
                                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                    }
                                }
                                Behavior on border.width {
                                    enabled: Appearance.animationsEnabled
                                    NumberAnimation {
                                        duration: Appearance.animation.elementMoveFast.duration
                                        easing.type: Appearance.animation.elementMoveFast.type
                                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                    }
                                }
                                Behavior on border.color {
                                    enabled: Appearance.animationsEnabled
                                    ColorAnimation {
                                        duration: Appearance.animation.elementMoveFast.duration
                                        easing.type: Appearance.animation.elementMoveFast.type
                                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                    }
                                }

                                RegaliaPlate {
                                    anchors.fill: parent
                                    visible: dockVisualBackground.regaliaEverywhere
                                    fillColor: Appearance.regalia.barSurfaceFloating
                                    radius: dockVisualBackground.radius
                                    inset: Appearance.regalia.surfaceInset
                                    deepFrame: true
                                    glassEnabled: true
                                }

                                ZzzPlate {
                                    anchors.fill: parent
                                    z: -1
                                    visible: root.zzzEverywhere
                                    chamfer: Appearance.zzz.cutCorner
                                    chamferBottomRight: true
                                    chamferTopRight: false
                                    fillColor: dockVisualBackground.zzzGlassActive
                                        ? "transparent"
                                        : Appearance.zzz.chromeAlt
                                    strokeColor: Appearance.zzz.hairline
                                    strokeWidth: 1
                                }

                                ZzzGlassWash {
                                    anchors.fill: parent
                                    z: -2
                                    maskRadius: Appearance.zzz.round
                                        ? dockVisualBackground.radius : 0
                                    chamfer: Appearance.zzz.cutCorner
                                    chamferTopRight: false
                                    chamferBottomRight: true
                                    glassEnabled: dockVisualBackground.zzzGlassActive
                                    selfBacked: true
                                    veilAlpha: Appearance.zzz.dark ? 0.66 : 0.72
                                }

                                clip: true
                                layer.enabled: auroraEverywhere
                                    && !alisEverywhere
                                    && !root.zzzEverywhere
                                    && !gameModeMinimal
                                    && !dockRoot.nativeBlurActive
                                layer.effect: GE.OpacityMask {
                                    maskSource: Rectangle {
                                        width: dockVisualBackground.width
                                        height: dockVisualBackground.height
                                        radius: dockVisualBackground.radius
                                    }
                                }

                                Image {
                                    id: dockBlurredWallpaper
                                    x: root.isVertical
                                        ? (root.isLeft
                                            ? 0
                                            : (-(dockRoot.screen?.width ?? 1920)
                                                + dockVisualBackground.width
                                                + Appearance.sizes.hyprlandGapsOut))
                                        : (-(dockRoot.screen?.width ?? 1920) / 2
                                            + dockVisualBackground.width / 2)
                                    y: root.isVertical
                                        ? (-(dockRoot.screen?.height ?? 1080) / 2
                                            + dockVisualBackground.height / 2)
                                        : (root.isTop
                                            ? 0
                                            : (-(dockRoot.screen?.height ?? 1080)
                                                + dockVisualBackground.height
                                                + Appearance.sizes.hyprlandGapsOut))
                                    width: dockRoot.screen?.width ?? 1920
                                    height: dockRoot.screen?.height ?? 1080
                                    visible: dockVisualBackground.auroraEverywhere
                                        && !dockVisualBackground.alisEverywhere
                                        && !root.zzzEverywhere
                                        && !dockVisualBackground.gameModeMinimal
                                        && !dockRoot.nativeBlurActive
                                    source: visible ? dockVisualBackground.wallpaperUrl : ""
                                    fillMode: Image.PreserveAspectCrop
                                    cache: true
                                    sourceSize.width: dockRoot.screen?.width ?? 1920
                                    sourceSize.height: dockRoot.screen?.height ?? 1080
                                    asynchronous: true

                                    layer.enabled: Appearance.effectsEnabled
                                        && dockVisualBackground.auroraEverywhere
                                        && !dockVisualBackground.alisEverywhere
                                        && !dockVisualBackground.gameModeMinimal
                                        && !dockRoot.nativeBlurActive
                                    layer.effect: MultiEffect {
                                        source: dockBlurredWallpaper
                                        anchors.fill: source
                                        saturation: dockVisualBackground.angelEverywhere
                                            ? (Appearance.angel.blurSaturation
                                                * Appearance.angel.colorStrength)
                                            : (Appearance.effectsEnabled ? 0.2 : 0)
                                        blurEnabled: Appearance.effectsEnabled
                                        blurMax: 64
                                        blur: Appearance.effectsEnabled
                                            ? (dockVisualBackground.angelEverywhere
                                                ? Appearance.angel.blurIntensity : 1)
                                            : 0
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        color: dockVisualBackground.angelEverywhere
                                            ? ColorUtils.transparentize(
                                                (dockVisualBackground.blendedColors?.colLayer0
                                                    ?? Appearance.colors.colLayer0Base),
                                                Appearance.angel.overlayOpacity
                                                    * Appearance.angel.panelTransparentize)
                                            : ColorUtils.transparentize(
                                                (dockVisualBackground.blendedColors?.colLayer0
                                                    ?? Appearance.colors.colLayer0Base),
                                                Appearance.aurora.overlayTransparentize)
                                    }
                                }

                                AngelPartialBorder {
                                    visible: dockVisualBackground.angelEverywhere
                                    targetRadius: dockVisualBackground.radius
                                }
                            }

                            RowLayout {
                                id: dockRow
                                visible: !root.isVertical
                                anchors.centerIn: dockVisualBackground
                                spacing: root.zzzEverywhere ? 5 : 2
                                property real padding: root.zzzEverywhere ? 7 : 5

                                DockApps {
                                    id: dockApps
                                    enabled: !root.isVertical
                                    vertical: false
                                    dockPosition: root.position
                                    parentWindow: dockRoot
                                }
                                DockButton {
                                    visible: Config.options?.dock?.showDashboardButton ?? true
                                    vertical: false
                                    onClicked: GlobalStates.toggleOverview(
                                        dockRoot.screen?.name ?? "")
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        font.pixelSize: parent.width * 0.5
                                        text: "apps"
                                        color: root.zzzEverywhere
                                            ? Appearance.zzz.ink
                                            : Appearance.colors.colOnLayer0
                                        Behavior on color {
                                            enabled: Appearance.animationsEnabled
                                            ColorAnimation {
                                                duration: Appearance.animation.elementMoveFast.duration
                                                easing.type: Appearance.animation.elementMoveFast.type
                                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                            }
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                id: dockColumn
                                visible: root.isVertical
                                anchors.centerIn: dockVisualBackground
                                spacing: root.zzzEverywhere ? 5 : 2
                                property real padding: root.zzzEverywhere ? 7 : 5

                                DockApps {
                                    id: dockAppsVertical
                                    enabled: root.isVertical
                                    vertical: true
                                    dockPosition: root.position
                                    parentWindow: dockRoot
                                }
                                DockButton {
                                    visible: Config.options?.dock?.showDashboardButton ?? true
                                    vertical: true
                                    onClicked: GlobalStates.toggleOverview(
                                        dockRoot.screen?.name ?? "")
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        font.pixelSize: parent.width * 0.5
                                        text: "apps"
                                        color: root.zzzEverywhere
                                            ? Appearance.zzz.ink
                                            : Appearance.colors.colOnLayer0
                                        Behavior on color {
                                            enabled: Appearance.animationsEnabled
                                            ColorAnimation {
                                                duration: Appearance.animation.elementMoveFast.duration
                                                easing.type: Appearance.animation.elementMoveFast.type
                                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ShellEditSurfaceFrame {
                        id: dockEditFrame
                        readonly property Item visualTarget:
                            dockRoot.nativeBlurItem ?? dockBackground
                        x: Math.round(dockBackground.x + visualTarget.x)
                        y: Math.round(dockBackground.y + visualTarget.y)
                        width: Math.round(visualTarget.width)
                        height: Math.round(visualTarget.height)
                        surfaceId: "iiDock"
                        label: Translation.tr("Dock")
                        active: ShellEditSession.blocksNormalActions(surfaceId)
                        selected: ShellEditSession.selectedSurfaceId === surfaceId
                        lifted: ShellEditSession.liftedSurfaceId === surfaceId
                        slotHint: Config.options?.dock?.position ?? "bottom"
                        screenWidth: dockRoot.screen?.width ?? 0
                        screenHeight: dockRoot.screen?.height ?? 0
                        onDragStarted: surface => ShellEditSession.beginDrag(surface)
                        onDragMoved: (surface, screenX, screenY) =>
                            ShellEditSession.updateDrag(screenX, screenY)
                        onDragEnded: () => ShellEditSession.endDrag()
                        onDragCanceled: () => ShellEditSession.cancelDrag()
                        accentColor: Appearance.colors.colPrimary
                        surfaceColor: Appearance.colors.colLayer2
                        textColor: Appearance.colors.colOnLayer2
                        frameRadius: Appearance.rounding.small
                        fontFamily: Appearance.font.family.main
                        fontPixelSize: Appearance.font.pixelSize.smaller
                        animationDuration: Appearance.animationsEnabled
                            ? Appearance.animation.elementMoveFast.duration : 0
                        onActivated: surface => ShellEditSession.selectSurface(surface)
                    }

                    ShellEditResizeHandle {
                        z: 11000
                        width: root.isVertical ? 20 : 96
                        height: root.isVertical ? 96 : 20
                        anchors {
                            horizontalCenter: root.isVertical
                                ? (root.isLeft ? dockEditFrame.right : dockEditFrame.left)
                                : dockEditFrame.horizontalCenter
                            verticalCenter: root.isVertical
                                ? dockEditFrame.verticalCenter
                                : (root.isTop ? dockEditFrame.bottom : dockEditFrame.top)
                        }
                        axis: root.isVertical ? "horizontal" : "vertical"
                        active: ShellEditSession.active
                            && ShellEditSession.selectedSurfaceId === "iiDock"
                            && ShellEditSession.liftedSurfaceId.length === 0
                        accentColor: Appearance.colors.colPrimary
                        surfaceColor: Appearance.colors.colLayer2
                        animationsEnabled: Appearance.animationsEnabled
                        radius: Appearance.rounding.full
                        onDragStarted: dockRoot.beginDockResize()
                        onDragged: (axis, deltaX, deltaY) =>
                            dockRoot.updateDockResize(deltaX, deltaY)
                        onDragFinished: dockRoot.finishDockResize()
                        onDragCanceled: dockRoot.cancelDockResize()
                    }

                    ShellEditSizeBadge {
                        z: 12000
                        anchors.centerIn: dockEditFrame
                        active: dockRoot.editThicknessPreview >= 0
                        valueText: Math.round(dockRoot.dockHeight) + " px"
                        accentColor: Appearance.colors.colPrimary
                        surfaceColor: Appearance.colors.colLayer2
                        textColor: Appearance.colors.colOnLayer2
                        fontFamily: Appearance.font.family.main
                        fontPixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }
        }
    }

    // Work-area reservation is intentionally decoupled from Dock rendering.
    // Quickshell's exclusiveZone setter switches a layer surface back to
    // Normal exclusion; keeping it on a transparent Top-layer window lets the
    // visual Dock remain an Overlay/Ignore surface in physical-output space.
    Variants {
        model: {
            const screens = Quickshell.screens;
            const list = Config.options?.dock?.screenList ?? [];
            if (!list || list.length === 0)
                return screens;
            const matchedScreens = screens.filter(screen => {
                const screenName = screen?.name ?? "";
                return screenName.length > 0 && list.includes(screenName);
            });
            return matchedScreens.length > 0 ? matchedScreens : screens;
        }

        PanelWindow {
            id: dockReservationWindow
            required property var modelData

            readonly property bool horizontal:
                root.position === "top" || root.position === "bottom"
            readonly property real reservationThickness:
                Math.max(0, Number(Config.options?.dock?.height ?? 70)
                    + Appearance.sizes.elevationMargin)
            readonly property bool mapped:
                root.pinned
                && !GlobalStates.screenLocked
                && !GlobalStates.widgetEditMode

            screen: modelData
            visible: mapped
            updatesEnabled: mapped
            color: "transparent"

            // This window paints nothing. Its only responsibility is preserving
            // the Dock's existing pinned work-area reservation.
            exclusiveZone: mapped ? reservationThickness : 0
            implicitWidth: horizontal ? 1 : reservationThickness
            implicitHeight: horizontal ? reservationThickness : 1

            WlrLayershell.namespace: "quickshell:dock-reservation"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                top: root.position === "top"
                    || root.position === "left"
                    || root.position === "right"
                bottom: root.position === "bottom"
                    || root.position === "left"
                    || root.position === "right"
                left: root.position === "left"
                    || root.position === "top"
                    || root.position === "bottom"
                right: root.position === "right"
                    || root.position === "top"
                    || root.position === "bottom"
            }

            Item {
                id: emptyDockReservationInput
                width: 0
                height: 0
                visible: false
            }

            mask: Region {
                item: emptyDockReservationInput
            }
        }
    }

}
