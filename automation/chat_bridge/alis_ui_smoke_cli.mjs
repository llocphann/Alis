#!/usr/bin/env node
/* AUTO-F01: complete smoke in ONE command. Desktop must already be running.
 * Explicit approval is needed; never called by queue or native scheduler.
 * One navigation click maximum + one send click maximum, no retries.
 */
import {oneShotUiSmoke} from "./alis_ui_smoke.mjs";
import {persistHarmlessUiAttempt} from "./legacy_ui_journal.mjs";
const denied=(code,status="blocked")=>({
  purpose:"alis-ui-one-shot-smoke",
  status,code,navigation_click_attempted:false,
  message_send_click_attempted:false,journal_recorded:false,
  assistant_only_reply_observed:false,
  selected_chat_identity_stable:false,
  message_submission_verified:false,
  server_identity_attested:false,ui_scheduler_authorized:false,
  queue_started:false
});
if(process.argv.length!==3||process.argv[2]!=="--owner-approved"){
  console.log(JSON.stringify(denied("EXPLICIT_OWNER_APPROVAL_REQUIRED")));
  process.exit(1);
}
const cdp=process.env.ALIS_CHATGPT_CDP_URL??
  process.env.HADALIS_CHATGPT_CDP_URL??"http://127.0.0.1:9222";
let local=false;
try{
  const u=new URL(cdp);
  local=u.protocol==="http:"&&
    ["localhost","127.0.0.1","[::1]"].includes(u.hostname)&&
    !u.username&&!u.password&&u.pathname==="/"&&!u.search&&!u.hash;
}catch{}
if(!local){
  console.log(JSON.stringify(denied("ALIS_UI_CDP_LOOPBACK_REQUIRED")));
  process.exit(1);
}
let browser;
const guard=setTimeout(()=>{
  console.log(JSON.stringify(denied("ALIS_UI_SMOKE_DEADLINE_NO_RETRY","uncertain")));
  process.exit(124);
},24000);
try{
  const path=process.env.ALIS_PLAYWRIGHT_MODULE??
    process.env.HADALIS_PLAYWRIGHT_MODULE??
    "file:///usr/lib/chatgpt/resources/cua_node/lib/node_modules/playwright-core/index.mjs";
  const {chromium}=await import(path);
  browser=await chromium.connectOverCDP(cdp,{timeout:6500});
  const pages=browser.contexts().flatMap(c=>c.pages())
    .filter(p=>p.url()==="app://-/index.html");
  if(pages.length!==1)throw Error("ALIS_UI_MAIN_PAGE_NOT_UNIQUE");
  const project=process.env.ALIS_CHATGPT_PROJECT??
    process.env.HADALIS_CHATGPT_PROJECT??"Automatic Alis";
  const result=await oneShotUiSmoke({
    page:pages[0],projectName:project,ownerApproved:true,
    persistAttempt:record=>persistHarmlessUiAttempt(record)
  });
  console.log(JSON.stringify(result));
  process.exitCode=result.status==="observed"?0:
    result.status==="blocked"?1:2;
}catch{
  // Suppress private CDP / Playwright context; never send again on error.
  console.log(JSON.stringify(denied("ALIS_UI_SMOKE_UNAVAILABLE_NO_RETRY","uncertain")));
  process.exitCode=2;
}finally{
  clearTimeout(guard);
  try{if(browser)await browser.close();}catch{}
}
