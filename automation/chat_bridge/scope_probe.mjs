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
        active_map_topology_complete: false,
        active_map_depth_range_capped: [0, 0],
        active_map_depth_limit_reached: false,
        active_map_ancestor_edges: [],
        active_map_ancestor_pair_count_capped: 0,
        active_map_incomparable_pair_count_capped: 0,
        active_map_depth_size_profiles: [],
        // Static source characteristics only: never execute resolve here.
        resolver_source_inspected: false,
        resolver_length_band: "unknown",
        resolver_uses_map_access_tokens: false,
        resolver_parameter_shape: "unknown",
        resolver_first_argument_map_access: false,
        resolver_second_argument_map_access: false,
        resolver_masked_shape: "",
        resolver_alpha_shape: "",
        resolver_alpha_complete: false,
        resolver_shape_complete: false,
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
      try {
        const source = Function.prototype.toString.call(definition.resolve);
        report.resolver_source_inspected = true;
        report.resolver_length_band = source.length <= 120 ? "0-120"
          : source.length <= 500 ? "121-500"
          : source.length <= 2000 ? "501-2k" : "over-2k";
        // Lexical hint only: minification and captured functions mean this
        // cannot prove or disprove a context-map dependency.
        report.resolver_uses_map_access_tokens = /\.(?:get|has)\s*\(/.test(source);
        // Scrub all text and symbol names before export. This is not an AST
        // proof; it is a bounded structural hint for identifying which
        // receiver makes .get/.has calls. No raw source ever leaves Desktop.
        const preserve = new Set([
          "function", "async", "return", "new", "const", "let", "var",
          "if", "else", "throw", "try", "catch", "null", "undefined",
          "true", "false", "this", "get", "has", "scope", "store"
        ]);
        const erased = source
          .replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, " ")
          .replace(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`/g, "STRING");
        report.resolver_masked_shape = erased.replace(/[$A-Za-z_][\w$]*/g,
          word => preserve.has(word) ? word : "id")
          .replace(/[0-9]+/g, "0")
          .replace(/\s+/g, " ").slice(0, 640);
        report.resolver_shape_complete = erased.length <= 640;
        // One-to-one ALPHA RENAMING, still no original symbol/literal/value.
        // Previous all-'id' masking loses variable equality information and
        // cannot distinguish local aliasing from accesses on function args.
        // Keep method operators, but only through a strict punctuation and
        // keyword allowlist. Never return the raw function or its symbols.
        const protectedWords = new Set([
          "function", "async", "return", "new", "const", "let", "var",
          "if", "else", "throw", "try", "catch", "finally", "null",
          "undefined", "true", "false", "this", "get", "has",
          "typeof", "void", "delete", "instanceof", "in", "of"
        ]);
        const aliases = new Map();
        const structurallyMasked = erased
          .replace(/[$A-Za-z_][\\w$]*/g, word => {
            if (protectedWords.has(word)) return word;
            if (!aliases.has(word)) aliases.set(word, "v" + aliases.size);
            return aliases.get(word);
          })
          .replace(/\\b(?:\\d+(?:\\.\\d*)?|\\.\\d+)\\b/g, "0")
          .replace(/[^A-Za-z0-9_$\\s.,;:{}()[\\]=!?+\\-*\\/%<>|&^~]/g, " ")
          .replace(/\\s+/g, " ").trim();
        report.resolver_alpha_shape = structurallyMasked.slice(0, 640);
        report.resolver_alpha_complete = structurallyMasked.length <= 640;
        // Very conservative lexical classification, NOT proof of dependency:
        // handle only two bare identifier arguments. No names/source are sent
        // outside Desktop. A function with destructuring, shadowing, or a
        // different syntactic form remains unknown.
        const header = source.match(/^(?:(?:async\s+)?function\s*[\w$]*|(?:async\s+)?[\w$]+)?\s*\(\s*([\w$]+)\s*,\s*([\w$]+)\s*\)\s*\{/);
        if (header) {
          report.resolver_parameter_shape = "two-simple-identifiers";
          const body = source.slice(header[0].length);
          const receivesAccess = argument =>
            new RegExp("(?:^|[^\\w$])" + argument +
              "\\s*(?:\\?\\.)?\\s*\\.(?:get|has)\\s*\\(").test(body);
          report.resolver_first_argument_map_access = receivesAccess(header[1]);
          report.resolver_second_argument_map_access = receivesAccess(header[2]);
        } else {
          report.resolver_parameter_shape = "complex-or-unrecognized";
        }
      } catch {}
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
      // Map topology is read only, and does not depend on user-visible
      // component names, DOM text, props, or raw context values. The active
      // tree is followed through child/sibling edges, never alternates.
      const topology = (() => {
        const stack = [...roots].map(node => ({
          node, depth: 0, ancestors: []
        }));
        const seen = new Set(), profiles = new Map(), ancestorPairs = new Set();
        const index = new Map();
        let iterations = 0, depthLimitReached = false;
        while (stack.length && iterations++ < 30000) {
          const frame = stack.pop();
          const node = frame?.node;
          if (!node || typeof node !== "object" || seen.has(node)) continue;
          seen.add(node);
          const value = node.memoizedProps?.value;
          const relevant = value instanceof Map && value.has(definition.scope.id);
          let nextAncestors = frame.ancestors;
          if (relevant) {
            if (!index.has(value)) index.set(value, index.size);
            const key = index.get(value);
            const depth = Math.min(4096, frame.depth);
            if (frame.depth > 4096) depthLimitReached = true;
            const prior = profiles.get(value);
            if (prior) {
              prior.min_depth = Math.min(prior.min_depth, depth);
              prior.max_depth = Math.max(prior.max_depth, depth);
            } else {
              profiles.set(value, {
                min_depth: depth, max_depth: depth,
                context_key_count_capped: Math.min(128, value.size)
              });
            }
            for (const parent of frame.ancestors) {
              if (parent === value) continue;
              if (!index.has(parent)) index.set(parent, index.size);
              const first = index.get(parent), last = key;
              ancestorPairs.add([Math.min(first, last), Math.max(first, last)].join(":"));
            }
            if (!frame.ancestors.includes(value))
              nextAncestors = [...frame.ancestors, value];
          }
          if (node.sibling) stack.push({
            node: node.sibling, depth: frame.depth,
            ancestors: frame.ancestors
          });
          if (node.child) stack.push({
            node: node.child, depth: frame.depth + 1,
            ancestors: nextAncestors
          });
        }
        const ordered = [...profiles.entries()].sort((a, b) =>
          a[1].min_depth - b[1].min_depth ||
          a[1].context_key_count_capped - b[1].context_key_count_capped);
        const rows = ordered.map(([, data]) => data);
        const order = new Map(ordered.map(([map], n) =>
          [index.get(map), n]));
        const edges = [...ancestorPairs].map(pair => {
          const [a, b] = pair.split(":").map(Number);
          return [order.get(a), order.get(b)].sort((x, y) => x - y);
        }).filter(pair => pair.every(Number.isSafeInteger))
          .sort((a,b) => a[0]-b[0] || a[1]-b[1]);
        const pairs = profiles.size * (profiles.size - 1) / 2;
        return {
          complete: stack.length === 0,
          depth_range: rows.length ? [
            Math.min(...rows.map(x => x.min_depth)),
            Math.max(...rows.map(x => x.max_depth))
          ] : [0, 0],
          ancestor_pairs: ancestorPairs.size,
          incomparable_pairs: Math.max(0, pairs - ancestorPairs.size),
          rows: rows.slice(0, 12),
          depth_limit_reached: depthLimitReached,
          ancestry_edges: rows.length <= 12 ? edges : []
        };
      })();
      report.active_map_topology_complete = topology.complete;
      report.active_map_depth_range_capped = topology.depth_range;
      report.active_map_depth_limit_reached = topology.depth_limit_reached;
      report.active_map_ancestor_edges = topology.ancestry_edges;
      report.active_map_ancestor_pair_count_capped =
        Math.min(128, topology.ancestor_pairs);
      report.active_map_incomparable_pair_count_capped =
        Math.min(128, topology.incomparable_pairs);
      report.active_map_depth_size_profiles = topology.rows;
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
