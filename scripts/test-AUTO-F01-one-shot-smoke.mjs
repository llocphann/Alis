#!/usr/bin/env node
/* Synthetic Desktop/CDP only. No live account, send or backend access. */
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {spawnSync} from "node:child_process";
import {fileURLToPath,pathToFileURL} from "node:url";
const root=fs.mkdtempSync(path.join(os.tmpdir(),"alis-smoke-mock-"));
try{
  const fake=path.join(root,"playwright.mjs");
  fs.writeFileSync(fake,"export const chromium={};\n");
  process.env.ALIS_PLAYWRIGHT_MODULE=pathToFileURL(fake).href;
  const {oneShotUiSmoke,SMOKE_ACCEPTANCE_ID}=await import(
    "../automation/chat_bridge/alis_ui_smoke.mjs");
  assert.match(SMOKE_ACCEPTANCE_ID,/^[0-9a-f-]{36}$/);
  const PROJECT="Automatic Alis";
  function makePage({initialScoped=false,initialDraft="",assistant=true,
    chatId=true,ambiguousAction=false,targetListInitiallyHidden=false,
    targetListAlwaysHidden=false,targetListAmbiguous=false}={}){
    let scoped=initialScoped,draft=initialDraft,submitted=false;
    let navClicks=0,sendClicks=0,fillCount=0;
    const oldDraft=initialDraft;
    const shown=()=>[{visible:true}];
    const loc=(resolve,kind)=>({
      count:async()=>resolve().length,
      nth:i=>loc(()=>[resolve()[i]].filter(Boolean),kind),
      isVisible:async()=>resolve()[0]?.visible===true,
      isDisabled:async()=>{
        if(kind==="send")return draft.length===0;
        return resolve()[0]?.disabled===true;
      },
      getAttribute:async key=>kind==="action"?"Copy":null,
      innerText:async()=>kind==="action"?"Copy":"",
      evaluate:async(fn,arg)=>{
        if(kind==="action")return assistant?{
          extractionSignal:"assistant-turn",text:"ALIS_LOOP:DONE",markerCount:1
        }:null;
        const element={
          textContent:draft,
          getAttribute:key=>kind==="selected"&&key==="data-chat-id"&&chatId
            ?"1234567890abcdef1234567890abcdef":null,
          closest:()=>null,querySelector:()=>null,
          click:()=>{
            if(kind==="nav"){navClicks++;scoped=true;draft="";}
            else if(kind==="send"){sendClicks++;submitted=true;draft="";}
            else throw Error("FORBIDDEN_CLICK");
          }
        };
        return fn(element,arg);
      },
      fill:async text=>{
        assert.equal(kind,"editor");fillCount++;draft=text;
      },
      locator:selector=>kind==="list" &&
        selector==='[role="button"][aria-current="page"]'
        ?loc(()=>submitted?shown():[],"selected"):loc(()=>[],"none"),
      getByRole:()=>loc(()=>[],"none"),
      getByText:label=>kind==="main"
        ?loc(()=>scoped&&["Automatic Alis","No chats yet"].includes(label)
          ?shown():[],"label"):loc(()=>[],"none")
    });
    const page={
      url:()=>"app://-/index.html",
      getByRole:(role,opt={})=>{
        const name=opt.name;
        if(role==="main")return loc(shown,"main");
        if(role==="textbox"){
          if(typeof name==="string")return loc(
            ()=>name==="New chat in "+PROJECT&&scoped?shown():[],"editor");
          if(name instanceof RegExp){
            const ask=name.test("Ask ChatGPT");
            const project=name.test("New chat in "+PROJECT);
            return loc(()=>ask&&project||scoped&&project||!scoped&&ask
              ?shown():[],"editor");
          }
        }
        if(role==="list")return loc(
          ()=>targetListAmbiguous?[{visible:true},{visible:true}]:
            targetListAlwaysHidden||targetListInitiallyHidden&&!scoped
              ?[]:shown(),"list");
        if(role==="button"){
          if(name==="Send")return loc(shown,"send");
          if(name==="Start new chat in "+PROJECT&&opt.exact)return loc(
            ()=>ambiguousAction?[{visible:true},{visible:true}]:[],"nav");
          if(name==="New chat in "+PROJECT&&opt.exact)return loc(shown,"nav");
          if(name instanceof RegExp){
            if(name.test("Stop"))return loc(()=>[],"none");
            if(name.test("Project: "+PROJECT))return loc(
              ()=>scoped?shown():[],"badge");
            if(name.test("New chat in "+PROJECT))return loc(shown,"nav");
            if(name.test("regenerate")||name.test("copy"))return loc(
              ()=>submitted?shown():[],"action");
          }
        }
        return loc(()=>[],"none");
      }
    };
    return {page,get:()=>({navClicks,sendClicks,fillCount,submitted,
      originalDraft:oldDraft,currentDraft:draft})};
  }
  const wait=async()=>{};
  const journal=new Set();
  const events=[];
  const persistAttempt=async record=>{
    assert.equal(record.id,SMOKE_ACCEPTANCE_ID);
    if(journal.has(record.id))throw Error("DUPLICATE_SMOKE");
    journal.add(record.id);
    events.push("journal");
  };
  const blockedPage=makePage();
  const noConsent=await oneShotUiSmoke({page:blockedPage.page,
    ownerApproved:false,persistAttempt,wait,maxResponsePolls:2});
  assert.equal(noConsent.status,"blocked");
  assert.equal(blockedPage.get().navClicks,0);
  assert.equal(blockedPage.get().sendClicks,0);
  assert.equal(journal.size,0);

  // User's real failure state: foreign/global composer has a draft.
  // One Project navigation, then one journal-before-fill-before-Send.
  const p=makePage({initialDraft:"FOREIGN_PRIVATE_DRAFT",
    targetListInitiallyHidden:true});
  const r=await oneShotUiSmoke({page:p.page,ownerApproved:true,
    persistAttempt:async record=>{
      await persistAttempt(record);
      assert.equal(p.get().sendClicks,0,"journal precedes Send");
      assert.equal(p.get().fillCount,0,"journal precedes fill");
    },wait,maxResponsePolls:3});
  assert.equal(r.status,"observed",JSON.stringify(r));
  assert.equal(r.assistant_only_reply_observed,true);
  assert.equal(r.selected_chat_identity_stable,true);
  assert.equal(r.message_submission_verified,false);
  assert.equal(r.server_identity_attested,false);
  assert.equal(r.ui_scheduler_authorized,false);
  assert.equal(r.queue_started,false);
  assert.equal(p.get().navClicks,1);
  assert.equal(p.get().sendClicks,1);
  assert.equal(p.get().fillCount,1);
  assert.equal(p.get().originalDraft,"FOREIGN_PRIVATE_DRAFT");
  assert.deepEqual(events,["journal"]);

  // Second command cannot generate another acceptance attempt/Send.
  const q=makePage({initialScoped:true});
  const duplicate=await oneShotUiSmoke({page:q.page,ownerApproved:true,
    persistAttempt,wait,maxResponsePolls:1});
  assert.notEqual(duplicate.status,"observed");
  assert.equal(q.get().sendClicks,0);
  assert.equal(journal.size,1);

  // New chat already selected in Project: do not navigate unnecessarily.
  const r2=makePage({initialScoped:true,assistant:false});
  const noAssistant=await oneShotUiSmoke({page:r2.page,ownerApproved:true,
    persistAttempt:async()=>{},wait,maxResponsePolls:2});
  assert.equal(noAssistant.status,"sent_unverified");
  assert.equal(noAssistant.assistant_only_reply_observed,false);
  assert.equal(r2.get().navClicks,0);
  assert.equal(r2.get().sendClicks,1);

  // A user-prompt marker is NOT an assistant-only turn.
  const unbound=makePage({chatId:false});
  const noId=await oneShotUiSmoke({page:unbound.page,ownerApproved:true,
    persistAttempt:async()=>{},wait,maxResponsePolls:1});
  assert.equal(noId.status,"sent_unverified");
  assert.equal(noId.assistant_only_reply_observed,true);
  assert.equal(noId.selected_chat_identity_stable,false);

  // The navigation target must become verifiable after exactly one click.
  // A sidebar button alone must never be used as Send authority.
  const listNeverAppears=makePage({initialDraft:"FOREIGN_DRAFT",
    targetListAlwaysHidden:true});
  const unverified=await oneShotUiSmoke({page:listNeverAppears.page,
    ownerApproved:true,persistAttempt:async()=>{throw Error("NO_JOURNAL_ALLOWED");},
    wait,maxResponsePolls:1});
  assert.equal(unverified.code,"ALIS_UI_PROJECT_NAVIGATION_NOT_VERIFIED");
  assert.equal(unverified.navigation_click_attempted,true);
  assert.equal(listNeverAppears.get().navClicks,1);
  assert.equal(listNeverAppears.get().fillCount,0);
  assert.equal(listNeverAppears.get().sendClicks,0);

  const listAmbiguous=makePage({targetListAmbiguous:true});
  const blockedList=await oneShotUiSmoke({page:listAmbiguous.page,
    ownerApproved:true,persistAttempt:async()=>{throw Error("NO_JOURNAL_ALLOWED");},
    wait,maxResponsePolls:1});
  assert.equal(blockedList.code,"ALIS_UI_NAVIGATION_UNSAFE");
  assert.ok(blockedList.navigation_blockers.includes("TARGET_PROJECT_LIST_AMBIGUOUS"));
  assert.equal(listAmbiguous.get().navClicks,0);
  assert.equal(listAmbiguous.get().sendClicks,0);

  const weird=makePage({ambiguousAction:true});
  const ambiguous=await oneShotUiSmoke({page:weird.page,ownerApproved:true,
    persistAttempt:async()=>{},wait,maxResponsePolls:1});
  assert.equal(ambiguous.code,"ALIS_UI_PROJECT_NEW_CHAT_ACTION_AMBIGUOUS");
  assert.equal(weird.get().navClicks,0);
  assert.equal(weird.get().sendClicks,0);

  // No owner flag / remote CDP never even connects.
  const cli=fileURLToPath(new URL(
    "../automation/chat_bridge/alis_ui_smoke_cli.mjs",import.meta.url));
  const run=(args,env={})=>spawnSync(process.execPath,[cli,...args],{
    encoding:"utf8",timeout:5000,env:{...process.env,...env}});
  let v=run([]);
  assert.equal(v.status,1);
  assert.equal(JSON.parse(v.stdout).code,"EXPLICIT_OWNER_APPROVAL_REQUIRED");
  v=run(["--owner-approved"],{ALIS_CHATGPT_CDP_URL:"http://example.com:9222"});
  assert.equal(v.status,1);
  assert.equal(JSON.parse(v.stdout).code,"ALIS_UI_CDP_LOOPBACK_REQUIRED");

  // A journaled one-shot must be rejected BEFORE CDP/import/navigation.
  // Force the Playwright module to be unimportable: an early journal guard
  // should still give the explicit no-retry code.
  const {persistHarmlessUiAttempt}=await import(
    "../automation/chat_bridge/legacy_ui_journal.mjs");
  persistHarmlessUiAttempt({
    id:SMOKE_ACCEPTANCE_ID,kind:"harmless-ui-acceptance",
    outcome:"indeterminate-once-attempted"
  },{stateHome:root});
  v=run(["--owner-approved"],{
    ALIS_CHATGPT_CDP_URL:"http://127.0.0.1:9222",
    ALIS_PLAYWRIGHT_MODULE:"file:///nonexistent/never-load-playwright.mjs",
    XDG_STATE_HOME:root
  });
  assert.equal(v.status,1,v.stderr);
  assert.equal(JSON.parse(v.stdout).code,
               "ALIS_UI_SMOKE_ALREADY_RECORDED_NO_RETRY");
  console.log("PASS AUTO-F01 one-command mock navigation -> immutable journal -> harmless Send -> assistant-only response -> UI chat key, no retry");
}finally{
  fs.rmSync(root,{recursive:true,force:true});
}
