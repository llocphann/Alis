#!/usr/bin/env node
/* Offline fixtures for AUTO-F01 read-only renderer diagnostics. */
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {pathToFileURL} from "node:url";
import {matchScopeCandidate, staticScopeCandidate, probeDesktopScopeReadOnly} from
  "../automation/chat_bridge/scope_probe.mjs";

const candidate = "async startCompletionStream() {}" + "0".repeat(9000) +
  ",T=mk(q,({scope:e})=>new Constructor(e));export{T as exportedScope}";
assert.equal(matchScopeCandidate(candidate).exportAlias, "exportedScope");
assert.throws(() => matchScopeCandidate(candidate.replace("export{T as exportedScope}", "")),
  /export list unavailable/);
assert.throws(() => matchScopeCandidate(candidate + ",T2=mk(q,({scope:x})=>new Other(x))"),
  /scope constructor not unique/);
assert.throws(() => matchScopeCandidate(candidate.replace("startCompletionStream", "stopCompletionStream")),
  /stream method not unique/);

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "alis-scope-probe-"));
try {
  const initialName = "app-initial-fixture.js";
  const initial = Buffer.from(candidate);
  const shared = Buffer.from("export {}");
  const archive = {
    files: {webview: {files: {assets: {files: {
      [initialName]: {size: initial.length, offset: "0"},
      "app-shared-fixture.js": {size: shared.length, offset: String(initial.length)}
    }}}}}
  };
  const headJSON = Buffer.from(JSON.stringify(archive));
  const head = Buffer.alloc(16);
  head.writeUInt32LE(8 + headJSON.length, 4);
  head.writeUInt32LE(headJSON.length, 12);
  const asarPath = path.join(dir, "fixture.asar");
  fs.writeFileSync(asarPath, Buffer.concat([head, headJSON, initial, shared]));
  const staticResult = staticScopeCandidate(asarPath);
  assert.equal(staticResult.exportAlias, "exportedScope");
  assert.equal(staticResult.initialName, initialName);
  assert.equal(staticResult.fingerprintPrefix.length, 12);

  // Mock CDP strictly inspects arguments and does not run the renderer
  // callback, ensuring any future accidental send code is rejected by test.
  const mockPath = path.join(dir, "playwright.mjs");
  fs.writeFileSync(mockPath, String.raw