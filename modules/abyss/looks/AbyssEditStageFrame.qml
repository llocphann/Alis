pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.services
import "root:modules/common/functions/md5.js" as MD5

// Renders the Overview/Hot-Corners-synced backdrop surround outside the shrunk
// Desktop Stage and smooth-unions (`fuse`) the outer Desktop Stage Abyss bezel
// with the external Customization Control Dock below it using AbyssStyle settings.
Item {
    id: root

    property var card: ({
        p: 0,
        x: 0,
        y: 0,
        width: width,
        height: height,
        cornerRadius: 0,
        bezel: 0,
        dockRadius: 34,
        dockX: 0,
        dockY: height,
        dockWidth: 0,
        dockHeight: 0
    })

    property bool warmBackdrop: false
    readonly property real progress: Math.max(0, Math.min(1, Number(root.card?.p ?? 0)))
    visible: root.progress > 0.001

    readonly property var screenObj: root.QsWindow.window?.screen ?? null
    readonly property string monitorName: WallpaperListener.getMonitorName(root.screenObj)
    readonly property var iiBackdrop: Config.options?.background?.backdrop ?? ({})

    readonly property bool useAuroraStyle: (root.iiBackdrop.useAuroraStyle ?? false) === true
    readonly property real auroraOverlayOpacity: Math.max(0, Math.min(1, Number(root.iiBackdrop.auroraOverlayOpacity ?? 0.38)))
    readonly property real backdropBlurRadius: root.useAuroraStyle
        ? (Appearance.effectsEnabled ? 64 : 0)
        : (Appearance.effectsEnabled ? Math.max(0, Math.min(100, Number(root.iiBackdrop.blurRadius ?? 32))) : 0)
    readonly property real backdropDim: root.useAuroraStyle
        ? 0
        : (Math.max(0, Math.min(100, Number(root.iiBackdrop.dim ?? 35))) / 100.0)
    readonly property real backdropSaturation: root.useAuroraStyle
        ? (Appearance.angelEverywhere ? Appearance.angel.blurSaturation : (Appearance.effectsEnabled ? 0.2 : 0))
        : Math.max(-1, Math.min(1, Number(root.iiBackdrop.saturation ?? 0)))
    readonly property real backdropContrast: root.useAuroraStyle
        ? 0
        : Math.max(-1, Math.min(1, Number(root.iiBackdrop.contrast ?? 0)))
    readonly property bool vignetteEnabled: (root.iiBackdrop.vignetteEnabled ?? false) === true
    readonly property real vignetteIntensity: Math.max(0, Math.min(1, Number(root.iiBackdrop.vignetteIntensity ?? 0.5)))
    readonly property real vignetteRadius: Math.max(0, Math.min(0.99, Number(root.iiBackdrop.vignetteRadius ?? 0.7)))
    readonly property bool fitWallpaper: (root.iiBackdrop.fillMode ?? "fill") === "fit"

    function _pathToSafeImageUrl(rawPath: string): string {
        const clean = FileUtils.trimFileProtocol(String(rawPath ?? ""));
        if (!clean)
            return "";
        if (Wallpapers.isVideoFile(clean)) {
            void Wallpapers.videoFirstFrames;
            const ff = Wallpapers.getVideoFirstFramePath(clean);
            if (ff) {
                const cleanFf = FileUtils.trimFileProtocol(ff);
                return "file://" + cleanFf.split("/").map(seg => encodeURIComponent(seg)).join("/") + "?ff=1";
            }
            const expected = Wallpapers._videoThumbDir + "/" + MD5.hash(clean) + ".jpg";
            Wallpapers.ensureVideoFirstFrame(clean);
            return "file://" + expected.split("/").map(seg => encodeURIComponent(seg)).join("/") + "?ff=0";
        }
        return "file://" + clean.split("/").map(seg => encodeURIComponent(seg)).join("/");
    }

    readonly property string wallpaperUrl: {
        if (!root.visible && !root.warmBackdrop)
            return "";
        if (Wallpapers.internalPreviewActive && Wallpapers.internalPreviewPath.length > 0
                && (Wallpapers.internalPreviewMonitor.length === 0 || Wallpapers.internalPreviewMonitor === root.monitorName)) {
            return root._pathToSafeImageUrl(Wallpapers.internalPreviewPath);
        }
        if (!(root.iiBackdrop.useMainWallpaper ?? true)) {
            if (WallpaperListener.multiMonitorEnabled && root.monitorName.length > 0) {
                const monData = WallpaperListener.effectivePerMonitor[root.monitorName] ?? null;
                if (monData && monData.backdropPath)
                    return root._pathToSafeImageUrl(monData.backdropPath);
            }
            const globalBd = String(root.iiBackdrop.wallpaperPath ?? "");
            if (globalBd.length > 0)
                return root._pathToSafeImageUrl(globalBd);
        }
        return WallpaperListener.wallpaperUrlForScreen(root.screenObj);
    }
    readonly property int decodeWidth: root.backdropBlurRadius > 12 ? 640 : 1280
    readonly property int decodeHeight: root.backdropBlurRadius > 12 ? 360 : 720

    property int _activeSlot: 0
    property string _displayedUrl: ""
    property string _pendingUrl: ""
    property real _wallMix: 0

    readonly property var activeWallpaperImage: root._activeSlot === 0 ? wallpaperImage0 : wallpaperImage1
    readonly property var nextWallpaperImage: root._activeSlot === 0 ? wallpaperImage1 : wallpaperImage0
    readonly property bool wallpaperReady: activeWallpaperImage.status === Image.Ready
    readonly property bool nextWallpaperReady: nextWallpaperImage.status === Image.Ready
    readonly property bool transitionsEnabled: Appearance.animationsEnabled
        && (Config.options?.background?.transition?.enable ?? true)
        && String(Config.options?.background?.transition?.type ?? "crossfade") !== "none"
    readonly property var _configuredBezier: Config.options?.background?.transition?.bezier ?? [0.54, 0.0, 0.34, 0.99]
    readonly property list<real> _transitionBezierCurve: [
        Number(_configuredBezier?.[0] ?? 0.54) || 0,
        Number(_configuredBezier?.[1] ?? 0.0) || 0,
        Number(_configuredBezier?.[2] ?? 0.34) || 0,
        Number(_configuredBezier?.[3] ?? 0.99) || 0,
        1, 1
    ]
    property int _transMode: 0
    property real _transOriginX: 0.5
    property real _transOriginY: 0.5
    property real _transAngleRad: 0.0
    property int _transDurationMs: Appearance.calcEffectiveDuration(
        Config.options?.background?.transition?.duration ?? 800
    )

    function _modeNumberForType(rawType: string, targetPath: string): int {
        const t = String(rawType ?? "crossfade");
        if (t === "wallfx")
            return Wallpapers.isFavourite(targetPath) ? 6 : 1;
        if (t === "alisMelt" || t === "inirMelt" || t === "shaderRandom")
            return 1;
        if (t === "grow" || t === "center" || t === "any")
            return 2;
        if (t === "outer")
            return 3;
        if (t === "wave")
            return 4;
        if (t === "wipe" || t === "slide" || t === "push"
                || t === "left" || t === "right" || t === "top" || t === "bottom")
            return 5;
        return 0;
    }

    function _angleForDirection(dir: string): real {
        switch (String(dir ?? "right")) {
        case "left": return Math.PI;
        case "top": return Math.PI * 0.5;
        case "bottom": return Math.PI * 1.5;
        default: return 0.0;
        }
    }

    function _syncActiveTransitionParams(targetUrl: string): void {
        const cleanPath = FileUtils.trimFileProtocol(String(targetUrl ?? ""));
        const meta = Wallpapers.activeTransitionMeta;
        const baseDur = Appearance.calcEffectiveDuration(
            Config.options?.background?.transition?.duration ?? 800
        );
        if (meta && String(meta.source ?? "") === cleanPath && String(meta.type ?? "").length > 0) {
            root._transMode = root._modeNumberForType(meta.type, cleanPath);
            root._transOriginX = Number.isFinite(Number(meta.originX)) ? Number(meta.originX) : 0.5;
            root._transOriginY = Number.isFinite(Number(meta.originY)) ? Number(meta.originY) : 0.5;
            root._transAngleRad = Number.isFinite(Number(meta.angleRad)) ? Number(meta.angleRad) : root._angleForDirection(meta.direction);
            root._transDurationMs = Math.max(120, Number(meta.durationMs) || baseDur);
            return;
        }
        let cfgType = String(Config.options?.background?.transition?.type ?? "crossfade");
        if (cfgType === "random") {
            const pool = ["alisMelt", "wipe", "wave", "grow", "center", "outer", "any", "fade"];
            cfgType = pool[Math.floor(Math.random() * pool.length)];
        }
        const cfgDir = ["left", "right", "top", "bottom"].includes(cfgType)
            ? cfgType
            : String(Config.options?.background?.transition?.direction ?? "right");
        root._transMode = root._modeNumberForType(cfgType, cleanPath);
        if (cfgType === "any") {
            root._transOriginX = 0.15 + Math.random() * 0.7;
            root._transOriginY = 0.15 + Math.random() * 0.7;
        } else {
            root._transOriginX = 0.5;
            root._transOriginY = 0.5;
        }
        root._transAngleRad = root._angleForDirection(cfgDir);
        root._transDurationMs = root._transMode === 6
            ? Math.max(baseDur, Appearance.calcEffectiveDuration(1650))
            : baseDur;
    }

    function _cropForImage(imgItem): vector4d {
        const imageAspect = Math.max(1, imgItem.implicitWidth) / Math.max(1, imgItem.implicitHeight);
        const viewAspect = Math.max(1, root.width) / Math.max(1, root.height);
        if (root.fitWallpaper) {
            const fitX = Math.max(1, viewAspect / Math.max(0.001, imageAspect));
            const fitY = Math.max(1, imageAspect / Math.max(0.001, viewAspect));
            return Qt.vector4d((1 - fitX) / 2, (1 - fitY) / 2, fitX, fitY);
        }
        const xScale = Math.min(1, viewAspect / Math.max(0.001, imageAspect));
        const yScale = Math.min(1, imageAspect / Math.max(0.001, viewAspect));
        return Qt.vector4d((1 - xScale) / 2, (1 - yScale) / 2, xScale, yScale);
    }

    function _loadNextPending(): void {
        if (wallMixAnim.running)
            return;
        const target = String(root._pendingUrl ?? "");
        if (!target || target === root._displayedUrl) {
            root._pendingUrl = "";
            return;
        }
        if (root._displayedUrl === "" || !root.wallpaperReady) {
            const activeImg = root.activeWallpaperImage;
            if (String(activeImg.source) === target && activeImg.status === Image.Ready) {
                root._displayedUrl = target;
                root._pendingUrl = "";
                return;
            }
            activeImg.source = target;
            return;
        }
        const nextImg = root.nextWallpaperImage;
        if (String(nextImg.source) === target && nextImg.status === Image.Ready) {
            root._beginBackdropCrossfade();
            return;
        }
        nextImg.source = target;
    }

    function _beginBackdropCrossfade(): void {
        if (root.nextWallpaperImage.status !== Image.Ready)
            return;
        if (!root.transitionsEnabled || !root.visible) {
            root._finishBackdropCrossfade();
            return;
        }
        root._syncActiveTransitionParams(String(root.nextWallpaperImage.source));
        root._wallMix = 0;
        wallMixAnim.restart();
    }

    function _finishBackdropCrossfade(): void {
        wallMixAnim.stop();
        const prevImg = root.activeWallpaperImage;
        const nextImg = root.nextWallpaperImage;
        if (nextImg.status === Image.Ready) {
            root._activeSlot = root._activeSlot === 0 ? 1 : 0;
            root._displayedUrl = String(nextImg.source);
        }
        root._wallMix = 0;
        if (root._pendingUrl === root._displayedUrl)
            root._pendingUrl = "";
        if (root._pendingUrl === "")
            prevImg.source = "";
        else
            Qt.callLater(root._loadNextPending);
    }

    onWallpaperUrlChanged: {
        const url = String(root.wallpaperUrl ?? "");
        if (!url) {
            wallMixAnim.stop();
            root._wallMix = 0;
            root._displayedUrl = "";
            root._pendingUrl = "";
            wallpaperImage0.source = "";
            wallpaperImage1.source = "";
            root._activeSlot = 0;
            return;
        }
        if (wallMixAnim.running && url !== String(root.nextWallpaperImage.source)) {
            wallMixAnim.stop();
            if (root._wallMix >= 0.5 && root.nextWallpaperReady) {
                root._activeSlot = root._activeSlot === 0 ? 1 : 0;
                root._displayedUrl = String(root.activeWallpaperImage.source);
            }
            root._wallMix = 0;
        }
        root._pendingUrl = url;
        root._loadNextPending();
    }

    Component.onCompleted: {
        if (root.wallpaperUrl) {
            root._pendingUrl = String(root.wallpaperUrl);
            root._loadNextPending();
        }
    }

    NumberAnimation {
        id: wallMixAnim
        target: root
        property: "_wallMix"
        from: 0
        to: 1
        duration: Math.max(120, root._transDurationMs)
        easing.type: root._transMode === 6 ? Easing.Linear : Easing.BezierSpline
        easing.bezierCurve: root._transitionBezierCurve
        onFinished: root._finishBackdropCrossfade()
    }

    Image {
        id: wallpaperImage0
        visible: false
        asynchronous: true
        cache: false
        smooth: true
        sourceSize: Qt.size(root.decodeWidth, root.decodeHeight)
        onStatusChanged: {
            if (status === Image.Ready) {
                if (root._activeSlot === 0 && root._displayedUrl === "") {
                    root._displayedUrl = String(source);
                    if (root._pendingUrl === root._displayedUrl)
                        root._pendingUrl = "";
                    else if (root._pendingUrl !== "")
                        Qt.callLater(root._loadNextPending);
                } else if (root._activeSlot === 1 && String(source) === root._pendingUrl && !wallMixAnim.running) {
                    Qt.callLater(root._beginBackdropCrossfade);
                }
            }
        }
    }

    Image {
        id: wallpaperImage1
        visible: false
        asynchronous: true
        cache: false
        smooth: true
        sourceSize: Qt.size(root.decodeWidth, root.decodeHeight)
        onStatusChanged: {
            if (status === Image.Ready) {
                if (root._activeSlot === 1 && root._displayedUrl === "") {
                    root._displayedUrl = String(source);
                    if (root._pendingUrl === root._displayedUrl)
                        root._pendingUrl = "";
                    else if (root._pendingUrl !== "")
                        Qt.callLater(root._loadNextPending);
                } else if (root._activeSlot === 0 && String(source) === root._pendingUrl && !wallMixAnim.running) {
                    Qt.callLater(root._beginBackdropCrossfade);
                }
            }
        }
    }

    Rectangle {
        id: emptyWallpaperTex
        width: 2
        height: 2
        visible: false
        color: "#0b0f16"
        layer.enabled: true
    }

    ShaderEffect {
        id: pass
        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("AbyssEditStageFrame.frag.qsb")

        readonly property vector4d viewport: Qt.vector4d(
            Math.max(1, root.width),
            Math.max(1, root.height),
            root.progress,
            root.wallpaperReady ? 1 : 0
        )

        readonly property vector4d stageRect: Qt.vector4d(
            Number(root.card?.x ?? 0),
            Number(root.card?.y ?? 0),
            Math.max(1, Number(root.card?.width ?? root.width)),
            Math.max(1, Number(root.card?.height ?? root.height))
        )

        readonly property vector4d dockRect: {
            const stageBottom = Number(root.card?.y ?? 0) + Number(root.card?.height ?? root.height);
            const bezel = Number(root.card?.bezel ?? 0);
            const dockW = Number(root.card?.dockWidth ?? 0);
            const dockH = Number(root.card?.dockHeight ?? 0);
            const dockY = Number(root.card?.dockY ?? (stageBottom + bezel));
            if (dockW <= 0 || dockH <= 0)
                return Qt.vector4d(0, 0, 0, 0);
            const gap = Math.max(0, dockY - (stageBottom + bezel));
            const weld = Math.max(0, Math.min(1, 1 - gap / 28.0)) * root.progress;
            const overlap = (bezel + 32) * weld;
            return Qt.vector4d(
                Number(root.card?.dockX ?? 0),
                dockY - overlap,
                dockW,
                dockH + overlap
            );
        }

        readonly property vector4d leftDockRect: {
            const stageLeft = Number(root.card?.x ?? 0);
            const bezel = Number(root.card?.bezel ?? 0);
            const leftW = Number(root.card?.leftDockWidth ?? 0);
            const leftH = Number(root.card?.leftDockHeight ?? 0);
            const leftP = Number(root.card?.leftProgress ?? 0);
            const leftX = Number(root.card?.leftDockX ?? (-leftW - 12));
            if (leftW <= 0 || leftH <= 0 || leftP <= 0.001)
                return Qt.vector4d(0, 0, 0, 0);
            const gap = Math.max(0, (stageLeft - bezel) - (leftX + leftW));
            const weld = Math.max(0, Math.min(1, 1 - gap / 28.0)) * Math.min(root.progress, leftP);
            const overlap = (bezel + 32) * weld;
            return Qt.vector4d(
                leftX,
                Number(root.card?.leftDockY ?? 0),
                leftW + overlap,
                leftH
            );
        }

        readonly property vector4d rightDockRect: {
            const stageRight = Number(root.card?.x ?? 0) + Number(root.card?.width ?? root.width);
            const bezel = Number(root.card?.bezel ?? 0);
            const rightW = Number(root.card?.rightDockWidth ?? 0);
            const rightH = Number(root.card?.rightDockHeight ?? 0);
            const rightP = Number(root.card?.rightProgress ?? 0);
            const rightX = Number(root.card?.rightDockX ?? (root.width + 12));
            if (rightW <= 0 || rightH <= 0 || rightP <= 0.001)
                return Qt.vector4d(0, 0, 0, 0);
            const gap = Math.max(0, rightX - (stageRight + bezel));
            const weld = Math.max(0, Math.min(1, 1 - gap / 28.0)) * Math.min(root.progress, rightP);
            const overlap = (bezel + 32) * weld;
            return Qt.vector4d(
                rightX - overlap,
                Number(root.card?.rightDockY ?? 0),
                rightW + overlap,
                rightH
            );
        }

        readonly property vector4d shapeParams: Qt.vector4d(
            Number(root.card?.cornerRadius ?? 0),
            Number(root.card?.bezel ?? 0),
            Number(root.card?.dockRadius ?? AbyssStyle.perimeterRadius),
            AbyssStyle.connectionDepth * root.progress
        )

        // (highlightStrength, refractionStrength, backdropBlurTexels, dockBlurTexels)
        readonly property vector4d materialParams: Qt.vector4d(
            AbyssStyle.highlightStrength,
            AbyssStyle.refractionStrength,
            (root.backdropBlurRadius / 100.0) * 14.0,
            (AbyssStyle.contentBlurRadius / 24.0) * 9.0
        )

        // (dim 0..1, saturation -1..1, contrast -1..1, fitMode 0|1)
        readonly property vector4d backdropTone: Qt.vector4d(
            root.backdropDim,
            root.backdropSaturation,
            root.backdropContrast,
            root.fitWallpaper ? 1.0 : 0.0
        )

        // (vignetteIntensity, vignetteRadius, auroraOverlayAlpha, texWidth)
        readonly property vector4d backdropVignette: Qt.vector4d(
            root.vignetteEnabled ? root.vignetteIntensity : 0.0,
            root.vignetteRadius,
            root.useAuroraStyle ? (1.0 - root.auroraOverlayOpacity) : 0.0,
            Math.max(1, root.activeWallpaperImage.implicitWidth)
        )

        readonly property vector4d wallpaperCrop: root._cropForImage(root.activeWallpaperImage)
        readonly property vector4d wallpaperNextCrop: root._cropForImage(root.nextWallpaperImage)
        readonly property vector4d wallpaperTransition: Qt.vector4d(
            root._wallMix,
            root.nextWallpaperReady ? 1.0 : 0.0,
            Math.max(1, root.nextWallpaperImage.implicitWidth),
            root._transMode
        )
        readonly property vector4d transitionParams: Qt.vector4d(
            root._transOriginX,
            root._transOriginY,
            root._transAngleRad,
            root._wallMix * (Math.max(120, root._transDurationMs) / 1000.0)
        )

        readonly property var wallpaper: root.wallpaperReady ? root.activeWallpaperImage : emptyWallpaperTex
        readonly property var wallpaperNext: root.nextWallpaperReady
            ? root.nextWallpaperImage
            : (root.wallpaperReady ? root.activeWallpaperImage : emptyWallpaperTex)
        readonly property color surface: Qt.alpha(AbyssStyle.surfaceDeep, AbyssStyle.surfaceOpacity)
        readonly property color dockSurface: Qt.alpha(AbyssStyle.surfaceDeep, AbyssStyle.contentOpacity)
        readonly property color raised: AbyssStyle.surfaceRaised
        readonly property color rim: AbyssStyle.specular
        readonly property color shadow: AbyssStyle.shadow
        readonly property color glow: AbyssStyle.glow
        readonly property color auroraBase: Appearance.colors.colLayer0Base

        onStatusChanged: {
            if (status === ShaderEffect.Error)
                console.error("[AbyssEditStageFrame]", log);
        }
    }
}
