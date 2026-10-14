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
    const mockLines = [
    'export const chromium = {',
    '  async connectOverCDP(url) {',
    '    if (url !== "http://127.0.0.1:9222") throw Error("bad CDP target");',
    '    return {',
    '      contexts: () => [{pages: () => [{',
    '        url: () => "app://-/index.html",',
    '        async evaluate(fn, args) {',
    '          if (args.alias !== "exportedScope" || args.asset !== "app-initial-fixture.js")',
    '            throw Error("unverified module binding");',
    '          const source = fn.toString();',
    '          if (source.includes(".startCompletionStream(") ||',
    '              source.includes(".prepareCompletionStream(") ||',
    '              source.includes("fetch("))',
    '            throw Error("read-only probe attempted a send or network call");',
    '          return {',
    '            exported_definition_present:true, scope_id_present:true,',
    '            resolve_function_present:true, provider_map_count:1,',
    '            resolution_attempted:true, prepare_function_present:true,',
    '            start_function_present:true, query_cache_present:true',
    '          };',
    '        }',
    '      }]}],',
    '      async close() {}',
    '    };',
    '  }',
    '};'
  ];
  fs.writeFileSync(mockPath, mockLines.join("\n"));
  const report = await probeDesktopScopeReadOnly({
    asarPath, playwrightModule: pathToFileURL(mockPath).href
  });
  assert.equal(report.supported, false);
  assert.equal(report.submission_authorized, false);
  assert.equal(report.prepare_function_present, true);
  assert.equal(report.start_function_present, true);
  assert.equal(report.fingerprint_prefix.length, 12);
  assert.ok(!JSON.stringify(report).includes("exportedScope"));
  assert.ok(!JSON.stringify(report).includes("Constructor"));

  await assert.rejects(
    () => probeDesktopScopeReadOnly({
      asarPath, playwrightModule: pathToFileURL(mockPath).href,
      cdpUrl: "http://example.com:9222"
    }), /CDP must use loopback/);
} finally {
  fs.rmSync(dir, {force:true, recursive:true});
}
console.log("PASS: AUTO-F01 unique scope-export match and isolated read-only runtime probe");
