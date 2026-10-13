pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * Internal Hadalis to-do persistence backend.
 *
 * Used only through the Todo singleton facade.
 *
 * Simple to-do list manager with two-way text file sync.
 *
 * Backend: todo.json (JSON array of {content, done} objects)
 * Mirror:  todo.txt  (human-editable markdown-checkbox format)
 *
 * todo.txt format:
 *   - [ ] Undone task
 *   - [x] Done task
 *   # Comment (ignored)
 *   Plain text (treated as undone task)
 *
 * Sync model:
 *   UI action  -> update list -> write json + txt
 *   txt edited -> parse       -> update list -> write json (skip txt to avoid loop)
 *
 * Implementation note:
 *   FileView.setText() caches content internally; subsequent reload()+text()
 *   returns the cached buffer, NOT fresh disk content.  To read the actual
 *   file after an external edit we run `cat` via Process + StdioCollector,
 *   which always reads from disk.
 */
Scope {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    property string filePath: Directories.todoPath
    property string txtFilePath: Directories.todoTxtPath
    property var list: []
    property bool ready: false

    // Guard flag: when true, skip writing txt back (because we're
    // processing a txt change and the file is already up-to-date)
    property bool _suppressTxtWrite: false

    // Startup guard: ignore txt onFileChanged until initial write settles.
    // Without this, the watcher can catch a truncated/empty intermediate state
    // from the initial setText() and destroy the list.
    property bool _startupLock: true

    // Fresh-start directory creation is asynchronous. Keep UI edits in memory
    // until storage is ready, then persist the latest list once.
    property bool _storageInitializing: false

    // Only saved()/saveFailed() complete a write. Reads must never replace
    // edits while their canonical JSON is still being persisted.
    property bool _jsonSaving: false
    property bool _jsonSaveQueued: false
    property bool _jsonSaveFailed: false
    property bool _refreshQueued: false
    property string _lastSavedJson: ""
    property string _durableJson: "[]"
    signal itemsPersisted(var savedItems)
    function getDurableItems() { return JSON.parse(root._durableJson) }
    property string _jsonWriteSnapshot: ""
    property FileView _jsonWriter: null
    property string errorMessage: ""
    readonly property string errorCode: root._jsonSaveFailed ? "INTERNAL_SAVE_FAILED" : ""

    // Migration reads the JSON file directly. Expose whether an in-memory edit
    // is still being persisted so the facade cannot snapshot a stale revision.
    readonly property bool persistenceBusy:
        root._storageInitializing || root._jsonSaving || root._jsonSaveQueued
            || root._jsonSaveFailed

    // --- Public API ---

    function _normalizeList(value) {
        if (!Array.isArray(value)) return []
        const normalized = []
        for (let i = 0; i < value.length; i++) {
            const item = value[i]
            if (!item || typeof item !== "object" || Array.isArray(item))
                continue
            const clean = {
                "content": String(item.content ?? ""),
                "done": item.done === true
            }
            if (typeof item.id === "string") clean.id = item.id
            if (typeof item.notes === "string") clean.notes = item.notes
            for (const field of ["description","date","startTime","endTime","startDate","endDate"])
                if(typeof item[field] === "string")clean[field]=item[field]
            if(typeof item.allDay === "boolean")clean.allDay=item.allDay
            // Keep historical task metadata without restoring Agenda linking.
            if (item.agenda?.version === 1 && typeof item.agenda.key === "string"
                    && /^agenda-[a-z0-9-]{8,96}$/.test(item.agenda.key)) {
                clean.agenda = Object.assign({},item.agenda)
            }
            normalized.push(clean)
        }
        return normalized
    }

    function addItem(item) {
        if (!root.ready) return false
        const normalized = root._normalizeList([item])
        if (normalized.length === 0) return false
        list.push(normalized[0])
        root.list = list.slice(0)
        _persistAll()
        return true
    }

    function addTask(desc) {
        return addItem({ "content": desc, "done": false })
    }

    function markDone(index) {
        if (!root.ready) return false
        if (index >= 0 && index < list.length) {
            list[index].done = true
            root.list = list.slice(0)
            _persistAll()
            return true
        }
        return false
    }

    function markUnfinished(index) {
        if (!root.ready) return false
        if (index >= 0 && index < list.length) {
            list[index].done = false
            root.list = list.slice(0)
            _persistAll()
            return true
        }
        return false
    }

    function deleteItem(index) {
        if (!root.ready) return false
        if (index >= 0 && index < list.length) {
            list.splice(index, 1)
            root.list = list.slice(0)
            _persistAll()
            return true
        }
        return false
    }

    function refresh() {
        if (root.persistenceBusy) {
            root._refreshQueued = true
            if (root._jsonSaveFailed && !root._jsonSaving)
                root._persistAll()
            return
        }
        root.ready = false
        todoFileView.reload()
    }

    function retrySave() {
        if (!root.ready) return false
        root._persistAll()
        return true
    }

    // --- Persistence helpers ---

    function _saveJson() {
        if (root._storageInitializing)
            return
        if (root._jsonSaving) {
            root._jsonSaveQueued = true
            return
        }
        const serialized = JSON.stringify(root.list)
        root._jsonSaveQueued = false
        if (!root._jsonSaveFailed && serialized === root._lastSavedJson) {
            root._finishQueuedRefresh()
            return
        }
        root._jsonWriteSnapshot = serialized
        root._jsonSaving = true
        try {
            // A failed setText updates FileView's cache, but not disk. An
            // explicit retry of the same bytes needs a fresh write-only view.
            if (todoFileView.text() === serialized) {
                const writer = uncachedJsonWriter.createObject(root, {path: root.filePath})
                if (!writer) throw new Error("Could not create Todo writer")
                root._jsonWriter = writer
                writer.setText(serialized)
            } else {
                todoFileView.setText(serialized)
            }
        } catch (error) {
            root._finishJsonSave(String(error))
        }
    }

    function _finishQueuedRefresh() {
        if (root._refreshQueued && !root.persistenceBusy) {
            root._refreshQueued = false
            Qt.callLater(() => root.refresh())
        }
    }

    function _finishJsonSave(error) {
        if (!root._jsonSaving) return
        if (error.length === 0) {
            root._lastSavedJson = root._jsonWriteSnapshot
            root._durableJson = root._jsonWriteSnapshot
            root._jsonSaveFailed = false
            root.errorMessage = ""
        } else {
            root._jsonSaveFailed = true
            root.errorMessage = "Could not save To-do. Your changes remain in memory; retry after restoring write access."
            console.warn("[Todo] Failed to save JSON:", error)
        }
        root._jsonSaving = false
        if(error.length===0)root.itemsPersisted(root.getDurableItems())
        if (error.length === 0 && root._jsonSaveQueued) {
            // Keep the queued flag until the follow-up starts: migration must
            // not observe a false idle interval with an older disk revision.
            Qt.callLater(() => root._saveJson())
        } else {
            root._jsonSaveQueued = false
            root._finishQueuedRefresh()
        }
    }

    function _finishUncachedSave(writer, error) {
        if (root._jsonWriter === writer) {
            root._jsonWriter = null
            root._finishJsonSave(error)
        }
        writer.destroy()
    }

    Component {
        id: uncachedJsonWriter
        FileView {
            preload: false
            onSaved: root._finishUncachedSave(this, "")
            onSaveFailed: error => root._finishUncachedSave(this, String(error))
        }
    }

    function _persistAll() {
        if (root._storageInitializing)
            return
        root._saveJson()
        if (!root._suppressTxtWrite) {
            _writeTxt()
        }
    }

    function _writeTxt() {
        let lines = []
        for (let i = 0; i < root.list.length; i++) {
            const item = root.list[i]
            const checkbox = item.done ? "[x]" : "[ ]"
            lines.push("- " + checkbox + " " + (item.content ?? ""))
        }
        txtFileView.setText(lines.join("\n") + "\n")
    }

    function _finishMissingInitialization(): void {
        root._storageInitializing = false
        root.ready = true
        root._persistAll()
        startupUnlock.start()
    }

    function _ensureStorageDirectories(): void {
        const jsonParent = root.filePath.substring(0, root.filePath.lastIndexOf('/'))
        const txtParent = root.txtFilePath.substring(0, root.txtFilePath.lastIndexOf('/'))
        const dirs = []
        if (jsonParent.length > 0)
            dirs.push(jsonParent)
        if (txtParent.length > 0 && txtParent !== jsonParent)
            dirs.push(txtParent)
        if (dirs.length === 0) {
            root._finishMissingInitialization()
            return
        }
        if (todoInitDirProc.running)
            return
        todoInitDirProc.command = ["/usr/bin/mkdir", "-p"].concat(dirs)
        todoInitDirProc.attempted = true
        todoInitDirProc.running = true
    }

    // --- Text file parsing ---

    function _parseTxt(text) {
        if (!text || text.trim().length === 0) return []

        const lines = text.split("\n")
        let tasks = []
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim()
            // Skip empty lines and comments
            if (line.length === 0 || line.startsWith("#")) continue

            let content = ""
            let done = false

            // Match: - [x] text  or  [x] text
            const doneMatch = line.match(/^(?:-\s*)?\[x\]\s*(.*)$/i)
            if (doneMatch) {
                content = doneMatch[1].trim()
                done = true
            } else {
                // Match: - [ ] text  or  [ ] text
                const undoneMatch = line.match(/^(?:-\s*)?\[\s?\]\s*(.*)$/)
                if (undoneMatch) {
                    content = undoneMatch[1].trim()
                    done = false
                } else {
                    // Match: - text (dash prefix, no checkbox)
                    const dashMatch = line.match(/^-\s+(.+)$/)
                    if (dashMatch) {
                        content = dashMatch[1].trim()
                        done = false
                    } else {
                        // Plain text line = undone task
                        content = line
                        done = false
                    }
                }
            }

            if (content.length > 0) {
                tasks.push({ "content": content, "done": done })
            }
        }
        return tasks
    }

    // --- Startup ---

    Component.onCompleted: {
        refresh()
    }

    // --- JSON FileView (canonical backend) ---

    FileView {
        id: todoFileView
        path: Qt.resolvedUrl(root.filePath)
        onLoaded: {
            if (root.persistenceBusy) return

            const fileContents = todoFileView.text()
            try {
                root.list = root._normalizeList(JSON.parse(fileContents))
            } catch (e) {
                console.log("[Todo] JSON parse error, resetting list:", e)
                root.list = []
            }
            root.ready = true
            root._lastSavedJson = fileContents
            root._durableJson = JSON.stringify(root.list)
            _log("[Todo] JSON loaded,", root.list.length, "tasks")
            // Generate txt mirror from loaded JSON, then unlock after settling
            root._writeTxt()
            startupUnlock.start()
        }
        onSaved: root._finishJsonSave("")
        onSaveFailed: error => root._finishJsonSave(String(error))
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                console.log("[Todo] JSON not found, creating new file.")
                root.list = []
                root._storageInitializing = true
                root._ensureStorageDirectories()
            } else {
                console.log("[Todo] Error loading JSON:", error)
            }
        }
    }

    Process {
        id: todoInitDirProc
        property bool attempted: false
        property bool startObserved: false
        running: false

        onRunningChanged: {
            if (todoInitDirProc.running) {
                todoInitDirProc.startObserved = false
                return
            }
            if (!todoInitDirProc.attempted || todoInitDirProc.startObserved)
                return
            todoInitDirProc.attempted = false
            root._storageInitializing = false
            root.ready = true
            console.warn("[Todo] Failed to start storage directory creation")
            root._persistAll()
            startupUnlock.start()
        }

        onStarted: todoInitDirProc.startObserved = true

        onExited: (exitCode, exitStatus) => {
            todoInitDirProc.attempted = false
            if (exitCode === 0) {
                root._finishMissingInitialization()
            } else {
                root._storageInitializing = false
                root.ready = true
                console.warn("[Todo] Failed to create storage directories, exit code:", exitCode)
                root._persistAll()
                startupUnlock.start()
            }
        }
    }

    // --- TXT FileView (write + watch) ---
    // setText() for writing; onFileChanged for external edit detection.
    // Never call text()/reload() on this — see txtCatProc below.

    FileView {
        id: txtFileView
        path: Qt.resolvedUrl(root.txtFilePath)
        watchChanges: true
        onFileChanged: {
            if (!root._startupLock) {
                txtDebounce.restart()
            }
        }
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                _log("[Todo] txt not found, will be created on next list change")
            }
        }
    }

    // --- Startup unlock timer ---

    Timer {
        id: startupUnlock
        interval: 800
        repeat: false
        onTriggered: {
            root._startupLock = false
            _log("[Todo] txt sync unlocked")
        }
    }

    // --- Debounce for external txt edits ---

    Timer {
        id: txtDebounce
        interval: 300
        repeat: false
        onTriggered: {
            // Read actual disk content via Process (avoids FileView stale buffer)
            txtCatProc.running = true
        }
    }

    // --- Process to read txt from disk (bypasses FileView cache) ---

    Process {
        id: txtCatProc
        running: false
        command: ["cat", root.txtFilePath]
        stdout: StdioCollector {
            onStreamFinished: {
                const txtContent = text ?? ""
                const parsed = root._parseTxt(txtContent)

                if (root._listsEqual(root.list, parsed)) return

                _log("[Todo] txt changed externally:", parsed.length, "tasks")
                root._suppressTxtWrite = true
                // TXT has no identity fields. Preserve linked metadata when a
                // checkbox/text item still matches; never resurrect deleted tasks.
                const remaining=root.list.slice()
                root.list=parsed.map(item=>{
                    const index=remaining.findIndex(old=>old.content===item.content)
                    return index>=0?Object.assign({},remaining.splice(index,1)[0],item):item
                })
                root._saveJson()
                root._suppressTxtWrite = false
            }
        }
    }

    // --- Comparison helper ---

    function _listsEqual(a, b) {
        if (!a || !b) return false
        if (a.length !== b.length) return false
        for (let i = 0; i < a.length; i++) {
            if ((a[i].content ?? "") !== (b[i].content ?? "")) return false
            if (!!a[i].done !== !!b[i].done) return false
        }
        return true
    }
}
