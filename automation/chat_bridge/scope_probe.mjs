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
    const result = await pages[0].evaluate(async ({asset, alias}) => {
      // Read-only: dynamic-import installed local app asset, inspect one
      // export and React's existing scope maps. No assignment to window,
      // no dispatch, no API request, no stream method invocation.
      const initial = await import("./assets/" + asset);
      const definition = initial[alias];
      const report = {
        exported_definition_present: !!definition,
        scope_id_present: definition?.scope?.id != null,
        resolve_function_present: typeof definition?.resolve === "function",
        provider_map_count: 0,
        resolution_attempted: false,
        prepare_function_present: false,
        start_function_present: false,
        query_cache_present: false
      };
      if (!report.scope_id_present || !report.resolve_function_present)
        return report;
      const stack = Array.from(document.body?.children ?? []).flatMap(el =>
        Object.keys(el).filter(k => k.startsWith("__reactContainer$"))
          .map(k => el[k]));
      const seen = new Set(), maps = [];
      for (let i = 0; i < 30000 && stack.length; i++) {
        const node = stack.pop();
        if (!node || seen.has(node)) continue;
        seen.add(node);
        const value = node.memoizedProps?.value;
        if (value instanceof Map && value.has(definition.scope.id)) maps.push(value);
        stack.push(node.child, node.sibling, node.alternate, node.current);
      }
      report.provider_map_count = Math.min(2, maps.length);
      if (maps.length !== 1) return report;
      const provider = maps[0].get(definition.scope.id);
      if (!provider?.store || typeof provider.store.get !== "function") return report;
      // Resolve once to TEST the candidate's shape; do not activate transport.
      // A capability check is not authority to send a message.
      const resolved = definition.resolve(provider, maps[0]);
      const transport = provider.store.get(resolved);
      report.resolution_attempted = true;
      report.prepare_function_present =
        typeof transport?.prepareCompletionStream === "function";
      report.start_function_present =
        typeof transport?.startCompletionStream === "function";
      report.query_cache_present =
        typeof transport?.scope?.queryClient?.getQueryCache === "function";
      return report;
    }, {asset: candidate.initialName, alias: candidate.exportAlias});
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
