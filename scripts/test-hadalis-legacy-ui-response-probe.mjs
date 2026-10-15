#!/usr/bin/env node
/* AUTO-F01 mock-only: visual receipt observation, NEVER connects to Desktop. */
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {spawnSync} from "node:child_process";
import {fileURLToPath,pathToFileURL} from "node:url";
import {observeHarmlessUiResponse} from
  "../automation/chat_bridge/legacy_ui_response_probe.mjs";
const REQUEST="AUTO-F01 UI transport acceptance test only. "+
  "Do not use any connectors or tools. Reply with exactly: HADALIS_LOOP:DONE";
const REPLY="HADALIS_LOOP:DONE";
let requestCount=1,replyCount=1,projectGuard=true;
let mutationAttempts=0;
const loc=items=>({
  count:async()=>items.length,
  nth:i=>loc([items[i]]),
  first:()=>loc([items[0]]),
  isVisible:async()=>items[0]?.visible===true,
  isDisabled:async()=>Boolean(items[0]?.disabled),
  evaluate:async fn=>fn({textContent:""}),
  locator:()=>loc([]),
  getByRole:()=>loc([]),
  getByText:()=>loc([])
});
const entries=n=>Array.from({length:n},()=>({visible:true}));
const page={
  url:()=>"app://-/index.html",
  getByText:(text,opts)=>{
    assert.equal(opts.exact,true);
    if(text===REQUEST)return loc(entries(requestCount));
    if(text===REPLY)return loc(entries(replyCount));
    throw Error("PRIVATE_CHAT_READ_ATTEMPT");
  },
  getByRole:(role,opts={})=>{
    if(role==="main")return {
      ...loc(entries(1)),
      getByRole:()=>loc([]),
      getByText:(label,options)=>{
        assert.equal(options.exact,true);
        return loc(entries(label==="Automatic Alis"?1:0));
      }
    };
    if(role==="textbox"){
      if(typeof opts.name==="string")return loc(entries(projectGuard?1:0));
      if(opts.name instanceof RegExp&&opts.name.test("New chat in Automatic Alis"))
        return loc(entries(projectGuard?1:0));
      return loc([]);
    }
    if(role==="list")return {
      ...loc(entries(1)),locator:()=>loc([])
    };
    if(role==="button"&&opts.name==="Send")
      return loc([{visible:true,disabled:true}]);
    if(role==="button"&&opts.name instanceof RegExp){
      if(opts.name.test("Stop"))return loc([]);
      if(opts.name.test("Project: Automatic Alis"))
        return loc(entries(projectGuard?1:0));
      return loc([]);
    }
    return loc([]);
  },
  click:()=>{mutationAttempts++;throw Error("NO_UI_MUTATION");},
  fill:()=>{mutationAttempts++;throw Error("NO_UI_MUTATION");}
};
const test=async(code,req,reply,guard)=>{
  requestCount=req;replyCount=reply;projectGuard=guard;
  const r=await observeHarmlessUiResponse(page,"Automatic Alis");
  assert.equal(r.visual_pair_status,code);
  assert.equal(r.request_visible_count_capped,Math.min(3,req));
  assert.equal(r.reply_visible_count_capped,Math.min(3,reply));
  assert.equal(r.visual_project_guard_observed,guard);
  for(const key of ["server_project_membership_verified",
    "server_conversation_identity_verified",
    "server_user_message_identity_verified","final_receipt_verified",
    "submission_authorized","scheduler_activation_authorized",
    "supported_for_automated_tasks"])assert.equal(r[key],false);
  for(const secret of ["ghp_PRIVATE_TOKEN","Automatic Alis",
    REQUEST,REPLY,"conversation_id","user_message_id","project_id"])
    assert.equal(JSON.stringify(r).includes(secret),false);
};
await test("ONE_VISIBLE_HARMLESS_PAIR_NOT_ATTESTED",1,1,true);
await test("ONE_VISIBLE_HARMLESS_PAIR_NOT_ATTESTED",1,1,false);
await test("HARMLESS_PAIR_NOT_VISIBLE_OR_INCOMPLETE",1,0,true);
await test("HARMLESS_PAIR_NOT_VISIBLE_OR_INCOMPLETE",0,1,true);
await test("AMBIGUOUS_VISIBLE_HARMLESS_MESSAGES",2,1,true);
await test("AMBIGUOUS_VISIBLE_HARMLESS_MESSAGES",1,2,true);
await test("AMBIGUOUS_VISIBLE_HARMLESS_MESSAGES",3,3,true);
assert.equal(mutationAttempts,0);
const wrongRenderer={...page,url:()=>"https://example.com"};
await assert.rejects(observeHarmlessUiResponse(wrongRenderer),/WRONG_RENDERER/);

// CLI rejects submit/extra operands before connecting. There is no send mode.
const cli=fileURLToPath(new URL(
  "../automation/chat_bridge/legacy_ui_probe_cli.mjs",import.meta.url));
const denied=spawnSync(process.execPath,[cli,"submit"],{
  encoding:"utf8",timeout:6000
});
assert.equal(denied.status,1);
assert.equal(JSON.parse(denied.stdout).error_code,
  "UNSUPPORTED_READ_ONLY_OPERATION");
const extra=spawnSync(process.execPath,[cli,"observe-acceptance","again"],{
  encoding:"utf8",timeout:6000
});
assert.equal(extra.status,1);
assert.equal(JSON.parse(extra.stdout).submission_authorized,false);

// Verify the new command against synthetic CDP, with NO real Desktop.
// The renderer returns exactly one fixed request and reply; every locator
// is read-only. A call to fill/click would throw and fail this test.
const root=fs.mkdtempSync(path.join(os.tmpdir(),"alis-ui-reply-"));
try{
  const fake=path.join(root,"playwright.mjs");
  fs.writeFileSync(fake,`
  const req=${JSON.stringify(REQUEST)};
  const reply=${JSON.stringify(REPLY)};
  const loc=items=>({
    count:async()=>items.length,
    nth:i=>loc([items[i]]),
    first:()=>loc([items[0]]),
    isVisible:async()=>items[0]?.visible===true,
    isDisabled:async()=>!!items[0]?.disabled,
    evaluate:async f=>f({textContent:""}),
    locator:()=>loc([]),
    getByRole:()=>loc([]),
    getByText:()=>loc([]),
    fill:()=>{throw Error("MUTATION_FORBIDDEN");},
    click:()=>{throw Error("MUTATION_FORBIDDEN");}
  });
  const yes=()=>loc([{visible:true}]),no=()=>loc([]);
  const page={
    url:()=>"app://-/index.html",
    getByText:(value)=>value===req||value===reply?yes():no(),
    getByRole:(role,opt={})=>{
      if(role==="main")return {...yes(),
        getByRole:()=>no(),
        getByText:value=>value==="Automatic Alis"?yes():no()};
      if(role==="textbox")return typeof opt.name==="string"?yes():
        opt.name?.test?.("New chat in Automatic Alis")?yes():no();
      if(role==="list")return yes();
      if(role==="button"&&opt.name==="Send")return
        loc([{visible:true,disabled:true}]);
      if(role==="button"&&opt.name?.test?.("Stop"))return no();
      if(role==="button"&&opt.name?.test?.("Project: Automatic Alis"))
        return yes();
      return no();
    }
  };
  export const chromium={connectOverCDP:async url=>{
    if(url!=="http://127.0.0.1:9222")throw Error("UNEXPECTED_CDP_URL");
    return {contexts:()=>[{pages:()=>[page]}],close:async()=>{}};
  }};
  `);
  const outcome=spawnSync(process.execPath,[cli,"observe-acceptance"],{
    encoding:"utf8",timeout:6000,env:{...process.env,
      HADALIS_PLAYWRIGHT_MODULE:pathToFileURL(fake).href,
      HADALIS_CHATGPT_CDP_URL:"http://127.0.0.1:9222",
      HADALIS_CHATGPT_PROJECT:"Automatic Alis"}
  });
  assert.equal(outcome.status,0,outcome.stderr);
  const report=JSON.parse(outcome.stdout);
  assert.equal(report.visual_pair_status,
    "ONE_VISIBLE_HARMLESS_PAIR_NOT_ATTESTED");
  assert.equal(report.final_receipt_verified,false);
  assert.equal(report.submission_authorized,false);
  const forbidden=spawnSync(process.execPath,[cli,"observe-acceptance"],{
    encoding:"utf8",timeout:6000,env:{...process.env,
      HADALIS_PLAYWRIGHT_MODULE:pathToFileURL(fake).href,
      HADALIS_CHATGPT_CDP_URL:"http://example.com:9222"}
  });
  assert.equal(forbidden.status,1);
  assert.equal(JSON.parse(forbidden.stdout).error_code,"CDP_MUST_BE_LOOPBACK");
}finally{
  fs.rmSync(root,{recursive:true,force:true});
}
console.log("PASS AUTO-F01: no-send visual response probe stays categorical and unauthenticated");
