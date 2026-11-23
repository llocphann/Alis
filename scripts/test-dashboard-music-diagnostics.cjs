#!/usr/bin/env node
"use strict";
// Exercise the REAL QML LocalMusic payload reducer with fake MPD status.
// This is a user-local deterministic fixture: never opens sockets/MPD, never
// touches an owner's music library or invokes transport commands.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const root = path.resolve(__dirname, "..");
const service = fs.readFileSync(path.join(root, "services/LocalMusic.qml"), "utf8");
const dashboard = fs.readFileSync(path.join(root, "modules/dashboard/DashboardMusic.qml"), "utf8");

const marker = "function _applyPayload(payload, includeLibrary = false): void {";
const start = service.indexOf(marker);
assert(start >= 0, "Live MPD payload reducer missing");
const bodyStart = service.indexOf("{", start);
let depth = 0, finish = -1;
for (let i = bodyStart; i < service.length; i++) {
    if (service[i] === "{") depth++;
    if (service[i] === "}" && --depth === 0) {finish = i + 1; break;}
}
assert(finish > bodyStart, "MPD reducer block unbalanced");
const declaration = service.slice(start, finish).replace("): void {", ") {");
const context = {
    error: "", mpdConnected: false, mpdHost: "127.0.0.1", mpdPort: 6600,
    mpdState: "stop", activeQueue: [], libraryTracks: [], playlists: [],
    currentIndex: -1, currentQueueId: -1, resumeIndex: -1, currentUri: "", currentPath: "",
    currentTitle: "", currentArtist: "", currentAlbum: "", currentArt: "",
    currentPosition: 0, currentDuration: 0, volume: 0.5, shuffleMode: false,
    repeatMode: 0, detectedLibraryFolder: "",
    _lastMpdPositionSampleMs: 0,
    _safeValidDuration(v) { const n = Number(v); return Number.isFinite(n) && n > 0 && n <= 86400 ? n : 0; },
    MprisController: {ensureMpdMprisBridge() {}},
    _applyCurrentTrack() {throw Error("unexpected playback mutation");},
};
context.root = context;
vm.createContext(context);
const apply = vm.runInContext("(" + declaration + ")", context);
const emptyQueue = [];
apply({connected: true, queue: emptyQueue,
       status: {state: "stop", song: -1,
                error: "Failed to decode FLAC test fixture"}});
assert.equal(context.error, "Failed to decode FLAC test fixture");
assert.equal(context.mpdConnected, true, "connected decoder failures must not imply network loss");
assert.equal(context.activeQueue, emptyQueue, "error display changed queue identity");
assert.equal(context.currentIndex, -1);
apply({connected: true, queue: emptyQueue,
       status: {state: "stop", song: -1}});
assert.equal(context.error, "", "recovery left stale MPD warning");
apply({connected: false, error: "MPD socket unavailable"});
assert.equal(context.error, "MPD socket unavailable");
assert.equal(context.mpdConnected, false);

// Dashboard uses exactly the existing backend signal, never a second MPD
// poller or independent audio backend. Hidden banners allocate zero viewport.
for (const token of [
    'readonly property string backendError: String(root.backend?.error ?? "")',
    'readonly property bool showErrorBanner: !root.backendAvailable || root.backendError.length > 0',
    'objectName: "musicBackendError"',
    'visible: root.showErrorBanner',
    '? root.backendError'
]) assert(dashboard.includes(token), "Dashboard missing error contract: " + token);
console.log("DASHBOARD_MPD_DIAGNOSTIC_PASS decoder errors visible, recovery clears, queue unchanged");
