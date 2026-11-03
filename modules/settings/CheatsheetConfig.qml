import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.services.deferred
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings

ContentPage {
    id: root
    settingsPageIndex: 9
    settingsPageName: Translation.tr("Shortcuts")

    // ── Data sources ────────────────────────────────────────────────────────
    readonly property var keybinds: CompositorService.isNiri ? NiriKeybinds.keybinds : HyprlandKeybinds.keybinds
    readonly property var categories: keybinds?.children ?? []
    readonly property bool hasEnrichedData: CompositorService.isNiri && NiriKeybinds.enrichedCategories.length > 0
    readonly property bool canEdit: CompositorService.isNiri

    property var keySubstitutions: ({
        "Mod": "󰖳", "Super": "󰖳", "Slash": "/", "Return": "↵", "Escape": "Esc",
        "Comma": ",", "Period": ".", "BracketLeft": "[", "BracketRight": "]",
        "Left": "←", "Right": "→", "Up": "↑", "Down": "↓",
        "Page_Up": "PgUp", "Page_Down": "PgDn", "Home": "Home", "End": "End"
    })

    // ── Status feedback state ────────────────────────────────────────────────
    property string _statusMsg: ""
    property string _statusType: ""   // "saved" | "removed" | "error"
    property bool _statusVisible: false
    property var expandedRows: ({})

    readonly property var defaultRoleShortcuts: [
        { slotId: "terminal", title: Translation.tr("Default Terminal"), icon: "terminal" },
        { slotId: "browser", title: Translation.tr("Default Web Browser"), icon: "language" },
        { slotId: "fileManager", title: Translation.tr("Default File Manager"), icon: "folder_open" },
        { slotId: "editor", title: Translation.tr("Default Code / Text Editor"), icon: "code" }
    ]

    readonly property var quickSystemActions: [
        { label: Translation.tr("App Launcher (Spotlight)"), icon: "apps", action: 'spawn "qs" "-c" "alis" "ipc" "call" "search" "toggle"' },
        { label: Translation.tr("Open Settings"), icon: "settings", action: 'spawn "qs" "-c" "alis" "ipc" "call" "settings" "open"' },
        { label: Translation.tr("Region Screenshot"), icon: "screenshot_region", action: 'spawn "qs" "-c" "alis" "ipc" "call" "region" "screenshot"' },
        { label: Translation.tr("Full Screen Screenshot"), icon: "photo_camera", action: "screenshot-screen" },
        { label: Translation.tr("Region OCR"), icon: "document_scanner", action: 'spawn "qs" "-c" "alis" "ipc" "call" "region" "ocr"' },
        { label: Translation.tr("Clipboard History"), icon: "content_paste", action: 'spawn "qs" "-c" "alis" "ipc" "call" "clipboard" "toggle"' },
        { label: Translation.tr("Toggle Overview"), icon: "grid_view", action: "toggle-overview" },
        { label: Translation.tr("Close Focused Window"), icon: "close", action: "close-window" },
        { label: Translation.tr("Maximize Column"), icon: "fullscreen", action: "maximize-column" },
        { label: Translation.tr("Fullscreen Window"), icon: "aspect_ratio", action: "fullscreen-window" },
        { label: Translation.tr("Toggle Floating"), icon: "picture_in_picture_alt", action: "toggle-window-floating" },
        { label: Translation.tr("Lock Screen"), icon: "lock", action: 'spawn "qs" "-c" "alis" "ipc" "call" "lock" "activate"' }
    ]

    Component.onCompleted: {
        if (!AppLauncher.discoveryLoaded && !AppLauncher.discoveryLoading)
            AppLauncher.refreshDiscovery()
        root._consumePendingShortcut()
    }

    function _consumePendingShortcut(): void {
        const pendingAct = String(AppLauncher.pendingShortcutAction ?? "").trim()
        if (!pendingAct)
            return
        addActionBuilder.actionText = pendingAct
        addActionBuilder.pickerMode = "app"
        const label = String(AppLauncher.pendingShortcutLabel ?? "").trim()
        root._statusMsg = label
            ? (Translation.tr("Selected application for shortcut: ") + label + " — " + Translation.tr("enter a key combination below."))
            : Translation.tr("Action pre-filled — enter a key combination below.")
        root._statusType = "saved"
        root._statusVisible = true
        AppLauncher.clearPendingShortcut()
        Qt.callLater(() => {
            addKeyComboField.forceActiveFocus()
        })
    }

    Connections {
        target: AppLauncher
        function onPendingShortcutActionChanged() {
            root._consumePendingShortcut()
        }
    }

    function toggleRowExpanded(rowIndex: int, nextExpanded: bool): void {
        if ((root.expandedRows[rowIndex] === true) === nextExpanded)
            return
        const next = Object.assign({}, root.expandedRows)
        next[rowIndex] = nextExpanded
        root.expandedRows = next
    }

    readonly property var balancedEnrichedCategories: {
        const rawCats = root.hasEnrichedData ? (NiriKeybinds.enrichedCategories ?? []) : []
        const allBinds = NiriKeybinds.allBinds ?? []
        if (rawCats.length === 0)
            return []

        const byName = {}
        const order = []
        function ensureBucket(name) {
            if (!byName[name]) {
                byName[name] = []
                order.push(name)
            }
            return byName[name]
        }

        for (let i = 0; i < rawCats.length; i++) {
            const cat = rawCats[i]
            const name = String(cat?.name ?? "Other")
            const indices = Array.isArray(cat?.binds) ? cat.binds.slice() : []
            if (name === "Window Switcher" || name === "System") {
                ensureBucket("System & Session").push(...indices)
            } else if (name === "Layout" || name === "Resize") {
                ensureBucket("Layout & Resize").push(...indices)
            } else if (name === "Media" || name === "Brightness" || name === "Other") {
                ensureBucket("Media & Brightness").push(...indices)
            } else if (name === "Screenshots" || name === "Region Tools") {
                ensureBucket("Screenshots").push(...indices)
            } else if (name === "Workspaces" && indices.length > 14) {
                const numbered = []
                const nav = []
                for (let k = 0; k < indices.length; k++) {
                    const idx = indices[k]
                    const combo = String(allBinds[idx]?.key_combo ?? "")
                    if (/(?:^|\+)[1-9]$/.test(combo))
                        numbered.push(idx)
                    else
                        nav.push(idx)
                }
                if (numbered.length > 0 && nav.length > 0) {
                    ensureBucket("Workspaces").push(...numbered)
                    ensureBucket("Workspace Navigation").push(...nav)
                } else {
                    ensureBucket(name).push(...indices)
                }
            } else {
                ensureBucket(name).push(...indices)
            }
        }

        // Balance Alis Shell & System & Session when System & Session is short
        const shellName = byName["Alis Shell"] ? "Alis Shell" : (byName["ii Shell"] ? "ii Shell" : "")
        if (shellName && byName["System & Session"] && byName[shellName].length >= 10 && byName["System & Session"].length < 7) {
            const shellKept = []
            const sysBucket = byName["System & Session"]
            for (let i = 0; i < byName[shellName].length; i++) {
                const idx = byName[shellName][i]
                const b = allBinds[idx] ?? {}
                const combo = String(b.key_combo ?? "")
                const desc = String(b.description ?? b.action ?? "").toLowerCase()
                if ((desc.includes("lock") || desc.includes("session") || desc.includes("power") || combo === "Mod+Alt+L" || combo === "Mod+Shift+Q")
                        && sysBucket.length < 8) {
                    sysBucket.push(idx)
                } else {
                    shellKept.push(idx)
                }
            }
            byName[shellName] = shellKept
        }

        let groups = order
            .map(name => ({ name: name, binds: byName[name] }))
            .filter(g => g.binds.length > 0)

        // If odd number of groups, merge the two smallest groups so 2-column rows stay paired
        if (groups.length > 2 && (groups.length % 2 === 1)) {
            groups.sort((a, b) => a.binds.length - b.binds.length)
            const first = groups.shift()
            const second = groups.shift()
            groups.push({
                name: first.name + " · " + second.name,
                binds: first.binds.concat(second.binds)
            })
        }

        // Sort by item count so adjacent (Left, Right) pairs on each row have matching height
        groups.sort((a, b) => b.binds.length - a.binds.length)
        return groups
    }

    readonly property var balancedLegacyCategories: {
        const rawCats = root.categories ?? []
        if (rawCats.length === 0)
            return []

        const byName = {}
        const order = []
        function ensureBucket(name) {
            if (!byName[name]) {
                byName[name] = []
                order.push(name)
            }
            return byName[name]
        }

        for (let i = 0; i < rawCats.length; i++) {
            const cat = rawCats[i]
            const name = String(cat?.name ?? "Other")
            const items = cat?.children?.[0]?.keybinds ?? []
            if (name === "Window Switcher" || name === "System") {
                ensureBucket("System & Session").push(...items)
            } else if (name === "Layout" || name === "Resize") {
                ensureBucket("Layout & Resize").push(...items)
            } else if (name === "Media" || name === "Brightness" || name === "Other") {
                ensureBucket("Media & Brightness").push(...items)
            } else if (name === "Screenshots" || name === "Region Tools") {
                ensureBucket("Screenshots").push(...items)
            } else if (name === "Monitors" || name === "Workspaces") {
                ensureBucket("Workspaces & Monitors").push(...items)
            } else {
                ensureBucket(name).push(...items)
            }
        }

        let groups = order
            .map(name => ({ name: name, children: [{ keybinds: byName[name] }] }))
            .filter(g => g.children[0].keybinds.length > 0)

        if (groups.length > 2 && (groups.length % 2 === 1)) {
            groups.sort((a, b) => a.children[0].keybinds.length - b.children[0].keybinds.length)
            const first = groups.shift()
            const second = groups.shift()
            groups.push({
                name: first.name + " · " + second.name,
                children: [{ keybinds: first.children[0].keybinds.concat(second.children[0].keybinds) }]
            })
        }

        groups.sort((a, b) => b.children[0].keybinds.length - a.children[0].keybinds.length)
        return groups
    }

    SettingsTaskNavigator {
        showTabBar: false
        icon: "keyboard"
        title: Translation.tr("Shortcuts")
        description: CompositorService.isNiri && NiriKeybinds.loaded
            ? NiriKeybinds.configPath
            : Translation.tr("Keyboard shortcuts and compositor keybinds.")
        summary: Translation.tr("Keybinds · categories · custom shortcuts")
        currentValue: "shortcuts"
        options: [
            { displayName: Translation.tr("Shortcuts"), icon: "keyboard", value: "shortcuts" }
        ]
    }

    Connections {
        target: NiriKeybinds
        function onBindSaved(keyCombo) {
            root._statusMsg = Translation.tr("Saved: ") + keyCombo
            root._statusType = "saved"
            root._statusVisible = true
            statusHideTimer.restart()
        }
        function onBindRemoved(keyCombo) {
            root._statusMsg = Translation.tr("Removed: ") + keyCombo
            root._statusType = "removed"
            root._statusVisible = true
            statusHideTimer.restart()
        }
        function onBindError(message) {
            root._statusMsg = message
            root._statusType = "error"
            root._statusVisible = true
            statusHideTimer.stop()
        }
    }

    Timer {
        id: statusHideTimer
        interval: 3000
        repeat: false
        onTriggered: root._statusVisible = false
    }

    // ── Feedback bar ─────────────────────────────────────────────────────────
    Rectangle {
        visible: root._statusVisible
        Layout.fillWidth: true
        implicitHeight: statusBarRow.implicitHeight + 16
        radius: Appearance.rounding.small
        color: root._statusType === "error"
            ? ColorUtils.transparentize(Appearance.colors.colError, 0.82)
            : root._statusType === "removed"
            ? ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 0.7)
            : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)
        border.width: 1
        border.color: root._statusType === "error"
            ? ColorUtils.transparentize(Appearance.colors.colError, 0.45)
            : root._statusType === "removed"
            ? ColorUtils.transparentize(Appearance.colors.colSubtext, 0.55)
            : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45)

        RowLayout {
            id: statusBarRow
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 12
                rightMargin: 8
            }
            spacing: 8

            MaterialSymbol {
                text: root._statusType === "error" ? "error"
                    : root._statusType === "removed" ? "do_not_disturb_on"
                    : "check_circle"
                iconSize: Appearance.font.pixelSize.normal
                color: root._statusType === "error" ? Appearance.colors.colError
                    : root._statusType === "removed" ? Appearance.colors.colSubtext
                    : Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                text: root._statusMsg
                font.pixelSize: Appearance.font.pixelSize.small
                color: root._statusType === "error" ? Appearance.colors.colError
                    : root._statusType === "removed" ? Appearance.colors.colOnLayer1
                    : Appearance.colors.colPrimary
                wrapMode: Text.WordWrap
            }

            RippleButton {
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: Appearance.rounding.full
                releaseAction: () => { root._statusVisible = false }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    // ── Add keybind section ──────────────────────────────────────────────────
    SettingsCardSection {
        _preventBentoReparent: true
        visible: root.canEdit
        Layout.fillWidth: true
        expanded: true
        icon: "add_circle"
        title: Translation.tr("Add keybind")

        SettingsGroup {
            Layout.fillWidth: true

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        text: Translation.tr("Key combination")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    MaterialTextField {
                        id: addKeyComboField
                        Layout.fillWidth: true
                        placeholderText: "Mod+Tab"
                        enableSettingsSearch: false

                        readonly property string conflictDesc: {
                            const v = text.trim()
                            if (!v) return ""
                            const found = (NiriKeybinds.allBinds ?? []).find(b => b.key_combo === v && !b.commented)
                            return found ? (found.description ?? found.action ?? v) : ""
                        }
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignBottom
                    implicitWidth: 92
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.small
                    enabled: addKeyComboField.text.trim().length > 0 && addActionBuilder.actionText.trim().length > 0
                    colBackground: enabled ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    colBackgroundHover: enabled ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                    onClicked: {
                        const combo = addKeyComboField.text.trim()
                        const action = addActionBuilder.actionText.trim()
                        if (combo.length > 0 && action.length > 0) {
                            NiriKeybinds.setBind(combo, action, addActionBuilder.optionsText.trim())
                            addKeyComboField.text = ""
                            addActionBuilder.actionText = ""
                            addActionBuilder.optionsText = ""
                            addActionBuilder.pickerMode = "app"
                        }
                    }
                    contentItem: Item {
                        implicitWidth: addKeybindBtnRow.implicitWidth
                        implicitHeight: addKeybindBtnRow.implicitHeight
                        RowLayout {
                            id: addKeybindBtnRow
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "add"
                                iconSize: 18
                                color: parent.parent.parent.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                verticalAlignment: Text.AlignVCenter
                                text: Translation.tr("Add")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: parent.parent.parent.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                            }
                        }
                    }
                    StyledToolTip {
                        text: Translation.tr("Add keybind")
                    }
                }
            }

            StyledText {
                visible: addKeyComboField.conflictDesc !== ""
                text: "⚠ " + Translation.tr("Already bound to: ") + "\"" + addKeyComboField.conflictDesc + "\""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colError
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            ShortcutActionBuilder {
                id: addActionBuilder
                Layout.fillWidth: true
            }
        }
    }

    // ── Enriched categories (editor-capable) ────────────────────────────────
    GridLayout {
        visible: root.hasEnrichedData
        Layout.fillWidth: true
        columns: width >= 620 ? 2 : 1
        uniformCellWidths: columns === 2
        columnSpacing: 14
        rowSpacing: 14

        Repeater {
            model: root.balancedEnrichedCategories

            delegate: SettingsCardSection {
                required property var modelData
                required property int index
                _preventBentoReparent: true
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1

                readonly property string catName: modelData?.name ?? ""
                readonly property var bindIndices: modelData?.binds ?? []

                expanded: true

                icon: root.getCategoryIcon(catName)
                title: catName

                SettingsGroup {
                    Layout.fillWidth: true

                    Repeater {
                        id: enrichedBindRepeater
                        model: bindIndices

                        delegate: KeybindRow {
                            required property int modelData   // index into allBinds
                            required property int index
                            Layout.fillWidth: true

                            readonly property var bindData: NiriKeybinds.allBinds[modelData] ?? {}
                            readonly property var _parsed: root.parseComboParts(bindData.key_combo ?? "")

                            mods: _parsed.mods
                            keyName: _parsed.key
                            action: bindData.description ?? bindData.action ?? ""
                            showDivider: index < enrichedBindRepeater.count - 1
                            keyCombo: bindData.key_combo ?? ""
                            actionRaw: bindData.action ?? ""
                            optionsStr: bindData.options ?? ""
                            isCommented: bindData.commented ?? false
                            canEdit: root.canEdit
                            keySubstitutions: root.keySubstitutions
                        }
                    }
                }
            }
        }
    }

    // ── Legacy categories (read-only fallback) ───────────────────────────────
    GridLayout {
        visible: !root.hasEnrichedData
        Layout.fillWidth: true
        columns: width >= 620 ? 2 : 1
        uniformCellWidths: columns === 2
        columnSpacing: 14
        rowSpacing: 14

        Repeater {
            model: root.balancedLegacyCategories

            delegate: SettingsCardSection {
                required property var modelData
                required property int index
                _preventBentoReparent: true
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                expanded: true

                readonly property var categoryKeybinds: modelData.children?.[0]?.keybinds ?? []

                icon: root.getCategoryIcon(modelData.name)
                title: modelData.name

                SettingsGroup {
                    Layout.fillWidth: true

                    Repeater {
                        id: legacyBindRepeater
                        model: categoryKeybinds

                        delegate: KeybindRow {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            mods: modelData.mods ?? []
                            keyName: modelData.key ?? ""
                            action: modelData.comment ?? ""
                            showDivider: index < legacyBindRepeater.count - 1
                            keyCombo: ""
                            actionRaw: ""
                            optionsStr: ""
                            isCommented: false
                            canEdit: false
                            keySubstitutions: root.keySubstitutions
                        }
                    }
                }
            }
        }
    }

    Item { Layout.preferredHeight: 20 }

    // ── Functions ────────────────────────────────────────────────────────────

    function getCategoryIcon(name: string): string {
        const icons = {
            "System": "settings_power",
            "System & Session": "settings_power",
            "ii Shell": "auto_awesome",
            "Alis Shell": "auto_awesome",
            "Window Switcher": "swap_horiz",
            "Screenshots": "screenshot_region",
            "Applications": "apps",
            "Window Management": "web_asset",
            "Focus": "center_focus_strong",
            "Move Windows": "open_with",
            "Workspaces": "grid_view",
            "Workspace Navigation": "swap_vert",
            "Workspaces & Monitors": "grid_view",
            "Media": "volume_up",
            "Media & Brightness": "volume_up",
            "Brightness": "light_mode",
            "Layout": "dashboard_customize",
            "Layout & Resize": "dashboard_customize",
            "Resize": "photo_size_select_large",
            "Monitors": "monitor",
            "Region Tools": "screenshot_region",
            "Other": "more_horiz"
        }
        return icons[name] ?? "keyboard"
    }

    function parseComboParts(combo: string): var {
        if (!combo || combo.length === 0)
            return { mods: [], key: "" }
        const parts = combo.split("+")
        if (parts.length === 1)
            return { mods: [], key: parts[0] }
        return {
            mods: parts.slice(0, parts.length - 1),
            key: parts[parts.length - 1]
        }
    }

    // ── ShortcutAppIcon component ────────────────────────────────────────────
    component ShortcutAppIcon: Rectangle {
        id: sAppIcon
        property string iconName: ""
        property string fallbackSymbol: "apps"
        property real boxSize: 22

        implicitWidth: boxSize
        implicitHeight: boxSize
        radius: Appearance.rounding.small
        color: Appearance.colors.colSecondaryContainer

        readonly property string resolvedPath: {
            const raw = String(sAppIcon.iconName ?? "").trim()
            if (!raw)
                return ""
            if (raw.startsWith("file://"))
                return raw
            if (raw.startsWith("/"))
                return "file://" + raw
            return Quickshell.iconPath(raw, true)
        }

        IconImage {
            id: sIconImg
            anchors.centerIn: parent
            width: Math.max(14, sAppIcon.boxSize - 6)
            height: width
            source: sAppIcon.resolvedPath
            visible: status === Image.Ready && source.toString() !== ""
        }

        MaterialSymbol {
            anchors.centerIn: parent
            visible: !sIconImg.visible
            text: sAppIcon.fallbackSymbol
            iconSize: Math.max(13, sAppIcon.boxSize - 8)
            color: Appearance.colors.colOnSecondaryContainer
        }
    }

    // ── ShortcutActionBuilder component ──────────────────────────────────────
    component ShortcutActionBuilder: ColumnLayout {
        id: builder
        property alias actionText: rawActionInput.text
        property alias optionsText: rawOptionsInput.text
        property string pickerMode: "app"   // "app" | "quick" | "manual"
        property string appSearchQuery: ""

        spacing: 8

        readonly property var resolvedInfo: AppLauncher.resolveShortcutAppInfo(rawActionInput.text)
        readonly property var filteredApps: {
            const apps = AppLauncher.discoveredApps ?? []
            const q = builder.appSearchQuery.trim().toLowerCase()
            if (!q)
                return apps.slice(0, 40)
            const out = []
            for (let i = 0; i < apps.length; i++) {
                const a = apps[i]
                const hay = [a?.name, a?.genericName, a?.id, a?.exec, a?.command].join(" ").toLowerCase()
                if (hay.indexOf(q) !== -1) {
                    out.push(a)
                    if (out.length >= 40)
                        break
                }
            }
            return out
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                text: Translation.tr("Action")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            // Selected App pill (shows only App icon + App name)
            Rectangle {
                visible: builder.resolvedInfo !== null
                implicitHeight: 24
                implicitWidth: resolvedBadgeRow.implicitWidth + 14
                radius: Appearance.rounding.full
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.86)

                RowLayout {
                    id: resolvedBadgeRow
                    anchors.centerIn: parent
                    spacing: 5

                    ShortcutAppIcon {
                        boxSize: 16
                        iconName: builder.resolvedInfo?.iconName ?? ""
                        fallbackSymbol: builder.resolvedInfo?.fallbackSymbol ?? "apps"
                    }

                    StyledText {
                        text: builder.resolvedInfo?.displayLabel ?? builder.resolvedInfo?.name ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colPrimary
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Mode buttons: Choose App (default) | Quick Action | Manual command
            RippleButton {
                implicitHeight: 28
                implicitWidth: chooseAppBtnRow.implicitWidth + 16
                buttonRadius: Appearance.rounding.small
                colBackground: builder.pickerMode === "app"
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colLayer2
                colBackgroundHover: builder.pickerMode === "app"
                    ? Appearance.colors.colPrimaryHover
                    : Appearance.colors.colLayer2Hover
                onClicked: {
                    if (!AppLauncher.discoveryLoaded && !AppLauncher.discoveryLoading)
                        AppLauncher.refreshDiscovery()
                    builder.pickerMode = "app"
                }
                contentItem: Item {
                    implicitWidth: chooseAppBtnRow.implicitWidth
                    implicitHeight: chooseAppBtnRow.implicitHeight
                    RowLayout {
                        id: chooseAppBtnRow
                        anchors.centerIn: parent
                        spacing: 5
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "apps"
                            iconSize: 15
                            color: builder.pickerMode === "app" ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            verticalAlignment: Text.AlignVCenter
                            text: Translation.tr("Choose App")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: builder.pickerMode === "app" ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }
                    }
                }
            }

            RippleButton {
                implicitHeight: 28
                implicitWidth: quickActBtnRow.implicitWidth + 16
                buttonRadius: Appearance.rounding.small
                colBackground: builder.pickerMode === "quick"
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colLayer2
                colBackgroundHover: builder.pickerMode === "quick"
                    ? Appearance.colors.colPrimaryHover
                    : Appearance.colors.colLayer2Hover
                onClicked: {
                    builder.pickerMode = "quick"
                }
                contentItem: Item {
                    implicitWidth: quickActBtnRow.implicitWidth
                    implicitHeight: quickActBtnRow.implicitHeight
                    RowLayout {
                        id: quickActBtnRow
                        anchors.centerIn: parent
                        spacing: 5
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "bolt"
                            iconSize: 15
                            color: builder.pickerMode === "quick" ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            verticalAlignment: Text.AlignVCenter
                            text: Translation.tr("Quick Action")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: builder.pickerMode === "quick" ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }
                    }
                }
            }

            RippleButton {
                implicitHeight: 28
                implicitWidth: manualCmdBtnRow.implicitWidth + 16
                buttonRadius: Appearance.rounding.small
                colBackground: builder.pickerMode === "manual"
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colLayer2
                colBackgroundHover: builder.pickerMode === "manual"
                    ? Appearance.colors.colPrimaryHover
                    : Appearance.colors.colLayer2Hover
                onClicked: {
                    builder.pickerMode = "manual"
                    rawActionInput.forceActiveFocus()
                }
                contentItem: Item {
                    implicitWidth: manualCmdBtnRow.implicitWidth
                    implicitHeight: manualCmdBtnRow.implicitHeight
                    RowLayout {
                        id: manualCmdBtnRow
                        anchors.centerIn: parent
                        spacing: 5
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "terminal"
                            iconSize: 15
                            color: builder.pickerMode === "manual" ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            verticalAlignment: Text.AlignVCenter
                            text: Translation.tr("Manual command")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: builder.pickerMode === "manual" ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }
                    }
                }
            }
        }

        // ── Manual Command + Options Panel (only visible when Manual command is selected) ──
        RowLayout {
            visible: builder.pickerMode === "manual"
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 3
                spacing: 4

                StyledText {
                    text: Translation.tr("Command / Action")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                MaterialTextField {
                    id: rawActionInput
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("e.g. spawn \"kitty\" or toggle-overview")
                    enableSettingsSearch: false
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 2
                spacing: 4

                StyledText {
                    text: Translation.tr("Options (optional)")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                MaterialTextField {
                    id: rawOptionsInput
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("e.g. repeat=false")
                    enableSettingsSearch: false
                }
            }
        }

        // ── App Picker Panel (shown by default) ──────────────────────────────
        Rectangle {
            visible: builder.pickerMode === "app"
            Layout.fillWidth: true
            implicitHeight: appPickerCol.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            ColumnLayout {
                id: appPickerCol
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 10
                }
                spacing: 8

                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Search applications...")
                    text: builder.appSearchQuery
                    enableSettingsSearch: false
                    onTextChanged: builder.appSearchQuery = text
                }

                ListView {
                    id: appPickerList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(220, Math.max(52, contentHeight))
                    clip: true
                    spacing: 4
                    model: builder.filteredApps

                    ScrollBar.vertical: StyledScrollBar {}

                    delegate: RippleButton {
                        required property var modelData
                        width: appPickerList.width
                        implicitHeight: 38
                        buttonRadius: Appearance.rounding.small
                        readonly property string candidateAction: AppLauncher.niriSpawnActionForApp(modelData)
                        readonly property bool isSelected: rawActionInput.text.trim() === candidateAction

                        colBackground: isSelected
                            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84)
                            : Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: {
                            rawActionInput.text = candidateAction
                        }

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            ShortcutAppIcon {
                                boxSize: 22
                                iconName: modelData?.icon ?? ""
                                fallbackSymbol: "apps"
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData?.name ?? modelData?.id ?? ""
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: isSelected ? Font.DemiBold : Font.Normal
                                color: isSelected ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }

                            MaterialSymbol {
                                visible: isSelected
                                text: "check_circle"
                                iconSize: 16
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }
            }
        }

        // ── Quick System / Window Action Picker Panel ────────────────────────
        Rectangle {
            visible: builder.pickerMode === "quick"
            Layout.fillWidth: true
            implicitHeight: quickPickerFlow.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            Flow {
                id: quickPickerFlow
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 10
                }
                spacing: 6

                Repeater {
                    model: root.quickSystemActions
                    delegate: RippleButton {
                        required property var modelData
                        readonly property bool isCurrent: rawActionInput.text.trim() === modelData.action
                        implicitHeight: 30
                        implicitWidth: quickChipRow.implicitWidth + 16
                        buttonRadius: Appearance.rounding.small
                        colBackground: isCurrent
                            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                            : Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: {
                            rawActionInput.text = modelData.action
                        }

                        contentItem: Item {
                            implicitWidth: quickChipRow.implicitWidth
                            implicitHeight: quickChipRow.implicitHeight
                            RowLayout {
                                id: quickChipRow
                                anchors.centerIn: parent
                                spacing: 6

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: modelData.icon
                                    iconSize: 15
                                    color: isCurrent ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignVCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: modelData.label
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: isCurrent ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── KeyBadge component ───────────────────────────────────────────────────
    component KeyBadge: Rectangle {
        property string keyText: ""

        implicitWidth: Math.max(keyLabel.implicitWidth + 10, 26)
        implicitHeight: 22
        radius: Appearance.rounding.small
        color: Appearance.colors.colSurfaceContainerHigh ?? Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant ?? ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.85)

        StyledText {
            id: keyLabel
            anchors.centerIn: parent
            text: keyText
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.family: Appearance.font.family.monospace
            color: Appearance.colors.colOnLayer1
        }
    }

    // ── KeybindRow component ─────────────────────────────────────────────────
    component KeybindRow: Item {
        id: kbRow

        // Display properties
        property var mods: []
        property string keyName: ""
        property string action: ""
        property bool showDivider: true
        property bool isCommented: false

        // Edit properties (empty string = read-only / legacy mode)
        property string keyCombo: ""
        property string actionRaw: ""
        property string optionsStr: ""

        // Feature flags
        property bool canEdit: false
        property var keySubstitutions: ({})

        // State: "display" | "editing" | "confirmDelete"
        property string editState: "display"

        readonly property bool isExpanded: editState !== "display"
        readonly property var resolvedAppInfo: kbRow.actionRaw
            ? AppLauncher.resolveShortcutAppInfo(kbRow.actionRaw)
            : null

        // Drive outer height from inner column
        implicitHeight: kbMainColumn.implicitHeight

        clip: true

        // Hover background for display rows
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                bottom: parent.bottom
                bottomMargin: kbRow.showDivider ? 1 : 0
            }
            color: kbRowHover.hovered && kbRow.editState === "display"
                ? Appearance.colors.colLayer1Hover
                : "transparent"
            radius: Appearance.rounding.small

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                }
            }
        }

        HoverHandler {
            id: kbRowHover
        }

        ColumnLayout {
            id: kbMainColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 0

            // ── Display row ──────────────────────────────────────────────────
            RowLayout {
                id: kbDisplayRow
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                spacing: 12
                Layout.preferredHeight: 36

                // Key badges
                Row {
                    Layout.preferredWidth: 200
                    Layout.minimumWidth: 140
                    spacing: 4
                    opacity: kbRow.isCommented ? 0.4 : 1.0

                    Repeater {
                        model: kbRow.mods
                        delegate: KeyBadge {
                            required property var modelData
                            keyText: kbRow.keySubstitutions[modelData] ?? modelData
                        }
                    }

                    StyledText {
                        visible: kbRow.mods.length > 0 && kbRow.keyName.length > 0
                        text: "+"
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    KeyBadge {
                        visible: kbRow.keyName.length > 0
                        keyText: kbRow.keySubstitutions[kbRow.keyName] ?? kbRow.keyName
                    }
                }

                // Action description (shows App icon + App name when resolved)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    ShortcutAppIcon {
                        visible: kbRow.resolvedAppInfo !== null
                        boxSize: 20
                        iconName: kbRow.resolvedAppInfo?.iconName ?? ""
                        fallbackSymbol: kbRow.resolvedAppInfo?.fallbackSymbol ?? "apps"
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            const info = kbRow.resolvedAppInfo
                            const baseLabel = info
                                ? (info.displayLabel || info.name || kbRow.action)
                                : kbRow.action
                            return baseLabel + (kbRow.isCommented ? "  " + Translation.tr("(disabled)") : "")
                        }
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: kbRow.isCommented
                            ? Appearance.colors.colSubtext
                            : Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                }

                // Edit / delete icon buttons (enriched mode only, fade in on hover)
                Row {
                    visible: kbRow.canEdit && kbRow.editState === "display"
                    spacing: 2
                    opacity: kbRowHover.hovered ? 1.0 : 0.0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                        }
                    }

                    RippleButton {
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        releaseAction: () => { kbRow.editState = "editing" }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "edit"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }

                    RippleButton {
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        releaseAction: () => { kbRow.editState = "confirmDelete" }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "delete"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colError
                        }
                    }
                }
            }

            // ── Expand container (edit form + confirm delete) ────────────────
            Item {
                id: kbExpandContainer
                Layout.fillWidth: true
                implicitHeight: kbRow.isExpanded ? kbExpandInner.implicitHeight + 12 : 0
                clip: true

                Behavior on implicitHeight {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                ColumnLayout {
                    id: kbExpandInner
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        topMargin: 4
                        leftMargin: 8
                        rightMargin: 8
                    }
                    spacing: 0

                    // ── Edit form (Loader — instantiate only when active) ────
                    Loader {
                        id: editFormLoader
                        active: kbRow.editState === "editing"
                        visible: active
                        Layout.fillWidth: true

                        sourceComponent: Component {
                            ColumnLayout {
                                spacing: 8

                                // Key combo field
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    StyledText {
                                        text: Translation.tr("Key combination")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                    }

                                    MaterialTextField {
                                        id: editKeyField
                                        Layout.fillWidth: true
                                        text: kbRow.keyCombo
                                        placeholderText: "Mod+Tab"
                                        enableSettingsSearch: false

                                        readonly property string conflictDesc: {
                                            const v = text.trim()
                                            if (!v || v === kbRow.keyCombo) return ""
                                            const found = (NiriKeybinds.allBinds ?? []).find(
                                                b => b.key_combo === v && !b.commented
                                            )
                                            return found ? (found.description ?? found.action ?? v) : ""
                                        }
                                    }

                                    StyledText {
                                        visible: editKeyField.conflictDesc !== ""
                                        text: "⚠ " + Translation.tr("Already bound to: ") + "\"" + editKeyField.conflictDesc + "\""
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colError
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }

                                // Action builder (Choose App by default; Manual command hides/shows Command & Options)
                                ShortcutActionBuilder {
                                    id: editActionBuilder
                                    Layout.fillWidth: true
                                    Component.onCompleted: {
                                        actionText = kbRow.actionRaw
                                        optionsText = kbRow.optionsStr
                                        pickerMode = "app"
                                    }
                                }

                                // Save / Cancel
                                RowLayout {
                                    spacing: 8

                                    DialogButton {
                                        buttonText: Translation.tr("Save")
                                        releaseAction: () => {
                                            const combo = editKeyField.text.trim()
                                            const act = editActionBuilder.actionText.trim()
                                            if (combo.length > 0 && act.length > 0) {
                                                NiriKeybinds.setBind(combo, act, editActionBuilder.optionsText.trim(), kbRow.keyCombo)
                                                kbRow.editState = "display"
                                            }
                                        }
                                    }

                                    DialogButton {
                                        buttonText: Translation.tr("Cancel")
                                        releaseAction: () => { kbRow.editState = "display" }
                                    }
                                }
                            }
                        }
                    }

                    // ── Confirm delete ───────────────────────────────────────
                    Loader {
                        id: confirmDeleteLoader
                        active: kbRow.editState === "confirmDelete"
                        visible: active
                        Layout.fillWidth: true

                        sourceComponent: Component {
                            RowLayout {
                                spacing: 8
                                Layout.bottomMargin: 4

                                MaterialSymbol {
                                    text: "warning"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colError
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Remove keybind ") + kbRow.keyCombo + "?"
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                    wrapMode: Text.WordWrap
                                }

                                DialogButton {
                                    buttonText: Translation.tr("Remove")
                                    colText: Appearance.colors.colError
                                    releaseAction: () => {
                                        NiriKeybinds.removeBind(kbRow.keyCombo)
                                        kbRow.editState = "display"
                                    }
                                }

                                DialogButton {
                                    buttonText: Translation.tr("Cancel")
                                    releaseAction: () => { kbRow.editState = "display" }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Bottom divider
        Rectangle {
            visible: kbRow.showDivider
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            height: 1
            color: Appearance.colors.colOutlineVariant
            opacity: 0.3
        }
    }
}
