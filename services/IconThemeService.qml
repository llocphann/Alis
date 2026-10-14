pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    property var availableThemes: []
    property string currentTheme: ""
    property string dockTheme: ""  // Separate theme for dock icons

    property bool _initialized: false
    property bool _themesLoaded: false
    property bool _restartQueued: false
    readonly property string nativeDispatchPath: Quickshell.shellPath("scripts/native-dispatch")
    readonly property string nativeBackendStatePath: {
        const stateHome = String(Quickshell.env("XDG_STATE_HOME") ?? "").trim()
        const base = stateHome.length > 0 ? stateHome : (Quickshell.env("HOME") + "/.local/state")
        return base + "/alis/native-backend"
    }
    property string _nativeBackendState: ""
    readonly property bool nativeBackendEnabled: {
        const envMode = String(Quickshell.env("ALIS_NATIVE_BACKEND") ?? "").trim()
        if (envMode.length > 0)
            return envMode === "rust" || envMode === "auto"
        const stateMode = root._nativeBackendState.trim()
        return stateMode === "rust" || stateMode === "auto"
    }

    FileView {
        id: nativeBackendStateFile
        path: root.nativeBackendStatePath
        watchChanges: true
        onLoaded: root._nativeBackendState = nativeBackendStateFile.text().trim()
        onFileChanged: nativeBackendStateFile.reload()
        onLoadFailed: root._nativeBackendState = ""
    }

    // Smart icon resolution: preserve app-provided identity whenever possible.
    // Only repair the duplicated Electron resources path that is known-broken.
    function smartIconName(icon, appId) {
        if (!icon) {
            const guessed = AppSearch.lookupDesktopEntry(appId)?.icon ?? AppSearch.guessIcon(appId);
            return guessed || appId || "application-x-executable";
        }

        if (icon.startsWith("/") || icon.startsWith("file://")) {
            const path = icon.startsWith("file://") ? icon.substring(7) : icon;

            if (path.indexOf("/resources/app/resources/") !== -1) {
                return path.replace("/resources/app/resources/", "/resources/");
            }
        }

        return icon;
    }

    // Get icon path from dock theme, fallback to system
    function dockIconPath(iconName: string, fallback: string): string {
        if (!iconName) return Quickshell.iconPath(fallback || "application-x-executable")

        // If iconName is already an absolute path, use it directly
        if (iconName.startsWith("/") || iconName.startsWith("file://")) {
            return iconName.startsWith("file://") ? iconName : `file://${iconName}`
        }

        if (!root.dockTheme) return Quickshell.iconPath(iconName, fallback || "application-x-executable")

        const home = Quickshell.env("HOME")
        const theme = root.dockTheme

        // Return first candidate path - Image will handle fallback via onStatusChanged
        // Structure: theme/apps/scalable (YAMIS, etc)
        return `file://${home}/.local/share/icons/${theme}/apps/scalable/${iconName}.svg`
    }

    // Get all candidate paths for dock icon
    function dockIconCandidates(iconName: string): list<string> {
        if (!iconName || !root.dockTheme) return []

        // If iconName is already an absolute path, return it as-is (no candidates needed)
        if (iconName.startsWith("/") || iconName.startsWith("file://")) {
            return []
        }

        const home = Quickshell.env("HOME")
        const theme = root.dockTheme

        return [
            `file://${home}/.local/share/icons/${theme}/apps/scalable/${iconName}.svg`,
            `file:///usr/share/icons/${theme}/apps/scalable/${iconName}.svg`,
            `file://${home}/.local/share/icons/${theme}/scalable/apps/${iconName}.svg`,
            `file:///usr/share/icons/${theme}/scalable/apps/${iconName}.svg`,
            `file://${home}/.local/share/icons/${theme}/apps/256x256/${iconName}.png`,
            `file:///usr/share/icons/${theme}/apps/256x256/${iconName}.png`,
            `file://${home}/.local/share/icons/${theme}/256x256/apps/${iconName}.png`,
            `file:///usr/share/icons/${theme}/256x256/apps/${iconName}.png`,
        ]
    }

    function ensureInitialized(): void {
        if (root._initialized)
            return;
        root._initialized = true;

        // Load system theme
        const savedTheme = Config.ready ? (Config.options?.appearance?.iconTheme ?? "") : ""
        if (savedTheme && String(savedTheme).trim().length > 0) {
            root.currentTheme = String(savedTheme).trim()
            _log("[IconThemeService] Restoring saved icon theme:", root.currentTheme)
            root._apply(root.currentTheme, true)
        } else {
            currentThemeProc.running = false
            currentThemeProc.running = true
        }

        // Load dock theme
        root.dockTheme = Config.options?.appearance?.dockIconTheme ?? ""
    }

    function ensureThemesLoaded(force = false) {
        if (listThemesProc.running)
            return
        if (root._themesLoaded && !force)
            return

        listThemesProc.themes = []
        listThemesProc.running = true
    }

    function setTheme(themeName) {
        if (!themeName || String(themeName).trim().length === 0)
            return;

        const themeStr = String(themeName).trim()
        _log("[IconThemeService] Setting icon theme:", themeStr)

        // Update UI immediately; actual system change follows via gsettings.
        root.currentTheme = themeStr

        root._apply(themeStr, false)

        // Persist to config.json
        Config.setNestedValue('appearance.iconTheme', themeStr)

        // Ensure config is written before we do any restart.
        Config.flushWrites()
    }

    function setDockTheme(themeName: string): void {
        root.dockTheme = themeName ?? ""
        Config.setNestedValue('appearance.dockIconTheme', themeName ?? "")
        Config.flushWrites()
        root.queueRestart()
    }

    Timer {
        id: restartDelay
        interval: 250
        repeat: false
        onTriggered: {
            root._restartQueued = false
            _log("[IconThemeService] Restarting shell now...")
            Quickshell.execDetached(["/usr/bin/bash", Quickshell.shellPath("scripts/restart-shell.sh")])
        }
    }

    function queueRestart(): void {
        if (root._restartQueued)
            return;
        root._restartQueued = true
        restartDelay.restart()
    }

    function _startLegacyKdeGlobalsSync(themeName: string, skipRestart: bool): void {
        kdeGlobalsUpdateProc.themeName = themeName
        kdeGlobalsUpdateProc.skipRestart = skipRestart
        kdeGlobalsUpdateProc.running = false
        kdeGlobalsUpdateProc.running = true
    }

    function _startKdeGlobalsSync(themeName: string, skipRestart: bool): void {
        if (root.nativeBackendEnabled) {
            nativeIconSyncProc.themeName = themeName
            nativeIconSyncProc.skipRestart = skipRestart
            nativeIconSyncProc.running = false
            nativeIconSyncProc.running = true
            return
        }
        root._startLegacyKdeGlobalsSync(themeName, skipRestart)
    }

    function _continueAfterKdeGlobals(themeName: string, skipRestart: bool): void {
        // kwriteconfig6 improves Plasma integration but is optional. Whether it
        // exists or not must not prevent qt5ct/qt6ct/GTK synchronization.
        kwriteconfigProc.themeName = themeName
        kwriteconfigProc.skipRestart = skipRestart
        kwriteconfigProc.running = false
        kwriteconfigProc.running = true

        // Restart shell if user actively changed theme. This intentionally does
        // not depend on any optional KDE integration helper succeeding.
        if (!skipRestart)
            root.queueRestart()
    }

    function _startQtSync(themeName: string): void {
        qt5ctProc.themeName = themeName
        qt5ctProc.running = false
        qt5ctProc.running = true
        qt6ctProc.themeName = themeName
        qt6ctProc.running = false
        qt6ctProc.running = true
    }

    function _startGtkSync(themeName: string): void {
        gtkSettingsProc.themeName = themeName
        gtkSettingsProc.running = false
        gtkSettingsProc.running = true
    }

    // Keep currentTheme as the family the user chose; resolve the installed
    // sibling for the active light/dark scheme before touching the system.
    function _apply(themeName: string, skipRestart: bool): void {
        variantProc.themeName = themeName
        variantProc.skipRestart = skipRestart
        variantProc.running = false
        variantProc.running = true
    }

    Process {
        id: variantProc
        property string themeName: ""
        property bool skipRestart: false
        property string resolved: ""
        command: ["/usr/bin/bash", Quickshell.shellPath("scripts/colors/icon-theme-for-mode.sh"),
            variantProc.themeName, Appearance.m3colors.darkmode ? "dark" : "light"]
        onStarted: variantProc.resolved = ""
        stdout: SplitParser {
            onRead: line => variantProc.resolved = line.trim()
        }
        onExited: (exitCode, exitStatus) => {
            gsettingsSetProc.themeName = exitCode === 0 && variantProc.resolved.length > 0
                ? variantProc.resolved : variantProc.themeName
            gsettingsSetProc.skipRestart = variantProc.skipRestart
            gsettingsSetProc.running = false
            gsettingsSetProc.running = true
        }
    }

    Process {
        id: gsettingsSetProc
        property string themeName: ""
        property bool skipRestart: false
        property bool startObserved: false
        command: ["/usr/bin/gsettings", "set", "org.gnome.desktop.interface", "icon-theme", gsettingsSetProc.themeName]
        onRunningChanged: {
            if (gsettingsSetProc.running) {
                gsettingsSetProc.startObserved = false
                return
            }
            if (gsettingsSetProc.startObserved)
                return

            console.warn("[IconThemeService] gsettings failed to start; continuing icon theme sync")
            root._startKdeGlobalsSync(gsettingsSetProc.themeName, gsettingsSetProc.skipRestart)
        }
        onStarted: gsettingsSetProc.startObserved = true
        onExited: (exitCode, exitStatus) => {
            _log("[IconThemeService] gsettings set exited:", exitCode, "theme:", gsettingsSetProc.themeName)
            root._startKdeGlobalsSync(gsettingsSetProc.themeName, gsettingsSetProc.skipRestart)
        }
    }

    // Rust test path: update KDE, qt5ct, qt6ct and GTK config files in one
    // process. If it fails, fall back to the existing Python chain.
    Process {
        id: nativeIconSyncProc
        property string themeName: ""
        property bool skipRestart: false
        command: [root.nativeDispatchPath, "desktop-icons", nativeIconSyncProc.themeName]

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root._log("[IconThemeService] native icon sync succeeded:", nativeIconSyncProc.themeName)
                if (!nativeIconSyncProc.skipRestart)
                    root.queueRestart()
                return
            }

            console.warn("[IconThemeService] native icon sync failed; falling back to legacy path:", exitCode, exitStatus)
            root._startLegacyKdeGlobalsSync(
                nativeIconSyncProc.themeName,
                nativeIconSyncProc.skipRestart)
        }
    }

    // Update kdeglobals [Icons] section properly
    Process {
        id: kdeGlobalsUpdateProc
        property string themeName: ""
        property bool skipRestart: false
        property bool startObserved: false
        command: [
            "/usr/bin/python3",
            "-c",
            `
import configparser
import os

config_path = os.path.expanduser("~/.config/kdeglobals")
theme = "${kdeGlobalsUpdateProc.themeName}"

config = configparser.ConfigParser()
config.optionxform = str  # Preserve case

if os.path.exists(config_path):
    config.read(config_path)

if "Icons" not in config:
    config["Icons"] = {}

config["Icons"]["Theme"] = theme

with open(config_path, "w") as f:
    config.write(f, space_around_delimiters=False)
`
        ]
        onRunningChanged: {
            if (kdeGlobalsUpdateProc.running) {
                kdeGlobalsUpdateProc.startObserved = false
                return
            }
            if (kdeGlobalsUpdateProc.startObserved)
                return

            console.warn("[IconThemeService] kdeglobals updater failed to start; continuing icon theme sync")
            root._continueAfterKdeGlobals(kdeGlobalsUpdateProc.themeName, kdeGlobalsUpdateProc.skipRestart)
        }
        onStarted: kdeGlobalsUpdateProc.startObserved = true
        onExited: (exitCode, exitStatus) => {
            root._continueAfterKdeGlobals(kdeGlobalsUpdateProc.themeName, kdeGlobalsUpdateProc.skipRestart)
        }
    }

    // Use kwriteconfig6 for better KDE integration (if available)
    Process {
        id: kwriteconfigProc
        property string themeName: ""
        property bool skipRestart: false
        property bool startObserved: false
        command: [
            "/usr/bin/kwriteconfig6",
            "--file", "kdeglobals",
            "--group", "Icons",
            "--key", "Theme",
            kwriteconfigProc.themeName
        ]
        onRunningChanged: {
            if (kwriteconfigProc.running) {
                kwriteconfigProc.startObserved = false
                return
            }
            if (kwriteconfigProc.startObserved)
                return

            _log("[IconThemeService] kwriteconfig6 unavailable; continuing with Qt/GTK sync")
            root._startQtSync(kwriteconfigProc.themeName)
        }
        onStarted: kwriteconfigProc.startObserved = true
        onExited: (exitCode, exitStatus) => {
            _log("[IconThemeService] kwriteconfig exited:", exitCode, "theme:", kwriteconfigProc.themeName)
            root._startQtSync(kwriteconfigProc.themeName)
        }
    }

    // Sync icon theme to qt5ct
    Process {
        id: qt5ctProc
        property string themeName: ""
        command: [
            "/usr/bin/python3",
            "-c",
            `
import configparser
import os

theme = "${qt5ctProc.themeName}"
config_path = os.path.expanduser("~/.config/qt5ct/qt5ct.conf")

if not os.path.exists(config_path):
    os.makedirs(os.path.dirname(config_path), exist_ok=True)
    with open(config_path, "w") as f:
        f.write("[Appearance]\\nicon_theme=" + theme + "\\n")
else:
    config = configparser.ConfigParser()
    config.optionxform = str
    config.read(config_path)
    if "Appearance" not in config:
        config["Appearance"] = {}
    config["Appearance"]["icon_theme"] = theme
    with open(config_path, "w") as f:
        config.write(f, space_around_delimiters=False)
`
        ]
        onExited: (exitCode, exitStatus) => {
            _log("[IconThemeService] qt5ct updated:", exitCode === 0 ? "success" : "failed")
        }
    }

    // Sync icon theme to qt6ct
    Process {
        id: qt6ctProc
        property string themeName: ""
        property bool startObserved: false
        command: [
            "/usr/bin/python3",
            "-c",
            `
import configparser
import os

theme = "${qt6ctProc.themeName}"
config_path = os.path.expanduser("~/.config/qt6ct/qt6ct.conf")

if not os.path.exists(config_path):
    os.makedirs(os.path.dirname(config_path), exist_ok=True)
    with open(config_path, "w") as f:
        f.write("[Appearance]\\nicon_theme=" + theme + "\\n")
else:
    config = configparser.ConfigParser()
    config.optionxform = str
    config.read(config_path)
    if "Appearance" not in config:
        config["Appearance"] = {}
    config["Appearance"]["icon_theme"] = theme
    with open(config_path, "w") as f:
        config.write(f, space_around_delimiters=False)
`
        ]
        onRunningChanged: {
            if (qt6ctProc.running) {
                qt6ctProc.startObserved = false
                return
            }
            if (qt6ctProc.startObserved)
                return

            console.warn("[IconThemeService] qt6ct updater failed to start; continuing with GTK sync")
            root._startGtkSync(qt6ctProc.themeName)
        }
        onStarted: qt6ctProc.startObserved = true
        onExited: (exitCode, exitStatus) => {
            _log("[IconThemeService] qt6ct updated:", exitCode === 0 ? "success" : "failed")
            root._startGtkSync(qt6ctProc.themeName)
        }
    }

    // Sync icon theme to GTK settings.ini (gtk-3.0 and gtk-4.0)
    Process {
        id: gtkSettingsProc
        property string themeName: ""
        command: [
            "/usr/bin/python3",
            "-c",
            `
import configparser
import datetime
import os
import shutil

theme = "${gtkSettingsProc.themeName}"

for subdir in ["gtk-3.0", "gtk-4.0"]:
    path = os.path.expanduser(f"~/.config/{subdir}/settings.ini")
    os.makedirs(os.path.dirname(path), exist_ok=True)

    config = configparser.ConfigParser(interpolation=None)
    config.optionxform = str
    valid = False
    if os.path.isfile(path):
        try:
            config.read(path)
            valid = config.has_section("Settings")
        except configparser.Error:
            valid = False

    if not valid:
        if os.path.isfile(path) and os.path.getsize(path) > 0:
            stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
            shutil.copy2(path, f"{path}.corrupt-{stamp}.bak")
        config = configparser.ConfigParser(interpolation=None)
        config.optionxform = str
        config["Settings"] = {}

    config["Settings"]["gtk-icon-theme-name"] = theme
    with open(path, "w") as f:
        config.write(f, space_around_delimiters=False)
`
        ]
        onExited: (exitCode, exitStatus) => {
            _log("[IconThemeService] GTK settings.ini updated:", exitCode === 0 ? "success" : "failed")
        }
    }

    Process {
        id: currentThemeProc
        command: ["/usr/bin/gsettings", "get", "org.gnome.desktop.interface", "icon-theme"]
        stdout: SplitParser {
            onRead: line => {
                root.currentTheme = line.trim().replace(/'/g, "")
            }
        }
    }

    Process {
        id: listThemesProc
        command: [
            "/usr/bin/find",
            "/usr/share/icons",
            `${FileUtils.trimFileProtocol(Directories.home)}/.local/share/icons`,
            "-maxdepth",
            "1",
            "-type",
            "d"
        ]

        property var themes: []

        stdout: SplitParser {
            onRead: line => {
                const p = line.trim()
                if (!p)
                    return
                const parts = p.split("/")
                const name = parts[parts.length - 1]
                if (!name)
                    return
                if (["icons", "default", "hicolor", "locolor"].includes(name))
                    return
                if (name === "cursors")
                    return
                listThemesProc.themes.push(name)
            }
        }

        onRunningChanged: {
            if (running)
                return

            const uniqueSorted = Array.from(new Set(themes)).sort()
            root.availableThemes = uniqueSorted
            root._themesLoaded = true
            themes = []
        }
    }
}
