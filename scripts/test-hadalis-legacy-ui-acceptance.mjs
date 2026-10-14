#!/usr/bin/env node
/* Only synthetic page + durable-journal mocks. Never connects to Desktop. */
import assert from "node:assert/strict";
import {oneShotUiAcceptance} from
  "../automation/chat_bridge/legacy_ui_acceptance.mjs";
const id="11111111-1111-4111-8111-111111111111";
const events=[];
let disabled=false,draft="",busy=false,clickThrows=false,fillThrows=false;
function loc(items,kind){
  return {
    count:async()=>items.length,
    nth:i=>loc([items[i]],kind),
    first:()=>loc([items[0]],kind),
    isVisible:async()=>items[0]?.visible??false,
    isDisabled:async()=>items[0]?.disabled??false,
    evaluate:async fn=>{
      if(kind==="send"){
        events.push("click");
        if(clickThrows)throw Error("UNKNOWN_CLICK_OUTCOME");
        return fn({click:()=>{}}); // only one attempted click
      }
      return fn({textContent:items[0]?.draft??""});
    },
    fill:async value=>{
      events.push("fill");
      assert.match(value,/AUTO-F01 UI transport acceptance test only/);
      assert.ok(!value.includes("secret"));
      if(fillThrows)throw Error("UNKNOWN_COMPOSER_OUTCOME");
    },
    locator:()=>loc([{visible:true}],"selected")
  };
}
const page={
  url:()=> "app://-/index.html",
  getByRole:(role,options)=>{
    if(role==="textbox")return loc([{visible:true,disabled,draft}],"editor");
    if(role==="list")return loc([],"list");
    if(role==="button"&&options.name==="Send")
      return loc([{visible:true,disabled:false}],"send");
    if(role==="button"&&options.name instanceof RegExp &&
       options.name.test("Stop"))
      return loc(busy?[{visible:true}]:[],"stop");
    return loc([{visible:true}],"badge");
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
await assert.rejects(call(),/duplicate attempt must remain quarantined/);
assert.deepEqual(events,["durable-intent","fill","click"]);
events.length=0;
const fresh="22222222-2222-4222-8222-222222222222";
clickThrows=true;
r=await call({acceptanceId:fresh});
assert.equal(r.status,"indeterminate");
assert.equal(r.code,"UI_ATTEMPT_UNCERTAIN_NO_RETRY");
assert.deepEqual(events,["durable-intent","fill","click"]);
events.length=0;clickThrows=false;
fillThrows=true;
r=await call({acceptanceId:"33333333-3333-4333-8333-333333333333"});
assert.equal(r.status,"indeterminate");
assert.deepEqual(events,["durable-intent","fill"]);
events.length=0;fillThrows=false;
await assert.rejects(call({
  acceptanceId:"44444444-4444-4444-8444-444444444444",
  persistAttempt:async()=>{throw Error("DISK_FSYNC_FAILED")}
}),/DISK_FSYNC_FAILED/);
assert.deepEqual(events,[]);
// No output can attest a server accepted the test or that a project ID
// matches. This primitive is deliberately absent from the production CLI.
console.log("PASS AUTO-F01: owner acceptance one-shot writes intent first, never retries, stays unverified");
