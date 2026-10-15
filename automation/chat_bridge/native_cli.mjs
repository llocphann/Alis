import {connectNative, nativeRead, resolveProject, nativeSubmit, nativeResume, discoverSubmission, projectTurn} from "./native_adapter.mjs";

let browser;
// End before Python's 45s subprocess ceiling, returning a safe reason.
// A timed-out dispatch remains uncertain in persisted manager state: never
// interpret this as authorization to send the same message a second time.
const deadline=setTimeout(()=>{
  console.error("DESKTOP_OPERATION_TIMEOUT");
  process.exit(1);
},42000);deadline.unref();
try {
  let raw = "";
  for await (const chunk of process.stdin) {
    raw += chunk;
    if (raw.length > 200000) throw new Error("request exceeds bound");
  }
  const input = JSON.parse(raw);
  // V1's text/time-window heuristic can match the wrong conversation or a
  // previously generated prompt. Without a trusted original user-message ID
  // it must NOT convert an uncertain legacy send into an acknowledged receipt.
  // Quarantine before connecting to Desktop (no project navigation or send).
  if(input.op==="adopt")
    throw new Error("legacy pending identity requires authenticated server evidence");
  // Structural fingerprints and owner-visible UI smoke tests cannot attest
  // server-side Project membership, a specific user turn, or durable final
  // receipt. Keep all managed message mutations disabled at this boundary
  // until a separately audited authenticated transport is implemented.
  // No env flag, profile option or unchecked Desktop renderer value can
  // override this gate. The owner-only one-shot test lives in a separate CLI.
  if(input.op==="submit" || input.op==="resume")
    throw new Error("managed submission transport not attested");
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
  } else if (input.op === "probe") result = {supported: true, fingerprint: connection.contract.fingerprint};
  else throw new Error("unknown native operation");
  console.log(JSON.stringify(result));
} catch (error) {
  // Never serialize a raw request/headers or an HTTP error body.
  const message=String(error.message);
  const code=message.includes("managed submission transport not attested")
    ? "MANAGED_SUBMISSION_NOT_ATTESTED"
    : message.includes("legacy pending") ? "LEGACY_IDENTITY_AMBIGUOUS"
    : /unsupported|capabilit|export contract|Desktop build/.test(message) ? "DESKTOP_CAPABILITY_UNAVAILABLE"
    : message.includes("GitHub plugin") ? "GITHUB_PLUGIN_UNAVAILABLE"
    : message.includes("project name") ? "PROJECT_UNAVAILABLE_OR_AMBIGUOUS"
    : "DESKTOP_OPERATION_UNAVAILABLE";
  console.error(code); process.exitCode = 1;
} finally { clearTimeout(deadline); if (browser) await browser.close(); }
