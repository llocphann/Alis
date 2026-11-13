import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.services.deferred
import qs.services.ai
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    settingsPageIndex: 24
    settingsPageName: Translation.tr("AI")
    property string activeSection: "setup"
    onActiveSectionChanged: if (activeSection !== "setup") activeSection = "setup"

    function activateSettingsSearchSection(section: string): bool {
        root.activeSection = "setup";
        return true;
    }

    SettingsTaskNavigator {
        showTabBar: false
        showIntro: false
        icon: "neurology"
        title: Translation.tr("AI")
        description: Translation.tr("Choose a provider and opt in to voice or privacy-sensitive features.")
        summary: Translation.tr("Providers & Voice · Assistant Behavior")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            {
                displayName: Translation.tr("AI"),
                icon: "neurology",
                value: "setup"
            }
        ]
    }

    Component.onCompleted: {
        Ai.ensureInitialized();
        LocalModels.ensureInitialized();
        VoiceSearch.ensureInitialized();
    }

    readonly property bool companionActive: AlisCompanion.available && !!companionAiSection.item
    readonly property string companionModelLabel: String(companionAiSection.item?.companionActiveModelLabel ?? "")
    readonly property string companionRoutingLabel: String(companionAiSection.item?.companionRoutingSummaryLabel ?? "")
    readonly property int dedupedLocalModelCount: {
        const catalogCount = Number(AiProviderCatalog.localModelCount ?? 0);
        const ggufList = Array.isArray(LocalModels.models) ? LocalModels.models : [];
        if (ggufList.length === 0)
            return catalogCount;
        if (catalogCount === 0)
            return ggufList.length;
        const lmStudioModels = AiProviderCatalog.modelsFor("lmstudio") ?? [];
        const liveLocalModels = lmStudioModels.concat(AiProviderCatalog.modelsFor("ollama") ?? []);
        const norm = s => String(s ?? "").toLowerCase().replace(/^(?:lmstudio-|ollama-|gguf:)/, "").replace(/\.gguf$/i, "").replace(/[@\-](?:ud-)?(?:iq|q|f|bf)\d[\w_.\-]*$/i, "").replace(/uncnr/g, "uncensored").replace(/imatrix/g, "").replace(/[^a-z0-9]+/g, "");
        const liveNorms = liveLocalModels.map(m => norm(m?.remoteId || m?.displayName || m?.name || m?.id || "")).filter(Boolean);
        const hasLmStudioCatalog = (AiProviderCatalog.stateFor("lmstudio")?.modelCount ?? 0) > 0 || lmStudioModels.length > 0;
        let extraGguf = 0;
        for (const item of ggufList) {
            const rawName = item?.name || item?.file || (item?.path ? String(item.path).split("/").pop() : "") || item?.id || "";
            const fileNorm = norm(rawName);
            const pathStr = String(item?.path ?? "").replace(/\\/g, "/").toLowerCase();
            const srcStr = String(item?.source ?? "").toLowerCase();
            const matchedLive = liveNorms.some(ln => ln && fileNorm && (ln === fileNorm || ln.includes(fileNorm) || fileNorm.includes(ln) || (ln.length >= 16 && fileNorm.length >= 16 && ln.slice(0, 16) === fileNorm.slice(0, 16))));
            const inLmStudioCache = hasLmStudioCatalog && (pathStr.includes("/.lmstudio/models/") || pathStr.includes("/lm-studio/models/") || srcStr.includes("lm studio"));
            if (!matchedLive && !inLmStudioCache)
                extraGguf += 1;
        }
        return catalogCount + extraGguf;
    }
    readonly property bool activeModelReady: companionActive ? (Boolean(companionAiSection.item?.companionActiveModelReady) || (companionModelLabel.length > 0 && companionModelLabel !== "No available model") || dedupedLocalModelCount > 0) : ((Ai.getModel() ?? null) !== null)
    readonly property string activeModelDisplayName: {
        if (companionActive && companionModelLabel.length > 0 && companionModelLabel !== "No available model") {
            return companionModelLabel;
        }
        return (Ai.getModel() ?? null) !== null ? String(Ai.getModel().name ?? "") : "";
    }
    readonly property bool activeModelUsesLocalNoKey: companionActive ? Boolean(companionAiSection.item?.companionActiveModelLocal ?? true) : Boolean(Ai.getModel()?.local || !Ai.getModel()?.requires_key)
    readonly property string defaultCompanionSystemPromptFallback: "You are Alis-Companion, a grounded Linux desktop assistant and agent running on {DISTRO} ({DE}) at {DATETIME} (active window: {WINDOWCLASS}).\n- Ground every file, directory, code, or system claim in real tool output; never fabricate paths, line numbers, or command results.\n- If an @file mention or path does not exist on disk, state clearly that it was not found instead of guessing its contents.\n- Lead with a concise, direct answer in clean Markdown and match the user's language (Vietnamese or English)."
    readonly property string defaultCompanionRulesFallback: "- Ground every file, directory, or code claim in real tool output; never fabricate paths, line numbers, or command results.\n- If an `@file` mention or target path does not exist on disk, state clearly that it was not found instead of guessing its contents.\n- Keep responses concise, structured in clean Markdown, and match the user's language (Vietnamese or English).\n- Never execute destructive or out-of-Home system actions without explicit confirmation."
    readonly property real targetBentoHeight: {
        const gap = SettingsMaterialPreset.pageSpacing;
        const baseH = SettingsMaterialPreset.standardBentoHeight;
        const availBodyH = root.height >= 800
            ? Math.max(720, root.height - 20 - (root._subTabItems.length > 1 || SettingsLayoutManager.editMode ? (40 + gap) : 0))
            : baseH;
        return Math.min(baseH, availBodyH);
    }
    readonly property bool twoColBento: root.width <= 0 || root.width >= 560
    readonly property real getStartedNaturalHeight: getStartedSection.chromeImplicitHeight
        + SettingsMaterialPreset.groupPadding * 2
        + getStartedInnerCol.implicitHeight
    readonly property real toolModeNaturalHeight: toolModeFallbackCard.visible
        ? (toolModeFallbackCard.chromeImplicitHeight
            + SettingsMaterialPreset.groupPadding * 2
            + toolModeContentSubsection.implicitHeight)
        : 0
    readonly property real topBentoRowHeight: {
        const minTop = Math.max(getStartedNaturalHeight, toolModeNaturalHeight);
        if (!root.twoColBento)
            return minTop;
        const targetRatioH = Math.round((root.targetBentoHeight - SettingsMaterialPreset.pageSpacing) * 0.44);
        return Math.max(minTop, targetRatioH);
    }
    readonly property real bottomBentoRowHeight: Math.max(
        220,
        root.targetBentoHeight - root.topBentoRowHeight - SettingsMaterialPreset.pageSpacing
    )

    // ── 1. Get started (Top-Left Bento, Compact 2x2 Grid + Voice) ────────────
    SettingsCardSection {
        id: getStartedSection
        objectName: "aiGetStartedSection"
        bentoColumn: "left"
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        settingsTaskSection: "setup"
        visible: true
        expanded: true
        icon: "rocket_launch"
        title: Translation.tr("Get started")

        SettingsGroup {
            spacing: 0

            ColumnLayout {
                id: getStartedInnerCol
                Layout.fillWidth: true
                spacing: 6

            GridLayout {
                Layout.fillWidth: true
                columns: getStartedSection.width > 420 ? 2 : 1
                uniformCellWidths: columns > 1
                columnSpacing: 8
                rowSpacing: 6

                StatusTile {
                    objectName: "activeModelStatus"
                    statusIcon: "smart_toy"
                    ok: root.activeModelReady
                    label: root.activeModelDisplayName.length > 0 ? Translation.tr("Active model: %1").arg(root.activeModelDisplayName) : Translation.tr("No model selected")
                    detail: root.companionActive && root.companionRoutingLabel.length > 0 ? root.companionRoutingLabel : Translation.tr("Alis keeps the selected model and can add live models from connected providers automatically")
                }

                StatusTile {
                    objectName: "apiKeyStatus"
                    statusIcon: root.activeModelUsesLocalNoKey ? "verified_user" : "key"
                    ok: root.activeModelUsesLocalNoKey || Ai.currentModelHasApiKey
                    label: root.activeModelUsesLocalNoKey ? Translation.tr("Local runtime ready — no API key required") : (Ai.currentModelHasApiKey ? Translation.tr("API key stored for the active model") : Translation.tr("The active model needs an API key"))
                    detail: root.activeModelUsesLocalNoKey ? Translation.tr("Local only: use on-device models (Ollama, LM Studio).") : (Ai.currentModelHasApiKey ? "" : Translation.tr("Connect the provider below. Keys are stored in the system keyring."))
                }

                StatusTile {
                    objectName: "localModelStatus"
                    readonly property bool localFound: root.dedupedLocalModelCount > 0 || Ai.modelList.some(m => Ai.models[m]?.local === true)
                    readonly property bool localReady: root.dedupedLocalModelCount > 0 || Ai.modelList.some(m => Ai.models[m]?.local === true && (Ai.models[m]?.api_format !== "gguf" || !!Ai.models[m]?.runtime_path))
                    statusIcon: "computer"
                    ok: localReady
                    label: localFound ? Translation.tr("Local models detected") : LocalModels.checkpoints.length > 0 ? Translation.tr("Downloaded checkpoints detected") : Translation.tr("No local models")
                    detail: LocalModels.models.length > 0 && !LocalModels.runtimePath && !localReady ? Translation.tr("GGUF runtime unavailable") : localFound ? Translation.tr("%1 local model(s) available").arg(Math.max(1, root.dedupedLocalModelCount)) : LocalModels.checkpoints.length > 0 ? Translation.tr("Choose a GGUF export for local chat") : Translation.tr("Start Ollama or LM Studio to chat privately without an account or key")
                }

                StatusTile {
                    statusIcon: AiProviderCatalog.refreshing ? "sync" : "cloud_sync"
                    ok: AiProviderCatalog.availableModelCount > 0
                    label: AiProviderCatalog.refreshing ? Translation.tr("Refreshing live model catalogs…") : Translation.tr("%1 live model(s) discovered").arg(AiProviderCatalog.availableModelCount)
                    detail: Translation.tr("%1 free · %2 local · %3 connected · %4 browseable").arg(AiProviderCatalog.freeModelCount).arg(root.dedupedLocalModelCount).arg(AiProviderCatalog.healthyProviderCount).arg(AiProviderCatalog.browseableProviderCount)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    text: Translation.tr("Choose local, free online or connected models; availability is discovered automatically.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }

                RippleButton {
                    objectName: "aiRefreshModelCatalogsButton"
                    implicitWidth: 30
                    implicitHeight: 30
                    enabled: !AiProviderCatalog.refreshing && !(companionAiSection.item?.companionRefreshingModels ?? false)
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: {
                        AiProviderCatalog.refreshAll();
                        LocalModels.refresh();
                        if (typeof Ai.refreshLocalModels === "function")
                            Ai.refreshLocalModels();
                        if (typeof companionAiSection.item?.refreshCompanionModels === "function")
                            companionAiSection.item.refreshCompanionModels();
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "refresh"
                        iconSize: 16
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledToolTip {
                        text: Translation.tr("Refresh model catalogs & auto-detect available models")
                    }
                }
            }

            SettingsDivider {}

            GridLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                columns: getStartedSection.width > 640 ? 2 : 1
                uniformCellWidths: false
                columnSpacing: 10
                rowSpacing: 6

                ContentSubsection {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    title: Translation.tr("Voice dictation backend")
                    tooltip: Translation.tr("The same backend is used for chat dictation and voice web search. Keys are passed through the process environment and never written to commands or config files.")

                    ConfigSelectionArray {
                        enableSettingsSearch: false
                        currentValue: Config.options?.voiceSearch?.provider ?? "auto"
                        onSelected: newValue => Config.setNestedValue("voiceSearch.provider", newValue)
                        options: [
                            {
                                displayName: Translation.tr("Auto"),
                                icon: "auto_awesome",
                                value: "auto"
                            },
                            {
                                displayName: Translation.tr("Local Whisper"),
                                icon: "shield_lock",
                                value: "local"
                            },
                            {
                                displayName: "Groq",
                                icon: "bolt",
                                value: "groq"
                            },
                            {
                                displayName: "Gemini",
                                icon: "auto_awesome",
                                value: "gemini"
                            },
                            {
                                displayName: "OpenAI",
                                icon: "neurology",
                                value: "openai"
                            }
                        ]
                    }
                }

                ConfigSpinBox {
                    id: voiceDurationSpin
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignBottom
                    property bool _ready: false
                    Component.onCompleted: _ready = true

                    icon: "timer"
                    text: Translation.tr("Max recording length (s)")
                    value: Config.options?.voiceSearch?.duration ?? 5
                    from: 3
                    to: 60
                    stepSize: 1
                    onValueChanged: {
                        if (voiceDurationSpin._ready)
                            Config.setNestedValue("voiceSearch.duration", value);
                    }
                }
            }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.twoColBento
                    ? Math.max(0, root.topBentoRowHeight - root.getStartedNaturalHeight)
                    : 0
                visible: Layout.preferredHeight > 0
            }
        }
    }

    component StatusTile: Rectangle {
        id: statusTile
        property string statusIcon: ""
        property bool ok: false
        property string label: ""
        property string detail: ""
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.minimumWidth: 0
        implicitHeight: 44
        radius: 10
        color: Appearance.colors.colLayer2

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            MaterialSymbol {
                text: statusTile.statusIcon
                iconSize: 18
                color: statusTile.ok ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                Layout.alignment: Qt.AlignVCenter
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                clip: true
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    text: statusTile.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    visible: statusTile.detail.length > 0
                    text: statusTile.detail
                    font.pixelSize: Appearance.font.pixelSize.smallest - 1
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
            MaterialSymbol {
                text: statusTile.ok ? "check_circle" : "radio_button_unchecked"
                iconSize: 16
                color: statusTile.ok ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    // ── 2. Companion AI Card (Top-Right Bento) ───────────────────────────────
    SettingsCardSection {
        id: companionAiHostCard
        bentoColumn: "right"
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        settingsTaskSection: "setup"
        visible: AlisCompanion.available && AlisCompanion.settingsSource.length > 0
        expanded: true
        icon: "chat"
        title: Translation.tr("Companion")

        SettingsGroup {
            spacing: 4

            Loader {
                id: companionAiSection
                objectName: "companionAiEmbeddedSection"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                Layout.preferredHeight: item?.implicitHeight ?? 0
                visible: active
                active: AlisCompanion.available && AlisCompanion.settingsSource.length > 0
                onActiveChanged: {
                    if (active && AlisCompanion.settingsSource.length > 0) {
                        setSource(AlisCompanion.settingsSource, {
                            embedded: true,
                            activeSection: "ai"
                        });
                    } else {
                        source = "";
                    }
                }
                Component.onCompleted: {
                    if (active && status === Loader.Null && AlisCompanion.settingsSource.length > 0) {
                        setSource(AlisCompanion.settingsSource, {
                            embedded: true,
                            activeSection: "ai"
                        });
                    }
                }
                Connections {
                    target: AlisCompanion
                    function onSettingsSourceChanged(): void {
                        if (companionAiSection.active && AlisCompanion.settingsSource.length > 0) {
                            companionAiSection.setSource(AlisCompanion.settingsSource, {
                                embedded: true,
                                activeSection: "ai"
                            });
                        }
                    }
                }
                Binding {
                    target: companionAiSection.item
                    property: "embedded"
                    value: true
                    when: !!companionAiSection.item
                }
                Binding {
                    target: companionAiSection.item
                    property: "activeSection"
                    value: "ai"
                    when: !!companionAiSection.item
                }
                Binding {
                    target: companionAiSection.item
                    property: "targetEmbeddedHeight"
                    value: root.twoColBento
                        ? Math.max(160, root.topBentoRowHeight - companionAiHostCard.chromeImplicitHeight - SettingsMaterialPreset.groupPadding * 2)
                        : 0
                    when: !!companionAiSection.item
                }
            }
        }
    }

    SettingsCardSection {
        id: toolModeFallbackCard
        bentoColumn: "right"
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "setup"
        visible: !AlisCompanion.available
        expanded: true
        icon: "service_toolbox"
        title: Translation.tr("Tool Mode & Safety")

        SettingsGroup {
            spacing: 0

            ContentSubsection {
                id: toolModeContentSubsection
                title: Translation.tr("Default tool mode")
                tooltip: Translation.tr("What the assistant is allowed to do.")

                ConfigSelectionArray {
                    enableSettingsSearch: false
                    currentValue: Config.options?.ai?.tool ?? "search"
                    onSelected: newValue => {
                        Config.setNestedValue("ai.tool", newValue);
                    }
                    options: [
                        {
                            displayName: Translation.tr("Shell tools"),
                            icon: "service_toolbox",
                            value: "functions"
                        },
                        {
                            displayName: Translation.tr("Search"),
                            icon: "search",
                            value: "search"
                        },
                        {
                            displayName: Translation.tr("Advanced"),
                            icon: "terminal",
                            value: "advanced"
                        },
                        {
                            displayName: Translation.tr("None"),
                            icon: "block",
                            value: "none"
                        }
                    ]
                }

                SettingsNote {
                    icon: "service_toolbox"
                    text: Config.options?.ai?.tool === "advanced" ? Translation.tr("Advanced also exposes raw shell commands. Every command still requires approval.") : Translation.tr("Shell configuration changes show a typed preview and require approval. Search appears only when the selected provider supports it.")
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.twoColBento
                    ? Math.max(0, root.topBentoRowHeight - root.toolModeNaturalHeight)
                    : 0
                visible: Layout.preferredHeight > 0
            }
        }
    }

    // ── 3. Prompt & Rules Card (Bottom-Right Bento) ───────────────────────────
    SettingsCardSection {
        id: promptRulesContainerCard
        bentoColumn: "right"
        _consumesBentoExtraHeight: true
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        settingsTaskSection: "setup"
        visible: true
        expanded: true
        icon: "psychology"
        title: Translation.tr("Prompt & Rules")

        readonly property real promptTextBoxHeight: {
            const avail = root.bottomBentoRowHeight
                - promptRulesContainerCard.chromeImplicitHeight
                - SettingsMaterialPreset.groupPadding * 2
                - promptHeaderRow.implicitHeight
                - promptFooterHint.implicitHeight
                - 8;
            return Math.max(72, promptAndRulesGrid.columns > 1 ? avail : Math.floor((avail - 10) / 2));
        }

        SettingsGroup {
            spacing: 6

            GridLayout {
                id: promptAndRulesGrid
                objectName: "aiPromptAndRulesGrid"
                Layout.fillWidth: true
                columns: width > 360 ? 2 : 1
                uniformCellWidths: columns > 1
                columnSpacing: 10
                rowSpacing: 8

                // LEFT HALF: System Prompt
                ColumnLayout {
                    id: systemPromptCard
                    objectName: "aiSystemPromptCard"
                    Layout.alignment: Qt.AlignTop
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 4

                    RowLayout {
                        id: promptHeaderRow
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: "psychology"
                            iconSize: 15
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: Translation.tr("System Prompt")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                        RippleButton {
                            objectName: "aiSystemPromptResetButton"
                            implicitWidth: resetSysPromptRow.implicitWidth + 12
                            implicitHeight: 24
                            buttonRadius: Appearance.rounding.small
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            onClicked: {
                                systemPromptSaveTimer.stop();
                                systemPromptTextArea._suppressNextTextChange = true;
                                try {
                                    if (root.companionActive && typeof companionAiSection.item?.resetCompanionSystemPrompt === "function") {
                                        companionAiSection.item.resetCompanionSystemPrompt();
                                        if (Persistent.states?.ai) {
                                            Persistent.states.ai.companionSystemPrompt = "";
                                        }
                                        Config.setNestedValue("ai.systemPrompt", "");
                                        systemPromptTextArea.text = String(companionAiSection.item?.companionSystemPrompt ?? root.defaultCompanionSystemPromptFallback);
                                    } else {
                                        if (Persistent.states?.ai) {
                                            Persistent.states.ai.companionSystemPrompt = "";
                                        }
                                        Config.setNestedValue("ai.systemPrompt", "");
                                        systemPromptTextArea.text = root.defaultCompanionSystemPromptFallback;
                                    }
                                } finally {
                                    systemPromptTextArea._suppressNextTextChange = false;
                                }
                                systemPromptSaveTimer.stop();
                            }
                            contentItem: Item {
                                implicitWidth: resetSysPromptRow.implicitWidth
                                implicitHeight: resetSysPromptRow.implicitHeight
                                Row {
                                    id: resetSysPromptRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "restart_alt"
                                        iconSize: 13
                                        color: Appearance.colors.colPrimary
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: "Reset"
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colPrimary
                                    }
                                }
                            }
                            StyledToolTip {
                                text: "Reset System Prompt to Companion default"
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: promptRulesContainerCard.promptTextBoxHeight
                        implicitHeight: promptRulesContainerCard.promptTextBoxHeight
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2
                        border.width: 1
                        border.color: systemPromptTextArea.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                        clip: true

                        Flickable {
                            id: systemPromptFlickable
                            objectName: "aiSystemPromptFlickable"
                            anchors.fill: parent
                            anchors.margins: 2
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            flickableDirection: Flickable.VerticalFlick
                            contentWidth: width
                            contentHeight: Math.max(height, systemPromptTextArea.implicitHeight)
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff; visible: false; width: 0 }
                            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOff; visible: false; height: 0 }

                            MaterialTextArea {
                                id: systemPromptTextArea
                                objectName: "aiSystemPromptTextArea"
                                width: systemPromptFlickable.width
                                height: Math.max(systemPromptFlickable.height, implicitHeight)
                                background: null
                                placeholderText: Translation.tr("System prompt")
                                wrapMode: TextEdit.Wrap
                                property bool _suppressNextTextChange: false
                                readonly property string upstreamPrompt: root.companionActive ? String(companionAiSection.item?.companionSystemPrompt ?? root.defaultCompanionSystemPromptFallback) : ((Persistent.states?.ai?.companionSystemPrompt ?? "").trim().length > 0 ? String(Persistent.states.ai.companionSystemPrompt) : root.defaultCompanionSystemPromptFallback)
                                text: upstreamPrompt
                                function flushSystemPromptSave(): void {
                                    const normalized = (text.trim().length === 0 || text.trim() === root.defaultCompanionSystemPromptFallback.trim()) ? "" : text;
                                    if (root.companionActive && typeof companionAiSection.item?.setCompanionSystemPrompt === "function") {
                                        companionAiSection.item.setCompanionSystemPrompt(text, true);
                                    } else if (Persistent.states?.ai) {
                                        Persistent.states.ai.companionSystemPrompt = normalized;
                                    }
                                    Config.setNestedValue("ai.systemPrompt", normalized);
                                }
                                Timer {
                                    id: systemPromptSaveTimer
                                    interval: 400
                                    repeat: false
                                    onTriggered: systemPromptTextArea.flushSystemPromptSave()
                                }
                                onUpstreamPromptChanged: {
                                    if (!activeFocus && text !== upstreamPrompt) {
                                        text = upstreamPrompt;
                                    }
                                }
                                onActiveFocusChanged: {
                                    if (!activeFocus && systemPromptSaveTimer.running) {
                                        systemPromptSaveTimer.stop();
                                        flushSystemPromptSave();
                                    }
                                }
                                onEditingFinished: {
                                    if (systemPromptSaveTimer.running) {
                                        systemPromptSaveTimer.stop();
                                        flushSystemPromptSave();
                                    }
                                }
                                Component.onDestruction: {
                                    if (systemPromptSaveTimer.running) {
                                        systemPromptSaveTimer.stop();
                                        flushSystemPromptSave();
                                    }
                                }
                                onCursorRectangleChanged: {
                                    const r = cursorRectangle;
                                    if (r.y < systemPromptFlickable.contentY) {
                                        systemPromptFlickable.contentY = r.y;
                                    } else if (r.y + r.height > systemPromptFlickable.contentY + systemPromptFlickable.height) {
                                        systemPromptFlickable.contentY = r.y + r.height - systemPromptFlickable.height;
                                    }
                                }
                                onTextChanged: {
                                    if (_suppressNextTextChange)
                                        return;
                                    if (!activeFocus && text === upstreamPrompt)
                                        return;
                                    if (!activeFocus) {
                                        Qt.callLater(() => systemPromptTextArea.flushSystemPromptSave());
                                        return;
                                    }
                                    if (root.companionActive && typeof companionAiSection.item?.setCompanionSystemPrompt === "function") {
                                        companionAiSection.item.setCompanionSystemPrompt(text, false);
                                    }
                                    systemPromptSaveTimer.restart();
                                }
                            }
                        }
                    }

                    StyledText {
                        id: promptFooterHint
                        Layout.fillWidth: true
                        text: "{DISTRO} · {DE} · {DATETIME} · {WINDOWCLASS}"
                        font.pixelSize: Appearance.font.pixelSize.smallest - 1
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }

                // RIGHT HALF: Rules
                ColumnLayout {
                    id: companionRulesCard
                    objectName: "aiCompanionRulesCard"
                    Layout.alignment: Qt.AlignTop
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: "gavel"
                            iconSize: 15
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: "Rules"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                        RippleButton {
                            objectName: "aiCompanionRulesResetButton"
                            implicitWidth: resetRulesRow.implicitWidth + 12
                            implicitHeight: 24
                            buttonRadius: Appearance.rounding.small
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            onClicked: {
                                companionRulesSaveTimer.stop();
                                companionRulesTextArea._suppressNextTextChange = true;
                                try {
                                    if (root.companionActive && typeof companionAiSection.item?.resetCompanionRulesText === "function") {
                                        companionAiSection.item.resetCompanionRulesText();
                                        if (Persistent.states?.ai) {
                                            Persistent.states.ai.companionRulesText = "";
                                        }
                                        companionRulesTextArea.text = String(companionAiSection.item?.defaultCompanionRulesText ?? root.defaultCompanionRulesFallback);
                                    } else {
                                        if (Persistent.states?.ai) {
                                            Persistent.states.ai.companionRulesText = "";
                                        }
                                        companionRulesTextArea.text = root.defaultCompanionRulesFallback;
                                    }
                                } finally {
                                    companionRulesTextArea._suppressNextTextChange = false;
                                }
                                companionRulesSaveTimer.stop();
                            }
                            contentItem: Item {
                                implicitWidth: resetRulesRow.implicitWidth
                                implicitHeight: resetRulesRow.implicitHeight
                                Row {
                                    id: resetRulesRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "restart_alt"
                                        iconSize: 13
                                        color: Appearance.colors.colPrimary
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: "Reset"
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colPrimary
                                    }
                                }
                            }
                            StyledToolTip {
                                text: "Reset Rules to default grounded rules"
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: promptRulesContainerCard.promptTextBoxHeight
                        implicitHeight: promptRulesContainerCard.promptTextBoxHeight
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2
                        border.width: 1
                        border.color: companionRulesTextArea.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                        clip: true

                        Flickable {
                            id: companionRulesFlickable
                            objectName: "aiCompanionRulesFlickable"
                            anchors.fill: parent
                            anchors.margins: 2
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            flickableDirection: Flickable.VerticalFlick
                            contentWidth: width
                            contentHeight: Math.max(height, companionRulesTextArea.implicitHeight)
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff; visible: false; width: 0 }
                            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOff; visible: false; height: 0 }

                            MaterialTextArea {
                                id: companionRulesTextArea
                                objectName: "aiCompanionRulesTextArea"
                                width: companionRulesFlickable.width
                                height: Math.max(companionRulesFlickable.height, implicitHeight)
                                background: null
                                placeholderText: "- Ground every claim in real tool output..."
                                wrapMode: TextEdit.Wrap
                                property bool _suppressNextTextChange: false
                                readonly property string upstreamRules: root.companionActive ? String(companionAiSection.item?.companionRulesText ?? root.defaultCompanionRulesFallback) : ((Persistent.states?.ai?.companionRulesText ?? "").trim().length > 0 ? String(Persistent.states.ai.companionRulesText) : root.defaultCompanionRulesFallback)
                                text: upstreamRules
                                function flushCompanionRulesSave(): void {
                                    const normalized = (text.trim().length === 0 || text.trim() === root.defaultCompanionRulesFallback.trim()) ? "" : text;
                                    if (root.companionActive && typeof companionAiSection.item?.setCompanionRulesText === "function") {
                                        companionAiSection.item.setCompanionRulesText(text, true);
                                    } else if (Persistent.states?.ai) {
                                        Persistent.states.ai.companionRulesText = normalized;
                                    }
                                }
                                Timer {
                                    id: companionRulesSaveTimer
                                    interval: 400
                                    repeat: false
                                    onTriggered: companionRulesTextArea.flushCompanionRulesSave()
                                }
                                onUpstreamRulesChanged: {
                                    if (!activeFocus && text !== upstreamRules) {
                                        text = upstreamRules;
                                    }
                                }
                                onActiveFocusChanged: {
                                    if (!activeFocus && companionRulesSaveTimer.running) {
                                        companionRulesSaveTimer.stop();
                                        flushCompanionRulesSave();
                                    }
                                }
                                onEditingFinished: {
                                    if (companionRulesSaveTimer.running) {
                                        companionRulesSaveTimer.stop();
                                        flushCompanionRulesSave();
                                    }
                                }
                                Component.onDestruction: {
                                    if (companionRulesSaveTimer.running) {
                                        companionRulesSaveTimer.stop();
                                        flushCompanionRulesSave();
                                    }
                                }
                                onCursorRectangleChanged: {
                                    const r = cursorRectangle;
                                    if (r.y < companionRulesFlickable.contentY) {
                                        companionRulesFlickable.contentY = r.y;
                                    } else if (r.y + r.height > companionRulesFlickable.contentY + companionRulesFlickable.height) {
                                        companionRulesFlickable.contentY = r.y + r.height - companionRulesFlickable.height;
                                    }
                                }
                                onTextChanged: {
                                    if (_suppressNextTextChange)
                                        return;
                                    if (!activeFocus && text === upstreamRules)
                                        return;
                                    if (!activeFocus) {
                                        Qt.callLater(() => companionRulesTextArea.flushCompanionRulesSave());
                                        return;
                                    }
                                    if (root.companionActive && typeof companionAiSection.item?.setCompanionRulesText === "function") {
                                        companionAiSection.item.setCompanionRulesText(text, false);
                                    }
                                    companionRulesSaveTimer.restart();
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "Synced · /rule <instruction> or /rule reset"
                        font.pixelSize: Appearance.font.pixelSize.smallest - 1
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ── 4. Providers & models (Bottom-Left Bento with internal scroll) ───────
    SettingsCardSection {
        id: providersAndModelsCard
        objectName: "aiProvidersAndModelsSection"
        bentoColumn: "left"
        _consumesBentoExtraHeight: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        settingsTaskSection: "setup"
        visible: true
        expanded: true
        icon: "cloud"
        title: Translation.tr("Providers & models")

        readonly property real providersListHeight: Math.max(110,
            root.bottomBentoRowHeight
            - providersAndModelsCard.chromeImplicitHeight
            - SettingsMaterialPreset.groupPadding * 2
            - providersHeaderRow.implicitHeight
            - providersDescText.implicitHeight
            - 12)

        SettingsGroup {
            spacing: 6

            RowLayout {
                id: providersHeaderRow
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("AI Providers")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }

                RippleButton {
                    implicitWidth: addProviderBtnRow.implicitWidth + 16
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.small
                    colBackground: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
                    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.80)
                    onClicked: {
                        providerForm.editingIndex = -1;
                        providerForm.titleText = Translation.tr("Add custom endpoint");
                        providerForm.saveLabelText = Translation.tr("Add");
                        providerNameInput.text = "";
                        providerEndpointInput.text = "";
                        providerForm.selectedFormat = "openai";
                        providerForm._manualOverride = false;
                        providerForm._presetId = "";
                        providerForm._presetKeyId = "";
                        providerModelInput.text = "";
                        providerApiKeyInput.text = "";
                        providerForm.expanded = true;
                        Qt.callLater(() => {
                            if (providersFlickable)
                                providersFlickable.contentY = Math.max(0, providersFlickable.contentHeight - providersFlickable.height);
                        });
                    }

                    contentItem: Item {
                        implicitWidth: addProviderBtnRow.implicitWidth
                        implicitHeight: addProviderBtnRow.implicitHeight
                        Row {
                            id: addProviderBtnRow
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "add"
                                iconSize: 16
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                verticalAlignment: Text.AlignVCenter
                                text: Translation.tr("Custom endpoint")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }
            }

            StyledText {
                id: providersDescText
                Layout.fillWidth: true
                Layout.leftMargin: 4
                text: Translation.tr("Models and API protocol are discovered from the selected provider.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }

            Flickable {
                id: providersFlickable
                Layout.fillWidth: true
                Layout.preferredHeight: providersAndModelsCard.providersListHeight
                implicitHeight: providersAndModelsCard.providersListHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                contentWidth: width
                contentHeight: providersScrollCol.implicitHeight
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff; visible: false; width: 0 }
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOff; visible: false; height: 0 }

                ColumnLayout {
                    id: providersScrollCol
                    width: providersFlickable.width
                    spacing: 8

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        columns: width >= 440 ? 2 : 1
                        uniformCellWidths: columns > 1
                        columnSpacing: 8
                        rowSpacing: 6

                        Repeater {
                            model: AiProviderPresets.presets

                            delegate: RippleButton {
                                id: providerCard
                                required property var modelData
                                readonly property var preset: providerCard.modelData
                                readonly property var providerState: AiProviderCatalog.stateFor(preset.id)
                                readonly property var discoveredModels: AiProviderCatalog.modelsFor(preset.id)
                                readonly property bool configured: (Config.options?.ai?.extraModels ?? []).some(m => (m?.provider_id ?? "") === preset.id || (m?.endpoint ?? "") === preset.endpoint)
                                readonly property bool connected: providerState.status === "ready"
                                readonly property string statusText: {
                                    if (providerState.status === "loading")
                                        return Translation.tr("Refreshing catalog…");
                                    if (providerState.status === "ready")
                                        return Translation.tr("Key stored · %1 models").arg(providerState.modelCount);
                                    if (providerState.status === "catalog-ready")
                                        return Translation.tr("%1 models visible · connect to use").arg(providerState.modelCount);
                                    if (providerState.status === "needs-key")
                                        return Translation.tr("API key required");
                                    if (providerState.status === "unavailable")
                                        return preset.local ? Translation.tr("Service not running") : Translation.tr("Provider unavailable");
                                    return preset.local ? Translation.tr("Detect local service") : Translation.tr("Connect provider");
                                }

                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.minimumWidth: 0
                                Layout.preferredHeight: 54
                                clip: true
                                buttonRadius: Appearance.rounding.normal
                                colBackground: connected ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.91) : Appearance.colors.colLayer2
                        colBackgroundHover: connected ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84) : Appearance.colors.colLayer2Hover

                        onClicked: {
                            providerForm.editingIndex = -1;
                            providerForm.titleText = connected ? Translation.tr("Update %1").arg(preset.name) : Translation.tr("Connect %1").arg(preset.name);
                            providerForm.saveLabelText = connected ? Translation.tr("Update") : Translation.tr("Connect");
                            providerNameInput.text = preset.name;
                            providerEndpointInput.text = preset.endpoint;
                            providerModelInput.text = providerCard.discoveredModels[0]?.remoteId ?? preset.model;
                            providerForm.selectedFormat = preset.api_format ?? "openai";
                            providerForm._manualOverride = true;
                            providerForm._presetId = preset.id ?? "";
                            providerForm._presetKeyId = preset.keyId ?? "";
                            providerApiKeyInput.text = "";
                            providerForm.expanded = true;
                        }

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10

                            Loader {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                readonly property string iconName: String(providerCard.preset.icon ?? "neurology")
                                readonly property color iconColor: providerCard.connected ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                                sourceComponent: iconName.endsWith("-symbolic") && iconName !== "anthropic-symbolic" ? providerThemeIcon : providerMaterialIcon

                                Component {
                                    id: providerThemeIcon
                                    CustomIcon {
                                        source: parent.iconName
                                        colorize: true
                                        color: parent.iconColor
                                    }
                                }
                                Component {
                                    id: providerMaterialIcon
                                    MaterialSymbol {
                                        text: parent.iconName === "anthropic-symbolic" ? "psychology" : parent.iconName
                                        iconSize: 24
                                        color: parent.iconColor
                                    }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.preferredWidth: 1
                                clip: true
                                spacing: 2
                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: providerCard.preset.name
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer2
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: providerCard.statusText
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: providerCard.connected ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }
                            MaterialSymbol {
                                Layout.fillWidth: false
                                text: providerCard.providerState.status === "loading" ? "sync" : providerCard.connected ? "check_circle" : providerCard.providerState.status === "catalog-ready" ? "lock" : providerCard.preset.local ? "computer" : "arrow_forward"
                                iconSize: Appearance.font.pixelSize.large
                                color: providerCard.connected ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }
                        }

                        StyledToolTip {
                            text: Translation.tr(providerCard.preset.description)
                        }
                    }
                }
            }

            Repeater {
                model: Config.options?.ai?.extraModels ?? []

                delegate: Item {
                    id: providerItem
                    required property var modelData
                    required property int index
                    readonly property string providerId: modelData?.provider_id ?? "custom"
                    readonly property var preset: AiProviderPresets.byId(providerId)
                    readonly property var providerState: AiProviderCatalog.stateFor(providerId)
                    readonly property bool guided: preset !== null
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitHeight: providerRow.implicitHeight + 12

                    Rectangle {
                        anchors.fill: parent
                        clip: true
                        radius: Appearance.rounding.small
                        color: providerMA.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                            }
                        }

                        RowLayout {
                            id: providerRow
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 10

                            MaterialSymbol {
                                Layout.fillWidth: false
                                readonly property var formatIcons: ({
                                        "openai": "smart_toy",
                                        "gemini": "auto_awesome",
                                        "mistral": "smart_toy",
                                        "anthropic": "psychology",
                                        "openai-response": "bolt"
                                    })
                                text: formatIcons[providerItem.modelData?.api_format] ?? "smart_toy"
                                iconSize: 20
                                color: Appearance.colors.colTertiary
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.preferredWidth: 1
                                clip: true
                                spacing: 1

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: providerItem.preset?.name ?? providerItem.modelData?.name ?? providerItem.modelData?.model ?? Translation.tr("Unnamed")
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnLayer1
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: providerItem.guided ? (providerItem.providerState.status === "ready" ? Translation.tr("Key stored · %1 live models").arg(providerItem.providerState.modelCount) : providerItem.providerState.status === "catalog-ready" ? Translation.tr("Catalog available · API key required") : Translation.tr("Connection needs attention")) : (providerItem.modelData?.model ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideMiddle
                                    maximumLineCount: 1
                                }
                            }

                            Rectangle {
                                visible: !providerItem.guided
                                width: visible ? fmtLabel.implicitWidth + 12 : 0
                                height: 22
                                radius: Appearance.rounding.full
                                color: ColorUtils.transparentize(Appearance.colors.colTertiary, 0.88)

                                readonly property var formatLabels: ({
                                        "openai": "OpenAI",
                                        "gemini": "Gemini",
                                        "mistral": "Mistral",
                                        "anthropic": "Anthropic",
                                        "openai-response": "Responses"
                                    })

                                StyledText {
                                    id: fmtLabel
                                    anchors.centerIn: parent
                                    text: parent.formatLabels[providerItem.modelData?.api_format] ?? providerItem.modelData?.api_format ?? "OpenAI"
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colTertiary
                                }
                            }

                            RippleButton {
                                implicitWidth: 28
                                implicitHeight: 28
                                buttonRadius: 14
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer1Hover
                                onClicked: {
                                    const m = providerItem.modelData;
                                    const preset = providerItem.preset;
                                    const liveModels = preset ? AiProviderCatalog.modelsFor(preset.id) : [];
                                    providerForm.editingIndex = providerItem.index;
                                    providerForm.titleText = preset ? Translation.tr("Update %1").arg(preset.name) : Translation.tr("Edit AI Provider");
                                    providerForm.saveLabelText = Translation.tr("Save");
                                    providerNameInput.text = preset?.name ?? m?.name ?? "";
                                    providerEndpointInput.text = preset?.endpoint ?? m?.endpoint ?? "";
                                    providerForm.selectedFormat = preset?.api_format ?? m?.api_format ?? "openai";
                                    providerForm._manualOverride = true;
                                    providerForm._presetId = m?.provider_id ?? "";
                                    providerForm._presetKeyId = preset?.keyId ?? m?.key_id ?? "";
                                    providerModelInput.text = liveModels[0]?.remoteId ?? preset?.model ?? m?.model ?? "";
                                    providerApiKeyInput.text = "";
                                    providerForm.expanded = true;
                                }

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "edit"
                                    iconSize: 14
                                    color: Appearance.colors.colSubtext
                                }

                                StyledToolTip {
                                    text: Translation.tr("Edit")
                                }
                            }

                            RippleButton {
                                implicitWidth: 28
                                implicitHeight: 28
                                buttonRadius: 14
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer1Hover
                                onClicked: {
                                    let models = [...(Config.options?.ai?.extraModels ?? [])];
                                    models.splice(providerItem.index, 1);
                                    Config.setNestedValue("ai.extraModels", models);
                                }

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: 14
                                    color: Appearance.colors.colSubtext
                                }

                                StyledToolTip {
                                    text: Translation.tr("Remove")
                                }
                            }
                        }

                        MouseArea {
                            id: providerMA
                            anchors.fill: parent
                            z: -1
                            hoverEnabled: true
                        }
                    }
                }
            }

            ColumnLayout {
                visible: (Config.options?.ai?.extraModels ?? []).length === 0
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.bottomMargin: 8
                spacing: 4

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "neurology"
                    iconSize: 28
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No custom providers")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Add a custom endpoint only if the provider is unsupported.")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                }
            }

            Rectangle {
                id: providerForm
                Layout.fillWidth: true
                Layout.topMargin: 4

                property bool expanded: false
                onExpandedChanged: {
                    if (expanded) {
                        Qt.callLater(() => {
                            if (providersFlickable)
                                providersFlickable.contentY = Math.max(0, providersFlickable.contentHeight - providersFlickable.height);
                        });
                    }
                }
                property int editingIndex: -1
                property string titleText: Translation.tr("Add AI Provider")
                property string saveLabelText: Translation.tr("Add")
                property string selectedFormat: "openai"
                property bool _manualOverride: false
                property string _presetId: ""
                readonly property var _preset: AiProviderPresets.byId(_presetId)
                readonly property bool _guidedPreset: _preset !== null
                readonly property bool _hasStoredPresetKey: _preset?.keyId ? ((KeyringStorage.keyringData?.apiKeys?.[_preset.keyId]?.length ?? 0) > 0) : false
                // Set from preset.keyId on quick-add so the keyring lookup key
                // doesn't drift from what scripts like gemini-translate.sh expect
                // (e.g. "gemini") when the model text differs from the id/text slug.
                property string _presetKeyId: ""

                implicitHeight: expanded ? aiAddFormCol.implicitHeight + 24 : 0
                visible: expanded
                clip: true
                radius: Appearance.rounding.small
                color: Appearance.colors.colSurfaceContainerLow
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                Behavior on implicitHeight {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                ColumnLayout {
                    id: aiAddFormCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    StyledText {
                        text: providerForm.titleText
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }

                    SettingsNote {
                        visible: providerForm._guidedPreset
                        icon: providerForm._preset?.local ? "computer" : "cloud_sync"
                        text: providerForm._preset ? Translation.tr(providerForm._preset.description) + "\n\n" + Translation.tr("Alis will discover the available model IDs and capabilities automatically.") : ""
                    }

                    ColumnLayout {
                        visible: !providerForm._guidedPreset
                        spacing: 4
                        Layout.fillWidth: true

                        StyledText {
                            text: Translation.tr("Provider name")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }

                        MaterialTextField {
                            id: providerNameInput
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("e.g. My Claude Proxy")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurface
                            placeholderTextColor: Appearance.colors.colSubtext
                            background: Rectangle {
                                color: Appearance.colors.colLayer1
                                radius: Appearance.rounding.small
                                border.width: providerNameInput.activeFocus ? 2 : 1
                                border.color: providerNameInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                            }
                        }
                    }

                    ColumnLayout {
                        visible: !providerForm._guidedPreset
                        spacing: 4
                        Layout.fillWidth: true

                        StyledText {
                            text: Translation.tr("API endpoint URL")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }

                        MaterialTextField {
                            id: providerEndpointInput
                            Layout.fillWidth: true
                            placeholderText: "https://api.openai.com/v1/chat/completions"
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurface
                            placeholderTextColor: Appearance.colors.colSubtext
                            background: Rectangle {
                                color: Appearance.colors.colLayer1
                                radius: Appearance.rounding.small
                                border.width: providerEndpointInput.activeFocus ? 2 : 1
                                border.color: providerEndpointInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                            }

                            onTextChanged: {
                                if (providerForm._manualOverride)
                                    return;
                                const url = text.toLowerCase();
                                if (url.includes("generativelanguage.googleapis.com")) {
                                    providerForm.selectedFormat = "gemini";
                                } else if (url.includes("api.anthropic.com") || url.includes("/v1/messages")) {
                                    providerForm.selectedFormat = "anthropic";
                                } else if (url.includes("api.openai.com") || url.includes("/v1/chat/completions")) {
                                    providerForm.selectedFormat = "openai";
                                }
                            }
                        }
                    }

                    ContentSubsection {
                        visible: !providerForm._guidedPreset
                        title: Translation.tr("API format")

                        ConfigSelectionArray {
                            enableSettingsSearch: false
                            options: [
                                {
                                    displayName: "OpenAI",
                                    icon: "smart_toy",
                                    value: "openai"
                                },
                                {
                                    displayName: "Gemini",
                                    icon: "auto_awesome",
                                    value: "gemini"
                                },
                                {
                                    displayName: "Anthropic",
                                    icon: "psychology",
                                    value: "anthropic"
                                },
                                {
                                    displayName: Translation.tr("Responses API"),
                                    icon: "bolt",
                                    value: "openai-response"
                                }
                            ]
                            currentValue: providerForm.selectedFormat
                            onSelected: newValue => {
                                providerForm.selectedFormat = newValue;
                                providerForm._manualOverride = true;
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: providerForm.selectedFormat === "openai"
                            text: Translation.tr("OpenAI-compatible: OpenAI, Mistral, Ollama, OpenRouter, vLLM.")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.WordWrap
                        }
                    }

                    ColumnLayout {
                        visible: !providerForm._guidedPreset
                        spacing: 4
                        Layout.fillWidth: true

                        StyledText {
                            text: Translation.tr("Model code")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }

                        MaterialTextField {
                            id: providerModelInput
                            Layout.fillWidth: true
                            placeholderText: "gpt-4.1"
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurface
                            placeholderTextColor: Appearance.colors.colSubtext
                            background: Rectangle {
                                color: Appearance.colors.colLayer1
                                radius: Appearance.rounding.small
                                border.width: providerModelInput.activeFocus ? 2 : 1
                                border.color: providerModelInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                            }
                        }
                    }

                    ColumnLayout {
                        spacing: 4
                        Layout.fillWidth: true

                        StyledText {
                            text: providerForm._preset?.requiresKey ? Translation.tr("API key") : Translation.tr("API key (optional)")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }

                        MaterialTextField {
                            id: providerApiKeyInput
                            Layout.fillWidth: true
                            placeholderText: providerForm._hasStoredPresetKey ? Translation.tr("A key is already stored — leave blank to keep it") : "sk-..."
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurface
                            placeholderTextColor: Appearance.colors.colSubtext
                            echoMode: TextInput.Password
                            background: Rectangle {
                                color: Appearance.colors.colLayer1
                                radius: Appearance.rounding.small
                                border.width: providerApiKeyInput.activeFocus ? 2 : 1
                                border.color: providerApiKeyInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Item {
                            Layout.fillWidth: true
                        }

                        RippleButton {
                            implicitWidth: cancelProviderLabel.implicitWidth + 24
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.small
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer1Hover
                            onClicked: {
                                providerForm.expanded = false;
                                providerForm.editingIndex = -1;
                                providerNameInput.text = "";
                                providerEndpointInput.text = "";
                                providerForm.selectedFormat = "openai";
                                providerForm._manualOverride = false;
                                providerForm._presetId = "";
                                providerForm._presetKeyId = "";
                                providerModelInput.text = "";
                                providerApiKeyInput.text = "";
                            }

                            contentItem: StyledText {
                                id: cancelProviderLabel
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: Translation.tr("Cancel")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                            }
                        }

                        RippleButton {
                            implicitWidth: saveProviderLabel.implicitWidth + 24
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.small
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            enabled: providerEndpointInput.text.trim() !== "" && providerModelInput.text.trim() !== "" && (!(providerForm._preset?.requiresKey ?? false) || providerApiKeyInput.text.trim().length > 0 || providerForm._hasStoredPresetKey)
                            opacity: enabled ? 1 : 0.5
                            onClicked: {
                                const modelCode = providerModelInput.text.trim();
                                const apiKey = providerApiKeyInput.text.trim();
                                const preset = providerForm._preset;
                                const keyId = providerForm._presetKeyId || modelCode.toLowerCase().replace(/[:\/ ]/g, "-");

                                const entry = {
                                    name: providerNameInput.text.trim() || modelCode,
                                    endpoint: providerEndpointInput.text.trim(),
                                    model: modelCode,
                                    api_format: providerForm.selectedFormat,
                                    requires_key: preset ? !!preset.requiresKey : apiKey.length > 0,
                                    key_id: keyId,
                                    provider_id: providerForm._presetId || "custom",
                                    auth_scheme: preset?.authScheme ?? "strategy",
                                    description: preset ? Translation.tr(preset.description) : "",
                                    icon: preset?.icon ?? "neurology",
                                    key_get_link: preset?.keyGetLink ?? ""
                                };

                                let models = [...(Config.options?.ai?.extraModels ?? [])];
                                if (preset) {
                                    // Curated providers are key + live catalog records.
                                    // Remove any legacy hardcoded model row.
                                    const filtered = models.filter(model => (model?.provider_id ?? "") !== preset.id);
                                    if (filtered.length !== models.length)
                                        Config.setNestedValue("ai.extraModels", filtered);
                                } else {
                                    if (providerForm.editingIndex >= 0) {
                                        const orig = models[providerForm.editingIndex];
                                        if (orig) {
                                            for (let k in orig) {
                                                if (!(k in entry) && k !== "index")
                                                    entry[k] = orig[k];
                                            }
                                        }
                                        models[providerForm.editingIndex] = entry;
                                    } else {
                                        models.push(entry);
                                    }
                                    Config.setNestedValue("ai.extraModels", models);
                                }

                                if (apiKey.length > 0) {
                                    KeyringStorage.setNestedField(["apiKeys", keyId], apiKey);
                                }
                                if (providerForm._presetId.length > 0)
                                    Qt.callLater(() => AiProviderCatalog.refreshProvider(providerForm._presetId));

                                providerForm.expanded = false;
                                providerForm.editingIndex = -1;
                                providerNameInput.text = "";
                                providerEndpointInput.text = "";
                                providerForm.selectedFormat = "openai";
                                providerForm._manualOverride = false;
                                providerForm._presetId = "";
                                providerForm._presetKeyId = "";
                                providerModelInput.text = "";
                                providerApiKeyInput.text = "";
                            }

                            contentItem: StyledText {
                                id: saveProviderLabel
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: providerForm.saveLabelText
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
            }
                }
            }
        }
    }
}
