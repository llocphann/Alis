#!/usr/bin/env node
/* Only synthetic page + durable-journal mocks. Never connects to Desktop. */
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {spawnSync} from "node:child_process";
import {fileURLToPath,pathToFileURL} from "node:url";
import {persistHarmlessUiAttempt} from
  "../automation/chat_bridge/legacy_ui_journal.mjs";
import {oneShotUiAcceptance} from
  "../automation/chat_bridge/legacy_ui_acceptance.mjs";
const id="11111111-1111-4111-8111-111111111111";
const events=[];
let disabled=false,draft="",busy=false,clickThrows=false,fillThrows=false;
let sendDisabled=true,keepSendDisabledAfterFill=false;
let forceForeignDraftAfterFill=false;
let hiddenComposerBeforeVisible=false,hiddenSendBeforeVisible=false;
let duplicateVisibleSend=false;
let projectListHidden=false,projectBadgeHidden=false;
function loc(items,kind){
  return {
    count:async()=>items.length,
    nth:i=>loc([items[i]],kind),
    first:()=>loc([items[0]],kind),
    isVisible:async()=>items[0]?.visible??false,
    isDisabled:async()=>kind==="send"?sendDisabled:
      (items[0]?.disabled??false),
    evaluate:async (fn,expected)=>{
      // A hidden duplicate must never be read or clicked, regardless of
      // its position before the one visible accessible-role control.
      if(items[0]?.visible===false)throw Error("HIDDEN_CONTROL_USED");
      if(kind==="send"){
        events.push("click");
        if(clickThrows)throw Error("UNKNOWN_CLICK_OUTCOME");
        return fn({click:()=>{}}); // only one attempted click
      }
      return fn({textContent:kind==="editor"?draft:(items[0]?.draft??"")},
        expected);
    },
    fill:async value=>{
      if(items[0]?.visible===false)throw Error("HIDDEN_COMPOSER_USED");
      events.push("fill");
      assert.match(value,/AUTO-F01 UI transport acceptance test only/);
      assert.ok(!value.includes("secret"));
      if(fillThrows)throw Error("UNKNOWN_COMPOSER_OUTCOME");
      draft=forceForeignDraftAfterFill?"ghp_FOREIGN_DRAFT":value;
      if(!keepSendDisabledAfterFill)sendDisabled=false;
    },
    locator:()=>loc([],"selected"),
    getByRole:()=>loc([],"heading"),
    getByText:()=>loc([],"text")
  };
}
const page={
  url:()=> "app://-/index.html",
  getByRole:(role,options)=>{
    if(role==="main")return {
      ...loc([{visible:true}],"main"),
      getByRole:()=>loc([],"heading"),
      getByText:(label)=>loc(["Automatic Alis","No chats yet"]
        .includes(label)?[{visible:true}]:[],"text")
    };
    if(role==="textbox")return loc([
      ...(hiddenComposerBeforeVisible?[{visible:false,disabled,draft:"foreign"}]:[]),
      {visible:true,disabled,draft}
    ],"editor");
    if(role==="dialog")return loc([],"dialog");
    if(role==="list")return loc(projectListHidden?[]:
      [{visible:true,selected:[]}],"list");
    if(role==="button"&&options.name==="Send")
      return loc([
        ...(hiddenSendBeforeVisible?[{visible:false,disabled:false}]:[]),
        {visible:true,disabled:sendDisabled},
        ...(duplicateVisibleSend?[{visible:true,disabled:sendDisabled}]:[])
      ],"send");
    if(role==="button"&&options.name instanceof RegExp &&
       options.name.test("Stop"))
      return loc(busy?[{visible:true}]:[],"stop");
    return loc(projectBadgeHidden?[]:[{visible:true}],"badge");
  }
};
const seen=new Set();
const persistAttempt=async record=>{
  assert.equal(record.kind,"harmless-ui-acceptance");
  assert.equal(record.outcome,"indeterminate-once-attempted");
  assert.ok(!seen.has(record.id),"duplicate attempt must remain quarantined");
  seen.add(record.id);
  events.push("durable-intent");
};
const call=overrides=>oneShotUiAcceptance({page,acceptanceId:id,
  ownerApproved:true,persistAttempt,...overrides});
let r=await call({ownerApproved:false});
assert.equal(r.status,"blocked");
assert.deepEqual(events,[]);
r=await call({acceptanceId:"not-a-uuid"});
assert.equal(r.status,"blocked");
assert.deepEqual(events,[]);
r=await call({persistAttempt:undefined});
assert.equal(r.status,"blocked");
assert.deepEqual(events,[]);
draft="ghp_FAKE_EXISTING_DRAFT";
r=await call();
assert.equal(r.status,"blocked");
assert.deepEqual(events,[]);
draft="";busy=true;
r=await call();
assert.equal(r.status,"blocked");
assert.deepEqual(events,[]);
busy=false;
r=await call();
assert.equal(r.status,"indeterminate");
assert.equal(r.code,"SINGLE_UI_CLICK_ISSUED_OBSERVE_ONLY");
assert.deepEqual(events,["durable-intent","fill","click"]);
assert.equal(r.submission_authorized,false);
draft="";sendDisabled=true;
await assert.rejects(call(),/duplicate attempt must remain quarantined/);
assert.deepEqual(events,["durable-intent","fill","click"]);
events.length=0;
const fresh="22222222-2222-4222-8222-222222222222";
clickThrows=true;
r=await call({acceptanceId:fresh});
assert.equal(r.status,"indeterminate");
assert.equal(r.code,"UI_ATTEMPT_UNCERTAIN_NO_RETRY");
assert.deepEqual(events,["durable-intent","fill","click"]);
events.length=0;clickThrows=false;draft="";sendDisabled=true;
fillThrows=true;
r=await call({acceptanceId:"33333333-3333-4333-8333-333333333333"});
assert.equal(r.status,"indeterminate");
assert.deepEqual(events,["durable-intent","fill"]);
events.length=0;fillThrows=false;draft="";sendDisabled=true;
await assert.rejects(call({
  acceptanceId:"44444444-4444-4444-8444-444444444444",
  persistAttempt:async()=>{throw Error("DISK_FSYNC_FAILED")}
}),/DISK_FSYNC_FAILED/);
assert.deepEqual(events,[]);
// If Send never becomes enabled after filling, the journal stays
// indeterminate and absolutely NO Send click is issued.
events.length=0;draft="";sendDisabled=true;
keepSendDisabledAfterFill=true;
r=await call({acceptanceId:"99999999-9999-4999-8999-999999999999"});
assert.equal(r.status,"indeterminate");
assert.equal(r.code,"POST_FILL_GUARD_FAILED_NO_SEND");
assert.deepEqual(events,["durable-intent","fill"]);
assert.equal(r.submission_authorized,false);
events.length=0;draft="";sendDisabled=true;
keepSendDisabledAfterFill=false;
// An unrelated draft inserted after fill must NEVER be submitted, even
// though it makes the Send control enabled and all UI visual guards pass.
forceForeignDraftAfterFill=true;
r=await call({acceptanceId:"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"});
assert.equal(r.status,"indeterminate");
assert.equal(r.code,"HARMLESS_DRAFT_MISMATCH_NO_SEND");
assert.deepEqual(events,["durable-intent","fill"]);
assert.equal(r.submission_authorized,false);
assert.ok(!JSON.stringify(r).includes("ghp_FOREIGN_DRAFT"));
events.length=0;draft="";sendDisabled=true;
forceForeignDraftAfterFill=false;
// Regression: the uniquely visible editor/Send can come AFTER hidden DOM
// duplicates. .first() would mutate or click a hidden foreign control.
hiddenComposerBeforeVisible=true;hiddenSendBeforeVisible=true;
r=await call({acceptanceId:"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"});
assert.equal(r.status,"indeterminate");
assert.equal(r.code,"SINGLE_UI_CLICK_ISSUED_OBSERVE_ONLY");
assert.deepEqual(events,["durable-intent","fill","click"]);
events.length=0;draft="";sendDisabled=true;
hiddenComposerBeforeVisible=false;hiddenSendBeforeVisible=false;
// Multiple visible Send controls are ambiguous; reject BEFORE journaling or
// touching any editor, even with otherwise valid Project evidence.
duplicateVisibleSend=true;
r=await call({acceptanceId:"cccccccc-cccc-4ccc-8ccc-cccccccccccc"});
assert.equal(r.status,"blocked");
assert.deepEqual(events,[]);
duplicateVisibleSend=false;

// Owner's live Desktop new-chat state: exact badge and scoped composer,
// no chat list visible. Must still journal and click ONCE, never infer ID.
projectListHidden=true;
events.length=0;draft="";sendDisabled=true;
r=await call({acceptanceId:"dddddddd-dddd-4ddd-8ddd-dddddddddddd"});
assert.equal(r.code,"SINGLE_UI_CLICK_ISSUED_OBSERVE_ONLY");
assert.deepEqual(events,["durable-intent","fill","click"]);
events.length=0;draft="";sendDisabled=true;
// A missing exact Project badge is never compensated by absent chat list.
projectBadgeHidden=true;
r=await call({acceptanceId:"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"});
assert.equal(r.status,"blocked");
assert.equal(r.code,"EMPTY_PROJECT_PREFLIGHT_NOT_READY");
assert.deepEqual(events,[]);
projectBadgeHidden=false;projectListHidden=false;
// Real offline fsynced journal cannot be replayed or silently overwritten.
const stateHome=fs.mkdtempSync(path.join(os.tmpdir(),"alis-ui-journal-"));
try {
  const record={id:"55555555-5555-4555-8555-555555555555",
    kind:"harmless-ui-acceptance",outcome:"indeterminate-once-attempted"};
  assert.equal(persistHarmlessUiAttempt(record,{stateHome}).persisted,true);
  const file=path.join(stateHome,"hadalis-automation",
    "legacy-ui-acceptance-attempts",record.id+".json");
  const body=fs.readFileSync(file,"utf8");
  assert.equal(JSON.parse(body).id,record.id);
  assert.equal(fs.statSync(file).mode&0o077,0);
  assert.ok(!body.includes("AUTO-F01 UI transport acceptance test only"));
  assert.throws(()=>persistHarmlessUiAttempt(record,{stateHome}),/EEXIST/);
  const invalid={...record,id:"../../ghp_PRIVATE_PAYLOAD"};
  assert.throws(()=>persistHarmlessUiAttempt(invalid,{stateHome}),
    /INVALID_ACCEPTANCE_JOURNAL_RECORD/);
}finally{fs.rmSync(stateHome,{recursive:true,force:true});}
// Owner-only CLI integration with mock Playwright. No actual Desktop access.
const mockRoot=fs.mkdtempSync(path.join(os.tmpdir(),"alis-ui-approved-cli-"));
try{
  const mockFile=path.join(mockRoot,"playwright.mjs");
  const mockLog=path.join(mockRoot,"clicks.txt");
  fs.writeFileSync(mockFile,[
    "import fs from 'node:fs';",
    "let draft='';let sendDisabled=true;",
    "const loc=(items=[],type='other')=>({",
    "count:async()=>items.length,nth:i=>loc([items[i]],type),",
    "first:()=>loc([items[0]],type),",
    "isVisible:async()=>items[0]?.visible??false,",
    "isDisabled:async()=>type==='send'?sendDisabled:(items[0]?.disabled??false),",
    "locator:()=>loc([]),",
    "getByRole:()=>loc([]),",
    "getByText:label=>loc((label==='Automatic Alis'||label==='No chats yet')",
    " ?[{visible:true}]:[]),",
    "fill:async value=>{draft=value;sendDisabled=false;},",
    "evaluate:async (fn,expected)=>type==='send'",
    " ?fn({click:()=>fs.appendFileSync(process.env.MOCK_LOG,'clicked\\n')})",
    " :fn({textContent:draft},expected)",
    "});",
    "const page={url:()=> 'app://-/index.html',",
    "getByRole:(role,o)=>{",
    "if(role==='main')return {...loc([{visible:true}]),",
    " getByRole:()=>loc([]),getByText:label=>loc(",
    " (label==='Automatic Alis'||label==='No chats yet')",
    " ?[{visible:true}]:[])};",
    "if(role==='textbox')return loc([{visible:true,disabled:false}],'composer');",
    "if(role==='dialog')return loc([]);",
    "if(role==='list')return loc([{visible:true,selected:[]}],'list');",
    "if(role==='button'&&o.name==='Send')return loc([{visible:true}],'send');",
    "if(role==='button'&&o.name instanceof RegExp&&o.name.test('Stop'))return loc([]);",
    "return loc([{visible:true}],'badge');",
    "}};",
    "export const chromium={connectOverCDP:async url=>{",
    "if(url!=='http://127.0.0.1:9222')throw Error('UNEXPECTED_URL');",
    "return {contexts:()=>[{pages:()=>[page]}],close:async()=>{}}",
    "}};"
  ].join("\n"));
  const cli=fileURLToPath(new URL(
    "../automation/chat_bridge/legacy_ui_acceptance_cli.mjs",import.meta.url));
  const run=(args,extra={})=>spawnSync(process.execPath,[cli,...args],{
    encoding:"utf8",timeout:6000,
    env:{...process.env,XDG_STATE_HOME:mockRoot,MOCK_LOG:mockLog,
      HADALIS_CHATGPT_PROJECT:"Automatic Alis",
      HADALIS_CHATGPT_CDP_URL:"http://127.0.0.1:9222",
      HADALIS_PLAYWRIGHT_MODULE:pathToFileURL(mockFile).href,...extra}
  });
  const notApproved=run([]);
  assert.equal(notApproved.status,1);
  assert.equal(JSON.parse(notApproved.stdout).code,"EXPLICIT_APPROVAL_REQUIRED");
  assert.equal(fs.existsSync(mockLog),false);
  const fakeId="77777777-7777-4777-8777-777777777777";
  const first=run(["--owner-approved",fakeId]);
  assert.equal(first.status,2,first.stderr);
  assert.equal(JSON.parse(first.stdout).status,"indeterminate");
  assert.equal(fs.readFileSync(mockLog,"utf8"),"clicked\n");
  const again=run(["--owner-approved",fakeId]);
  assert.equal(again.status,2);
  assert.equal(JSON.parse(again.stdout).code,
    "ACCEPTANCE_UNAVAILABLE_OR_ALREADY_RECORDED_NO_RETRY");
  assert.equal(fs.readFileSync(mockLog,"utf8"),"clicked\n");
  const invalidRemote=run(["--owner-approved",
    "88888888-8888-4888-8888-888888888888"],{
    HADALIS_CHATGPT_CDP_URL:"http://example.com:9222"});
  assert.equal(invalidRemote.status,2);
  assert.equal(JSON.parse(invalidRemote.stdout).code,"CDP_MUST_BE_LOOPBACK");
  assert.equal(fs.readFileSync(mockLog,"utf8"),"clicked\n");
  assert.ok(!first.stdout.includes(fakeId));
}finally{fs.rmSync(mockRoot,{recursive:true,force:true});}
// No output can attest a server accepted the test or that a project ID
// matches. This primitive is deliberately absent from the production CLI.
console.log("PASS AUTO-F01: owner acceptance one-shot writes intent first, never retries, stays unverified");
