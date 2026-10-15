#!/usr/bin/env node
/* Read-only synthetic desktop identity evidence; no real account/CDP access. */
import assert from "node:assert/strict";
import {inspectUiSessionIdentity} from
  "../automation/chat_bridge/ui_session_diagnostics.mjs";

const SECRET_ID="1234567890abcdef1234567890abcdef";
let mutationCalls=0;
const forbid=()=>{mutationCalls++;throw Error("MOCK_MUTATION_FORBIDDEN");};
function makePage({listVisible=false,badgeVisible=false,scopedVisible=false,
  globalKeys=[],projectKeys=[],hrefInstead=false}={}){
  const keyItem=id=>({visible:true,id});
  const globalItems=globalKeys.map(keyItem);
  const projectItems=projectKeys.map(keyItem);
  const items=(source,kind="none")=>({
    count:async()=>source.length,
    nth:i=>items(source[i]?[source[i]]:[],kind),
    isVisible:async()=>source[0]?.visible??false,
    evaluate:async fn=>{
      const id=source[0]?.id;
      if(!id)return fn({
        getAttribute:()=>null,closest:()=>null,querySelector:()=>null
      });
      const link={
        getAttribute:attr=>attr==="href"&&hrefInstead?"/c/"+id:null
      };
      return fn({
        getAttribute:attr=>attr==="data-chat-id"&&!hrefInstead?id:null,
        closest:selector=>selector==="a[href]"&&hrefInstead?link:null,
        querySelector:()=>null
      });
    },
    locator:selector=>kind==="list"&&
      selector==='[role="button"][aria-current="page"]'
      ?items(projectItems,"selected"):items([]),
    click:forbid,fill:forbid,press:forbid
  });
  return {
    url:()=>"app://-/index.html",
    locator:selector=>selector==='[aria-current="page"]'
      ?items(globalItems,"global"):items([]),
    getByRole:(role,q={})=>{
      if(role==="list"&&q.name==="Chats in Automatic Alis")
        return items(listVisible?[{visible:true}]:[],"list");
      if(role==="textbox"&&q.name==="New chat in Automatic Alis")
        return items(scopedVisible?[{visible:true}]:[]);
      if(role==="button"&&q.name instanceof RegExp&&
        (q.name.test("Project: Automatic Alis")||
         q.name.test("Change project: Automatic Alis")))
        return items(badgeVisible?[{visible:true}]:[]);
      return items([]);
    }
  };
}
const noDelay=async()=>{};
const inspect=page=>inspectUiSessionIdentity(page,"Automatic Alis",{
  delay:noDelay
});
let r=await inspect(makePage({badgeVisible:true,globalKeys:[SECRET_ID]}));
assert.equal(r.diagnosis,"GLOBAL_SELECTED_CHAT_KEY_PROJECT_UNBOUND");
assert.equal(r.global_current_chat_with_key_count_capped,1);
assert.equal(r.project_sidebar_identity_evidence_present,false);
assert.equal(r.global_chat_key_evidence,"dom-conversation-attribute");
assert.equal(r.selected_chat_identity_stable,false);
assert.equal(r.ui_scheduler_authorized,false);
assert.equal(r.message_submission_attempted,false);
assert.equal(r.server_identity_attested,false);
assert.equal(r.queue_started,false);
assert.equal(r.accessibility_counts_stable,true);
assert.ok(!JSON.stringify(r).includes(SECRET_ID));
r=await inspect(makePage({listVisible:true,
  globalKeys:[SECRET_ID],projectKeys:[SECRET_ID],hrefInstead:true}));
assert.equal(r.diagnosis,"PROJECT_SIDEBAR_CHAT_KEY_OBSERVED");
assert.equal(r.project_sidebar_identity_evidence_present,true);
assert.equal(r.project_chat_key_evidence,"conversation-href");
assert.equal(r.selected_chat_identity_stable,false);
assert.ok(!JSON.stringify(r).includes("/c/"+SECRET_ID));
r=await inspect(makePage({badgeVisible:true,scopedVisible:true}));
assert.equal(r.diagnosis,"PROJECT_EDITOR_VISIBLE_CHAT_KEY_UNAVAILABLE");
assert.equal(r.project_sidebar_identity_evidence_present,false);
r=await inspect(makePage({globalKeys:[SECRET_ID,SECRET_ID]}));
assert.equal(r.diagnosis,"NO_UNAMBIGUOUS_UI_CHAT_KEY");
assert.equal(r.global_chat_key_evidence,"ambiguous");
r=await inspect(makePage({listVisible:true,projectKeys:[SECRET_ID,SECRET_ID],
  globalKeys:[SECRET_ID,SECRET_ID]}));
assert.equal(r.project_sidebar_identity_evidence_present,false);
assert.equal(r.project_chat_key_evidence,"ambiguous");
assert.equal(mutationCalls,0);
console.log("PASS AUTO-F01: post-smoke session probe categorical, no secrets, no sends, no scheduler authority");
