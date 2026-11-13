pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.services

Singleton {
    id: root

    property int _configRevision: 0
    property bool discoveryLoaded: false
    property bool discovering: false
    readonly property bool discoveryLoading: discovering
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
            id: "pdfViewer",
            group: "primary",
            icon: "picture_as_pdf",
            label: Translation.tr("PDF Documents (.pdf)"),
            description: Translation.tr("Default viewer for PDF files and documents (application/pdf)."),
            defaultCommand: "okular",
            placeholder: "okular",
            supportsXdgSync: true,
            xdgTargetLabel: "application/pdf",
            presets: [
                { id: "okular", label: "Okular", command: "okular", desktopId: "org.kde.okular.desktop" },
                { id: "evince", label: "Document Viewer (Evince)", command: "evince", desktopId: "org.gnome.Evince.desktop" },
                { id: "papers", label: "Papers", command: "papers", desktopId: "org.gnome.Papers.desktop" },
                { id: "zathura", label: "Zathura", command: "zathura", desktopId: "org.pwmt.zathura.desktop" },
                { id: "sioyek", label: "Sioyek", command: "sioyek", desktopId: "com.github.ahrm.sioyek.desktop" },
                { id: "zen", label: "Zen Browser", command: "zen-browser", desktopId: "app.zen_browser.zen.desktop" },
                { id: "firefox", label: "Firefox", command: "firefox", desktopId: "firefox.desktop" }
            ]
        },
        {
            id: "officeSuite",
            group: "primary",
            icon: "description",
            label: Translation.tr("Office Documents (.docx, .xlsx, .pptx)"),
            description: Translation.tr("Default application for Word (.docx, .doc, .odt), Excel (.xlsx), and PowerPoint (.pptx) files."),
            defaultCommand: "libreoffice",
            placeholder: "libreoffice",
            supportsXdgSync: true,
            xdgTargetLabel: ".docx · .odt · .xlsx · .pptx",
            presets: [
                { id: "libreoffice-writer", label: "LibreOffice Writer", command: "libreoffice --writer", desktopId: "libreoffice-writer.desktop" },
                { id: "libreoffice", label: "LibreOffice", command: "libreoffice", desktopId: "org.libreoffice.LibreOffice.desktop" },
                { id: "onlyoffice", label: "ONLYOFFICE", command: "onlyoffice-desktopeditors", desktopId: "org.onlyoffice.desktopeditors.desktop" },
                { id: "wps", label: "WPS Office", command: "wps", desktopId: "com.wps.Office.desktop" },
                { id: "abiword", label: "AbiWord", command: "abiword", desktopId: "com.abisource.AbiWord.desktop" }
            ]
        },
        {
            id: "htmlViewer",
            group: "primary",
            icon: "html",
            label: Translation.tr("HTML Files (.html, .htm)"),
            description: Translation.tr("Default application for opening local .html / .htm documents (text/html)."),
            defaultCommand: "firefox",
            placeholder: "firefox",
            supportsXdgSync: true,
            xdgTargetLabel: "text/html · application/xhtml+xml",
            presets: [
                { id: "firefox", label: "Firefox", command: "firefox", desktopId: "firefox.desktop" },
                { id: "zen", label: "Zen Browser", command: "zen-browser", desktopId: "app.zen_browser.zen.desktop" },
                { id: "chromium", label: "Chromium", command: "chromium", desktopId: "chromium.desktop" },
                { id: "code", label: "Visual Studio Code", command: "code", desktopId: "code.desktop" },
                { id: "zed", label: "Zed", command: "zeditor", desktopId: "dev.zed.Zed.desktop" }
            ]
        },
        {
            id: "imageViewer",
            group: "primary",
            icon: "image",
            label: Translation.tr("Images (.png, .jpg, .webp, .svg)"),
            description: Translation.tr("Default viewer for photos and image files (image/png, image/jpeg, image/webp, image/svg+xml)."),
            defaultCommand: "loupe",
            placeholder: "loupe",
            supportsXdgSync: true,
            xdgTargetLabel: "image/png · image/jpeg · image/webp · image/svg+xml",
            presets: [
                { id: "loupe", label: "Image Viewer (Loupe)", command: "loupe", desktopId: "org.gnome.Loupe.desktop" },
                { id: "gwenview", label: "Gwenview", command: "gwenview", desktopId: "org.kde.gwenview.desktop" },
                { id: "eog", label: "Eye of GNOME", command: "eog", desktopId: "org.gnome.eog.desktop" },
                { id: "imv", label: "imv", command: "imv", desktopId: "imv.desktop" },
                { id: "swayimg", label: "Swayimg", command: "swayimg", desktopId: "swayimg.desktop" },
                { id: "qview", label: "qView", command: "qview", desktopId: "com.interversehq.qView.desktop" },
                { id: "gimp", label: "GIMP", command: "gimp", desktopId: "org.gimp.GIMP.desktop" }
            ]
        },
        {
            id: "videoPlayer",
            group: "primary",
            icon: "movie",
            label: Translation.tr("Videos (.mp4, .mkv, .webm)"),
            description: Translation.tr("Default player for video and movie files (video/mp4, video/x-matroska, video/webm)."),
            defaultCommand: "mpv",
            placeholder: "mpv",
            supportsXdgSync: true,
            xdgTargetLabel: "video/mp4 · video/x-matroska · video/webm",
            presets: [
                { id: "mpv", label: "mpv Media Player", command: "mpv", desktopId: "mpv.desktop" },
                { id: "vlc", label: "VLC Media Player", command: "vlc", desktopId: "vlc.desktop" },
                { id: "celluloid", label: "Celluloid", command: "celluloid", desktopId: "io.github.celluloid_player.Celluloid.desktop" },
                { id: "haruna", label: "Haruna", command: "haruna", desktopId: "org.kde.haruna.desktop" },
                { id: "clapper", label: "Clapper", command: "clapper", desktopId: "com.github.rafostar.Clapper.desktop" },
                { id: "showtime", label: "Showtime", command: "showtime", desktopId: "org.gnome.Showtime.desktop" },
                { id: "totem", label: "Videos (Totem)", command: "totem", desktopId: "org.gnome.Totem.desktop" }
            ]
        },
        {
            id: "audioPlayer",
            group: "primary",
            icon: "music_note",
            label: Translation.tr("Audio & Music (.mp3, .flac, .ogg, .wav)"),
            description: Translation.tr("Default player for local music and audio tracks (audio/mpeg, audio/flac, audio/ogg, audio/x-wav)."),
            defaultCommand: "amberol",
            placeholder: "amberol",
            supportsXdgSync: true,
            xdgTargetLabel: "audio/mpeg · audio/flac · audio/ogg · audio/x-wav",
            presets: [
                { id: "alis-local-music", label: "Local Music (MPD)", command: "alis local-music", desktopId: "alis-local-music.desktop", builtin: true },
                { id: "amberol", label: "Amberol", command: "amberol", desktopId: "io.bassi.Amberol.desktop" },
                { id: "gapless", label: "Gapless (G4Music)", command: "g4music", desktopId: "com.github.neithern.g4music.desktop" },
                { id: "elisa", label: "Elisa", command: "elisa", desktopId: "org.kde.elisa.desktop" },
                { id: "strawberry", label: "Strawberry", command: "strawberry", desktopId: "org.strawberrymusicplayer.strawberry.desktop" },
                { id: "audacious", label: "Audacious", command: "audacious", desktopId: "audacious.desktop" },
                { id: "vlc", label: "VLC Media Player", command: "vlc", desktopId: "vlc.desktop" },
                { id: "mpv", label: "mpv Media Player", command: "mpv", desktopId: "mpv.desktop" }
            ]
        },
        {
            id: "archiveManager",
            group: "primary",
            icon: "folder_zip",
            label: Translation.tr("Archives (.zip, .tar.gz, .7z, .rar)"),
            description: Translation.tr("Default archive manager for compressed packages (application/zip, application/x-compressed-tar, application/x-7z-compressed)."),
            defaultCommand: "file-roller",
            placeholder: "file-roller",
            supportsXdgSync: true,
            xdgTargetLabel: "application/zip · .tar.gz · .7z · .rar",
            presets: [
                { id: "file-roller", label: "Archive Manager (File Roller)", command: "file-roller", desktopId: "org.gnome.FileRoller.desktop" },
                { id: "ark", label: "Ark", command: "ark", desktopId: "org.kde.ark.desktop" },
                { id: "engrampa", label: "Engrampa", command: "engrampa", desktopId: "engrampa.desktop" },
                { id: "xarchiver", label: "Xarchiver", command: "xarchiver", desktopId: "xarchiver.desktop" },
                { id: "peazip", label: "PeaZip", command: "peazip", desktopId: "io.github.peazip.PeaZip.desktop" }
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
                const updates = {}
                let hasUpdates = false
                const defs = root._slotDefinitions ?? []
                for (let i = 0; i < defs.length; ++i) {
                    const slotId = defs[i].id
                    const idKey = root.configuredDesktopId(slotId)
                    if (!idKey || !idKey.includes("alis-app-"))
                        continue
                    const matched = payload.apps.find(a => a && (a.identityKey === idKey || a.desktopId === idKey))
                    if (matched && matched.exec && matched.exec !== root.configuredCommand(slotId)) {
                        updates[`apps.${slotId}`] = matched.exec
                        if (slotId === "fileManager")
                            updates["apps.fileExplorer"] = matched.exec
                        hasUpdates = true
                    }
                }
                if (hasUpdates)
                    Config.setNestedValues(updates)
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
            const slug = cmd.toLowerCase()
                .replace(/^.*\/+/, "")
                .replace(/\.(appimage|desktop)$/i, "")
                .replace(/[^a-z0-9]+/g, "-")
                .replace(/^-+|-+$/g, "")
            if (slug.length > 0) {
                const bySlug = all.find(a => {
                    const did = String(a.desktopId ?? "").toLowerCase()
                    const nm = String(a.name ?? "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
                    const eb = String(a.execBin ?? "").toLowerCase().replace(/\.(appimage|desktop)$/i, "").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
                    return did === `alis-app-${slug}.desktop`
                        || did === `${slug}.desktop`
                        || nm === slug
                        || (eb.length > 0 && (eb === slug || eb.startsWith(`${slug}-`)))
                })
                if (bySlug)
                    return bySlug
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
        if (preset?.builtin) {
            return {
                name: preset.label, icon: def.icon, sourceBadge: "Alis",
                desktopId: preset.desktopId, appId: "", identityKey: idKey,
                command: cmd, installed: true, isCustom: false,
                isFlatpak: false, installation: "native", origin: ""
            }
        }
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

        const fallbackDesktopId = idKey.endsWith(".desktop")
            ? idKey
            : (idKey.startsWith("native:") && idKey.length > 7
                ? (idKey.slice(7).endsWith(".desktop") ? idKey.slice(7) : `${idKey.slice(7)}.desktop`)
                : "")

        return {
            name: cmd || (def?.label ?? slotId),
            icon: def?.icon ?? "terminal",
            sourceBadge: Translation.tr("Custom command"),
            desktopId: fallbackDesktopId,
            appId: "",
            identityKey: idKey,
            command: cmd,
            installed: cmd.length > 0,
            isCustom: fallbackDesktopId.length === 0,
            isFlatpak: false,
            installation: fallbackDesktopId.length > 0 ? "native" : "custom",
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
        updates[`apps.${definition.id}`] = preset.builtin ? preset.command : (matched ? matched.exec : preset.command)
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

        if (targetSlot === "audioPlayer" && root.commandFor(targetSlot) === "alis local-music") {
            root.openLocalMusic(argsList)
            return
        }

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
            Quickshell.execDetached(["/usr/bin/python3", "-c",
                "import runpy, subprocess, sys; helper = runpy.run_path(sys.argv[1]); " +
                "argv = helper['resolve_launch_argv'](sys.argv[2], sys.argv[3], sys.argv[4:]); " +
                "subprocess.Popen(argv) if argv else sys.exit(1)",
                root._helperScript, targetSlot, Config.filePath].concat(argsList.map(a => String(a))))
            return
        }

        ShellExec.execCmd(command)
    }

    function openLocalMusic(files): string {
        if (!(Config.options?.dashboard?.music?.enable ?? true))
            return "error: Local Music is disabled in Dashboard settings"
        GlobalStates.dashboardSelectionRestored = true
        GlobalStates.dashboardPageId = "music"
        GlobalStates.dashboardPage = 1
        GlobalStates.dashboardOpen = true
        return LocalMusic.openExternalFiles(files)
    }

    property string pendingShortcutAction: ""
    property string pendingShortcutLabel: ""
    property int _shortcutRequestNonce: 0

    function _escapeKdlToken(tok: string): string {
        return String(tok ?? "").replace(/\\/g, "\\\\").replace(/"/g, '\\"')
    }

    function _splitCommandTokens(cmdStr: string): list<string> {
        const s = String(cmdStr ?? "").trim()
        if (!s)
            return []
        const tokens = []
        const re = /"((?:[^"\\]|\\.)*)"|'([^']*)'|(\S+)/g
        let m
        while ((m = re.exec(s)) !== null) {
            if (m[1] !== undefined)
                tokens.push(m[1].replace(/\\(.)/g, "$1"))
            else if (m[2] !== undefined)
                tokens.push(m[2])
            else if (m[3] !== undefined)
                tokens.push(m[3])
        }
        return tokens
    }

    function niriSpawnActionForSlot(slotId: string, forceNewWindow = false): string {
        const target = slotId === "fileExplorer" ? "fileManager" : slotId
        const home = Directories.homePath ?? ""
        const alisBin = home.length > 0 ? `${home}/.local/bin/alis` : "alis"
        const suffix = forceNewWindow ? ' "--new"' : ""
        if (target === "terminal")
            return `spawn "${root._escapeKdlToken(alisBin)}" "terminal"${suffix}`
        if (target === "browser")
            return `spawn "${root._escapeKdlToken(alisBin)}" "browser"${suffix}`
        if (target === "fileManager")
            return `spawn "${root._escapeKdlToken(alisBin)}" "files"${suffix}`
        if (target === "editor")
            return `spawn "${root._escapeKdlToken(alisBin)}" "editor"${suffix}`
        const app = root.findDiscoveredAppForSlot(target)
        if (app)
            return root.niriSpawnActionForApp(app)
        const cmd = root.commandFor(target)
        return root.niriSpawnActionForCommand(cmd)
    }

    readonly property var tuiAppBins: [
        "yazi", "ranger", "lf", "nnn", "vifm", "mc",
        "nvim", "vim", "vi", "nano", "hx", "helix", "micro", "kak",
        "btop", "htop", "top", "nvtop", "nmtui", "pulsemixer", "alsamixer", "lazygit"
    ]

    function _isTuiBin(binStr: string): bool {
        const clean = String(binStr ?? "").trim()
        if (!clean)
            return false
        const base = clean.includes("/") ? clean.slice(clean.lastIndexOf("/") + 1) : clean
        return root.tuiAppBins.includes(base.toLowerCase())
    }

    function _stripDesktopFieldCodes(execStr: string): string {
        return String(execStr ?? "")
            .replace(/(?:^|\s)%[fFuUdDnNickvm](?=\s|$)/g, " ")
            .replace(/\s+/g, " ")
            .trim()
    }

    function niriSpawnActionForCommand(cmdStr: string, forceTerminal = false): string {
        const cleaned = root._stripDesktopFieldCodes(cmdStr)
        const tokens = root._splitCommandTokens(cleaned)
        if (tokens.length === 0)
            return ""
        if (forceTerminal || root._isTuiBin(tokens[0])) {
            const home = Directories.homePath ?? ""
            const alisBin = home.length > 0 ? `${home}/.local/bin/alis` : "alis"
            return `spawn "${root._escapeKdlToken(alisBin)}" "terminal" "-e" ` + tokens.map(t => `"${root._escapeKdlToken(t)}"`).join(" ")
        }
        return "spawn " + tokens.map(t => `"${root._escapeKdlToken(t)}"`).join(" ")
    }

    function niriSpawnActionForApp(appObj: var): string {
        if (!appObj)
            return ""
        if (appObj.isFlatpak && appObj.appId) {
            if (appObj.installation === "user")
                return `spawn "flatpak" "run" "--user" "${root._escapeKdlToken(appObj.appId)}"`
            return `spawn "flatpak" "run" "${root._escapeKdlToken(appObj.appId)}"`
        }
        const needsTerminal = Boolean(appObj.terminal) || root._isTuiBin(String(appObj.execBin ?? ""))
        const execStr = root._stripDesktopFieldCodes(String(appObj.exec ?? appObj.execPath ?? ""))
        return root.niriSpawnActionForCommand(execStr, needsTerminal)
    }

    function normalizeNiriBindAction(rawAction: string): string {
        let trimmed = String(rawAction ?? "").trim()
        if (trimmed.endsWith(";"))
            trimmed = trimmed.slice(0, -1).trim()
        if (!trimmed)
            return ""
        if (!trimmed.startsWith("spawn ") && !trimmed.startsWith("spawn\t"))
            return trimmed
        const rest = trimmed.slice(5).trim()
        let tokens = root._splitCommandTokens(rest)
        if (tokens.length === 0)
            return trimmed
        if (tokens.length === 1 && /\s/.test(tokens[0]) && !tokens[0].startsWith("/")) {
            const sub = root._splitCommandTokens(tokens[0])
            if (sub.length >= 2) {
                const sub0 = sub[0].includes("/") ? sub[0].slice(sub[0].lastIndexOf("/") + 1).toLowerCase() : sub[0].toLowerCase()
                if (sub.length === 2 && (sub0 === "kitty" || sub0 === "foot" || sub0 === "alacritty") && root._isTuiBin(sub[1]))
                    tokens = [sub[0], "-e", sub[1]]
                else
                    tokens = sub
            }
        }
        if (tokens.length === 1 && root._isTuiBin(tokens[0]))
            return root.niriSpawnActionForCommand(tokens[0], true)
        return "spawn " + tokens.map(t => `"${root._escapeKdlToken(t)}"`).join(" ")
    }

    function slotSummary(slotId: string): var {
        const s = root.selectedAppSummary(slotId)
        if (!s)
            return null
        return Object.assign({}, s, { displayName: s.name })
    }

    function resolveShortcutAppInfo(actionRaw: string): var {
        void(root._configRevision)
        const act = String(actionRaw ?? "").trim()
        if (!act.startsWith("spawn"))
            return null

        const tokens = []
        const re = /"((?:[^"\\]|\\.)*)"/g
        let m
        while ((m = re.exec(act)) !== null) {
            tokens.push(m[1].replace(/\\(.)/g, "$1"))
        }
        if (tokens.length === 0)
            return null

        const t0 = tokens[0]
        const base0 = t0.includes("/") ? t0.slice(t0.lastIndexOf("/") + 1) : t0
        const isNewWindow = tokens.indexOf("--new") !== -1 || tokens.indexOf("--new-window") !== -1

        // 1. Check if it routes through `alis` default app role (terminal / browser / files / editor)
        if (base0 === "alis" && tokens.length >= 2) {
            const rawRole = tokens[1]
            if (rawRole === "terminal" || rawRole === "browser" || rawRole === "files" || rawRole === "file-manager" || rawRole === "editor") {
                const extraArg = tokens.slice(2).find(tok => !tok.startsWith("-")) ?? ""
                // If `alis terminal <tui-app>` (e.g. `alis terminal yazi`), resolve `<tui-app>` as the target application
                if (rawRole === "terminal" && extraArg) {
                    const extraLower = extraArg.toLowerCase()
                    const allApps = root.discoveredApps ?? []
                    const tuiMatch = allApps.find(a =>
                        String(a.execBin ?? "").toLowerCase() === extraLower
                        || String(a.name ?? "").toLowerCase() === extraLower
                        || String(a.desktopId ?? "").toLowerCase() === `${extraLower}.desktop`
                    ) ?? null
                    const tuiName = tuiMatch?.name ?? (extraArg.charAt(0).toUpperCase() + extraArg.slice(1))
                    const tuiIcon = tuiMatch?.icon || "terminal"
                    return {
                        kind: "app",
                        slotId: "",
                        slotLabel: "",
                        slotTitle: "",
                        name: tuiName,
                        appName: tuiName,
                        displayLabel: tuiName + (isNewWindow ? " (new window)" : ""),
                        icon: tuiIcon,
                        iconName: tuiIcon,
                        fallbackSymbol: "terminal",
                        sourceBadge: tuiMatch?.sourceBadge ?? "Native",
                        desktopId: String(tuiMatch?.desktopId ?? ""),
                        isPortable: false,
                        badge: tuiName,
                        badgeText: tuiName
                    }
                }

                const slotId = (rawRole === "files" || rawRole === "file-manager") ? "fileManager" : rawRole
                const def = root.slotDefinition(slotId)
                const summary = root.selectedAppSummary(slotId)
                const roleLabel = def?.label ?? slotId
                const appName = summary?.name || roleLabel
                const iconVal = summary?.icon ?? (def?.icon ?? "apps")
                const desktopId = String(summary?.desktopId ?? "")
                return {
                    kind: "slot",
                    slotId: slotId,
                    slotLabel: roleLabel,
                    slotTitle: roleLabel,
                    name: appName,
                    appName: appName,
                    displayLabel: appName + (isNewWindow ? " (new window)" : ""),
                    icon: iconVal,
                    iconName: iconVal,
                    fallbackSymbol: def?.icon ?? "apps",
                    sourceBadge: summary?.sourceBadge ?? "",
                    desktopId: desktopId,
                    isPortable: desktopId.startsWith("alis-app-"),
                    badge: appName,
                    badgeText: appName
                }
            }
            return null
        }

        // 2. Check if it launches a discovered application directly
        if (base0 === "qs" || base0 === "wpctl" || base0 === "brightnessctl" || base0 === "loginctl" || base0 === "systemctl")
            return null

        const all = root.discoveredApps ?? []
        let matched = null
        if (base0 === "flatpak" && tokens.length >= 3 && tokens[1] === "run") {
            let appId = ""
            for (let i = 2; i < tokens.length; ++i) {
                if (!tokens[i].startsWith("-")) {
                    appId = tokens[i]
                    break
                }
            }
            if (appId) {
                matched = all.find(a => a.isFlatpak && a.appId === appId) ?? null
            }
        } else {
            const joined = tokens.join(" ")
            const base0Lower = base0.toLowerCase()
            const terminalBins = ["kitty", "foot", "ghostty", "alacritty", "wezterm", "konsole", "xterm"]
            let lookupToken = t0
            let lookupLower = base0Lower
            if (terminalBins.includes(base0Lower) && tokens.length >= 2) {
                const tuiArg = tokens.slice(1).find(tok => !tok.startsWith("-") && root._isTuiBin(tok)) ?? ""
                if (tuiArg) {
                    lookupToken = tuiArg
                    lookupLower = (tuiArg.includes("/") ? tuiArg.slice(tuiArg.lastIndexOf("/") + 1) : tuiArg).toLowerCase()
                }
            }
            matched = all.find(a =>
                a.exec === joined
                || a.exec === lookupToken
                || (!a.isFlatpak && String(a.execBin ?? "").toLowerCase() === lookupLower)
                || String(a.desktopId ?? "").toLowerCase() === `${lookupLower}.desktop`
                || String(a.name ?? "").toLowerCase() === lookupLower
            ) ?? null
        }

        if (matched) {
            const desktopId = String(matched.desktopId ?? matched.id ?? "")
            const defaultSlots = root.defaultSlotsForDesktopId(desktopId)
            const firstDefaultSlot = defaultSlots.length > 0 ? defaultSlots[0] : null
            const isPortable = desktopId.startsWith("alis-app-")
            const iconVal = matched.icon || "apps"
            return {
                kind: "app",
                slotId: firstDefaultSlot ? firstDefaultSlot.id : "",
                slotLabel: firstDefaultSlot ? firstDefaultSlot.label : "",
                slotTitle: firstDefaultSlot ? firstDefaultSlot.label : "",
                name: matched.name,
                appName: matched.name,
                displayLabel: matched.name + (isNewWindow ? " (new window)" : ""),
                icon: iconVal,
                iconName: iconVal,
                fallbackSymbol: "apps",
                sourceBadge: matched.sourceBadge || (matched.isFlatpak ? "Flatpak" : "Native"),
                desktopId: desktopId,
                isPortable: isPortable,
                badge: matched.name,
                badgeText: matched.name
            }
        }
        return null
    }

    function defaultSlotsForDesktopId(desktopId: string): list<var> {
        void(root._configRevision)
        const target = String(desktopId ?? "").trim()
        if (!target)
            return []
        const norm = target.endsWith(".desktop") ? target : `${target}.desktop`
        const matches = []
        const defs = root.primarySlotDefinitions()
        for (let i = 0; i < defs.length; ++i) {
            const slot = defs[i]
            const sum = root.selectedAppSummary(slot.id)
            if (sum && sum.desktopId === norm) {
                matches.push({ id: slot.id, label: slot.label, title: slot.label, icon: slot.icon })
            }
        }
        return matches
    }

    function clearPendingShortcut(): void {
        root.pendingShortcutAction = ""
        root.pendingShortcutLabel = ""
    }

    function prepareShortcutForSlot(slotId: string): void {
        const def = root.slotDefinition(slotId)
        const sum = root.selectedAppSummary(slotId)
        root.pendingShortcutAction = root.niriSpawnActionForSlot(slotId, false)
        root.pendingShortcutLabel = def ? `${def.label} (${sum?.name ?? ""})` : slotId
        root._shortcutRequestNonce++
    }

    function prepareShortcutForApp(appObj: var): void {
        if (!appObj)
            return
        root.pendingShortcutAction = root.niriSpawnActionForApp(appObj)
        root.pendingShortcutLabel = String(appObj.name ?? appObj.desktopId ?? appObj.id ?? "")
        root._shortcutRequestNonce++
    }

    function prepareShortcutForCommand(execPath: string, appName: string): void {
        root.pendingShortcutAction = root.niriSpawnActionForCommand(execPath)
        root.pendingShortcutLabel = appName
        root._shortcutRequestNonce++
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

    // -------------------------------------------------------------------------
    // Persistent Portable Applications State & Process Execution
    // -------------------------------------------------------------------------
    readonly property string portableManageScript: Quickshell.shellPath("scripts/apps/manage-portable-apps.py")
    property var apps: []
    readonly property var managedApps: apps
    readonly property var portableApps: apps
    property bool portableAppsLoaded: false
    property bool _manualAppsOverride: false

    property bool busy: false
    property string busyAction: ""
    property string busyAppId: ""
    property bool checkingUpdates: false
    property string updatingAppId: ""
    property int progressPercent: -1
    property string progressDetail: ""
    property string progressStage: ""
    property bool pickerActive: false
    property string statusMessage: ""
    property string statusError: ""

    property string _lastPortableAction: ""
    property bool _refreshAppLauncherAfterAction: false
    property string _portableStdoutBuffer: ""
    property bool _portableStdoutDone: false
    property bool _portableProcExited: false
    property int _portableLastExitCode: 0
    property bool _portableCommandActive: false

    readonly property int updatesAvailableCount: {
        let count = 0
        const list = root.apps || []
        for (let i = 0; i < list.length; ++i) {
            if (list[i] && list[i].updateAvailable)
                count++
        }
        return count
    }

    function setManagedAppsManual(list: var): void {
        root._manualAppsOverride = true
        root.apps = Array.isArray(list) ? list : []
        root.portableAppsLoaded = true
    }

    readonly property bool portableProcessRunning: Boolean(root._portableCommandActive || portableManageProc?.running || portableFinalizeFallbackTimer?.running)
    readonly property bool portableAppsBusy: root.busy && root.portableProcessRunning

    function _setNativePickerDialogVisible(visible: bool): void {
        try {
            if (typeof GlobalStates !== "undefined" && GlobalStates && typeof GlobalStates.setSettingsNativeDialogVisible === "function") {
                GlobalStates.setSettingsNativeDialogVisible("applicationsFilePicker", visible)
            }
        } catch (e) {
        }
    }

    function _releasePortablePickerLock(): void {
        if (root.pickerActive || Boolean(typeof GlobalStates !== "undefined" && GlobalStates?._settingsNativeDialogs?.applicationsFilePicker)) {
            root.pickerActive = false
            root._setNativePickerDialogVisible(false)
        }
    }

    function _recoverStalePortableBusyIfIdle(): void {
        if (!portableManageProc.running && !portableFinalizeFallbackTimer.running) {
            root._portableCommandActive = false
            root._releasePortablePickerLock()
            if (root.busy) {
                root.busy = false
                root.busyAction = ""
                root.busyAppId = ""
                root.checkingUpdates = false
                root.updatingAppId = ""
                root.progressPercent = -1
                root.progressDetail = ""
                root.progressStage = ""
            }
        }
    }

    function _handlePortableProgressEvent(ev: var): void {
        if (!ev)
            return
        const act = String(ev.action ?? "").trim()
        if (act.length > 0) {
            root.busyAction = act
            root._lastPortableAction = act
            root.checkingUpdates = (act === "check-updates")
        }
        const aid = String(ev.appId ?? "").trim()
        if (aid.length > 0) {
            root.busyAppId = aid
            if (root.busyAction === "update")
                root.updatingAppId = aid
        } else if (root.busyAction === "update" && !root.updatingAppId) {
            root.updatingAppId = "__all__"
        }
        if (typeof ev.percent === "number" && ev.percent >= 0) {
            root.progressPercent = Math.max(0, Math.min(100, Math.round(ev.percent)))
        }
        const det = String(ev.detail ?? "").trim()
        if (det.length > 0) {
            root.progressDetail = det
            root.statusMessage = det
            root.statusError = ""
        }
        const stg = String(ev.stage ?? "").trim()
        if (stg.length > 0) {
            root.progressStage = stg
            if (stg === "installing" && root.pickerActive) {
                root._releasePortablePickerLock()
            }
        }
        if (Array.isArray(ev.apps) && !root._manualAppsOverride) {
            root.apps = ev.apps
            root.portableAppsLoaded = true
        }
    }

    function _applyPortableResult(parsed: var): void {
        if (!parsed)
            return
        if (Array.isArray(parsed.apps)) {
            if (!(root._manualAppsOverride && root._lastPortableAction === "list")) {
                root.apps = parsed.apps
                root.portableAppsLoaded = true
            }
        }
        if (parsed.added || parsed.removed || (Array.isArray(parsed.updated) && parsed.updated.length > 0)) {
            root._refreshAppLauncherAfterAction = true
        }
        if (parsed.cancelled) {
            root.statusError = ""
            root.statusMessage = ""
            return
        }
        if (parsed.ok === false) {
            root.statusError = String(parsed.error || Translation.tr("Operation failed."))
            root.statusMessage = payloadHasUpdatesApplied(parsed.updated)
                ? Translation.tr("Updated %1 application(s).").arg(parsed.updated.length)
                : ""
            return
        }
        const chkErrs = Array.isArray(parsed.checkErrors) ? parsed.checkErrors : []
        if (chkErrs.length > 0) {
            root.statusError = String(parsed.error || chkErrs.join("; "))
        } else if (root._lastPortableAction !== "list" || Array.isArray(parsed.updated) || Array.isArray(parsed.checked)) {
            root.statusError = ""
        }
        if (Array.isArray(parsed.updated)) {
            if (payloadHasUpdatesApplied(parsed.updated)) {
                root.statusMessage = Translation.tr("Updated %1 application(s).").arg(parsed.updated.length)
                root._refreshAppLauncherAfterAction = true
            } else {
                root.statusMessage = Translation.tr("Application is already up to date.")
            }
        } else if (Array.isArray(parsed.checked)) {
            const avail = Number(parsed.updatesAvailable ?? 0)
            if (avail > 0)
                root.statusMessage = Translation.tr("%1 update(s) available.").arg(avail)
            else if (chkErrs.length === 0)
                root.statusMessage = Translation.tr("All supported applications are up to date.")
            else
                root.statusMessage = ""
        } else if (root._lastPortableAction === "add" || root._lastPortableAction === "pick-and-add") {
            const addedCount = Array.isArray(parsed.added) ? parsed.added.length : 0
            if (addedCount > 0) {
                root.statusMessage = Translation.tr("Installed %1 portable application(s) into ~/.local/share/alis/applications.").arg(addedCount)
                root._refreshAppLauncherAfterAction = true
            } else if (parsed.error) {
                root.statusError = String(parsed.error)
            }
        } else if (root._lastPortableAction === "remove") {
            root.statusMessage = Translation.tr("Removed application and cleaned up desktop entry.")
            root._refreshAppLauncherAfterAction = true
        } else if (root._lastPortableAction === "set-update-source") {
            root.statusMessage = Translation.tr("Saved update source.")
        }
    }

    function payloadHasUpdatesApplied(updatedArr: var): bool {
        return Array.isArray(updatedArr) && updatedArr.length > 0
    }

    function _finalizePortableCommandIfReady(): void {
        if (!root._portableProcExited || !root._portableStdoutDone)
            return
        portableFinalizeFallbackTimer.stop()
        root._releasePortablePickerLock()
        if (root._lastPortableAction !== "list") {
            root.statusMessage = ""
        }
        const raw = root._portableStdoutBuffer
        if (raw.length > 0) {
            try {
                const parsed = JSON.parse(raw)
                root._applyPortableResult(parsed)
            } catch (e) {
                root.statusError = String(e)
                root.statusMessage = ""
            }
        }
        if (root._portableLastExitCode !== 0 && root.statusError.length === 0) {
            root.statusError = Translation.tr("Command exited with code %1").arg(root._portableLastExitCode)
            root.statusMessage = ""
        }
        const shouldRefreshDiscovery = root._refreshAppLauncherAfterAction
        root._refreshAppLauncherAfterAction = false
        root._portableCommandActive = false
        root.busy = false
        root.busyAction = ""
        root.busyAppId = ""
        root.checkingUpdates = false
        root.updatingAppId = ""
        root.progressPercent = -1
        root.progressDetail = ""
        root.progressStage = ""
        if (shouldRefreshDiscovery) {
            root.refreshDiscovery()
            Autostart.refresh()
        }
    }

    function _startPortableCommand(args: var, actionTag: string, targetAppId = ""): void {
        root._recoverStalePortableBusyIfIdle()
        if (root.busy || portableManageProc.running)
            return
        root._lastPortableAction = actionTag
        root.busy = true
        root.busyAction = actionTag
        root.busyAppId = String(targetAppId ?? "")
        root.checkingUpdates = (actionTag === "check-updates")
        root.updatingAppId = (actionTag === "update") ? (String(targetAppId ?? "") || "__all__") : ""
        if (actionTag === "pick-and-add") {
            root.pickerActive = true
            root._setNativePickerDialogVisible(true)
        } else {
            root.pickerActive = false
        }
        root._portableStdoutBuffer = ""
        root._portableStdoutDone = false
        root._portableProcExited = false
        root._portableLastExitCode = 0

        if (actionTag === "update") {
            root.progressPercent = 2
            root.progressStage = "preparing"
            root.progressDetail = targetAppId && targetAppId !== "__all__"
                ? Translation.tr("Updating %1…").arg(targetAppId)
                : Translation.tr("Updating portable applications…")
            root.statusError = ""
            root.statusMessage = root.progressDetail
        } else if (actionTag === "check-updates") {
            root.progressPercent = 5
            root.progressStage = "checking"
            root.progressDetail = Translation.tr("Checking for updates…")
            root.statusError = ""
            root.statusMessage = root.progressDetail
        } else {
            root.progressPercent = -1
            root.progressStage = ""
            root.progressDetail = ""
            if (actionTag !== "list") {
                root.statusError = ""
                root.statusMessage = ""
            }
        }

        portableManageProc.command = ["python3", "-B", root.portableManageScript].concat(args)
        root._portableCommandActive = true
        portableManageProc.running = true
    }

    function refreshList(forceAppLauncherDiscovery = false): void {
        root._recoverStalePortableBusyIfIdle()
        if (forceAppLauncherDiscovery) {
            root._manualAppsOverride = false
            root._refreshAppLauncherAfterAction = true
            root.statusError = ""
            root.statusMessage = ""
        }
        if (root.busy || portableManageProc.running)
            return
        root._startPortableCommand(["list", "--attach-running"], "list", "")
    }

    function list(forceAppLauncherDiscovery = false): void {
        root.refreshList(forceAppLauncherDiscovery)
    }

    function checkForUpdates(appId = ""): void {
        root._recoverStalePortableBusyIfIdle()
        if (root.busy || portableManageProc.running)
            return
        root._manualAppsOverride = false
        const target = String(appId ?? "").trim()
        const args = target.length > 0
            ? ["--bg-survive", "check-updates", target]
            : ["--bg-survive", "check-updates", "--all"]
        root._startPortableCommand(args, "check-updates", target)
    }

    function checkUpdates(appId = ""): void {
        root.checkForUpdates(appId)
    }

    function updateApplication(appId: string): void {
        root._recoverStalePortableBusyIfIdle()
        const target = String(appId ?? "").trim()
        if (!target || root.busy || portableManageProc.running)
            return
        root._manualAppsOverride = false
        root._startPortableCommand(["--bg-survive", "update", target], "update", target)
    }

    function updateAllApplications(): void {
        root._recoverStalePortableBusyIfIdle()
        if (root.busy || portableManageProc.running)
            return
        root._manualAppsOverride = false
        root._startPortableCommand(["--bg-survive", "update", "--all"], "update", "__all__")
    }

    function update(appId = ""): void {
        const target = String(appId ?? "").trim()
        if (!target || target === "--all" || target === "all")
            root.updateAllApplications()
        else
            root.updateApplication(target)
    }

    function pickAndAddApplications(): void {
        root._recoverStalePortableBusyIfIdle()
        if (root.busy || portableManageProc.running)
            return
        root._manualAppsOverride = false
        root._startPortableCommand(["pick-and-add"], "pick-and-add", "")
    }

    function pickAndAddPortableApplications(): void {
        root.pickAndAddApplications()
    }

    function addApplicationPaths(paths: var): void {
        root._recoverStalePortableBusyIfIdle()
        if (root.busy || portableManageProc.running)
            return
        const clean = []
        for (let i = 0; i < (paths ? paths.length : 0); ++i) {
            const p = String(paths[i] ?? "").trim()
            if (p.length > 0)
                clean.push(p)
        }
        if (clean.length === 0)
            return
        root._manualAppsOverride = false
        root._startPortableCommand(["add"].concat(clean), "add", "")
    }

    function register(paths: var): void {
        root.addApplicationPaths(paths)
    }

    function removeApplication(appId: string): void {
        root._recoverStalePortableBusyIfIdle()
        const target = String(appId ?? "").trim()
        if (!target || root.busy || portableManageProc.running)
            return
        root._manualAppsOverride = false
        root._startPortableCommand(["remove", target], "remove", target)
    }

    function remove(appId: string): void {
        root.removeApplication(appId)
    }

    function setUpdateSource(appId: string, source: string): void {
        root._recoverStalePortableBusyIfIdle()
        const target = String(appId ?? "").trim()
        if (!target || root.busy || portableManageProc.running)
            return
        root._manualAppsOverride = false
        root._startPortableCommand(["set-update-source", target, String(source ?? "").trim()], "set-update-source", target)
    }

    Timer {
        id: portableFinalizeFallbackTimer
        interval: 60
        repeat: false
        onTriggered: {
            root._portableStdoutDone = true
            root._finalizePortableCommandIfReady()
        }
    }

    Process {
        id: portableManageProc
        stdout: StdioCollector {
            onStreamFinished: {
                root._portableStdoutBuffer = (this.text ?? "").trim()
                root._portableStdoutDone = true
                root._finalizePortableCommandIfReady()
            }
        }
        stderr: SplitParser {
            onRead: line => {
                const trimmed = String(line ?? "").trim()
                if (!trimmed.startsWith("ALIS_PROGRESS:"))
                    return
                const jsonPart = trimmed.slice("ALIS_PROGRESS:".length).trim()
                if (!jsonPart)
                    return
                try {
                    const ev = JSON.parse(jsonPart)
                    root._handlePortableProgressEvent(ev)
                } catch (e) {
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            root._portableProcExited = true
            root._portableLastExitCode = exitCode
            if (root._portableStdoutDone) {
                root._finalizePortableCommandIfReady()
            } else {
                portableFinalizeFallbackTimer.restart()
            }
        }
    }
}

