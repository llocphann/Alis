pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.perimeter
import qs.modules.common.widgets
import qs.modules.abyss.looks
import qs.modules.waffle.regionSelector as WaffleRegion
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects as GE
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root
    visible: true
    color: "transparent"
    WlrLayershell.namespace: "quickshell:regionSelector"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    enum SnipAction { Copy, Edit, Search, CharRecognition, Record, RecordWithSound }
    enum SelectionMode { RectCorners, Circle }
    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    signal dismiss()

    onActionChanged: {
        if (root.screenshotReady
                && root.enableContentRegions
                && (root.action === RegionSelection.SnipAction.Search
                    || root.action === RegionSelection.SnipAction.CharRecognition)
                && !imageDetectionProcess.running
                && root.imageRegions.length === 0) {
            imageDetectionProcess.running = true;
        }
    }

    readonly property bool useNiri: CompositorService.isNiri
    readonly property real screenEdgeThickness: Math.max(1, Math.min(32,
        Math.round(Config.options?.appearance?.screenEdge?.width ?? 10)))
    // Screenshot selection stays full-output for hit testing/crop coordinates,
    // but its dim/guide visuals must not repaint the persistent Bar/Screen Edge.
    readonly property bool screenshotIiBarActive:
        (Config.options?.panelFamily ?? "ii") === "ii"
        && GlobalStates.barOpen
        && !(Config.options?.bar?.autoHide?.enable ?? false)
        && (Config.options?.enabledPanels ?? []).includes(
            (Config.options?.bar?.vertical ?? false) ? "iiVerticalBar" : "iiBar")
    readonly property string screenshotIiBarEdge:
        (Config.options?.bar?.vertical ?? false)
            ? ((Config.options?.bar?.bottom ?? false) ? "right" : "left")
            : ((Config.options?.bar?.bottom ?? false) ? "bottom" : "top")
    readonly property real screenshotTopOwnerInset:
        screenshotIiBarActive && screenshotIiBarEdge === "top"
            ? Appearance.sizes.barHeight : screenEdgeThickness
    readonly property real screenshotBottomOwnerInset:
        screenshotIiBarActive && screenshotIiBarEdge === "bottom"
            ? Appearance.sizes.barHeight : screenEdgeThickness
    readonly property real screenshotLeftOwnerInset:
        screenshotIiBarActive && screenshotIiBarEdge === "left"
            ? Appearance.sizes.verticalBarWidth : screenEdgeThickness
    readonly property real screenshotRightOwnerInset:
        screenshotIiBarActive && screenshotIiBarEdge === "right"
            ? Appearance.sizes.verticalBarWidth : screenEdgeThickness
    readonly property bool screenEdgeShadowEnabled:
        Config.options?.appearance?.screenEdge?.physicalShadow?.enabled ?? true
    readonly property real screenEdgeShadowSize: Math.max(0, Math.min(32,
        Math.round(Config.options?.appearance?.screenEdge?.physicalShadow?.size ?? 15)))
    readonly property real screenEdgeShadowOpacity: Math.max(0, Math.min(1.0,
        Number(Config.options?.appearance?.screenEdge?.physicalShadow?.opacity ?? 0.70)))
    readonly property color screenEdgeShadowColor:
        Qt.alpha(Appearance.m3colors.m3shadow, root.screenEdgeShadowOpacity)

    property string screenshotDir: Directories.screenshotTemp
    readonly property string screenshotNameFormat: Config.options?.regionSelector?.screenshotNameFormat || "ss-%Y%m%d-%H%M%S"
    property string imageSearchEngineBaseUrl: Config.options?.search?.imageSearch?.imageSearchEngineBaseUrl ?? "https://www.bing.com/images/search?view=detailv2&iss=sbi&form=SBIVSP&sbisrc=UrlPaste&q=imgurl:"
    property string fileUploadApiEndpoint: Config.options?.search?.imageSearch?.fileUploadApiFallback ?? "https://litterbox.catbox.moe/resources/internals/api.php"
    property string fileUploadApiFallback: Config.options?.search?.imageSearch?.fileUploadApiFallback2 ?? "https://catbox.moe/user/api.php"
    property string fileUploadApiFallback2: Config.options?.search?.imageSearch?.fileUploadApiEndpoint ?? "https://0x0.st"
    readonly property string effectiveImageSearchEngineBaseUrl: {
        const configured = imageSearchEngineBaseUrl ?? ""
        // Google and Yandex endpoints no longer work well, fallback to Bing
        if (configured === ""
                || configured === "https://lens.google.com/uploadbyurl?url="
                || configured === "https://www.google.com/searchbyimage?image_url="
                || configured === "https://yandex.com/images/search?rpt=imageview&url=") {
            return "https://www.bing.com/images/search?view=detailv2&iss=sbi&form=SBIVSP&sbisrc=UrlPaste&q=imgurl:"
        }
        return configured
    }

    // Tri-style color support
    property color overlayColor: Appearance.angelEverywhere ? ColorUtils.applyAlpha(Appearance.colors.colScrim, 0.33)
        : Appearance.alisEverywhere ? ColorUtils.applyAlpha(Appearance.colors.colScrim, 0.53)
        : Appearance.auroraEverywhere ? ColorUtils.applyAlpha(Appearance.colors.colScrim, 0.4) : ColorUtils.applyAlpha(Appearance.colors.colScrim, 0.53)
    property color brightText: Appearance.alisEverywhere ? Appearance.alis.colText
        : Appearance.auroraEverywhere ? Appearance.colors.colOnLayer0
        : (Appearance.m3colors.darkmode ? Appearance.colors.colOnLayer0 : Appearance.colors.colLayer0)
    property color brightSecondary: Appearance.alisEverywhere ? Appearance.alis.colTextSecondary
        : Appearance.auroraEverywhere ? Appearance.aurora.colTextSecondary
        : (Appearance.m3colors.darkmode ? Appearance.colors.colSecondary : Appearance.colors.colOnSecondary)
    property color brightTertiary: Appearance.zzzEverywhere ? Appearance.zzz.accent
        : Appearance.alisEverywhere ? Appearance.alis.colPrimary
        : Appearance.auroraEverywhere ? Appearance.colors.colPrimary
        : (Appearance.m3colors.darkmode ? Appearance.colors.colTertiary : Qt.lighter(Appearance.colors.colPrimary))
    property color selectionBorderColor: Appearance.zzzEverywhere ? Appearance.zzz.accent
        : Appearance.alisEverywhere ? Appearance.alis.colBorder
        : Appearance.auroraEverywhere ? Appearance.aurora.colPopupBorder
        : ColorUtils.mix(brightText, brightSecondary, 0.5)
    property color selectionFillColor: Appearance.zzzEverywhere ? ColorUtils.transparentize(Appearance.zzz.accent, 0.86)
        : Appearance.alisEverywhere ? ColorUtils.transparentize(Appearance.alis.colPrimary, 0.8)
        : Appearance.auroraEverywhere ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
        : ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.2)
    property color windowBorderColor: brightSecondary
    property color windowFillColor: ColorUtils.transparentize(windowBorderColor, 0.85)
    property color imageBorderColor: brightTertiary
    property color imageFillColor: ColorUtils.transparentize(imageBorderColor, 0.85)
    property color onBorderColor: Appearance.alisEverywhere ? Appearance.alis.colText
        : Appearance.auroraEverywhere ? Appearance.colors.colOnLayer0 : Appearance.colors.colScrim
    readonly property var windows: useNiri
        ? (NiriService.windows || [])
        : [...HyprlandData.windowList].sort((a, b) => {
            // Sort floating=true windows before others
            if (a.floating === b.floating) return 0;
            return a.floating ? -1 : 1;
        })
    readonly property var layers: useNiri ? ({}) : HyprlandData.layers
    readonly property real falsePositivePreventionRatio: 0.5

    readonly property var hyprlandMonitor: CompositorService.isHyprland ? null : null // Disabled for Niri
    readonly property real monitorScale: root.useNiri
        ? ((NiriService.displayScales && NiriService.displayScales[screen.name] !== undefined)
            ? NiriService.displayScales[screen.name]
            : 1)
        : (hyprlandMonitor ? hyprlandMonitor.scale : 1)
    readonly property real monitorOffsetX: root.useNiri ? 0 : (hyprlandMonitor ? hyprlandMonitor.x : 0)
    readonly property real monitorOffsetY: root.useNiri ? 0 : (hyprlandMonitor ? hyprlandMonitor.y : 0)
    property int activeWorkspaceId: root.useNiri
        ? (NiriService.focusedWorkspaceIndex ?? 0)
        : (hyprlandMonitor && hyprlandMonitor.activeWorkspace ? hyprlandMonitor.activeWorkspace.id : 0)
    property string screenshotPath: `${root.screenshotDir}/image-${screen.name}`
    property bool screenshotReady: false
    property real dragStartX: 0
    property real dragStartY: 0
    property real draggingX: 0
    property real draggingY: 0
    property real dragDiffX: 0
    property real dragDiffY: 0
    property bool draggedAway: (dragDiffX !== 0 || dragDiffY !== 0)
    property bool dragging: false
    property list<point> points: []
    property var mouseButton: null
    property var imageRegions: []
    readonly property list<var> windowRegions: {
        if (root.useNiri) {
            const wins = NiriService.windows || []
            const regions = []
            for (let i = 0; i < wins.length; ++i) {
                const w = wins[i]
                const layout = w.layout
                if (!layout || !layout.tile_pos_in_workspace_view || !layout.tile_size)
                    continue

                const pos = layout.tile_pos_in_workspace_view
                const size = layout.tile_size

                regions.push({
                    at: [pos[0], pos[1]],
                    size: [size[0], size[1]],
                    class: w.app_id || w.appId || "",
                    title: w.title || "",
                })
            }
            return regions
        }

        return RegionFunctions.filterWindowRegionsByLayers(
            root.windows.filter(w => w.workspace.id === root.activeWorkspaceId),
            root.layerRegions
        ).map(window => {
            return {
                at: [window.at[0] - root.monitorOffsetX, window.at[1] - root.monitorOffsetY],
                size: [window.size[0], window.size[1]],
                class: window.class,
                title: window.title,
            }
        })
    }
    readonly property list<var> layerRegions: {
        if (root.useNiri || !root.hyprlandMonitor)
            return [];

        const layersOfThisMonitor = root.layers[root.hyprlandMonitor.name]
        const topLayers = layersOfThisMonitor?.levels["2"]
        if (!topLayers) return [];
        const nonBarTopLayers = topLayers
            .filter(layer => !(layer.namespace.includes(":bar") || layer.namespace.includes(":verticalBar") || layer.namespace.includes(":dock")))
            .map(layer => {
            return {
                at: [layer.x, layer.y],
                size: [layer.w, layer.h],
                namespace: layer.namespace,
            }
        })
        const offsetAdjustedLayers = nonBarTopLayers.map(layer => {
            return {
                at: [layer.at[0] - root.monitorOffsetX, layer.at[1] - root.monitorOffsetY],
                size: layer.size,
                namespace: layer.namespace,
            }
        });
        return offsetAdjustedLayers;
    }

    property bool isCircleSelection: (root.selectionMode === RegionSelection.SelectionMode.Circle)
    property bool enableWindowRegions: (Config.options?.regionSelector?.targetRegions?.windows ?? true) && !isCircleSelection
    property bool enableLayerRegions: (Config.options?.regionSelector?.targetRegions?.layers ?? true) && !isCircleSelection
    property bool enableContentRegions: Config.options?.regionSelector?.targetRegions?.content ?? true
    property real targetRegionOpacity: Config.options?.regionSelector?.targetRegions?.opacity ?? 0.5
    property real contentRegionOpacity: Config.options?.regionSelector?.targetRegions?.contentRegionOpacity ?? 0.3

    property real targetedRegionX: -1
    property real targetedRegionY: -1
    property real targetedRegionWidth: 0
    property real targetedRegionHeight: 0
    function targetedRegionValid() {
        return (root.targetedRegionX >= 0 && root.targetedRegionY >= 0)
    }
    function setRegionToTargeted() {
        const padding = Config.options?.regionSelector?.targetRegions?.selectionPadding ?? 2; // Make borders not cut off n stuff
        root.regionX = root.targetedRegionX - padding;
        root.regionY = root.targetedRegionY - padding;
        root.regionWidth = root.targetedRegionWidth + padding * 2;
        root.regionHeight = root.targetedRegionHeight + padding * 2;
    }

    function updateTargetedRegion(x, y) {
        function regionContainsPoint(region) {
            if (!region || !region.at || !region.size)
                return false;
            if (region.at.length < 2 || region.size.length < 2)
                return false;

            const rx = region.at[0];
            const ry = region.at[1];
            const rw = region.size[0];
            const rh = region.size[1];
            return rx <= x && x <= rx + rw && ry <= y && y <= ry + rh;
        }

        // Image regions
        const clickedRegion = root.imageRegions.find(region => regionContainsPoint(region));
        if (clickedRegion) {
            root.targetedRegionX = clickedRegion.at[0];
            root.targetedRegionY = clickedRegion.at[1];
            root.targetedRegionWidth = clickedRegion.size[0];
            root.targetedRegionHeight = clickedRegion.size[1];
            return;
        }

        // Layer regions
        const clickedLayer = root.layerRegions.find(region => regionContainsPoint(region));
        if (clickedLayer) {
            root.targetedRegionX = clickedLayer.at[0];
            root.targetedRegionY = clickedLayer.at[1];
            root.targetedRegionWidth = clickedLayer.size[0];
            root.targetedRegionHeight = clickedLayer.size[1];
            return;
        }

        // Window regions
        const clickedWindow = root.windowRegions.find(region => regionContainsPoint(region));
        if (clickedWindow) {
            root.targetedRegionX = clickedWindow.at[0];
            root.targetedRegionY = clickedWindow.at[1];
            root.targetedRegionWidth = clickedWindow.size[0];
            root.targetedRegionHeight = clickedWindow.size[1];
            return;
        }

        root.targetedRegionX = -1;
        root.targetedRegionY = -1;
        root.targetedRegionWidth = 0;
        root.targetedRegionHeight = 0;
    }

    function regionMatchesTarget(region) {
        if (!region || !region.at || !region.size)
            return false;
        if (region.at.length < 2 || region.size.length < 2)
            return false;

        return root.targetedRegionX === region.at[0]
            && root.targetedRegionY === region.at[1]
            && root.targetedRegionWidth === region.size[0]
            && root.targetedRegionHeight === region.size[1];
    }

    property real regionWidth: Math.abs(draggingX - dragStartX)
    property real regionHeight: Math.abs(draggingY - dragStartY)
    property real regionX: Math.min(dragStartX, draggingX)
    property real regionY: Math.min(dragStartY, draggingY)

    readonly property bool useStageMode: false
    property real screenshotStageProgress: 0
    readonly property var stageCard: null

    function toStageX(mx: real): real {
        return mx;
    }

    function toStageY(my: real): real {
        return my;
    }

    // Inline on-screenshot editing & auto-hiding proximity toolbar state
    property string annotationTool: ""
    property color annotationColor: Appearance.colors.colPrimary
    property real annotationStrokeWidth: 4
    property bool colorStripOpen: false
    property bool toolbarHovered: false
    property bool colorStripHovered: false
    property bool edgeProximityActive: false
    property bool _annotatedExportInFlight: false
    readonly property bool pointerActionActive: root.dragging
        || liveAnnotationCanvas.drawing
        || liveAnnotationCanvas.textEditing
    readonly property bool toolbarRevealed: root.visible
        && root.screenshotReady
        && !root.pointerActionActive
        && (root.edgeProximityActive || root.toolbarHovered || root.colorStripHovered || root.colorStripOpen)

    Timer {
        id: toolbarHideGraceTimer
        interval: 200
        repeat: false
        onTriggered: {
            if (!root.toolbarHovered && !root.colorStripHovered && !root.colorStripOpen)
                root.edgeProximityActive = false;
        }
    }

    function _updateEdgeProximity(mx: real, my: real): void {
        if (root.pointerActionActive) {
            toolbarHideGraceTimer.stop();
            root.edgeProximityActive = false;
            return;
        }
        const nearBottom = my >= Math.max(0, root.height - (root.screenEdgeThickness + 56));
        const nearTop = my <= 60;
        const inZone = regionSelectionControls.useWaffle ? nearTop : nearBottom;
        if (inZone) {
            toolbarHideGraceTimer.stop();
            root.edgeProximityActive = true;
        } else if (root.edgeProximityActive && !root.toolbarHovered && !root.colorStripHovered && !root.colorStripOpen) {
            toolbarHideGraceTimer.restart();
        }
    }

    function _restoreKeyboardFocus(): void {
        keyScopeRect.forceActiveFocus();
    }

    Component.onCompleted: {
        root.screenshotReady = false
        screenshotProc.running = true
    }

    Process {
        id: screenshotProc
        running: false
        command: ["/usr/bin/bash", "-c", `/usr/bin/mkdir -p '${StringUtils.shellSingleQuoteEscape(root.screenshotDir)}' && '${StringUtils.shellSingleQuoteEscape(Quickshell.shellPath("scripts/native-dispatch"))}' screencopy -o '${StringUtils.shellSingleQuoteEscape(root.screen.name)}' '${StringUtils.shellSingleQuoteEscape(root.screenshotPath)}'`]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.screenshotReady = false
                Quickshell.execDetached(["/usr/bin/notify-send", "Region search failed", "Screen capture failed" , "-a", "Region Selector", "-t", "4000"])
            } else {
                root.screenshotReady = true
            }
            if (root.enableContentRegions
                    && (root.action === RegionSelection.SnipAction.Search
                        || root.action === RegionSelection.SnipAction.CharRecognition)) {
                imageDetectionProcess.running = true;
            }
            root.preparationDone = !checkRecordingProc.running;
        }
    }
    property bool isRecording: root.action === RegionSelection.SnipAction.Record || root.action === RegionSelection.SnipAction.RecordWithSound
    property bool recordingShouldStop: false
    Process {
        id: checkRecordingProc
        running: isRecording
        command: ["/usr/bin/pidof", "wf-recorder"]
        onExited: (exitCode, exitStatus) => {
            root.preparationDone = !screenshotProc.running
            root.recordingShouldStop = (exitCode === 0);
        }
    }
    property bool preparationDone: false
    onPreparationDoneChanged: {
        if (!preparationDone) return;
        if (root.isRecording && root.recordingShouldStop) {
            Quickshell.execDetached(["/usr/bin/bash", Directories.recordScriptPath, "--stop"]);
            root.dismiss();
            return;
        }
        Qt.callLater(() => { root.visible = true; });
    }

    Process {
        id: imageDetectionProcess
        command: ["/usr/bin/bash", "-c", `${Directories.scriptsPath}/images/find-regions-venv.sh `
            + `--image '${StringUtils.shellSingleQuoteEscape(root.screenshotPath)}' `
            + `--max-width ${Math.round(root.screen.width * root.falsePositivePreventionRatio)} `
            + `--max-height ${Math.round(root.screen.height * root.falsePositivePreventionRatio)} `]
        stdout: StdioCollector {
            id: imageDimensionCollector
            onStreamFinished: {
                try {
                    const text = imageDimensionCollector.text.trim()
                    if (text) {
                        imageRegions = RegionFunctions.filterImageRegions(
                            JSON.parse(text),
                            root.windowRegions
                        );
                    }
                } catch (e) {
                    imageRegions = []
                }
            }
        }
    }

    function snip() {
        if (root.regionWidth <= 0 || root.regionHeight <= 0) {
            root.dismiss();
            return;
        }

        root.regionX = Math.max(0, Math.min(root.regionX, root.screen.width - root.regionWidth));
        root.regionY = Math.max(0, Math.min(root.regionY, root.screen.height - root.regionHeight));
        root.regionWidth = Math.max(0, Math.min(root.regionWidth, root.screen.width - root.regionX));
        root.regionHeight = Math.max(0, Math.min(root.regionHeight, root.screen.height - root.regionY));

        // Honor the toolbar's explicit action. Right-click while in plain
        // screenshot (Copy) mode stays a shortcut to annotate instead.
        if (root.action === RegionSelection.SnipAction.Copy && root.mouseButton === Qt.RightButton) {
            root.action = RegionSelection.SnipAction.Edit;
        }

        const rx = Math.round(root.regionX * root.monitorScale);
        const ry = Math.round(root.regionY * root.monitorScale);
        const rw = Math.round(root.regionWidth * root.monitorScale);
        const rh = Math.round(root.regionHeight * root.monitorScale);
        if (liveAnnotationCanvas.hasAnnotations && root.action !== RegionSelection.SnipAction.Record && root.action !== RegionSelection.SnipAction.RecordWithSound) {
            root.exportAnnotatedCapture(rx, ry, rw, rh);
            return;
        }
        const nativeDispatch = StringUtils.shellSingleQuoteEscape(Quickshell.shellPath("scripts/native-dispatch"))
        const cropGeom = `${rw}x${rh}+${rx}+${ry}`
        const cropBase = `'${nativeDispatch}' image crop '${StringUtils.shellSingleQuoteEscape(root.screenshotPath)}' '${cropGeom}'`
        const cropToStdout = `${cropBase} -`
        const cropInPlace = `${cropBase} '${StringUtils.shellSingleQuoteEscape(root.screenshotPath)}'`
        const cleanup = `/usr/bin/rm '${StringUtils.shellSingleQuoteEscape(root.screenshotPath)}'`
        const slurpRegion = `${rx},${ry} ${rw}x${rh}`
        const screenshotSaveDir = StringUtils.shellSingleQuoteEscape(Directories.screenshotsPath)
        const uploadAndGetUrl = (filePath) => {
            const escaped = StringUtils.shellSingleQuoteEscape(filePath)
            const primary = `/usr/bin/curl -s --max-time 15 -F reqtype=fileupload -F time=1h -F fileToUpload=@'${escaped}' '${root.fileUploadApiEndpoint}'`
            const fallback1 = `/usr/bin/curl -s --max-time 15 -F reqtype=fileupload -F fileToUpload=@'${escaped}' '${root.fileUploadApiFallback}'`
            const fallback2 = `/usr/bin/curl -sf --max-time 10 -F file=@'${escaped}' '${root.fileUploadApiFallback2}'`
            // Try primary, then fallback1, then fallback2 if all fail or return empty/non-URL response
            return `url=$(${primary} 2>/dev/null); if [[ -z "$url" || "$url" != http* ]]; then url=$(${fallback1}); fi; if [[ -z "$url" || "$url" != http* ]]; then url=$(${fallback2}); fi; echo "$url"`
        }
        const annotationBin = (Config.options?.regionSelector?.annotation?.useSatty ?? false) ? "satty" : "swappy";
        const annotationCommand = `${annotationBin} -f -`;
        switch (root.action) {
            case RegionSelection.SnipAction.Copy:
                snipProc.command = ["/usr/bin/bash", "-c", `_dir='${screenshotSaveDir}' && mkdir -p "$_dir" && _ss="$_dir/$(date +'${StringUtils.shellSingleQuoteEscape(root.screenshotNameFormat)}').png" && ${cropToStdout} | tee "$_ss" | '${nativeDispatch}' clipboard copy --type image/png && echo -n "$_ss" | '${nativeDispatch}' clipboard copy --primary && ${cleanup} && /usr/bin/sleep 0.08 && /usr/bin/notify-send "Screenshot copied" "${rw}x${rh} saved to $_ss" -a "Screenshot" -i camera-photo -t 3000`]
                break;
            case RegionSelection.SnipAction.Edit:
                if (Config.options?.regionSelector?.annotation?.useNativeEditor ?? true) {
                    editCropProc.editFile = `${root.screenshotDir}/edit-${root.screen.name}.png`;
                    editCropProc.command = ["/usr/bin/bash", "-c", `${cropBase} '${StringUtils.shellSingleQuoteEscape(editCropProc.editFile)}' && ${cleanup}`];
                    editCropProc.running = true;
                    return; // editCropProc.onExited opens the native editor and dismisses
                }
                snipProc.command = ["/usr/bin/bash", "-c", `if command -v ${annotationBin} >/dev/null 2>&1; then ${cropToStdout} | ${annotationCommand} && ${cleanup}; else _edit='${StringUtils.shellSingleQuoteEscape(`${root.screenshotDir}/edit-${root.screen.name}.png`)}'; ${cropBase} "$_edit" && ${cleanup} && qs -p '${StringUtils.shellSingleQuoteEscape(Quickshell.shellDir)}' ipc call annotationEditor open "$_edit" >/dev/null 2>&1 || true; fi`]
                break;
            case RegionSelection.SnipAction.Search:
                snipProc.command = ["/usr/bin/bash", "-c", `${cropInPlace} && uploaded_url="$(${uploadAndGetUrl(root.screenshotPath)})"; if [[ -n "$uploaded_url" && "$uploaded_url" == http* ]]; then /usr/bin/xdg-open "${root.effectiveImageSearchEngineBaseUrl}$uploaded_url"; else /usr/bin/notify-send "Image search failed" "Could not upload the image for reverse search" -a "Image Search" -i image; fi; ${cleanup}`]
                break;
            case RegionSelection.SnipAction.CharRecognition:
                snipProc.command = ["/usr/bin/bash", "-c", `${cropInPlace} && /usr/bin/tesseract '${StringUtils.shellSingleQuoteEscape(root.screenshotPath)}' stdout -l $(/usr/bin/tesseract --list-langs | /usr/bin/awk 'NR>1{print $1}' | /usr/bin/tr '\\n' '+' | /usr/bin/sed 's/\\+$/\\n/') | tee >('${nativeDispatch}' clipboard copy --primary) | '${nativeDispatch}' clipboard copy && ${cleanup} && /usr/bin/notify-send "Text recognized" "OCR text copied to clipboard" -a "OCR" -i edit-find -t 3000`]
                break;
            case RegionSelection.SnipAction.Record:
                snipProc.command = ["/usr/bin/bash", Directories.recordScriptPath, "--region", slurpRegion]
                break;
            case RegionSelection.SnipAction.RecordWithSound:
                snipProc.command = ["/usr/bin/bash", Directories.recordScriptPath, "--region", slurpRegion, "--sound"]
                break;
            default:
                root.dismiss();
                return;
        }

        // Image post-processing
        snipProc.startDetached();
        if (root.action === RegionSelection.SnipAction.Record
                || root.action === RegionSelection.SnipAction.RecordWithSound)
            RecorderStatus.scheduleQuickCheck();
        root.dismiss();
    }

    // Capture the whole screen with the current action (no region drawing).
    function snipFullscreen() {
        root.dragStartX = 0;
        root.dragStartY = 0;
        root.draggingX = root.screen.width;
        root.draggingY = root.screen.height;
        root.snip();
    }

    function exportAnnotatedCapture(rx: real, ry: real, rw: real, rh: real): void {
        if (root._annotatedExportInFlight)
            return;
        liveAnnotationCanvas.commitActiveText();
        root._restoreKeyboardFocus();
        const targetW = Math.max(1, Math.round(root.width * root.monitorScale));
        const targetH = Math.max(1, Math.round(root.height * root.monitorScale));
        const cropW = rw > 0 ? rw : targetW;
        const cropH = rh > 0 ? rh : targetH;
        const cropX = rw > 0 ? rx : 0;
        const cropY = rh > 0 ? ry : 0;
        const compositedPath = `${root.screenshotDir}/annotated-live-${root.screen.name}.png`;
        root._annotatedExportInFlight = true;
        const accepted = annotatedExportContainer.grabToImage(function(result) {
            const saved = result.saveToFile(compositedPath);
            root._annotatedExportInFlight = false;
            if (!saved) {
                Quickshell.execDetached(["/usr/bin/notify-send", "Screenshot failed", "Could not composite annotated capture", "-a", "Screenshot", "-t", "3000"]);
                root.dismiss();
                return;
            }
            const escapedComposite = StringUtils.shellSingleQuoteEscape(compositedPath);
            const escapedOrig = StringUtils.shellSingleQuoteEscape(root.screenshotPath);
            const nativeDispatch = StringUtils.shellSingleQuoteEscape(Quickshell.shellPath("scripts/native-dispatch"));
            const cropBase = `'${nativeDispatch}' image crop '${escapedComposite}' '${cropW}x${cropH}+${cropX}+${cropY}'`;
            const cleanup = `/usr/bin/rm -f '${escapedOrig}' '${escapedComposite}'`;
            const screenshotSaveDir = StringUtils.shellSingleQuoteEscape(Directories.screenshotsPath);

            if (root.action === RegionSelection.SnipAction.CharRecognition) {
                snipProc.command = ["/usr/bin/bash", "-c", `${cropBase} '${escapedComposite}' && /usr/bin/tesseract '${escapedComposite}' stdout -l $(/usr/bin/tesseract --list-langs | /usr/bin/awk 'NR>1{print $1}' | /usr/bin/tr '\\n' '+' | /usr/bin/sed 's/\\+$/\\n/') | tee >('${nativeDispatch}' clipboard copy --primary) | '${nativeDispatch}' clipboard copy && ${cleanup} && /usr/bin/notify-send "Text recognized" "OCR text copied to clipboard" -a "OCR" -i edit-find -t 3000`];
            } else {
                snipProc.command = ["/usr/bin/bash", "-c", `_dir='${screenshotSaveDir}' && mkdir -p "$_dir" && _ss="$_dir/$(date +'${StringUtils.shellSingleQuoteEscape(root.screenshotNameFormat)}').png" && ${cropBase} - | tee "$_ss" | '${nativeDispatch}' clipboard copy --type image/png && echo -n "$_ss" | '${nativeDispatch}' clipboard copy --primary && ${cleanup} && /usr/bin/sleep 0.08 && /usr/bin/notify-send "Screenshot copied" "${cropW}x${cropH} annotated capture saved to $_ss" -a "Screenshot" -i camera-photo -t 3000`];
            }
            snipProc.startDetached();
            root.dismiss();
        }, Qt.size(targetW, targetH));
        if (!accepted) {
            root._annotatedExportInFlight = false;
            root.dismiss();
        }
    }

    Process {
        id: snipProc
    }

    // Crops the selected region to a temp file for the native annotation editor,
    // then opens it. Lives until exit (we dismiss only after it fires).
    Process {
        id: editCropProc
        property string editFile: ""
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                GlobalStates.annotationEditorPath = editCropProc.editFile;
                GlobalStates.annotationEditorOpen = true;
            } else {
                Quickshell.execDetached(["/usr/bin/notify-send", "Edit failed", "Could not prepare the region for editing", "-a", "Screenshot", "-t", "3000"]);
            }
            root.dismiss();
        }
    }

    Rectangle {
        id: keyScopeRect
        anchors.fill: parent
        color: "transparent"

        HoverHandler {
            onPointChanged: root._updateEdgeProximity(point.position.x, point.position.y)
        }

        focus: root.visible
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                if (liveAnnotationCanvas.textEditing) {
                    liveAnnotationCanvas.cancelActiveText();
                } else if (root.colorStripOpen) {
                    root.colorStripOpen = false;
                } else if (root.annotationTool.length > 0) {
                    root.annotationTool = "";
                } else {
                    root.dismiss();
                }
                event.accepted = true;
                return;
            }
            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                    && !liveAnnotationCanvas.textEditing
                    && liveAnnotationCanvas.hasAnnotations) {
                event.accepted = true;
                root.exportAnnotatedCapture(0, 0, Math.round(root.screen.width * root.monitorScale), Math.round(root.screen.height * root.monitorScale));
                return;
            }
            liveAnnotationCanvas.handleKey(event);
        }

        Item {
            id: screenshotStageViewport
            objectName: "screenshotStageViewport"
            width: root.width
            height: root.height

            Item {
                id: annotatedExportContainer
                anchors.fill: parent
                z: 1

                Image {
                    id: frozenScreenshot
                    anchors.fill: parent
                    source: root.visible && root.screenshotReady ? `file://${root.screenshotPath}` : ""
                    fillMode: Image.PreserveAspectFit
                    cache: false
                }

                RegionAnnotationCanvas {
                    id: liveAnnotationCanvas
                    objectName: "regionLiveAnnotationCanvas"
                    anchors.fill: parent
                    z: 2
                    imageSource: frozenScreenshot.source
                    tool: root.annotationTool
                    strokeColor: root.annotationColor
                    strokeWidth: root.annotationStrokeWidth
                    interactive: root.annotationTool.length > 0
                    handleInternalPointer: false
                    onToolSelected: (nextTool) => {
                        root.annotationTool = nextTool;
                        if (nextTool.length === 0)
                            root.colorStripOpen = false;
                    }
                    onEditingTextFinished: root._restoreKeyboardFocus()
                }
            }

            // Clip only the dim/selection-guide rendering to the workspace
            // interior so it does not repaint the persistent Bar/Screen Edge.
            Item {
                id: selectionVisualViewport
                z: 2
                x: root.screenshotLeftOwnerInset
                y: root.screenshotTopOwnerInset
                width: Math.max(0, root.width - (root.screenshotLeftOwnerInset + root.screenshotRightOwnerInset))
                height: Math.max(0, root.height - (root.screenshotTopOwnerInset + root.screenshotBottomOwnerInset))
                clip: true
                visible: root.annotationTool.length === 0 || root.dragging || (root.regionWidth > 0 && root.regionHeight > 0)
                // Keep layer.enabled off during interactive region selection so
                // full-screen FBO + OpacityMask re-renders do not stall every
                // 1px mouse movement event.
                layer.enabled: false

                Loader {
                    x: -selectionVisualViewport.x
                    y: -selectionVisualViewport.y
                    width: root.width
                    height: root.height
                    active: root.selectionMode === RegionSelection.SelectionMode.RectCorners
                    sourceComponent: RectCornersSelectionDetails {
                        regionX: root.regionX
                        regionY: root.regionY
                        regionWidth: root.regionWidth
                        regionHeight: root.regionHeight
                        mouseX: root.toStageX(mouseArea.mouseX)
                        mouseY: root.toStageY(mouseArea.mouseY)
                        color: root.selectionBorderColor
                        overlayColor: root.overlayColor
                    }
                }

                Loader {
                    x: -selectionVisualViewport.x
                    y: -selectionVisualViewport.y
                    width: root.width
                    height: root.height
                    active: root.selectionMode === RegionSelection.SelectionMode.Circle
                    sourceComponent: CircleSelectionDetails {
                        color: root.selectionBorderColor
                        overlayColor: root.overlayColor
                        points: root.points
                    }
                }
            }

            // Window regions
            Repeater {
                model: ScriptModel {
                    values: root.enableWindowRegions && root.annotationTool.length === 0 ? root.windowRegions : []
                }
                delegate: TargetRegion {
                    z: 2
                    required property var modelData
                    clientDimensions: modelData
                    showIcon: true
                    targeted: !root.draggedAway && root.regionMatchesTarget(modelData)

                    opacity: root.draggedAway ? 0 : root.targetRegionOpacity
                    borderColor: root.windowBorderColor
                    fillColor: targeted ? root.windowFillColor : "transparent"
                    text: `${modelData.class}`
                    radius: Appearance.rounding.windowRounding
                }
            }

            // Layer regions
            Repeater {
                model: ScriptModel {
                    values: root.enableLayerRegions && root.annotationTool.length === 0 ? root.layerRegions : []
                }
                delegate: TargetRegion {
                    z: 3
                    required property var modelData
                    clientDimensions: modelData
                    targeted: !root.draggedAway && root.regionMatchesTarget(modelData)

                    opacity: root.draggedAway ? 0 : root.targetRegionOpacity
                    borderColor: root.windowBorderColor
                    fillColor: targeted ? root.windowFillColor : "transparent"
                    text: `${modelData.namespace}`
                    radius: Appearance.rounding.windowRounding
                }
            }

            // Content regions
            Repeater {
                model: ScriptModel {
                    values: root.enableContentRegions && root.annotationTool.length === 0 ? root.imageRegions : []
                }
                delegate: TargetRegion {
                    z: 4
                    required property var modelData
                    clientDimensions: modelData
                    targeted: !root.draggedAway && root.regionMatchesTarget(modelData)

                    opacity: root.draggedAway ? 0 : root.contentRegionOpacity
                    borderColor: root.imageBorderColor
                    fillColor: targeted ? root.imageFillColor : "transparent"
                    text: Translation.tr("Content region")
                }
            }
        }

        MouseArea {
            id: mouseArea
            z: 60
            anchors.fill: parent
            cursorShape: root.annotationTool === "text" ? Qt.IBeamCursor : Qt.CrossCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true

            onPressed: (mouse) => {
                if (imageDetectionProcess.running) imageDetectionProcess.running = false;
                // Pressing on canvas starts a user action -> collapse & suppress toolbar until idle hover returns.
                toolbarHideGraceTimer.stop();
                root.edgeProximityActive = false;
                root.colorStripOpen = false;
                const sx = root.toStageX(mouse.x);
                const sy = root.toStageY(mouse.y);

                if (root.annotationTool.length > 0 && mouse.button === Qt.LeftButton) {
                    liveAnnotationCanvas.startStroke(sx, sy, mouse.modifiers);
                    return;
                }

                root.dragStartX = sx;
                root.dragStartY = sy;
                root.draggingX = sx;
                root.draggingY = sy;
                root.dragDiffX = 0;
                root.dragDiffY = 0;
                root.points = [];
                root.dragging = true;
                root.mouseButton = mouse.button;
            }
            onReleased: (mouse) => {
                if (liveAnnotationCanvas.drawing) {
                    liveAnnotationCanvas.endStroke();
                    return;
                }
                if (root.annotationTool.length > 0 && mouse.button === Qt.LeftButton) {
                    return;
                }
                root.dragging = false;
                // Detect if it was a click -> Try to select targeted region
                if (root.draggingX === root.dragStartX && root.draggingY === root.dragStartY) {
                    if (root.targetedRegionValid()) {
                        root.setRegionToTargeted();
                    }
                }
                // Circle dragging?
                else if (root.selectionMode === RegionSelection.SelectionMode.Circle) {
                    const padding = (Config.options?.regionSelector?.circle?.padding ?? 10) + (Config.options?.regionSelector?.circle?.strokeWidth ?? 2) / 2;
                    const sx = root.toStageX(mouseArea.mouseX);
                    const sy = root.toStageY(mouseArea.mouseY);
                    const dragPoints = (root.points.length > 0) ? root.points : [{ x: sx, y: sy }];
                    const xValues = dragPoints.map(p => p.x);
                    const maxX = Math.max(...xValues);
                    const minX = Math.min(...xValues);
                    const yValues = dragPoints.map(p => p.y);
                    const maxY = Math.max(...yValues);
                    const minY = Math.min(...yValues);
                    root.regionX = minX - padding;
                    root.regionY = minY - padding;
                    root.regionWidth = maxX - minX + padding * 2;
                    root.regionHeight = maxY - minY + padding * 2;
                }
                root.snip();
            }
            onCanceled: () => {
                liveAnnotationCanvas.cancelStroke();
                root.dragging = false;
            }
            onPositionChanged: (mouse) => {
                const sx = root.toStageX(mouse.x);
                const sy = root.toStageY(mouse.y);
                root._updateEdgeProximity(mouse.x, mouse.y);
                if (liveAnnotationCanvas.drawing) {
                    liveAnnotationCanvas.moveStroke(sx, sy, mouse.modifiers);
                    return;
                }
                if (!root.dragging) {
                    if (root.annotationTool.length === 0)
                        root.updateTargetedRegion(sx, sy);
                    return;
                }
                root.draggingX = sx;
                root.draggingY = sy;
                root.dragDiffX = sx - root.dragStartX;
                root.dragDiffY = sy - root.dragStartY;
                if (root.selectionMode === RegionSelection.SelectionMode.Circle) {
                    root.points.push({ x: sx, y: sy });
                }
            }
        }

        // Subtle bottom reveal indicator when toolbar is auto-hidden and user is idle
        Rectangle {
            id: bottomRevealCue
            objectName: "screenshotToolbarCue"
            z: 9996
            visible: !regionSelectionControls.useWaffle && !root.useStageMode && opacity > 0.01
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.screenEdgeThickness + 4
            width: 38
            height: 3
            radius: 1.5
            color: Appearance.colors.colOnLayer0
            opacity: (!root.toolbarRevealed && !root.pointerActionActive && root.screenshotReady) ? 0.42 : 0
            Behavior on opacity {
                enabled: Appearance.animationsEnabled
                NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
            }
        }

        // Material ii / Abyss uses one connected Abyss body that grows directly from
        // the physical bottom Screen Edge and tucks smoothly off-screen until hovered.
        ConnectedSurfaceAbyssEdgeSurface {
            id: regionControlsAbyss
            z: 9998
            anchors.fill: parent
            visible: !regionSelectionControls.useWaffle && !root.useStageMode
                && (regionSelectionControls.y < root.height - root.screenEdgeThickness + 1)
            edge: "bottom"
            ownerThickness: root.screenEdgeThickness
            paintOverlap: Math.min(
                PerimeterTokens.seamOverlap,
                Math.max(0, root.screenEdgeThickness - 1))
            outputRect: Qt.rect(0, 0, width, height)
            bodyRect: Qt.rect(
                regionSelectionControls.x,
                regionSelectionControls.y,
                regionSelectionControls.width,
                regionSelectionControls.height)
            bodyRadius: PerimeterTokens.popupRadius
            fillColor: Appearance.colors.colLayer0
            borderColor: Appearance.colors.colLayer0Border
            borderWidth: 0
            progress: 1
            shadowEnabled: root.screenEdgeShadowEnabled
                && root.screenEdgeShadowSize > 0
                && root.screenEdgeShadowOpacity > 0
            shadowExtent: root.screenEdgeShadowSize
            shadowColor: root.screenEdgeShadowColor
        }

        // Compact Abyss popover strip for stroke color + width above toolbar
        Rectangle {
            id: colorStylePopover
            objectName: "screenshotColorStylePopover"
            z: 10000
            visible: root.colorStripOpen && root.toolbarRevealed
            width: styleRow.implicitWidth + 16
            height: 34
            radius: 12
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            x: Math.max(root.screenEdgeThickness + 8, Math.min(parent.width - width - root.screenEdgeThickness - 8,
                Math.round(regionSelectionControls.x + regionSelectionControls.width * 0.52 - width / 2)))
            y: regionSelectionControls.y - height - 6

            readonly property bool pointerInsidePopover: stylePopoverBackdropMouse.containsMouse || stylePopoverHoverHandler.hovered
            onPointerInsidePopoverChanged: {
                root.colorStripHovered = pointerInsidePopover;
                if (!pointerInsidePopover && !root.toolbarHovered && !root.colorStripOpen)
                    toolbarHideGraceTimer.restart();
                else if (pointerInsidePopover)
                    toolbarHideGraceTimer.stop();
            }

            MouseArea {
                id: stylePopoverBackdropMouse
                anchors.fill: parent
                z: -1
                enabled: colorStylePopover.visible
                hoverEnabled: true
                cursorShape: Qt.ArrowCursor
                acceptedButtons: Qt.AllButtons
            }

            HoverHandler {
                id: stylePopoverHoverHandler
            }

            RowLayout {
                id: styleRow
                anchors.centerIn: parent
                spacing: 6

                Repeater {
                    model: liveAnnotationCanvas.palette
                    delegate: Rectangle {
                        id: swatchDot
                        required property var modelData
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 16
                        implicitHeight: 16
                        radius: 8
                        color: modelData
                        border.width: String(root.annotationColor) === String(modelData) ? 2 : 1
                        border.color: String(root.annotationColor) === String(modelData)
                            ? Appearance.colors.colOnLayer0
                            : Appearance.colors.colLayer0Border
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -2
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.annotationColor = swatchDot.modelData
                        }
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 1
                    implicitHeight: 16
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.4
                }

                Repeater {
                    model: [
                        { "label": "S", "width": 2 },
                        { "label": "M", "width": 4 },
                        { "label": "L", "width": 8 }
                    ]
                    delegate: RippleButton {
                        id: widthBtn
                        required property var modelData
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 24
                        implicitHeight: 22
                        buttonRadius: 8
                        toggled: Math.abs(root.annotationStrokeWidth - modelData.width) < 0.5
                        colBackground: "transparent"
                        colBackgroundHover: Qt.alpha(AbyssStyle.accent, 0.16)
                        colBackgroundToggled: Qt.alpha(AbyssStyle.accent, 0.28)
                        onClicked: root.annotationStrokeWidth = widthBtn.modelData.width
                        contentItem: StyledText {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: widthBtn.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: widthBtn.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                        }
                    }
                }
            }
        }

        Item {
            id: regionSelectionControls
            objectName: "regionSelectionControls"
            z: 9999
            readonly property bool useWaffle: Config.options?.panelFamily === "waffle"
            readonly property real shellPadding: useWaffle ? 0 : 4
            implicitWidth: controlsLoader.implicitWidth + shellPadding * 2
            implicitHeight: controlsLoader.implicitHeight + shellPadding * 2
            visible: true
            opacity: fallbackOpacity
            property real fallbackOpacity: root.toolbarRevealed ? 1 : 0

            x: Math.round((parent.width - width) / 2)
            y: useWaffle ? fallbackTopMargin : (parent.height - height - fallbackBottomMargin)
            width: implicitWidth
            height: implicitHeight

            property real fallbackTopMargin: root.toolbarRevealed ? 16 : -(implicitHeight + 16)
            property real fallbackBottomMargin: root.toolbarRevealed ? root.screenEdgeThickness : -(implicitHeight + 16)

            readonly property bool pointerInsideControls: controlsBackdropMouse.containsMouse || controlsHoverHandler.hovered
            onPointerInsideControlsChanged: {
                root.toolbarHovered = pointerInsideControls;
                if (!pointerInsideControls && !root.colorStripHovered && !root.colorStripOpen)
                    toolbarHideGraceTimer.restart();
                else if (pointerInsideControls)
                    toolbarHideGraceTimer.stop();
            }

            MouseArea {
                id: controlsBackdropMouse
                anchors.fill: parent
                z: -1
                enabled: root.toolbarRevealed
                hoverEnabled: true
                cursorShape: Qt.ArrowCursor
                acceptedButtons: Qt.AllButtons
            }

            HoverHandler {
                id: controlsHoverHandler
            }

            Behavior on fallbackOpacity {
                enabled: Appearance.animationsEnabled
                NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
            }
            Behavior on fallbackTopMargin {
                enabled: Appearance.animationsEnabled
                NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.OutCubic }
            }
            Behavior on fallbackBottomMargin {
                enabled: Appearance.animationsEnabled
                NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.OutCubic }
            }

            Loader {
                id: controlsLoader
                anchors.centerIn: parent
                sourceComponent: regionSelectionControls.useWaffle ? waffleControls : materialControls
            }

            // Material ii / Abyss compact connected controls
            Component {
                id: materialControls
                Row {
                    spacing: 2

                    OptionsToolbar {
                        enableShadow: false
                        transparent: true
                        tooltipPosition: regionSelectionControls.useWaffle ? "bottom" : "top"
                        action: root.action
                        selectionMode: root.selectionMode
                        annotationTool: root.annotationTool
                        annotationColor: root.annotationColor
                        annotationStrokeWidth: root.annotationStrokeWidth
                        hasAnnotations: liveAnnotationCanvas.hasAnnotations
                        canUndo: liveAnnotationCanvas.canUndo
                        canRedo: liveAnnotationCanvas.canRedo
                        stylePopoverOpen: root.colorStripOpen
                        onActionChanged: if (action !== undefined && root.action !== action) root.action = action
                        onSelectionModeChanged: if (selectionMode !== undefined && root.selectionMode !== selectionMode) root.selectionMode = selectionMode
                        onAnnotationToolChanged: if (root.annotationTool !== annotationTool) root.annotationTool = annotationTool
                        onStylePopoverOpenChanged: if (root.colorStripOpen !== stylePopoverOpen) root.colorStripOpen = stylePopoverOpen
                        onUndoRequested: liveAnnotationCanvas.undo()
                        onRedoRequested: liveAnnotationCanvas.redo()
                        onClearAnnotationsRequested: liveAnnotationCanvas.clearAll()
                        onSaveAnnotatedRequested: root.exportAnnotatedCapture(0, 0, Math.round(root.screen.width * root.monitorScale), Math.round(root.screen.height * root.monitorScale))
                        onDismiss: root.dismiss()
                        onFullscreenRequested: root.snipFullscreen()
                        onColorPickerRequested: {
                            // Dismiss before the Alis picker captures the desktop.
                            root.dismiss();
                            ColorPickerService.start();
                        }
                    }

                    RippleButton {
                        id: closeFab
                        objectName: "regionCloseButton"
                        property string iconText: "close"
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: 30
                        implicitHeight: 30
                        buttonRadius: (Config.options?.panelFamily === "abyss") ? 12 : Appearance.rounding.full
                        colBackground: Appearance.colors.colTertiaryContainer
                        colBackgroundHover: Appearance.colors.colTertiaryContainerHover
                        colRipple: Appearance.colors.colTertiaryContainerActive
                        onClicked: root.dismiss()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: closeFab.iconText
                            iconSize: 17
                            color: Appearance.colors.colOnTertiaryContainer
                        }
                        StyledToolTip {
                            text: Translation.tr("Close (Esc)")
                            position: regionSelectionControls.useWaffle ? "bottom" : "top"
                            enabled: true
                        }
                    }
                }
            }

            // Waffle (Windows 11) controls
            Component {
                id: waffleControls
                WaffleRegion.WOptionsToolbar {
                    action: root.action
                    selectionMode: root.selectionMode
                    onActionChanged: if (action !== undefined && root.action !== action) root.action = action
                    onSelectionModeChanged: if (selectionMode !== undefined && root.selectionMode !== selectionMode) root.selectionMode = selectionMode
                    onDismiss: root.dismiss()
                    onFullscreenRequested: root.snipFullscreen()
                    onColorPickerRequested: {
                        root.dismiss();
                        ColorPickerService.start();
                    }
                }
            }
        }
    }
}
