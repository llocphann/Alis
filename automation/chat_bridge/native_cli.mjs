import {connectNative, nativeRead, resolveProject, nativeSubmit, nativeResume, discoverSubmission, projectTurn} from "./native_adapter.mjs";

let browser;
// A supervisor crash must not leave an orphan CDP client indefinitely alive.
const deadline=setTimeout(()=>process.exit(1),45000);deadline.unref();
try {
  let raw = "";
  for await (const chunk of process.stdin) {
    raw += chunk;
    if (raw.length > 200000) throw new Error("request exceeds bound");
  }
  const input = JSON.parse(raw);
  const connection = await connectNative(); browser = connection.browser;
  const page = connection.page;
  let result;
  if (input.op === "project") result = {project_id: await resolveProject(page, input.name)};
  else if (input.op === "preflight") result=await page.evaluate(requiresGithub=>{
    if(requiresGithub){
      const plugins=window.__hadalisNative.transport.scope.queryClient.getQueryCache().getAll()
        .filter(q=>q.queryKey[0]==="plugins" && Array.isArray(q.state.data)).flatMap(q=>q.state.data)
        .map(x=>x.plugin).filter(p=>p?.id==="github@openai-curated-remote" && p.installed && p.enabled && p.remotePluginId);
      if(new Set(plugins.map(p=>p.remotePluginId)).size!==1)throw new Error("GitHub plugin capability unavailable");
    }
    return {ready:true};
  },input.requires_github);
  else if (input.op === "read") result = await nativeRead(page, `/conversation/${input.conversation_id}`);
  else if (input.op === "cursor") {
    const c = await nativeRead(page, `/conversation/${input.conversation_id}`);
    result = {conversation_id: c.conversation_id, current_node: c.current_node, model: c.default_model_slug};
  }
  else if (input.op === "submit") result = await nativeSubmit(page, input);
  else if (input.op === "resume") result = await nativeResume(page, input.pending);
  else if (input.op === "poll") {
    let pending = {...input.pending};
    if (!pending.conversation_id) Object.assign(pending, await discoverSubmission(page, pending));
    if (!pending.conversation_id) result = {completed: false, submitted: false, uncertain: true};
    else result = {...projectTurn(await nativeRead(page, `/conversation/${pending.conversation_id}`), pending),
      conversation_id: pending.conversation_id};
  } else if (input.op === "adopt") {
    const projectId = await resolveProject(page, input.project_name);
    const list = await nativeRead(page, `/gizmos/${projectId}/conversations`, {limit: 40, owned_only: true});
    const matches = [];
    for (const c of (list.items ?? []).slice(0, 12)) {
      const history = await nativeRead(page, `/conversation/${c.id}`);
      for (const n of Object.values(history.mapping ?? {})) {
        const m = n.message;
        if (m?.author?.role === "user" && Math.abs(m.create_time - input.prepared_at_unix) <= 90 &&
            (m.content?.parts ?? []).some(p => typeof p === "string" && p.includes(input.match_text)))
          matches.push({conversation_id: c.id, project_id: projectId, user_message_id: m.id});
      }
    }
    if (matches.length !== 1) throw new Error("legacy pending chat cannot be uniquely identified; receipt preserved");
    result = matches[0];
  } else if (input.op === "probe") result = {supported: true, fingerprint: connection.contract.fingerprint};
  else throw new Error("unknown native operation");
  console.log(JSON.stringify(result));
} catch (error) {
  // Never serialize a raw request/headers or an HTTP error body.
  const message=String(error.message);
  const code=message.includes("legacy pending") ? "LEGACY_IDENTITY_AMBIGUOUS"
    : /unsupported|capabilit|export contract|Desktop build/.test(message) ? "DESKTOP_CAPABILITY_UNAVAILABLE"
    : message.includes("GitHub plugin") ? "GITHUB_PLUGIN_UNAVAILABLE"
    : message.includes("project name") ? "PROJECT_UNAVAILABLE_OR_AMBIGUOUS"
    : "DESKTOP_OPERATION_UNAVAILABLE";
  console.error(code); process.exitCode = 1;
} finally { clearTimeout(deadline); if (browser) await browser.close(); }
