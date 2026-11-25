import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.abyss.looks
import qs.modules.sidebarLeft.translator
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Translator widget with the `trans` commandline tool.
 */
Item {
    id: root

    // Sizes
    property real padding: 4
    readonly property bool abyssMode: Config.options?.panelFamily === "abyss"
    readonly property real edgeOpacity: AbyssStyle.contentOpacity
    readonly property real edgeHighlight: AbyssStyle.highlightStrength
    readonly property real edgeLift: AbyssStyle.blurRadius > 0 ? 0.024 : 0
    readonly property real edgeRadius: Math.max(12, Math.min(26, AbyssStyle.perimeterRadius))
    readonly property color cloudColor: Qt.rgba(
        Math.min(1, AbyssStyle.surfaceDeep.r + edgeLift),
        Math.min(1, AbyssStyle.surfaceDeep.g + edgeLift),
        Math.min(1, AbyssStyle.surfaceDeep.b + edgeLift),
        edgeOpacity
    )
    readonly property color cloudBorderColor: edgeHighlight > 0.01
        ? Qt.alpha(AbyssStyle.specular, Math.max(0.08, 0.55 * edgeHighlight))
        : Qt.alpha(AbyssStyle.textColor, 0.06)

    function edgeSurfaceColor(depthWeight): color {
        const k = Math.max(0, Math.min(1, depthWeight * 0.38 * root.edgeHighlight))
        return Qt.rgba(
            root.cloudColor.r + (AbyssStyle.surfaceRaised.r - root.cloudColor.r) * k,
            root.cloudColor.g + (AbyssStyle.surfaceRaised.g - root.cloudColor.g) * k,
            root.cloudColor.b + (AbyssStyle.surfaceRaised.b - root.cloudColor.b) * k,
            root.edgeOpacity
        )
    }

    // Widgets
    property var inputField: inputCanvas.inputTextArea

    // Widget variables
    property bool translationFor: false // Indicates if the translation is for an autocorrected text
    property string translatedText: ""
    property var languages: ["auto"]
    property var translationHistory: []
    property bool showHistory: false
    property bool speaking: false
    property string _pendingSpeakText: ""

    function stopSpeaking(): void {
        root._pendingSpeakText = "";
        if (ttsProc.running) {
            try { ttsProc.signal(15); } catch (_e) { ttsProc.running = false; }
        }
        root.speaking = false;
    }

    function _launchSpeak(cleaned: string): void {
        const script = [
            "set -u",
            "text=\"$1\"",
            "tts_bin=\"\"",
            "if command -v edge-tts >/dev/null 2>&1; then tts_bin=\"$(command -v edge-tts)\"",
            "elif [ -x \"$HOME/.local/bin/edge-tts\" ]; then tts_bin=\"$HOME/.local/bin/edge-tts\"",
            "elif [ -x \"$HOME/.local/state/quickshell/.venv/bin/edge-tts\" ]; then tts_bin=\"$HOME/.local/state/quickshell/.venv/bin/edge-tts\"",
            "fi",
            "tmp=\"$(mktemp \"${TMPDIR:-/tmp}/alis-tr-tts.XXXXXX.mp3\" 2>/dev/null || true)\"",
            "[ -n \"$tmp\" ] || exit 0",
            "child=\"\"",
            "cleanup() { if [ -n \"$child\" ]; then kill -TERM \"$child\" 2>/dev/null || true; child=\"\"; fi; rm -f -- \"$tmp\"; }",
            "trap cleanup EXIT",
            "trap 'cleanup; exit 0' TERM INT HUP",
            "if [ -n \"$tts_bin\" ]; then \"$tts_bin\" --voice en-US-AvaMultilingualNeural --text=\"$text\" --write-media \"$tmp\" >/dev/null 2>&1 & child=$!; wait \"$child\" 2>/dev/null || exit 0; child=\"\"",
            "elif command -v python3 >/dev/null 2>&1 && python3 -c 'import edge_tts' >/dev/null 2>&1; then python3 -m edge_tts --voice en-US-AvaMultilingualNeural --text=\"$text\" --write-media \"$tmp\" >/dev/null 2>&1 & child=$!; wait \"$child\" 2>/dev/null || exit 0; child=\"\"",
            "else exit 0; fi",
            "[ -s \"$tmp\" ] || exit 0",
            "if command -v mpv >/dev/null 2>&1; then mpv --no-video --really-quiet \"$tmp\" >/dev/null 2>&1 & child=$!; wait \"$child\" 2>/dev/null || true",
            "elif command -v ffplay >/dev/null 2>&1; then ffplay -nodisp -autoexit -loglevel quiet \"$tmp\" >/dev/null 2>&1 & child=$!; wait \"$child\" 2>/dev/null || true",
            "elif command -v pw-play >/dev/null 2>&1; then pw-play \"$tmp\" >/dev/null 2>&1 & child=$!; wait \"$child\" 2>/dev/null || true",
            "elif command -v paplay >/dev/null 2>&1; then paplay \"$tmp\" >/dev/null 2>&1 & child=$!; wait \"$child\" 2>/dev/null || true",
            "fi"
        ].join("\n");
        ttsProc.command = ["/usr/bin/bash", "-c", script, "alis-tr-tts", cleaned];
        root.speaking = true;
        ttsProc.running = true;
    }

    function speakText(rawText): void {
        const cleaned = String(rawText ?? "").replace(/\s+/g, " ").trim().slice(0, 600);
        if (!cleaned.length)
            return;
        if (ttsProc.running) {
            root._pendingSpeakText = cleaned;
            try { ttsProc.signal(15); } catch (_e) { ttsProc.running = false; }
            return;
        }
        root._launchSpeak(cleaned);
    }

    Process {
        id: ttsProc
        onExited: {
            const queued = root._pendingSpeakText;
            root._pendingSpeakText = "";
            if (queued.length > 0) {
                Qt.callLater(() => root._launchSpeak(queued));
                return;
            }
            root.speaking = false;
        }
        onRunningChanged: {
            if (!running && root._pendingSpeakText.length === 0)
                root.speaking = false;
        }
    }

    Component.onDestruction: root.stopSpeaking()

    function swapLanguages(): void {
        if (root.sourceLanguage === "auto")
            return;
        const oldSource = root.sourceLanguage;
        const oldTarget = root.targetLanguage;
        const prevOutput = root.translatedText.trim();
        root.sourceLanguage = oldTarget;
        root.targetLanguage = oldSource;
        Config.setNestedValue("language.translator.sourceLanguage", root.sourceLanguage);
        Config.setNestedValue("language.translator.targetLanguage", root.targetLanguage);
        if (prevOutput.length > 0 && root.inputField) {
            root.inputField.text = prevOutput;
            translateTimer.restart();
        }
    }

    function _recordHistory(srcText, outText): void {
        const s = String(srcText ?? "").trim();
        const o = String(outText ?? "").trim();
        if (!s || !o) return;
        const entry = { source: s, target: o, from: root.sourceLanguage, to: root.targetLanguage };
        const filtered = (root.translationHistory ?? []).filter(it => it.source !== s || it.to !== entry.to);
        root.translationHistory = [entry].concat(filtered).slice(0, 10);
    }

    // Options
    property string targetLanguage: Config.options?.language?.translator?.targetLanguage ?? "en"
    property string sourceLanguage: Config.options?.language?.translator?.sourceLanguage ?? "auto"
    property string hostLanguage: targetLanguage

    // States
    property bool showLanguageSelector: false
    property bool languageSelectorTarget: false // true for target language, false for source language

    function showLanguageSelectorDialog(isTargetLang: bool) {
        root.languageSelectorTarget = isTargetLang;
        root.showLanguageSelector = true
    }

    onFocusChanged: (focus) => {
        if (focus && root.inputField) {
            // Defer focus to next event loop tick to ensure the item is in a window
            Qt.callLater(() => root.inputField.forceActiveFocus());
        }
    }

    Timer {
        id: translateTimer
        interval: Config.options?.sidebar?.translator?.delay ?? 500
        repeat: false
        onTriggered: () => {
            if (root.inputField.text.trim().length > 0) {
                translateProc.running = false;
                translateProc.running = true; // Restart the process
            } else {
                root.translatedText = "";
            }
        }
    }

    readonly property string _nativeDispatch: FileUtils.trimFileProtocol(`${Directories.scriptPath}/native-dispatch`)

    Process {
        id: translateProc
        command: [
            root._nativeDispatch,
            "translate",
            "--source",
            root.sourceLanguage,
            "--target",
            root.targetLanguage,
            "--",
            root.inputField.text.trim()
        ]
        stdout: StdioCollector {
            id: translateCollector
            onStreamFinished: {
                const buffer = String(translateCollector.text || "").trim();
                root.translatedText = buffer;
                if (buffer.length > 0 && root.inputField)
                    root._recordHistory(root.inputField.text, buffer);
            }
        }
    }

    Process {
        id: getLanguagesProc
        command: [root._nativeDispatch, "translate", "--list-languages"]
        stdout: StdioCollector {
            id: langsCollector
            onStreamFinished: {
                // Parse collected text into language list, ensure "auto" is first
                const text = String(langsCollector.text || "");
                if (!text || !text.trim()) {
                    root.languages = ["auto"];
                    return;
                }
                // Simple split + trim; JS array, no fancy constructs to keep QML happy.
                var parsed = text.split("\n");
                var result = ["auto"];
                for (var i = 0; i < parsed.length; ++i) {
                    var lang = String(parsed[i]).trim();
                    if (!lang || lang === "auto")
                        continue;
                    if (result.indexOf(lang) === -1)
                        result.push(lang);
                }
                try {
                    root.languages = result;
                } catch (e) {
                    // Keep the initial ["auto"] default and avoid spamming the full error
                    console.warn("[Translator] Failed to set languages list, keeping ['auto'] as fallback");
                }
            }
        }
        Component.onCompleted: running = true
    }

    readonly property color colTonalBase: ColorUtils.applyAlpha(
        Qt.color(Appearance.colors.colLayer1Base).valid
            ? Appearance.colors.colLayer1Base
            : Appearance.colors.colLayer0Base,
        1.0
    )
    readonly property real tonalDir: Qt.color(root.colTonalBase).hslLightness > 0.86 ? -1 : 1

    Rectangle {
        id: translatorCloudBackground
        objectName: "translatorCloudBackground"
        visible: root.abyssMode
        anchors.fill: parent
        anchors.margins: 0
        radius: Appearance.rounding.normal
        color: root.cloudColor
        border.width: 1
        border.color: root.cloudBorderColor
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: root.edgeSurfaceColor(1.0) }
            GradientStop { position: 1.0; color: root.edgeSurfaceColor(0.25) }
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.abyssMode ? 10 : root.padding
        }
        spacing: 8

        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: contentColumn.implicitHeight
            clip: true

            ColumnLayout {
                id: contentColumn
                width: parent.width
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    LanguageSelectorButton { // Target language button
                        id: targetLanguageButton
                        displayText: root.targetLanguage
                        onClicked: {
                            root.showLanguageSelectorDialog(true);
                        }
                    }
                    GroupButton {
                        id: swapLangButton
                        baseWidth: 32
                        baseHeight: 32
                        buttonRadius: Appearance.rounding.small
                        enabled: root.sourceLanguage !== "auto"
                        colBackground: root.abyssMode ? Qt.alpha(AbyssStyle.textColor, 0.05) : Appearance.colors.colLayer1
                        colBackgroundHover: root.abyssMode ? Qt.alpha(AbyssStyle.accent, 0.14) : Appearance.colors.colLayer1Hover
                        contentItem: Item {
                            implicitWidth: 18
                            implicitHeight: 18
                            MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                iconSize: Appearance.font.pixelSize.normal
                                text: "swap_horiz"
                                color: swapLangButton.enabled
                                    ? (root.abyssMode ? AbyssStyle.textColor : Appearance.colors.colOnLayer1)
                                    : Appearance.colors.colSubtext
                            }
                        }
                        onClicked: root.swapLanguages()
                    }
                    Item { Layout.fillWidth: true }
                    GroupButton {
                        id: historyToggleButton
                        visible: root.translationHistory.length > 0
                        baseWidth: 32
                        baseHeight: 32
                        buttonRadius: Appearance.rounding.small
                        toggled: root.showHistory
                        colBackground: root.abyssMode ? Qt.alpha(AbyssStyle.textColor, 0.05) : Appearance.colors.colLayer1
                        colBackgroundHover: root.abyssMode ? Qt.alpha(AbyssStyle.accent, 0.14) : Appearance.colors.colLayer1Hover
                        colBackgroundToggled: Appearance.colors.colPrimary
                        contentItem: Item {
                            implicitWidth: 18
                            implicitHeight: 18
                            MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                iconSize: Appearance.font.pixelSize.normal
                                text: "history"
                                color: root.showHistory ? Appearance.colors.colOnPrimary : (root.abyssMode ? AbyssStyle.textColor : Appearance.colors.colOnLayer1)
                            }
                        }
                        onClicked: root.showHistory = !root.showHistory
                    }
                }

                ColumnLayout {
                    visible: root.showHistory && root.translationHistory.length > 0
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: root.translationHistory.slice(0, 5)
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: histLbl.implicitHeight + 10
                            radius: 8
                            color: root.abyssMode
                                ? Qt.alpha(AbyssStyle.textColor, 0.05)
                                : ColorUtils.tonalStep(root.colTonalBase, root.tonalDir * 0.04, 1.05)
                            border.width: root.abyssMode ? 1 : 0
                            border.color: root.abyssMode ? Qt.alpha(AbyssStyle.textColor, 0.08) : "transparent"
                            StyledText {
                                id: histLbl
                                anchors.fill: parent
                                anchors.margins: 5
                                text: `${modelData.from}→${modelData.to}: ${modelData.source} = ${modelData.target}`
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: root.abyssMode ? AbyssStyle.textColor : Appearance.colors.colOnLayer1
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.inputField) root.inputField.text = modelData.source;
                                    root.translatedText = modelData.target;
                                    root.showHistory = false;
                                }
                            }
                        }
                    }
                }

                TextCanvas { // Content translation
                    id: outputCanvas
                    isInput: false
                    placeholderText: Translation.tr("Translation goes here...")
                    property bool hasTranslation: (root.translatedText.trim().length > 0)
                    text: hasTranslation ? root.translatedText : ""
                    GroupButton {
                        id: listenButton
                        objectName: "translatorListenButton"
                        baseWidth: 34
                        baseHeight: 34
                        buttonRadius: Appearance.rounding.small
                        enabled: outputCanvas.displayedText.trim().length > 0
                        toggled: root.speaking
                        colBackground: root.abyssMode ? Qt.alpha(AbyssStyle.textColor, 0.05) : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                        colBackgroundHover: root.abyssMode ? Qt.alpha(AbyssStyle.accent, 0.14) : Appearance.colors.colLayer1Hover
                        colBackgroundActive: root.abyssMode ? Qt.alpha(AbyssStyle.accent, 0.22) : Appearance.colors.colLayer1Active
                        colBackgroundToggled: Appearance.colors.colPrimary
                        contentItem: Item {
                            implicitWidth: 20
                            implicitHeight: 20
                            MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                iconSize: Appearance.font.pixelSize.larger
                                text: root.speaking ? "stop_circle" : "volume_up"
                                color: root.speaking
                                    ? Appearance.colors.colOnPrimary
                                    : (listenButton.enabled
                                        ? (root.abyssMode ? AbyssStyle.textColor : Appearance.colors.colOnLayer1)
                                        : (root.abyssMode ? Qt.alpha(AbyssStyle.textColorMuted, 0.45) : Appearance.colors.colSubtext))
                            }
                        }
                        onClicked: {
                            if (root.speaking)
                                root.stopSpeaking();
                            else
                                root.speakText(outputCanvas.displayedText);
                        }
                    }
                    GroupButton {
                        id: copyButton
                        baseWidth: 34
                        baseHeight: 34
                        buttonRadius: Appearance.rounding.small
                        enabled: outputCanvas.displayedText.trim().length > 0
                        colBackground: root.abyssMode ? Qt.alpha(AbyssStyle.textColor, 0.05) : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                        colBackgroundHover: root.abyssMode ? Qt.alpha(AbyssStyle.accent, 0.14) : Appearance.colors.colLayer1Hover
                        colBackgroundActive: root.abyssMode ? Qt.alpha(AbyssStyle.accent, 0.22) : Appearance.colors.colLayer1Active
                        contentItem: Item {
                            implicitWidth: 20
                            implicitHeight: 20
                            MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                iconSize: Appearance.font.pixelSize.larger
                                text: "content_copy"
                                color: copyButton.enabled
                                    ? (root.abyssMode ? AbyssStyle.textColor : Appearance.colors.colOnLayer1)
                                    : (root.abyssMode ? Qt.alpha(AbyssStyle.textColorMuted, 0.45) : Appearance.colors.colSubtext)
                            }
                        }
                        onClicked: {
                            Quickshell.clipboardText = outputCanvas.displayedText
                        }
                    }
                    GroupButton {
                        id: searchButton
                        baseWidth: 34
                        baseHeight: 34
                        buttonRadius: Appearance.rounding.small
                        enabled: outputCanvas.displayedText.trim().length > 0
                        colBackground: root.abyssMode ? Qt.alpha(AbyssStyle.textColor, 0.05) : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                        colBackgroundHover: root.abyssMode ? Qt.alpha(AbyssStyle.accent, 0.14) : Appearance.colors.colLayer1Hover
                        colBackgroundActive: root.abyssMode ? Qt.alpha(AbyssStyle.accent, 0.22) : Appearance.colors.colLayer1Active
                        contentItem: Item {
                            implicitWidth: 20
                            implicitHeight: 20
                            MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                iconSize: Appearance.font.pixelSize.larger
                                text: "travel_explore"
                                color: searchButton.enabled
                                    ? (root.abyssMode ? AbyssStyle.textColor : Appearance.colors.colOnLayer1)
                                    : (root.abyssMode ? Qt.alpha(AbyssStyle.textColorMuted, 0.45) : Appearance.colors.colSubtext)
                            }
                        }
                        onClicked: {
                            let query = outputCanvas.displayedText;
                            for (let site of (Config.options?.search?.excludedSites ?? [])) {
                                query += ` -site:${site}`;
                            }
                            const base = Config.options?.search?.engineBaseUrl ?? "https://www.google.com/search?q=";
                            Qt.openUrlExternally(base + encodeURIComponent(query));
                        }
                    }
                }

            }    
        }

        LanguageSelectorButton { // Source language button
            id: sourceLanguageButton
            displayText: root.sourceLanguage
            onClicked: {
                root.showLanguageSelectorDialog(false);
            }
        }

        TextCanvas { // Content input
            id: inputCanvas
            isInput: true
            placeholderText: Translation.tr("Enter text to translate...")
            onInputTextChanged: {
                translateTimer.restart();
            }
            GroupButton {
                id: pasteButton
                baseWidth: 34
                baseHeight: 34
                buttonRadius: Appearance.rounding.small
                colBackground: root.abyssMode ? Qt.alpha(AbyssStyle.textColor, 0.05) : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                colBackgroundHover: root.abyssMode ? Qt.alpha(AbyssStyle.accent, 0.14) : Appearance.colors.colLayer1Hover
                colBackgroundActive: root.abyssMode ? Qt.alpha(AbyssStyle.accent, 0.22) : Appearance.colors.colLayer1Active
                contentItem: Item {
                    implicitWidth: 20
                    implicitHeight: 20
                    MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: Appearance.font.pixelSize.larger
                        text: "content_paste"
                        color: root.abyssMode ? AbyssStyle.textColor : Appearance.colors.colOnLayer1
                    }
                }
                onClicked: {
                    root.inputField.text = Quickshell.clipboardText
                }
            }
            GroupButton {
                id: deleteButton
                baseWidth: 34
                baseHeight: 34
                buttonRadius: Appearance.rounding.small
                enabled: (inputCanvas.inputTextArea?.text?.length ?? 0) > 0
                colBackground: root.abyssMode ? Qt.alpha(AbyssStyle.textColor, 0.05) : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                colBackgroundHover: root.abyssMode ? Qt.alpha(AbyssStyle.accent, 0.14) : Appearance.colors.colLayer1Hover
                colBackgroundActive: root.abyssMode ? Qt.alpha(AbyssStyle.accent, 0.22) : Appearance.colors.colLayer1Active
                contentItem: Item {
                    implicitWidth: 20
                    implicitHeight: 20
                    MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: Appearance.font.pixelSize.larger
                        text: "close"
                        color: deleteButton.enabled
                            ? (root.abyssMode ? AbyssStyle.textColor : Appearance.colors.colOnLayer1)
                            : (root.abyssMode ? Qt.alpha(AbyssStyle.textColorMuted, 0.45) : Appearance.colors.colSubtext)
                    }
                }
                onClicked: {
                    root.inputField.text = ""
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.showLanguageSelector
        visible: root.showLanguageSelector
        z: 9999
        sourceComponent: SelectionDialog {
            id: languageSelectorDialog
            titleText: Translation.tr("Select Language")
            items: root.languages
            defaultChoice: root.languageSelectorTarget ? root.targetLanguage : root.sourceLanguage
            onCanceled: () => {
                root.showLanguageSelector = false;
            }
            onSelected: (result) => {
                root.showLanguageSelector = false;
                if (!result || result.length === 0) return; // No selection made

                if (root.languageSelectorTarget) {
                    root.targetLanguage = result;
                    Config.setNestedValue("language.translator.targetLanguage", result)
                } else {
                    root.sourceLanguage = result;
                    Config.setNestedValue("language.translator.sourceLanguage", result)
                }

                translateTimer.restart(); // Restart translation after language change
            }
        }
    }
}
