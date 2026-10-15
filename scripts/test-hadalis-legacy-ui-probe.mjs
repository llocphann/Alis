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
  async isDisabled(){
    return items[0]?.disabled===undefined?false:items[0].disabled;
  },
  async evaluate(fn){return fn({textContent:items[0]?.draft??""});},
  locator(){return makeLocator(items[0]?.selected??[]);},
  click:failWrite,fill:failWrite,focus:failWrite,press:failWrite
});
const page=(opts={})=>{
  const data={composer:opts.composer??[{visible:true,disabled:false,draft:""}],
    badge:opts.badge??[{visible:true}],list:opts.list??[],
    scopedComposer:opts.scopedComposer??[],
    action:opts.action??[],
    main:opts.main??[{visible:true}],
    mainHeading:opts.mainHeading??[],
    mainProjectText:opts.mainProjectText??[],
    mainEmptyState:opts.mainEmptyState??[],
    mainComposerVisualLabel:opts.mainComposerVisualLabel??[],
    send:opts.send??[{visible:true,disabled:false}],stop:opts.stop??[]};
  data.genericComposer=opts.genericComposer??(
    data.scopedComposer.length>0?[]:data.composer);
  return {
    url:()=>opts.url??"app://-/index.html",
    keyboard:{press:failWrite,insertText:failWrite},
    evaluate:failWrite,
    getByRole(role,options){
      if(role==="main")return {
        ...makeLocator(data.main),
        getByRole(kind,query){
          assert.equal(kind,"heading");
          assert.equal(query.name,"Automatic Alis");
          assert.equal(query.exact,true);
          return makeLocator(data.mainHeading);
        },
        getByText(label,query){
          assert.equal(query.exact,true);
          if(label==="Automatic Alis")
            return makeLocator(data.mainProjectText);
          if(label==="No chats yet")
            return makeLocator(data.mainEmptyState);
          if(label==="New chat in Automatic Alis")
            return makeLocator(data.mainComposerVisualLabel);
          throw Error("UNEXPECTED_MAIN_TEXT_QUERY");
        }
      };
      if(role==="textbox"&&options.name==="New chat in Automatic Alis" &&
         options.exact===true)return makeLocator(data.scopedComposer);
      if(role==="textbox"&&options.name instanceof RegExp &&
         options.name.test("Ask ChatGPT") &&
         !options.name.test("New chat in Automatic Alis"))
        return makeLocator(data.genericComposer);
      if(role==="textbox")return makeLocator(data.composer);
      if(role==="list")return makeLocator(data.list);
      if(role==="button"&&options.name==="Send")return makeLocator(data.send);
      if(role==="button"&&options.name instanceof RegExp &&
          options.name.test("Stop"))return makeLocator(data.stop);
      if(role==="button"&&options.name instanceof RegExp &&
          options.name.test("New chat in Automatic Alis"))
        return makeLocator(data.action);
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
// Owner's actual snapshot: project list visible, no selected conversation,
// blank editor, and no Send. This does not prove the editor is in Project.
result=await inspect({badge:[],list:[{visible:true,selected:[]}],send:[]});
assert.equal(result.project_view_visible,false);
assert.equal(result.observation_ready,false);
assert.equal(result.read_only_project_entry_ready,false);
assert.ok(result.readiness_issues.includes("PROJECT_UI_GUARD_NOT_UNIQUE"));
assert.ok(result.readiness_issues.includes(
  "SEND_ABSENT_ON_EMPTY_UNSCOPED_COMPOSER"));
assert.equal(result.composer_scope_evidence,
  "generic-label-without-project-guard");
assert.equal(result.send_control_state,"absent-on-empty-unscoped-composer");
assert.equal(result.project_new_chat_action_visible,false);
// The Project's new-chat action is a manual navigation affordance, never
// proof that the CURRENT blank editor belongs to that Project.
result=await inspect({badge:[],list:[{visible:true,selected:[]}],send:[],
  action:[{visible:true}]});
assert.equal(result.project_new_chat_action_visible,true);
assert.equal(result.project_view_visible,false);
assert.equal(result.main_project_view_evidence,"no-exact-project-heading-in-main");
// An exact heading in the current main region is only an additional
// visual navigation hint, not proof of server-side Project membership.
result=await inspect({badge:[],list:[{visible:true,selected:[]}],send:[],
  action:[{visible:true}],mainHeading:[{visible:true}]});
assert.equal(result.main_project_view_evidence,"exact-project-heading-in-main");
assert.equal(result.project_view_visible,false);
assert.equal(result.observation_ready,false);
assert.equal(result.submission_authorized,false);
assert.equal(result.project_identity_verified,false);
result=await inspect({badge:[],list:[{visible:true,selected:[]}],send:[],
  action:[{visible:true}],main:[],mainHeading:[]});
assert.equal(result.main_project_view_evidence,"no-main-region");
assert.equal(result.read_only_project_entry_ready,false);
// Actual screenshot: two main regions, central Project name and empty
// Project, visually scoped bar, but textbox remains generic "Ask ChatGPT".
// This corroborates the Project *landing page* only, not server identity.
result=await inspect({badge:[],main:[{visible:true},{visible:true}],
  mainProjectText:[{visible:true},{visible:true}],
  mainEmptyState:[{visible:true}],
  mainComposerVisualLabel:[{visible:true}],
  action:[{visible:true}],list:[{visible:true,selected:[]}],send:[]});
assert.equal(result.main_project_view_evidence,
  "main-region-ambiguous-or-unverified");
assert.equal(result.project_landing_visual_evidence,
  "project-empty-landing-corroborated");
assert.equal(result.project_composer_visual_label_observed,true);
assert.equal(result.project_view_visible,false);
assert.equal(result.read_only_project_entry_ready,false);
assert.equal(result.observation_ready,false);
assert.equal(result.submission_authorized,false);
assert.equal(result.project_identity_verified,false);
assert.equal(result.conversation_identity_verified,false);
assert.equal(result.durable_server_receipt_verified,false);
// Owner's exact 2026-10-15 probe: scoped empty Project composer and
// disabled Send, even though there are two main regions and the visual
// composer label is not separately found as a text node.
result=await inspect({
  composer:[{visible:true,disabled:false,draft:""}],
  scopedComposer:[{visible:true,disabled:false,draft:""}],
  genericComposer:[],
  badge:[{visible:true}],
  list:[{visible:true,selected:[]}],
  action:[{visible:true}],
  main:[{visible:true},{visible:true}],
  mainHeading:[{visible:true}],
  mainProjectText:[{visible:true},{visible:true}],
  mainEmptyState:[{visible:true}],
  mainComposerVisualLabel:[],
  send:[{visible:true,disabled:true}],
  stop:[]
});
assert.equal(result.main_project_view_evidence,
  "main-region-ambiguous-or-unverified");
assert.equal(result.project_landing_visual_evidence,
  "project-empty-landing-corroborated");
assert.equal(result.project_composer_visual_label_observed,false);
assert.equal(result.project_view_visible,true);
assert.equal(result.empty_project_composer_observed,true);
assert.equal(result.send_control_state,"disabled-on-empty-project-composer");
assert.equal(result.read_only_project_entry_ready,true);
assert.equal(result.observation_ready,false);
assert.deepEqual(result.readiness_issues,
  ["SEND_DISABLED_ON_EMPTY_PROJECT_COMPOSER"]);
assert.equal(result.project_identity_verified,false);
assert.equal(result.conversation_identity_verified,false);
assert.equal(result.durable_server_receipt_verified,false);
assert.equal(result.submission_authorized,false);
assert.equal(result.scheduler_activation_authorized,false);
assert.equal(result.supported_for_automated_tasks,false);
// A missing disabled state, a nonempty draft, a busy generation or
// duplicated visible Send buttons are not a quiet empty Project editor.
const base={badge:[{visible:true}],scopedComposer:[{visible:true}],
  genericComposer:[],list:[{visible:true,selected:[]}]};
result=await inspect({...base,send:[{visible:true,disabled:null}]});
assert.equal(result.read_only_project_entry_ready,false);
assert.ok(result.readiness_issues.includes("SEND_CONTROL_NOT_READY"));
result=await inspect({...base,
  composer:[{visible:true,disabled:false,draft:"ghp_FAKE_DRAFT"}],
  send:[{visible:true,disabled:true}]});
assert.equal(result.read_only_project_entry_ready,false);
assert.equal(result.observation_ready,false);
assert.ok(!JSON.stringify(result).includes("ghp_FAKE_DRAFT"));
result=await inspect({...base,stop:[{visible:true}],
  send:[{visible:true,disabled:true}]});
assert.equal(result.read_only_project_entry_ready,false);
result=await inspect({...base,
  send:[{visible:true,disabled:true},{visible:true,disabled:true}]});
assert.equal(result.read_only_project_entry_ready,false);
assert.ok(result.readiness_issues.includes("SEND_CONTROL_NOT_READY"));
// An unrelated empty-state string without the matching central Project
// name is not corroborated, even if sidebar remains visible.
result=await inspect({badge:[],main:[{visible:true},{visible:true}],
  mainProjectText:[],mainEmptyState:[{visible:true}],
  action:[{visible:true}],list:[{visible:true,selected:[]}],send:[]});
assert.equal(result.project_landing_visual_evidence,
  "empty-state-without-project-text-corroboration");
assert.equal(result.submission_authorized,false);
assert.equal(result.submission_authorized,false);
// A distinctly project-scoped blank composer may legitimately hide Send.
// This is only "read-only project entry ready"; managed sends stay blocked.
result=await inspect({badge:[],list:[{visible:true,selected:[]}],send:[],
  scopedComposer:[{visible:true,disabled:false,draft:""}]});
assert.equal(result.project_view_visible,true);
assert.equal(result.empty_project_composer_observed,true);
assert.equal(result.composer_scope_evidence,"exact-project-scoped-label");
assert.equal(result.read_only_project_entry_ready,true);
assert.equal(result.observation_ready,false);
assert.deepEqual(result.readiness_issues,
  ["SEND_ABSENT_ON_EMPTY_PROJECT_COMPOSER"]);
assert.equal(result.send_control_state,"absent-on-empty-project-composer");
assert.equal(result.project_identity_verified,false);
assert.equal(result.conversation_identity_verified,false);
assert.equal(result.submission_authorized,false);
assert.equal(result.scheduler_activation_authorized,false);
// A bare Project list + generic composer must not pass this new guard.
result=await inspect({badge:[],list:[{visible:true,selected:[]}],send:[],
  scopedComposer:[]});
assert.equal(result.read_only_project_entry_ready,false);
// Busy or non-empty project-scoped composer never qualifies.
result=await inspect({badge:[],list:[{visible:true,selected:[]}],send:[],
  scopedComposer:[{visible:true}],stop:[{visible:true}]});
assert.equal(result.read_only_project_entry_ready,false);
result=await inspect({badge:[],list:[{visible:true,selected:[]}],send:[],
  composer:[{visible:true,draft:"ghp_PRIVATE_DRAFT"}],
  scopedComposer:[{visible:true}]});
assert.equal(result.read_only_project_entry_ready,false);
assert.ok(!JSON.stringify(result).includes("ghp_PRIVATE_DRAFT"));
result=await inspect({badge:[],list:[{visible:true,selected:[]}],send:[],
  scopedComposer:[{visible:true},{visible:true}]});
assert.equal(result.read_only_project_entry_ready,false);
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
    "if(role==='main')return {...locator([{visible:true}]),",
    " getByRole:(kind,q)=>locator(process.env.MOCK_MAIN_PROJECT==='1'",
    " ?[{visible:true}]:[]),",
    " getByText:(label,opt)=>locator(process.env.MOCK_PROJECT_LANDING==='1'",
    " &&(label==='Automatic Alis'||label==='No chats yet'||",
    " label==='New chat in Automatic Alis')?[{visible:true}]:[])};",
    "if(role==='textbox'&&opt.name==='New chat in Automatic Alis')",
    " return locator(process.env.MOCK_BLANK_PROJECT==='1'",
    " ?[{visible:true,disabled:false}]:[]);",
    "if(role==='textbox'&&opt.name instanceof RegExp&&opt.name.test('Ask ChatGPT')",
    " &&!opt.name.test('New chat in Automatic Alis'))",
    " return locator(process.env.MOCK_BLANK_PROJECT==='1'",
    " ?[]:[{visible:true,disabled:false}]);",
    "if(role==='textbox')return locator([{visible:true,disabled:false}]);",
    "if(role==='list')return locator(process.env.MOCK_BLANK_PROJECT==='1'",
    " ||process.env.MOCK_PROJECT_LANDING==='1'",
    " ?[{visible:true,selected:[]}]:[]);",
    "if(role==='button'&&opt.name==='Send')",
    " return locator(process.env.MOCK_BLANK_PROJECT==='1'",
    " ?[]:[{visible:true}]);",
    "if(role==='button'&&opt.name instanceof RegExp&&opt.name.test('Stop'))return locator([]);",
    "if(role==='button'&&opt.name instanceof RegExp&&opt.name.test('New chat in Automatic Alis'))",
    " return locator(process.env.MOCK_SHOW_PROJECT_ACTION==='1'?[{visible:true}]:[]);",
    "return locator(process.env.MOCK_BLANK_PROJECT==='1'?[]:[{visible:true}]);}};",
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
  const blank=run(["probe"],{MOCK_BLANK_PROJECT:"1"});
  assert.equal(blank.status,0,blank.stderr);
  const blankReport=JSON.parse(blank.stdout);
  assert.equal(blankReport.read_only_project_entry_ready,true);
  assert.equal(blankReport.observation_ready,false);
  assert.deepEqual(blankReport.readiness_issues,
    ["SEND_ABSENT_ON_EMPTY_PROJECT_COMPOSER"]);
  assert.equal(blankReport.submission_authorized,false);
  assert.equal(blankReport.durable_server_receipt_verified,false);
  const withAction=run(["probe"],{MOCK_SHOW_PROJECT_ACTION:"1"});
  assert.equal(withAction.status,0);
  const actionReport=JSON.parse(withAction.stdout);
  assert.equal(actionReport.project_new_chat_action_visible,true);
  assert.equal(actionReport.main_project_view_evidence,
    "no-exact-project-heading-in-main");
  assert.equal(actionReport.submission_authorized,false);
  const mainProject=run(["probe"],{MOCK_MAIN_PROJECT:"1"});
  assert.equal(mainProject.status,0);
  const mainReport=JSON.parse(mainProject.stdout);
  assert.equal(mainReport.main_project_view_evidence,
    "exact-project-heading-in-main");
  assert.equal(mainReport.project_identity_verified,false);
  assert.equal(mainReport.submission_authorized,false);
  const landing=run(["probe"],{MOCK_PROJECT_LANDING:"1",
    MOCK_SHOW_PROJECT_ACTION:"1"});
  assert.equal(landing.status,0,landing.stderr);
  const landingReport=JSON.parse(landing.stdout);
  assert.equal(landingReport.project_landing_visual_evidence,
    "project-empty-landing-corroborated");
  assert.equal(landingReport.project_composer_visual_label_observed,true);
  assert.equal(landingReport.submission_authorized,false);
  assert.equal(landingReport.project_identity_verified,false);
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
