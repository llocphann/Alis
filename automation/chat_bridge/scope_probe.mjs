/* AUTO-F01 read-only Desktop scope investigation.
 * Diagnostics are isolated from native_adapter.mjs/native_cli.mjs and NEVER
 * authorize managed submission. No auth headers, tokens or message bodies
 * are read, returned, stored, or logged.
 */
import fs from "node:fs";
import crypto from "node:crypto";

const ARCHIVE = "/usr/lib/chatgpt/resources/app.asar";
const DEFAULT_CDP = "http://127.0.0.1:9222";
const CALLBACK = /(?:^|[,;])([\w$]+)\s*=\s*[\w$]+\(\s*[\w$]+\s*,\s*\(\s*\{\s*scope\s*:\s*([\w$]+)\s*\}\s*\)\s*=>\s*new\s+[\w$]+\(\s*\2\s*\)\s*\)/g;
const STREAM = /\basync\s+startCompletionStream\s*\(/g;
const EXPORT = /(?:^|,)([\w$]+)\s+as\s+([\w$]+)(?=,|})/g;

export function matchScopeCandidate(initial) {
  if (typeof initial !== "string") throw new Error("invalid bundled module");
  const methods = [...initial.matchAll(STREAM)];
  if (methods.length !== 1) throw new Error("stream method not unique");
  const nearby = [...initial.matchAll(CALLBACK)]
    .filter(m => Math.abs(m.index - methods[0].index) <= 12000);
  if (nearby.length !== 1) throw new Error("scope constructor not unique near stream");
  const tailAt = initial.lastIndexOf("export{");
  if (tailAt < 0) throw new Error("bundled export list unavailable");
  const symbols = [...initial.slice(tailAt + 7).matchAll(EXPORT)]
    .filter(m => m[1] === nearby[0][1]);
  if (symbols.length !== 1) throw new Error("scope constructor export not unique");
  // The symbol is used ONLY by the one-time read-only renderer inspection.
  // It is never returned to callers, persisted, or used by live transport.
  return { exportAlias: symbols[0][2], binding: nearby[0][1] };
}

function readInstalledAssets(asarPath = process.env.HADALIS_DESKTOP_ASAR ?? ARCHIVE) {
  const fd = fs.openSync(asarPath, "r");
  try {
    const head = Buffer.alloc(16);
    if (fs.readSync(fd, head, 0, 16, 0) !== 16) throw new Error("invalid Desktop archive");
    const size = head.readUInt32LE(12), offset = 8 + head.readUInt32LE(4);
    if (!size || size > 32 * 1024 * 1024) throw new Error("invalid Desktop archive");
    const header = Buffer.alloc(size);
    if (fs.readSync(fd, header, 0, size, 16) !== size) throw new Error("invalid Desktop archive");
    const root = JSON.parse(header.toString("utf8")).files.webview.files.assets.files;
    const findOne = pattern => {
      const list = Object.keys(root).filter(x => pattern.test(x));
      if (list.length !== 1) throw new Error("ambiguous Desktop build");
      return list[0];
    };
    const initialName = findOne(/^app-initial-.*\.js$/);
    const sharedName = findOne(/^app-shared-.*\.js$/);
    const read = name => {
      const entry = root[name];
      if (!entry || entry.unpacked || !Number.isSafeInteger(entry.size) ||
          entry.size <= 0 || entry.size > 32 * 1024 * 1024 ||
          !/^\d+$/.test(String(entry.offset)))
        throw new Error("unsupported Desktop asset");
      const out = Buffer.alloc(entry.size);
      const position = offset + Number(entry.offset);
      if (fs.readSync(fd, out, 0, out.length, position) !== out.length)
        throw new Error("incomplete Desktop asset");
      return out.toString("utf8");
    };
    const initial = read(initialName), shared = read(sharedName);
    const fingerprint = crypto.createHash("sha256")
      .update(initial).update(shared).digest("hex");
    return { initialName, initial, fingerprint };
  } finally { fs.closeSync(fd); }
}

export function staticScopeCandidate(asarPath) {
  const {initialName, initial, fingerprint} = readInstalledAssets(asarPath);
  const match = matchScopeCandidate(initial);
  return {initialName, exportAlias: match.exportAlias,
    fingerprintPrefix: fingerprint.slice(0, 12)};
}

export async function probeDesktopScopeReadOnly({
  cdpUrl = process.env.HADALIS_CHATGPT_CDP_URL ?? DEFAULT_CDP,
  playwrightModule = process.env.HADALIS_PLAYWRIGHT_MODULE ??
    "file:///usr/lib/chatgpt/resources/cua_node/lib/node_modules/playwright-core/index.mjs",
  asarPath
} = {}) {
  // Never fall back to browser UI clicking, global chat, or alternative CDP.
  const url = new URL(cdpUrl);
  if (url.protocol !== "http:" ||
      !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname))
    throw new Error("CDP must use loopback");
  const candidate = staticScopeCandidate(asarPath);
  const {chromium} = await import(playwrightModule);
  const browser = await chromium.connectOverCDP(cdpUrl, {timeout: 10000});
  try {
    const pages = browser.contexts().flatMap(ctx => ctx.pages())
      .filter(page => page.url() === "app://-/index.html");
    if (pages.length !== 1) throw new Error("Desktop renderer unavailable or ambiguous");
    const result = await pages[0].evaluate(inspectRendererScopeReadOnly,
      {asset: candidate.initialName, alias: candidate.exportAlias});
    return {
      supported: false, purpose: "read-only-runtime-diagnostics",
      submission_authorized: false,
      fingerprint_prefix: candidate.fingerprintPrefix,
      renderer_found: true,
      ...result
    };
  } finally {
    try { await browser.close(); } catch {}
  }
}

// This very function is serialized by page.evaluate and independently exercised
// on isolated in-memory React Fiber fixtures. No helper closures are required.
// Test fixtures are ignored inside Desktop (where document exists).
export async function inspectRendererScopeReadOnly({asset, alias, fixture}) {
      // Read-only: dynamic-import installed local app asset, inspect one
      // export and React's existing scope maps. No assignment to window,
      // no dispatch, no API request, no stream method invocation.
      const testFixture = typeof document === "undefined" ? fixture : null;
      const initial = testFixture
        ? {[alias]: testFixture.definition} : await import("./assets/" + asset);
      const definition = initial[alias];
      const report = {
        exported_definition_present: !!definition,
        scope_id_present: definition?.scope?.id != null,
        resolve_function_present: typeof definition?.resolve === "function",
        provider_map_count: 0,
        unique_provider_map_count_capped: 0,
        active_provider_map_count_capped: 0,
        unique_provider_identity_count_capped: 0,
        alternate_only_provider_map_count_capped: 0,
        distinct_maps_share_provider_identity: false,
        active_maps_have_equal_key_sets: false,
        active_maps_have_equal_entries_by_identity: false,
        active_maps_have_nested_key_sets: false,
        active_map_size_range_capped: [0, 0],
        // This comparison reads Map entries only; it does not call resolve.
        active_map_comparison_complete: false,
        active_provider_identity_count_capped: 0,
        react_container_count_capped: 0,
        active_root_count_capped: 0,
        unresolved_root_count_capped: 0,
        provider_map_shared_with_active_tree: false,
        fiber_scan_truncated: false,
        provider_selection: "not_evaluated",
        resolution_attempted: false,
        prepare_function_present: false,
        start_function_present: false,
        query_cache_present: false
      };
      if (!report.scope_id_present || !report.resolve_function_present)
        return report;
      const anchors = testFixture
        ? testFixture.anchors
        : Array.from(document.body?.children ?? []).flatMap(el =>
          Object.keys(el).filter(k => k.startsWith("__reactContainer$"))
            .map(k => el[k]).filter(Boolean));
      report.react_container_count_capped = Math.min(8, anchors.length);

      // React often exposes both current and alternate Fibers. A repeated
      // map hit is not automatically an independent provider. Compare object
      // identity without exposing it, choosing a provider, or invoking resolve.
      const observe = (roots, includeAlternates) => {
        const stack = [...roots], seen = new Set(), maps = new Set();
        const providers = new Set();
        let hits = 0, iterations = 0;
        while (stack.length && iterations < 30000) {
          const node = stack.pop();
          iterations++;
          if (!node || typeof node !== "object" || seen.has(node)) continue;
          seen.add(node);
          const value = node.memoizedProps?.value;
          if (value instanceof Map && value.has(definition.scope.id)) {
            hits++;
            maps.add(value);
            providers.add(value.get(definition.scope.id));
          }
          if (node.child) stack.push(node.child);
          if (node.sibling) stack.push(node.sibling);
          if (includeAlternates) {
            if (node.alternate) stack.push(node.alternate);
            if (node.current) stack.push(node.current);
          }
        }
        return {maps, providers, hits, truncated: stack.length > 0};
      };

      // Roots are accepted only if their React HostRoot stateNode explicitly
      // owns a current Fiber. Never infer active ownership from DOM selection,
      // sibling order, or whichever alternate happens to be visited first.
      const roots = new Set();
      let unknownRoots = 0;
      for (const anchor of anchors) {
        let top = anchor, steps = 0;
        const parents = new Set();
        while (top?.return && steps++ < 1024 && !parents.has(top)) {
          parents.add(top);
          top = top.return;
        }
        const current = top?.stateNode?.current;
        if (top && !top.return && top.stateNode && current &&
            current.stateNode === top.stateNode)
          roots.add(current);
        else
          unknownRoots++;
      }
      report.active_root_count_capped = Math.min(8, roots.size);
      report.unresolved_root_count_capped = Math.min(8, unknownRoots);
      const all = observe(anchors, true);
      const active = observe(roots, false);
      report.provider_map_count = Math.min(2, all.hits); // Retained legacy display field.
      report.unique_provider_map_count_capped = Math.min(8, all.maps.size);
      report.active_provider_map_count_capped = Math.min(8, active.maps.size);
      report.unique_provider_identity_count_capped = Math.min(8, all.providers.size);
      report.alternate_only_provider_map_count_capped = Math.min(8,
        [...all.maps].filter(map => !active.maps.has(map)).length);
      report.distinct_maps_share_provider_identity =
        all.maps.size > 1 && all.providers.size === 1;
      report.active_provider_identity_count_capped = Math.min(8, active.providers.size);
      const currentMaps = [...active.maps];
      // Compare only JS Map key/value object identities (Object.is).
      // Do not stringify map keys, values, component props, or provider data.
      // Even identical entries in distinct Map objects do NOT establish that
      // definition.resolve() can safely use an arbitrarily chosen Map.
      if (currentMaps.length && currentMaps.length <= 32) {
        const entries = currentMaps.map(map => [...map.entries()]);
        const keysEqual = (a, b) => a.length === b.length &&
          a.every(([key]) => b.some(([other]) => Object.is(key, other)));
        const entriesEqual = (a, b) => a.length === b.length &&
          a.every(([key, value]) => b.some(([otherKey, otherValue]) =>
            Object.is(key, otherKey) && Object.is(value, otherValue)));
        const subsetKeys = (a, b) => a.every(([key]) =>
          b.some(([other]) => Object.is(key, other)));
        const baseline = entries[0];
        report.active_map_comparison_complete = true;
        report.active_maps_have_equal_key_sets =
          entries.every(other => keysEqual(baseline, other));
        report.active_maps_have_equal_entries_by_identity =
          entries.every(other => entriesEqual(baseline, other));
        report.active_maps_have_nested_key_sets =
          entries.every((one, i) => entries.every((two, j) =>
            i === j || subsetKeys(one, two) || subsetKeys(two, one)));
        const sizes = currentMaps.map(map => map.size);
        report.active_map_size_range_capped = [
          Math.min(128, Math.min(...sizes)), Math.min(128, Math.max(...sizes))
        ];
      }
      report.provider_map_shared_with_active_tree =
        [...active.maps].some(map => all.maps.has(map));
      report.fiber_scan_truncated = all.truncated || active.truncated;
      if (report.fiber_scan_truncated) {
        report.provider_selection = "fiber_scan_incomplete";
        return report;
      }
      if (unknownRoots || roots.size !== 1) {
        report.provider_selection = "active_root_ambiguous";
        return report;
      }
      if (active.maps.size !== 1) {
        report.provider_selection = "active_provider_ambiguous";
        return report;
      }
      if (all.maps.size !== 1 || all.providers.size !== 1) {
        report.provider_selection = "alternate_or_duplicate_provider_unresolved";
        return report;
      }
      const map = [...active.maps][0];
      if (![...all.maps].includes(map)) {
        report.provider_selection = "active_provider_not_verified";
        return report;
      }
      const provider = map.get(definition.scope.id);
      if (!provider?.store || typeof provider.store.get !== "function") {
        report.provider_selection = "provider_store_unavailable";
        return report;
      }
      report.provider_selection = "unique_active_and_full_tree";
      // Resolve once to TEST the candidate's shape; do not activate transport.
      // A capability check is not authority to send a message.
      const resolved = definition.resolve(provider, map);
      const transport = provider.store.get(resolved);
      report.resolution_attempted = true;
      report.prepare_function_present =
        typeof transport?.prepareCompletionStream === "function";
      report.start_function_present =
        typeof transport?.startCompletionStream === "function";
      report.query_cache_present =
        typeof transport?.scope?.queryClient?.getQueryCache === "function";
      return report;
}
