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
    settingsPageName: Translation.tr("Compositor")
    property string activeSection: "displays"
    property bool pageReady: false

    function activateSettingsSearchSection(section: string): bool {
        const label = String(section ?? "").toLowerCase()
        if (label.includes("touchpad") || label.includes("mouse") || label.includes("trackpoint")
                || label.includes("input") || label.includes("cursor")) {
            root.activeSection = "input"
        } else {
            root.activeSection = "displays"
        }
        return true
    }

    property var outputList: []
    property int selectedOutputIndex: 0

    readonly property var currentOutput: outputList.length > selectedOutputIndex ? outputList[selectedOutputIndex] : null
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
    property int confirmCountdown: 10
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
    readonly property bool displayControlsLocked: confirmationPending || applyOutputProcess.running || persistOutputProcess.running

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
        case "layout":
        case "animations":
        case "rules":
            loadOutputs()
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
        confirmCountdown = 10
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
        confirmCountdown = 10

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
            root.activeSection = "displays"
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
    onSelectedOutputIndexChanged: Qt.callLater(resyncDisplayCombos)

    function resyncDisplayCombos() {
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
        if (typeof keyboardRepeatDelaySpin !== "undefined")
            keyboardRepeatDelaySpin.value = kb.repeat_delay ?? 250
        if (typeof keyboardRepeatRateSpin !== "undefined")
            keyboardRepeatRateSpin.value = kb.repeat_rate ?? 50
        if (typeof disablePowerKeySwitch !== "undefined")
            disablePowerKeySwitch.checked = gn.disable_power_key_handling ?? false
        if (typeof workspaceAutoBackAndForthSwitch !== "undefined")
            workspaceAutoBackAndForthSwitch.checked = gn.workspace_auto_back_and_forth ?? false
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
                    if (Array.isArray(data))
                        root.outputList = data
                    root.outputReady = true
                })
            }
        }
        stderr: StdioCollector { id: outputsErrorCollector }
        onExited: (exitCode) => {
            if (exitCode !== 0)
                root.setProcessError("outputs", (outputsErrorCollector.text || outputsCollector.text || Translation.tr("Unable to query connected outputs.")).trim())
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
                    if (typeof animationsEnabledSwitch !== "undefined")
                        animationsEnabledSwitch.checked = data?.enabled ?? true
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
                        width: parent.width * (root.confirmCountdown / 10.0)
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

    SettingsTaskNavigator {
        showTabBar: true
        showIntro: false
        icon: "monitor"
        title: Translation.tr("Compositor")
        description: Translation.tr("Tune displays, input, layout and rules; unconfirmed display previews revert.")
        summary: Translation.tr("Displays & Rules · Tiling Layout · Mouse & Touchpad")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Displays & Windows"), icon: "desktop_windows", value: "displays" },
            { displayName: Translation.tr("Mouse, Touchpad & Cursor"), icon: "keyboard", value: "input" }
        ]
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        uniformCellWidths: true
        columnSpacing: 14
        rowSpacing: 14

SettingsCardSection {
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop
    Layout.fillWidth: true
    settingsTaskSection: "displays"
    bentoColumn: "left"
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

        ContentSubsection {
            title: Translation.tr("Monitor")
            visible: root.outputList.length > 1

            StyledComboBox {
                Layout.fillWidth: true
                enabled: !root.displayControlsLocked
                model: root.outputList.map(o => ({
                    displayName: `${o.name} — ${o.make} ${o.model}`,
                    value: o.name
                }))
                textRole: "displayName"
                currentIndex: root.choiceIndex(model, root.currentOutputName)
                onActivated: {
                    const idx = root.outputList.findIndex(o => o.name === model[currentIndex].value)
                    if (idx >= 0)
                        root.selectedOutputIndex = idx
                }
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: monitorInfoRow.implicitHeight + 8
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
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: root.currentOutputName
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
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
                visible: root.refreshOptions.length > 1

                StyledComboBox {
                    id: refreshRateCombo
                    Layout.fillWidth: true
                    enabled: !root.displayControlsLocked
                    model: root.refreshOptions
                    textRole: "displayName"
                    onActivated: root.safeApplyOutput("mode", "mode", `${root.currentResolution}@${model[currentIndex].rateString}`)
                }
            }
        }

        ConfigRow {
            uniform: true
            ContentSubsection {
                title: Translation.tr("Scale")

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

        ContentSubsection {
            title: Translation.tr("Variable refresh rate (VRR)")
            tooltip: Translation.tr("Adaptive sync / FreeSync / G-Sync.")
            visible: root.vrrSupported

            StyledComboBox {
                id: vrrCombo
                Layout.fillWidth: true
                enabled: !root.displayControlsLocked
                model: root.vrrOptions
                textRole: "displayName"
                onActivated: {
                    if (!root.outputReady) return
                    root.applyAndPersistOutput("vrr", model[currentIndex].value)
                }
            }
        }
    }
}

SettingsCardSection {
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop
    Layout.fillWidth: true
    settingsTaskSection: "displays"
    bentoColumn: "left"
    visible: true
    expanded: true
    icon: "rounded_corner"
    title: Translation.tr("Window Rules & Motion")

    SettingsGroup {
        ContentSubsection {
            title: Translation.tr("Corner radius")
            tooltip: Translation.tr("Rounding applied to window corners (0 = square)")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledSlider {
                    id: cornerRadiusSlider
                    Layout.fillWidth: true
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

                StyledSlider {
                    id: inactiveOpacitySlider
                    Layout.fillWidth: true
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

        SettingsSwitch {
            id: clipToGeometrySwitch
            Layout.fillWidth: true
            buttonIcon: "crop"
            text: Translation.tr("Clip windows to rounded geometry")
            checked: root.windowRulesData?.clip_to_geometry ?? true
            onCheckedChanged: {
                if (!root.windowRulesReady) return
                root.setConfig("window-rules", "clip-to-geometry", checked ? "true" : "false")
            }
        }

        SettingsDivider {}

        SettingsSwitch {
            id: animationsEnabledSwitch
            Layout.fillWidth: true
            buttonIcon: "animation"
            text: Translation.tr("Enable compositor animations")
            checked: root.animationsData?.enabled ?? true
            onCheckedChanged: {
                if (!root.animationsReady) return
                root.setBooleanConfig("animations", "enabled", checked)
            }
        }

        ContentSubsection {
            title: Translation.tr("Global animation slowdown")
            tooltip: Translation.tr("1.0 is normal speed. Higher values make every animation slower.")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledSlider {
                    id: slowdownSlider
                    Layout.fillWidth: true
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
    }
}

    // =====================
    // LAYOUT SECTION
    // =====================
    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        settingsTaskSection: "displays"
        bentoColumn: "right"
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
                    text: Translation.tr("Overview zoom (%)")
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

            SettingsSwitch {
                id: alwaysCenterSingleColumnSwitch
                Layout.fillWidth: true
                buttonIcon: "center_focus_strong"
                text: Translation.tr("Always center a single column")
                checked: root.layoutData?.always_center_single_column ?? false
                onCheckedChanged: {
                    if (!root.layoutReady) return
                    root.setBooleanConfig("layout", "always-center-single-column", checked)
                }
            }

            SettingsSwitch {
                Layout.fillWidth: true
                buttonIcon: "fullscreen"
                text: Translation.tr("Auto-expand a single tiling window")
                checked: Config.options?.compositor?.autoExpandSingleTilingWindow ?? false
                onCheckedChanged: Config.setNestedValue("compositor.autoExpandSingleTilingWindow", checked)
            }

            SettingsSwitch {
                id: emptyWorkspaceAboveFirstSwitch
                Layout.fillWidth: true
                buttonIcon: "vertical_align_top"
                text: Translation.tr("Empty workspace above first")
                checked: root.layoutData?.empty_workspace_above_first ?? false
                onCheckedChanged: {
                    if (!root.layoutReady) return
                    root.setBooleanConfig("layout", "empty-workspace-above-first", checked)
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
        }
    }

    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        settingsTaskSection: "displays"
        bentoColumn: "right"
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
                visible: root.layoutData?.border?.enabled ?? false
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
                visible: root.layoutData?.focus_ring?.enabled ?? false
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
        }
    }

SettingsCardSection {
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop
    Layout.fillWidth: true
    settingsTaskSection: "input"
    visible: true
    expanded: true
    icon: "mouse"
    title: Translation.tr("Mouse, Focus & Cursor")

    SettingsGroup {
        ConfigRow {
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

        ContentSubsection {
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

                StyledSlider {
                    id: mouseSpeedSlider
                    Layout.fillWidth: true
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

        SettingsDivider {}

        ContentSubsection {
            title: Translation.tr("Cursor theme & size")
            visible: root.cursorThemes.length > 0

            StyledComboBox {
                Layout.fillWidth: true
                model: root.cursorThemes
                currentIndex: root.cursorThemes.indexOf(root.cursorData?.theme ?? "")
                onActivated: root.setConfig("input", "cursor.xcursor-theme", model[currentIndex])
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledSlider {
                id: cursorSizeSlider
                Layout.fillWidth: true
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
    // TOUCHPAD SECTION
    // =====================
    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        settingsTaskSection: "input"
        visible: true
        expanded: true
        icon: "touch_app"
        title: Translation.tr("Touchpad")

        SettingsGroup {
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

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    id: touchpadDwtSwitch
                    Layout.fillWidth: true
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
                    buttonIcon: "mouse"
                    text: Translation.tr("Disable with external mouse")
                    checked: root.touchpadData?.disabled_on_external_mouse ?? false
                    onCheckedChanged: {
                        if (!root.inputReady) return
                        root.setBooleanConfig("input", "touchpad.disabled-on-external-mouse", checked)
                    }
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

                    StyledSlider {
                        id: touchpadSpeedSlider
                        Layout.fillWidth: true
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
        Layout.preferredWidth: 1
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

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    id: trackpointMiddleEmulationSwitch
                    Layout.fillWidth: true
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

                    StyledSlider {
                        id: trackpointSpeedSlider
                        Layout.fillWidth: true
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
        }
    }

    // Default applications are owned by Settings -> Default Applications (SET-F01).
    readonly property string _legacyAppPresetHint: Translation.tr("Choose an app preset or custom command.")
    }

}
