#!/usr/bin/env node
/* AUTO-F01 mock UI/CDP — NO live Desktop, send or account access. */
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {spawnSync} from "node:child_process";
import {fileURLToPath,pathToFileURL} from "node:url";
import {inspectLegacyUiReadOnly,assessLegacyUiReadiness}
  from "../automation/chat_bridge/legacy_ui_probe.mjs";
const failWrite=()=>{throw Error("MOCK_WOULD_MUTATE_DESKTOP");};
const makeLocator=(items=[])=>({
  async count(){return items.length;},
  nth(i){return makeLocator([items[i]]);},
  first(){return makeLocator([items[0]]);},
  async isVisible(){return items[0]?.visible??false;},
  async isDisabled(){return items[0]?.disabled??false;},
  async evaluate(fn){return fn({textContent:items[0]?.draft??""});},
  locator(){return makeLocator(items[0]?.selected??[]);},
  click:failWrite,fill:failWrite,focus:failWrite,press:failWrite
});
const page=(opts={})=>{
  const data={composer:opts.composer??[{visible:true,disabled:false,draft:""}],
    badge:opts.badge??[{visible:true}],list:opts.list??[],
    send:opts.send??[{visible:true,disabled:false}],stop:opts.stop??[]};
  return {
    url:()=>opts.url??"app://-/index.html",
    keyboard:{press:failWrite,insertText:failWrite},
    evaluate:failWrite,
    getByRole(role,options){
      if(role==="textbox")return makeLocator(data.composer);
      if(role==="list")return makeLocator(data.list);
      if(role==="button"&&options.name==="Send")return makeLocator(data.send);
      if(role==="button"&&options.name instanceof RegExp &&
          options.name.test("Stop"))return makeLocator(data.stop);
      if(role==="button")return makeLocator(data.badge);
      throw Error("UNEXPECTED_ROLE");
    }
  };
};
const inspect=async p=>assessLegacyUiReadiness(
  await inspectLegacyUiReadOnly(page(p)));
let result=await inspect();
assert.equal(result.observation_ready,true);
assert.equal(result.project_view_visible,true);
assert.equal(result.project_identity_verified,false);
assert.equal(result.conversation_identity_verified,false);
assert.equal(result.submission_authorized,false);
assert.equal(result.scheduler_activation_authorized,false);
assert.equal(result.supported_for_automated_tasks,false);
result=await inspect({badge:[],list:[{visible:true,selected:[{visible:true}]}]});
assert.equal(result.observation_ready,true);
result=await inspect({badge:[],list:[]});
assert.equal(result.observation_ready,false);
assert.ok(result.readiness_issues.includes("PROJECT_UI_GUARD_NOT_UNIQUE"));
result=await inspect({composer:[{visible:true,draft:"ghp_FAKE_DRAFT"}]});
assert.ok(result.readiness_issues.includes("COMPOSER_NOT_EMPTY_OR_UNVERIFIED"));
assert.ok(!JSON.stringify(result).includes("ghp_FAKE_DRAFT"));
result=await inspect({stop:[{visible:true}]});
assert.ok(result.readiness_issues.includes("GENERATION_BUSY_OR_UNVERIFIED"));
result=await inspect({send:[{visible:true,disabled:true}]});
assert.ok(result.readiness_issues.includes("SEND_CONTROL_NOT_READY"));
result=await inspect({composer:[]});
assert.ok(result.readiness_issues.includes("COMPOSER_NOT_UNIQUE"));
result=await inspect({composer:[{visible:true},{visible:true}]});
assert.ok(result.readiness_issues.includes("COMPOSER_NOT_UNIQUE"));
result=await assessLegacyUiReadiness({
 renderer_matches:true,composer_count_capped:1,
 project_badge_count_capped:1,send_count_capped:1,
 send_disabled:false,stop_count_capped:0,composer_draft_present:false,
 composer_disabled:false,supported:true,submission_authorized:true,
 project_identity_verified:true,server_receipt_verified:true
});
assert.equal(result.observation_ready,true);
assert.equal(result.submission_authorized,false);
assert.equal(result.project_identity_verified,false);
await assert.rejects(()=>inspectLegacyUiReadOnly(page({url:"http://example.org"})),
  /WRONG_RENDERER/);
await assert.rejects(()=>inspectLegacyUiReadOnly(page(),"INVALID/NAME"),
  /INVALID_PROJECT_NAME/);
assert.equal(assessLegacyUiReadiness(null).submission_authorized,false);

// Execute the exact read-only CLI with synthetic Playwright. Any click,
// focus, fill, keyboard, network fetch or outbound submission fails in mock.
const dir=fs.mkdtempSync(path.join(os.tmpdir(),"alis-ui-probe-"));
try {
  const fake=path.join(dir,"playwright.mjs");
  fs.writeFileSync(fake,[
    "const fail=()=>{throw Error('FORBIDDEN_MUTATION')};",
    "const locator=(items=[])=>({",
    "count:async()=>items.length,",
    "nth:i=>locator([items[i]]),first:()=>locator([items[0]]),",
    "isVisible:async()=>items[0]?.visible??false,",
    "isDisabled:async()=>items[0]?.disabled??false,",
    "evaluate:async fn=>fn({textContent:items[0]?.draft??''}),",
    "locator:()=>locator(items[0]?.selected??[]),",
    "click:fail,fill:fail,focus:fail});",
    "const p={url:()=> 'app://-/index.html',",
    "evaluate:fail,keyboard:{press:fail,insertText:fail},",
    "getByRole:(role,opt)=>{",
    "if(role==='textbox')return locator([{visible:true,disabled:false}]);",
    "if(role==='list')return locator([]);",
    "if(role==='button'&&opt.name==='Send')return locator([{visible:true}]);",
    "if(role==='button'&&opt.name instanceof RegExp&&opt.name.test('Stop'))return locator([]);",
    "return locator([{visible:true}]);}};",
    "export const chromium={connectOverCDP:async url=>{",
    "if(url!=='http://127.0.0.1:9222')throw Error('UNEXPECTED_URL');",
    "return {contexts:()=>[{pages:()=>[p]}],close:async()=>{}};",
    "}};"
  ].join("\n"));
  const cli=fileURLToPath(new URL("../automation/chat_bridge/legacy_ui_probe_cli.mjs",import.meta.url));
  const run=(args,extra={})=>spawnSync(process.execPath,[cli,...args],{
    encoding:"utf8",timeout:5000,
    env:{...process.env,HADALIS_PLAYWRIGHT_MODULE:pathToFileURL(fake).href,
      HADALIS_CHATGPT_CDP_URL:"http://127.0.0.1:9222",
      HADALIS_CHATGPT_PROJECT:"Automatic Alis",...extra}
  });
  const ok=run(["probe"]);
  assert.equal(ok.status,0,ok.stderr);
  const output=JSON.parse(ok.stdout);
  assert.equal(output.observation_ready,true);
  assert.equal(output.submission_authorized,false);
  assert.equal(output.project_identity_verified,false);
  const denied=run(["submit"]);
  assert.equal(denied.status,1);
  assert.equal(JSON.parse(denied.stdout).error_code,
    "UNSUPPORTED_READ_ONLY_OPERATION");
  const remote=run(["probe"],{HADALIS_CHATGPT_CDP_URL:"http://example.com:9222"});
  assert.equal(remote.status,1);
  assert.equal(JSON.parse(remote.stdout).error_code,"CDP_MUST_BE_LOOPBACK");
  for(const item of ["ghp_FAKE_DRAFT","Automatic Alis","PRIVATE","FORBIDDEN_MUTATION"]){
    assert.ok(!ok.stdout.includes(item),"private detail leaked in UI probe");
  }
}finally {fs.rmSync(dir,{recursive:true,force:true});}
console.log("PASS AUTO-F01 legacy CDP UI read-only probe and no-send gate");
