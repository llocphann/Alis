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

    Process {
        id: translateProc
        command: [
            "/usr/bin/trans",
            "-no-theme",
            "-no-bidi",
            "-source",
            root.sourceLanguage,
            "-target",
            root.targetLanguage,
            "-no-ansi",
            root.inputField.text.trim()
        ]
        stdout: StdioCollector {
            id: translateCollector
            onStreamFinished: {
                // Split into sections by double newlines
                const buffer = translateCollector.text || "";
                const sections = buffer.trim().split(/\n\s*\n/);
                // Extract translated text from second section
                root.translatedText = sections.length > 1 ? sections[1].trim() : "";
            }
        }
    }

    Process {
        id: getLanguagesProc
        command: ["/usr/bin/trans", "-list-languages", "-no-bidi"]
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

    Rectangle {
        id: translatorCloudBackground
        visible: root.abyssMode
        anchors.fill: parent
        anchors.margins: root.padding
        radius: 14
        color: root.cloudColor
        border.width: 1
        border.color: root.cloudBorderColor
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: root.edgeSurfaceColor(1.0) }
            GradientStop { position: 1.0; color: root.edgeSurfaceColor(0.25) }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: root.edgeRadius * 0.7
            anchors.rightMargin: root.edgeRadius * 0.7
            height: 1.5
            radius: 1
            color: Qt.alpha(AbyssStyle.accent, 0.45)
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.abyssMode ? (root.padding + 10) : root.padding
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

                LanguageSelectorButton { // Target language button
                    id: targetLanguageButton
                    displayText: root.targetLanguage
                    onClicked: {
                        root.showLanguageSelectorDialog(true);
                    }
                }

                TextCanvas { // Content translation
                    id: outputCanvas
                    isInput: false
                    placeholderText: Translation.tr("Translation goes here...")
                    property bool hasTranslation: (root.translatedText.trim().length > 0)
                    text: hasTranslation ? root.translatedText : ""
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
                            let url = (Config.options?.search?.engineBaseUrl ?? "https://www.google.com/search?q=") + outputCanvas.displayedText;
                            for (let site of (Config.options?.search?.excludedSites ?? [])) {
                                url += ` -site:${site}`;
                            }
                            Qt.openUrlExternally(url);
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
