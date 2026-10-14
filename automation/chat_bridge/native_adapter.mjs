/* Desktop owns authentication. This adapter never reads tokens/cookies.
 * Installed renderer exports are private APIs: probe the installed build,
 * validate identities and fail closed before dispatch if it is unsupported.
 */
import fs from "node:fs";
import crypto from "node:crypto";

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function activeBranch(conversation) {
  const mapping = conversation?.mapping;
  if (!mapping || typeof mapping !== "object") throw new Error("conversation mapping unavailable");
  let id = conversation.current_node;
  const branch = [], seen = new Set();
  while (id && mapping[id] && !seen.has(id) && branch.length < 10000) {
    seen.add(id);
    const node = mapping[id];
    branch.push(node);
    id = node.parent;
  }
  return branch.reverse();
}

export function projectTurn(conversation, pending) {
  if (conversation.conversation_id && conversation.conversation_id !== pending.conversation_id)
    throw new Error("conversation identity mismatch");
  const branch = activeBranch(conversation);
  const start = branch.findIndex(n => n.message?.id === pending.user_message_id || n.id === pending.user_message_id);
  if (start < 0) return { completed: false, submitted: false };
  const messages = branch.slice(start + 1).map(n => n.message).filter(Boolean);
  // A response from a different user turn must never satisfy this receipt.
  const nextUser = messages.findIndex(m => m.author?.role === "user");
  const turn = nextUser < 0 ? messages : messages.slice(0, nextUser);
  const final = turn.findLast(m => m.author?.role === "assistant" &&
    m.recipient === "all" && (m.channel == null || m.channel === "final") &&
    m.status === "finished_successfully" && m.end_turn === true);
  if (!final) {
    const lastAssistant=turn.findLast(m=>m.author?.role === "assistant");
    return { completed: false, submitted: true,
      superseded: nextUser >= 0,
      ...(nextUser >= 0 ? {successor_user_message_id: messages[nextUser].id} : {}),
      streamError: turn.some(m => ["failed", "error", "cancelled"].includes(m.status)),
      terminal_failed: !!lastAssistant && ["failed","error","cancelled"].includes(lastAssistant.status) && lastAssistant.end_turn === true };
  }
  return { completed: true, submitted: true, response: {
    message_id: final.id, text: (final.content?.parts ?? []).filter(p => typeof p === "string").join("\n")
  }};
}

function asarReader(path) {
  const fd = fs.openSync(path, "r");
  const h = Buffer.alloc(16); fs.readSync(fd, h, 0, 16, 0);
  const size = h.readUInt32LE(12), offset = 8 + h.readUInt32LE(4);
  if (size > 32 * 1024 * 1024) throw new Error("invalid Desktop archive");
  const data = Buffer.alloc(size); fs.readSync(fd, data, 0, size, 16);
  const root = JSON.parse(data.toString());
  return {
    files: Object.keys(root.files.webview.files.assets.files),
    read(name) {
      const entry = root.files.webview.files.assets.files[name];
      if (!entry || entry.unpacked || entry.size > 32 * 1024 * 1024)
        throw new Error("unsupported Desktop asset");
      const buf = Buffer.alloc(entry.size);
      fs.readSync(fd, buf, 0, buf.length, offset + Number(entry.offset));
      return buf.toString();
    }, close() { fs.closeSync(fd); }
  };
}

function exported(source, name) {
  const tail = source.slice(source.lastIndexOf("export{"));
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = tail.match(new RegExp("[,{]" + escaped + " as ([\\w$]+)[,}]"));
  if (!match) throw new Error("unsupported Desktop export contract");
  return match[1];
}

export function installedContract() {
  const archive = asarReader(process.env.HADALIS_DESKTOP_ASAR ?? "/usr/lib/chatgpt/resources/app.asar");
  try {
    const initialNames = archive.files.filter(n => /^app-initial-.*\.js$/.test(n));
    const sharedNames = archive.files.filter(n => /^app-shared-.*\.js$/.test(n));
    if (initialNames.length !== 1 || sharedNames.length !== 1) throw new Error("ambiguous Desktop build");
    const initial = archive.read(initialNames[0]), shared = archive.read(sharedNames[0]);
    const apiLocal = initial.match(/([\w$]+)\.streamPost\(`\/f\/conversation`/)[1];
    const apiImport = initial.match(new RegExp("([\\w$]+) as " + apiLocal + "[,}]"))?.[1];
    const atom = initial.match(/,([\w$]+)=\w+\(\$,\(\{scope:e\}\)=>new (\w+)\(e\)\)\}\)\)\)\(\)\}\s*function brn/);
    if (!apiImport || !atom || !initial.includes("async startCompletionStream("))
      throw new Error("unsupported Desktop stream contract");
    return { shared: sharedNames[0], initial: initialNames[0], api: apiImport,
      stream: exported(initial, atom[1]),
      fingerprint: crypto.createHash("sha256").update(initial).update(shared).digest("hex") };
  } finally { archive.close(); }
}

export async function connectNative() {
  const url = process.env.HADALIS_CHATGPT_CDP_URL ?? "http://127.0.0.1:9222";
  const parsed = new URL(url);
  if (parsed.protocol !== "http:" || !["localhost", "127.0.0.1", "[::1]"].includes(parsed.hostname))
    throw new Error("Desktop connection must use loopback");
  const { chromium } = await import(process.env.HADALIS_PLAYWRIGHT_MODULE ??
    "file:///usr/lib/chatgpt/resources/cua_node/lib/node_modules/playwright-core/index.mjs");
  const browser = await chromium.connectOverCDP(url, { timeout: 10000 });
  const page = browser.contexts().flatMap(c => c.pages()).find(p => p.url() === "app://-/index.html");
  if (!page) { await browser.close(); throw new Error("Desktop main renderer unavailable"); }
  const contract = installedContract();
  await page.evaluate(async contract => {
    const shared = await import(`./assets/${contract.shared}`), initial = await import(`./assets/${contract.initial}`);
    const api = shared[contract.api], definition = initial[contract.stream];
    if (typeof api?.safeGet !== "function" || typeof definition?.resolve !== "function")
      throw new Error("Desktop capabilities unavailable");
    // Read the app-wide scope, never the selected chat/composer. This is
    // bounded and capability checked; navigation does not change identities.
    let chain;
    const todo = Array.from(document.body.children).flatMap(el => Object.keys(el)
      .filter(k => k.startsWith("__reactContainer$")).map(k => el[k]));
    const seen = new Set();
    for (let i = 0; i < 30000 && todo.length; i++) {
      const node = todo.pop();
      if (!node || seen.has(node)) continue;
      seen.add(node);
      const value = node.memoizedProps?.value;
      if (value instanceof Map && value.has(definition.scope.id)) { chain = value; break; }
      todo.push(node.child, node.sibling, node.alternate, node.current);
    }
    if (!chain) throw new Error("Desktop app scope unavailable");
    const node = chain.get(definition.scope.id);
    const transport = node.store.get(definition.resolve(node, chain));
    if (typeof transport?.prepareCompletionStream !== "function" ||
        typeof transport?.startCompletionStream !== "function") throw new Error("unsupported Desktop transport");
    window.__hadalisNative = { api, transport, fingerprint: contract.fingerprint };
    window.__hadalisReceipts ??= new Map();
  }, contract);
  return { page, browser, contract };
}

export async function nativeRead(page, path, query = {}) {
  return page.evaluate(async ({path, query}) => window.__hadalisNative.api.safeGet(path, {
    signal: AbortSignal.timeout(25000), parameters: { query }
  }), { path, query });
}

export async function resolveProject(page, name) {
  let cursor;
  const matches = [];
  for (let pageNo = 0; pageNo < 5; pageNo++) {
    const data = await nativeRead(page, "/gizmos/snorlax/sidebar", {
      limit: 40, conversations_per_gizmo: 0, owned_only: true, ...(cursor ? {cursor} : {})
    });
    for (const item of data.items ?? []) {
      const gizmo = item.gizmo?.gizmo;
      if (gizmo?.display?.name === name) matches.push(gizmo.id);
    }
    cursor = data.cursor;
    if (!cursor) break;
  }
  if (new Set(matches).size !== 1) throw new Error("project name unavailable or ambiguous; bind an exact project ID");
  return matches[0];
}

export async function nativeSubmit(page, input) {
  if (!UUID.test(input.user_message_id) || !UUID.test(input.parent_message_id)) throw new Error("invalid submission identity");
  if (input.conversation_id && !UUID.test(input.conversation_id)) throw new Error("invalid conversation identity");
  return page.evaluate(async input => {
    const {api, transport} = window.__hadalisNative, receipts = window.__hadalisReceipts;
    if (receipts.has(input.user_message_id)) return receipts.get(input.user_message_id);
    // No UI mutation, no account credential exposure, no transport resend.
    const hints = [];
    if (input.requires_github) {
      let plugins = transport.scope.queryClient.getQueryCache().getAll()
        .filter(q => q.queryKey[0] === "plugins" && Array.isArray(q.state.data))
        .flatMap(q => q.state.data).map(x => x.plugin).filter(Boolean)
        .filter(x => x.id === "github@openai-curated-remote" && x.installed && x.enabled);
      const ids = [...new Set(plugins.map(p => p.remotePluginId).filter(Boolean))];
      if (ids.length !== 1) throw new Error("GitHub plugin capability unavailable");
      hints.push(`plugin:${ids[0]}`);
    }
    const request = { action: "next", model: input.model || "auto",
      parent_message_id: input.parent_message_id, messages: [{ id: input.user_message_id,
        author: {role: "user"}, content: {content_type: "text", parts: [input.prompt]},
        metadata: {system_hints: hints} }], system_hints: hints,
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      timezone_offset_min: new Date().getTimezoneOffset(),
      ...(input.project_id ? {gizmo_id: input.project_id,
        conversation_mode: {kind: "gizmo_interaction", gizmo_id: input.project_id}} : {}),
      ...(input.conversation_id ? {conversation_id: input.conversation_id} : {}) };
    const prepared = await transport.prepareCompletionStream(request, {signal: AbortSignal.timeout(20000)});
    // Receipt insertion is the last local point before the possible send.
    // Python has already committed dispatch intent, so failure stays uncertain.
    const receipt = { user_message_id: input.user_message_id, conversation_id: input.conversation_id,
      dispatched: false, streamError: false };
    for (const [id, prior] of receipts) {
      if (receipts.size < 32) break;
      if (prior.streamComplete || (prior.streamError && !prior.dispatched)) receipts.delete(id);
    }
    if (receipts.size >= 64) throw new Error("managed stream limit reached");
    receipts.set(input.user_message_id, receipt);
    const inspect = value => {
      if (!value || typeof value !== "object") return;
      const id = value.conversation_id ?? value.conversationId ?? value.conversation?.conversation_id;
      if (typeof id === "string" && /^[0-9a-f-]{36}$/i.test(id)) receipt.conversation_id = id;
    };
    try {
      await transport.startCompletionStream({request, prepared: Promise.resolve(prepared),
        startupSignal: AbortSignal.timeout(25000),
        onRequestStart: () => { receipt.dispatched = true; receipt.dispatched_at_ms = Date.now(); },
        onResponse: () => { receipt.accepted = true; },
        onUpdate: inspect,
        onEvent: event => { try { inspect(typeof event.data === "string" ? JSON.parse(event.data) : event.data); } catch {} },
        onError: () => { receipt.streamError = true; },
        onComplete: () => { receipt.streamComplete = true; receipt.completed_at_ms = Date.now(); }
      });
      const deadline = Date.now() + 10000;
      while (!receipt.conversation_id && !receipt.streamError && Date.now() < deadline)
        await new Promise(resolve => setTimeout(resolve, 100));
      return receipt;
    } catch (error) {
      receipt.streamError = true;
      receipt.errorName = error.name;
      // Kept only in Desktop memory for local diagnosis, never returned in
      // the publication protocol or stored alongside profile configuration.
      receipt.localError = String(error.message).slice(0, 1000);
      throw new Error("Desktop submission outcome uncertain; reconcile message identity");
    }
  }, input);
}

export async function discoverSubmission(page, pending) {
  const receipt = await page.evaluate(id => {
    const r = window.__hadalisReceipts?.get(id);
    return r ? {conversation_id: r.conversation_id, streamError: r.streamError} : null;
  }, pending.user_message_id);
  if (receipt?.conversation_id) return receipt;
  const list = await nativeRead(page, pending.project_id
    ? `/gizmos/${pending.project_id}/conversations` : "/conversations", {limit: 40, owned_only: true, order: "updated"});
  // Limit history scans per reconciliation; no guessing by title or UI.
  const recent = (list.items ?? []).filter(c => Number(c.create_time) >= pending.prepared_at_unix - 120).slice(0, 12);
  for (const item of recent) {
    const conversation = await nativeRead(page, `/conversation/${item.id}`);
    if (Object.values(conversation.mapping ?? {}).some(n => n.message?.id === pending.user_message_id || n.id === pending.user_message_id))
      return {conversation_id: item.id};
  }
  return {conversation_id: null};
}

export async function nativeResume(page, pending) {
  if (!UUID.test(pending.conversation_id)) throw new Error("invalid resume identity");
  // Read-only reattachment to the server stream. No new user message, variant
  // generation, prompt replay or credential persistence is permitted here.
  return page.evaluate(async pending => {
    const {transport} = window.__hadalisNative;
    if (typeof transport.resumeCompletionStream !== "function") throw new Error("Desktop resume capability unavailable");
    const receipt = window.__hadalisReceipts.get(pending.user_message_id) ?? {
      conversation_id:pending.conversation_id, user_message_id:pending.user_message_id};
    window.__hadalisReceipts.set(pending.user_message_id,receipt);
    await transport.resumeCompletionStream({request:{conversation_id:pending.conversation_id,offset:0},
      onResponse:()=>{receipt.resumed=true;},onUpdate:()=>{},onDecodedPayload:()=>{},
      onError:()=>{receipt.streamError=true;},onTransportClose:()=>{},
      onComplete:()=>{receipt.streamComplete=true;receipt.completed_at_ms=Date.now();}});
    return {reattached:true};
  }, pending);
}
