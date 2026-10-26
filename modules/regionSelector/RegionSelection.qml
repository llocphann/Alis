pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.perimeter
import qs.modules.common.widgets
import qs.modules.waffle.regionSelector as WaffleRegion
import qs.services
import QtQuick
import QtQuick.Controls
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
        if (root.useNiri)
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

    Component.onCompleted: {
        root.screenshotReady = false
        screenshotProc.running = true
    }

    Process {
        id: screenshotProc
        running: false
        command: ["/usr/bin/bash", "-c", `/usr/bin/mkdir -p '${StringUtils.shellSingleQuoteEscape(root.screenshotDir)}' && /usr/bin/grim -o '${StringUtils.shellSingleQuoteEscape(root.screen.name)}' '${StringUtils.shellSingleQuoteEscape(root.screenshotPath)}'`]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.screenshotReady = false
                Quickshell.execDetached(["/usr/bin/notify-send", "Region search failed", "grim failed to capture the screen" , "-a", "Region Selector", "-t", "4000"])
            } else {
                root.screenshotReady = true
            }
            if (root.enableContentRegions) imageDetectionProcess.running = true;
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
            Quickshell.execDetached([Directories.recordScriptPath, "--stop"]);
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
        const cropBase = `magick '${StringUtils.shellSingleQuoteEscape(root.screenshotPath)}' `
            + `-crop ${rw}x${rh}+${rx}+${ry}`
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
        const annotationCommand = `${(Config.options?.regionSelector?.annotation?.useSatty ?? false) ? "satty" : "swappy"} -f -`;
        switch (root.action) {
            case RegionSelection.SnipAction.Copy:
                snipProc.command = ["/usr/bin/bash", "-c", `_dir='${screenshotSaveDir}' && mkdir -p "$_dir" && _ss="$_dir/$(date +'${StringUtils.shellSingleQuoteEscape(root.screenshotNameFormat)}').png" && ${cropToStdout} | tee "$_ss" | /usr/bin/wl-copy && echo -n "$_ss" | /usr/bin/wl-copy --primary && ${cleanup} && /usr/bin/notify-send "Screenshot copied" "${rw}x${rh} saved to $_ss" -a "Screenshot" -i camera-photo -t 3000`]
                break;
            case RegionSelection.SnipAction.Edit:
                if (Config.options?.regionSelector?.annotation?.useNativeEditor ?? true) {
                    editCropProc.editFile = `${root.screenshotDir}/edit-${root.screen.name}.png`;
                    editCropProc.command = ["/usr/bin/bash", "-c", `${cropBase} '${StringUtils.shellSingleQuoteEscape(editCropProc.editFile)}' && ${cleanup}`];
                    editCropProc.running = true;
                    return; // editCropProc.onExited opens the native editor and dismisses
                }
                snipProc.command = ["/usr/bin/bash", "-c", `${cropToStdout} | ${annotationCommand} && ${cleanup}`]
                break;
            case RegionSelection.SnipAction.Search:
                snipProc.command = ["/usr/bin/bash", "-c", `${cropInPlace} && uploaded_url="$(${uploadAndGetUrl(root.screenshotPath)})"; if [[ -n "$uploaded_url" && "$uploaded_url" == http* ]]; then /usr/bin/xdg-open "${root.effectiveImageSearchEngineBaseUrl}$uploaded_url"; else /usr/bin/notify-send "Image search failed" "Could not upload the image for reverse search" -a "Image Search" -i image; fi; ${cleanup}`]
                break;
            case RegionSelection.SnipAction.CharRecognition:
                snipProc.command = ["/usr/bin/bash", "-c", `${cropInPlace} && /usr/bin/tesseract '${StringUtils.shellSingleQuoteEscape(root.screenshotPath)}' stdout -l $(/usr/bin/tesseract --list-langs | /usr/bin/awk 'NR>1{print $1}' | /usr/bin/tr '\\n' '+' | /usr/bin/sed 's/\\+$/\\n/') | tee >(/usr/bin/wl-copy --primary) | /usr/bin/wl-copy && ${cleanup} && /usr/bin/notify-send "Text recognized" "OCR text copied to clipboard" -a "OCR" -i edit-find -t 3000`]
                break;
            case RegionSelection.SnipAction.Record:
                snipProc.command = ["/usr/bin/bash", "-c", `${Directories.recordScriptPath} --region '${slurpRegion}'`]
                break;
            case RegionSelection.SnipAction.RecordWithSound:
                snipProc.command = ["/usr/bin/bash", "-c", `${Directories.recordScriptPath} --region '${slurpRegion}' --sound`]
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
        anchors.fill: parent
        color: "transparent"

        Image {
            anchors.fill: parent
            source: root.visible && root.screenshotReady ? `file://${root.screenshotPath}` : ""
            fillMode: Image.PreserveAspectFit
            cache: false
        }

        focus: root.visible
        Keys.onPressed: (event) => { // Esc to close
            if (event.key === Qt.Key_Escape) {
                root.dismiss();
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            cursorShape: Qt.CrossCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true

            // Controls
            onPressed: (mouse) => {
                root.dragStartX = mouse.x;
                root.dragStartY = mouse.y;
                root.draggingX = mouse.x;
                root.draggingY = mouse.y;
                root.dragging = true;
                root.mouseButton = mouse.button;
            }
            onReleased: (mouse) => {
                // Detect if it was a click -> Try to select targeted region
                if (root.draggingX === root.dragStartX && root.draggingY === root.dragStartY) {
                    if (root.targetedRegionValid()) {
                        root.setRegionToTargeted();
                    }
                }
                // Circle dragging?
                else if (root.selectionMode === RegionSelection.SelectionMode.Circle) {
                    const padding = (Config.options?.regionSelector?.circle?.padding ?? 10) + (Config.options?.regionSelector?.circle?.strokeWidth ?? 2) / 2;
                    const dragPoints = (root.points.length > 0) ? root.points : [{ x: mouseArea.mouseX, y: mouseArea.mouseY }];
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
            onPositionChanged: (mouse) => {
                root.updateTargetedRegion(mouse.x, mouse.y);
                if (!root.dragging) return;
                root.draggingX = mouse.x;
                root.draggingY = mouse.y;
                root.dragDiffX = mouse.x - root.dragStartX;
                root.dragDiffY = mouse.y - root.dragStartY;
                root.points.push({ x: mouse.x, y: mouse.y });
            }

            // Clip only the dim/selection-guide rendering to the workspace
            // interior. The MouseArea and snip coordinates remain full-output,
            // so Bar/Screen Edge pixels stay visually unchanged without
            // changing what the user can select or capture.
            Item {
                id: selectionVisualViewport
                z: 2
                x: root.screenshotLeftOwnerInset
                y: root.screenshotTopOwnerInset
                width: Math.max(0, mouseArea.width
                    - root.screenshotLeftOwnerInset
                    - root.screenshotRightOwnerInset)
                height: Math.max(0, mouseArea.height
                    - root.screenshotTopOwnerInset
                    - root.screenshotBottomOwnerInset)
                clip: true
                // Match the exact rounded inner workspace hole painted by
                // ScreenEdges.qml. A rectangular clip protects the straight
                // edge bands but still lets the screenshot scrim cover the four
                // rounded frame corners because RegionSelection lives on Overlay.
                layer.enabled: true
                layer.smooth: true
                layer.effect: GE.OpacityMask {
                    maskSource: Rectangle {
                        width: selectionVisualViewport.width
                        height: selectionVisualViewport.height
                        radius: Math.max(0, Math.min(
                            PerimeterTokens.frameRadius,
                            width / 2,
                            height / 2))
                    }
                }

                Loader {
                    x: -selectionVisualViewport.x
                    y: -selectionVisualViewport.y
                    width: mouseArea.width
                    height: mouseArea.height
                    active: root.selectionMode === RegionSelection.SelectionMode.RectCorners
                    sourceComponent: RectCornersSelectionDetails {
                        regionX: root.regionX
                        regionY: root.regionY
                        regionWidth: root.regionWidth
                        regionHeight: root.regionHeight
                        mouseX: mouseArea.mouseX
                        mouseY: mouseArea.mouseY
                        color: root.selectionBorderColor
                        overlayColor: root.overlayColor
                    }
                }

                Loader {
                    x: -selectionVisualViewport.x
                    y: -selectionVisualViewport.y
                    width: mouseArea.width
                    height: mouseArea.height
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
                    values: root.enableWindowRegions ? root.windowRegions : []
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
                    values: root.enableLayerRegions ? root.layerRegions : []
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
                    values: root.enableContentRegions ? root.imageRegions : []
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

            // Controls
            // Material ii uses one connected Abyss body that grows directly from
            // the physical bottom Screen Edge. The toolbar and close action are
            // content inside that single body instead of separate floating cards.
            ConnectedSurfaceAbyssEdgeSurface {
                id: regionControlsAbyss
                z: 9998
                anchors.fill: parent
                visible: !regionSelectionControls.useWaffle
                edge: "bottom"
                ownerThickness: root.screenEdgeThickness
                // Same raster seam treatment as the now-validated Sidebar
                // attachment: only Abyss paint overlaps the physical owner;
                // toolbar layout/input still stop at the real boundary.
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

            Item {
                id: regionSelectionControls
                z: 9999
                readonly property bool useWaffle: Config.options?.panelFamily === "waffle"
                readonly property real shellPadding: useWaffle ? 0 : 8
                implicitWidth: controlsLoader.implicitWidth + shellPadding * 2
                implicitHeight: controlsLoader.implicitHeight + shellPadding * 2
                opacity: 0

                // Position: waffle = top center, material = connected to bottom Screen Edge
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: useWaffle ? parent.top : undefined
                    bottom: useWaffle ? undefined : parent.bottom
                    topMargin: useWaffle ? -height : 0
                    bottomMargin: useWaffle ? 0 : -height
                }

                Connections {
                    target: root
                    function onVisibleChanged() {
                        if (!visible) return;
                        if (regionSelectionControls.useWaffle) {
                            regionSelectionControls.anchors.topMargin = 16;
                        } else {
                            regionSelectionControls.anchors.bottomMargin = root.screenEdgeThickness;
                        }
                        regionSelectionControls.opacity = 1;
                    }
                }
                Behavior on opacity {
                    animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                }
                Behavior on anchors.topMargin {
                    animation: NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Appearance.animation.elementMove.type; easing.bezierCurve: Appearance.animation.elementMove.bezierCurve }
                }
                Behavior on anchors.bottomMargin {
                    animation: NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Appearance.animation.elementMove.type; easing.bezierCurve: Appearance.animation.elementMove.bezierCurve }
                }

                Loader {
                    id: controlsLoader
                    anchors.centerIn: parent
                    sourceComponent: regionSelectionControls.useWaffle ? waffleControls : materialControls
                }

                // Material ii controls
                Component {
                    id: materialControls
                    Row {
                        spacing: 4

                        OptionsToolbar {
                            enableShadow: false
                            transparent: true
                            action: root.action
                            selectionMode: root.selectionMode
                            onActionChanged: root.action = action
                            onSelectionModeChanged: root.selectionMode = selectionMode
                            onDismiss: root.dismiss();
                            onFullscreenRequested: root.snipFullscreen()
                            onColorPickerRequested: {
                                // Dismiss first so hyprpicker grabs the live desktop, not this overlay.
                                root.dismiss();
                                ShellExec.execDetachedArgs(["/usr/bin/bash", "-c", "sleep 0.3; /usr/bin/hyprpicker -a"], "Pick color");
                            }
                        }

                        FloatingActionButton {
                            id: closeFab
                            anchors.verticalCenter: parent.verticalCenter
                            baseSize: 40
                            iconText: "close"
                            onClicked: root.dismiss();
                            StyledToolTip {
                                text: Translation.tr("Close")
                            }
                            colBackground: Appearance.colors.colTertiaryContainer
                            colBackgroundHover: Appearance.colors.colTertiaryContainerHover
                            colRipple: Appearance.colors.colTertiaryContainerActive
                            colOnBackground: Appearance.colors.colOnTertiaryContainer
                        }
                    }
                }

                // Waffle (Windows 11) controls
                Component {
                    id: waffleControls
                    WaffleRegion.WOptionsToolbar {
                        action: root.action
                        selectionMode: root.selectionMode
                        onActionChanged: root.action = action
                        onSelectionModeChanged: root.selectionMode = selectionMode
                        onDismiss: root.dismiss()
                        onFullscreenRequested: root.snipFullscreen()
                        onColorPickerRequested: {
                            root.dismiss();
                            ShellExec.execDetachedArgs(["/usr/bin/bash", "-c", "sleep 0.3; /usr/bin/hyprpicker -a"], "Pick color");
                        }
                    }
                }
            }

        }
    }
}
