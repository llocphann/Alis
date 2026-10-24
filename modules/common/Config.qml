pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import "PanelFamilyPolicy.js" as FamilyPolicy
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property string filePath: Directories.shellConfigPath
    property alias options: configOptionsJsonAdapter
    property bool ready: false
    property int revision: 0
    property bool isSettingsProcess: (Quickshell.env("ALIS_STANDALONE_WINDOW") ?? "") === "1"
    property int readWriteDelay: 50 // milliseconds
    property bool blockWrites: false
    // Custom widget data stored outside JsonAdapter to avoid VME crash on property var
    property var customWidgetData: ({})
    property bool customWidgetDataSynced: false

    signal configChanged

    function _bumpRevision(): void {
        root.revision = (root.revision + 1) % 2147483647;
    }

    function flushWrites(): void {
        // Keep raw-save intent when this flush is queued behind another save.
        root._pendingRawWrite = true;
        fileWriteTimer.stop();
        fileReloadTimer.stop();
        if (!root.ready) {
            root._pendingWrite = true;
            return;
        }
        if (root._writeInFlight || root._rawWriteView !== null) {
            root._pendingWrite = true;
            return;
        }
        root._prepareCustomInject();
        root._pendingWrite = false;
        root._writeInFlight = true;
        root._writeRetries = 0;
        root._pendingRawWrite = false;
        writeFlightGuard.restart();
        root._writeMirrorToDisk();
    }

    function _applyNestedKey(nestedKey, value) {
        let keys = [];
        if (Array.isArray(nestedKey)) {
            keys = nestedKey;
        } else if (typeof nestedKey === "string") {
            keys = nestedKey.split(".");
        } else {
            console.warn("[Config] setNestedValue called with invalid nestedKey:", nestedKey);
            return;
        }

        if (keys.length === 0) {
            console.warn("[Config] setNestedValue called with empty key");
            return;
        }

        let convertedValue = value;
        if (typeof value === "string") {
            let trimmed = value.trim();
            if (trimmed === "true" || trimmed === "false" || !isNaN(Number(trimmed))) {
                try {
                    convertedValue = JSON.parse(trimmed);
                } catch (e) {
                    convertedValue = value;
                }
            }
        }

        // Route custom widget paths to standalone property (outside adapter)
        if (keys.length >= 3 && keys[0] === "background" && keys[1] === "widgets" && keys[2] === "custom") {
            const subKeys = keys.slice(3);
            if (subKeys.length === 0) {
                root.customWidgetData = (typeof convertedValue === "object" && convertedValue !== null) ? convertedValue : {};
                root._customSnapshotForInject = root._cloneObject(root.customWidgetData);
                root._pendingCustomInject = root._hasObjectKeys(root._customSnapshotForInject);
                return;
            }
            let data = {};
            try {
                data = JSON.parse(JSON.stringify(root.customWidgetData ?? {}));
            } catch (e) {
                data = {};
            }
            let obj = data;
            for (let i = 0; i < subKeys.length - 1; ++i) {
                if (!obj[subKeys[i]] || typeof obj[subKeys[i]] !== "object")
                    obj[subKeys[i]] = {};
                obj = obj[subKeys[i]];
            }
            obj[subKeys[subKeys.length - 1]] = convertedValue;
            root.customWidgetData = data;
            root._customSnapshotForInject = root._cloneObject(data);
            root._pendingCustomInject = root._hasObjectKeys(root._customSnapshotForInject);
            return;
        }

        let obj = root.options;
        for (let i = 0; i < keys.length - 1; ++i) {
            if (!obj[keys[i]] || typeof obj[keys[i]] !== "object") {
                obj[keys[i]] = {};
            }
            obj = obj[keys[i]];
        }

        const lastKey = keys[keys.length - 1];
        const isPlainObject = convertedValue !== null && typeof convertedValue === "object" && !Array.isArray(convertedValue);
        if (isPlainObject && root._isQtObject(obj[lastKey])) {
            root._assignObjectInto(obj[lastKey], convertedValue);
        } else {
            obj[lastKey] = convertedValue;
        }
    }

    function _isQtObject(v) {
        return v !== null && typeof v === "object" && v.objectName !== undefined;
    }

    function _assignObjectInto(target, value) {
        const ks = Object.keys(value);
        for (let i = 0; i < ks.length; ++i) {
            const k = ks[i];
            const v = value[k];
            if (v !== null && typeof v === "object" && !Array.isArray(v) && root._isQtObject(target[k])) {
                root._assignObjectInto(target[k], v);
            } else {
                target[k] = v;
            }
        }
    }

    function _recordPendingMutation(nestedKey, value): void {
        if (!root._reloadInFlight && !root._writeInFlight && root._rawWriteView === null)
            return;
        const path = Array.isArray(nestedKey) ? nestedKey.join(".") : String(nestedKey);
        if (root._reloadInFlight) {
            let overlay = root._cloneObject(root._reloadOverlay);
            overlay[path] = value;
            root._reloadOverlay = overlay;
        }
        if (root._writeInFlight || root._rawWriteView !== null) {
            let overlay = root._cloneObject(root._writeOverlay);
            overlay[path] = value;
            root._writeOverlay = overlay;
        }
    }

    function _beginLocalMutation(): void {
        // A queued reload can be cancelled, but a reload() already handed to
        // FileView is asynchronous. Record mutations made while that read is
        // in flight so onLoaded can reapply them over its older snapshot.
        fileReloadTimer.stop();
        root._pendingReload = false;
    }

    function _reconcileMandatoryPanels(): void {
        const current=Array.from(root.options?.enabledPanels ?? [])
        const required=FamilyPolicy.reconcileMandatory(root.options?.panelFamily,current)
        if(JSON.stringify(current)===JSON.stringify(required))return
        root._recordPendingMutation("enabledPanels",required)
        root._applyNestedKey("enabledPanels",required)
        root._applyToMirror("enabledPanels",required)
        fileWriteTimer.restart()
    }

    function setNestedValue(nestedKey, value) {
        _beginLocalMutation();
        _recordPendingMutation(nestedKey, value);
        _applyNestedKey(nestedKey, value);
        _applyToMirror(nestedKey, value);
        _reconcileMandatoryPanels();
        fileWriteTimer.restart();
        root._bumpRevision();
        root.configChanged();
    }

    function setNestedValues(updates) {
        if (!updates || typeof updates !== "object")
            return;
        const paths = Object.keys(updates);
        if (paths.length > 0)
            _beginLocalMutation();
        for (let i = 0; i < paths.length; ++i) {
            _recordPendingMutation(paths[i], updates[paths[i]]);
            _applyNestedKey(paths[i], updates[paths[i]]);
            _applyToMirror(paths[i], updates[paths[i]]);
        }
        if (paths.length > 0) {
            _reconcileMandatoryPanels();
            fileWriteTimer.restart();
            root._bumpRevision();
            root.configChanged();
        }
    }

    function _applyToMirror(nestedKey, value): void {
        let keys = Array.isArray(nestedKey) ? nestedKey : String(nestedKey).split(".");
        if (keys.length === 0) return;
        if (keys.length >= 3 && keys[0] === "background" && keys[1] === "widgets" && keys[2] === "custom") return;
        let obj = root._jsonMirror;
        let schema = root.options;
        for (let i = 0; i < keys.length - 1; i++) {
            if (!obj[keys[i]] || typeof obj[keys[i]] !== "object")
                obj[keys[i]] = {};
            obj = obj[keys[i]];
            schema = (schema !== null && typeof schema === "object") ? schema[keys[i]] : undefined;
        }

        const lastKey = keys[keys.length - 1];
        const isPlainObject = value !== null && typeof value === "object" && !Array.isArray(value);
        if (isPlainObject && root._isQtObject(schema?.[lastKey])) {
            if (!obj[lastKey] || typeof obj[lastKey] !== "object" || Array.isArray(obj[lastKey]))
                obj[lastKey] = {};
            root._mergeIntoMirror(obj[lastKey], value, schema[lastKey]);
        } else {
            obj[lastKey] = value;
        }
    }

    function _mergeIntoMirror(target, value, schemaNode): void {
        const ks = Object.keys(value);
        for (let i = 0; i < ks.length; ++i) {
            const k = ks[i];
            const v = value[k];
            const isPlainObject = v !== null && typeof v === "object" && !Array.isArray(v);
            if (isPlainObject && root._isQtObject(schemaNode?.[k])) {
                if (!target[k] || typeof target[k] !== "object" || Array.isArray(target[k]))
                    target[k] = {};
                root._mergeIntoMirror(target[k], v, schemaNode[k]);
            } else {
                target[k] = v;
            }
        }
    }

    function getNestedValue(nestedKey, fallback) {
        let keys = [];
        if (Array.isArray(nestedKey)) {
            keys = nestedKey;
        } else if (typeof nestedKey === "string") {
            keys = nestedKey.split(".");
        } else {
            return fallback;
        }

        if (keys.length === 0)
            return fallback;

        root.revision;
        let obj = root.options;
        let startIndex = 0;
        if (keys.length >= 3 && keys[0] === "background" && keys[1] === "widgets" && keys[2] === "custom") {
            obj = root.customWidgetData;
            startIndex = 3;
        }

        for (let i = startIndex; i < keys.length; ++i) {
            if (obj === undefined || obj === null)
                return fallback;
            obj = obj[keys[i]];
        }
        return (obj === undefined || obj === null) ? fallback : obj;
    }

    function _syncVarProperties(): void {
        let text = "";
        try {
            text = configFileView.text();
        } catch (e) {}
        if (!text || text.length === 0) {
            try {
                rawConfigReader.reload();
                text = rawConfigReader.text();
            } catch (e) {}
        }
        try {
            const raw = JSON.parse(text);
            root.customWidgetData = raw?.background?.widgets?.custom ?? {};
            root.customWidgetDataSynced = true;
        } catch (e) {
            root.customWidgetDataSynced = false;
        }
    }

    property bool _writeInFlight: false
    property FileView _rawWriteView: null
    property bool _pendingWrite: false
    property bool _pendingRawWrite: false
    property bool _pendingCustomInject: false
    property bool _pendingReload: false
    property bool _reloadInFlight: false
    property var _reloadOverlay: ({})
    property var _writeOverlay: ({})
    property int _writeRetries: 0

    function _endWriteFlight(reason: string): void {
        writeFlightGuard.stop();
        const overlay = root._writeOverlay;
        root._writeOverlay = ({});
        root._writeInFlight = false;
        root._writeRetries = 0;
        // FileView deserializes the saved snapshot before emitting onSaved.
        // Local edits made during that save must remain authoritative, just
        // like mutations made during a reload of an older disk snapshot.
        const paths = Object.keys(overlay);
        for (let i = 0; i < paths.length; ++i) {
            root._applyNestedKey(paths[i], overlay[paths[i]]);
            root._applyToMirror(paths[i], overlay[paths[i]]);
        }
        if (paths.length > 0) {
            root._pendingWrite = true;
            root._pendingReload = false;
        }
        if (reason.length > 0)
            console.warn("[Config] write flight released:", reason);
        if (root._pendingCustomInject) {
            root._pendingCustomInject = false;
            customInjectTimer.restart();
            return;
        }
        if (root._pendingWrite) {
            root._pendingWrite = false;
            fileWriteTimer.restart();
            return;
        }
        if (root._pendingReload) {
            root._pendingReload = false;
            fileReloadTimer.restart();
        }
    }
    property var _customSnapshotForInject: ({})
    property var _jsonMirror: ({})
    property bool _styleMigrationWritePending: false

    function _cloneObject(obj: var): var {
        try {
            return JSON.parse(JSON.stringify(obj ?? {}));
        } catch (e) {
            return {};
        }
    }

    function _hasObjectKeys(obj: var): bool {
        return obj && typeof obj === "object" && Object.keys(obj).length > 0;
    }

    function _customDataForWrite(): var {
        if (root._hasObjectKeys(root.customWidgetData))
            return root._cloneObject(root.customWidgetData);
        try {
            const current = JSON.parse(configFileView.text());
            const currentCustom = current?.background?.widgets?.custom ?? {};
            if (root._hasObjectKeys(currentCustom))
                return root._cloneObject(currentCustom);
        } catch (e) {}
        try {
            rawConfigReader.reload();
            const raw = JSON.parse(rawConfigReader.text());
            const diskCustom = raw?.background?.widgets?.custom ?? {};
            if (root._hasObjectKeys(diskCustom))
                return root._cloneObject(diskCustom);
        } catch (e) {}
        return {};
    }

    function _prepareCustomInject(): void {
        root._customSnapshotForInject = root._customDataForWrite();
        root._pendingCustomInject = root._hasObjectKeys(root._customSnapshotForInject);
        if (root._pendingCustomInject && !root._hasObjectKeys(root.customWidgetData))
            root.customWidgetData = root._cloneObject(root._customSnapshotForInject);
    }

    function _finishRawWrite(view: FileView, reason: string): void {
        if (root._rawWriteView === view) {
            root._rawWriteView = null;
            root._endWriteFlight(reason);
        }
        view.destroy();
    }

    Component {
        id: uncachedRawWriter
        FileView {
            // A fresh write-only view submits even unchanged bytes. Comparing
            // the main view's cache cannot prove a successful disk save.
            preload: false
            blockWrites: root.blockWrites
            onSaved: root._finishRawWrite(this, "")
            onSaveFailed: error => root._finishRawWrite(this, `save failed (${error})`)
        }
    }

    function _writeMirrorToDisk(): void {
        if (root._rawWriteView !== null)
            return;
        try {
            let obj = root._jsonMirror;
            if (!obj || Object.keys(obj).length === 0) {
                root._endWriteFlight("empty config mirror");
                return;
            }
            if (root._hasObjectKeys(root.customWidgetData)) {
                if (!obj.background) obj.background = {};
                if (!obj.background.widgets) obj.background.widgets = {};
                obj.background.widgets.custom = root.customWidgetData;
            }
            // This complete snapshot already contains custom data. A second
            // identical injection receives no FileView acknowledgement.
            root._pendingCustomInject = false;
            root._customSnapshotForInject = ({});
            const text = JSON.stringify(obj, null, 4);
            if (configFileView.text() === text) {
                const view = uncachedRawWriter.createObject(root, {path: root.filePath});
                if (!view)
                    throw new Error("could not create raw config writer");
                root._rawWriteView = view;
                view.setText(text);
            } else configFileView.setText(text);
        } catch (e) {
            root._endWriteFlight(`mirror write failed (${e.message})`);
        }
    }

    function _injectCustomDataSync(): void {
        const customData = root._hasObjectKeys(root._customSnapshotForInject)
            ? root._customSnapshotForInject : root.customWidgetData;
        if (!root._hasObjectKeys(customData)) return;
        try {
            if (!root._jsonMirror.background) root._jsonMirror.background = {};
            if (!root._jsonMirror.background.widgets) root._jsonMirror.background.widgets = {};
            root._jsonMirror.background.widgets.custom = customData;
            root.customWidgetData = root._cloneObject(customData);
            root._customSnapshotForInject = ({});
            root._writeInFlight = true;
            root._writeRetries = 0;
            writeFlightGuard.restart();
            root._writeMirrorToDisk();
        } catch (e) { root._endWriteFlight(`custom injection failed (${e.message})`); }
    }

    Timer {
        id: fileReloadTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            if (root._writeInFlight || root._rawWriteView !== null || fileWriteTimer.running || customInjectTimer.running || root._reloadInFlight) {
                root._pendingReload = true;
                return;
            }
            root._reloadInFlight = true;
            root._reloadOverlay = ({});
            configFileView.reload();
        }
    }

    Timer {
        id: fileWriteTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            if (!root.ready) {
                root._pendingWrite = true;
                return;
            }
            if (root._writeInFlight || root._rawWriteView !== null) {
                root._pendingWrite = true;
                return;
            }
            root._prepareCustomInject();
            root._pendingWrite = false;
            root._writeInFlight = true;
            root._writeRetries = 0;
            fileReloadTimer.stop();
            writeFlightGuard.restart();
            // A migration patches the original document, including keys owned
            // by optional/custom features that JsonAdapter does not declare.
            if (root._styleMigrationWritePending || root._pendingRawWrite) {
                root._styleMigrationWritePending = false;
                root._pendingRawWrite = false;
                root._writeMirrorToDisk();
            } else configFileView.writeAdapter();
        }
    }

    Timer {
        id: writeFlightGuard
        interval: 2000
        repeat: false
        onTriggered: {
            if (!root._writeInFlight)
                return;
            if (root._writeRetries >= 2) {
                root._endWriteFlight("write never acknowledged");
                return;
            }
            root._writeRetries++;
            root._writeMirrorToDisk();
            writeFlightGuard.restart();
        }
    }

    Timer {
        id: customInjectTimer
        interval: 1
        repeat: false
        onTriggered: root._injectCustomDataSync()
    }

    FileView {
        id: rawConfigReader
        path: root.filePath
    }

    FileView {
        id: configFileView
        path: root.filePath
        watchChanges: true
        blockWrites: root.blockWrites
        onFileChanged: {
            // A save from the previous mutation can signal FileChanged after
            // onSaved while the next debounced local write is already queued.
            // Never reload that older disk snapshot ahead of the queued write.
            if (root._writeInFlight || root._rawWriteView !== null || fileWriteTimer.running || customInjectTimer.running) {
                root._pendingReload = true;
                return;
            }
            fileReloadTimer.restart();
        }
        onSaved: root._endWriteFlight("")
        onSaveFailed: error => root._endWriteFlight(`save failed (${error})`)
        onLoaded: {
            const wasReload = root._reloadInFlight;
            const overlay = wasReload ? root._cloneObject(root._reloadOverlay) : ({});
            root._reloadInFlight = false;
            root._reloadOverlay = ({});
            try {
                root._jsonMirror = JSON.parse(configFileView.text());
            } catch (e) {
                root._jsonMirror = {};
            }
            root._syncVarProperties();

            // reload() may have started before a later local mutation. FileView
            // applies the loaded adapter before this signal, so restore those
            // newer local values and make the merged snapshot authoritative.
            const overlayPaths = Object.keys(overlay);
            for (let i = 0; i < overlayPaths.length; ++i) {
                const path = overlayPaths[i];
                root._applyNestedKey(path, overlay[path]);
                root._applyToMirror(path, overlay[path]);
            }
            if (overlayPaths.length > 0)
                fileWriteTimer.restart();

            const styleMigration = Object.assign({},
                FamilyPolicy.migrateMaterial(root._jsonMirror),
                FamilyPolicy.migrateContentOpacity(root._jsonMirror));
            if (Object.keys(styleMigration).length) {
                root._styleMigrationWritePending = true;
                root.setNestedValues(styleMigration);
            }
            root._reconcileMandatoryPanels();
            root._bumpRevision();
            root.ready = true;
            if (wasReload)
                root.configChanged();
        }
        onLoadFailed: error => {
            root._reloadInFlight = false;
            root._reloadOverlay = ({});
            if (error == FileViewError.FileNotFound) {
                console.log("[Config] File not found, creating new file.");
                const parentDir = root.filePath.substring(0, root.filePath.lastIndexOf('/'));
                Quickshell.execDetached(["/usr/bin/mkdir", "-p", parentDir]);
                root.customWidgetData = {};
                root.customWidgetDataSynced = true;
                writeAdapter();
            }
            root.ready = true;
        }

        JsonAdapter {
            id: configOptionsJsonAdapter

            property JsonObject perimeter: JsonObject {
                property int schemaVersion: 1
                property list<var> instances: []
                property list<var> defaultSlots: []
                property list<var> outputs: []
            }

            property list<string> enabledPanels: FamilyPolicy.abyssPanels
            property list<string> knownPanels: []
            property list<string> visitedPanelFamilies: []
            property string panelFamily: "abyss"
            property int panelStyleVersion: 1
            property bool familyTransitionAnimation: true

            property JsonObject abyss: JsonObject {
                property string quality: "balanced"
                property bool autoQuality: false
                property list<var> positions: []
                property JsonObject sidebars: JsonObject {
                    property bool hoverEnabled: true
                }
                property JsonObject companionMind: JsonObject {
                    property bool talkEnabled: true
                    property bool localOnly: true
                    property bool aiEnabled: false
                    property string endpoint: "http://127.0.0.1:11434"
                    property string model: ""
                    property string thinkingEffort: "off"
                    property string proactive: "occasional"
                    property bool proactiveEnabled: false
                    property int proactiveDailyCap: 6
                    property int proactiveEventCap: 3
                    property bool proactiveQuietEnabled: true
                    property int proactiveQuietStart: 1320
                    property int proactiveQuietEnd: 480
                    property bool todoRemindersEnabled: false
                    property bool calendarRemindersEnabled: false
                    property bool journalRemindersEnabled: false
                    property bool reminderNotificationsEnabled: false
                    property bool memoryEnabled: false
                    property bool bondEnabled: false
                    property string dialogueTone: "gentle"
                    property string familiarity: "neutral"
                    property bool obsidianEnabled: false
                    property string referenceVault: ""
                }
                property JsonObject companion: JsonObject {
                    property bool enabled: false
                    property bool contextEnabled: false
                    property bool contextFocusEnabled: false
                    property bool contextAiEnabled: false
                    property string character: "aqua"
                    property bool alternateCompanions: false
                    property string output: ""
                    property string edge: "auto"
                    property real along: 0.72
                    property real size: 1
                    property bool interactive: true
                    property bool soundEnabled: false
                    property string personality: "balanced"
                    property string appearanceFrequency: "always"
                    property bool animationsEnabled: true
                    property bool effectsEnabled: true
                    property bool hideInFullscreen: false
                    property string renderQuality: "quality"
                    property bool autoQuality: false
                    property real translucency: 0.16
                    property bool exploreFeatures: true
                }
                property JsonObject spectrum: JsonObject {
                    property bool configured: false
                    property bool enabled: false
                    property real strength: 0.45
                    property string edge: "bar"
                    property string multiMonitorMode: "primary"
                }
                property JsonObject perimeter: JsonObject {
                    property int thickness: 16
                    property int radius: 34
                    property bool visibleInFullscreen: false
                }
                property JsonObject surface: JsonObject {
                    property real opacity: 0.78
                    property real tension: 0.5
                    property int softness: 24
                }
                property JsonObject content: JsonObject {
                    property int opacityVersion: 1
                    // -1 follows the Screen Edge material until customized.
                    property real opacity: -1
                    property int blurRadius: -1
                    // Retired saved key; migrated once when opacity is absent.
                    property real cardOpacity: 0.9
                }
                property JsonObject waves: JsonObject {
                    property real strength: -1
                    property bool popupTravel: true
                    property real whitewater: 0.65
                    property bool enabled: false
                    property string preset: "balanced"
                    property real amplitude: 0.6
                    property real propagation: 0.8
                    property real speed: 0.55
                    property real decay: 0.55
                    property real tension: 0.5
                    property real viscosity: 0.55
                    property real rebound: 0.6
                    property real corner: 0.8
                    property real hover: 1
                    property real press: 1
                    property real open: 1
                    property real close: 1
                    property real drag: 1
                    property bool idle: false
                    property real small: 0.7
                    property real large: 1
                    property real dock: 0.5
                    property real notifications: 0.3
                }
                property JsonObject modules: JsonObject {
                    property bool configured: false
                    // Launch both converted Screen Edge affordances immediately;
                    // saving an edited profile marks the corresponding migration.
                    property bool autoUnifiedEdgeLaunchers: true
                    // Legacy combined selection retained only as a migration
                    // fallback; each feature now owns an independent mode.
                    property string launcherMode: "module"
                    property string notesTimersMode: ""
                    property string notificationActivityMode: ""
                    // Declarative JsonAdapter schema is required: assigning a
                    // previously undeclared nested key silently fails to
                    // persist. "inherit" preserves legacy per-output values.
                    property JsonObject iconVisibility: JsonObject {
                        property string notesTimers: "inherit"
                        property string notificationActivity: "inherit"
                    }
                    property bool unifiedLaunchersConfigured: false
                    property list<var> placements: []
                    property list<var> outputLayouts: []
                    property real gap: 8
                    property real size: 1
                    property JsonObject singleModuleExpansion: JsonObject {
                        property string top: "edge"
                        property string right: "edge"
                        property string bottom: "edge"
                        property string left: "edge"
                    }
                    property JsonObject edgeThicknesses: JsonObject {
                        property real top: -1
                        property real right: -1
                        property real bottom: -1
                        property real left: -1
                    }
                    property JsonObject edgeWidthAffectsModules: JsonObject {
                        property bool top: true
                        property bool right: true
                        property bool bottom: true
                        property bool left: true
                    }
                    property JsonObject edgeJoinModules: JsonObject {
                        property bool top: false
                        property bool right: false
                        property bool bottom: false
                        property bool left: false
                    }
                    property JsonObject edgeRoundZeroCorners: JsonObject {
                        property bool top: false
                        property bool right: false
                        property bool bottom: false
                        property bool left: false
                    }
                    property JsonObject edgeModuleRadii: JsonObject {
                        property real top: -1
                        property real right: -1
                        property real bottom: -1
                        property real left: -1
                    }
                    property JsonObject edgeSizes: JsonObject {
                        property real top: 1
                        property real right: 1
                        property real bottom: 1
                        property real left: 1
                    }
                    property real depth: 36
                }
                property JsonObject motion: JsonObject { property real intensity: 0.6 }
                property JsonObject effects: JsonObject {
                    property JsonObject blur: JsonObject { property bool enabled: true; property int radius: 10 }
                    property JsonObject refraction: JsonObject { property bool enabled: false; property real strength: 6 }
                    property JsonObject glow: JsonObject { property real strength: 0.08 }
                    property real surfaceHighlight: 0.45
                    property real shadowStrength: 0.24
                }
            }

            property JsonObject policies: JsonObject {
                property int ai: 0
                property int weeb: 0
            }

            property JsonObject ai: JsonObject {
                property string localModelFolder: ""
                property string systemPrompt: "## Style\n- Use casual tone, don't be formal! Make sure you answer precisely without hallucination and prefer bullet points over walls of text. You can have a friendly greeting at the beginning of the conversation, but don't repeat the user's question\n\n## Context (ignore when irrelevant)\n- You are a helpful and inspiring sidebar assistant on a {DISTRO} Linux system\n- Desktop environment: {DE}\n- Current date & time: {DATETIME}\n- Focused app: {WINDOWCLASS}\n\n## Presentation\n- Use Markdown features in your response: \n  - **Bold** text to **highlight keywords** in your response\n  - **Split long information into small sections** with h2 headers and a relevant emoji at the start of it (for example `## 🐧 Linux`). Bullet points are preferred over long paragraphs, unless you're offering writing support or instructed otherwise by the user.\n- Asked to compare different options? You should firstly use a table to compare the main aspects, then elaborate or include relevant comments from online forums *after* the table. Make sure to provide a final recommendation for the user's use case!\n- Use LaTeX formatting for mathematical and scientific notations whenever appropriate. Enclose all LaTeX '$$' delimiters. NEVER generate LaTeX code in a latex block unless the user explicitly asks for it. DO NOT use LaTeX for regular documents (resumes, letters, essays, CVs, etc.).\n"
                property string tool: "functions"
                property list<var> extraModels: [
                    {
                        "api_format": "openai",
                        "description": "This is a custom model. Edit the config to add more! | Anyway, this is DeepSeek R1 Distill LLaMA 70B",
                        "endpoint": "https://openrouter.ai/api/v1/chat/completions",
                        "homepage": "https://openrouter.ai/deepseek/deepseek-r1-distill-llama-70b:free",
                        "icon": "spark-symbolic",
                        "key_get_link": "https://openrouter.ai/settings/keys",
                        "key_id": "openrouter",
                        "model": "deepseek/deepseek-r1-distill-llama-70b:free",
                        "name": "Custom: DS R1 Dstl. LLaMA 70B",
                        "requires_key": true
                    }
                ]
            }

            property JsonObject appearance: JsonObject {
                property string theme: "auto"
                property string globalStyle: "material"
                property JsonObject screenEdge: JsonObject {
                    property int width: 10
                    property int radius: 25

                    // Connected-surface body shadow contract. Kept separate from
                    // the physical Screen Edge frame so popup/sidebar tuning can
                    // never change the perimeter shadow itself.
                    property JsonObject shadow: JsonObject {
                        property bool enabled: true
                        property int size: 15
                        property real opacity: 0.70
                    }

                    // Public Screen Edge depth controls. The physical frame and
                    // ii Bar popups share these values so popup depth matches
                    // the perimeter. Defaults mirror Caelestia ContentWindow.
                    property JsonObject physicalShadow: JsonObject {
                        property bool enabled: true
                        property int size: 15
                        property real opacity: 0.70
                    }
                }
                // Shared skin for island surfaces such as dock, sidebars and search.
                property JsonObject island: JsonObject {
                    property bool glass: true
                    property real glassBlur: 1
                    property int radius: 18
                    property real opacity: 1
                    property bool shadow: true
                    property bool sheen: true
                }
                property bool colorInvert: false
                property JsonObject regalia: JsonObject {
                    property bool glass: true
                    property real glassBlur: 0.72
                    property real glassTintTransparency: 0.52
                    property real glassSurfaceOpacity: 0.60
                    property real glassSaturation: 0.12
                    property real radiusScale: 1.0
                }
                property JsonObject aurora: JsonObject {
                    property JsonObject transparency: JsonObject {
                        property real overlay: 0.38
                        property real subSurface: 0.52
                        property real popup: 0.42
                        property real tooltip: 0.35
                        property real layer: 0.40
                    }
                    property string customPreset: ""
                }
                property string angelSubStyle: "frost"
                property JsonObject zzz: JsonObject {
                    property string shape: "square"
                    property bool glass: true
                    property JsonObject backdrop: JsonObject {
                        property bool burst: true
                        property bool ghost: true
                        property bool grid: true
                        property bool ticks: true
                        property real burstSize: 1.0
                    }
                }
                property JsonObject angel: JsonObject {
                    property JsonObject blur: JsonObject {
                        property real intensity: 0.25
                        property real saturation: 0.15
                        property real overlayOpacity: 0.35
                        property real noiseOpacity: 0.15
                        property real vignetteStrength: 0.4
                    }
                    property JsonObject transparency: JsonObject {
                        property real panel: 0.35
                        property real card: 0.50
                        property real popup: 0.35
                        property real tooltip: 0.25
                    }
                    property JsonObject escalonado: JsonObject {
                        property int offsetX: 2
                        property int offsetY: 2
                        property int hoverOffsetX: 7
                        property int hoverOffsetY: 7
                        property real opacity: 0.40
                        property real borderOpacity: 0.60
                        property real hoverOpacity: 0.60
                    }
                    property JsonObject escalonadoShadow: JsonObject {
                        property int offsetX: 4
                        property int offsetY: 4
                        property int hoverOffsetX: 10
                        property int hoverOffsetY: 10
                        property real opacity: 0.30
                        property real borderOpacity: 0.50
                        property real hoverOpacity: 0.50
                        property bool glass: true
                        property real glassBlur: 0.15
                        property real glassOverlay: 0.50
                    }
                    property JsonObject border: JsonObject {
                        property real width: 1.5
                        property int accentBarHeight: 0
                        property int accentBarWidth: 0
                        property real coverage: 0.0
                        property real opacity: 0.0
                        property real hoverOpacity: 0.0
                        property real activeOpacity: 0.0
                        property int insetGlowHeight: 0
                        property real insetGlowOpacity: 0.0
                    }
                    property JsonObject surface: JsonObject {
                        property int panelBorderWidth: 0
                        property int cardBorderWidth: 1
                        property real panelBorderOpacity: 0.0
                        property real cardBorderOpacity: 0.30
                    }
                    property JsonObject glow: JsonObject {
                        property real opacity: 0.80
                        property real strongOpacity: 0.65
                    }
                    property JsonObject rounding: JsonObject {
                        property int small: 10
                        property int normal: 15
                        property int large: 25
                    }
                    property real colorStrength: 1.0
                    property string customPreset: ""
                }
                property list<string> recentThemes: []
                property list<string> favoriteThemes: []
                property JsonObject themeSchedule: JsonObject {
                    property bool enabled: false
                    property string dayTheme: "auto"
                    property string nightTheme: "auto"
                    property string dayStart: "06:00"
                    property string nightStart: "18:00"
                }
                property JsonObject globalStyleCornerStyles: JsonObject {
                    property int material: 0
                    property int cards: 3
                    property int aurora: 0
                    property int alis: 1
                    property int angel: 1
                    property int regalia: 1
                    property int zzz: 0
                    property int cookie: 1
                }
                property bool extraBackgroundTint: true
                property bool softenColors: true
                property JsonObject customTheme: JsonObject {
                    property bool darkmode: true
                    property string m3background: "#282828"
                    property string m3onBackground: "#ebdbb2"
                    property string m3surface: "#282828"
                    property string m3surfaceDim: "#1d2021"
                    property string m3surfaceBright: "#3c3836"
                    property string m3surfaceContainerLowest: "#1d2021"
                    property string m3surfaceContainerLow: "#282828"
                    property string m3surfaceContainer: "#32302f"
                    property string m3surfaceContainerHigh: "#3c3836"
                    property string m3surfaceContainerHighest: "#504945"
                    property string m3onSurface: "#ebdbb2"
                    property string m3surfaceVariant: "#504945"
                    property string m3onSurfaceVariant: "#d5c4a1"
                    property string m3inverseSurface: "#ebdbb2"
                    property string m3inverseOnSurface: "#282828"
                    property string m3outline: "#928374"
                    property string m3outlineVariant: "#665c54"
                    property string m3shadow: "#000000"
                    property string m3scrim: "#000000"
                    property string m3surfaceTint: "#fe8019"
                    property string m3primary: "#fe8019"
                    property string m3onPrimary: "#1d2021"
                    property string m3primaryContainer: "#af3a03"
                    property string m3onPrimaryContainer: "#fbd5a8"
                    property string m3inversePrimary: "#d65d0e"
                    property string m3secondary: "#b8bb26"
                    property string m3onSecondary: "#1d2021"
                    property string m3secondaryContainer: "#79740e"
                    property string m3onSecondaryContainer: "#d5c4a1"
                    property string m3tertiary: "#83a598"
                    property string m3onTertiary: "#1d2021"
                    property string m3tertiaryContainer: "#427b58"
                    property string m3onTertiaryContainer: "#d5c4a1"
                    property string m3error: "#fb4934"
                    property string m3onError: "#1d2021"
                    property string m3errorContainer: "#cc241d"
                    property string m3onErrorContainer: "#fbd5a8"
                    property string m3primaryFixed: "#fabd2f"
                    property string m3primaryFixedDim: "#d79921"
                    property string m3onPrimaryFixed: "#1d2021"
                    property string m3onPrimaryFixedVariant: "#3c3836"
                    property string m3secondaryFixed: "#b8bb26"
                    property string m3secondaryFixedDim: "#98971a"
                    property string m3onSecondaryFixed: "#1d2021"
                    property string m3onSecondaryFixedVariant: "#3c3836"
                    property string m3tertiaryFixed: "#8ec07c"
                    property string m3tertiaryFixedDim: "#689d6a"
                    property string m3onTertiaryFixed: "#1d2021"
                    property string m3onTertiaryFixedVariant: "#3c3836"
                    property string m3success: "#b8bb26"
                    property string m3onSuccess: "#1d2021"
                    property string m3successContainer: "#79740e"
                    property string m3onSuccessContainer: "#d5c4a1"
                }
                property JsonObject transparency: JsonObject {
                    property bool enable: false
                    property bool automatic: true
                    property real backgroundTransparency: 0.11
                    property real contentTransparency: 0.57
                }
                property JsonObject wallpaperTheming: JsonObject {
                    property bool autoDarkLightMode: false
                    property bool enableAppsAndShell: true
                    property bool enableQtApps: true
                    property bool enableTerminal: true
                    property bool enableVesktop: true
                    property bool enableZed: true
                    property bool enableVSCode: true
                    property bool enableChrome: true
                    property bool enableSpicetify: false
                    property string spicetifyTheme: "Alis"
                    property bool enableSteam: false
                    property bool enablePearDesktop: true
                    property bool enableOpenCode: false
                    property bool enableNeovim: false
                    property bool enableCava: false
                    property real colorStrength: 1.0
                    property JsonObject vscodeEditors: JsonObject {
                        property bool code: true
                        property bool codium: true
                        property bool codeOss: true
                        property bool codeInsiders: true
                        property bool cursor: true
                        property bool windsurf: true
                        property bool windsurfNext: true
                        property bool qoder: true
                        property bool antigravity: true
                        property bool positron: true
                        property bool voidEditor: true
                        property bool melty: true
                        property bool pearai: true
                        property bool aide: true
                    }
                    property bool useBackdropForColors: false
                    property bool colorsOnlyMode: false
                    property string previewSourcePath: ""
                    property JsonObject terminals: JsonObject {
                        property bool kitty: true
                        property bool alacritty: true
                        property bool foot: true
                        property bool wezterm: true
                        property bool ghostty: true
                        property bool konsole: true
                        property bool starship: true
                        property bool btop: true
                        property bool lazygit: true
                        property bool yazi: true
                        property bool omp: true
                    }
                    property JsonObject terminalGenerationProps: JsonObject {
                        property real harmony: 0.6
                        property real harmonizeThreshold: 100
                        property real termFgBoost: 0.35
                        property bool forceDarkMode: false
                    }
                    property JsonObject terminalColorAdjustments: JsonObject {
                        property real saturation: 0.65
                        property real brightness: 0.60
                        property real harmony: 0.40
                        property real backgroundBrightness: 0.50
                    }
                }
                property JsonObject cava: JsonObject {
                    property string colorSource: "theme"
                    property int gradientCount: 8
                    property string foreground: ""
                    property string background: ""
                    property int sensitivity: 100
                    property int bars: 0
                    property int framerate: 30
                    property int barWidth: 2
                    property int barSpacing: 1
                    property bool stereo: true
                    property int waveOpacity: 30
                }
                property JsonObject palette: JsonObject {
                    property string type: "auto"
                    property string accentColor: ""
                }
                property JsonObject typography: JsonObject {
                    property string mainFont: "Roboto Flex"
                    property string titleFont: "Gabarito"
                    property string monospaceFont: "JetBrainsMono Nerd Font"
                    property real sizeScale: 1.0
                    property bool syncWithSystem: true
                    property JsonObject variableAxes: JsonObject {
                        property int wght: 300
                        property int wdth: 105
                        property int grad: 150
                    }
                }
                property string iconTheme: "WhiteSur-dark"
                property string dockIconTheme: ""
                property real shellScale: 1.0
                property string iiMotionProfile: "classic"
                property JsonObject desaturation: JsonObject {
                    property bool enable: false
                    property real saturation: -0.7
                    property real brightness: -0.15
                    property string scope: "all"
                    property bool bar: true
                    property bool dock: true
                    property bool sidebars: true
                    property bool overlays: true
                    property bool popups: true
                }
                property JsonObject animationSpeed: JsonObject {
                    property real movement: 1.0
                    property real enterExit: 1.0
                    property real clickBounce: 1.0
                    property real scroll: 1.0
                }
                property JsonObject animationCurve: JsonObject {
                    property string movement: "default"
                    property string enterExit: "default"
                    property string clickBounce: "default"
                    property string scroll: "default"
                }
            }

            property JsonObject performance: JsonObject {
                property bool lowPower: false
                property bool reduceAnimations: false
                property bool memoryMonitoring: true
                property int jsgcThreshold: 300
                property bool memoryWarningNotification: false
                property bool compositorBlur: true
                property string blurBackend: "auto"
                property JsonObject blurAreas: JsonObject {
                    property string bar: "inherit"
                    property string dock: "inherit"
                    property string panels: "inherit"
                    property string islands: "inherit"
                    property string widgets: "inherit"
                }
            }

            property JsonObject powerProfiles: JsonObject {
                property bool restoreOnStart: true
                property string preferredProfile: ""
                property JsonObject fanControl: JsonObject {
                    property bool enabled: false
                    property int powerSaver: 0
                    property int balanced: 0
                    property int performance: 0
                }
            }

            property JsonObject idle: JsonObject {
                property int screenOffTimeout: 300
                property int lockTimeout: 600
                property int suspendTimeout: 0
                property bool lockBeforeSleep: true
                property JsonObject onBattery: JsonObject {
                    property bool enable: false
                    property int screenOffTimeout: 120
                    property int lockTimeout: 300
                    property int suspendTimeout: 600
                }
            }

            property JsonObject modules: JsonObject {
                property bool altSwitcher: false
                property bool bar: true
                property bool background: true
                property bool cheatsheet: true
                property bool clipboard: true
                property bool crosshair: false
                property bool dock: true
                property bool lock: true
                property bool mediaControls: true
                property bool notificationPopup: true
                property bool onScreenDisplay: true
                property bool onScreenKeyboard: true
                property bool overview: true
                property bool overlay: true
                property bool polkit: true
                property bool regionSelector: true
                property bool reloadPopup: true
                property bool screenCorners: true
                property bool sessionScreen: true
                property bool sidebarLeft: true
                property bool sidebarRight: true
                property bool verticalBar: true
                property bool wallpaperSelector: true
            }

            property JsonObject gameMode: JsonObject {
                property bool autoDetect: true
                property bool disableAnimations: true
                property bool disableEffects: true
                property bool disableNiriAnimations: true
                property bool disableReloadToasts: true
                property bool disableDiscoverOverlay: true
                property bool suppressNotifications: true
                property bool minimalMode: true
                property int niriWindowListUpdateIntervalMs: 100
                property int niriWindowListUpdateIntervalMsGameMode: 500
                property int checkInterval: 10000
            }

            property JsonObject reloadToasts: JsonObject {
                property bool enable: true
            }

            property JsonObject audio: JsonObject {
                property JsonObject protection: JsonObject {
                    property bool enable: true
                    property real maxAllowedIncrease: 10
                    property real maxAllowed: 100
                }
            }

            property JsonObject compositor: JsonObject {
                property bool autoExpandSingleTilingWindow: false
            }

            property JsonObject apps: JsonObject {
                property string bluetooth: "kcmshell6 kcm_bluetooth"
                property string network: "kitty -1 fish -c nmtui"
                property string networkEthernet: "kcmshell6 kcm_networkmanagement"
                property string taskManager: "missioncenter"
                property string terminal: "kitty"
                property string browser: "firefox"
                property string volumeMixer: "pavucontrol"
                property string discord: "discord"
                property string update: "kitty -e sudo pacman -Syu"
                property string manageUser: "kcmshell6 kcm_users"
            }

            property JsonObject background: JsonObject {
                property JsonObject widgets: JsonObject {
                    property string style: "panel"
                    property int dynamicOpacity: 0
                    property bool adaptColorsToWallpaperPosition: false
                    property JsonObject powerSaving: JsonObject {
                        property bool enable: true
                        property bool pauseOnGameMode: true
                        property bool pauseOnFullscreen: true
                        property bool pauseWhenWindowsPresent: false
                        property bool showPausedEffect: true
                    }
                    property list<string> screenList: []
                    property list<var> outputOverrides: []
                    property list<string> layerOrder: []
                    property JsonObject clock: JsonObject {
                        property bool enable: false
                        property bool locked: false
                        property string placementStrategy: "free"
                        property real x: 100
                        property real y: 100
                        property string style: "digital"
                        property int dim: 70
                        property string fontFamily: "Space Grotesk"
                        property string timeFormat: "system"
                        property string dateStyle: "long"
                        property bool showDate: true
                        property bool showSeconds: false
                        property bool showShadow: true
                        property int timeScale: 100
                        property int dateScale: 100
                        property int widgetScale: 100
                        property int widgetOpacity: 100
                        property bool showBackground: false
                        property bool useBlur: false
                        property bool showBorder: false
                        property real backgroundOpacity: 0
                        property real borderWidth: 0
                        property real borderOpacity: 0.08
                        property real cornerRadius: -1
                        property string colorMode: "auto"
                        property JsonObject palette: JsonObject {
                            property string primary: "primary"
                            property string secondary: "secondary"
                            property string tertiary: "tertiary"
                            property string signal: "signal"
                            property string surface: "surface"
                        }
                        property JsonObject cookie: JsonObject {
                            property bool aiStyling: false
                            property int sides: 15
                            property string dialNumberStyle: "full"
                            property string hourHandStyle: "hollow"
                            property string minuteHandStyle: "hide"
                            property string secondHandStyle: "hide"
                            property string dateStyle: "bubble"
                            property bool timeIndicators: false
                            property bool hourMarks: false
                            property bool dateInClock: true
                            property bool constantlyRotate: false
                            property bool useSineCookie: false
                            property int size: 230
                            property string preset: "default"
                        }
                        property JsonObject digital: JsonObject {
                            property bool adaptToWallpaper: true
                            property bool animateChange: true
                            property int fontWeight: 600
                            property int spacing: 6
                            property string preset: "default"
                        }
                        property JsonObject quote: JsonObject {
                            property bool enable: false
                            property string text: ""
                        }
                    }
                    property JsonObject weather: JsonObject {
                        property bool enable: false
                        property bool locked: false
                        property string placementStrategy: "free"
                        property real x: 100
                        property real y: 200
                        property int size: 200
                        property int tempSize: 80
                        property int iconSize: 80
                        property bool showTemp: true
                        property bool showIcon: true
                        property bool showCondition: false
                        property int padding: 20
                        property int tempFontWeight: 500
                        property real conditionOpacity: 0.7
                        property string preset: "default"
                        property string style: "pill"
                        property bool showMetrics: true
                        property string shape: "pill"
                        property int widgetScale: 100
                        property int widgetOpacity: 100
                        property bool showBackground: true
                property bool showDashboardButton: true
                        property bool useBlur: false
                        property bool showBorder: true
                        property real backgroundOpacity: 0.16
                        property real borderWidth: 1
                        property real borderOpacity: 0.20
                        property real cornerRadius: -1
                        property string colorMode: "auto"
                        property JsonObject palette: JsonObject {
                            property string primary: "primary"
                            property string secondary: "secondary"
                            property string tertiary: "tertiary"
                            property string signal: "signal"
                            property string surface: "surface"
                        }
                        property int dim: 0
                    }

                    property JsonObject customImage: JsonObject {
                        property bool enable: false
                        property bool locked: false
                        property string placementStrategy: "free"
                        property string sourceMode: "file"
                        property string path: ""
                        property string folder: ""
                        property string mediaFilter: "all"
                        property int intervalSeconds: 30
                        property string order: "sequential"
                        property int transitionDuration: 450
                        property string shape: "Cookie4Sided"
                        property string fitMode: "cover"
                        property int size: 220
                        property int contentWidth: 0
                        property int contentHeight: 0
                        property int dim: 0
                        property int widgetScale: 100
                        property int widgetOpacity: 100
                        property JsonObject palette: JsonObject {
                            property string primary: "primary"
                            property string secondary: "secondary"
                            property string tertiary: "tertiary"
                            property string signal: "signal"
                            property string surface: "surface"
                        }
                        property real x: 120
                        property real y: 320
                    }

                    property JsonObject imageConverter: JsonObject {
                        property bool enable: false
                        property bool locked: false
                        property string placementStrategy: "free"
                        property string selectedFormat: "webp"
                        property int contentWidth: 292
                        property int contentHeight: 260
                        property int widgetScale: 100
                        property int widgetOpacity: 100
                        property string colorMode: "auto"
                        property JsonObject palette: JsonObject {
                            property string primary: "primary"
                            property string secondary: "secondary"
                            property string tertiary: "tertiary"
                            property string signal: "signal"
                            property string surface: "surface"
                        }
                        property int dim: 0
                        property bool showBackground: true
                        property bool useBlur: false
                        property bool showBorder: true
                        property real backgroundOpacity: 0.22
                        property real borderWidth: 1
                        property real borderOpacity: 0.22
                        property real cornerRadius: -1
                        property real x: 120
                        property real y: 360
                    }

                    property JsonObject mediaControls: JsonObject {
                        property bool enable: false
                        property bool locked: false
                        property string placementStrategy: "free"
                        property string playerPreset: "full"
                        property string visualizerType: "wave"
                        property string visualizerPosition: "bottom"
                        property bool lyricsExpanded: false
                        property real x: 240
                        property real y: 240
                        property int widgetScale: 100
                        property int widgetOpacity: 100
                        property string colorMode: "auto"
                        property JsonObject palette: JsonObject {
                            property string primary: "primary"
                            property string secondary: "secondary"
                            property string tertiary: "tertiary"
                            property string signal: "signal"
                            property string surface: "surface"
                        }
                        property int dim: 0
                    }

                    property JsonObject visualizer: JsonObject {
                        property bool enable: false
                        property bool locked: false
                        property string placementStrategy: "free"
                        property string vizType: "bars"
                        property string preset: "default"
                        property string paletteMode: "cava"
                        property string barsOrigin: "bottom"
                        property string waveMode: "fill"
                        property string frequencyProfile: "flat"
                        property int smoothing: 2
                        property int fillRatio: 90
                        property int barOpacity: 100
                        property int waveOpacity: -1
                        property int barCount: 48
                        property int barSpacing: 2
                        property int barRadius: 2
                        property int barMinHeight: 1
                        property int lineWidth: 2
                        property int edgeInset: 0
                        property int edgeSoftness: 28
                        property int accentStrength: 70
                        property int contentWidth: 304
                        property int contentHeight: 104
                        property int dim: 0
                        property int widgetScale: 100
                        property int widgetOpacity: 100
                        property bool showBackground: true
                        property bool useBlur: false
                        property bool showBorder: true
                        property real backgroundOpacity: 0.16
                        property real borderWidth: 1
                        property real borderOpacity: 0.20
                        property real cornerRadius: -1
                        property string colorMode: "auto"
                        property JsonObject palette: JsonObject {
                            property string primary: "primary"
                            property string secondary: "secondary"
                            property string tertiary: "tertiary"
                            property string signal: "signal"
                            property string surface: "surface"
                        }
                        property real x: 100
                        property real y: 100
                    }

                    property JsonObject systemMonitor: JsonObject {
                        property bool enable: false
                        property bool locked: false
                        property string placementStrategy: "free"
                        property string displayMode: "bars"
                        property int barCount: 32
                        property int barSpacing: 2
                        property real trackAlpha: 0.08
                        property real fillOpacity: 0.7
                        property real graphFillOpacity: 0.3
                        property bool showCpu: true
                        property bool showMemory: true
                        property bool showGpu: true
                        property bool showTemp: false
                        property bool showGpuTemp: false
                        property bool showDisk: false
                        property bool showLabels: true
                        property int contentWidth: 320
                        property int contentHeight: 120
                        property string preset: "default"
                        property int dim: 0
                        property int widgetScale: 100
                        property int widgetOpacity: 100
                        property bool showBackground: true
                        property bool useBlur: false
                        property bool showBorder: true
                        property real backgroundOpacity: 0.16
                        property real borderWidth: 1
                        property real borderOpacity: 0.20
                        property real cornerRadius: -1
                        property string colorMode: "auto"
                        property JsonObject palette: JsonObject {
                            property string primary: "primary"
                            property string secondary: "secondary"
                            property string tertiary: "tertiary"
                            property string signal: "signal"
                            property string surface: "surface"
                        }
                        property real x: 50
                        property real y: 400
                    }

                    property JsonObject battery: JsonObject {
                        property bool enable: false
                        property bool locked: false
                        property string placementStrategy: "free"
                        property string displayMode: "ring"
                        property bool showTime: true
                        property int ringSize: 72
                        property int ringLineWidth: 6
                        property int barCount: 20
                        property int barSpacing: 2
                        property int barRadius: 2
                        property int pillHeight: 12
                        property string preset: "default"
                        property int dim: 0
                        property int widgetScale: 100
                        property int widgetOpacity: 100
                        property bool showBackground: true
                        property bool useBlur: false
                        property bool showBorder: true
                        property real backgroundOpacity: 0.16
                        property real borderWidth: 1
                        property real borderOpacity: 0.20
                        property real cornerRadius: -1
                        property string colorMode: "auto"
                        property JsonObject palette: JsonObject {
                            property string primary: "primary"
                            property string secondary: "secondary"
                            property string tertiary: "tertiary"
                            property string signal: "signal"
                            property string surface: "surface"
                        }
                        property real x: 50
                        property real y: 50
                    }

                    property JsonObject notes: JsonObject {
                        property bool enable: false
                        property bool locked: false
                        property string placementStrategy: "free"
                        property string text: ""
                        property int fontSize: 14
                        property string fontFamily: "sans"
                        property string textAlign: "left"
                        property int contentWidth: 240
                        property int contentHeight: 160
                        property int dim: 0
                        property int widgetScale: 100
                        property int widgetOpacity: 100
                        property bool showBackground: true
                        property bool useBlur: false
                        property bool showBorder: true
                        property real backgroundOpacity: 0.10
                        property real borderWidth: 1
                        property real borderOpacity: 0.12
                        property real cornerRadius: -1
                        property string colorMode: "auto"
                        property JsonObject palette: JsonObject {
                            property string primary: "primary"
                            property string secondary: "secondary"
                            property string tertiary: "tertiary"
                            property string signal: "signal"
                            property string surface: "surface"
                        }
                        property real x: 80
                        property real y: 80
                    }

                    property JsonObject japaneseTypography: JsonObject {
                        property bool enable: false
                        property bool locked: false
                        property string placementStrategy: "free"
                        property string preset: "exhibition"
                        property string primaryText: "夏の記憶"
                        property string secondaryText: "潮風と、あの子と、終わらない夏"
                        property string sealText: "特別展"
                        property string footerText: "PACIFIC DRIVE-IN"
                        property string dateText: "7.12 — 8.31"
                        property bool showSecondary: true
                        property bool showSeal: true
                        property bool showFooter: true
                        property bool showRule: true
                        property string fontPreset: "mincho"
                        property string fontFamily: "serif"
                        property string secondaryFontFamily: ""
                        property string latinFontFamily: ""
                        property int primaryWeight: 500
                        property int secondaryWeight: 400
                        property int latinWeight: 600
                        property int primarySize: 72
                        property int secondarySize: 18
                        property int footerSize: 14
                        property int dateSize: 12
                        property int primaryColumns: 2
                        property int secondaryColumns: 2
                        property int columnGap: 14
                        property int letterSpacing: 2
                        property int secondaryLetterSpacing: 1
                        property bool mirrorLayout: false
                        property bool rotateLatin: false
                        property string paletteMode: "adaptive"
                        property string palettePreset: "adaptive"
                        property string primaryColor: "#E7D4B2"
                        property string secondaryColor: "#CDB48D"
                        property string sealColor: "#A64B39"
                        property string detailColor: "#D0B996"
                        property string ruleColor: "#C18A53"
                        property int primaryOpacity: 100
                        property int secondaryOpacity: 78
                        property int sealOpacity: 100
                        property int detailOpacity: 72
                        property int ruleOpacity: 78
                        property real sealFillOpacity: 0
                        property int ruleThickness: 1
                        property string outlineColor: "#000000"
                        property int outlineOpacity: 0
                        property int shadowStrength: 35
                        property int contentWidth: 330
                        property int contentHeight: 600
                        property int dim: 10
                        property int widgetScale: 100
                        property int widgetOpacity: 100
                        property bool showBackground: false
                        property bool useBlur: false
                        property bool showBorder: false
                        property real backgroundOpacity: 0
                        property real borderWidth: 0
                        property real borderOpacity: 0.12
                        property real cornerRadius: -1
                        property string colorMode: "auto"
                        property JsonObject palette: JsonObject {
                            property string primary: "primary"
                            property string secondary: "secondary"
                            property string tertiary: "tertiary"
                            property string signal: "signal"
                            property string surface: "surface"
                        }
                        property real x: 56
                        property real y: 120
                    }

                    property JsonObject calendarUpcoming: JsonObject {
                        property bool enable: false
                        property bool locked: false
                        property string placementStrategy: "free"
                        property int maxEvents: 5
                        property bool showDate: true
                        property bool showTime: true
                        property bool showLocation: false
                        property bool groupByDay: true
                        property int contentWidth: 280
                        property int contentHeight: 220
                        property int dim: 0
                        property int widgetScale: 100
                        property int widgetOpacity: 100
                        property bool showBackground: true
                        property bool useBlur: false
                        property bool showBorder: true
                        property real backgroundOpacity: 0.10
                        property real borderWidth: 1
                        property real borderOpacity: 0.12
                        property real cornerRadius: -1
                        property string colorMode: "auto"
                        property JsonObject palette: JsonObject {
                            property string primary: "primary"
                            property string secondary: "secondary"
                            property string tertiary: "tertiary"
                            property string signal: "signal"
                            property string surface: "surface"
                        }
                        property real x: 80
                        property real y: 80
                    }

                    property JsonObject uptime: JsonObject {
                        property bool enable: false
                        property bool locked: false
                        property string placementStrategy: "free"
                        property int contentWidth: 250
                        property int contentHeight: 96
                        property int widgetScale: 100
                        property int widgetOpacity: 100
                        property bool showBackground: true
                        property bool useBlur: false
                        property bool showBorder: true
                        property real backgroundOpacity: 0.16
                        property real borderWidth: 1
                        property real borderOpacity: 0.20
                        property real cornerRadius: -1
                        property string colorMode: "auto"
                        property JsonObject palette: JsonObject {
                            property string primary: "primary"
                            property string secondary: "secondary"
                            property string tertiary: "tertiary"
                            property string signal: "signal"
                            property string surface: "surface"
                        }
                        property int dim: 0
                        property real x: 80
                        property real y: 80
                    }

                    property JsonObject worldClock: JsonObject {
                        property bool enable: false
                        property bool locked: false
                        property string placementStrategy: "free"
                        property int contentWidth: 300
                        property int contentHeight: 210
                        property int widgetScale: 100
                        property int widgetOpacity: 100
                        property bool showBackground: true
                        property bool useBlur: false
                        property bool showBorder: true
                        property real backgroundOpacity: 0.16
                        property real borderWidth: 1
                        property real borderOpacity: 0.20
                        property real cornerRadius: -1
                        property string colorMode: "auto"
                        property JsonObject palette: JsonObject {
                            property string primary: "primary"
                            property string secondary: "secondary"
                            property string tertiary: "tertiary"
                            property string signal: "signal"
                            property string surface: "surface"
                        }
                        property int dim: 0
                        property real x: 80
                        property real y: 200
                        property list<string> timezones: ["Australia/Sydney", "Asia/Tokyo", "Europe/London", "America/New_York"]
                    }

                    property JsonObject userCard: JsonObject {
                        property bool enable: false
                        property bool locked: false
                        property string placementStrategy: "free"
                        property int contentWidth: 280
                        property int contentHeight: 176
                        property int widgetScale: 100
                        property int widgetOpacity: 100
                        property bool showBackground: true
                        property bool useBlur: false
                        property bool showBorder: true
                        property real backgroundOpacity: 0.16
                        property real borderWidth: 1
                        property real borderOpacity: 0.20
                        property real cornerRadius: -1
                        property string colorMode: "auto"
                        property JsonObject palette: JsonObject {
                            property string primary: "primary"
                            property string secondary: "secondary"
                            property string tertiary: "tertiary"
                            property string signal: "signal"
                            property string surface: "surface"
                        }
                        property int dim: 0
                        property real x: 80
                        property real y: 420
                    }

                    property JsonObject newsTicker: JsonObject {
                        property bool enable: false
                        property bool locked: false
                        property string placementStrategy: "free"
                        property int contentWidth: 320
                        property int contentHeight: 92
                        property int widgetScale: 100
                        property int widgetOpacity: 100
                        property bool showBackground: true
                        property bool useBlur: false
                        property bool showBorder: true
                        property real backgroundOpacity: 0.16
                        property real borderWidth: 1
                        property real borderOpacity: 0.20
                        property real cornerRadius: -1
                        property string colorMode: "auto"
                        property JsonObject palette: JsonObject {
                            property string primary: "primary"
                            property string secondary: "secondary"
                            property string tertiary: "tertiary"
                            property string signal: "signal"
                            property string surface: "surface"
                        }
                        property int dim: 0
                        property real x: 100
                        property real y: 260
                    }

                    property JsonObject editGrid: JsonObject {
                        property int size: 32
                        property bool snap: true
                    }
                }
                property string wallpaperPath: ""
                property string thumbnailPath: ""
                property string fillMode: "fill"
                property bool enableAnimation: true
                property bool pauseAnimationOnBattery: true
                property bool hideWhenFullscreen: true
                property JsonObject effects: JsonObject {
                    property bool enableBlur: false
                    property int blurRadius: 32
                    property int thumbnailBlurStrength: 50
                    property bool enableAnimatedBlur: false
                    property int dim: 0
                    property int dynamicDim: 0
                    property JsonObject ripple: JsonObject {
                        property bool enable: false
                        property bool charging: true
                        property bool overview: true
                        property bool reload: true
                        property bool lock: true
                        property bool session: true
                        property bool hotcorners: true
                        property int rippleDuration: 3000
                        property real sparkleIntensity: 1.0
                        property real glowIntensity: 1.0
                        property real ringWidth: 0.15
                    }
                }
                property JsonObject backdrop: JsonObject {
                    property bool enable: true
                    property bool hideWallpaper: false
                    property string fillMode: "fill"
                    property bool useMainWallpaper: true
                    property string wallpaperPath: ""
                    property string thumbnailPath: ""
                    property bool enableAnimation: false
                    property bool enableAnimatedBlur: false
                    property int blurRadius: 32
                    property int dim: 35
                    property real saturation: 0
                    property real contrast: 0
                    property bool vignetteEnabled: false
                    property real vignetteIntensity: 0.5
                    property real vignetteRadius: 0.7
                    property bool useAuroraStyle: false
                    property real auroraOverlayOpacity: 0.38
                }
                property JsonObject parallax: JsonObject {
                    property bool enable: false
                    property string axis: "vertical"
                    property bool vertical: false
                    property bool autoVertical: false
                    property bool enableWorkspace: true
                    property real workspaceShift: 1.0
                    property real workspaceZoom: 1.0
                    property real zoom: 1.0
                    property bool enableSidebar: true
                    property real panelShift: 0.15
                    property real widgetsFactor: 1.2
                    property real widgetDepth: 1.2
                    property bool pauseDuringTransitions: true
                    property int transitionSettleMs: 220
                }
                property JsonObject multiMonitor: JsonObject {
                    property bool enable: false
                }
                property list<var> wallpapersByMonitor: []
                property JsonObject autoWallpaper: JsonObject {
                    property bool enable: false
                    property int intervalMinutes: 30
                    property bool generateColors: true
                    property string folder: ""
                }
                property JsonObject pan: JsonObject {
                    property real x: 0.0
                    property real y: 0.0
                    property real zoom: 1.0
                }
                property JsonObject backend: JsonObject {
                    property string provider: "awww"
                    property JsonObject awww: JsonObject {
                        property int transitionFps: 60
                        property int simpleStep: 5
                        property int spatialStep: 30
                    }
                }
                property JsonObject transition: JsonObject {
                    property bool enable: true
                    property string type: "alisMelt"
                    property string direction: "right"
                    property int duration: 800
                    property list<var> bezier: [0.54, 0.0, 0.34, 0.99]
                }
                property bool hideUpscaleNotification: false
            }

            property JsonObject bar: JsonObject {
                property JsonObject activeWindow: JsonObject {
                    property bool showTitle: true
                    property int width: 220
                }
                property JsonObject autoHide: JsonObject {
                    property bool enable: false
                    property int hoverRegionWidth: 2
                    property bool pushWindows: false
                    property JsonObject showWhenPressingSuper: JsonObject {
                        property bool enable: true
                        property int delay: 140
                    }
                }
                property bool bottom: false
                property int height: 40
                property real opacity: 1.0
                property int cornerStyle: 0
                property int customRounding: -1
                property bool borderless: true
                property string topLeftIcon: "distro"
                property bool showBackground: true
                property bool showScrollHints: true
                property string leftScrollAction: "brightness"
                property string rightScrollAction: "volume"
                property JsonObject visualizer: JsonObject {
                    property bool enable: false
                    property string multiMonitorMode: "primary"
                    property string type: "bars"
                    property real height: 0.6
                    property real opacity: 0.35
                    property string barsOrigin: "bottom"
                    property int density: 12
                    property int gap: 2
                    property int smoothing: 2
                    property string waveMode: "fill"
                    property real lineWidth: 2
                    property int edgeInset: 0
                    property int edgeSoftness: 28
                    property string frequencyProfile: "flat"
                    property int accentStrength: 70
                }
                property bool verbose: true
                property bool vertical: false
                property JsonObject clock: JsonObject {
                    property string timeFontFamily: ""
                    property int timePixelSize: 0
                    property string dateFontFamily: ""
                    property int datePixelSize: 0
                }
                property JsonObject media: JsonObject {
                    property int width: 180
                }
                property JsonObject vignette: JsonObject {
                    property bool enabled: false
                    property real intensity: 0.6
                    property real radius: 0.5
                }
                property JsonObject modules: JsonObject {
                    property bool leftSidebarButton: true
                    property bool distroIcon: true
                    property bool activeWindow: true
                    property bool resources: false
                    property bool media: true
                    property bool workspaces: true
                    property bool clock: true
                    property bool utilButtons: false
                    property bool battery: true
                    property bool rightSidebarButton: true
                    property bool sysTray: true
                    property bool weather: true
                    property bool taskbar: false
                }
                property JsonObject modulesPlacement: JsonObject {
                    property string resources: "start"
                    property string media: "start"
                    property string workspaces: "center"
                    property string clock: "end"
                    property string utilButtons: "end"
                    property string battery: "end"
                }
                property JsonObject modulesLayout: JsonObject {
                    property list<string> order: ["resources", "media", "workspaces", "clock", "utilButtons", "battery"]
                }
                property JsonObject edgeModulesLayout: JsonObject {
                    property list<string> leftOrder: ["leftSidebarButton", "distroIcon", "activeWindow"]
                    property list<string> rightOrder: ["rightSidebarButton", "sysTray", "weather"]
                }
                property JsonObject layout: JsonObject {
                    property list<string> left: ["leftSidebarButton", "distroIcon", "activeWindow"]
                    property list<string> centerLeft: ["resources", "media"]
                    property list<string> center: ["workspaces"]
                    property list<string> centerRight: ["clock", "utilButtons", "battery"]
                    property list<string> right: ["rightSidebarButton", "tray", "timer", "shellUpdate", "spacer", "weather"]
                    property int spacerWidth: 0
                    property string spacerMode: "auto"
                    property bool migrated: false
                }
                property JsonObject verticalLayout: JsonObject {
                    property list<string> top: ["leftSidebarButton", "distroIcon", "activeWindow", "spacer"]
                    property list<string> centerTop: ["resources", "media"]
                    property list<string> center: ["workspaces"]
                    property list<string> centerBottom: ["clock", "utilButtons", "battery"]
                    property list<string> bottom: ["weather", "tray", "timer", "shellUpdate", "spacer", "rightSidebarButton"]
                    property int spacerHeight: 0
                    property string spacerMode: "auto"
                }
                property JsonObject resources: JsonObject {
                    property bool showMemoryIndicator: true
                    property bool showSwapIndicator: true
                    property bool showTempIndicator: true
                    property bool showCpuIndicator: true
                    property bool showGpuIndicator: true
                    property bool alwaysShowSwap: true
                    property bool alwaysShowTemp: true
                    property bool alwaysShowCpu: true
                    property bool alwaysShowGpu: true
                    property int tempCautionThreshold: 65
                    property int tempWarningThreshold: 80
                    property int memoryWarningThreshold: 95
                    property int swapWarningThreshold: 85
                    property int cpuWarningThreshold: 90
                    property int gpuWarningThreshold: 90
                }
                property list<string> screenList: []
                property JsonObject utilButtons: JsonObject {
                    property bool showScreenSnip: true
                    property bool showScreenRecord: true
                    property bool showColorPicker: false
                    property bool showMicToggle: false
                    property bool showKeyboardToggle: true
                    property bool showKeyboardLayoutSwitch: false
                    property bool showDarkModeToggle: true
                    property bool showPerformanceProfileToggle: false
                    property bool showScreenCast: false
                    property string screenCastOutput: "HDMI-A-1"
                    property bool showNotepad: true
                    property bool showUtilitiesLauncher: true
                    property list<string> order: ["screenSnip","screenRecord","colorPicker","notepad","keyboard","keyboardLayout","mic","screenCast","darkMode","performance","utilities"]
                }
                property JsonObject tray: JsonObject {
                    property bool monochromeIcons: true
                    property bool showItemId: false
                    property bool invertPinnedItems: true
                    property list<string> pinnedItems: []
                    property bool filterPassive: true
                }
                property JsonObject workspaces: JsonObject {
                    property string scrollBehavior: "workspace"
                    property bool invertScroll: false
                    property bool monochromeIcons: true
                    property bool dynamicCount: true
                    property int shown: 10
                    property bool wrapAround: true
                    property int scrollSteps: 3
                    property bool showAppIcons: true
                    property bool alwaysShowNumbers: false
                    property int showNumberDelay: 300
                    property list<string> numberMap: ["1", "2"]
                    property bool useNerdFont: false
                    property bool perMonitor: true
                    property bool automaticIndicatorColor: true
                    property string indicatorColor: ""
                }
                property JsonObject weather: JsonObject {
                    property bool enable: true
                    property bool useUSCS: false
                    property int fetchInterval: 10
                    property string city: ""
                    property bool enableGPS: false
                    property real manualLat: 0
                    property real manualLon: 0
                }
                property JsonObject indicators: JsonObject {
                    property JsonObject notifications: JsonObject {
                        property bool showUnreadCount: false
                    }
                }
            }

            property JsonObject battery: JsonObject {
                property int low: 20
                property int critical: 5
                property int full: 101
                property bool automaticSuspend: true
                property int suspend: 3
                property bool notifyFull: true
                property JsonObject chargeLimit: JsonObject {
                    property bool enable: false
                    property int threshold: 80
                }
            }

            property JsonObject calendar: JsonObject {
                property JsonObject externalSync: JsonObject {
                    property bool enable: false
                    property int refreshMinutes: 15
                    property list<var> sources: []
                }
                property bool showUpcoming: true
                property int upcomingDays: 3
                property int maxEventDots: 3
            }

            property JsonObject closeConfirm: JsonObject {
                property bool enabled: false
            }

            property JsonObject conflictKiller: JsonObject {
                property bool autoKillNotificationDaemons: false
                property bool autoKillTrays: false
            }

            property JsonObject crosshair: JsonObject {
                property string code: "0;P;d;1;0l;10;0o;2;1b;0"
            }

            property JsonObject display: JsonObject {
                property string primaryMonitor: ""
            }

            property JsonObject dock: JsonObject {
                property string style: "panel"
                property bool cardStyle: false
                property bool enable: true
                property bool monochromeIcons: true
                property string position: "bottom"
                property real height: 60
                property real iconSize: 35
                property real hoverRegionHeight: 2
                property bool pinnedOnStartup: true
                property bool hoverToReveal: false
                property bool showOnDesktop: true
                property bool showBackground: true
                property bool showDashboardButton: true
                property bool minimizeUnfocused: false
                property bool enableBlurGlass: true
                property bool separatePinnedFromRunning: true
                property bool notificationBadge: true
                property list<string> pinnedApps: ["org.gnome.Nautilus", "firefox", "kitty"]
                property list<string> hiddenPinnedApps: []
                property list<string> ignoredAppRegexes: []
                property list<string> screenList: []
                property bool smartIndicator: true
                property bool showAllWindowDots: true
                property int maxIndicatorDots: 5
                property bool hoverPreview: true
                property int hoverPreviewDelay: 400
                property bool keepPreviewOnClick: false
            }

            property JsonObject controlPanel: JsonObject {
                property string style: "panel"
                property bool keepLoaded: false
                property bool compactMode: true
                property bool showMediaSection: true
                property bool showWeatherSection: true
                property bool showWallpaperSection: true
                property bool showSystemSection: true
                property bool showSlidersSection: true
                property bool showQuickActionsSection: true
                property bool showWallpaperSchemeChips: false
            }

            property JsonObject dashboard: JsonObject {
                property int pageOrderVersion: 1
                property list<string> pageOrder: ["dashboard", "music", "weeklyPlanner"]
                // DASH-F01: explicit JsonAdapter fields are mandatory for
                // round-trip persistence. Keep per-tab layouts in a list of
                // JSON records (not dynamically named Qt object properties).
                property list<var> customTabs: []
                property list<var> customTabLayouts: []
                property string defaultTabId: ""
                property int inactiveMinutes: 0
                property real lastHiddenAtMs: 0
                property string lastPageId: "dashboard"
                property JsonObject music: JsonObject {
                    property bool enable: true
                    property bool showScrollbars: true
                }
                property bool keepLoaded: false
                property bool showHeader: true
                property bool showPowerButtons: true
                property JsonObject appearance: JsonObject {
                    property string density: "comfortable"
                    property real cardOpacity: 1.0
                    property bool showCardTitles: true
                }
                property string subtitle: ""
                property real widthRatio: 0.72
                property real heightRatio: 0.72
                property JsonObject canvas: JsonObject {
                    property real workspaceWidth: 0
                    property real workspaceHeight: 0
                    property int gridSize: 24
                    property bool snap: true
                    property bool autoAdjustSize: true
                    property string gridStyle: "dots"
                    property list<var> widgets: [
                        { id: "welcome", x: 0.00, y: 0.00, w: 0.30, h: 0.18, visible: true },
                        { id: "clock", x: 0.00, y: 0.19, w: 0.30, h: 0.14, visible: true },
                        { id: "system", x: 0.00, y: 0.34, w: 0.30, h: 0.17, visible: true },
                        { id: "github", x: 0.00, y: 0.52, w: 0.30, h: 0.12, visible: true },
                        { id: "notifications", x: 0.31, y: 0.00, w: 0.35, h: 0.25, visible: true },
                        { id: "agenda", x: 0.31, y: 0.26, w: 0.35, h: 0.13, visible: true },
                        { id: "todo", x: 0.31, y: 0.40, w: 0.35, h: 0.24, visible: true },
                        { id: "media", x: 0.67, y: 0.00, w: 0.33, h: 0.62, visible: true },
                        { id: "weather", x: 0.67, y: 0.64, w: 0.33, h: 0.36, visible: true },
                        { id: "calendar", x: 0.00, y: 0.65, w: 0.66, h: 0.35, visible: true },
                        { id: "notes", x: 0.67, y: 0.77, w: 0.33, h: 0.23, visible: false }
                    ]
                }
                property JsonObject github: JsonObject {
                    property string username: ""
                }
            }

            property JsonObject interactions: JsonObject {
                property JsonObject scrolling: JsonObject {
                    property bool fasterTouchpadScroll: false
                    property int mouseScrollDeltaThreshold: 120
                    property int mouseScrollFactor: 120
                    property int touchpadScrollFactor: 450
                }
                property JsonObject deadPixelWorkaround: JsonObject {
                    property bool enable: false
                }
            }

            property JsonObject language: JsonObject {
                property string ui: "auto"
                property JsonObject translator: JsonObject {
                    property string engine: "auto"
                    property string targetLanguage: "en"
                    property string sourceLanguage: "es"
                }
            }

            property JsonObject light: JsonObject {
                property JsonObject night: JsonObject {
                    property bool automatic: true
                    property bool enabled: false
                    property string from: "19:00"
                    property string to: "06:30"
                    property int colorTemperature: 5000
                }
                property JsonObject antiFlashbang: JsonObject {
                    property bool enable: false
                    property bool darkOnly: true
                    property real threshold: 0.30
                    property real strength: 0.90
                    property real minMultiplier: 0.12
                    property int sampleInterval: 500
                    property real sampleScale: 0.10
                    property int windowDelay: 30
                    property int workspaceDelay: 180
                    property int responseMs: 80
                }
            }

            property JsonObject lock: JsonObject {
                property bool useHyprlock: false
                property bool launchOnStartup: false
                property JsonObject blur: JsonObject {
                    property bool enable: true
                    property real radius: 100
                    property real extraZoom: 1.1
                }
                property bool centerClock: true
                property bool showLockedText: true
                property JsonObject security: JsonObject {
                    property bool unlockKeyring: true
                    property bool requirePasswordToPower: false
                }
                property bool materialShapeChars: true
                property bool enableAnimation: false
                property JsonObject dim: JsonObject {
                    property bool enable: false
                    property real opacity: 0.3
                }
                property JsonObject clock: JsonObject {
                    property string style: "default"
                    property string position: "center"
                }
                property JsonObject notifications: JsonObject {
                    property bool enable: false
                    property int maxCount: 3
                    property bool showBody: true
                    property string position: "auto"
                }
                property JsonObject status: JsonObject {
                    property bool enable: true
                }
                property JsonObject widgets: JsonObject {
                    property bool weather: true
                    property bool media: true
                    property bool powerButtons: true
                    property bool hintText: true
                }
            }

            property JsonObject media: JsonObject {
                property bool filterDuplicatePlayers: true
                property string popupMode: "dock"
                property list<string> screenList: []
            }

            property JsonObject hotspot: JsonObject {
                property string ssid: "Alis Hotspot"
                property string password: "alishotspot"
                property string band: "bg"
            }

            property JsonObject keyboardIndicators: JsonObject {
                property bool showPopup: true
                property bool showPanel: true
                property JsonObject popup: JsonObject {
                    property bool layout: true
                    property bool caps: true
                    property bool num: false
                }
                property JsonObject panel: JsonObject {
                    property bool layout: true
                    property bool caps: true
                    property bool num: false
                }
            }

            property JsonObject networking: JsonObject {
                property string userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
            }

            property JsonObject notifications: JsonObject {
                property int timeout: 7000
                property list<string> screenList: []
                property JsonObject quietHours: JsonObject {
                    property bool enable: false
                    property string start: "22:00"
                    property string end: "08:00"
                }
                property int timeoutLow: 5000
                property int timeoutNormal: 7000
                property int timeoutCritical: 0
                property bool ignoreAppTimeout: false
                property int maxPopupLifetime: 30000
                property string position: "topRight"
                property int edgeMargin: 4
                property bool scaleOnHover: false
                property bool silent: false
                property bool useLegacyCounter: true
            }

            // Material notification history surface hosted by the bottom-right
            // ScreenCorners owner. Transient toast placement remains under
            // notifications.* so the two surfaces can be configured independently.
            property JsonObject notificationCenter: JsonObject {
                property bool enable: true
                property bool hoverEnable: true
                property int hoverDelayMs: 220
                property int closeGraceMs: 280
                property int cornerSize: 14
                property int popupWidth: 420
                property int popupHeight: 560
                property bool markReadOnOpen: true
                property bool allowInFullscreen: false
                property list<string> screenList: []
            }

            property JsonObject osd: JsonObject {
                property int timeout: 1000
                property bool mediaEnabled: true
                property list<string> screenList: []
            }

            property JsonObject osk: JsonObject {
                property string layout: "qwerty_full"
                property bool pinnedOnStartup: false
                property bool keepOnTop: false
            }

            property JsonObject overlay: JsonObject {
                property bool openingZoomAnimation: true
                property bool darkenScreen: true
                property real clickthroughOpacity: 0.8
                property real backgroundOpacity: 0.9
                property int scrimDim: 35
                property int animationDurationMs: 180
                property int scrimAnimationDurationMs: 140
                property JsonObject floatingImage: JsonObject {
                    property string imageSource: "https://media.tenor.com/H5U5bJzj3oAAAAAi/kukuru.gif"
                    property real scale: 0.5
                }
            }

            // Bottom-left hover Quick Notes. The popup reuses Notepad state,
            // so these values only control presentation/interaction geometry.
            property JsonObject quickNotes: JsonObject {
                property bool enable: true
                property string monitorMode: "all"
                property int hoverDelayMs: 220
                property int cornerSize: 14
                property int popupWidth: 420
                property int popupHeight: 300
            }

            property JsonObject overview: JsonObject {
                property bool enable: true
                property real scale: 0.17
                property real rows: 3
                property real columns: 1
                property bool centerIcons: true
                property bool backgroundBlurEnable: true
                property int backgroundBlurRadius: 22
                property int backgroundDim: 35
                property int scrimDim: 35
                property int topMargin: 0
                property int bottomMargin: 0
                property bool respectBar: true
                property real maxPanelWidthRatio: 1.0
                property int workspaceSpacing: 5
                property int windowTileMargin: 6
                property int iconMinSize: 0
                property int iconMaxSize: 0
                property bool showWorkspaceNumbers: true
                property bool switchToWorkspaceOnOpen: false
                property int switchWorkspaceIndex: 0
                property bool focusAnimationEnable: true
                property int focusAnimationDurationMs: 180
                property int scrollWorkspaceSteps: 2
                property bool keepOverviewOpenOnWindowClick: true
                property bool closeAfterWindowMove: true
                property bool showPreviews: false
                property bool activeScreenOnly: true
                property bool allAppsGrid: false
                property string allAppsGridMode: "minimal"
                property JsonObject workspaceHover: JsonObject {
                    property bool enable: true
                    property int delayMs: 280
                    property int closeDelayMs: 220
                }
            }

            property JsonObject altSwitcher: JsonObject {
                property string preset: "default"
                property bool noVisualUi: false
                property bool monochromeIcons: false
                property bool enableAnimation: true
                property int animationDurationMs: 200
                property bool useMostRecentFirst: true
                property bool enableBlurGlass: true
                property real backgroundOpacity: 0.9
                property real blurAmount: 0.4
                property int scrimDim: 35
                property string panelAlignment: "right"
                property bool useM3Layout: false
                property bool compactStyle: false
                property bool showOverviewWhileSwitching: false
                property int autoHideDelayMs: 500
            }

            property JsonObject regionSelector: JsonObject {
                property int borderSize: 4
                property int numSize: 48
                property bool rememberSnipChoice: true
                property int lastAction: 0
                property int lastMode: 0
                property JsonObject targetRegions: JsonObject {
                    property bool windows: true
                    property bool layers: false
                    property bool content: true
                    property bool showLabel: false
                    property real opacity: 0.3
                    property real contentRegionOpacity: 0.8
                    property int selectionPadding: 5
                }
                property JsonObject rect: JsonObject {
                    property bool showAimLines: true
                }
                property JsonObject circle: JsonObject {
                    property int strokeWidth: 6
                    property int padding: 10
                }
                property JsonObject annotation: JsonObject {
                    property bool useSatty: false
                    property bool useNativeEditor: true
                }
                property string savePath: ""
                property string screenshotNameFormat: "ss-%Y%m%d-%H%M%S"
            }

            property JsonObject resources: JsonObject {
                property int updateInterval: 3000
                property bool monitorGpu: true
            }

            property JsonObject musicRecognition: JsonObject {
                property int timeout: 16
                property int interval: 4
            }

            property JsonObject voiceSearch: JsonObject {
                property int duration: 5
                property string provider: "auto"
                property string language: "auto"
                property string localModelPath: ""
                property string groqModel: "whisper-large-v3-turbo"
                property string geminiModel: "gemini-2.5-flash"
                property string openaiModel: "gpt-4o-mini-transcribe"
            }

            property JsonObject clipboard: JsonObject {
                property list<string> pinned: []
            }

            property JsonObject search: JsonObject {
                property string style: "default"
                property int nonAppResultDelay: 30
                property string engineBaseUrl: "https://www.google.com/search?q="
                property list<string> excludedSites: ["quora.com", "facebook.com"]
                property bool sloppy: false
                property JsonObject prefix: JsonObject {
                    property bool showDefaultActionsWithoutPrefix: true
                    property string action: "/"
                    property string app: ">"
                    property string clipboard: ";"
                    property string emojis: ":"
                    property string math: "="
                    property string shellCommand: "$"
                    property string webSearch: "?"
                }
                property JsonObject imageSearch: JsonObject {
                    property string imageSearchEngineBaseUrl: "https://yandex.com/images/search?rpt=imageview&url="
                    property string fileUploadApiEndpoint: "https://0x0.st"
                    property string fileUploadApiFallback: "https://litterbox.catbox.moe/resources/internals/api.php"
                    property string fileUploadApiFallback2: "https://catbox.moe/user/api.php"
                    property bool useCircleSelection: false
                }
                property JsonObject globalActions: JsonObject {
                    property bool enableSystem: true
                    property bool enableAppearance: true
                    property bool enableTools: true
                    property bool enableMedia: true
                    property bool enableSettings: true
                    property bool enablePackages: true
                    property bool enableSetup: true
                    property bool enableCustom: true
                }
            }

            property JsonObject sidebar: JsonObject {
                property string style: "panel"
                property bool cardStyle: false
                property list<string> screenList: []
                property string layout: "default"
                property bool keepRightSidebarLoaded: true
                property bool keepLeftSidebarLoaded: true
                property bool collapseEmptyNotifications: false
                property bool collapseWidgetsTab: false
                property JsonObject shellLayout: JsonObject {
                    property JsonObject feature: JsonObject {
                        property string slot: "left"
                        property string sizeMode: "full"
                        property int customHeight: 720
                        property int width: 460
                    }
                    property JsonObject system: JsonObject {
                        property string slot: "right"
                        property string sizeMode: "full"
                        property int customHeight: 720
                        property int width: 460
                    }
                }
                property bool openFolderOnDownload: false
                property JsonObject translator: JsonObject {
                    property bool enable: false
                    property int delay: 300
                }
                property JsonObject ai: JsonObject {
                    property bool textFadeIn: false
                }
                property JsonObject booru: JsonObject {
                    property bool allowNsfw: false
                    property string defaultProvider: "yandere"
                    property int limit: 20
                    property JsonObject gelbooru: JsonObject {
                        property string apiKey: ""
                        property string userId: ""
                    }
                    property JsonObject zerochan: JsonObject {
                        property string username: "[unset]"
                    }
                    property JsonObject downloadPath: JsonObject {
                        property string sfw: ""
                        property string nsfw: ""
                    }
                }
                property JsonObject wallhaven: JsonObject {
                    property bool enable: true
                    property int limit: 24
                    property string fitMode: "auto"
                    property string apiKey: ""
                }
                property JsonObject news: JsonObject {
                    property bool enable: true
                    property string mode: "local"
                    property string topic: "WORLD"
                }
                property JsonObject animeSchedule: JsonObject {
                    property bool enable: false
                    property bool showNsfw: false
                    property string watchSite: ""
                }
                property JsonObject tools: JsonObject {
                    property bool enable: false
                }
                property JsonObject software: JsonObject {
                    property bool enable: false
                }
                property JsonObject plugins: JsonObject {
                    property bool enable: false
                    property string lastActivePlugin: ""
                }
                // Canonical local Music frontend. MPD owns the library/queue and
                // mpd-mpris exposes that same session through the shell's MPRIS path.
                // libraryFolder is only an optional local-path override for cover art.
                property JsonObject music: JsonObject {
                    property bool enable: false
                    property string libraryFolder: ""
                    property string mpdHost: "127.0.0.1"
                    property int mpdPort: 6600
                }
                property JsonObject ytmusic: JsonObject {
                    property bool enable: false
                    property bool autoConnect: true
                    property bool hideSyncBanner: false
                    property string browser: "firefox"
                    property string cookiesPath: ""
                    property bool useManualCookies: false
                    property bool connected: false
                    property string resolvedBrowserArg: ""
                    property string audioQuality: "best"
                    property bool normalizeVolume: true
                    property bool verbose: false
                    property bool shuffleMode: false
                    property int repeatMode: 0
                    property list<string> recentSearches: []
                    property list<var> queue: []
                    property list<var> playlists: []
                    property list<var> liked: []
                    property string lastLikedSync: ""
                    property bool upNextNotifications: true
                    property bool suppressUpNextInFullscreen: true
                    property int volume: 100
                    property JsonObject profile: JsonObject {
                        property string name: ""
                        property string avatar: ""
                        property string url: ""
                    }
                    property JsonObject cache: JsonObject {
                        property list<var> playlists: []
                        property list<var> albums: []
                        property list<var> liked: []
                    }
                    property JsonObject resume: JsonObject {
                        property string videoId: ""
                        property string title: ""
                        property string artist: ""
                        property string thumbnail: ""
                        property string url: ""
                        property real position: 0
                        property bool wasPlaying: false
                        property list<var> activePlaylist: []
                        property int currentIndex: -1
                        property string activePlaylistSource: ""
                    }
                }
                property JsonObject widgets: JsonObject {
                    property bool enable: true
                    property bool media: true
                    property bool week: true
                    property bool context: true
                    property bool note: false
                    property bool launch: false
                    property bool controls: true
                    property bool status: true
                    property bool crypto: false
                    property bool wallpaper: false
                    property bool worldClock: false
                    property bool contextShowWeather: true
                    property list<string> widgetOrder: ["context", "week", "media", "note", "launch", "controls", "status", "crypto", "wallpaper", "worldclock"]
                    property int spacing: 8
                    property JsonObject glance: JsonObject {
                        property bool showVolume: true
                        property bool showGameMode: true
                        property bool showDnd: true
                    }
                    property JsonObject statusRings: JsonObject {
                        property bool showCpu: true
                        property bool showRam: true
                        property bool showDisk: true
                        property bool showTemp: true
                        property bool showBattery: true
                    }
                    property JsonObject controlsCard: JsonObject {
                        property bool showDarkMode: true
                        property bool showDnd: true
                        property bool showNightLight: true
                        property bool showGameMode: true
                        property bool showNetwork: true
                        property bool showBluetooth: true
                        property bool showSettings: true
                        property bool showLock: true
                    }
                    property JsonObject crypto_settings: JsonObject {
                        property int refreshInterval: 300
                        property list<string> coins: ["bitcoin", "ethereum"]
                    }
                    property JsonObject worldClock_settings: JsonObject {
                        property list<string> timezones: []
                        property bool showSeconds: false
                        property bool use24Hour: true
                        property bool showDate: true
                        property bool highlightLocal: true
                    }
                    property list<var> quickLaunch: [
                        { "icon": "folder", "name": "Files", "cmd": "/usr/bin/nautilus" },
                        { "icon": "terminal", "name": "Terminal", "cmd": "/usr/bin/kitty" },
                        { "icon": "web", "name": "Browser", "cmd": "/usr/bin/firefox" },
                        { "icon": "code", "name": "Code", "cmd": "/usr/bin/code" }
                    ]
                    property JsonObject quickWallpaper: JsonObject {
                        property int itemSize: 72
                        property bool showHeader: true
                    }
                }
                property JsonObject cornerOpen: JsonObject {
                    property bool enable: false
                    property bool bottom: false
                    property bool valueScroll: true
                    property bool clickless: false
                    property int cornerRegionWidth: 250
                    property int cornerRegionHeight: 5
                    property bool visualize: false
                    property bool clicklessCornerEnd: true
                    property int clicklessCornerVerticalOffset: 1
                }
                property JsonObject edgeOpen: JsonObject {
                    property bool enable: false
                    property int regionWidth: 2
                }
                property JsonObject quickToggles: JsonObject {
                    property string style: "android"
                    property JsonObject android: JsonObject {
                        property int columns: 4
                        property list<var> toggles: [
                            { "size": 1, "type": "network" },
                            { "size": 1, "type": "bluetooth" },
                            { "size": 1, "type": "audio" },
                            { "size": 1, "type": "mic" }
                        ]
                    }
                }
                property JsonObject quickSliders: JsonObject {
                    property bool enable: true
                    property bool showMic: true
                    property bool showVolume: true
                    property bool showBrightness: true
                }
                property JsonObject left: JsonObject {
                    property list<string> tabOrder: ["ai", "translator", "anime", "animeSchedule", "news", "tools"]
                }
                property JsonObject right: JsonObject {
                    property list<string> enabledWidgets: ["calculator", "sysmon"]
                    property list<string> controlsSectionOrder: ["sliders", "toggles", "devices", "media", "quickActions"]
                    property list<string> sectionOrder: ["system", "sliders", "toggles", "widgets"]
                    property string headerStyle: "profile"
                    property string headerBanner: "wallpaper"
                    property string headerBannerPath: ""
                    property JsonObject sectionWeights: JsonObject {
                        property real notifications: 1
                        property real widgets: 1
                    }
                }
                property JsonObject screenTime: JsonObject {
                    property bool enable: false
                    property int pollIntervalSeconds: 5
                    property int retentionDays: 30
                }
            }

            property JsonObject sounds: JsonObject {
                property bool battery: false
                property bool timer: false
                property bool pomodoro: false
                property string theme: "freedesktop"
                property bool notifications: true
                property real volume: 0.5
                property JsonObject events: JsonObject {
                    property string notification: ""
                    property string notificationCritical: ""
                    property string batteryLow: ""
                    property string batteryCritical: ""
                    property string batteryFull: ""
                    property string powerPlug: ""
                    property string powerUnplug: ""
                    property string pomodoroDone: ""
                    property string timerDone: ""
                }
            }

            property JsonObject time: JsonObject {
                property string format: "hh:mm"
                property string shortDateFormat: "dd/MM"
                property string dateFormat: "ddd, dd/MM"
                property JsonObject pomodoro: JsonObject {
                    property int breakTime: 300
                    property int cyclesBeforeLongBreak: 4
                    property int focus: 1500
                    property int longBreak: 900
                }
                property bool secondPrecision: false
            }

            property JsonObject wallpapers: JsonObject {
                property string directory: ""
            }

            property JsonObject wallpaperSelector: JsonObject {
                property bool useSystemFileDialog: false
                property string selectionTarget: "main"
                property string targetMonitor: ""
                property string style: "caelestia"
                property string coverflowView: "gallery"
            }

            property JsonObject screenRecord: JsonObject {
                property JsonObject recordingOsd: JsonObject {
                    property bool autoHide: false
                }
                property bool showOsd: false
                property bool showNotifications: true
                property string savePath: ""
                property string qualityPreset: "balanced"
                property string videoCodec: "libx264"
                property string audioCodec: "aac"
                property string accelerationMode: "auto"
                property string hardwareDevice: "/dev/dri/renderD128"
                property int fps: 60
                property int videoBitrateKbps: 12000
                property int audioBitrateKbps: 192
                property string audioMode: "system"
                property string audioSource: ""
                property string systemAudioSource: ""
                property string microphoneSource: ""
                property string audioBackend: ""
                property int audioSampleRate: 48000
                property string pixelFormat: "yuv420p"
                property string preset: "veryfast"
                property int crf: 21
                property string vaapiFilter: "scale_vaapi=format=nv12:out_range=full"
                property bool enableFallback: true
                property string recordingNameFormat: "recording_%Y-%m-%d_%H.%M.%S"
                property JsonObject discordCompress: JsonObject {
                    property bool enabled: false
                    property real targetSizeMb: 10
                    property real safetyMarginMb: 0.5
                    property bool onlyIfNeeded: true
                    property int audioBitrateKbps: 96
                    property string preset: "slow"
                    property int maxDimension: 1280
                }
            }

            property JsonObject windows: JsonObject {
                property bool showTitlebar: true
                property bool centerTitle: true
                property list<var> appIdentityRules: []
            }

            property JsonObject settingsUi: JsonObject {
                property bool overlayMode: true
                property string overlayStyle: "rail"
                property string categories: ""
                property string chromeLayout: ""
                property JsonObject overlayAppearance: JsonObject {
                    property int scrimDim: 35
                    property real backgroundOpacity: 1.0
                    property int backdropBlur: 0
                }
            }

            property JsonObject hacks: JsonObject {
                property int arbitraryRaceConditionDelay: 20
            }

            property JsonObject tray: JsonObject {
                property bool monochromeIcons: true
                property bool showItemId: false
                property bool invertPinnedItems: true
                property list<string> pinnedItems: []
                property bool filterPassive: true
            }
            property JsonObject updates: JsonObject {
                property int checkInterval: 120
                property int adviseUpdateThreshold: 75
                property int stronglyAdviseUpdateThreshold: 200
            }
            property JsonObject shellUpdates: JsonObject {
                property bool enabled: true
                property int checkIntervalMinutes: 360
                property string dismissedCommit: ""
                property string lastNotifiedCommit: ""
                property bool openTerminalOnUpdate: true
            }
            property JsonObject bootGreeting: JsonObject {
                property bool enable: false
                property int autoDismissDelay: 5000
                property bool showWeather: true
                property bool showDate: true
            }
            property JsonObject welcomeWizard: JsonObject {
                property bool completed: false
                property bool skipped: false
                property string profile: "balanced"
            }

            property JsonObject waffles: JsonObject {
                property JsonObject settings: JsonObject {
                    property bool useMaterialStyle: false
                }
                property JsonObject modules: JsonObject {
                    property bool sidebarLeft: false
                    property bool sidebarRight: false
                    property bool dock: false
                    property bool mediaControls: false
                    property bool screenCorners: false
                    property bool widgets: true
                }
                property JsonObject tweaks: JsonObject {
                    property bool smootherMenuAnimations: true
                    property bool switchHandlePositionFix: true
                }
                property JsonObject altSwitcher: JsonObject {
                    property string preset: "thumbnails"
                    property bool noVisualUi: false
                    property bool monochromeIcons: false
                    property bool enableAnimation: true
                    property int animationDurationMs: 300
                    property real backgroundOpacity: 1.0
                    property real blurAmount: 0.0
                    property int scrimDim: 0
                    property int autoHideDelayMs: 500
                    property bool showOverviewWhileSwitching: false
                    property bool compactStyle: false
                    property string panelAlignment: "center"
                    property bool useM3Layout: false
                    property bool useMostRecentFirst: true
                    property bool quickSwitch: false
                    property bool autoHide: true
                    property bool closeOnFocus: true
                    property int thumbnailWidth: 280
                    property int thumbnailHeight: 180
                    property real scrimOpacity: 0.4
                }
                property JsonObject background: JsonObject {
                    property string wallpaperPath: ""
                    property string thumbnailPath: ""
                    property bool useMainWallpaper: true
                    property bool enableAnimation: true
                    property bool hideWhenFullscreen: true
                    property JsonObject transition: JsonObject {
                        property bool enable: true
                        property string type: "alisMelt"
                        property string direction: "right"
                        property int duration: 800
                    }
                    property JsonObject effects: JsonObject {
                        property bool enableBlur: false
                        property int blurRadius: 32
                        property int dim: 0
                        property int dynamicDim: 0
                        property bool enableAnimatedBlur: false
                        property int thumbnailBlurStrength: 70
                    }
                    property JsonObject backdrop: JsonObject {
                        property bool enable: true
                        property bool hideWallpaper: false
                        property bool useMainWallpaper: true
                        property string wallpaperPath: ""
                        property string thumbnailPath: ""
                        property bool enableAnimation: false
                        property bool enableAnimatedBlur: false
                        property int blurRadius: 32
                        property int dim: 35
                        property real saturation: 0
                        property real contrast: 0
                        property bool vignetteEnabled: false
                        property real vignetteIntensity: 0.5
                        property real vignetteRadius: 0.7
                    }
                    property JsonObject parallax: JsonObject {
                        property bool enable: false
                        property string axis: "horizontal"
                        property bool vertical: false
                        property bool autoVertical: true
                        property bool enableWorkspace: false
                        property real workspaceShift: 1.0
                        property real workspaceZoom: 1.0
                        property real zoom: 1.0
                        property bool enableSidebar: false
                        property real panelShift: 0.12
                        property real widgetsFactor: 1.0
                        property real widgetDepth: 1.0
                        property bool pauseDuringTransitions: true
                        property int transitionSettleMs: 220
                    }
                    property JsonObject widgets: JsonObject {
                        property JsonObject clock: JsonObject {
                            property bool enable: false
                            property string placementStrategy: "leastBusy"
                            property int x: 100
                            property int y: 100
                            property int dim: 55
                            property string fontFamily: "Segoe UI Variable Display"
                            property string style: "hero"
                            property string timeFormat: "system"
                            property string dateStyle: "long"
                            property string colorMode: "adaptive"
                            property bool showDate: true
                            property bool showSeconds: false
                            property bool showShadow: true
                            property bool showLockStatus: true
                            property int timeScale: 100
                            property int dateScale: 100
                            property JsonObject digital: JsonObject {
                                property bool animateChange: true
                            }
                        }
                    }
                }
                property JsonObject bar: JsonObject {
                    property bool bottom: true
                    property bool leftAlignApps: false
                    property bool monochromeIcons: false
                    property bool tintTrayIcons: false
                    property int iconSize: 26
                    property int searchIconSize: 24
                    property list<string> screenList: []
                    property JsonObject activationWatermark: JsonObject {
                        property bool enable: false
                    }
                    property JsonObject desktopPeek: JsonObject {
                        property bool hoverPeek: false
                        property int hoverDelay: 500
                    }
                    property JsonObject notifications: JsonObject {
                        property bool showUnreadCount: true
                    }
                }
                property JsonObject notifications: JsonObject {
                    property bool showUnreadCount: true
                }
                property JsonObject actionCenter: JsonObject {
                    property list<string> toggles: ["network", "hotspot", "bluetooth", "easyEffects", "powerProfile", "idleInhibitor", "nightLight", "darkMode", "antiFlashbang", "cloudflareWarp", "mic", "musicRecognition", "notifications", "onScreenKeyboard", "gameMode", "screenSnip", "colorPicker"]
                }
                property JsonObject calendar: JsonObject {
                    property bool force2CharDayOfWeek: true
                    property string locale: ""
                }
                property JsonObject theming: JsonObject {
                    property bool useMaterialColors: true
                    property JsonObject font: JsonObject {
                        property string family: "Noto Sans"
                        property real scale: 1.0
                    }
                }
                property JsonObject startMenu: JsonObject {
                    property string sizePreset: "normal"
                    property real scale: 1.0
                }
                property JsonObject behavior: JsonObject {
                    property bool allowMultiplePanels: false
                }
                property JsonObject widgetsPanel: JsonObject {
                    property bool showDateTime: true
                    property bool showWeather: true
                    property bool showSystem: true
                    property bool showMedia: true
                    property bool showQuickActions: true
                    property list<string> quickActions: ["files", "terminal", "settings", "wallpaper", "screenshot", "screenRecord", "session"]
                    property bool weatherHideLocation: false
                    property bool showFiles: true
                    property bool showTerminal: true
                    property bool showSettings: true
                    property bool showWallpaper: true
                    property bool showScreenshot: true
                    property bool showScreenRecord: true
                    property bool showSession: true
                    property bool showColorScheme: true
                }
                property JsonObject workspaceNames: JsonObject {
                }
                property JsonObject taskView: JsonObject {
                    property string mode: "centered"
                    property bool closeOnSelect: false
                }
            }
            property JsonObject integrations: JsonObject {
                property JsonObject hadalird: JsonObject {
                    property bool tlp: false
                    property bool thinkfan: false
                    property bool obsidian: false
                }
                property JsonObject obsidian: JsonObject {
                    property bool autoTheme: false
                    property string configPath: ""
                    property string applicationConfigPath: ""
                    property string applicationPath: "obsidian"
                }
            }

            property JsonObject todo: JsonObject {
                property string backend: "internal"
                property JsonObject obsidian: JsonObject {
                    property string vaultPath: ""
                    property string sourceMode: "markdown-note"
                    property string notePath: "Hadalis/Todo.md"
                    property string scope: "managed-section"
                    property JsonObject dailyNote: JsonObject {
                        property string folder: "00_Capture/01_Journal"
                        property string format: "YYYY/MMMM/DD-MM-YYYY-dddd"
                        property string plannerHeading: "Tasks"
                        property int plannerHeadingLevel: 2
                        property int defaultDurationMinutes: 30
                    }
                    property bool preferTasksPlugin: true
                    property bool allowBasicOfflineMutation: true
                }
            }

            property JsonObject notes: JsonObject {
                property JsonObject zettelkasten: JsonObject {
                    // Legacy Quick Notes override, read only as fallback when the
                    // shared Todo vault is empty. Do not add a second UI field.
                    property string vaultPath: ""
                    property string folder: "00_Capture/03_Zettelkasten"
                    property string defaultType: "Fleeting"
                }
            }

            property JsonObject workSafety: JsonObject {
                property JsonObject enable: JsonObject {
                    property bool wallpaper: false
                    property bool clipboard: false
                }
                property JsonObject triggerCondition: JsonObject {
                    property list<string> networkNameKeywords: ["airport", "cafe", "college", "company", "eduroam", "free", "guest", "public", "school", "university"]
                    property list<string> fileKeywords: ["anime", "booru", "ecchi", "hentai", "yande.re", "konachan", "breast", "nipples", "pussy", "nsfw", "spoiler", "girl"]
                    property list<string> linkKeywords: ["hentai", "porn", "sukebei", "hitomi.la", "rule34", "gelbooru", "fanbox", "dlsite"]
                }
            }
        }
    }
}
