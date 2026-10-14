#!/usr/bin/env node
/* AUTO-F01: historical Playwright/CDP read-only observation.
 * NOT a message submission CLI or a managed transport selector.
 */
import {inspectLegacyUiReadOnly,assessLegacyUiReadiness}
  from "./legacy_ui_probe.mjs";
let browser;
const guard=setTimeout(()=>{
  console.log(JSON.stringify({purpose:"legacy-ui-transport-assessment",
    submission_authorized:false,supported_for_automated_tasks:false,
    error_code:"LEGACY_UI_PROBE_TIMEOUT"}));
  process.exit(124);
},20000);
try {
  if(process.argv.length>2&&process.argv[2]!=="probe")
    throw Error("UNSUPPORTED_READ_ONLY_OPERATION");
  const cdpUrl=process.env.HADALIS_CHATGPT_CDP_URL ??
    "http://127.0.0.1:9222";
  const parsed=new URL(cdpUrl);
  if(parsed.protocol!=="http:"||
     !["127.0.0.1","localhost","[::1]"].includes(parsed.hostname)||
     parsed.username||parsed.password||parsed.pathname!=="/"||
     parsed.search||parsed.hash)
    throw Error("CDP_MUST_BE_LOOPBACK");
  const moduleUrl=process.env.HADALIS_PLAYWRIGHT_MODULE ??
    "file:///usr/lib/chatgpt/resources/cua_node/lib/node_modules/playwright-core/index.mjs";
  const {chromium}=await import(moduleUrl);
  browser=await chromium.connectOverCDP(cdpUrl,{timeout:9000});
  const pages=browser.contexts().flatMap(c=>c.pages())
    .filter(p=>p.url()==="app://-/index.html");
  if(pages.length!==1)throw Error("DESKTOP_MAIN_PAGE_NOT_UNIQUE");
  const project=process.env.HADALIS_CHATGPT_PROJECT??"Automatic Alis";
  const snapshot=await inspectLegacyUiReadOnly(pages[0],project);
  const readiness=assessLegacyUiReadiness(snapshot);
  console.log(JSON.stringify({...snapshot,...readiness,
    purpose:"legacy-ui-read-only-transport-probe"}));
} catch(error){
  const allowed=new Set(["UNSUPPORTED_READ_ONLY_OPERATION",
    "CDP_MUST_BE_LOOPBACK","DESKTOP_MAIN_PAGE_NOT_UNIQUE",
    "INVALID_PROJECT_NAME","WRONG_RENDERER","AMBIGUOUS_UI_COUNT"]);
  const code=allowed.has(error?.message)?error.message:
    "LEGACY_UI_PROBE_UNAVAILABLE";
  console.log(JSON.stringify({purpose:"legacy-ui-read-only-transport-probe",
    submission_authorized:false,supported_for_automated_tasks:false,
    error_code:code}));
  process.exitCode=1;
} finally {
  clearTimeout(guard);
  try{if(browser)await browser.close();}catch{}
}
