pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

Singleton {
    id: root

    property int _configRevision: 0
    property bool discoveryLoaded: false
    property bool discovering: false
    property var discoveredApps: []
    property var xdgDefaults: ({})
    property var toolsAvailable: ({ flatpak: false, xdgSettings: false, xdgMime: false })
    property var lastSyncMessage: ({})
    property var lastSyncError: ({})

    property string _discoverStdout: ""
    property string _syncStdout: ""
    property string _pendingSyncSlot: ""

    readonly property string _helperScript: Quickshell.shellPath("scripts/default_apps_helper.py")

    Connections {
        target: Config
        function onConfigChanged(): void { root._configRevision++ }
    }

    Component.onCompleted: {
        Qt.callLater(() => root.refreshDiscovery())
    }

    readonly property var _slotDefinitions: [
        {
            id: "terminal",
            group: "primary",
            icon: "terminal",
            label: Translation.tr("Terminal"),
            description: Translation.tr("Used by shell actions, keybinds (Mod+T / Mod+Return), package commands, and terminal-backed launchers."),
            defaultCommand: "kitty",
            placeholder: "kitty",
            supportsXdgSync: false,
            xdgTargetLabel: "",
            presets: [
                { id: "foot", label: "Foot", command: "foot", desktopId: "foot.desktop" },
                { id: "kitty", label: "Kitty", command: "kitty", desktopId: "kitty.desktop" },
                { id: "ghostty", label: "Ghostty", command: "ghostty", desktopId: "com.mitchellh.ghostty.desktop" },
                { id: "alacritty", label: "Alacritty", command: "alacritty", desktopId: "Alacritty.desktop" },
                { id: "wezterm", label: "WezTerm", command: "wezterm", desktopId: "org.wezfurlong.wezterm.desktop" },
                { id: "konsole", label: "Konsole", command: "konsole", desktopId: "org.kde.konsole.desktop" }
            ]
        },
        {
            id: "browser",
            group: "primary",
            icon: "language",
            label: Translation.tr("Web Browser"),
            description: Translation.tr("Used by Super+W, alis browser, web links, and browser launch tiles."),
            defaultCommand: "firefox",
            placeholder: "firefox",
            supportsXdgSync: true,
            xdgTargetLabel: "default-web-browser · http/https · text/html",
            presets: [
                { id: "firefox", label: "Firefox", command: "firefox", desktopId: "firefox.desktop" },
                { id: "zen", label: "Zen Browser", command: "zen-browser", desktopId: "zen.desktop" },
                { id: "librewolf", label: "LibreWolf", command: "librewolf", desktopId: "librewolf.desktop" },
                { id: "chromium", label: "Chromium", command: "chromium", desktopId: "chromium.desktop" },
                { id: "chrome", label: "Google Chrome", command: "google-chrome-stable", desktopId: "google-chrome.desktop" },
                { id: "brave", label: "Brave", command: "brave-browser", desktopId: "brave-browser.desktop" }
            ]
        },
        {
            id: "editor",
            group: "primary",
            icon: "code",
            label: Translation.tr("Code / Text Editor"),
            description: Translation.tr("Used by the Left Sidebar Editor tile and text/config editing actions."),
            defaultCommand: "code",
            placeholder: "code",
            supportsXdgSync: true,
            xdgTargetLabel: "text/plain",
            presets: [
                { id: "code", label: "Visual Studio Code", command: "code", desktopId: "code.desktop" },
                { id: "codium", label: "VSCodium", command: "codium", desktopId: "codium.desktop" },
                { id: "zed", label: "Zed", command: "zeditor", desktopId: "dev.zed.Zed.desktop" },
                { id: "kate", label: "Kate", command: "kate", desktopId: "org.kde.kate.desktop" },
                { id: "gnome-text-editor", label: "GNOME Text Editor", command: "gnome-text-editor", desktopId: "org.gnome.TextEditor.desktop" },
                { id: "gedit", label: "gedit", command: "gedit", desktopId: "org.gnome.gedit.desktop" }
            ]
        },
        {
            id: "fileManager",
            group: "primary",
            icon: "folder",
            label: Translation.tr("File Manager"),
            description: Translation.tr("Used by Super+E, Left Sidebar Files tile, and folder-open actions."),
            defaultCommand: "nautilus",
            placeholder: "nautilus",
            supportsXdgSync: true,
            xdgTargetLabel: "inode/directory",
            presets: [
                { id: "nautilus", label: "Files (Nautilus)", command: "nautilus", desktopId: "org.gnome.Nautilus.desktop" },
                { id: "dolphin", label: "Dolphin", command: "dolphin", desktopId: "org.kde.dolphin.desktop" },
                { id: "thunar", label: "Thunar", command: "thunar", desktopId: "thunar.desktop" },
                { id: "nemo", label: "Nemo", command: "nemo", desktopId: "nemo.desktop" },
                { id: "pcmanfm-qt", label: "PCManFM-Qt", command: "pcmanfm-qt", desktopId: "pcmanfm-qt.desktop" }
            ]
        },
        {
            id: "manageUser",
            group: "utility",
            icon: "person",
            label: Translation.tr("Manage my account"),
            description: Translation.tr("Used by the profile menu and start menu account shortcuts."),
            defaultCommand: "kcmshell6 kcm_users",
            placeholder: "kcmshell6 kcm_users",
            supportsXdgSync: false,
            xdgTargetLabel: "",
            presets: [
                { id: "kcm-users", label: "KDE Users", command: "kcmshell6 kcm_users", desktopId: "" },
                { id: "gnome-users", label: "GNOME Users", command: "gnome-control-center user-accounts", desktopId: "" },
                { id: "mate-users", label: "MATE Users", command: "mate-user-admin", desktopId: "" }
            ]
        },
        {
            id: "network",
            group: "utility",
            icon: "wifi",
            label: Translation.tr("Network manager (TUI)"),
            description: Translation.tr("Used by Wi-Fi details shortcuts when a text-mode network tool is preferred."),
            defaultCommand: "nm-connection-editor",
            placeholder: "kitty -1 fish -c nmtui",
            supportsXdgSync: false,
            xdgTargetLabel: "",
            presets: [
                { id: "nm-editor", label: "NetworkManager GUI", command: "nm-connection-editor", desktopId: "nm-connection-editor.desktop" },
                { id: "nmtui-kitty", label: "nmtui in Kitty", command: "kitty -1 fish -c nmtui", desktopId: "" },
                { id: "nmtui-foot", label: "nmtui in Foot", command: "foot -e nmtui", desktopId: "" },
                { id: "kcm-network", label: "KDE Network", command: "kcmshell6 kcm_networkmanagement", desktopId: "" }
            ]
        },
        {
            id: "networkEthernet",
            group: "utility",
            icon: "settings_ethernet",
            label: Translation.tr("Network settings (GUI)"),
            description: Translation.tr("Used by Ethernet-oriented settings shortcuts."),
            defaultCommand: "nm-connection-editor",
            placeholder: "kcmshell6 kcm_networkmanagement",
            supportsXdgSync: false,
            xdgTargetLabel: "",
            presets: [
                { id: "nm-editor", label: "NetworkManager GUI", command: "nm-connection-editor", desktopId: "nm-connection-editor.desktop" },
                { id: "kcm-network", label: "KDE Network", command: "kcmshell6 kcm_networkmanagement", desktopId: "" },
                { id: "gnome-network", label: "GNOME Network", command: "gnome-control-center network", desktopId: "" }
            ]
        },
        {
            id: "bluetooth",
            group: "utility",
            icon: "bluetooth",
            label: Translation.tr("Bluetooth settings"),
            description: Translation.tr("Used by Bluetooth toggles, dialogs, and action center shortcuts."),
            defaultCommand: "blueman-manager",
            placeholder: "kcmshell6 kcm_bluetooth",
            supportsXdgSync: false,
            xdgTargetLabel: "",
            presets: [
                { id: "blueman", label: "Blueman", command: "blueman-manager", desktopId: "blueman-manager.desktop" },
                { id: "kcm-bluetooth", label: "KDE Bluetooth", command: "kcmshell6 kcm_bluetooth", desktopId: "" },
                { id: "gnome-bluetooth", label: "GNOME Bluetooth", command: "gnome-control-center bluetooth", desktopId: "" }
            ]
        },
        {
            id: "volumeMixer",
            group: "utility",
            icon: "volume_up",
            label: Translation.tr("Volume mixer"),
            description: Translation.tr("Used by audio details buttons and quick launch surfaces."),
            defaultCommand: "pavucontrol",
            placeholder: "pavucontrol",
            supportsXdgSync: false,
            xdgTargetLabel: "",
            presets: [
                { id: "pavucontrol", label: "Pavucontrol", command: "pavucontrol", desktopId: "org.pulseaudio.pavucontrol.desktop" },
                { id: "pavucontrol-qt", label: "Pavucontrol Qt", command: "pavucontrol-qt", desktopId: "pavucontrol-qt.desktop" },
                { id: "helvum", label: "Helvum", command: "helvum", desktopId: "org.pipewire.Helvum.desktop" }
            ]
        },
        {
            id: "taskManager",
            group: "utility",
            icon: "monitoring",
            label: Translation.tr("Task manager"),
            description: Translation.tr("Used by the start menu, actions, and session tools."),
            defaultCommand: "missioncenter",
            placeholder: "missioncenter",
            supportsXdgSync: false,
            xdgTargetLabel: "",
            presets: [
                { id: "missioncenter", label: "Mission Center", command: "missioncenter", desktopId: "io.missioncenter.MissionCenter.desktop" },
                { id: "resources", label: "GNOME Resources", command: "resources", desktopId: "net.nokyan.Resources.desktop" },
                { id: "plasma-monitor", label: "KSysGuard", command: "plasma-systemmonitor", desktopId: "org.kde.plasma-systemmonitor.desktop" },
                { id: "btop", label: "btop", command: "kitty -e btop", desktopId: "btop.desktop" }
            ]
        }
    ]

    function slotDefinitions(): list<var> {
        return root._slotDefinitions
    }

    function primarySlotDefinitions(): list<var> {
        return root._slotDefinitions.filter(s => s.group === "primary")
    }

    function utilitySlotDefinitions(): list<var> {
        return root._slotDefinitions.filter(s => s.group === "utility")
    }

    function slotDefinition(slotId: string): var {
        if (slotId === "fileExplorer")
            slotId = "fileManager"
        return root._slotDefinitions.find(definition => definition.id === slotId) ?? null
    }

    function configuredCommand(slotId: string): string {
        const apps = Config.options?.apps ?? {}
        let rawValue = apps[slotId]
        if ((typeof rawValue !== "string" || rawValue.trim().length === 0) && slotId === "fileManager") {
            rawValue = apps["fileExplorer"]
        }
        return typeof rawValue === "string" ? rawValue.trim() : ""
    }

    function configuredDesktopId(slotId: string): string {
        const desktopIds = Config.options?.apps?.desktopIds ?? {}
        const raw = desktopIds[slotId]
        return typeof raw === "string" ? raw.trim() : ""
    }

    function defaultCommand(slotId: string): string {
        return String(root.slotDefinition(slotId)?.defaultCommand ?? "").trim()
    }

    function commandFor(slotId: string): string {
        const configured = root.configuredCommand(slotId)
        return configured.length > 0 ? configured : root.defaultCommand(slotId)
    }

    function refreshDiscovery(): void {
        if (discoverProc.running)
            return
        root._discoverStdout = ""
        root.discovering = true
        discoverProc.running = true
    }

    function _applyDiscoveryPayload(jsonText: string): void {
        try {
            const payload = JSON.parse(jsonText)
            if (payload && Array.isArray(payload.apps)) {
                root.discoveredApps = payload.apps
                root.xdgDefaults = payload.xdgDefaults ?? {}
                root.toolsAvailable = payload.toolsAvailable ?? { flatpak: false, xdgSettings: false, xdgMime: false }
                root.discoveryLoaded = true
                root._configRevision++
            }
        } catch (e) {
            console.warn("[AppLauncher] Failed to parse discovery output:", e)
        }
    }

    Process {
        id: discoverProc
        running: false
        command: ["/usr/bin/python3", root._helperScript, "discover"]
        stdout: StdioCollector {
            onStreamFinished: root._discoverStdout = this.text ?? ""
        }
        onExited: (exitCode, exitStatus) => {
            root.discovering = false
            if (exitCode === 0 && root._discoverStdout.trim().length > 0) {
                root._applyDiscoveryPayload(root._discoverStdout)
            }
        }
    }

    Process {
        id: syncXdgProc
        running: false
        property string targetSlot: ""
        property string targetDesktopId: ""
        command: ["/usr/bin/python3", root._helperScript, "apply-xdg", targetSlot, targetDesktopId]
        stdout: StdioCollector {
            onStreamFinished: root._syncStdout = this.text ?? ""
        }
        onExited: (exitCode, exitStatus) => {
            const slot = syncXdgProc.targetSlot
            let nextMsg = Object.assign({}, root.lastSyncMessage)
            let nextErr = Object.assign({}, root.lastSyncError)
            try {
                const res = JSON.parse(root._syncStdout)
                if (res.readback) {
                    let nextXdg = Object.assign({}, root.xdgDefaults)
                    nextXdg[slot] = res.readback
                    root.xdgDefaults = nextXdg
                }
                if (res.ok) {
                    nextMsg[slot] = res.message || Translation.tr("Synced with system default")
                    delete nextErr[slot]
                } else {
                    nextErr[slot] = res.error || Translation.tr("Failed to update system default")
                    delete nextMsg[slot]
                }
            } catch (e) {
                if (exitCode !== 0) {
                    nextErr[slot] = Translation.tr("System default update failed")
                    delete nextMsg[slot]
                }
            }
            root.lastSyncMessage = nextMsg
            root.lastSyncError = nextErr
            root._configRevision++
        }
    }

    function candidatesForSlot(slotId: string, searchQuery = "", showAllApps = false): list<var> {
        void(root._configRevision)
        const query = String(searchQuery ?? "").trim().toLowerCase()
        const all = root.discoveredApps ?? []
        const filtered = all.filter(app => {
            if (!app || !app.installed)
                return false
            if (!showAllApps) {
                const slots = app.slots ?? []
                if (slots.indexOf(slotId) === -1)
                    return false
            }
            if (query.length === 0)
                return true
            return String(app.name ?? "").toLowerCase().includes(query)
                || String(app.genericName ?? "").toLowerCase().includes(query)
                || String(app.desktopId ?? "").toLowerCase().includes(query)
                || String(app.appId ?? "").toLowerCase().includes(query)
                || String(app.exec ?? "").toLowerCase().includes(query)
                || String(app.sourceBadge ?? "").toLowerCase().includes(query)
        })
        return filtered
    }

    function findDiscoveredAppForSlot(slotId: string): var {
        void(root._configRevision)
        const idKey = root.configuredDesktopId(slotId)
        const cmd = root.commandFor(slotId)
        const all = root.discoveredApps ?? []

        if (idKey.length > 0) {
            const byKey = all.find(a => a.identityKey === idKey || a.desktopId === idKey)
            if (byKey)
                return byKey
        }
        if (cmd.length > 0) {
            const exact = all.find(a => a.exec === cmd || a.desktopId === cmd || (a.appId && a.appId === cmd))
            if (exact)
                return exact
            if (!cmd.includes(" ")) {
                const byBin = all.find(a => !a.isFlatpak && a.execBin === cmd)
                    ?? all.find(a => a.execBin === cmd)
                if (byBin)
                    return byBin
            }
        }
        return null
    }

    function selectedAppSummary(slotId: string): var {
        void(root._configRevision)
        const def = root.slotDefinition(slotId)
        const cmd = root.commandFor(slotId)
        const idKey = root.configuredDesktopId(slotId)
        const matched = root.findDiscoveredAppForSlot(slotId)

        if (matched) {
            return {
                name: matched.name,
                icon: matched.icon || (def?.icon ?? "apps"),
                sourceBadge: matched.sourceBadge || (matched.isFlatpak ? "Flatpak" : "Native"),
                desktopId: matched.desktopId || "",
                appId: matched.appId || "",
                identityKey: matched.identityKey || "",
                command: matched.exec || cmd,
                installed: true,
                isCustom: false,
                isFlatpak: Boolean(matched.isFlatpak),
                installation: matched.installation || "native",
                origin: matched.origin || ""
            }
        }

        const preset = (def?.presets ?? []).find(p => p.command === cmd)
        if (idKey.startsWith("flatpak:") || cmd.startsWith("flatpak run")) {
            const parts = idKey.split(":")
            const appId = parts.length >= 3 ? parts.slice(2).join(":") : cmd.replace(/^flatpak\s+run\s+(--user\s+|--system\s+)?/, "").trim()
            return {
                name: preset ? preset.label : (appId || cmd),
                icon: def?.icon ?? "apps",
                sourceBadge: root.discoveryLoaded ? Translation.tr("Flatpak · Unavailable") : "Flatpak",
                desktopId: appId ? `${appId}.desktop` : "",
                appId: appId,
                identityKey: idKey,
                command: cmd,
                installed: !root.discoveryLoaded,
                isCustom: false,
                isFlatpak: true,
                installation: parts.length >= 2 ? parts[1] : "system",
                origin: ""
            }
        }

        if (preset && idKey.length === 0) {
            return {
                name: preset.label,
                icon: def?.icon ?? "apps",
                sourceBadge: root.discoveryLoaded ? Translation.tr("Unavailable") : Translation.tr("Preset"),
                desktopId: preset.desktopId || "",
                appId: "",
                identityKey: "",
                command: cmd,
                installed: !root.discoveryLoaded,
                isCustom: false,
                isFlatpak: false,
                installation: "native",
                origin: ""
            }
        }

        return {
            name: cmd || (def?.label ?? slotId),
            icon: def?.icon ?? "terminal",
            sourceBadge: Translation.tr("Custom command"),
            desktopId: "",
            appId: "",
            identityKey: "",
            command: cmd,
            installed: cmd.length > 0,
            isCustom: true,
            isFlatpak: false,
            installation: "custom",
            origin: ""
        }
    }

    function selectDiscoveredApp(slotId: string, appObj: var): void {
        if (!appObj)
            return
        const targetSlot = slotId === "fileExplorer" ? "fileManager" : slotId
        const updates = {}
        const execCmd = String(appObj.exec ?? "").trim()
        const idKey = String(appObj.identityKey ?? appObj.desktopId ?? "").trim()
        updates[`apps.${targetSlot}`] = execCmd
        updates[`apps.desktopIds.${targetSlot}`] = idKey
        if (targetSlot === "fileManager") {
            updates["apps.fileExplorer"] = execCmd
        }
        Config.setNestedValues(updates)
        root._configRevision++
    }

    function xdgStatusFor(slotId: string): var {
        void(root._configRevision)
        const def = root.slotDefinition(slotId)
        if (!def || !def.supportsXdgSync) {
            return {
                supported: false,
                synced: false,
                canApply: false,
                currentDesktopId: "",
                selectedDesktopId: "",
                targetLabel: "",
                statusText: Translation.tr("Alis shell & keybind preference (no universal XDG MIME default)"),
                errorText: "",
                messageText: ""
            }
        }

        const summary = root.selectedAppSummary(slotId)
        const selectedDesktopId = String(summary?.desktopId ?? "").trim()
        const slotXdg = root.xdgDefaults?.[slotId] ?? {}
        const currentDesktopId = String(slotXdg.effectiveDesktopId ?? "").trim()
        const consistent = Boolean(slotXdg.consistent ?? (currentDesktopId.length > 0))
        const canApply = Boolean(summary?.installed && selectedDesktopId.length > 0 && selectedDesktopId.endsWith(".desktop"))
        const synced = Boolean(canApply && currentDesktopId === selectedDesktopId && consistent)

        let statusText = ""
        if (!root.discoveryLoaded) {
            statusText = Translation.tr("Checking system XDG association…")
        } else if (synced) {
            statusText = Translation.tr("System default matches (%1)").arg(currentDesktopId)
        } else if (currentDesktopId.length > 0) {
            if (!consistent) {
                statusText = Translation.tr("System MIME handlers differ (primary: %1)").arg(currentDesktopId)
            } else {
                statusText = Translation.tr("System default: %1").arg(currentDesktopId)
            }
        } else {
            statusText = Translation.tr("No system XDG default reported")
        }

        return {
            supported: true,
            synced: synced,
            canApply: canApply,
            currentDesktopId: currentDesktopId,
            selectedDesktopId: selectedDesktopId,
            targetLabel: def.xdgTargetLabel || "",
            statusText: statusText,
            errorText: String(root.lastSyncError?.[slotId] ?? ""),
            messageText: String(root.lastSyncMessage?.[slotId] ?? "")
        }
    }

    function syncSystemDefault(slotId: string): bool {
        const status = root.xdgStatusFor(slotId)
        if (!status.supported || !status.canApply) {
            let nextErr = Object.assign({}, root.lastSyncError)
            nextErr[slotId] = Translation.tr("System XDG default requires an installed .desktop application entry")
            root.lastSyncError = nextErr
            root._configRevision++
            return false
        }
        if (syncXdgProc.running)
            return false
        root._syncStdout = ""
        syncXdgProc.targetSlot = slotId
        syncXdgProc.targetDesktopId = status.selectedDesktopId
        syncXdgProc.running = true
        return true
    }

    function presetOptions(slotId: string): list<var> {
        const definition = root.slotDefinition(slotId)
        const options = (definition?.presets ?? []).map(preset => ({
            value: preset.id,
            displayName: preset.label
        }))

        options.push({
            value: "__custom__",
            displayName: Translation.tr("Custom command")
        })

        return options
    }

    function presetIdFor(slotId: string): string {
        const definition = root.slotDefinition(slotId)
        if (!definition)
            return "__custom__"

        const currentCommand = root.commandFor(slotId)
        const preset = (definition.presets ?? []).find(candidate => candidate.command === currentCommand)
        return preset?.id ?? "__custom__"
    }

    function applyPreset(slotId: string, presetId: string): void {
        const definition = root.slotDefinition(slotId)
        if (!definition)
            return

        const preset = (definition.presets ?? []).find(candidate => candidate.id === presetId)
        if (!preset)
            return

        const matched = (root.discoveredApps ?? []).find(a =>
            (preset.desktopId && a.desktopId === preset.desktopId)
            || a.exec === preset.command
            || (!a.isFlatpak && a.execBin === preset.command)
        )
        const updates = {}
        updates[`apps.${definition.id}`] = matched ? matched.exec : preset.command
        updates[`apps.desktopIds.${definition.id}`] = matched ? matched.identityKey : (preset.desktopId ? `native:${preset.desktopId}` : "")
        if (definition.id === "fileManager") {
            updates["apps.fileExplorer"] = matched ? matched.exec : preset.command
        }
        Config.setNestedValues(updates)

        if (definition.id === "browser") {
            const desktopFile = matched?.desktopId || preset.desktopId || ""
            if (desktopFile) {
                Quickshell.execDetached(["xdg-settings", "set", "default-web-browser", desktopFile])
            }
        }
        root._configRevision++
    }

    function setCustomCommand(slotId: string, command: string): void {
        const targetSlot = slotId === "fileExplorer" ? "fileManager" : slotId
        const trimmed = String(command ?? "").trim()
        const updates = {}
        updates[`apps.${targetSlot}`] = trimmed
        updates[`apps.desktopIds.${targetSlot}`] = ""
        if (targetSlot === "fileManager") {
            updates["apps.fileExplorer"] = trimmed
        }
        Config.setNestedValues(updates)
        root._configRevision++
    }

    function launch(slotId: string, extraArgs = []): void {
        const targetSlot = slotId === "fileExplorer" ? "fileManager" : slotId
        const matched = root.findDiscoveredAppForSlot(targetSlot)
        const argsList = Array.isArray(extraArgs) ? extraArgs : (extraArgs ? [String(extraArgs)] : [])

        if (matched && argsList.length === 0 && !matched.isFlatpak && matched.desktopId) {
            const stem = matched.desktopId.endsWith(".desktop") ? matched.desktopId.slice(0, -8) : matched.desktopId
            const entry = DesktopEntries.byId(stem) ?? DesktopEntries.heuristicLookup(stem)
            if (entry) {
                AppSearch.launchEntry(entry)
                return
            }
        }

        if (matched && matched.isFlatpak && matched.appId) {
            const fpArgs = ["flatpak", "run"]
            if (matched.installation === "user")
                fpArgs.push("--user")
            fpArgs.push(matched.appId)
            for (let i = 0; i < argsList.length; ++i)
                fpArgs.push(String(argsList[i]))
            Quickshell.execDetached(fpArgs)
            return
        }

        const command = root.commandFor(targetSlot)
        if (command.length === 0)
            return

        if (argsList.length === 0 && !command.includes(" ") && !command.includes("/")) {
            const entry = DesktopEntries.heuristicLookup(command)
            if (entry) {
                AppSearch.launchEntry(entry)
                return
            }
        }

        if (argsList.length > 0) {
            const helperCmd = ["/usr/bin/python3", root._helperScript, "resolve-launch", targetSlot, Config.filePath, "--"].concat(argsList.map(a => String(a)))
            Quickshell.execDetached(["/usr/bin/python3", "-c",
                "import json, subprocess, sys; from default_apps_helper import resolve_launch_argv; " +
                "argv = resolve_launch_argv(sys.argv[1], sys.argv[2], sys.argv[3:]); " +
                "sys.exit(subprocess.Popen(argv).pid if argv else 1)",
                targetSlot, Config.filePath].concat(argsList.map(a => String(a))))
            return
        }

        ShellExec.execCmd(command)
    }

    function launchNetworkSettings(useEthernet: bool): void {
        const slot = useEthernet ? "networkEthernet" : "network"
        const matched = root.findDiscoveredAppForSlot(slot)
        if (matched && matched.installed) {
            root.launch(slot)
            return
        }
        const command = root.commandFor(slot)
        const fallbacks = [
            "nm-connection-editor",
            "kcmshell6 kcm_networkmanagement",
            "gnome-control-center network",
            "kitty -1 fish -c nmtui",
            "foot -e nmtui"
        ]
        const chain = [command].concat(fallbacks.filter(c => c.split(" ")[0] !== command.split(" ")[0]))
        const sh = chain
            .filter(c => c.length > 0)
            .map(c => `command -v ${c.split(" ")[0]} >/dev/null 2>&1 && exec ${c}`)
            .join(" || ")
        ShellExec.execCmd(sh)
    }
}
