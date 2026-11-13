pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * PackageSearch — Async package manager search service.
 *
 * Searches pacman repos and AUR via yay/paru for packages matching a query.
 * Results are parsed into structured objects with name, version, repo,
 * description, and installed status.
 *
 * Usage:
 *   PackageSearch.search("vesktop")
 *   // results available in PackageSearch.results after search completes
 */
Singleton {
    id: root

    property string query: ""
    property bool searching: false
    property var results: []
    property string error: ""

    // Debounce to avoid spamming package manager
    property int debounceMs: 300

    property int _requestGeneration: 0
    property string _searchStdout: ""
    property int _activeSearchGeneration: 0
    property string _pendingSearchQuery: ""
    property int _pendingSearchGeneration: 0
    property string _installedStdout: ""
    property int _activeInstalledGeneration: 0
    property string _pendingInstalledQuery: ""
    property int _pendingInstalledGeneration: 0

    function _safeTerminal(): string {
        const configured = (Config.options?.apps?.terminal ?? "kitty").trim()
        if (configured.length === 0)
            return "kitty"
        if (!/^[A-Za-z0-9._+-]+$/.test(configured))
            return "kitty"
        return configured
    }

    function _runTerminalScript(script: string, args): void {
        const command = ["/usr/bin/bash", "-lc", script + "\nprintf \"\\nPress Enter to close...\"\nread", "bash", ...(args ?? [])]
        const terminal = root._safeTerminal()
        if (terminal === "wezterm") {
            ShellExec.execDetachedArgs([terminal, "start", "--always-new-process", "--", ...command], "Run package action")
            return
        }
        ShellExec.execDetachedArgs([terminal, "-e", ...command], "Run package action")
    }

    function isSafePackageName(name: string): bool {
        const pkg = (name ?? "").trim()
        return pkg.length > 0 && /^[A-Za-z0-9@._+-]+$/.test(pkg)
    }

    function installPackage(name: string, preferAurHelper: bool): bool {
        const pkg = (name ?? "").trim()
        if (!root.isSafePackageName(pkg)) {
            Quickshell.execDetached(["/usr/bin/notify-send", Translation.tr("Install Package"),
                Translation.tr("Invalid package name"), "-a", "Shell"])
            return false
        }

        const script = preferAurHelper
            ? "if command -v yay &>/dev/null; then yay -S -- \"$1\"; elif command -v paru &>/dev/null; then paru -S -- \"$1\"; else sudo pacman -S -- \"$1\"; fi"
            : "sudo pacman -S -- \"$1\""
        root._runTerminalScript(script, [pkg])
        return true
    }

    function removePackage(name: string): bool {
        const pkg = (name ?? "").trim()
        if (!root.isSafePackageName(pkg)) {
            Quickshell.execDetached(["/usr/bin/notify-send", Translation.tr("Remove Package"),
                Translation.tr("Invalid package name"), "-a", "Shell"])
            return false
        }

        root._runTerminalScript("sudo pacman -Rns -- \"$1\"", [pkg])
        return true
    }

    function updateSystem(): void {
        root._runTerminalScript("if command -v yay &>/dev/null; then yay; elif command -v paru &>/dev/null; then paru; else sudo pacman -Syu; fi", [])
    }

    function _invalidatePendingRequests(): void {
        root._pendingSearchQuery = ""
        root._pendingSearchGeneration = 0
        root._pendingInstalledQuery = ""
        root._pendingInstalledGeneration = 0
    }

    function search(q: string): void {
        root.query = q.trim()
        if (root.query === "") {
            root._requestGeneration++
            root._invalidatePendingRequests()
            root.results = []
            root.searching = false
            root.error = ""
            _debounceTimer.stop()
            _searchProc.running = false
            _installedProc.running = false
            return
        }
        // Invalidate any visible completion from the previous query as soon as
        // the user types, rather than waiting for the debounce timer to fire.
        root._requestGeneration++
        root._invalidatePendingRequests()
        root.error = ""
        _debounceTimer.restart()
    }

    function clear(): void {
        root._requestGeneration++
        root._invalidatePendingRequests()
        root.query = ""
        root.results = []
        root.searching = false
        root.error = ""
        _debounceTimer.stop()
        _searchProc.running = false
        _installedProc.running = false
    }

    function _startSearchRequest(searchQuery: string, generation: int): void {
        root._activeSearchGeneration = generation
        root._searchStdout = ""
        _searchProc.command = ["/usr/bin/bash", "-lc",
            "if command -v yay &>/dev/null; then yay -Ss \"$1\" 2>/dev/null | head -200; elif command -v paru &>/dev/null; then paru -Ss \"$1\" 2>/dev/null | head -200; else pacman -Ss \"$1\" 2>/dev/null | head -200; fi",
            "bash", searchQuery
        ]
        _searchProc.running = true
    }

    function _queueSearchRequest(searchQuery: string, generation: int): void {
        if (_searchProc.running) {
            root._pendingSearchQuery = searchQuery
            root._pendingSearchGeneration = generation
            return
        }
        root._startSearchRequest(searchQuery, generation)
    }

    function _drainSearchQueue(): void {
        if (root._pendingSearchQuery.length === 0)
            return
        const pendingQuery = root._pendingSearchQuery
        const pendingGeneration = root._pendingSearchGeneration
        root._pendingSearchQuery = ""
        root._pendingSearchGeneration = 0
        Qt.callLater(() => {
            if (pendingGeneration !== root._requestGeneration)
                return
            root._startSearchRequest(pendingQuery, pendingGeneration)
        })
    }

    function _startInstalledRequest(searchQuery: string, generation: int): void {
        root._activeInstalledGeneration = generation
        root._installedStdout = ""
        _installedProc.command = ["/usr/bin/bash", "-lc",
            "pacman -Qs \"$1\" 2>/dev/null | head -100",
            "bash", searchQuery
        ]
        _installedProc.running = true
    }

    function _queueInstalledRequest(searchQuery: string, generation: int): void {
        if (_installedProc.running) {
            root._pendingInstalledQuery = searchQuery
            root._pendingInstalledGeneration = generation
            return
        }
        root._startInstalledRequest(searchQuery, generation)
    }

    function _drainInstalledQueue(): void {
        if (root._pendingInstalledQuery.length === 0)
            return
        const pendingQuery = root._pendingInstalledQuery
        const pendingGeneration = root._pendingInstalledGeneration
        root._pendingInstalledQuery = ""
        root._pendingInstalledGeneration = 0
        Qt.callLater(() => {
            if (pendingGeneration !== root._requestGeneration)
                return
            root._startInstalledRequest(pendingQuery, pendingGeneration)
        })
    }

    Timer {
        id: _debounceTimer
        interval: root.debounceMs
        onTriggered: {
            if (root.query === "") return
            const generation = root._requestGeneration
            root._pendingInstalledQuery = ""
            root._pendingInstalledGeneration = 0
            root.searching = true
            root.error = ""
            root._queueSearchRequest(root.query, generation)
        }
    }

    Process {
        id: _searchProc
        stdout: StdioCollector {
            id: _searchStdoutCollector
        }
        onExited: (exitCode, exitStatus) => {
            const generation = root._activeSearchGeneration
            const output = String(_searchStdoutCollector.text ?? "")
            root._activeSearchGeneration = 0
            if (generation === root._requestGeneration) {
                root.searching = false
                if (exitCode !== 0 && output.trim() === "") {
                    root.results = []
                } else {
                    root.results = root._parseResults(output)
                }
            }
            root._drainSearchQueue()
        }
    }

    // Timeout for slow searches
    Timer {
        id: _timeoutTimer
        interval: 15000
        running: _searchProc.running
        onTriggered: {
            const generation = root._activeSearchGeneration
            _searchProc.running = false
            if (generation === root._requestGeneration) {
                root.searching = false
                root.error = "Search timed out"
            }
        }
    }

    function _parseResults(output: string): list<var> {
        const lines = output.split("\n")
        const pkgs = []
        let i = 0
        while (i < lines.length) {
            const line = lines[i]
            // Package line format: "repo/name version [size] [installed]"
            // or AUR: "aur/name version (+votes popularity) [installed]"
            const pkgMatch = line.match(/^(\S+)\/(\S+)\s+(\S+)\s*(.*)$/)
            if (pkgMatch) {
                const repo = pkgMatch[1]
                const name = pkgMatch[2]
                const version = pkgMatch[3]
                const rest = pkgMatch[4] || ""
                const installed = /\(Installed\)/i.test(rest) || /\[installed\]/i.test(rest) || /\[Installed\]/i.test(rest)

                // Extract AUR popularity/votes if present
                const aurMeta = rest.match(/\(([+-]?\d+)\s+([\d.]+)\)/)
                const votes = aurMeta ? parseInt(aurMeta[1]) : 0
                const popularity = aurMeta ? parseFloat(aurMeta[2]) : 0

                // Next line is description (indented)
                let description = ""
                if (i + 1 < lines.length && lines[i + 1].match(/^\s+/)) {
                    description = lines[i + 1].trim()
                    i++
                }

                pkgs.push({
                    name: name,
                    version: version,
                    repo: repo,
                    description: description,
                    installed: installed,
                    votes: votes,
                    popularity: popularity,
                    isAur: repo === "aur"
                })
            }
            i++
        }
        return pkgs
    }

    // Search for installed packages only (for remove operations)
    function searchInstalled(q: string): void {
        root.query = q.trim()
        _debounceTimer.stop()
        if (root.query === "") {
            root._requestGeneration++
            root._invalidatePendingRequests()
            root.results = []
            root.searching = false
            root.error = ""
            _searchProc.running = false
            _installedProc.running = false
            return
        }
        const generation = ++root._requestGeneration
        root._pendingSearchQuery = ""
        root._pendingSearchGeneration = 0
        root.searching = true
        root.error = ""
        root._queueInstalledRequest(root.query, generation)
    }

    Process {
        id: _installedProc
        stdout: StdioCollector {
            id: _installedStdoutCollector
        }
        onExited: (exitCode, exitStatus) => {
            const generation = root._activeInstalledGeneration
            const output = String(_installedStdoutCollector.text ?? "")
            root._activeInstalledGeneration = 0
            if (generation === root._requestGeneration) {
                root.searching = false
                if (exitCode !== 0 && output.trim() === "") {
                    root.results = []
                } else {
                    // Parse results and mark all as installed
                    const parsed = root._parseResults(output)
                    root.results = parsed.map(pkg => Object.assign({}, pkg, { installed: true }))
                }
            }
            root._drainInstalledQueue()
        }
    }

    IpcHandler {
        target: "packageSearch"

        function search(query: string): string {
            root.search(query)
            return "searching: " + query
        }

        function results(): string {
            return root.results.map(p =>
                `${p.repo}/${p.name} ${p.version}${p.installed ? " [installed]" : ""}\t${p.description}`
            ).join("\n")
        }
    }
}
