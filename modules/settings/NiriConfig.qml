pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: root
    settingsPageIndex: 12
    settingsPageName: Translation.tr("Display & Input")
    property string activeSection: "displays"
    property bool pageReady: false
    readonly property string _legacyAppPresetHint: Translation.tr("Choose an app preset or custom command.")

    function activateSettingsSearchSection(section: string): bool {
        const label = String(section ?? "").toLowerCase()
        if (label.includes("touchpad") || label.includes("mouse") || label.includes("trackpoint")
                || label.includes("keyboard") || label.includes("repeat") || label.includes("numlock")
                || label.includes("input") || label.includes("cursor")) {
            root.activeSection = "input"
        } else if (label.includes("window") || label.includes("tiling") || label.includes("layout")
                || label.includes("animation") || label.includes("rule") || label.includes("border")
                || label.includes("column") || label.includes("shadow") || label.includes("strut")
                || label.includes("titlebar")) {
            root.activeSection = "windows"
        } else {
            root.activeSection = "displays"
        }
        return true
    }

    readonly property var shellVisibilitySurfaces: [
        { key: "bar", label: Translation.tr("Bar"), path: "bar.screenList" },
        { key: "sidebar", label: Translation.tr("Sidebars"), path: "sidebar.screenList" },
        { key: "dock", label: Translation.tr("Dock"), path: "dock.screenList" },
        { key: "notificationCenter", label: Translation.tr("Notifications"), path: "notificationCenter.screenList" },
        { key: "media", label: Translation.tr("Media"), path: "media.screenList" },
        { key: "widgets", label: Translation.tr("Widgets"), path: "background.widgets.screenList" }
    ]

    readonly property var knownScreens: {
        const seen = {}
        const result = []
        const outs = root.outputList ?? []
        for (let i = 0; i < outs.length; i++) {
            const name = String(outs[i]?.name ?? "").trim()
            if (name.length > 0 && !seen[name]) {
                seen[name] = true
                result.push(name)
            }
        }
        if (result.length === 0) {
            const screens = Quickshell.screens ?? []
            for (let i = 0; i < screens.length; i++) {
                const name = String(screens[i]?.name ?? "").trim()
                if (name.length > 0 && !seen[name]) {
                    seen[name] = true
                    result.push(name)
                }
            }
        }
        return result
    }

    readonly property string configuredPrimaryMonitor: String(Config.options?.display?.primaryMonitor ?? "")

    readonly property var primaryMonitorOptions: {
        const opts = [{ displayName: Translation.tr("Automatic (first active)"), value: "" }]
        for (let i = 0; i < root.knownScreens.length; i++) {
            const name = root.knownScreens[i]
            opts.push({ displayName: name, value: name })
        }
        return opts
    }

    function effectivePrimaryMonitor(): string {
        const configured = root.configuredPrimaryMonitor
        if (configured.length > 0 && root.knownScreens.indexOf(configured) >= 0)
            return configured
        return root.knownScreens.length > 0 ? root.knownScreens[0] : ""
    }

    function configuredSurfaceScreens(path: string): var {
        const val = root.getConfigValue(path, [])
        return Array.isArray(val) ? val.map(v => String(v)) : []
    }

    function surfaceAllScreensEnabled(path: string): bool {
        return root.configuredSurfaceScreens(path).length === 0
    }

    function surfaceScreenEnabled(path: string, screenName: string): bool {
        const list = root.configuredSurfaceScreens(path)
        return list.length === 0 || list.indexOf(screenName) >= 0
    }

    function setSurfaceAllScreens(path: string): void {
        Config.setNestedValue(path, [])
    }

    function toggleSurfaceScreen(path: string, screenName: string): void {
        const screens = root.knownScreens
        const current = root.configuredSurfaceScreens(path)
        let next = current.length === 0 ? screens.slice() : current.slice()
        const idx = next.indexOf(screenName)
        if (idx >= 0) {
            if (next.length > 1)
                next.splice(idx, 1)
        } else {
            next.push(screenName)
        }
        if (screens.length > 0 && screens.every(name => next.indexOf(name) >= 0))
            next = []
        Config.setNestedValue(path, next)
    }

    function setAllShellSurfacesToPrimary(): void {
        const primary = root.effectivePrimaryMonitor()
        if (!primary.length) return
        for (let i = 0; i < root.shellVisibilitySurfaces.length; i++) {
            Config.setNestedValue(root.shellVisibilitySurfaces[i].path, [primary])
        }
    }

    function setAllShellSurfacesToAll(): void {
        for (let i = 0; i < root.shellVisibilitySurfaces.length; i++) {
            Config.setNestedValue(root.shellVisibilitySurfaces[i].path, [])
        }
    }

    property var outputList: buildFallbackScreenOutputs()
    readonly property var effectiveOutputList: (Array.isArray(outputList) && outputList.length > 0)
        ? outputList
        : buildFallbackScreenOutputs()
    property int selectedOutputIndex: 0
    readonly property int effectiveSelectedOutputIndex: effectiveOutputList.length > 0
        ? Math.min(Math.max(0, selectedOutputIndex), effectiveOutputList.length - 1)
        : 0

    readonly property var currentOutput: effectiveOutputList.length > effectiveSelectedOutputIndex
        ? effectiveOutputList[effectiveSelectedOutputIndex]
        : null
    readonly property string currentOutputName: currentOutput?.name ?? ""
    readonly property string currentResolution: currentOutput?.current_resolution ?? ""
    readonly property real currentRate: currentOutput?.current_rate ?? 0
    readonly property string currentRateString: currentOutput?.current_rate_string ?? (currentRate > 0 ? currentRate.toFixed(3) : "")
    readonly property real currentScale: currentOutput?.scale ?? 1.0
    readonly property string currentTransform: currentOutput?.transform ?? "Normal"
    readonly property bool vrrSupported: currentOutput?.vrr_supported ?? false
    readonly property bool vrrEnabled: currentOutput?.vrr_enabled ?? false
    readonly property string vrrMode: currentOutput?.vrr_mode ?? (vrrEnabled ? "on" : "off")

    readonly property var vrrOptions: [
        {
            value: "off",
            displayName: Translation.tr("Off")
        },
        {
            value: "on-demand",
            displayName: Translation.tr("On demand (recommended)")
        },
        {
            value: "on",
            displayName: Translation.tr("Always on")
        }
    ]
    readonly property string niriConfigPath: validationData?.config_path ?? ""
    readonly property string niriConfigDir: customConfigData?.config_dir ?? ""
    readonly property bool hasAnyProcessError: processErrors.outputs.length > 0 || processErrors.input.length > 0 || processErrors.layout.length > 0 || processErrors.animations.length > 0 || processErrors.windowRules.length > 0 || processErrors.cursorThemes.length > 0 || processErrors.validation.length > 0 || processErrors.customizations.length > 0

    readonly property var resolutionOptions: {
        const out = currentOutput
        if (!out?.resolutions) return []
        return out.resolutions.map(r => ({
            displayName: `${r.width}x${r.height}` + (r.preferred ? " ★" : ""),
            value: `${r.width}x${r.height}`,
            width: r.width,
            height: r.height,
            rates: r.rates
        }))
    }

    readonly property var refreshOptions: {
        const res = currentResolution
        if (!res || !currentOutput?.resolutions) return []
        const match = currentOutput.resolutions.find(r => `${r.width}x${r.height}` === res)
        if (!match?.rates) return []
        return match.rates.map(r => ({
            displayName: `${r.rate_string ?? Number(r.rate).toFixed(3)} Hz` + (r.preferred ? " ★" : ""),
            value: r.rate,
            rateString: r.rate_string ?? Number(r.rate).toFixed(3)
        })).sort((a, b) => b.value - a.value)
    }

    readonly property var scaleOptions: [
        { displayName: "0.5x", value: 0.5 },
        { displayName: "0.75x", value: 0.75 },
        { displayName: "1x", value: 1.0 },
        { displayName: "1.25x", value: 1.25 },
        { displayName: "1.5x", value: 1.5 },
        { displayName: "1.75x", value: 1.75 },
        { displayName: "2x", value: 2.0 },
        { displayName: "2.5x", value: 2.5 },
        { displayName: "3x", value: 3.0 }
    ]

    readonly property var transformOptions: [
        { displayName: Translation.tr("Normal"), icon: "screen_rotation_alt", value: "normal" },
        { displayName: "90°", icon: "screen_rotation_alt", value: "90" },
        { displayName: "180°", icon: "screen_rotation_alt", value: "180" },
        { displayName: "270°", icon: "screen_rotation_alt", value: "270" },
        { displayName: Translation.tr("Flipped"), icon: "flip", value: "flipped" },
        { displayName: Translation.tr("Flipped 90°"), icon: "flip", value: "flipped-90" },
        { displayName: Translation.tr("Flipped 180°"), icon: "flip", value: "flipped-180" },
        { displayName: Translation.tr("Flipped 270°"), icon: "flip", value: "flipped-270" }
    ]

    property var inputData: ({})
    readonly property var keyboardData: inputData?.keyboard ?? {}
    readonly property var generalInputData: inputData?.general ?? {}
    readonly property var touchpadData: inputData?.touchpad ?? {}
    readonly property var mouseData: inputData?.mouse ?? {}
    readonly property var trackpointData: inputData?.trackpoint ?? {}
    readonly property var cursorData: inputData?.cursor ?? {}

    property var layoutData: ({})
    property var animationsData: ({})
    property var windowRulesData: ({})
    property var cursorThemes: []
    property var validationData: ({ valid: true, output: "", config_path: "" })
    property var customConfigData: ({ customized: false, config_dir: "", summary: {}, files: [] })
    readonly property var customConfigSummary: customConfigData?.summary ?? ({ managed_override: 0, extra_file: 0, expected_generated: 0, user_extra: 0, actionable: 0, total: 0 })
    readonly property int customConfigManagedOverrideCount: Number(customConfigSummary?.managed_override ?? 0)
    readonly property int customConfigExtraFileCount: Number(customConfigSummary?.extra_file ?? 0)
    readonly property int customConfigExpectedGeneratedCount: Number(customConfigSummary?.expected_generated ?? 0)
    readonly property int customConfigUserExtraCount: Number(customConfigSummary?.user_extra ?? 0)
    readonly property int customConfigActionableCount: Number(customConfigSummary?.actionable ?? (customConfigManagedOverrideCount + customConfigExtraFileCount))
    readonly property int customConfigDiffCount: Number(customConfigSummary?.total ?? (customConfigData?.files?.length ?? 0))
    readonly property bool hasCustomConfigDiffs: customConfigActionableCount > 0
    readonly property bool showCustomConfigStatusSection: customConfigActionableCount > 0 || customConfigUserExtraCount > 0
    readonly property var actionableCustomConfigFiles: (customConfigData?.files ?? []).filter(file => {
        const kind = String(file?.kind ?? "")
        return kind === "managed-override" || kind === "extra-file"
    })
    readonly property var informationalCustomConfigFiles: (customConfigData?.files ?? []).filter(file => {
        const kind = String(file?.kind ?? "")
        return kind === "expected-generated" || kind === "user-extra"
    })
    property var processErrors: ({
        outputs: "",
        input: "",
        layout: "",
        animations: "",
        windowRules: "",
        cursorThemes: "",
        validation: "",
        customizations: ""
    })
    property string lastActionError: ""
    property string lastActionInfo: ""

    property bool inputReady: false
    property bool layoutReady: false
    property bool outputReady: false
    property bool animationsReady: false
    property bool windowRulesReady: false
    property bool validationReady: false
    property bool customizationsReady: false
    property bool positionEditorReady: false
    property bool shadowEditorReady: false

    // Display safety / serialization state
    property string previousMode: ""
    property real previousScale: -1
    property string previousTransform: ""
    property bool confirmationPending: false
    property int confirmCountdown: 15
    property string pendingOutputName: ""
    property string pendingChangeType: ""
    property string pendingChangeValue: ""
    property string pendingPreviewKind: ""
    property string pendingSetSection: ""
    property string pendingActionLabel: ""
    property string applyOutputPurpose: ""
    property string applyOutputTargetName: ""
    property string applyOutputKey: ""
    property string applyOutputValue: ""
    property string applyRollbackKey: ""
    property string applyRollbackValue: ""
    property string persistOutputPurpose: ""
    property string persistOutputTargetName: ""
    property string persistOutputKey: ""
    property string persistOutputValue: ""
    property string persistRollbackKey: ""
    property string persistRollbackValue: ""
    property var setRequestQueue: []
    readonly property bool displayControlsLocked: !CompositorService.isNiri || !root.outputReady || confirmationPending || applyOutputProcess.running || persistOutputProcess.running

    function buildFallbackScreenOutputs(): var {
        const screens = Quickshell.screens ?? []
        const fallback = []
        for (let i = 0; i < screens.length; i++) {
            const s = screens[i]
            if (!s) continue
            const w = Math.max(1, Number(s.width ?? 1920))
            const h = Math.max(1, Number(s.height ?? 1080))
            const dpr = Number(s.devicePixelRatio ?? 1.0)
            fallback.push({
                name: String(s.name || `WAYLAND-${i + 1}`),
                make: "Wayland",
                model: String(s.model || "Display"),
                serial: "",
                physical_size: [0, 0],
                current_resolution: `${w}x${h}`,
                current_rate: 60.0,
                current_rate_string: "60.000",
                scale: dpr > 0 ? dpr : 1.0,
                transform: "Normal",
                vrr_supported: false,
                vrr_enabled: false,
                vrr_mode: "off",
                position: { x: Number(s.x ?? 0), y: Number(s.y ?? 0) },
                resolutions: [
                    {
                        width: w,
                        height: h,
                        preferred: true,
                        rates: [{ rate: 60.0, rate_string: "60.000", preferred: true }]
                    }
                ]
            })
        }
        if (fallback.length === 0) {
            fallback.push({
                name: "WAYLAND-1",
                make: "Wayland",
                model: "Display",
                serial: "",
                physical_size: [0, 0],
                current_resolution: "1920x1080",
                current_rate: 60.0,
                current_rate_string: "60.000",
                scale: 1.0,
                transform: "Normal",
                vrr_supported: false,
                vrr_enabled: false,
                vrr_mode: "off",
                position: { x: 0, y: 0 },
                resolutions: [
                    {
                        width: 1920,
                        height: 1080,
                        preferred: true,
                        rates: [{ rate: 60.0, rate_string: "60.000", preferred: true }]
                    }
                ]
            })
        }
        return fallback
    }

    readonly property string scriptPath: Quickshell.shellPath("scripts/niri-config.py")
    readonly property string nativeDispatchPath: Quickshell.shellPath("scripts/native-dispatch")
    readonly property var keyboardLayoutOptions: [
        { displayName: "US English", value: "us" },
        { displayName: "Spanish", value: "es" },
        { displayName: "German", value: "de" },
        { displayName: "French", value: "fr" },
        { displayName: "Portuguese (BR)", value: "br" },
        { displayName: "Italian", value: "it" },
        { displayName: "UK English", value: "gb" },
        { displayName: "Russian", value: "ru" },
        { displayName: "Japanese", value: "jp" },
        { displayName: "Korean", value: "kr" },
        { displayName: "Latin American", value: "latam" },
        { displayName: Translation.tr("Custom..."), value: "__custom__" }
    ]

    // Folders resolve the inode/directory handler explicitly because common
    // terminal emulators claim that type (kitty-open ships as the first cached
    // handler on many distros), which makes bare xdg-open launch a terminal.
    // When the resolved handler looks like a terminal, fall back to the first
    // installed real file manager so the button keeps its promised semantics.
    function openConfigFolderExternally(): void {
        if (!root.niriConfigDir || root.niriConfigDir.length === 0)
            return;
        if (!defaultFileManagerQuery.running)
            defaultFileManagerQuery.running = true;
    }

    function openConfigFileExternally(): void {
        if (!root.niriConfigPath || root.niriConfigPath.length === 0)
            return;
        if (!defaultEditorQuery.running)
            defaultEditorQuery.running = true;
    }

    Process {
        id: defaultFileManagerQuery
        command: ["bash", "-c", `
            id=$(xdg-mime query default inode/directory)
            case "$id" in
                ""|kitty-open*|*terminal*|foot*|alacritty*|konsole*|xterm*|wezterm*)
                    for c in org.gnome.Nautilus org.kde.dolphin thunar nemo pcmanfm-qt; do
                        [ -f "/usr/share/applications/$c.desktop" ] && { echo "$c"; exit 0; }
                    done ;;
                *) echo "\${id%.desktop}" ;;
            esac`]
        stdout: StdioCollector {
            id: defaultFileManagerCollector
        }
        onExited: (exitCode) => {
            const desktopId = (defaultFileManagerCollector.text || "").trim();
            if (exitCode === 0 && desktopId.length > 0)
                ShellExec.execDetachedArgs(["gtk-launch", desktopId, root.niriConfigDir], Translation.tr("Open config folder"));
            else
                ShellExec.execDetachedArgs(["xdg-open", root.niriConfigDir], Translation.tr("Open config folder"));
        }
    }

    Process {
        id: defaultEditorQuery
        command: ["xdg-mime", "query", "default", "text/plain"]
        stdout: StdioCollector {
            id: defaultEditorCollector
        }
        onExited: (exitCode) => {
            const desktopId = (defaultEditorCollector.text || "").trim().replace(/\.desktop$/, "");
            if (exitCode === 0 && desktopId.length > 0)
                ShellExec.execDetachedArgs(["gtk-launch", desktopId, root.niriConfigPath], Translation.tr("Open config file"));
            else
                ShellExec.execDetachedArgs(["xdg-open", root.niriConfigPath], Translation.tr("Open config file"));
        }
    }

    // Humanized animation type names
    readonly property var animationLabels: ({
        "workspace-switch": Translation.tr("Workspace switch"),
        "window-open": Translation.tr("Window open"),
        "window-close": Translation.tr("Window close"),
        "horizontal-view-movement": Translation.tr("Horizontal scroll"),
        "window-movement": Translation.tr("Window movement"),
        "window-resize": Translation.tr("Window resize"),
        "config-notification-open-close": Translation.tr("Config notification"),
        "exit-confirmation-open-close": Translation.tr("Exit confirmation"),
        "screenshot-ui-open": Translation.tr("Screenshot UI"),
        "overview-open-close": Translation.tr("Overview"),
        "recent-windows-close": Translation.tr("Recent windows")
    })
    readonly property var modKeyOptions: ["Super", "Alt", "Ctrl", "Shift", "Mod3", "Mod5"]
    readonly property var trackLayoutOptions: [
        { displayName: Translation.tr("Global"), value: "global" },
        { displayName: Translation.tr("Per window"), value: "window" }
    ]
    readonly property var tapButtonMapOptions: [
        { displayName: Translation.tr("Left / Right / Middle"), value: "left-right-middle" },
        { displayName: Translation.tr("Left / Middle / Right"), value: "left-middle-right" }
    ]
    readonly property var clickMethodOptions: [
        { displayName: Translation.tr("Button areas"), value: "button-areas" },
        { displayName: Translation.tr("Clickfinger"), value: "clickfinger" }
    ]
    readonly property var touchpadScrollMethodOptions: [
        { displayName: Translation.tr("Two-finger"), value: "two-finger" },
        { displayName: Translation.tr("Edge"), value: "edge" },
        { displayName: Translation.tr("On button down"), value: "on-button-down" },
        { displayName: Translation.tr("Disable scrolling"), value: "no-scroll" }
    ]
    readonly property var pointerScrollMethodOptions: [
        { displayName: Translation.tr("On button down"), value: "on-button-down" },
        { displayName: Translation.tr("Disable scrolling"), value: "no-scroll" },
        { displayName: Translation.tr("Two-finger"), value: "two-finger" },
        { displayName: Translation.tr("Edge"), value: "edge" }
    ]
    readonly property var defaultColumnDisplayOptions: [
        { displayName: Translation.tr("Normal"), value: "normal" },
        { displayName: Translation.tr("Tabbed"), value: "tabbed" }
    ]
    readonly property var warpMouseModeOptions: [
        { displayName: Translation.tr("Separate axes"), value: "separate" },
        { displayName: Translation.tr("Center window"), value: "center-xy" },
        { displayName: Translation.tr("Always center"), value: "center-xy-always" }
    ]

    function loadOutputs() { outputsProcess.running = true }
    function loadInput() { inputProcess.running = true }
    function loadLayout() { layoutProcess.running = true }
    function loadAnimations() { animationsProcess.running = true }
    function loadWindowRules() { windowRulesProcess.running = true }
    function loadCursorThemes() { cursorThemesProcess.running = true }
    function loadValidation() { validationProcess.running = true }
    function loadCustomizations() { customizationsProcess.running = true }

    function setProcessError(key, message) {
        processErrors = Object.assign({}, processErrors, { [key]: message })
    }

    function resetBanner(message) {
        if (message === undefined)
            message = ""
        lastActionError = ""
        lastActionInfo = message
    }

    function handleJsonResult(rawText, processKey, onSuccess) {
        try {
            const parsed = JSON.parse(rawText)
            if (parsed && typeof parsed === "object" && parsed.error) {
                const errorText = String(parsed.error)
                setProcessError(processKey, errorText)
                if (processKey === "validation") {
                    validationData = { valid: false, output: errorText, config_path: "" }
                    validationReady = true
                }
                return
            }
            setProcessError(processKey, "")
            onSuccess(parsed)
        } catch (e) {
            const parseError = Translation.tr("Failed to parse %1 response.").arg(processKey)
            console.warn(`[NiriConfig] ${processKey} parse failure:`, e)
            setProcessError(processKey, parseError)
        }
    }

    function saveAndRefresh(message) {
        resetBanner(message)
        loadValidation()
        loadCustomizations()
    }

    function refreshAll() {
        loadOutputs()
        loadInput()
        loadLayout()
        loadAnimations()
        loadWindowRules()
        loadCursorThemes()
        loadValidation()
        loadCustomizations()
    }

    function refreshActiveSection(): void {
        switch (root.activeSection) {
        case "displays":
            loadOutputs()
            break
        case "windows":
        case "layout":
        case "animations":
        case "rules":
            loadLayout()
            loadAnimations()
            loadWindowRules()
            break
        case "input":
            loadInput()
            loadCursorThemes()
            break
        }
    }

    function refreshInitial(): void {
        refreshAll()
    }

    function getConfigValue(path, fallback) {
        const parts = String(path ?? "").split(".")
        let cursor = Config.options

        for (const part of parts) {
            if (!part.length)
                continue
            if (cursor === null || cursor === undefined || cursor[part] === undefined)
                return fallback
            cursor = cursor[part]
        }

        return cursor === undefined || cursor === null ? fallback : cursor
    }

    function armPositionEditor() {
        positionEditorReady = false
        positionEditorTimer.restart()
    }

    function armShadowEditor() {
        shadowEditorReady = false
        shadowEditorTimer.restart()
    }

    function clearPreviewState() {
        confirmationPending = false
        previousMode = ""
        previousScale = -1
        previousTransform = ""
        pendingOutputName = ""
        pendingChangeType = ""
        pendingChangeValue = ""
        pendingPreviewKind = ""
        pendingActionLabel = ""
        confirmCountdown = 15
    }

    function clearApplyOutputState() {
        applyOutputPurpose = ""
        applyOutputTargetName = ""
        applyOutputKey = ""
        applyOutputValue = ""
        applyRollbackKey = ""
        applyRollbackValue = ""
    }

    function clearPersistOutputState() {
        persistOutputPurpose = ""
        persistOutputTargetName = ""
        persistOutputKey = ""
        persistOutputValue = ""
        persistRollbackKey = ""
        persistRollbackValue = ""
    }

    function outputValueForKey(output, key) {
        if (!output)
            return ""
        if (key === "position")
            return `${output?.position?.x ?? 0},${output?.position?.y ?? 0}`
        if (key === "vrr")
            return output?.vrr_mode ?? ((output?.vrr_enabled ?? false) ? "on" : "off")
        if (key === "scale")
            return String(output?.scale ?? 1.0)
        if (key === "transform")
            return String(output?.transform ?? "Normal").toLowerCase()
        if (key === "mode") {
            const resolution = output?.current_resolution ?? ""
            const rate = output?.current_rate ?? 0
            const rateString = output?.current_rate_string ?? (rate > 0 ? Number(rate).toFixed(3) : "")
            return resolution.length > 0 && rateString.length > 0 ? `${resolution}@${rateString}` : ""
        }
        return ""
    }

    function previewRollbackRequest() {
        if (pendingPreviewKind === "mode" && previousMode.length > 0)
            return { key: "mode", value: previousMode }
        if (pendingPreviewKind === "scale" && previousScale >= 0)
            return { key: "scale", value: String(previousScale) }
        if (pendingPreviewKind === "transform" && previousTransform.length > 0)
            return { key: "transform", value: previousTransform }
        return null
    }

    function startOutputApply(outputName, key, value, purpose, rollbackKey, rollbackValue) {
        applyOutputPurpose = purpose
        applyOutputTargetName = outputName
        applyOutputKey = key
        applyOutputValue = String(value)
        applyRollbackKey = rollbackKey ?? ""
        applyRollbackValue = rollbackValue ?? ""
        applyOutputProcess.command = [root.nativeDispatchPath, "niri", "apply-output", outputName, `${key}=${String(value)}`]
        applyOutputProcess.running = true
    }

    function startOutputPersist(outputName, key, value, purpose, rollbackKey, rollbackValue) {
        persistOutputPurpose = purpose
        persistOutputTargetName = outputName
        persistOutputKey = key
        persistOutputValue = String(value)
        persistRollbackKey = rollbackKey ?? ""
        persistRollbackValue = rollbackValue ?? ""
        persistOutputProcess.command = [root.nativeDispatchPath, "niri", "persist-output", outputName, `${key}=${String(value)}`]
        persistOutputProcess.running = true
    }

    function applyOutput(key, value) {
        if (!currentOutputName.length)
            return
        startOutputApply(currentOutputName, key, value, "adhoc", "", "")
    }

    function persistOutput(key, value) {
        if (!currentOutputName.length)
            return
        startOutputPersist(currentOutputName, key, value, "adhoc", "", "")
    }

    function applyAndPersistOutput(key, value) {
        if (displayControlsLocked)
            return

        const output = currentOutput
        const outputName = currentOutputName
        if (!output || !outputName.length)
            return

        startOutputApply(outputName, key, value, "apply-and-persist", key, outputValueForKey(output, key))
    }

    // Display safety: apply transient change, start confirmation timer
    function safeApplyOutput(changeType, key, value) {
        if (displayControlsLocked)
            return

        const outputName = currentOutputName
        if (!outputName.length)
            return

        // Store current state for revert
        if (changeType === "mode") {
            previousMode = `${currentResolution}@${currentRateString || currentRate.toFixed(3)}`
            previousScale = -1
            previousTransform = ""
        } else if (changeType === "scale") {
            previousScale = currentScale
            previousMode = ""
            previousTransform = ""
        } else if (changeType === "transform") {
            previousTransform = currentTransform.toLowerCase()
            previousMode = ""
            previousScale = -1
        }

        pendingOutputName = outputName
        pendingChangeType = key
        pendingChangeValue = value
        pendingPreviewKind = changeType
        pendingActionLabel = Translation.tr("Previewing display change")
        confirmCountdown = 15

        startOutputApply(outputName, key, value, "preview", "", "")
    }

    function confirmDisplayChange() {
        if (!confirmationPending || applyOutputProcess.running || persistOutputProcess.running || !pendingOutputName.length)
            return

        const rollback = previewRollbackRequest()

        confirmationPending = false
        pendingActionLabel = Translation.tr("Saving display settings")
        startOutputPersist(pendingOutputName, pendingChangeType, pendingChangeValue, "preview-confirm", rollback ? rollback.key : "", rollback ? rollback.value : "")
    }

    function revertDisplayChange() {
        if (!pendingOutputName.length || applyOutputProcess.running || persistOutputProcess.running)
            return

        const outputName = pendingOutputName
        const rollback = previewRollbackRequest()

        confirmationPending = false

        if (!rollback) {
            clearPreviewState()
            lastActionInfo = Translation.tr("Display preview reverted.")
            return
        }

        pendingActionLabel = Translation.tr("Reverting display preview")
        startOutputApply(outputName, rollback.key, rollback.value, "preview-revert", "", "")
    }

    function runNextSetRequest() {
        if (setProcess.running || setRequestQueue.length === 0)
            return

        const nextQueue = setRequestQueue.slice()
        const request = nextQueue.shift()
        setRequestQueue = nextQueue
        pendingSetSection = request.section
        pendingActionLabel = `${request.section}.${request.key}`
        setProcess.command = [root.nativeDispatchPath, "niri", "set", request.section, request.key, request.value]
        setProcess.running = true
    }

    function setConfig(section, key, value) {
        const normalizedValue = String(value)
        const nextQueue = []

        for (const request of setRequestQueue) {
            if (request.section === section && request.key === key)
                continue
            nextQueue.push(request)
        }

        nextQueue.push({ section: section, key: key, value: normalizedValue })
        setRequestQueue = nextQueue
        runNextSetRequest()
    }

    function setBooleanConfig(section, key, enabled) {
        setConfig(section, key, enabled ? "on" : "off")
    }

    function setFocusFollowsMouse(enabled, percent) {
        if (percent === undefined)
            percent = -1
        if (!enabled) {
            setConfig("input", "focus-follows-mouse", "off")
            return
        }
        const finalPercent = percent >= 0 ? percent : (generalInputData?.focus_follows_mouse_max_scroll ?? 0)
        setConfig("input", "focus-follows-mouse", `max-scroll-amount=\"${finalPercent}%\"`)
    }

    function setWarpMouseMode(mode) {
        if (mode === "off") {
            setConfig("input", "warp-mouse-to-focus", "off")
            return
        }
        setConfig("input", "warp-mouse-to-focus", mode)
    }

    function animationIsEnabled(typeData) {
        return !(typeData?.off ?? false)
    }

    function processErrorSummary() {
        const messages = []
        for (const key of ["outputs", "input", "layout", "animations", "windowRules", "cursorThemes", "validation", "customizations"]) {
            const message = String(processErrors[key] ?? "").trim()
            if (message.length > 0)
                messages.push(message)
        }
        return messages.join("\n")
    }

    function choiceIndex(options, value) {
        for (let i = 0; i < options.length; ++i) {
            if (String(options[i].value) === String(value))
                return i
        }
        return -1
    }

    Component.onCompleted: {
        root.pageReady = true
        root.refreshInitial()
    }

    onActiveSectionChanged: {
        if (root.activeSection === "layout" || root.activeSection === "animations" || root.activeSection === "rules") {
            root.activeSection = "windows"
            return
        }
        if (root.pageReady)
            root.refreshActiveSection()
    }

    onCurrentOutputChanged: armPositionEditor()
    onLayoutDataChanged: armShadowEditor()

    // Force-resync display combo boxes when output data refreshes.
    // Inline bindings on currentIndex get broken by user interaction (classic QML issue),
    // and Binding elements inside ContentSubsection resolve `root` to ContentSubsection's
    // own root, not NiriConfig. So we resync imperatively here.
    onOutputListChanged: Qt.callLater(resyncDisplayCombos)
    onEffectiveOutputListChanged: Qt.callLater(resyncDisplayCombos)
    onSelectedOutputIndexChanged: Qt.callLater(resyncDisplayCombos)

    function resyncDisplayCombos() {
        if (typeof monitorSelectorCombo !== "undefined")
            monitorSelectorCombo.currentIndex = Math.max(0, choiceIndex(monitorSelectorCombo.model, currentOutputName))
        resolutionCombo.currentIndex = choiceIndex(resolutionCombo.model, currentResolution)
        refreshRateCombo.currentIndex = choiceIndex(refreshRateCombo.model, currentRate)
        scaleCombo.currentIndex = choiceIndex(scaleCombo.model, currentScale)
        rotationCombo.currentIndex = choiceIndex(rotationCombo.model, currentTransform.toLowerCase())
        vrrCombo.currentIndex = choiceIndex(vrrCombo.model, vrrMode)
    }

    // =====================
    // CONFIRMATION TIMER
    // =====================
    Timer {
        id: confirmTimer
        interval: 1000
        repeat: true
        running: root.confirmationPending
        onTriggered: {
            root.confirmCountdown--
            if (root.confirmCountdown <= 0) {
                root.revertDisplayChange()
            }
        }
    }

    Timer {
        id: positionEditorTimer
        interval: 1
        repeat: false
        onTriggered: root.positionEditorReady = true
    }

    // Deferred output refresh — gives Niri time to commit display changes
    // before we query the new state (avoids stale reads after scale/mode changes).
    Timer {
        id: _deferredOutputRefresh
        interval: 300
        repeat: false
        onTriggered: root.loadOutputs()
    }

    Timer {
        id: shadowEditorTimer
        interval: 1
        repeat: false
        onTriggered: root.shadowEditorReady = true
    }

    function resyncAnimationsControls() {
        const ad = root.animationsData ?? {}
        const types = ad.types ?? {}
        if (typeof animationsEnabledSwitch !== "undefined")
            animationsEnabledSwitch.checked = ad.enabled ?? true
        if (typeof animWorkspaceSwitch !== "undefined")
            animWorkspaceSwitch.checked = !(types["workspace-switch"]?.off ?? false)
        if (typeof animOverviewSwitch !== "undefined")
            animOverviewSwitch.checked = !(types["overview-open-close"]?.off ?? false)
        if (typeof animWindowOpenSwitch !== "undefined")
            animWindowOpenSwitch.checked = !(types["window-open"]?.off ?? false)
        if (typeof animWindowCloseSwitch !== "undefined")
            animWindowCloseSwitch.checked = !(types["window-close"]?.off ?? false)
        if (typeof animHorizontalScrollSwitch !== "undefined")
            animHorizontalScrollSwitch.checked = !(types["horizontal-view-movement"]?.off ?? false)
        if (typeof animWindowResizeSwitch !== "undefined")
            animWindowResizeSwitch.checked = !(types["window-resize"]?.off ?? false)
    }

    function resyncWindowRulesControls() {
        const wr = root.windowRulesData ?? {}
        if (typeof clipToGeometrySwitch !== "undefined")
            clipToGeometrySwitch.checked = wr.clip_to_geometry ?? true
    }

    function resyncLayoutControls() {
        const ld = root.layoutData ?? {}
        if (typeof layoutGapsSpin !== "undefined")
            layoutGapsSpin.value = ld.gaps ?? 25
        if (typeof alwaysCenterSingleColumnSwitch !== "undefined")
            alwaysCenterSingleColumnSwitch.checked = ld.always_center_single_column ?? false
        if (typeof emptyWorkspaceAboveFirstSwitch !== "undefined")
            emptyWorkspaceAboveFirstSwitch.checked = ld.empty_workspace_above_first ?? false
        if (typeof defaultColumnDisplayCombo !== "undefined")
            defaultColumnDisplayCombo.currentIndex = root.choiceIndex(root.defaultColumnDisplayOptions, ld.default_column_display ?? "normal")
        if (typeof borderEnabledSwitch !== "undefined")
            borderEnabledSwitch.checked = ld.border?.enabled ?? false
        if (typeof borderWidthSpin !== "undefined")
            borderWidthSpin.value = ld.border?.width ?? 4
        if (typeof focusRingEnabledSwitch !== "undefined")
            focusRingEnabledSwitch.checked = ld.focus_ring?.enabled ?? false
        if (typeof focusRingWidthSpin !== "undefined")
            focusRingWidthSpin.value = ld.focus_ring?.width ?? 1
        if (typeof shadowEnabledSwitch !== "undefined")
            shadowEnabledSwitch.checked = ld.shadow?.enabled ?? true
        if (typeof shadowSoftnessSpin !== "undefined")
            shadowSoftnessSpin.value = ld.shadow?.softness ?? 30
        if (typeof shadowSpreadSpin !== "undefined")
            shadowSpreadSpin.value = ld.shadow?.spread ?? 5
        if (typeof shadowOffsetXSpin !== "undefined")
            shadowOffsetXSpin.value = ld.shadow?.offset_x ?? 0
        if (typeof shadowOffsetYSpin !== "undefined")
            shadowOffsetYSpin.value = ld.shadow?.offset_y ?? 5
        if (typeof strutLeftSpin !== "undefined")
            strutLeftSpin.value = ld.struts?.left ?? 0
        if (typeof strutRightSpin !== "undefined")
            strutRightSpin.value = ld.struts?.right ?? 0
        if (typeof strutTopSpin !== "undefined")
            strutTopSpin.value = ld.struts?.top ?? 0
        if (typeof strutBottomSpin !== "undefined")
            strutBottomSpin.value = ld.struts?.bottom ?? 0
        if (typeof overviewZoomSpin !== "undefined")
            overviewZoomSpin.value = Math.round((ld.overview_zoom ?? 0.75) * 100)
    }

    function resyncInputControls() {
        const kb = root.keyboardData ?? {}
        const tp = root.touchpadData ?? {}
        const ms = root.mouseData ?? {}
        const tk = root.trackpointData ?? {}
        const cr = root.cursorData ?? {}
        const gn = root.generalInputData ?? {}
        if (typeof cursorHideWhenTypingSwitch !== "undefined")
            cursorHideWhenTypingSwitch.checked = cr.hide_when_typing ?? true
        if (typeof keyboardNumlockSwitch !== "undefined")
            keyboardNumlockSwitch.checked = kb.numlock ?? false
        if (typeof keyboardLayoutCombo !== "undefined") {
            const kbIdx = root.choiceIndex(root.keyboardLayoutOptions, kb.layout ?? "us")
            keyboardLayoutCombo.currentIndex = kbIdx >= 0 ? kbIdx : (root.keyboardLayoutOptions.length - 1)
        }
        if (typeof keyboardTrackLayoutCombo !== "undefined")
            keyboardTrackLayoutCombo.currentIndex = Math.max(0, root.choiceIndex(root.trackLayoutOptions, kb.track_layout ?? "global"))
        if (typeof keyboardRepeatDelaySpin !== "undefined")
            keyboardRepeatDelaySpin.value = kb.repeat_delay ?? 250
        if (typeof keyboardRepeatRateSpin !== "undefined")
            keyboardRepeatRateSpin.value = kb.repeat_rate ?? 50
        if (typeof disablePowerKeySwitch !== "undefined")
            disablePowerKeySwitch.checked = gn.disable_power_key_handling ?? false
        if (typeof workspaceAutoBackAndForthSwitch !== "undefined")
            workspaceAutoBackAndForthSwitch.checked = gn.workspace_auto_back_and_forth ?? false
        if (typeof touchpadScrollMethodCombo !== "undefined")
            touchpadScrollMethodCombo.currentIndex = Math.max(0, root.choiceIndex(root.touchpadScrollMethodOptions, tp.scroll_method ?? "two-finger"))
        if (typeof touchpadClickMethodCombo !== "undefined")
            touchpadClickMethodCombo.currentIndex = Math.max(0, root.choiceIndex(root.clickMethodOptions, tp.click_method ?? "button-areas"))
        if (typeof touchpadTapButtonMapCombo !== "undefined")
            touchpadTapButtonMapCombo.currentIndex = Math.max(0, root.choiceIndex(root.tapButtonMapOptions, tp.tap_button_map ?? "left-right-middle"))
        if (typeof modKeyCombo !== "undefined") {
            const mkIdx = root.modKeyOptions.indexOf(gn.mod_key || "Super")
            modKeyCombo.currentIndex = mkIdx >= 0 ? mkIdx : 0
        }
        if (typeof modKeyNestedCombo !== "undefined") {
            const mknIdx = root.modKeyOptions.indexOf(gn.mod_key_nested || "Alt")
            modKeyNestedCombo.currentIndex = mknIdx >= 0 ? mknIdx : 1
        }
        if (typeof warpMouseToFocusSwitch !== "undefined")
            warpMouseToFocusSwitch.checked = gn.warp_mouse_to_focus ?? false
        if (typeof focusFollowsMouseSwitch !== "undefined")
            focusFollowsMouseSwitch.checked = gn.focus_follows_mouse ?? false
        if (typeof focusFollowsMouseMaxScrollSpin !== "undefined")
            focusFollowsMouseMaxScrollSpin.value = gn.focus_follows_mouse_max_scroll ?? 0
        if (typeof mouseNaturalScrollSwitch !== "undefined")
            mouseNaturalScrollSwitch.checked = ms.natural_scroll ?? false
        if (typeof mouseLeftHandedSwitch !== "undefined")
            mouseLeftHandedSwitch.checked = ms.left_handed ?? false
        if (typeof mouseMiddleEmulationSwitch !== "undefined")
            mouseMiddleEmulationSwitch.checked = ms.middle_emulation ?? false
        if (typeof mouseScrollButtonLockSwitch !== "undefined")
            mouseScrollButtonLockSwitch.checked = ms.scroll_button_lock ?? false
        if (typeof touchpadEnabledSwitch !== "undefined")
            touchpadEnabledSwitch.checked = !(tp.off ?? false)
        if (typeof touchpadTapSwitch !== "undefined")
            touchpadTapSwitch.checked = tp.tap ?? true
        if (typeof touchpadNaturalScrollSwitch !== "undefined")
            touchpadNaturalScrollSwitch.checked = tp.natural_scroll ?? false
        if (typeof touchpadDwtSwitch !== "undefined")
            touchpadDwtSwitch.checked = tp.dwt ?? false
        if (typeof touchpadDwtpSwitch !== "undefined")
            touchpadDwtpSwitch.checked = tp.dwtp ?? false
        if (typeof touchpadDisableExternalMouseSwitch !== "undefined")
            touchpadDisableExternalMouseSwitch.checked = tp.disabled_on_external_mouse ?? false
        if (typeof touchpadLeftHandedSwitch !== "undefined")
            touchpadLeftHandedSwitch.checked = tp.left_handed ?? false
        if (typeof touchpadMiddleEmulationSwitch !== "undefined")
            touchpadMiddleEmulationSwitch.checked = tp.middle_emulation ?? false
        if (typeof touchpadDragLockSwitch !== "undefined")
            touchpadDragLockSwitch.checked = tp.drag_lock ?? false
        if (typeof touchpadScrollButtonLockSwitch !== "undefined")
            touchpadScrollButtonLockSwitch.checked = tp.scroll_button_lock ?? false
        if (typeof trackpointNaturalScrollSwitch !== "undefined")
            trackpointNaturalScrollSwitch.checked = tk.natural_scroll ?? false
        if (typeof trackpointLeftHandedSwitch !== "undefined")
            trackpointLeftHandedSwitch.checked = tk.left_handed ?? false
        if (typeof trackpointMiddleEmulationSwitch !== "undefined")
            trackpointMiddleEmulationSwitch.checked = tk.middle_emulation ?? false
        if (typeof trackpointScrollButtonLockSwitch !== "undefined")
            trackpointScrollButtonLockSwitch.checked = tk.scroll_button_lock ?? false
    }

    // =====================
    // PROCESSES
    // =====================
    Process {
        id: outputsProcess
        command: [root.nativeDispatchPath, "niri", "outputs"]
        stdout: StdioCollector {
            id: outputsCollector
            onStreamFinished: {
                root.outputReady = false
                root.handleJsonResult(outputsCollector.text, "outputs", data => {
                    if (Array.isArray(data) && data.length > 0) {
                        root.outputList = data
                        root.outputReady = CompositorService.isNiri
                    } else {
                        root.outputList = root.buildFallbackScreenOutputs()
                        root.outputReady = false
                    }
                })
            }
        }
        stderr: StdioCollector { id: outputsErrorCollector }
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                if (!Array.isArray(root.outputList) || root.outputList.length === 0) {
                    root.outputList = root.buildFallbackScreenOutputs()
                }
                root.outputReady = false
                root.setProcessError("outputs", (outputsErrorCollector.text || outputsCollector.text || Translation.tr("Unable to query connected outputs.")).trim())
            }
        }
    }

    Process {
        id: inputProcess
        command: [root.nativeDispatchPath, "niri", "get-input"]
        stdout: StdioCollector {
            id: inputCollector
            onStreamFinished: {
                root.inputReady = false
                root.handleJsonResult(inputCollector.text, "input", data => {
                    root.inputData = data
                    root.resyncInputControls()
                    root.inputReady = true
                })
            }
        }
        stderr: StdioCollector { id: inputErrorCollector }
        onExited: (exitCode) => {
            if (exitCode !== 0)
                root.setProcessError("input", (inputErrorCollector.text || inputCollector.text || Translation.tr("Unable to read input configuration.")).trim())
        }
    }

    Process {
        id: layoutProcess
        command: [root.nativeDispatchPath, "niri", "get-layout"]
        stdout: StdioCollector {
            id: layoutCollector
            onStreamFinished: {
                root.layoutReady = false
                root.handleJsonResult(layoutCollector.text, "layout", data => {
                    root.layoutData = data
                    root.resyncLayoutControls()
                    root.layoutReady = true
                })
            }
        }
        stderr: StdioCollector { id: layoutErrorCollector }
        onExited: (exitCode) => {
            if (exitCode !== 0)
                root.setProcessError("layout", (layoutErrorCollector.text || layoutCollector.text || Translation.tr("Unable to read layout configuration.")).trim())
        }
    }

    Process {
        id: animationsProcess
        command: [root.nativeDispatchPath, "niri", "get-animations"]
        stdout: StdioCollector {
            id: animationsCollector
            onStreamFinished: {
                root.animationsReady = false
                root.handleJsonResult(animationsCollector.text, "animations", data => {
                    root.animationsData = data
                    root.resyncAnimationsControls()
                    root.animationsReady = true
                })
            }
        }
        stderr: StdioCollector { id: animationsErrorCollector }
        onExited: (exitCode) => {
            if (exitCode !== 0)
                root.setProcessError("animations", (animationsErrorCollector.text || animationsCollector.text || Translation.tr("Unable to read animations configuration.")).trim())
        }
    }

    Process {
        id: windowRulesProcess
        command: [root.nativeDispatchPath, "niri", "get-window-rules"]
        stdout: StdioCollector {
            id: windowRulesCollector
            onStreamFinished: {
                root.windowRulesReady = false
                root.handleJsonResult(windowRulesCollector.text, "windowRules", data => {
                    root.windowRulesData = data
                    root.resyncWindowRulesControls()
                    root.windowRulesReady = true
                })
            }
        }
        stderr: StdioCollector { id: windowRulesErrorCollector }
        onExited: (exitCode) => {
            if (exitCode !== 0)
                root.setProcessError("windowRules", (windowRulesErrorCollector.text || windowRulesCollector.text || Translation.tr("Unable to read window rules.")).trim())
        }
    }

    Process {
        id: cursorThemesProcess
        command: [root.nativeDispatchPath, "niri", "list-cursor-themes"]
        stdout: StdioCollector {
            id: cursorThemesCollector
            onStreamFinished: {
                root.handleJsonResult(cursorThemesCollector.text, "cursorThemes", data => {
                    root.cursorThemes = Array.isArray(data) ? data : []
                })
            }
        }
        stderr: StdioCollector { id: cursorThemesErrorCollector }
        onExited: (exitCode) => {
            if (exitCode !== 0)
                root.setProcessError("cursorThemes", (cursorThemesErrorCollector.text || cursorThemesCollector.text || Translation.tr("Unable to enumerate cursor themes.")).trim())
        }
    }

    Process {
        id: validationProcess
        command: [root.nativeDispatchPath, "niri", "validate"]
        stdout: StdioCollector {
            id: validationCollector
            onStreamFinished: {
                root.validationReady = false
                root.handleJsonResult(validationCollector.text, "validation", data => {
                    root.validationData = data
                    root.validationReady = true
                })
            }
        }
        stderr: StdioCollector { id: validationErrorCollector }
        onExited: (exitCode) => {
            if (exitCode !== 0)
                root.setProcessError("validation", (validationErrorCollector.text || validationCollector.text || Translation.tr("Unable to validate Niri configuration.")).trim())
        }
    }

    Process {
        id: customizationsProcess
        command: [root.nativeDispatchPath, "niri", "detect-customizations"]
        stdout: StdioCollector {
            id: customizationsCollector
            onStreamFinished: {
                root.customizationsReady = false
                root.handleJsonResult(customizationsCollector.text, "customizations", data => {
                    root.customConfigData = data
                    root.customizationsReady = true
                })
            }
        }
        stderr: StdioCollector { id: customizationsErrorCollector }
        onExited: (exitCode) => {
            if (exitCode !== 0)
                root.setProcessError("customizations", (customizationsErrorCollector.text || customizationsCollector.text || Translation.tr("Unable to inspect custom Niri configuration.")).trim())
        }
    }

    Process {
        id: applyOutputProcess
        stdout: StdioCollector { id: applyOutputCollector }
        stderr: StdioCollector { id: applyOutputErrorCollector }
        onExited: (exitCode) => {
            const purpose = root.applyOutputPurpose
            const stdout = (applyOutputCollector.text || "").trim()
            const stderr = (applyOutputErrorCollector.text || "").trim()

            // Parse JSON results for detailed failure info
            let jsonFailed = false
            let failDetail = ""
            try {
                const parsed = JSON.parse(stdout)
                if (parsed?.results) {
                    const failed = parsed.results.filter(r => r.success === false)
                    if (failed.length > 0) {
                        jsonFailed = true
                        failDetail = failed.map(r => `${r.key}: ${r.output || "failed"}`).join("; ")
                    }
                }
            } catch (_) {
                // Not JSON — fall through to text-based handling
            }

            const effectiveFailed = exitCode !== 0 || jsonFailed
            const text = failDetail || stderr || stdout

            if (!effectiveFailed) {
                if (purpose === "preview") {
                    root.lastActionError = ""
                    root.confirmationPending = true
                } else if (purpose === "preview-revert") {
                    root.lastActionError = ""
                    root.clearPreviewState()
                    root.lastActionInfo = Translation.tr("Display preview reverted.")
                } else if (purpose === "preview-revert-after-failure") {
                    root.clearPreviewState()
                    root.lastActionInfo = Translation.tr("Display preview reverted after save failure.")
                } else if (purpose === "apply-and-persist") {
                    root.lastActionError = ""
                    root.startOutputPersist(root.applyOutputTargetName, root.applyOutputKey, root.applyOutputValue, "apply-and-persist", root.applyRollbackKey, root.applyRollbackValue)
                } else if (purpose === "apply-and-persist-rollback") {
                    root.lastActionInfo = Translation.tr("Display change reverted after save failure.")
                } else {
                    root.lastActionError = ""
                }
                _deferredOutputRefresh.restart()
            } else {
                if (purpose === "preview" || purpose === "preview-revert" || purpose === "preview-revert-after-failure")
                    root.clearPreviewState()
                root.lastActionError = text.length > 0 ? text : ((purpose === "preview")
                    ? Translation.tr("Failed to preview display change.")
                    : ((purpose === "preview-revert" || purpose === "preview-revert-after-failure" || purpose === "apply-and-persist-rollback")
                        ? Translation.tr("Failed to revert display change.")
                        : Translation.tr("Failed to apply display change.")))
            }
            root.clearApplyOutputState()
        }
    }

    Process {
        id: persistOutputProcess
        stdout: StdioCollector { id: persistOutputCollector }
        stderr: StdioCollector { id: persistOutputErrorCollector }
        onExited: (exitCode) => {
            const purpose = root.persistOutputPurpose
            const text = (persistOutputErrorCollector.text || persistOutputCollector.text || "").trim()
            if (exitCode === 0) {
                root.lastActionError = ""
                if (purpose === "preview-confirm")
                    root.clearPreviewState()
                root.saveAndRefresh(Translation.tr("Display settings saved."))
                root.loadOutputs()
            } else {
                root.lastActionError = text.length > 0 ? text : Translation.tr("Failed to save display settings.")

                if (purpose === "preview-confirm" && root.persistRollbackKey.length > 0 && root.persistRollbackValue.length > 0) {
                    root.pendingActionLabel = Translation.tr("Reverting display preview")
                    root.startOutputApply(root.persistOutputTargetName, root.persistRollbackKey, root.persistRollbackValue, "preview-revert-after-failure", "", "")
                } else if (purpose === "apply-and-persist" && root.persistRollbackKey.length > 0 && root.persistRollbackValue.length > 0) {
                    root.startOutputApply(root.persistOutputTargetName, root.persistRollbackKey, root.persistRollbackValue, "apply-and-persist-rollback", "", "")
                } else if (purpose === "preview-confirm") {
                    root.clearPreviewState()
                }
            }
            root.clearPersistOutputState()
        }
    }

    Process {
        id: setProcess
        stdout: StdioCollector { id: setCollector }
        stderr: StdioCollector { id: setErrorCollector }
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                root.lastActionError = (setErrorCollector.text || setCollector.text || Translation.tr("Failed to update Niri configuration.")).trim()
                root.pendingSetSection = ""
                root.pendingActionLabel = ""
                root.runNextSetRequest()
                return
            }

            root.lastActionError = ""

            if (root.pendingSetSection === "input") {
                root.loadInput()
            } else if (root.pendingSetSection === "layout") {
                root.loadLayout()
            } else if (root.pendingSetSection === "animations") {
                root.loadAnimations()
            } else if (root.pendingSetSection === "window-rules") {
                root.loadWindowRules()
            }

            root.saveAndRefresh(Translation.tr("Niri configuration updated."))
            root.pendingSetSection = ""
            root.pendingActionLabel = ""
            root.runNextSetRequest()
        }
    }

    // =====================
    // DISPLAY CONFIRMATION OVERLAY
    // =====================
    Item {
        id: confirmBanner
        visible: root.confirmationPending
        Layout.fillWidth: true
        implicitHeight: confirmCol.implicitHeight + 24

        // Auto-scroll to this banner when confirmation becomes pending
        onVisibleChanged: {
            if (visible) {
                // mapToItem(null, ...) gives the y in content coordinates via the layout
                // Use a small delay so the layout has time to position the item
                scrollToBannerTimer.restart()
            }
        }

        Timer {
            id: scrollToBannerTimer
            interval: 50
            onTriggered: {
                // Scroll the flickable so the banner is near the top with some padding
                const bannerY = confirmBanner.mapToItem(root.contentItem, 0, 0).y
                if (bannerY < root.contentY || bannerY > root.contentY + root.height - confirmBanner.height) {
                    root.contentY = Math.max(0, bannerY - 16)
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer2
            radius: Appearance.rounding.screenRounding
            border.width: 2
            border.color: Appearance.colors.colPrimary

            ColumnLayout {
                id: confirmCol
                anchors {
                    fill: parent
                    margins: 16
                }
                spacing: 12

                RowLayout {
                    spacing: 8

                    MaterialSymbol {
                        text: "monitor"
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: Appearance.colors.colPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: Translation.tr("Keep these display settings?")
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            text: Translation.tr("Reverting in %1 seconds...").arg(root.confirmCountdown)
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: {
                                if (root.pendingPreviewKind === "mode")
                                    return Translation.tr("Previewing %1").arg(root.pendingChangeValue)
                                if (root.pendingPreviewKind === "scale")
                                    return Translation.tr("Previewing scale %1x").arg(root.pendingChangeValue)
                                if (root.pendingPreviewKind === "transform")
                                    return Translation.tr("Previewing rotation %1").arg(root.pendingChangeValue)
                                return ""
                            }
                            visible: text.length > 0
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colPrimary
                        }
                    }
                }

                // Countdown bar
                Rectangle {
                    Layout.fillWidth: true
                    height: 4
                    radius: 2
                    color: Appearance.colors.colLayer1

                    Rectangle {
                        width: parent.width * (root.confirmCountdown / 15.0)
                        height: parent.height
                        radius: 2
                        color: Appearance.colors.colPrimary

                        Behavior on width {
                            NumberAnimation { duration: 900; easing.type: Easing.Linear }
                        }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: 8

                    Button {
                        text: Translation.tr("Revert")
                        onClicked: root.revertDisplayChange()

                        background: Rectangle {
                            implicitWidth: 80
                            implicitHeight: 36
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer1
                        }

                        contentItem: StyledText {
                            text: parent.text
                            color: Appearance.colors.colOnLayer1
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: Translation.tr("Keep changes")
                        onClicked: root.confirmDisplayChange()

                        background: Rectangle {
                            implicitWidth: 120
                            implicitHeight: 36
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colPrimary
                        }

                        contentItem: StyledText {
                            text: parent.text
                            color: Appearance.colors.colOnPrimary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }

    component NiriFieldSlider: StyledSlider {
        Layout.fillWidth: !isVertical && customLength <= 0
        Layout.maximumWidth: isVertical || customLength > 0 ? implicitWidth : Math.round(520 * Appearance.fontSizeScale)
    }

    SettingsTaskNavigator {
        showTabBar: true
        showIntro: false
        icon: "monitor"
        title: Translation.tr("Display & Input")
        description: Translation.tr("Tune displays, input, layout and rules; unconfirmed display previews revert.")
        summary: Translation.tr("Displays & Visibility · Windows & Tiling · Mouse & Touchpad")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Displays & Monitors"), icon: "desktop_windows", value: "displays" },
            { displayName: Translation.tr("Windows & Tiling"), icon: "grid_view", value: "windows" },
            { displayName: Translation.tr("Input"), icon: "mouse", value: "input" }
        ]
    }

    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "displays"
        visible: true
        expanded: true
        icon: "display_settings"
        title: Translation.tr("Monitors & Arrangement")

        SettingsGroup {
            id: arrangementFields
            fieldColumns: width >= 700 * Appearance.fontSizeScale ? 2 : 1
            MonitorVisibilityConfig {
                id: niriArrangementEmbed
                visible: CompositorService.isNiri
                embeddedArrangementOnly: true
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                settingsFormPreview: true
                Layout.preferredHeight: implicitHeight
                implicitHeight: niriOutputNames().length > 1 ? 300 : 215
                interactive: false
                activeSection: "outputs"
            }

            Rectangle {
                id: fallbackArrangementPreview
                visible: !CompositorService.isNiri
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredHeight: implicitHeight
                implicitHeight: 184 * Appearance.fontSizeScale
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 10

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 210
                        implicitHeight: 126
                        radius: Appearance.rounding.normal
                        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
                        border.width: 2
                        border.color: Appearance.colors.colPrimary

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                text: "desktop_windows"
                                iconSize: Appearance.font.pixelSize.hugeass
                                color: Appearance.colors.colPrimary
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.currentOutputName || Translation.tr("Primary Output")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.currentResolution || "1920x1080"
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.family: Appearance.font.family.monospace
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Interactive output drag requires Niri compositor")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Primary monitor")
                tooltip: Translation.tr("Fallback output for single-screen surfaces.")

                StyledComboBox {
                    Layout.fillWidth: true
                    model: root.primaryMonitorOptions
                    textRole: "displayName"
                    currentIndex: root.choiceIndex(model, root.configuredPrimaryMonitor)
                    onActivated: {
                        const val = model[currentIndex]?.value ?? ""
                        Config.setNestedValue("display.primaryMonitor", val)
                    }
                }
            }
        }
    }

    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "displays"
        visible: true
        expanded: true
        icon: "monitor"
        title: Translation.tr("Displays")

        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Display previews revert after 15 seconds unless confirmed.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: 44
                visible: root.currentOutput !== null

                RowLayout {
                    id: monitorInfoRow
                    anchors {
                        left: parent.left; right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 8; rightMargin: 8
                    }
                    spacing: 10

                    MaterialSymbol {
                        text: "monitor"
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: Appearance.colors.colPrimary
                    }

                    ColumnLayout {
                        visible: root.effectiveOutputList.length <= 1
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: root.currentOutputName
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                const o = root.currentOutput
                                if (!o) return ""
                                const make = o.make ?? ""
                                const model = o.model ?? ""
                                const phys = o.physical_size ?? [0, 0]
                                let info = `${make} ${model}`.trim()
                                if (phys[0] > 0 && phys[1] > 0) {
                                    const diag = Math.sqrt(phys[0]*phys[0] + phys[1]*phys[1]) / 25.4
                                    info += ` — ${diag.toFixed(1)}"`
                                }
                                return info
                            }
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }

                    StyledComboBox {
                        id: monitorSelectorCombo
                        visible: root.effectiveOutputList.length > 1
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        enabled: root.effectiveOutputList.length > 1
                        model: root.effectiveOutputList.map(o => ({
                            displayName: `${o.name} — ${o.make ?? ""} ${o.model ?? ""}`.trim(),
                            value: o.name
                        }))
                        textRole: "displayName"
                        currentIndex: Math.max(0, root.choiceIndex(model, root.currentOutputName))
                        onActivated: {
                            const idx = root.effectiveOutputList.findIndex(o => o.name === model[currentIndex]?.value)
                            if (idx >= 0)
                                root.selectedOutputIndex = idx
                        }
                    }
                }
            }

            SettingsDivider { visible: root.currentOutput !== null }

            ConfigRow {
                uniform: true
                ContentSubsection {
                    title: Translation.tr("Resolution")
                    visible: root.resolutionOptions.length > 0

                    StyledComboBox {
                        id: resolutionCombo
                        Layout.fillWidth: true
                        enabled: !root.displayControlsLocked
                        model: root.resolutionOptions
                        textRole: "displayName"
                        onActivated: {
                            const selectedValue = model[currentIndex].value
                            const match = root.currentOutput?.resolutions?.find(r => `${r.width}x${r.height}` === selectedValue)
                            if (match?.rates?.length > 0) {
                                const best = match.rates.reduce((a, b) => a.rate > b.rate ? a : b)
                                root.safeApplyOutput("mode", "mode", `${selectedValue}@${best.rate_string ?? Number(best.rate).toFixed(3)}`)
                            }
                        }
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Refresh rate")
                    visible: root.resolutionOptions.length > 0

                    StyledComboBox {
                        id: refreshRateCombo
                        Layout.fillWidth: true
                        enabled: !root.displayControlsLocked && root.refreshOptions.length > 1
                        model: root.refreshOptions
                        textRole: "displayName"
                        onActivated: root.safeApplyOutput("mode", "mode", `${root.currentResolution}@${model[currentIndex].rateString}`)
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                visible: root.currentOutput !== null
                columns: width >= 680 * Appearance.fontSizeScale ? 2 : 1
                uniformCellWidths: columns > 1
                columnSpacing: 16
                rowSpacing: 12

                ContentSubsection {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    title: Translation.tr("Scale")

                    Flow {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
                            delegate: RippleButton {
                                required property real modelData
                                readonly property bool activeScale: Math.abs((root.currentOutput?.scale ?? 1.0) - modelData) < 0.01
                                enabled: !root.displayControlsLocked
                                implicitHeight: 28
                                implicitWidth: Math.max(52, scalePillLabel.implicitWidth + 18)
                                buttonRadius: Appearance.rounding.full
                                toggled: activeScale
                                colBackground: Appearance.colors.colLayer2
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colBackgroundToggled: Appearance.colors.colPrimary
                                colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                                onClicked: root.safeApplyOutput("scale", "scale", String(modelData))
                                contentItem: StyledText {
                                    id: scalePillLabel
                                    anchors.centerIn: parent
                                    text: Math.round(parent.modelData * 100) + "%"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.family: Appearance.font.family.monospace
                                    color: parent.toggled
                                        ? (parent.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1)
                                        : Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }

                    StyledComboBox {
                        id: scaleCombo
                        Layout.fillWidth: true
                        enabled: !root.displayControlsLocked
                        model: root.scaleOptions
                        textRole: "displayName"
                        onActivated: root.safeApplyOutput("scale", "scale", String(model[currentIndex].value))
                    }
                }

                ContentSubsection {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    title: Translation.tr("Rotation")

                    StyledComboBox {
                        id: rotationCombo
                        Layout.fillWidth: true
                        enabled: !root.displayControlsLocked
                        model: root.transformOptions
                        textRole: "displayName"
                        onActivated: root.safeApplyOutput("transform", "transform", model[currentIndex].value)
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Output position")
                tooltip: Translation.tr("Logical coordinates in Niri's global space.")
                visible: root.currentOutput !== null

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ConfigSpinBox {
                        id: positionXSpin
                        Layout.fillWidth: true
                        enabled: !root.displayControlsLocked
                        text: "X"
                        value: root.currentOutput?.position?.x ?? 0
                        from: -10000
                        to: 10000
                        stepSize: 10
                        onValueChanged: {
                            if (!root.outputReady || !root.positionEditorReady) return
                            root.applyAndPersistOutput("position", `${value},${positionYSpin.value}`)
                        }
                    }

                    ConfigSpinBox {
                        id: positionYSpin
                        Layout.fillWidth: true
                        enabled: !root.displayControlsLocked
                        text: "Y"
                        value: root.currentOutput?.position?.y ?? 0
                        from: -10000
                        to: 10000
                        stepSize: 10
                        onValueChanged: {
                            if (!root.outputReady || !root.positionEditorReady) return
                            root.applyAndPersistOutput("position", `${positionXSpin.value},${value}`)
                        }
                    }
                }
            }

            SettingsDivider { visible: root.currentOutput !== null }

            ContentSubsection {
                title: Translation.tr("Variable refresh rate (VRR)")
                tooltip: Translation.tr("Adaptive sync / FreeSync / G-Sync.")
                visible: root.currentOutput !== null

                StyledComboBox {
                    id: vrrCombo
                    Layout.fillWidth: true
                    enabled: !root.displayControlsLocked && root.vrrSupported
                    model: root.vrrSupported
                        ? root.vrrOptions
                        : [{ value: "off", displayName: Translation.tr("Not supported on this display") }]
                    textRole: "displayName"
                    onActivated: {
                        if (!root.outputReady || !root.vrrSupported) return
                        root.applyAndPersistOutput("vrr", model[currentIndex].value)
                    }
                }
            }
        }
    }

    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "displays"
        visible: true
        expanded: true
        icon: "wallpaper"
        title: Translation.tr("Desktop Widgets & Wallpapers")

        SettingsGroup {
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitHeight: 34
                    materialIcon: "filter_1"
                    mainText: Translation.tr("Primary only")
                    onClicked: root.setAllShellSurfacesToPrimary()
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitHeight: 34
                    materialIcon: "select_all"
                    mainText: Translation.tr("All outputs")
                    onClicked: root.setAllShellSurfacesToAll()
                }
            }

            SettingsDivider {}

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "wallpaper_slideshow"
                    text: Translation.tr("Per-monitor wallpapers")
                    checked: Config.options?.background?.multiMonitor?.enable ?? false
                    onCheckedChanged: Config.setNestedValue("background.multiMonitor.enable", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "fullscreen_exit"
                    text: Translation.tr("Hide on fullscreen")
                    checked: Config.options?.background?.hideWhenFullscreen ?? true
                    onCheckedChanged: Config.setNestedValue("background.hideWhenFullscreen", checked)
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "blur_on"
                    text: Translation.tr("Overview backdrop")
                    checked: Config.options?.background?.backdrop?.enable ?? true
                    onCheckedChanged: Config.setNestedValue("background.backdrop.enable", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "animation"
                    text: Translation.tr("Wallpaper transitions")
                    checked: Config.options?.background?.transition?.enable ?? true
                    onCheckedChanged: Config.setNestedValue("background.transition.enable", checked)
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "pause_circle"
                    text: Translation.tr("Pause widgets fullscreen")
                    checked: Config.options?.background?.widgets?.powerSaving?.pauseOnFullscreen ?? true
                    onCheckedChanged: Config.setNestedValue("background.widgets.powerSaving.pauseOnFullscreen", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "sports_esports"
                    text: Translation.tr("Pause widgets GameMode")
                    checked: Config.options?.background?.widgets?.powerSaving?.pauseOnGameMode ?? true
                    onCheckedChanged: Config.setNestedValue("background.widgets.powerSaving.pauseOnGameMode", checked)
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "motion_photos_on"
                    text: Translation.tr("Animate wallpapers")
                    checked: Config.options?.background?.enableAnimation ?? true
                    onCheckedChanged: Config.setNestedValue("background.enableAnimation", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    enabled: Config.options?.background?.enableAnimation ?? true
                    buttonIcon: "battery_saver"
                    text: Translation.tr("Pause on battery")
                    checked: Config.options?.background?.pauseAnimationOnBattery ?? true
                    onCheckedChanged: Config.setNestedValue("background.pauseAnimationOnBattery", checked)
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "autorenew"
                    text: Translation.tr("Auto-cycle wallpapers")
                    checked: Config.options?.background?.autoWallpaper?.enable ?? false
                    onCheckedChanged: Config.setNestedValue("background.autoWallpaper.enable", checked)
                }

                ConfigSpinBox {
                    enabled: Config.options?.background?.autoWallpaper?.enable ?? false
                    icon: "schedule"
                    text: Translation.tr("Cycle (min)")
                    value: Config.options?.background?.autoWallpaper?.intervalMinutes ?? 30
                    from: 5
                    to: 240
                    stepSize: 5
                    onValueChanged: Config.setNestedValue("background.autoWallpaper.intervalMinutes", value)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.preferredWidth: 126
                    Layout.minimumWidth: 0
                    text: Translation.tr("Desktop widgets")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 6

                    RippleButton {
                        implicitHeight: 28
                        implicitWidth: Math.max(46, allWidgetText.implicitWidth + 18)
                        buttonRadius: Appearance.rounding.full
                        toggled: root.surfaceAllScreensEnabled("background.widgets.screenList")
                        onClicked: root.setSurfaceAllScreens("background.widgets.screenList")
                        contentItem: StyledText {
                            id: allWidgetText
                            text: Translation.tr("All")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: parent.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }
                    }

                    Repeater {
                        model: root.knownScreens
                        delegate: RippleButton {
                            required property string modelData
                            implicitHeight: 28
                            implicitWidth: Math.max(48, widgetScreenText.implicitWidth + 18)
                            buttonRadius: Appearance.rounding.full
                            toggled: !root.surfaceAllScreensEnabled("background.widgets.screenList")
                                     && root.surfaceScreenEnabled("background.widgets.screenList", modelData)
                            onClicked: root.toggleSurfaceScreen("background.widgets.screenList", modelData)
                            contentItem: StyledText {
                                id: widgetScreenText
                                text: modelData
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: parent.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.preferredWidth: 126
                    Layout.minimumWidth: 0
                    text: Translation.tr("OSD popups")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 6

                    RippleButton {
                        implicitHeight: 28
                        implicitWidth: Math.max(46, allOsdScreenText.implicitWidth + 18)
                        buttonRadius: Appearance.rounding.full
                        toggled: root.surfaceAllScreensEnabled("osd.screenList")
                        onClicked: root.setSurfaceAllScreens("osd.screenList")
                        contentItem: StyledText {
                            id: allOsdScreenText
                            text: Translation.tr("All")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: parent.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }
                    }

                    Repeater {
                        model: root.knownScreens
                        delegate: RippleButton {
                            required property string modelData
                            implicitHeight: 28
                            implicitWidth: Math.max(48, osdScreenText.implicitWidth + 18)
                            buttonRadius: Appearance.rounding.full
                            toggled: !root.surfaceAllScreensEnabled("osd.screenList")
                                     && root.surfaceScreenEnabled("osd.screenList", modelData)
                            onClicked: root.toggleSurfaceScreen("osd.screenList", modelData)
                            contentItem: StyledText {
                                id: osdScreenText
                                text: modelData
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: parent.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "displays"
        visible: true
        expanded: true
        icon: "view_sidebar"
        title: Translation.tr("Bar, Sidebars & Shell Surfaces")

    SettingsGroup {
        Repeater {
            model: root.shellVisibilitySurfaces.slice(0, 5)
            delegate: RowLayout {
                id: surfaceVisRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.preferredWidth: 126
                    Layout.minimumWidth: 0
                    text: surfaceVisRow.modelData.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 6

                    RippleButton {
                        implicitHeight: 28
                        implicitWidth: Math.max(46, allSurfText.implicitWidth + 18)
                        buttonRadius: Appearance.rounding.full
                        toggled: root.surfaceAllScreensEnabled(surfaceVisRow.modelData.path)
                        onClicked: root.setSurfaceAllScreens(surfaceVisRow.modelData.path)
                        contentItem: StyledText {
                            id: allSurfText
                            text: Translation.tr("All")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: parent.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }
                    }

                    Repeater {
                        model: root.knownScreens
                        delegate: RippleButton {
                            required property string modelData
                            implicitHeight: 28
                            implicitWidth: Math.max(48, surfScreenText.implicitWidth + 18)
                            buttonRadius: Appearance.rounding.full
                            toggled: !root.surfaceAllScreensEnabled(surfaceVisRow.modelData.path)
                                     && root.surfaceScreenEnabled(surfaceVisRow.modelData.path, modelData)
                            onClicked: root.toggleSurfaceScreen(surfaceVisRow.modelData.path, modelData)
                            contentItem: StyledText {
                                id: surfScreenText
                                text: modelData
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: parent.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }
    }
}

    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "displays"
        visible: true
        expanded: true
        icon: "night_sight_auto"
        title: Translation.tr("Night Light & Eye Comfort")

    SettingsGroup {
        ConfigRow {
            uniform: true

            SettingsSwitch {
                Layout.fillWidth: true
                buttonIcon: "lightbulb"
                text: Translation.tr("Night Light")
                checked: Hyprsunset.active
                onCheckedChanged: {
                    if (checked !== Hyprsunset.active)
                        Hyprsunset.toggle(checked)
                }
            }

            SettingsSwitch {
                Layout.fillWidth: true
                buttonIcon: "schedule"
                text: Translation.tr("Auto schedule")
                checked: Config.options?.light?.night?.automatic ?? true
                onCheckedChanged: Config.setNestedValue("light.night.automatic", checked)
            }
        }

        ContentSubsection {
            title: Translation.tr("Color temperature")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                NiriFieldSlider {
                    id: nightTempSlider
                    from: 1200
                    to: 6500
                    stepSize: 100
                    value: Config.options?.light?.night?.colorTemperature ?? 5000
                    liveValue: Config.options?.light?.night?.colorTemperature ?? 5000
                    configuration: StyledSlider.Configuration.S
                    onMoved: {
                        if (pressed) return
                        Config.setNestedValue("light.night.colorTemperature", Math.round(value))
                    }
                }

                StyledText {
                    text: Math.round(nightTempSlider.value) + " K"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colSubtext
                    Layout.preferredWidth: 48
                    horizontalAlignment: Text.AlignRight
                }
            }
        }

        SettingsDivider {}

        ConfigRow {
            uniform: true

            SettingsSwitch {
                Layout.fillWidth: true
                buttonIcon: "flash_off"
                text: Translation.tr("Anti-flashbang")
                checked: Config.options?.light?.antiFlashbang?.enable ?? false
                onCheckedChanged: Config.setNestedValue("light.antiFlashbang.enable", checked)
            }

            SettingsSwitch {
                Layout.fillWidth: true
                buttonIcon: "dark_mode"
                text: Translation.tr("Dark mode only")
                checked: Config.options?.light?.antiFlashbang?.darkOnly ?? true
                onCheckedChanged: Config.setNestedValue("light.antiFlashbang.darkOnly", checked)
            }
        }
    }
}

    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "windows"
        visible: true
        expanded: true
        icon: "rounded_corner"
        title: Translation.tr("Window Rules")

    SettingsGroup {
            id: rulesFields
            fieldColumns: width >= 700 * Appearance.fontSizeScale ? 2 : 1
        ContentSubsection {
            title: Translation.tr("Corner radius")
            tooltip: Translation.tr("Rounding applied to window corners (0 = square)")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                NiriFieldSlider {
                    id: cornerRadiusSlider
                    from: 0
                    to: 32
                    value: root.windowRulesData?.corner_radius ?? 16
                    liveValue: root.windowRulesData?.corner_radius ?? 16
                    stepSize: 1
                    configuration: StyledSlider.Configuration.S

                    onMoved: {
                        if (pressed) return
                        root.setConfig("window-rules", "corner-radius", String(Math.round(value)))
                    }
                }

                StyledText {
                    text: Math.round(cornerRadiusSlider.value) + "px"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colSubtext
                    Layout.preferredWidth: 35
                    horizontalAlignment: Text.AlignRight
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Inactive window opacity")
            tooltip: Translation.tr("Transparency of unfocused windows (1.0 = fully opaque)")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                NiriFieldSlider {
                    id: inactiveOpacitySlider
                    from: 0
                    to: 100
                    value: Math.round((root.windowRulesData?.inactive_opacity ?? 0.9) * 100)
                    liveValue: Math.round((root.windowRulesData?.inactive_opacity ?? 0.9) * 100)
                    stepSize: 5
                    configuration: StyledSlider.Configuration.S

                    onMoved: {
                        if (pressed) return
                        root.setConfig("window-rules", "inactive-opacity", (value / 100.0).toFixed(2))
                    }
                }

                StyledText {
                    text: (inactiveOpacitySlider.value / 100.0).toFixed(2)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colSubtext
                    Layout.preferredWidth: 35
                    horizontalAlignment: Text.AlignRight
                }
            }
        }

        ConfigRow {
            Layout.columnSpan: rulesFields.activeColumns
            uniform: true

            SettingsSwitch {
                id: clipToGeometrySwitch
                Layout.fillWidth: true
                buttonIcon: "crop"
                text: Translation.tr("Clip rounded geometry")
                checked: root.windowRulesData?.clip_to_geometry ?? true
                onCheckedChanged: {
                    if (!root.windowRulesReady) return
                    root.setConfig("window-rules", "clip-to-geometry", checked ? "true" : "false")
                }
            }

            SettingsSwitch {
                Layout.fillWidth: true
                buttonIcon: "help"
                text: Translation.tr("Confirm window close")
                checked: Config.options?.closeConfirm?.enabled ?? false
                onCheckedChanged: Config.setNestedValue("closeConfirm.enabled", checked)
            }
        }
    }
}

    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "windows"
        visible: true
        expanded: true
        icon: "animation"
        title: Translation.tr("Motion & Animations")

        SettingsGroup {
            id: motionFields
            fieldColumns: width >= 700 * Appearance.fontSizeScale ? 2 : 1
            Rectangle {
                id: motionPreviewStage
                Layout.alignment: Qt.AlignTop
                objectName: "niriMotionPreviewStage"
                Layout.fillWidth: true
                implicitHeight: 92
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: SettingsMaterialPreset.groupBorderColor
                clip: true

                property bool previewShifted: false
                readonly property int previewDurationMs: Math.max(80, Math.round(280 * Math.max(0.5, (slowdownSlider.value / 100.0))))

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 14

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 68

                        Rectangle {
                            width: 112
                            height: 54
                            anchors.verticalCenter: parent.verticalCenter
                            x: motionPreviewStage.previewShifted
                                ? Math.max(0, parent.width - width - 8)
                                : 8
                            radius: Math.min(18, Math.max(4, Math.round(cornerRadiusSlider.value)))
                            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84)
                            border.width: 2
                            border.color: Appearance.colors.colPrimary

                            Behavior on x {
                                enabled: animationsEnabledSwitch.checked
                                NumberAnimation {
                                    duration: motionPreviewStage.previewDurationMs
                                    easing.type: Easing.OutCubic
                                }
                            }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6

                                MaterialSymbol {
                                    text: "motion_mode"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colPrimary
                                }

                                StyledText {
                                    text: (slowdownSlider.value / 100.0).toFixed(2) + "x"
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.family: Appearance.font.family.monospace
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }

                    RippleButtonWithIcon {
                        implicitHeight: 34
                        materialIcon: "play_arrow"
                        mainText: Translation.tr("Preview motion")
                        onClicked: motionPreviewStage.previewShifted = !motionPreviewStage.previewShifted
                    }
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    id: animationsEnabledSwitch
                Layout.fillWidth: true
                buttonIcon: "animation"
                text: Translation.tr("Compositor animations")
                checked: root.animationsData?.enabled ?? true
                onCheckedChanged: {
                    if (!root.animationsReady) return
                    root.setBooleanConfig("animations", "enabled", checked)
                }
            }

            SettingsSwitch {
                Layout.fillWidth: true
                buttonIcon: "sports_esports"
                text: Translation.tr("Skip in GameMode")
                checked: Config.options?.gameMode?.disableNiriAnimations ?? true
                onCheckedChanged: Config.setNestedValue("gameMode.disableNiriAnimations", checked)
            }
        }

        ContentSubsection {
            title: Translation.tr("Global animation slowdown")
            tooltip: Translation.tr("1.0 is normal speed. Higher values make every animation slower.")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                NiriFieldSlider {
                    id: slowdownSlider
                    from: 50
                    to: 500
                    value: Math.round((root.animationsData?.slowdown ?? 1.0) * 100)
                    liveValue: Math.round((root.animationsData?.slowdown ?? 1.0) * 100)
                    stepSize: 10
                    configuration: StyledSlider.Configuration.S
                    onMoved: {
                        if (pressed) return
                        root.setConfig("animations", "slowdown", (value / 100.0).toFixed(2))
                    }
                }

                StyledText {
                    text: (slowdownSlider.value / 100.0).toFixed(2) + "x"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colSubtext
                    Layout.preferredWidth: 42
                    horizontalAlignment: Text.AlignRight
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Animation events")

            ConfigRow {
                uniform: true
                enabled: animationsEnabledSwitch.checked

                SettingsSwitch {
                    id: animWorkspaceSwitch
                    Layout.fillWidth: true
                    buttonIcon: "swap_vert"
                    text: Translation.tr("Workspace switch")
                    checked: !(root.animationsData?.types?.["workspace-switch"]?.off ?? false)
                    onCheckedChanged: {
                        if (!root.animationsReady) return
                        root.setBooleanConfig("animations", "workspace-switch.enabled", checked)
                    }
                }

                SettingsSwitch {
                    id: animOverviewSwitch
                    Layout.fillWidth: true
                    buttonIcon: "grid_view"
                    text: Translation.tr("Overview")
                    checked: !(root.animationsData?.types?.["overview-open-close"]?.off ?? false)
                    onCheckedChanged: {
                        if (!root.animationsReady) return
                        root.setBooleanConfig("animations", "overview-open-close.enabled", checked)
                    }
                }
            }

            ConfigRow {
                uniform: true
                enabled: animationsEnabledSwitch.checked

                SettingsSwitch {
                    id: animWindowOpenSwitch
                    Layout.fillWidth: true
                    buttonIcon: "open_in_full"
                    text: Translation.tr("Window open")
                    checked: !(root.animationsData?.types?.["window-open"]?.off ?? false)
                    onCheckedChanged: {
                        if (!root.animationsReady) return
                        root.setBooleanConfig("animations", "window-open.enabled", checked)
                    }
                }

                SettingsSwitch {
                    id: animWindowCloseSwitch
                    Layout.fillWidth: true
                    buttonIcon: "close_fullscreen"
                    text: Translation.tr("Window close")
                    checked: !(root.animationsData?.types?.["window-close"]?.off ?? false)
                    onCheckedChanged: {
                        if (!root.animationsReady) return
                        root.setBooleanConfig("animations", "window-close.enabled", checked)
                    }
                }
            }

            ConfigRow {
                uniform: true
                enabled: animationsEnabledSwitch.checked

                SettingsSwitch {
                    id: animHorizontalScrollSwitch
                    Layout.fillWidth: true
                    buttonIcon: "swap_horiz"
                    text: Translation.tr("Horizontal scroll")
                    checked: !(root.animationsData?.types?.["horizontal-view-movement"]?.off ?? false)
                    onCheckedChanged: {
                        if (!root.animationsReady) return
                        root.setBooleanConfig("animations", "horizontal-view-movement.enabled", checked)
                    }
                }

                SettingsSwitch {
                    id: animWindowResizeSwitch
                    Layout.fillWidth: true
                    buttonIcon: "aspect_ratio"
                    text: Translation.tr("Window resize")
                    checked: !(root.animationsData?.types?.["window-resize"]?.off ?? false)
                    onCheckedChanged: {
                        if (!root.animationsReady) return
                        root.setBooleanConfig("animations", "window-resize.enabled", checked)
                    }
                }
            }
        }
    }
}

    // =====================
    // WINDOW CHROME & STRUTS (LEFT COLUMN)
    // =====================
    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "windows"
        visible: true
        expanded: true
        icon: "web_asset"
        title: Translation.tr("Window Chrome & Struts")

        SettingsGroup {
            ConfigRow {
                uniform: true

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "title"
                    text: Translation.tr("Shell window titlebars")
                    checked: Config.options?.windows?.showTitlebar ?? true
                    onCheckedChanged: Config.setNestedValue("windows.showTitlebar", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "format_align_center"
                    text: Translation.tr("Center window titles")
                    checked: Config.options?.windows?.centerTitle ?? true
                    onCheckedChanged: Config.setNestedValue("windows.centerTitle", checked)
                }
            }

            SettingsDivider {}

            ContentSubsection {
                title: Translation.tr("Outer workspace struts (px)")
                tooltip: Translation.tr("Extra reserved margins at screen edges.")

                ConfigRow {
                    uniform: true

                    ConfigSpinBox {
                        id: strutLeftSpin
                        text: Translation.tr("Left")
                        value: root.layoutData?.struts?.left ?? 0
                        from: 0
                        to: 128
                        stepSize: 2
                        onValueChanged: {
                            if (!root.layoutReady) return
                            root.setConfig("layout", "struts.left", value)
                        }
                    }

                    ConfigSpinBox {
                        id: strutRightSpin
                        text: Translation.tr("Right")
                        value: root.layoutData?.struts?.right ?? 0
                        from: 0
                        to: 128
                        stepSize: 2
                        onValueChanged: {
                            if (!root.layoutReady) return
                            root.setConfig("layout", "struts.right", value)
                        }
                    }
                }

                ConfigRow {
                    uniform: true

                    ConfigSpinBox {
                        id: strutTopSpin
                        text: Translation.tr("Top")
                        value: root.layoutData?.struts?.top ?? 0
                        from: 0
                        to: 128
                        stepSize: 2
                        onValueChanged: {
                            if (!root.layoutReady) return
                            root.setConfig("layout", "struts.top", value)
                        }
                    }

                    ConfigSpinBox {
                        id: strutBottomSpin
                        text: Translation.tr("Bottom")
                        value: root.layoutData?.struts?.bottom ?? 0
                        from: 0
                        to: 128
                        stepSize: 2
                        onValueChanged: {
                            if (!root.layoutReady) return
                            root.setConfig("layout", "struts.bottom", value)
                        }
                    }
                }
            }

            SettingsDivider {}

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    icon: "table_rows"
                    text: Translation.tr("Overview rows")
                    value: Math.round(Config.options?.overview?.rows ?? 3)
                    from: 1
                    to: 6
                    stepSize: 1
                    onValueChanged: Config.setNestedValue("overview.rows", value)
                }

                ConfigSpinBox {
                    icon: "view_column"
                    text: Translation.tr("Overview columns")
                    value: Math.round(Config.options?.overview?.columns ?? 1)
                    from: 1
                    to: 8
                    stepSize: 1
                    onValueChanged: Config.setNestedValue("overview.columns", value)
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "view_compact"
                    text: Translation.tr("Compact Alt-Tab")
                    checked: Config.options?.altSwitcher?.compactStyle ?? false
                    onCheckedChanged: Config.setNestedValue("altSwitcher.compactStyle", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "layers"
                    text: Translation.tr("Overview on Alt-Tab")
                    checked: Config.options?.altSwitcher?.showOverviewWhileSwitching ?? false
                    onCheckedChanged: Config.setNestedValue("altSwitcher.showOverviewWhileSwitching", checked)
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "ads_click"
                    text: Translation.tr("Overview hover preview")
                    checked: Config.options?.overview?.workspaceHover?.enable ?? true
                    onCheckedChanged: Config.setNestedValue("overview.workspaceHover.enable", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "desktop_windows"
                    text: Translation.tr("Active screen overview")
                    checked: Config.options?.overview?.activeScreenOnly ?? true
                    onCheckedChanged: Config.setNestedValue("overview.activeScreenOnly", checked)
                }
            }
        }
    }

    // =====================
    // LAYOUT SECTION
    // =====================
    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "windows"
        visible: true
        expanded: true
        icon: "grid_view"
        title: Translation.tr("Tiling & Columns")

        SettingsGroup {
            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    id: layoutGapsSpin
                    text: Translation.tr("Window gap (px)")
                    value: root.layoutData?.gaps ?? 25
                    from: 0
                    to: 64
                    stepSize: 1
                    onValueChanged: {
                        if (!root.layoutReady) return
                        root.setConfig("layout", "gaps", value)
                    }
                }

                ConfigSpinBox {
                    id: overviewZoomSpin
                    text: Translation.tr("Overview zoom")
                    value: Math.round((root.layoutData?.overview_zoom ?? 0.75) * 100)
                    from: 30
                    to: 100
                    stepSize: 5
                    onValueChanged: {
                        if (!root.layoutReady) return
                        root.setConfig("layout", "overview.zoom", (value / 100.0).toFixed(2))
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Focus behavior")
                tooltip: Translation.tr("When to center the focused column on screen")

                ConfigSelectionArray {
                    currentValue: root.layoutData?.center_focused ?? "never"
                    options: [
                        { displayName: Translation.tr("Never"), icon: "align_horizontal_left", value: "never" },
                        { displayName: Translation.tr("On overflow"), icon: "align_horizontal_center", value: "on-overflow" },
                        { displayName: Translation.tr("Always"), icon: "center_focus_strong", value: "always" }
                    ]
                    onSelected: newValue => {
                        root.setConfig("layout", "center-focused-column", newValue)
                    }
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    id: alwaysCenterSingleColumnSwitch
                    Layout.fillWidth: true
                    buttonIcon: "center_focus_strong"
                    text: Translation.tr("Center single column")
                    checked: root.layoutData?.always_center_single_column ?? false
                    onCheckedChanged: {
                        if (!root.layoutReady) return
                        root.setBooleanConfig("layout", "always-center-single-column", checked)
                    }
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "fullscreen"
                    text: Translation.tr("Auto-expand single")
                    checked: Config.options?.compositor?.autoExpandSingleTilingWindow ?? false
                    onCheckedChanged: Config.setNestedValue("compositor.autoExpandSingleTilingWindow", checked)
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    id: emptyWorkspaceAboveFirstSwitch
                    Layout.fillWidth: true
                    buttonIcon: "vertical_align_top"
                    text: Translation.tr("Empty space above first")
                    checked: root.layoutData?.empty_workspace_above_first ?? false
                    onCheckedChanged: {
                        if (!root.layoutReady) return
                        root.setBooleanConfig("layout", "empty-workspace-above-first", checked)
                    }
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "grid_view"
                    text: Translation.tr("Shell overview")
                    checked: Config.options?.overview?.enable ?? true
                    onCheckedChanged: Config.setNestedValue("overview.enable", checked)
                }
            }

            ContentSubsection {
                title: Translation.tr("Default column display")

                StyledComboBox {
                    id: defaultColumnDisplayCombo
                    Layout.fillWidth: true
                    model: root.defaultColumnDisplayOptions
                    textRole: "displayName"
                    currentIndex: root.choiceIndex(model, root.layoutData?.default_column_display ?? "normal")
                    onActivated: root.setConfig("layout", "default-column-display", model[currentIndex].value)
                }
            }

            SettingsDivider {}

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "tag"
                    text: Translation.tr("Workspace numbers")
                    checked: Config.options?.overview?.showWorkspaceNumbers ?? true
                    onCheckedChanged: Config.setNestedValue("overview.showWorkspaceNumbers", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "preview"
                    text: Translation.tr("Overview previews")
                    checked: Config.options?.overview?.showPreviews ?? false
                    onCheckedChanged: Config.setNestedValue("overview.showPreviews", checked)
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "swap_horiz"
                    text: Translation.tr("Alt-Tab animations")
                    checked: Config.options?.altSwitcher?.enableAnimation ?? true
                    onCheckedChanged: Config.setNestedValue("altSwitcher.enableAnimation", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "history"
                    text: Translation.tr("Recent windows first")
                    checked: Config.options?.altSwitcher?.useMostRecentFirst ?? true
                    onCheckedChanged: Config.setNestedValue("altSwitcher.useMostRecentFirst", checked)
                }
            }
        }
    }

    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "windows"
        visible: true
        expanded: true
        icon: "border_style"
        title: Translation.tr("Borders, Focus Ring & Shadow")

        SettingsGroup {
            SettingsSwitch {
                id: borderEnabledSwitch
                Layout.fillWidth: true
                buttonIcon: "border_style"
                text: Translation.tr("Enable window border")
                checked: root.layoutData?.border?.enabled ?? false
                onCheckedChanged: {
                    if (!root.layoutReady) return
                    root.setBooleanConfig("layout", "border.enabled", checked)
                }
            }

            ConfigSpinBox {
                id: borderWidthSpin
                enabled: borderEnabledSwitch.checked
                text: Translation.tr("Border width (px)")
                value: root.layoutData?.border?.width ?? 4
                from: 1
                to: 8
                stepSize: 1
                onValueChanged: {
                    if (!root.layoutReady) return
                    root.setConfig("layout", "border.width", value)
                }
            }

            SettingsDivider {}

            SettingsSwitch {
                id: focusRingEnabledSwitch
                Layout.fillWidth: true
                buttonIcon: "radio_button_checked"
                text: Translation.tr("Enable focus ring")
                checked: root.layoutData?.focus_ring?.enabled ?? false
                onCheckedChanged: {
                    if (!root.layoutReady) return
                    root.setBooleanConfig("layout", "focus-ring.enabled", checked)
                }
            }

            ConfigSpinBox {
                id: focusRingWidthSpin
                enabled: focusRingEnabledSwitch.checked
                text: Translation.tr("Focus ring width (px)")
                value: root.layoutData?.focus_ring?.width ?? 1
                from: 1
                to: 8
                stepSize: 1
                onValueChanged: {
                    if (!root.layoutReady) return
                    root.setConfig("layout", "focus-ring.width", value)
                }
            }

            SettingsDivider {}

            SettingsSwitch {
                id: shadowEnabledSwitch
                Layout.fillWidth: true
                buttonIcon: "shadow"
                text: Translation.tr("Window shadow")
                checked: root.layoutData?.shadow?.enabled ?? true
                onCheckedChanged: {
                    if (!root.layoutReady) return
                    root.setBooleanConfig("layout", "shadow.enabled", checked)
                }
            }

            ConfigRow {
                uniform: true
                enabled: shadowEnabledSwitch.checked

                ConfigSpinBox {
                    id: shadowSoftnessSpin
                    text: Translation.tr("Softness")
                    value: root.layoutData?.shadow?.softness ?? 30
                    from: 0
                    to: 120
                    stepSize: 5
                    onValueChanged: {
                        if (!root.layoutReady || !root.shadowEditorReady) return
                        root.setConfig("layout", "shadow.softness", value)
                    }
                }

                ConfigSpinBox {
                    id: shadowSpreadSpin
                    text: Translation.tr("Spread")
                    value: root.layoutData?.shadow?.spread ?? 5
                    from: 0
                    to: 40
                    stepSize: 1
                    onValueChanged: {
                        if (!root.layoutReady || !root.shadowEditorReady) return
                        root.setConfig("layout", "shadow.spread", value)
                    }
                }
            }

            ConfigRow {
                uniform: true
                enabled: shadowEnabledSwitch.checked

                ConfigSpinBox {
                    id: shadowOffsetXSpin
                    text: Translation.tr("Offset X")
                    value: root.layoutData?.shadow?.offset_x ?? 0
                    from: -40
                    to: 40
                    stepSize: 1
                    onValueChanged: {
                        if (!root.layoutReady || !root.shadowEditorReady) return
                        root.setConfig("layout", "shadow.offset", `${value},${shadowOffsetYSpin.value}`)
                    }
                }

                ConfigSpinBox {
                    id: shadowOffsetYSpin
                    text: Translation.tr("Offset Y")
                    value: root.layoutData?.shadow?.offset_y ?? 5
                    from: -40
                    to: 40
                    stepSize: 1
                    onValueChanged: {
                        if (!root.layoutReady || !root.shadowEditorReady) return
                        root.setConfig("layout", "shadow.offset", `${shadowOffsetXSpin.value},${value}`)
                    }
                }
            }
        }
    }

    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "input"
        visible: true
        expanded: true
        icon: "mouse"
        title: Translation.tr("Mouse")

    SettingsGroup {
            id: mouseFields
            fieldColumns: width >= 700 * Appearance.fontSizeScale ? 2 : 1
        ConfigRow {
            Layout.columnSpan: mouseFields.activeColumns
            uniform: true
            SettingsSwitch {
                id: focusFollowsMouseSwitch
                Layout.fillWidth: true
                buttonIcon: "mouse"
                text: Translation.tr("Focus follows mouse")
                checked: root.generalInputData?.focus_follows_mouse ?? false
                onCheckedChanged: {
                    if (!root.inputReady) return
                    root.setFocusFollowsMouse(checked)
                }
            }

            SettingsSwitch {
                id: warpMouseToFocusSwitch
                Layout.fillWidth: true
                buttonIcon: "center_focus_strong"
                text: Translation.tr("Warp pointer to focus")
                checked: root.generalInputData?.warp_mouse_to_focus ?? false
                onCheckedChanged: {
                    if (!root.inputReady) return
                    root.setWarpMouseMode(checked ? (root.generalInputData?.warp_mouse_to_focus_mode ?? "separate") : "off")
                }
            }
        }

        ConfigRow {
            Layout.columnSpan: mouseFields.activeColumns
            uniform: true

            SettingsSwitch {
                id: mouseNaturalScrollSwitch
                Layout.fillWidth: true
                buttonIcon: "swipe"
                text: Translation.tr("Natural scroll")
                checked: root.mouseData?.natural_scroll ?? false
                onCheckedChanged: {
                    if (!root.inputReady) return
                    root.setBooleanConfig("input", "mouse.natural-scroll", checked)
                }
            }

            SettingsSwitch {
                id: mouseLeftHandedSwitch
                Layout.fillWidth: true
                buttonIcon: "left_click"
                text: Translation.tr("Left-handed")
                checked: root.mouseData?.left_handed ?? false
                onCheckedChanged: {
                    if (!root.inputReady) return
                    root.setBooleanConfig("input", "mouse.left-handed", checked)
                }
            }
        }

        ConfigRow {
            Layout.columnSpan: mouseFields.activeColumns
            uniform: true

            SettingsSwitch {
                id: mouseMiddleEmulationSwitch
                Layout.fillWidth: true
                buttonIcon: "ads_click"
                text: Translation.tr("Middle-click emulation")
                checked: root.mouseData?.middle_emulation ?? false
                onCheckedChanged: {
                    if (!root.inputReady) return
                    root.setBooleanConfig("input", "mouse.middle-emulation", checked)
                }
            }

            SettingsSwitch {
                id: mouseScrollButtonLockSwitch
                Layout.fillWidth: true
                buttonIcon: "lock"
                text: Translation.tr("Scroll button lock")
                checked: root.mouseData?.scroll_button_lock ?? false
                onCheckedChanged: {
                    if (!root.inputReady) return
                    root.setBooleanConfig("input", "mouse.scroll-button-lock", checked)
                }
            }
        }

        SettingsDivider { Layout.columnSpan: mouseFields.activeColumns }

        ConfigRow {
            Layout.columnSpan: mouseFields.activeColumns
            uniform: true

            ConfigSpinBox {
                id: focusFollowsMouseMaxScrollSpin
                enabled: focusFollowsMouseSwitch.checked
                text: Translation.tr("Focus max scroll (%)")
                value: root.generalInputData?.focus_follows_mouse_max_scroll ?? 0
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    if (!root.inputReady) return
                    root.setFocusFollowsMouse(focusFollowsMouseSwitch.checked, value)
                }
            }

            ConfigSpinBox {
                text: Translation.tr("Shell scroll speed")
                value: Config.options?.interactions?.scrolling?.mouseScrollFactor ?? 120
                from: 40
                to: 400
                stepSize: 20
                onValueChanged: Config.setNestedValue("interactions.scrolling.mouseScrollFactor", value)
            }
        }

        ContentSubsection {
            Layout.columnSpan: mouseFields.activeColumns
            title: Translation.tr("Mouse acceleration & speed")

            ConfigSelectionArray {
                currentValue: root.mouseData?.accel_profile ?? "flat"
                options: [
                    { displayName: Translation.tr("Adaptive"), icon: "tune", value: "adaptive" },
                    { displayName: Translation.tr("Flat"), icon: "horizontal_rule", value: "flat" }
                ]
                onSelected: newValue => {
                    root.setConfig("input", "mouse.accel-profile", newValue)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                NiriFieldSlider {
                    id: mouseSpeedSlider
                    from: -100
                    to: 100
                    value: Math.round((root.mouseData?.accel_speed ?? 0) * 100)
                    liveValue: Math.round((root.mouseData?.accel_speed ?? 0) * 100)
                    stepSize: 5
                    configuration: StyledSlider.Configuration.S

                    onMoved: {
                        if (pressed) return
                        root.setConfig("input", "mouse.accel-speed", (value / 100.0).toFixed(2))
                    }
                }

                StyledText {
                    text: (mouseSpeedSlider.value / 100.0).toFixed(2)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colSubtext
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignRight
                }
            }
        }

        SettingsDivider { Layout.columnSpan: mouseFields.activeColumns }

        ContentSubsection {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            title: Translation.tr("Cursor theme & size")
            visible: true

            StyledComboBox {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                enabled: root.cursorThemes.length > 0
                model: root.cursorThemes.length > 0
                    ? root.cursorThemes
                    : [root.cursorData?.theme || Translation.tr("System default")]
                currentIndex: root.cursorThemes.length > 0
                    ? Math.max(0, root.cursorThemes.indexOf(root.cursorData?.theme ?? ""))
                    : 0
                onActivated: {
                    if (root.cursorThemes.length > 0 && currentIndex >= 0 && currentIndex < model.length)
                        root.setConfig("input", "cursor.xcursor-theme", model[currentIndex])
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            NiriFieldSlider {
                id: cursorSizeSlider
                from: 16
                to: 48
                value: root.cursorData?.size ?? 24
                liveValue: root.cursorData?.size ?? 24
                stepSize: 2
                configuration: StyledSlider.Configuration.S

                onMoved: {
                    if (pressed) return
                    root.setConfig("input", "cursor.xcursor-size", String(Math.round(value)))
                }
            }

            StyledText {
                text: Math.round(cursorSizeSlider.value) + "px"
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colSubtext
                Layout.preferredWidth: 35
                horizontalAlignment: Text.AlignRight
            }
        }

        SettingsSwitch {
            id: cursorHideWhenTypingSwitch
            Layout.fillWidth: true
            buttonIcon: "keyboard_hide"
            text: Translation.tr("Hide cursor while typing")
            checked: root.cursorData?.hide_when_typing ?? true
            onCheckedChanged: {
                if (!root.inputReady) return
                root.setBooleanConfig("input", "cursor.hide-when-typing", checked)
            }
        }
    }
}

    // =====================
    // KEYBOARD SECTION
    // =====================
    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "input"
        visible: true
        expanded: true
        icon: "keyboard"
        title: Translation.tr("Keyboard")

        SettingsGroup {
            ConfigRow {
                uniform: true

                ContentSubsection {
                    title: Translation.tr("Keyboard layout")

                    StyledComboBox {
                        id: keyboardLayoutCombo
                        Layout.fillWidth: true
                        model: root.keyboardLayoutOptions
                        textRole: "displayName"
                        currentIndex: {
                            const idx = root.choiceIndex(model, root.keyboardData?.layout ?? "us")
                            return idx >= 0 ? idx : (model.length - 1)
                        }
                        onActivated: {
                            const val = model[currentIndex]?.value ?? ""
                            if (val.length > 0 && val !== "__custom__")
                                root.setConfig("input", "keyboard.layout", val)
                        }
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Layout scope")

                    StyledComboBox {
                        id: keyboardTrackLayoutCombo
                        Layout.fillWidth: true
                        model: root.trackLayoutOptions
                        textRole: "displayName"
                        currentIndex: Math.max(0, root.choiceIndex(model, root.keyboardData?.track_layout ?? "global"))
                        onActivated: root.setConfig("input", "keyboard.track-layout", model[currentIndex].value)
                    }
                }
            }

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    id: keyboardRepeatDelaySpin
                    text: Translation.tr("Repeat delay (ms)")
                    value: root.keyboardData?.repeat_delay ?? 250
                    from: 100
                    to: 1000
                    stepSize: 25
                    onValueChanged: {
                        if (!root.inputReady) return
                        root.setConfig("input", "keyboard.repeat-delay", value)
                    }
                }

                ConfigSpinBox {
                    id: keyboardRepeatRateSpin
                    text: Translation.tr("Repeat rate (/s)")
                    value: root.keyboardData?.repeat_rate ?? 50
                    from: 10
                    to: 100
                    stepSize: 5
                    onValueChanged: {
                        if (!root.inputReady) return
                        root.setConfig("input", "keyboard.repeat-rate", value)
                    }
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    id: keyboardNumlockSwitch
                    Layout.fillWidth: true
                    buttonIcon: "dialpad"
                    text: Translation.tr("Num Lock on startup")
                    checked: root.keyboardData?.numlock ?? false
                    onCheckedChanged: {
                        if (!root.inputReady) return
                        root.setBooleanConfig("input", "keyboard.numlock", checked)
                    }
                }

                SettingsSwitch {
                    id: workspaceAutoBackAndForthSwitch
                    Layout.fillWidth: true
                    buttonIcon: "swap_horiz"
                    text: Translation.tr("Workspace back & forth")
                    checked: root.generalInputData?.workspace_auto_back_and_forth ?? false
                    onCheckedChanged: {
                        if (!root.inputReady) return
                        root.setBooleanConfig("input", "workspace-auto-back-and-forth", checked)
                    }
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    id: disablePowerKeySwitch
                    Layout.fillWidth: true
                    buttonIcon: "power_settings_new"
                    text: Translation.tr("Ignore hardware power key")
                    checked: root.generalInputData?.disable_power_key_handling ?? false
                    onCheckedChanged: {
                        if (!root.inputReady) return
                        root.setBooleanConfig("input", "disable-power-key-handling", checked)
                    }
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "notifications"
                    text: Translation.tr("Lock key OSD popup")
                    checked: Config.options?.keyboardIndicators?.showPopup ?? true
                    onCheckedChanged: Config.setNestedValue("keyboardIndicators.showPopup", checked)
                }
            }

            SettingsDivider {}

            ConfigRow {
                uniform: true

                ContentSubsection {
                    title: Translation.tr("Compositor mod key")

                    StyledComboBox {
                        id: modKeyCombo
                        Layout.fillWidth: true
                        model: root.modKeyOptions
                        currentIndex: {
                            const idx = model.indexOf(root.generalInputData?.mod_key || "Super")
                            return idx >= 0 ? idx : 0
                        }
                        onActivated: {
                            if (currentIndex >= 0 && currentIndex < model.length)
                                root.setConfig("input", "mod-key", model[currentIndex])
                        }
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Nested mod key")

                    StyledComboBox {
                        id: modKeyNestedCombo
                        Layout.fillWidth: true
                        model: root.modKeyOptions
                        currentIndex: {
                            const idx = model.indexOf(root.generalInputData?.mod_key_nested || "Alt")
                            return idx >= 0 ? idx : 1
                        }
                        onActivated: {
                            if (currentIndex >= 0 && currentIndex < model.length)
                                root.setConfig("input", "mod-key-nested", model[currentIndex])
                        }
                    }
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "badge"
                    text: Translation.tr("Bar lock indicator")
                    checked: Config.options?.keyboardIndicators?.showPanel ?? true
                    onCheckedChanged: Config.setNestedValue("keyboardIndicators.showPanel", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    enabled: Config.options?.keyboardIndicators?.showPopup ?? true
                    buttonIcon: "keyboard_capslock"
                    text: Translation.tr("Caps Lock in popup")
                    checked: Config.options?.keyboardIndicators?.popup?.caps ?? true
                    onCheckedChanged: Config.setNestedValue("keyboardIndicators.popup.caps", checked)
                }
            }
        }
    }

    // =====================
    // TOUCHPAD SECTION
    // =====================
    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "input"
        visible: true
        expanded: true
        icon: "touch_app"
        title: Translation.tr("Touchpad")

        SettingsGroup {
            ConfigRow {
                uniform: true

                SettingsSwitch {
                    id: touchpadEnabledSwitch
                    Layout.fillWidth: true
                    buttonIcon: "touchpad_mouse"
                    text: Translation.tr("Enable touchpad")
                    checked: !(root.touchpadData?.off ?? false)
                    onCheckedChanged: {
                        if (!root.inputReady) return
                        root.setBooleanConfig("input", "touchpad.off", !checked)
                    }
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "speed"
                    text: Translation.tr("Fast shell scroll")
                    checked: Config.options?.interactions?.scrolling?.fasterTouchpadScroll ?? false
                    onCheckedChanged: Config.setNestedValue("interactions.scrolling.fasterTouchpadScroll", checked)
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    id: touchpadTapSwitch
                    Layout.fillWidth: true
                    buttonIcon: "touch_app"
                    text: Translation.tr("Tap to click")
                    checked: root.touchpadData?.tap ?? true
                    onCheckedChanged: {
                        if (!root.inputReady) return
                        root.setBooleanConfig("input", "touchpad.tap", checked)
                    }
                }

                SettingsSwitch {
                    id: touchpadNaturalScrollSwitch
                    Layout.fillWidth: true
                    buttonIcon: "swipe"
                    text: Translation.tr("Natural scroll")
                    checked: root.touchpadData?.natural_scroll ?? false
                    onCheckedChanged: {
                        if (!root.inputReady) return
                        root.setBooleanConfig("input", "touchpad.natural-scroll", checked)
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                columns: width >= 540 ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: Appearance.sizes.spacingSmall
                rowSpacing: Appearance.sizes.spacingSmall

                SettingsSwitch {
                    id: touchpadDwtSwitch
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "block"
                    text: Translation.tr("Disable while typing")
                    checked: root.touchpadData?.dwt ?? false
                    onCheckedChanged: {
                        if (!root.inputReady) return
                        root.setBooleanConfig("input", "touchpad.dwt", checked)
                    }
                }

                SettingsSwitch {
                    id: touchpadDisableExternalMouseSwitch
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "mouse"
                    text: Translation.tr("Disable with external mouse")
                    checked: root.touchpadData?.disabled_on_external_mouse ?? false
                    onCheckedChanged: {
                        if (!root.inputReady) return
                        root.setBooleanConfig("input", "touchpad.disabled-on-external-mouse", checked)
                    }
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    id: touchpadLeftHandedSwitch
                    Layout.fillWidth: true
                    buttonIcon: "left_click"
                    text: Translation.tr("Left-handed")
                    checked: root.touchpadData?.left_handed ?? false
                    onCheckedChanged: {
                        if (!root.inputReady) return
                        root.setBooleanConfig("input", "touchpad.left-handed", checked)
                    }
                }

                SettingsSwitch {
                    id: touchpadMiddleEmulationSwitch
                    Layout.fillWidth: true
                    buttonIcon: "ads_click"
                    text: Translation.tr("Middle-click emulation")
                    checked: root.touchpadData?.middle_emulation ?? false
                    onCheckedChanged: {
                        if (!root.inputReady) return
                        root.setBooleanConfig("input", "touchpad.middle-emulation", checked)
                    }
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    id: touchpadDragLockSwitch
                    Layout.fillWidth: true
                    buttonIcon: "pan_tool"
                    text: Translation.tr("Tap drag lock")
                    checked: root.touchpadData?.drag_lock ?? false
                    onCheckedChanged: {
                        if (!root.inputReady) return
                        root.setBooleanConfig("input", "touchpad.drag-lock", checked)
                    }
                }

                SettingsSwitch {
                    id: touchpadScrollButtonLockSwitch
                    Layout.fillWidth: true
                    buttonIcon: "lock"
                    text: Translation.tr("Scroll button lock")
                    checked: root.touchpadData?.scroll_button_lock ?? false
                    onCheckedChanged: {
                        if (!root.inputReady) return
                        root.setBooleanConfig("input", "touchpad.scroll-button-lock", checked)
                    }
                }
            }

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    id: touchpadDwtpSwitch
                    Layout.fillWidth: true
                    buttonIcon: "joystick"
                    text: Translation.tr("Disable on trackpoint")
                    checked: root.touchpadData?.dwtp ?? false
                    onCheckedChanged: {
                        if (!root.inputReady) return
                        root.setBooleanConfig("input", "touchpad.dwtp", checked)
                    }
                }

                ConfigSpinBox {
                    text: Translation.tr("Touchpad scroll speed")
                    value: Config.options?.interactions?.scrolling?.touchpadScrollFactor ?? 450
                    from: 100
                    to: 1000
                    stepSize: 50
                    onValueChanged: Config.setNestedValue("interactions.scrolling.touchpadScrollFactor", value)
                }
            }

            ConfigRow {
                uniform: true

                ContentSubsection {
                    Layout.fillWidth: true
                    title: Translation.tr("Scroll method")

                    StyledComboBox {
                        id: touchpadScrollMethodCombo
                        Layout.fillWidth: true
                        model: root.touchpadScrollMethodOptions
                        textRole: "displayName"
                        currentIndex: Math.max(0, root.choiceIndex(model, root.touchpadData?.scroll_method ?? "two-finger"))
                        onActivated: root.setConfig("input", "touchpad.scroll-method", model[currentIndex].value)
                    }
                }

                ContentSubsection {
                    Layout.fillWidth: true
                    title: Translation.tr("Click method")

                    StyledComboBox {
                        id: touchpadClickMethodCombo
                        Layout.fillWidth: true
                        model: root.clickMethodOptions
                        textRole: "displayName"
                        currentIndex: Math.max(0, root.choiceIndex(model, root.touchpadData?.click_method ?? "button-areas"))
                        onActivated: root.setConfig("input", "touchpad.click-method", model[currentIndex].value)
                    }
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                title: Translation.tr("Multi-finger tap mapping")

                StyledComboBox {
                    id: touchpadTapButtonMapCombo
                    Layout.fillWidth: true
                    model: root.tapButtonMapOptions
                    textRole: "displayName"
                    currentIndex: Math.max(0, root.choiceIndex(model, root.touchpadData?.tap_button_map ?? "left-right-middle"))
                    onActivated: root.setConfig("input", "touchpad.tap-button-map", model[currentIndex].value)
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                title: Translation.tr("Touchpad acceleration & speed")

                ConfigSelectionArray {
                    currentValue: root.touchpadData?.accel_profile ?? "adaptive"
                    options: [
                        { displayName: Translation.tr("Adaptive"), icon: "tune", value: "adaptive" },
                        { displayName: Translation.tr("Flat"), icon: "horizontal_rule", value: "flat" }
                    ]
                    onSelected: newValue => {
                        root.setConfig("input", "touchpad.accel-profile", newValue)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    NiriFieldSlider {
                        id: touchpadSpeedSlider
                        from: -100
                        to: 100
                        value: Math.round((root.touchpadData?.accel_speed ?? 0) * 100)
                        liveValue: Math.round((root.touchpadData?.accel_speed ?? 0) * 100)
                        stepSize: 5
                        configuration: StyledSlider.Configuration.S

                        onMoved: {
                            if (pressed) return
                            root.setConfig("input", "touchpad.accel-speed", (value / 100.0).toFixed(2))
                        }
                    }

                    StyledText {
                        text: (touchpadSpeedSlider.value / 100.0).toFixed(2)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colSubtext
                        Layout.preferredWidth: 40
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
        }
    }

    // =====================
    // TRACKPOINT SECTION
    // =====================
    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "input"
        visible: true
        expanded: true
        icon: "joystick"
        title: Translation.tr("Trackpoint")

        SettingsGroup {
            ConfigRow {
                uniform: true

                SettingsSwitch {
                    id: trackpointNaturalScrollSwitch
                    Layout.fillWidth: true
                    buttonIcon: "swap_vert"
                    text: Translation.tr("Natural scroll")
                    checked: root.trackpointData?.natural_scroll ?? false
                    onCheckedChanged: {
                        if (!root.inputReady) return
                        root.setBooleanConfig("input", "trackpoint.natural-scroll", checked)
                    }
                }

                SettingsSwitch {
                    id: trackpointLeftHandedSwitch
                    Layout.fillWidth: true
                    buttonIcon: "left_click"
                    text: Translation.tr("Left-handed")
                    checked: root.trackpointData?.left_handed ?? false
                    onCheckedChanged: {
                        if (!root.inputReady) return
                        root.setBooleanConfig("input", "trackpoint.left-handed", checked)
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                columns: width >= 460 ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: Appearance.sizes.spacingSmall
                rowSpacing: Appearance.sizes.spacingSmall

                SettingsSwitch {
                    id: trackpointMiddleEmulationSwitch
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "ads_click"
                    text: Translation.tr("Middle-click emulation")
                    checked: root.trackpointData?.middle_emulation ?? false
                    onCheckedChanged: {
                        if (!root.inputReady) return
                        root.setBooleanConfig("input", "trackpoint.middle-emulation", checked)
                    }
                }

                SettingsSwitch {
                    id: trackpointScrollButtonLockSwitch
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "lock"
                    text: Translation.tr("Scroll button lock")
                    checked: root.trackpointData?.scroll_button_lock ?? false
                    onCheckedChanged: {
                        if (!root.inputReady) return
                        root.setBooleanConfig("input", "trackpoint.scroll-button-lock", checked)
                    }
                }
            }

            ConfigRow {
                uniform: true

                ContentSubsection {
                    Layout.fillWidth: true
                    title: Translation.tr("Trackpoint acceleration")

                    ConfigSelectionArray {
                        currentValue: root.trackpointData?.accel_profile ?? "flat"
                        options: [
                            { displayName: Translation.tr("Adaptive"), icon: "tune", value: "adaptive" },
                            { displayName: Translation.tr("Flat"), icon: "horizontal_rule", value: "flat" }
                        ]
                        onSelected: newValue => root.setConfig("input", "trackpoint.accel-profile", newValue)
                    }
                }

                ContentSubsection {
                    Layout.fillWidth: true
                    title: Translation.tr("Trackpoint scrolling")

                    StyledComboBox {
                        Layout.fillWidth: true
                        model: root.pointerScrollMethodOptions
                        textRole: "displayName"
                        currentIndex: root.choiceIndex(model, root.trackpointData?.scroll_method ?? "on-button-down")
                        onActivated: root.setConfig("input", "trackpoint.scroll-method", model[currentIndex].value)
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Trackpoint speed")
                tooltip: Translation.tr("Acceleration speed. Negative = slower, positive = faster.")

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    NiriFieldSlider {
                        id: trackpointSpeedSlider
                        from: -100
                        to: 100
                        value: Math.round((root.trackpointData?.accel_speed ?? 0) * 100)
                        liveValue: Math.round((root.trackpointData?.accel_speed ?? 0) * 100)
                        stepSize: 5
                        configuration: StyledSlider.Configuration.S

                        onMoved: {
                            if (pressed) return
                            root.setConfig("input", "trackpoint.accel-speed", (value / 100.0).toFixed(2))
                        }
                    }

                    StyledText {
                        text: (trackpointSpeedSlider.value / 100.0).toFixed(2)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colSubtext
                        Layout.preferredWidth: 40
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }

            SettingsDivider {}

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "crop_free"
                    text: Translation.tr("Edge pixel workaround")
                    checked: Config.options?.interactions?.deadPixelWorkaround?.enable ?? false
                    onCheckedChanged: Config.setNestedValue("interactions.deadPixelWorkaround.enable", checked)
                }

                ConfigSpinBox {
                    text: Translation.tr("Scroll step threshold")
                    value: Config.options?.interactions?.scrolling?.mouseScrollDeltaThreshold ?? 120
                    from: 30
                    to: 240
                    stepSize: 15
                    onValueChanged: Config.setNestedValue("interactions.scrolling.mouseScrollDeltaThreshold", value)
                }
            }
        }
    }
}
