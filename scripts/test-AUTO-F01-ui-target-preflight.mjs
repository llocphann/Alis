#!/usr/bin/env node
/* AUTO-F01: synthetic Desktop/CDP, no real chat, no send or account access. */
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {spawnSync} from "node:child_process";
import {fileURLToPath, pathToFileURL} from "node:url";

const root = fs.mkdtempSync(path.join(os.tmpdir(), "alis-target-check-"));
try {
  const mock = path.join(root, "playwright.mjs");
  fs.writeFileSync(mock, `
const scenario=process.env.MOCK_SCENARIO;
const fail=()=>{throw Error("MOCK_READ_ONLY_MUTATION");};
const loc=(items=[],tag="")=>({
  count:async()=>items.length,
  nth:i=>loc([items[i]],tag),
  isVisible:async()=>items[0]?.visible??false,
  isDisabled:async()=>items[0]?.disabled??false,
  evaluate:async fn=>fn({
    textContent:items[0]?.draft??"",
    getAttribute:key=>items[0]?.attributes?.[key]??null,
    closest:()=>null,
    querySelector:()=>null
  }),
  locator:selector=>tag==="list" &&
    selector==='[role="button"][aria-current="page"]'
      ?loc(scenario==="selected"||scenario==="missing-id"
        ?[{visible:true,attributes:scenario==="selected"
          ?{"data-chat-id":"1234567890abcdef1234567890abcdef"}:{}}]
        :scenario==="ambiguous"?[{visible:true},{visible:true}]:[],"selected")
      :loc([]),
  getByRole:()=>loc([]),
  getByText:()=>loc([]),
  click:fail,fill:fail,focus:fail,press:fail
});
const scoped=scenario==="blank"||scenario==="draft";
const draft=scenario==="draft"?"ghp_DO_NOT_EXPOSE":"";
const editor=scoped?[{visible:true,disabled:false,draft}]
                   :[{visible:true,disabled:false,draft:""}];
const p={
  url:()=>"app://-/index.html",
  waitForTimeout:async()=>{},
  evaluate:fail,
  keyboard:{press:fail,insertText:fail},
  getByRole:(role,q={})=>{
    if(role==="main")return loc([{visible:true}],"main");
    if(role==="textbox") {
      if(typeof q.name==="string")
        return loc(q.name==="New chat in Automatic Alis"&&scoped?editor:[]);
      if(q.name?.test?.("New chat in Automatic Alis") &&
         !q.name?.test?.("Ask ChatGPT"))return loc(scoped?editor:[]);
      if(q.name?.test?.("Ask ChatGPT") &&
         !q.name?.test?.("New chat in Automatic Alis"))
        return loc(scoped?[]:editor);
      return loc(editor);
    }
    if(role==="list")return loc([{visible:true}],"list");
    if(role==="button") {
      if(q.name==="Send")return loc(scoped?[{visible:true,disabled:true}]
                                           :[{visible:true,disabled:false}]);
      if(q.name instanceof RegExp && q.name.test("Stop"))return loc([]);
      if(q.name instanceof RegExp &&
         (q.name.test("Project: Automatic Alis") ||
          q.name.test("Change project: Automatic Alis")))
        return loc(scoped?[{visible:true}]:[]);
      if(q.name instanceof RegExp &&
         q.name.test("New chat in Automatic Alis"))
        return loc([{visible:true}]);
    }
    return loc([]);
  }
};
export const chromium={connectOverCDP:async url=>{
  if(url!=="http://127.0.0.1:9222")throw Error("MOCK_UNEXPECTED_URL");
  return {contexts:()=>[{pages:()=>[p]}],close:async()=>{}};
}};
`);
  const cli=fileURLToPath(new URL(
    "../automation/chat_bridge/desktop_cli.mjs",import.meta.url));
  function check(scenario){
    const p=spawnSync(process.execPath,[cli,"ui-target-check"],{
      encoding:"utf8",timeout:6000,
      env:{
        ...process.env,
        ALIS_PLAYWRIGHT_MODULE:pathToFileURL(mock).href,
        ALIS_CHATGPT_CDP_URL:"http://127.0.0.1:9222",
        ALIS_CHATGPT_PROJECT:"Automatic Alis",
        MOCK_SCENARIO:scenario
      }
    });
    assert.equal(p.status,0,p.stderr);
    assert.ok(!p.stdout.includes("1234567890abcdef"));
    assert.ok(!p.stdout.includes("ghp_DO_NOT_EXPOSE"));
    return JSON.parse(p.stdout);
  }
  const blank=check("blank");
  assert.equal(blank.selected_chat_identity_stable,false);
  assert.equal(blank.empty_project_entry_ready,true);
  assert.equal(blank.diagnosis,"ALIS_UI_EMPTY_PROJECT_ENTRY_OBSERVED");
  const selected=check("selected");
  assert.equal(selected.selected_chat_identity_stable,true);
  assert.equal(selected.empty_project_entry_ready,false);
  assert.equal(selected.diagnosis,"ALIS_UI_CHAT_TARGET_OBSERVED");
  for(const scenario of ["generic","draft","missing-id","ambiguous"]){
    const result=check(scenario);
    assert.equal(result.selected_chat_identity_stable,false,scenario);
    assert.equal(result.empty_project_entry_ready,false,scenario);
    assert.equal(result.diagnosis,"ALIS_UI_CHAT_IDENTITY_UNAVAILABLE",scenario);
    assert.equal(result.message_submission_attempted,false);
    assert.equal(result.server_identity_attested,false);
    assert.equal(result.ui_scheduler_authorized,false);
  }
  assert.equal(blank.message_submission_attempted,false);
  assert.equal(blank.ui_scheduler_authorized,false);
  assert.equal(selected.ui_scheduler_authorized,false);
  console.log("PASS AUTO-F01: existing-chat identity vs blank Project entry is read-only and never authorizes send");
} finally {
  fs.rmSync(root,{recursive:true,force:true});
}
