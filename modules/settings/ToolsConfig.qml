import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    settingsPageIndex: 6
    settingsPageName: Translation.tr("Tools")
    property string activeSection: "recording"

    SettingsTaskNavigator {
        showTabBar: false
        showIntro: false
        icon: "build"
        title: Translation.tr("Tools")
        description: Translation.tr("Capture, selection and overlay settings by tool.")
        summary: Translation.tr("Recording · snipping")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Recording"), icon: "screen_record", value: "recording" },
            { displayName: Translation.tr("Snipping"), icon: "screenshot_frame_2", value: "snipping" }
        ]
    }

    property bool recordingCapabilitiesLoaded: false
    property var detectedVideoCodecs: []
    property var detectedAudioCodecs: []
    property var detectedAudioSources: []
    property var detectedHardwareDevices: []
    property string detectedDefaultSink: ""
    property string detectedDefaultSource: ""
    property bool audioMixAvailable: false
    property string captureFolderTarget: "recordings"

    readonly property string recordingAudioMode: RecorderStatus.configuredAudioMode
    readonly property string effectiveRecordingPath: {
        const configured = String(Config.getNestedValue("screenRecord.savePath", ""))
        return configured.length > 0 ? configured : Directories.videosPath
    }
    readonly property string effectiveScreenshotPath: Directories.screenshotsPath
    readonly property string detectedDefaultAudioSource: detectedDefaultSink.length > 0 ? `${detectedDefaultSink}.monitor` : ""
    readonly property var recordingAudioModeOptions: [
        { value: "none", displayName: Translation.tr("No audio") },
        { value: "system", displayName: Translation.tr("System audio") },
        { value: "microphone", displayName: Translation.tr("Microphone") },
        { value: "both", displayName: Translation.tr("System + microphone") }
    ]

    function openCaptureFolderDialog(target: string): void {
        root.captureFolderTarget = target
        captureFolderDialog.open()
    }

    FolderDialog {
        id: captureFolderDialog
        title: root.captureFolderTarget === "screenshots"
            ? Translation.tr("Select screenshots folder")
            : Translation.tr("Select recordings folder")
        currentFolder: `file://${root.captureFolderTarget === "screenshots"
            ? root.effectiveScreenshotPath : root.effectiveRecordingPath}`
        onAccepted: {
            const path = FileUtils.trimFileProtocol(String(selectedFolder))
            Config.setNestedValue(root.captureFolderTarget === "screenshots"
                ? "regionSelector.savePath" : "screenRecord.savePath", path)
        }
    }

    SettingsNativeDialogGuard {
        dialog: captureFolderDialog
        dialogKey: "tools-capture-folder"
    }
    readonly property bool vaapiRecordingAvailable: detectedVideoCodecs.some(codec => String(codec).indexOf("_vaapi") !== -1)
    readonly property bool nvencRecordingAvailable: detectedVideoCodecs.some(codec => String(codec).indexOf("_nvenc") !== -1)
    readonly property bool gpuRecordingAvailable: vaapiRecordingAvailable || nvencRecordingAvailable
    readonly property var recordingQualityPresetOptions: [
        { value: "compact", displayName: Translation.tr("Compact") },
        { value: "balanced", displayName: Translation.tr("Balanced") },
        { value: "quality", displayName: Translation.tr("Quality") },
        { value: "master", displayName: Translation.tr("Master") },
        { value: "custom", displayName: Translation.tr("Custom") }
    ]
    readonly property var recordingAccelerationOptions: gpuRecordingAvailable
        ? [
            { value: "auto", displayName: Translation.tr("Auto") },
            { value: "gpu", displayName: Translation.tr("Prefer GPU") },
            { value: "software", displayName: Translation.tr("Software only") }
        ]
        : [
            { value: "auto", displayName: Translation.tr("Auto") },
            { value: "software", displayName: Translation.tr("Software only") }
        ]
    readonly property var recordingFpsOptions: [24, 30, 45, 60, 90, 120, 144].map(value => ({ value: value, displayName: `${value} FPS` }))
    readonly property var recordingVideoBitrateOptions: [4000, 6000, 8000, 10000, 12000, 16000, 20000, 28000].map(value => ({ value: value, displayName: `${value} kbps` }))
    readonly property var recordingAudioBitrateOptions: [96, 128, 160, 192, 256, 320].map(value => ({ value: value, displayName: `${value} kbps` }))
    readonly property var recordingSampleRateOptions: [32000, 44100, 48000, 96000].map(value => ({ value: value, displayName: `${value} Hz` }))
    readonly property var recordingSoftwarePresetOptions: ["ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow"].map(value => ({ value: value, displayName: value }))
    readonly property var recordingPixelFormatOptions: [
        { value: "yuv420p", displayName: Translation.tr("yuv420p — smaller files") },
        { value: "yuv444p", displayName: Translation.tr("yuv444p — sharper text, bigger files") }
    ]
    readonly property var recordingCrfOptions: [14, 18, 21, 23, 26, 28, 30, 35].map(value => ({ value: value, displayName: `CRF ${value}` }))
    readonly property var recordingDiscordTargetSizeOptions: [
        { value: 8, displayName: Translation.tr("8 MB") },
        { value: 10, displayName: Translation.tr("10 MB") },
        { value: 25, displayName: Translation.tr("25 MB") },
        { value: 50, displayName: Translation.tr("50 MB") }
    ]
    readonly property var recordingDiscordDimensionOptions: [540, 720, 960, 1280, 1440, 1920].map(value => ({ value: value, displayName: `${value}px` }))
    readonly property var recordingAudioBackendOptions: [
        { value: "", displayName: Translation.tr("Auto") },
        { value: "pipewire", displayName: "PipeWire" },
        { value: "pulse", displayName: "PulseAudio" }
    ]
    readonly property var recordingVaapiFilterOptions: [
        { value: "scale_vaapi=format=nv12:out_range=full", displayName: Translation.tr("Full range — recommended") },
        { value: "scale_vaapi=format=nv12", displayName: Translation.tr("Limited range") },
        { value: "", displayName: Translation.tr("No VAAPI filter") }
    ]
    readonly property var oskLayoutOptions: [
        { value: "English (US)", displayName: Translation.tr("English (US)") },
        { value: "German", displayName: Translation.tr("German") },
        { value: "Russian", displayName: Translation.tr("Russian") }
    ]

    function availableOskLayoutOptions() {
        const current = Config.options?.osk?.layout ?? "English (US)"
        const label = current === "qwerty_full" ? Translation.tr("QWERTY (Default)") : current
        return root.ensureOption(root.oskLayoutOptions, current, label)
    }

    function setRecordingConfig(path, value) {
        Config.setNestedValue(path, value)
        if (path !== "screenRecord.qualityPreset" && (Config.options?.screenRecord?.qualityPreset ?? "balanced") !== "custom")
            Config.setNestedValue("screenRecord.qualityPreset", "custom")
    }

    function choiceIndex(options, value) {
        for (let i = 0; i < options.length; ++i) {
            if (options[i].value === value)
                return i
        }
        return options.length > 0 ? 0 : -1
    }

    function ensureOption(options, value, displayName) {
        const normalized = String(value ?? "")
        const result = Array.isArray(options) ? options.slice() : []
        if (normalized.length === 0)
            return result
        if (!result.some(option => String(option.value) === normalized))
            result.push({ value: value, displayName: displayName })
        return result
    }

    function videoCodecDisplayName(codec) {
        switch (codec) {
        case "h264_vaapi": return Translation.tr("H.264 (GPU / VAAPI)")
        case "hevc_vaapi": return Translation.tr("H.265 / HEVC (GPU / VAAPI)")
        case "vp9_vaapi": return Translation.tr("VP9 (GPU / VAAPI)")
        case "av1_vaapi": return Translation.tr("AV1 (GPU / VAAPI)")
        case "h264_nvenc": return Translation.tr("H.264 (GPU / NVENC)")
        case "hevc_nvenc": return Translation.tr("H.265 / HEVC (GPU / NVENC)")
        case "av1_nvenc": return Translation.tr("AV1 (GPU / NVENC)")
        case "libx264": return Translation.tr("H.264 (software)")
        case "libx265": return Translation.tr("H.265 / HEVC (software)")
        default: return codec
        }
    }

    function audioCodecDisplayName(codec) {
        switch (codec) {
        case "aac": return Translation.tr("AAC")
        case "libopus": return Translation.tr("Libopus")
        case "opus": return Translation.tr("Opus")
        default: return codec
        }
    }

    function systemAudioSourceDisplayName(source) {
        if (source === "")
            return detectedDefaultAudioSource.length > 0
                ? `${Translation.tr("Default output monitor")} (${detectedDefaultAudioSource})`
                : Translation.tr("Default output monitor")
        if (source === detectedDefaultAudioSource)
            return `${Translation.tr("Default output monitor")} (${source})`
        return `${Translation.tr("Output monitor")} (${source})`
    }

    function microphoneSourceDisplayName(source) {
        if (source === "")
            return detectedDefaultSource.length > 0
                ? `${Translation.tr("Default microphone")} (${detectedDefaultSource})`
                : Translation.tr("Default microphone")
        if (source === detectedDefaultSource)
            return `${Translation.tr("Default microphone")} (${source})`
        return source
    }

    function hardwareDeviceDisplayName(device) {
        return device === "/dev/dri/renderD128"
            ? `${Translation.tr("Primary render device")} (${device})`
            : device
    }

    function updateRecordingCapabilities(payloadText) {
        try {
            const payload = JSON.parse((payloadText ?? "").trim() || "{}")
            detectedVideoCodecs = payload.videoCodecs ?? []
            detectedAudioCodecs = payload.audioCodecs ?? []
            detectedAudioSources = payload.audioSources ?? []
            detectedHardwareDevices = payload.hardwareDevices ?? []
            detectedDefaultSink = payload.defaultSink ?? ""
            detectedDefaultSource = payload.defaultSource ?? ""
            audioMixAvailable = payload.audioMixAvailable ?? false
        } catch (e) {
            detectedVideoCodecs = []
            detectedAudioCodecs = []
            detectedAudioSources = []
            detectedHardwareDevices = []
            detectedDefaultSink = ""
            detectedDefaultSource = ""
            audioMixAvailable = false
        }
        recordingCapabilitiesLoaded = true
    }

    function availableVideoCodecOptions() {
        let options = detectedVideoCodecs.map(codec => ({ value: codec, displayName: videoCodecDisplayName(codec) }))
        options = ensureOption(options, Config.options?.screenRecord?.videoCodec ?? "libx264", `${Translation.tr("Configured")}: ${Config.options?.screenRecord?.videoCodec ?? "libx264"}`)
        return options
    }

    function availableAudioCodecOptions() {
        let options = detectedAudioCodecs.map(codec => ({ value: codec, displayName: audioCodecDisplayName(codec) }))
        options = ensureOption(options, Config.options?.screenRecord?.audioCodec ?? "aac", `${Translation.tr("Configured")}: ${Config.options?.screenRecord?.audioCodec ?? "aac"}`)
        return options
    }

    function availableSystemAudioSourceOptions() {
        let options = [{ value: "", displayName: systemAudioSourceDisplayName("") }]
        for (const source of detectedAudioSources) {
            if (String(source).endsWith(".monitor"))
                options.push({ value: source, displayName: systemAudioSourceDisplayName(source) })
        }
        const configured = RecorderStatus.configuredSystemAudioSource
        options = ensureOption(options, configured, `${Translation.tr("Configured source")}: ${configured}`)
        return options
    }

    function availableMicrophoneSourceOptions() {
        let options = [{ value: "", displayName: microphoneSourceDisplayName("") }]
        for (const source of detectedAudioSources) {
            if (!String(source).endsWith(".monitor"))
                options.push({ value: source, displayName: microphoneSourceDisplayName(source) })
        }
        const configured = RecorderStatus.configuredMicrophoneSource
        options = ensureOption(options, configured, `${Translation.tr("Configured source")}: ${configured}`)
        return options
    }

    function availableHardwareDeviceOptions() {
        let options = detectedHardwareDevices.map(device => ({ value: device, displayName: hardwareDeviceDisplayName(device) }))
        options = ensureOption(options, Config.options?.screenRecord?.hardwareDevice ?? "/dev/dri/renderD128", `${Translation.tr("Configured device")}: ${Config.options?.screenRecord?.hardwareDevice ?? "/dev/dri/renderD128"}`)
        return options
    }

    component RecordingDropdownField: ColumnLayout {
        id: field
        required property string title
        required property string description
        required property var options
        required property var currentValue
        property bool fieldEnabled: true
        signal selected(var newValue)

        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 4

        StyledText {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            wrapMode: Text.WordWrap
            text: field.title
        }

        StyledText {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            visible: field.description.length > 0
            text: field.description
            color: Appearance.angelEverywhere ? Appearance.angel.colTextMuted
                : Appearance.alisEverywhere ? Appearance.alis.colTextSecondary
                : Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smallie
            wrapMode: Text.WordWrap
        }

        StyledComboBox {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            enabled: field.fieldEnabled
            model: field.options
            textRole: "displayName"
            currentIndex: root.choiceIndex(field.options, field.currentValue)
            onActivated: index => {
                if (index >= 0 && index < field.options.length)
                    field.selected(field.options[index].value)
            }
        }
    }

    Process {
        id: recordingCapabilityProbe
        running: true
        command: ["/usr/bin/bash", Directories.recordScriptPath, "--probe-capabilities"]
        stdout: StdioCollector {
            id: recordingCapabilityCollector
            onStreamFinished: root.updateRecordingCapabilities(recordingCapabilityCollector.text)
        }
        onExited: (exitCode) => {
            if (exitCode !== 0 && !root.recordingCapabilitiesLoaded)
                root.recordingCapabilitiesLoaded = true
        }
    }

    function applyRecordingPreset(preset) {
        Config.setNestedValue("screenRecord.qualityPreset", preset)
        switch (preset) {
        case "compact":
            Config.setNestedValue("screenRecord.accelerationMode", "auto")
            Config.setNestedValue("screenRecord.videoCodec", "libx264")
            Config.setNestedValue("screenRecord.audioCodec", "aac")
            Config.setNestedValue("screenRecord.fps", 30)
            Config.setNestedValue("screenRecord.videoBitrateKbps", 6000)
            Config.setNestedValue("screenRecord.audioBitrateKbps", 128)
            Config.setNestedValue("screenRecord.audioSampleRate", 48000)
            Config.setNestedValue("screenRecord.pixelFormat", "yuv420p")
            Config.setNestedValue("screenRecord.preset", "veryfast")
            Config.setNestedValue("screenRecord.crf", 28)
            break
        case "balanced":
            Config.setNestedValue("screenRecord.accelerationMode", "auto")
            Config.setNestedValue("screenRecord.videoCodec", "libx264")
            Config.setNestedValue("screenRecord.audioCodec", "aac")
            Config.setNestedValue("screenRecord.fps", 60)
            Config.setNestedValue("screenRecord.videoBitrateKbps", 10000)
            Config.setNestedValue("screenRecord.audioBitrateKbps", 160)
            Config.setNestedValue("screenRecord.audioSampleRate", 48000)
            Config.setNestedValue("screenRecord.pixelFormat", "yuv420p")
            Config.setNestedValue("screenRecord.preset", "veryfast")
            Config.setNestedValue("screenRecord.crf", 23)
            break
        case "quality":
            Config.setNestedValue("screenRecord.accelerationMode", "auto")
            Config.setNestedValue("screenRecord.videoCodec", "libx264")
            Config.setNestedValue("screenRecord.audioCodec", "aac")
            Config.setNestedValue("screenRecord.fps", 60)
            Config.setNestedValue("screenRecord.videoBitrateKbps", 16000)
            Config.setNestedValue("screenRecord.audioBitrateKbps", 192)
            Config.setNestedValue("screenRecord.audioSampleRate", 48000)
            Config.setNestedValue("screenRecord.pixelFormat", "yuv420p")
            Config.setNestedValue("screenRecord.preset", "medium")
            Config.setNestedValue("screenRecord.crf", 18)
            break
        case "master":
            Config.setNestedValue("screenRecord.accelerationMode", "auto")
            Config.setNestedValue("screenRecord.videoCodec", "libx264")
            Config.setNestedValue("screenRecord.audioCodec", "aac")
            Config.setNestedValue("screenRecord.fps", 60)
            Config.setNestedValue("screenRecord.videoBitrateKbps", 28000)
            Config.setNestedValue("screenRecord.audioBitrateKbps", 256)
            Config.setNestedValue("screenRecord.audioSampleRate", 48000)
            Config.setNestedValue("screenRecord.pixelFormat", "yuv420p")
            Config.setNestedValue("screenRecord.preset", "slow")
            Config.setNestedValue("screenRecord.crf", 14)
            break
        }
    }

    SettingsCardSection {
        id: screenRecordSection
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        visible: true
        expanded: true
        icon: "screen_record"
        title: Translation.tr("Screen recording")

    readonly property bool isCustomPreset: (Config.options?.screenRecord?.qualityPreset ?? "balanced") === "custom"

    SettingsGroup {
        ConfigRow {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            uniform: width >= 500

            SettingsSwitch {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                buttonIcon: "pip"
                text: Translation.tr("Show recording overlay")
                checked: Config.options?.screenRecord?.showOsd ?? false
                onCheckedChanged: {
                    Config.setNestedValue("screenRecord.showOsd", checked)
                    let panels = [...(Config.options?.enabledPanels ?? [])]
                    const idx = panels.indexOf("iiRecordingOsd")
                    if (checked && idx === -1) {
                        panels.push("iiRecordingOsd")
                        Config.setNestedValue("enabledPanels", panels)
                    } else if (!checked && idx !== -1) {
                        panels.splice(idx, 1)
                        Config.setNestedValue("enabledPanels", panels)
                    }
                }
            }

            SettingsSwitch {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                buttonIcon: "mouse"
                text: Translation.tr("Auto-hide recording OSD")
                checked: Config.options?.screenRecord?.recordingOsd?.autoHide ?? false
                onCheckedChanged: Config.setNestedValue("screenRecord.recordingOsd.autoHide", checked)
            }
        }

        SettingsSwitch {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            buttonIcon: "notifications"
            text: Translation.tr("Recording notifications")
            checked: Config.options?.screenRecord?.showNotifications ?? true
            onCheckedChanged: Config.setNestedValue("screenRecord.showNotifications", checked)
        }

        LoadingText {
            Layout.fillWidth: true
            visible: false
        }

        ContentSubsection {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            title: Translation.tr("Recording folder")

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: Appearance.sizes.spacingSmall

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: Directories.shortHomePath(root.effectiveRecordingPath)
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideMiddle
                }

                RippleButtonWithIcon {
                    materialIcon: "folder_open"
                    mainText: Translation.tr("Open folder")
                    onClicked: ShellExec.openDirectory(root.effectiveRecordingPath, Translation.tr("Open recordings folder"))
                }

                RippleButtonWithIcon {
                    materialIcon: "drive_file_move"
                    mainText: Translation.tr("Change folder")
                    onClicked: root.openCaptureFolderDialog("recordings")
                }
            }
        }

        ConfigRow {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            uniform: true

            RecordingDropdownField {
                Layout.preferredWidth: 1
                title: Translation.tr("Quality preset")
                description: Translation.tr("Tradeoff between file size and quality.")
                options: root.recordingQualityPresetOptions
                currentValue: Config.options?.screenRecord?.qualityPreset ?? "balanced"
                onSelected: newValue => {
                    if (newValue === "custom")
                        Config.setNestedValue("screenRecord.qualityPreset", "custom")
                    else
                        root.applyRecordingPreset(newValue)
                }
            }

            RecordingDropdownField {
                Layout.preferredWidth: 1
                title: Translation.tr("Acceleration")
                description: Translation.tr("Auto picks the best path for your hardware.")
                options: root.recordingAccelerationOptions
                currentValue: Config.options?.screenRecord?.accelerationMode ?? "auto"
                onSelected: newValue => root.setRecordingConfig("screenRecord.accelerationMode", newValue)
            }
        }

        ConfigRow {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            uniform: true

            RecordingDropdownField {
                Layout.preferredWidth: 1
                title: Translation.tr("Codec")
                description: ""
                options: root.availableVideoCodecOptions()
                currentValue: Config.options?.screenRecord?.videoCodec ?? "libx264"
                onSelected: newValue => root.setRecordingConfig("screenRecord.videoCodec", newValue)
            }

            RecordingDropdownField {
                Layout.preferredWidth: 1
                title: Translation.tr("Frame rate")
                description: ""
                options: root.recordingFpsOptions
                currentValue: Config.options?.screenRecord?.fps ?? 60
                onSelected: newValue => root.setRecordingConfig("screenRecord.fps", newValue)
            }
        }

        SettingsSwitch {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            buttonIcon: "swap_horiz"
            text: Translation.tr("Fallback if preferred encoder fails")
            checked: Config.options?.screenRecord?.enableFallback ?? true
            onCheckedChanged: {
                if (checked !== (Config.options?.screenRecord?.enableFallback ?? true))
                    root.setRecordingConfig("screenRecord.enableFallback", checked);
            }
        }

        ContentSubsection {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            title: Translation.tr("Audio capture")

            RecordingDropdownField {
                title: Translation.tr("Recording audio")
                description: Translation.tr("Choose whether recordings include system audio, microphone, both, or no audio.")
                options: root.recordingAudioModeOptions
                currentValue: root.recordingAudioMode
                onSelected: newValue => RecorderStatus.setConfiguredAudioMode(newValue)
            }

            NoticeBox {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                visible: root.recordingAudioMode === "both"
                materialIcon: root.audioMixAvailable ? "instant_mix" : "warning"
                text: root.audioMixAvailable
                    ? Translation.tr("Alis combines system audio and microphone automatically. The temporary audio route is removed when recording ends.")
                    : Translation.tr("System and microphone audio cannot be combined on this setup. Recording will continue with whichever source is available.")
            }

            RecordingDropdownField {
                visible: root.recordingAudioMode === "system" || root.recordingAudioMode === "both"
                title: Translation.tr("System audio source")
                description: Translation.tr("Auto follows the current default output device.")
                options: root.availableSystemAudioSourceOptions()
                currentValue: RecorderStatus.configuredSystemAudioSource
                onSelected: newValue => RecorderStatus.setConfiguredSystemAudioSource(newValue)
            }

            RecordingDropdownField {
                visible: root.recordingAudioMode === "microphone" || root.recordingAudioMode === "both"
                title: Translation.tr("Microphone source")
                description: Translation.tr("Auto follows the current default microphone.")
                options: root.availableMicrophoneSourceOptions()
                currentValue: RecorderStatus.configuredMicrophoneSource
                onSelected: newValue => RecorderStatus.setConfiguredMicrophoneSource(newValue)
            }
        }

        ContentSubsection {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            visible: screenRecordSection.isCustomPreset
            title: Translation.tr("Video")

            ConfigRow {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                uniform: true

                RecordingDropdownField {
                    Layout.preferredWidth: 1
                    title: Translation.tr("Bitrate")
                    description: Translation.tr("Higher = better quality, bigger file.")
                    options: root.recordingVideoBitrateOptions
                    currentValue: Config.options?.screenRecord?.videoBitrateKbps ?? 12000
                    onSelected: newValue => root.setRecordingConfig("screenRecord.videoBitrateKbps", newValue)
                }

                RecordingDropdownField {
                    Layout.preferredWidth: 1
                    title: Translation.tr("CRF")
                    description: Translation.tr("Lower = better quality. Software mode only.")
                    options: root.recordingCrfOptions
                    currentValue: Config.options?.screenRecord?.crf ?? 21
                    onSelected: newValue => root.setRecordingConfig("screenRecord.crf", newValue)
                }
            }

            ConfigRow {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                uniform: true

                RecordingDropdownField {
                    Layout.preferredWidth: 1
                    title: Translation.tr("Encoder speed")
                    description: Translation.tr("Software mode only.")
                    options: root.recordingSoftwarePresetOptions
                    currentValue: Config.options?.screenRecord?.preset ?? "veryfast"
                    onSelected: newValue => root.setRecordingConfig("screenRecord.preset", newValue)
                }

                RecordingDropdownField {
                    Layout.preferredWidth: 1
                    title: Translation.tr("Pixel format")
                    description: ""
                    options: root.recordingPixelFormatOptions
                    currentValue: Config.options?.screenRecord?.pixelFormat ?? "yuv420p"
                    onSelected: newValue => root.setRecordingConfig("screenRecord.pixelFormat", newValue)
                }
            }
        }

        ContentSubsection {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            visible: screenRecordSection.isCustomPreset
            title: Translation.tr("Audio encoding")

            ConfigRow {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                uniform: true

                RecordingDropdownField {
                    Layout.preferredWidth: 1
                    title: Translation.tr("Bitrate")
                    description: ""
                    options: root.recordingAudioBitrateOptions
                    currentValue: Config.options?.screenRecord?.audioBitrateKbps ?? 192
                    onSelected: newValue => root.setRecordingConfig("screenRecord.audioBitrateKbps", newValue)
                }

                RecordingDropdownField {
                    Layout.preferredWidth: 1
                    title: Translation.tr("Backend")
                    description: ""
                    options: root.recordingAudioBackendOptions
                    currentValue: Config.options?.screenRecord?.audioBackend ?? ""
                    onSelected: newValue => root.setRecordingConfig("screenRecord.audioBackend", newValue)
                }
            }
        }

        ContentSubsection {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            visible: screenRecordSection.isCustomPreset && root.vaapiRecordingAvailable
            title: Translation.tr("VAAPI hardware")

            ConfigRow {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                uniform: true

                RecordingDropdownField {
                    Layout.preferredWidth: 1
                    title: Translation.tr("Render device")
                    description: ""
                    options: root.availableHardwareDeviceOptions()
                    currentValue: Config.options?.screenRecord?.hardwareDevice ?? "/dev/dri/renderD128"
                    onSelected: newValue => root.setRecordingConfig("screenRecord.hardwareDevice", newValue)
                }

                RecordingDropdownField {
                    Layout.preferredWidth: 1
                    title: Translation.tr("VAAPI filter")
                    description: ""
                    options: root.ensureOption(root.recordingVaapiFilterOptions, Config.options?.screenRecord?.vaapiFilter ?? "scale_vaapi=format=nv12:out_range=full", `${Translation.tr("Configured filter")}: ${Config.options?.screenRecord?.vaapiFilter ?? "scale_vaapi=format=nv12:out_range=full"}`)
                    currentValue: Config.options?.screenRecord?.vaapiFilter ?? "scale_vaapi=format=nv12:out_range=full"
                    onSelected: newValue => root.setRecordingConfig("screenRecord.vaapiFilter", newValue)
                }
            }
        }

    }
}

    SettingsCardSection {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        visible: true
        expanded: true
        icon: "screenshot_frame_2"
        title: Translation.tr("Screen Snipping, OCR & Lens")

    SettingsGroup {
        ConfigRow {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            uniform: width >= 500

            SettingsSwitch {
                buttonIcon: "history"
                text: Translation.tr("Remember last snip choice")
                checked: Config.options?.regionSelector?.rememberSnipChoice ?? true
                onCheckedChanged: Config.setNestedValue("regionSelector.rememberSnipChoice", checked)
            }

            SettingsSwitch {
                buttonIcon: "point_scan"
                text: Translation.tr("Show aim lines")
                checked: Config.options?.regionSelector?.rect?.showAimLines ?? true
                onCheckedChanged: {
                    Config.setNestedValue("regionSelector.rect.showAimLines", checked);
                }
            }
        }

        ContentSubsection {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            title: Translation.tr("Screenshots folder")

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: Appearance.sizes.spacingSmall

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: Directories.shortHomePath(root.effectiveScreenshotPath)
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideMiddle
                }

                RippleButtonWithIcon {
                    materialIcon: "folder_open"
                    mainText: Translation.tr("Open folder")
                    onClicked: ShellExec.openDirectory(root.effectiveScreenshotPath, Translation.tr("Open screenshots folder"))
                }

                RippleButtonWithIcon {
                    materialIcon: "drive_file_move"
                    mainText: Translation.tr("Change folder")
                    onClicked: root.openCaptureFolderDialog("screenshots")
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Hint target regions")

            GridLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                columns: width >= 370 ? 3 : 1
                uniformCellWidths: columns === 3
                columnSpacing: Appearance.sizes.spacingSmall
                rowSpacing: Appearance.sizes.spacingSmall

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "select_window"
                    text: Translation.tr('Windows')
                    checked: Config.options?.regionSelector?.targetRegions?.windows ?? true
                    onCheckedChanged: {
                        Config.setNestedValue("regionSelector.targetRegions.windows", checked);
                    }
                }
                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "right_panel_open"
                    text: Translation.tr('Layers')
                    checked: Config.options?.regionSelector?.targetRegions?.layers ?? true
                    onCheckedChanged: {
                        Config.setNestedValue("regionSelector.targetRegions.layers", checked);
                    }
                }
                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "nearby"
                    text: Translation.tr('Content')
                    checked: Config.options?.regionSelector?.targetRegions?.content ?? false
                    onCheckedChanged: {
                        Config.setNestedValue("regionSelector.targetRegions.content", checked);
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Google Lens")

            ConfigSelectionArray {
                currentValue: (Config.options?.search?.imageSearch?.useCircleSelection ?? false) ? "circle" : "rectangles"
                onSelected: newValue => {
                    Config.setNestedValue("search.imageSearch.useCircleSelection", newValue === "circle");
                }
                options: [
                    { icon: "activity_zone", value: "rectangles", displayName: Translation.tr("Rectangular") },
                    { icon: "gesture", value: "circle", displayName: Translation.tr("Circle to Search") }
                ]
            }
        }

        ConfigRow {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            uniform: width >= 500

            SettingsSwitch {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                buttonIcon: "draw"
                text: Translation.tr("Native screenshot editor")
                checked: Config.options?.regionSelector?.annotation?.useNativeEditor ?? true
                onCheckedChanged: Config.setNestedValue("regionSelector.annotation.useNativeEditor", checked)
            }

            SettingsSwitch {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                buttonIcon: "label"
                text: Translation.tr("Region labels")
                checked: Config.options?.regionSelector?.targetRegions?.showLabel ?? false
                onCheckedChanged: Config.setNestedValue("regionSelector.targetRegions.showLabel", checked)
            }
        }

        ConfigRow {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            uniform: width >= 500

            SettingsSwitch {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                buttonIcon: "open_in_new"
                text: Translation.tr("External Satty editor")
                checked: Config.options?.regionSelector?.annotation?.useSatty ?? false
                onCheckedChanged: Config.setNestedValue("regionSelector.annotation.useSatty", checked)
            }

            ConfigSpinBox {
                icon: "border_outer"
                text: Translation.tr("Region border (px)")
                value: Config.options?.regionSelector?.borderSize ?? 4
                from: 1
                to: 12
                stepSize: 1
                onValueChanged: Config.setNestedValue("regionSelector.borderSize", value)
            }
        }

        ConfigRow {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            uniform: width >= 500

            ConfigSpinBox {
                icon: "padding"
                text: Translation.tr("Target padding (px)")
                value: Config.options?.regionSelector?.targetRegions?.selectionPadding ?? 5
                from: 0
                to: 24
                stepSize: 1
                onValueChanged: Config.setNestedValue("regionSelector.targetRegions.selectionPadding", value)
            }

            ConfigSpinBox {
                icon: "gesture"
                text: Translation.tr("Circle stroke (px)")
                value: Config.options?.regionSelector?.circle?.strokeWidth ?? 6
                from: 2
                to: 16
                stepSize: 1
                onValueChanged: Config.setNestedValue("regionSelector.circle.strokeWidth", value)
            }
        }

        ContentSubsection {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            title: Translation.tr("Screenshot filename format")

            MaterialTextField {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.maximumHeight: 44
                wrapMode: TextEdit.NoWrap
                placeholderText: "ss-%Y%m%d-%H%M%S"
                text: Config.options?.regionSelector?.screenshotNameFormat ?? "ss-%Y%m%d-%H%M%S"
                onEditingFinished: Config.setNestedValue("regionSelector.screenshotNameFormat", text)
            }
        }
    }
}

    SettingsCardSection {
        id: recordingFileAndCompressSection
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        visible: true
        expanded: true
        icon: "video_file"
        title: Translation.tr("Recording File & Compression")

    SettingsGroup {
        ConfigRow {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            uniform: true

            RecordingDropdownField {
                Layout.preferredWidth: 1
                title: Translation.tr("Audio codec")
                description: ""
                options: root.availableAudioCodecOptions()
                currentValue: Config.options?.screenRecord?.audioCodec ?? "aac"
                onSelected: newValue => root.setRecordingConfig("screenRecord.audioCodec", newValue)
            }

            RecordingDropdownField {
                Layout.preferredWidth: 1
                title: Translation.tr("Sample rate")
                description: ""
                options: root.recordingSampleRateOptions
                currentValue: Config.options?.screenRecord?.audioSampleRate ?? 48000
                onSelected: newValue => root.setRecordingConfig("screenRecord.audioSampleRate", newValue)
            }
        }

        ContentSubsection {
            title: Translation.tr("Discord compression")

            SettingsSwitch {
                buttonIcon: "compress"
                text: Translation.tr("Compress recordings for Discord")
                checked: Config.options?.screenRecord?.discordCompress?.enabled ?? false
                onCheckedChanged: Config.setNestedValue("screenRecord.discordCompress.enabled", checked)
                StyledToolTip {
                    text: Translation.tr("Creates a separate Discord-ready copy after recording")
                }
            }

            NoticeBox {
                visible: Config.options?.screenRecord?.discordCompress?.enabled ?? false
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                materialIcon: "info"
                text: Translation.tr("Two-pass H.264 makes a smaller copy; original stays intact. Higher CPU load.")
            }

            ConfigRow {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                visible: Config.options?.screenRecord?.discordCompress?.enabled ?? false
                uniform: true

                RecordingDropdownField {
                    Layout.preferredWidth: 1
                    title: Translation.tr("Target size")
                    description: Translation.tr("10 MB fits Discord Free. A safety margin is applied automatically.")
                    options: root.recordingDiscordTargetSizeOptions
                    currentValue: Config.options?.screenRecord?.discordCompress?.targetSizeMb ?? 10
                    onSelected: newValue => Config.setNestedValue("screenRecord.discordCompress.targetSizeMb", newValue)
                }

                RecordingDropdownField {
                    Layout.preferredWidth: 1
                    title: Translation.tr("Max dimension")
                    description: Translation.tr("Lower values help long clips fit without turning into soup.")
                    options: root.recordingDiscordDimensionOptions
                    currentValue: Config.options?.screenRecord?.discordCompress?.maxDimension ?? 1280
                    onSelected: newValue => Config.setNestedValue("screenRecord.discordCompress.maxDimension", newValue)
                }
            }

            ConfigRow {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                visible: Config.options?.screenRecord?.discordCompress?.enabled ?? false
                uniform: true

                RecordingDropdownField {
                    Layout.preferredWidth: 1
                    title: Translation.tr("Encoder speed")
                    description: Translation.tr("Slower is smaller and cleaner, because physics remains annoying.")
                    options: root.recordingSoftwarePresetOptions
                    currentValue: Config.options?.screenRecord?.discordCompress?.preset ?? "slow"
                    onSelected: newValue => Config.setNestedValue("screenRecord.discordCompress.preset", newValue)
                }

                RecordingDropdownField {
                    Layout.preferredWidth: 1
                    title: Translation.tr("Audio bitrate")
                    description: Translation.tr("Automatically reduced if the clip needs more video budget.")
                    options: root.recordingAudioBitrateOptions
                    currentValue: Config.options?.screenRecord?.discordCompress?.audioBitrateKbps ?? 96
                    onSelected: newValue => Config.setNestedValue("screenRecord.discordCompress.audioBitrateKbps", newValue)
                }
            }

            SettingsSwitch {
                enabled: Config.options?.screenRecord?.discordCompress?.enabled ?? false
                buttonIcon: "done_all"
                text: Translation.tr("Skip compression when already under target")
                checked: Config.options?.screenRecord?.discordCompress?.onlyIfNeeded ?? true
                onCheckedChanged: Config.setNestedValue("screenRecord.discordCompress.onlyIfNeeded", checked)
            }
        }

        ContentSubsection {
            title: Translation.tr("File naming")

            ContentSubsectionLabel {
                text: Translation.tr("Recording filename format (date tokens)")
            }
            MaterialTextField {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.maximumHeight: 44
                wrapMode: TextEdit.NoWrap
                placeholderText: "recording_%Y-%m-%d_%H.%M.%S"
                text: Config.options?.screenRecord?.recordingNameFormat ?? "recording_%Y-%m-%d_%H.%M.%S"
                onEditingFinished: Config.setNestedValue("screenRecord.recordingNameFormat", text)
            }
        }
    }
}

    SettingsCardSection {
        id: captureToolsQuickSection
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        visible: true
        expanded: true
        icon: "keyboard_onscreen"
        title: Translation.tr("Clipboard, Keyboard & Quick Tools")

    SettingsGroup {
        ConfigRow {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            uniform: width >= 500

            SettingsSwitch {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                buttonIcon: "content_paste"
                text: Translation.tr("Clipboard history")
                checked: Config.options?.modules?.clipboard ?? true
                onCheckedChanged: Config.setNestedValue("modules.clipboard", checked)
            }

            SettingsSwitch {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                buttonIcon: "keyboard"
                text: Translation.tr("On-screen keyboard")
                checked: Config.options?.modules?.onScreenKeyboard ?? true
                onCheckedChanged: Config.setNestedValue("modules.onScreenKeyboard", checked)
            }
        }

        ConfigRow {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            uniform: width >= 500

            SettingsSwitch {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                enabled: Config.options?.modules?.onScreenKeyboard ?? true
                buttonIcon: "push_pin"
                text: Translation.tr("Pin OSK on startup")
                checked: Config.options?.osk?.pinnedOnStartup ?? false
                onCheckedChanged: Config.setNestedValue("osk.pinnedOnStartup", checked)
            }

            SettingsSwitch {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                enabled: Config.options?.modules?.onScreenKeyboard ?? true
                buttonIcon: "flip_to_front"
                text: Translation.tr("Keep OSK on top")
                checked: Config.options?.osk?.keepOnTop ?? false
                onCheckedChanged: Config.setNestedValue("osk.keepOnTop", checked)
            }
        }

        ContentSubsection {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            title: Translation.tr("OSK layout")

            StyledComboBox {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                enabled: Config.options?.modules?.onScreenKeyboard ?? true
                model: root.availableOskLayoutOptions()
                textRole: "displayName"
                currentIndex: root.choiceIndex(model, Config.options?.osk?.layout ?? "English (US)")
                onActivated: index => {
                    if (index >= 0 && index < model.length)
                        Config.setNestedValue("osk.layout", model[index].value)
                }
            }
        }

        SettingsDivider {}

        ContentSubsection {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            title: Translation.tr("Bar capture shortcuts")

            ConfigRow {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                uniform: width >= 500

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    buttonIcon: "screenshot_region"
                    text: Translation.tr("Screen snip button")
                    checked: Config.options?.bar?.utilButtons?.showScreenSnip ?? true
                    onCheckedChanged: Config.setNestedValue("bar.utilButtons.showScreenSnip", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    buttonIcon: "screen_record"
                    text: Translation.tr("Screen record button")
                    checked: Config.options?.bar?.utilButtons?.showScreenRecord ?? true
                    onCheckedChanged: Config.setNestedValue("bar.utilButtons.showScreenRecord", checked)
                }
            }

            ConfigRow {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                uniform: width >= 500

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    buttonIcon: "colorize"
                    text: Translation.tr("Color picker button")
                    checked: Config.options?.bar?.utilButtons?.showColorPicker ?? false
                    onCheckedChanged: Config.setNestedValue("bar.utilButtons.showColorPicker", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    buttonIcon: "edit_note"
                    text: Translation.tr("Quick notepad button")
                    checked: Config.options?.bar?.utilButtons?.showNotepad ?? true
                    onCheckedChanged: Config.setNestedValue("bar.utilButtons.showNotepad", checked)
                }
            }

            ConfigRow {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                uniform: width >= 500

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    buttonIcon: "keyboard_alt"
                    text: Translation.tr("Keyboard toggle button")
                    checked: Config.options?.bar?.utilButtons?.showKeyboardToggle ?? true
                    onCheckedChanged: Config.setNestedValue("bar.utilButtons.showKeyboardToggle", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    buttonIcon: "widgets"
                    text: Translation.tr("Utilities button")
                    checked: Config.options?.bar?.utilButtons?.showUtilitiesLauncher ?? true
                    onCheckedChanged: Config.setNestedValue("bar.utilButtons.showUtilitiesLauncher", checked)
                }
            }
        }
    }
}
}
