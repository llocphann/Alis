#!/usr/bin/env node
/* Explicit owner-only harmless acceptance — NEVER called by Scheduler.
 * No caller prompt, GitHub task code, connector or queue argument accepted.
 * Outcome after any attempted UI click remains indeterminate/no retry.
 */
import {oneShotUiAcceptance} from "./legacy_ui_acceptance.mjs";
import {persistHarmlessUiAttempt} from "./legacy_ui_journal.mjs";
const UUID=/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const args=process.argv.slice(2);
const approved=args.length===2&&args[0]==="--owner-approved"&&
  UUID.test(args[1]);
if(!approved){
  console.log(JSON.stringify({purpose:"owner-only-harmless-ui-acceptance",
    status:"blocked",code:"EXPLICIT_APPROVAL_REQUIRED",
    submission_authorized:false}));
  process.exit(1);
}
let browser;
const guard=setTimeout(()=>{
  console.log(JSON.stringify({purpose:"owner-only-harmless-ui-acceptance",
    status:"indeterminate",code:"ACCEPTANCE_DEADLINE_NO_RETRY",
    submission_authorized:false}));
  process.exit(124);
},25000);
try{
  const url=process.env.ALIS_CHATGPT_CDP_URL??process.env.HADALIS_CHATGPT_CDP_URL??"http://127.0.0.1:9222";
  const parsed=new URL(url);
  if(parsed.protocol!=="http:"||
    !["localhost","127.0.0.1","[::1]"].includes(parsed.hostname)||
    parsed.username||parsed.password||parsed.pathname!=="/"||
    parsed.search||parsed.hash)
    throw Error("CDP_MUST_BE_LOOPBACK");
  const moduleUrl=process.env.ALIS_PLAYWRIGHT_MODULE??process.env.HADALIS_PLAYWRIGHT_MODULE??
    "file:///usr/lib/chatgpt/resources/cua_node/lib/node_modules/playwright-core/index.mjs";
  const {chromium}=await import(moduleUrl);
  browser=await chromium.connectOverCDP(url,{timeout:9000});
  const pages=browser.contexts().flatMap(c=>c.pages())
    .filter(p=>p.url()==="app://-/index.html");
  if(pages.length!==1)throw Error("DESKTOP_MAIN_PAGE_NOT_UNIQUE");
  const result=await oneShotUiAcceptance({
    page:pages[0],ownerApproved:true,acceptanceId:args[1],
    projectName:process.env.ALIS_CHATGPT_PROJECT??process.env.HADALIS_CHATGPT_PROJECT??"Automatic Alis",
    persistAttempt:record=>persistHarmlessUiAttempt(record)
  });
  console.log(JSON.stringify({purpose:"owner-only-harmless-ui-acceptance",
    status:result.status,code:result.code,
    submission_authorized:false}));
  // A nonzero exit is intentional: even after a click, receipt is unverified.
  process.exitCode=result.status==="blocked"?1:2;
}catch(error){
  const allowed=new Set(["CDP_MUST_BE_LOOPBACK",
    "DESKTOP_MAIN_PAGE_NOT_UNIQUE","INVALID_PROJECT_NAME"]);
  console.log(JSON.stringify({purpose:"owner-only-harmless-ui-acceptance",
    status:"indeterminate",
    code:allowed.has(error?.message)?error.message:
      "ACCEPTANCE_UNAVAILABLE_OR_ALREADY_RECORDED_NO_RETRY",
    submission_authorized:false}));
  process.exitCode=2;
}finally{
  clearTimeout(guard);
  try{if(browser)await browser.close();}catch{}
}
