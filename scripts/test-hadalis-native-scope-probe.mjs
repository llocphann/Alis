#!/usr/bin/env node
/* Offline fixtures for AUTO-F01 read-only renderer diagnostics. */
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {pathToFileURL} from "node:url";
import {matchScopeCandidate, staticScopeCandidate, probeDesktopScopeReadOnly,
  inspectRendererScopeReadOnly} from "../automation/chat_bridge/scope_probe.mjs";

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
// Run the EXACT renderer callback with fake React Fibers. These objects never
// leave the local test; no Desktop, account or network connection is involved.
const scopeId = {};
let resolves = 0;
const transport = {
  prepareCompletionStream() {},
  startCompletionStream() {},
  scope: {queryClient: {getQueryCache() {}}}
};
const provider = {store: {get() {return transport;}}};
const def = {
  scope: {id: scopeId},
  resolve(p, map) {
    assert.equal(p, provider);
    assert.ok(map instanceof Map);
    resolves++;
    return "read-only-fixture";
  }
};
function rootsFor(currentMap, alternateMap = currentMap) {
  const rootState = {current: null};
  const currentRoot = {stateNode: rootState, child: null, alternate: null};
  const alternateRoot = {stateNode: rootState, child: null, alternate: currentRoot};
  currentRoot.alternate = alternateRoot;
  rootState.current = currentRoot;
  const currentChild = {
    return: currentRoot, memoizedProps: {value: currentMap}, sibling: null
  };
  const alternateChild = {
    return: alternateRoot, memoizedProps: {value: alternateMap}, sibling: null
  };
  currentRoot.child = currentChild;
  alternateRoot.child = alternateChild;
  currentChild.alternate = alternateChild;
  alternateChild.alternate = currentChild;
  return {currentRoot, alternateRoot, currentChild, alternateChild};
}
const inspect = roots => inspectRendererScopeReadOnly({
  asset: "not-used-in-Node-test", alias: "fixtureExport",
  fixture: {definition: def, anchors: roots}
});
const sharedMap = new Map([[scopeId, provider]]);
const duplicated = rootsFor(sharedMap);
let res = await inspect([duplicated.currentRoot]);
assert.equal(res.provider_map_count, 2, "current + alternate report as two hits");
assert.equal(res.unique_provider_map_count_capped, 1);
assert.equal(res.active_provider_map_count_capped, 1);
assert.equal(res.unique_provider_identity_count_capped, 1);
assert.equal(res.alternate_only_provider_map_count_capped, 0);
assert.equal(res.provider_selection, "unique_active_and_full_tree");
assert.equal(res.resolution_attempted, true);
assert.equal(res.prepare_function_present, true);
assert.equal(res.start_function_present, true);
assert.equal(res.query_cache_present, true);
assert.equal(res.active_root_count_capped, 1);
assert.equal(res.fiber_scan_truncated, false);
assert.equal(resolves, 1);

resolves = 0;
const differentMap = new Map([[scopeId, provider]]);
const alternateOnly = rootsFor(sharedMap, differentMap);
res = await inspect([alternateOnly.currentRoot]);
assert.equal(res.provider_map_count, 2);
assert.equal(res.unique_provider_map_count_capped, 2);
assert.equal(res.active_provider_map_count_capped, 1);
assert.equal(res.unique_provider_identity_count_capped, 1);
assert.equal(res.alternate_only_provider_map_count_capped, 1);
assert.equal(res.distinct_maps_share_provider_identity, true);
assert.equal(res.provider_selection, "alternate_or_duplicate_provider_unresolved");
assert.equal(res.resolution_attempted, false);
assert.equal(resolves, 0, "never resolve an alternate-only distinct map");

const multipleActive = rootsFor(sharedMap);
multipleActive.currentChild.sibling = {
  return: multipleActive.currentRoot, memoizedProps: {value: differentMap}
};
res = await inspect([multipleActive.currentRoot]);
assert.equal(res.active_provider_map_count_capped, 2);
assert.equal(res.provider_selection, "active_provider_ambiguous");
assert.equal(resolutionAttempted(res), false);
assert.equal(resolves, 0);

// Owner's Desktop had seven distinct active Map objects with one provider
// identity. Never treat content equivalence as Map-identity equivalence or
// authorize a transport resolver from these read-only observations.
function inspectSeven(maps) {
  const tree = rootsFor(maps[0]);
  let cursor = tree.currentChild;
  for (const map of maps.slice(1)) {
    cursor.sibling = {return: tree.currentRoot,
      memoizedProps: {value: map}, sibling: null};
    cursor = cursor.sibling;
  }
  return inspect([tree.currentRoot]);
}
const sevenMaps = Array.from({length: 7}, () =>
  new Map([[scopeId, provider]]));
resolves = 0;
res = await inspectSeven(sevenMaps);
assert.equal(res.active_provider_map_count_capped, 7);
assert.equal(res.active_provider_identity_count_capped, 1);
assert.equal(res.active_map_comparison_complete, true);
assert.equal(res.active_map_topology_complete, true);
assert.deepEqual(res.active_map_depth_range_capped, [1, 1]);
assert.equal(res.active_map_ancestor_pair_count_capped, 0);
assert.deepEqual(res.active_map_ancestor_edges, []);
assert.equal(res.active_map_depth_limit_reached, false);
assert.equal(res.active_map_incomparable_pair_count_capped, 21);
assert.equal(res.active_map_depth_size_profiles.length, 7);
assert.equal(res.resolver_source_inspected, true);
assert.notEqual(res.resolver_length_band, "unknown");
assert.equal(res.active_maps_have_equal_key_sets, true);
assert.equal(res.active_maps_have_equal_entries_by_identity, true);
assert.equal(res.active_maps_have_nested_key_sets, true);
assert.deepEqual(res.active_map_size_range_capped, [1, 1]);
assert.equal(res.resolution_attempted, false);
assert.equal(res.provider_selection, "active_provider_ambiguous");
assert.equal(resolves, 0);

const contextKey = {};
const layered = sevenMaps.map((_, i) =>
  new Map([[scopeId, provider], ...(i > 0 ? [[contextKey, i]] : [])]));
res = await inspectSeven(layered);
assert.equal(res.active_map_comparison_complete, true);
assert.equal(res.active_maps_have_equal_key_sets, false);
assert.equal(res.active_maps_have_equal_entries_by_identity, false);
assert.equal(res.active_maps_have_nested_key_sets, true);
assert.deepEqual(res.active_map_size_range_capped, [1, 2]);
assert.equal(res.resolution_attempted, false);
assert.equal(resolves, 0);

const reversed = [
  new Map([[scopeId,provider],[contextKey,1]]),
  new Map([[scopeId,provider],[contextKey,2]])
];
res = await inspectSeven(reversed);
assert.equal(res.active_maps_have_equal_key_sets, true);
assert.equal(res.active_maps_have_equal_entries_by_identity, false);
assert.equal(res.active_maps_have_nested_key_sets, true);
assert.equal(res.resolution_attempted, false);
assert.equal(resolves, 0);

// A genuinely nested scope context is distinguishable from seven sibling
// branches, but no nesting topology is enough to authorize a resolver.
const nested = rootsFor(sharedMap);
nested.currentChild.child = {
  return: nested.currentChild,
  memoizedProps: {value: differentMap},
  sibling: null
};
res = await inspect([nested.currentRoot]);
assert.equal(res.active_provider_map_count_capped, 2);
assert.equal(res.active_map_ancestor_pair_count_capped, 1);
assert.deepEqual(res.active_map_ancestor_edges, [[0, 1]]);
assert.equal(res.active_map_incomparable_pair_count_capped, 0);
assert.deepEqual(res.active_map_depth_range_capped, [1, 2]);
assert.deepEqual(res.active_map_depth_size_profiles.map(x => x.min_depth), [1, 2]);
assert.equal(res.provider_selection, "active_provider_ambiguous");
assert.equal(res.resolution_attempted, false);

// The original depth=128 ceiling obscured most real Desktop providers.
const deep = rootsFor(sharedMap);
let deepCursor = deep.currentChild;
for (let i=0; i<180; i++) {
  deepCursor = {child:deepCursor, sibling:null};
}
deep.currentRoot.child = deepCursor;
res = await inspect([deep.currentRoot]);
assert.deepEqual(res.active_map_depth_range_capped, [181,181]);
assert.equal(res.active_map_depth_limit_reached, false);

const originalResolver = def.resolve;
def.resolve = function resolve(p,map) {return map.get(scopeId);};
resolves = 0;
res = await inspectSeven(sevenMaps);
assert.equal(res.resolver_source_inspected, true);
assert.equal(res.resolver_parameter_shape, "two-simple-identifiers");
assert.equal(res.resolver_first_argument_map_access, false);
assert.equal(res.resolver_second_argument_map_access, true);
assert.equal(res.resolution_attempted, false);
assert.equal(resolves, 0);
def.resolve = originalResolver;

// The inspected function can contain private data. Source content and symbol
// names must never leave the Desktop; test the exact renderer callback.
def.resolve = function scopedResolver(alpha, beta) {
  const hidden = "ghp_TEST_PRIVATE_LITERAL";
  /* SECRET_COMMENT_NEVER_EXPORT */
  return alpha.store.get(beta.has(scopeId) ? beta.get(scopeId) : hidden);
};
res = await inspectSeven(sevenMaps);
assert.equal(res.provider_selection, "active_provider_ambiguous");
assert.equal(res.resolution_attempted, false);
assert.equal(res.resolver_shape_complete, true);
assert.ok(res.resolver_masked_shape.includes(".get("));
assert.ok(res.resolver_masked_shape.includes(".has("));
assert.ok(res.resolver_masked_shape.includes("return"));
for (const privatePart of ["ghp_", "PRIVATE", "SECRET_COMMENT", "scopeId",
  "scopedResolver", "alpha", "beta", "hidden"]) {
  assert.ok(!JSON.stringify(res).includes(privatePart),
    "resolver structural probe must hide " + privatePart);
}
def.resolve = originalResolver;

const unknownRoot = {memoizedProps:{value:sharedMap}};
res = await inspect([unknownRoot]);
assert.equal(res.active_root_count_capped, 0);
assert.equal(res.unresolved_root_count_capped, 1);
assert.equal(res.provider_selection, "active_root_ambiguous");
assert.equal(res.resolution_attempted, false);
assert.equal(resolves, 0);

function resolutionAttempted(result) {return result.resolution_attempted;}
console.log("PASS: AUTO-F01 unique scope-export, current/alternate identity and fail-closed read-only probe");

