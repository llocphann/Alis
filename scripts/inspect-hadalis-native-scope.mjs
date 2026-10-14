#!/usr/bin/env node
/* AUTO-F01 diagnostic ONLY. No native-cli submission path or profile state. */
import {probeDesktopScopeReadOnly} from "../automation/chat_bridge/scope_probe.mjs";
import {assessNativeTransportEvidence} from "../automation/chat_bridge/transport_evidence.mjs";

const guard = setTimeout(() => {
  console.log(JSON.stringify({
    supported: false, purpose: "read-only-runtime-diagnostics",
    submission_authorized: false, error_code: "PROBE_TIMEOUT"
  }));
  process.exit(124);
}, 25000);
try {
  const result = await probeDesktopScopeReadOnly();
  console.log(JSON.stringify({...result,
    transport_evidence: assessNativeTransportEvidence(result)}));
} catch (error) {
  // No raw Desktop exceptions: they can embed session IDs, file paths,
  // or account data. Only bounded categories are exported.
  const message = String(error?.message ?? "");
  const code = /scope constructor|export not unique|stream method not unique|ambiguous Desktop build|unsupported Desktop asset/.test(message)
    ? "STATIC_CANDIDATE_AMBIGUOUS"
    : /renderer|page/i.test(message) ? "RENDERER_UNAVAILABLE"
    : /loopback/.test(message) ? "CDP_URL_INVALID"
    : /CDP|connect|socket|ECONN|timeout/i.test(message) ? "CDP_UNAVAILABLE"
    : /module|import|ERR_MODULE/i.test(message) ? "DESKTOP_ASSET_UNAVAILABLE"
    : "READ_ONLY_PROBE_UNAVAILABLE";
  console.log(JSON.stringify({
    supported: false, purpose: "read-only-runtime-diagnostics",
    submission_authorized: false, error_code: code
  }));
  process.exitCode = 1;
} finally {
  clearTimeout(guard);
}
