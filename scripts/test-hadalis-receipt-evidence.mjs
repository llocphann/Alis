#!/usr/bin/env node
import assert from "node:assert/strict";
import {auditFinalTurnReceipt} from
 "../automation/chat_bridge/receipt_evidence.mjs";
const conversation_id="11111111-1111-4111-8111-111111111111";
const other_id="22222222-2222-4222-8222-222222222222";
const user_message_id="33333333-3333-4333-8333-333333333333";
const assistant_message_id="55555555-5555-4555-8555-555555555555";
const other_assistant_id="66666666-6666-4666-8666-666666666666";
const p={conversation_id,user_message_id,assistant_message_id};
const user=(id=user_message_id)=>({id,author:{role:"user"},
  status:"finished_successfully",end_turn:true,
  content:{parts:["ghp_PRIVATE_SNAPSHOT_TEST"]}});
const assistant=(id=assistant_message_id,status="finished_successfully",
  end_turn=true,recipient="all",channel="final")=>
 ({id,author:{role:"assistant"},recipient,channel,status,end_turn,
 content:{parts:["PRIVATE_FINAL_REPLY"]}});
const snapshot=()=>({
  conversation_id,current_node:"a",project_id:"PRIVATE_PROJECT",
  project_verified:true,submission_authorized:true,
  mapping:{
    u:{id:"u",parent:null,message:user()},
    a:{id:"a",parent:"u",message:assistant()}
  }
});
const check=(conversation,pending,code,finals=0)=>{
  const r=auditFinalTurnReceipt(conversation,pending);
  assert.equal(r.status,"blocked");
  assert.equal(r.submission_authorized,false);
  assert.equal(r.response_receipt_verified,false);
  assert.equal(r.project_membership_verified,false);
  assert.equal(r.receipt_shape_status,code);
  assert.equal(r.terminal_final_count_capped,finals);
  return r;
};
check(snapshot(),p,"ONE_TERMINAL_FINAL_SHAPE_NOT_ATTESTED",1);
check({...snapshot(),conversation_id:other_id},p,
  "CONVERSATION_IDENTITY_MISMATCH");
check(snapshot(),{...p,conversation_id:other_id},
  "CONVERSATION_IDENTITY_MISMATCH");
check(snapshot(),{user_message_id,conversation_id:null},
  "PENDING_IDENTITY_INVALID");
check(snapshot(),{...p,assistant_message_id:other_assistant_id},
  "ASSISTANT_RECEIPT_ID_MISMATCH",1);
check(snapshot(),{...p,assistant_message_id:undefined},
  "ONE_TERMINAL_FINAL_SHAPE_NOT_ATTESTED",1);
// The parent node's ID is not the user-message ID. Node IDs cannot certify
// authored message identity, even if an assistant follows the node.
const forged=snapshot();
forged.mapping.u.id=user_message_id;
forged.mapping.u.message=user(other_id);
check(forged,p,"TARGET_USER_TURN_MISSING");
const spoofRole=snapshot();
spoofRole.mapping.u.message.author.role="assistant";
check(spoofRole,p,"TARGET_MESSAGE_ROLE_MISMATCH");
const noEnd=snapshot();
noEnd.mapping.a.message.end_turn=false;
check(noEnd,p,"TARGET_FINAL_NOT_COMPLETE");
const inProgress=snapshot();
inProgress.mapping.a.message.status="in_progress";
check(inProgress,p,"TARGET_FINAL_NOT_COMPLETE");
const tool=snapshot();
tool.mapping.a.message.recipient="functions.exec";
check(tool,p,"TARGET_FINAL_NOT_COMPLETE");
const commentary=snapshot();
commentary.mapping.a.message.channel="commentary";
check(commentary,p,"TARGET_FINAL_NOT_COMPLETE");
const failed=snapshot();
failed.mapping.a.message.status="failed";
check(failed,p,"TERMINAL_FAILURE_NO_SUCCESSFUL_FINAL");
const unfinished=snapshot();
unfinished.mapping.a.message.status="error";
unfinished.mapping.a.message.end_turn=false;
check(unfinished,p,"TARGET_FINAL_NOT_COMPLETE");
// A final from the next user turn must not complete the pending turn.
const next=snapshot();
next.mapping.next={id:"next",parent:"u",message:user(other_id)};
next.mapping.later={id:"later",parent:"next",message:assistant()};
next.current_node="later";
check(next,p,"TARGET_TURN_SUPERSEDED");
const finishedBeforeNext=snapshot();
finishedBeforeNext.mapping.next={id:"next",parent:"a",message:user(other_id)};
finishedBeforeNext.mapping.later={id:"later",parent:"next",
  message:assistant(other_assistant_id)};
finishedBeforeNext.current_node="later";
assert.equal(check(finishedBeforeNext,p,
  "ONE_TERMINAL_FINAL_SHAPE_NOT_ATTESTED",1).subsequent_user_turn_present,true);
// Duplicate terminal responses on the same active chain fail closed.
const doubleFinal=snapshot();
doubleFinal.mapping.second={id:"second",parent:"a",
  message:assistant(other_assistant_id)};
doubleFinal.current_node="second";
check(doubleFinal,{...p,assistant_message_id:undefined},
  "MULTIPLE_TERMINAL_FINALS",2);
const duplicateUser=snapshot();
duplicateUser.mapping.extra={id:"extra",parent:"u",message:user()};
duplicateUser.mapping.a.parent="extra";
check(duplicateUser,p,"DUPLICATE_USER_MESSAGE_ON_BRANCH");
const missing=snapshot();
missing.mapping.u.parent="missing";
check(missing,p,"INVALID_OR_INCOMPLETE_BRANCH");
const cycle=snapshot();
cycle.mapping.u.parent="a";
check(cycle,p,"INVALID_OR_INCOMPLETE_BRANCH");
const noMapping=snapshot();
delete noMapping.mapping;
check(noMapping,p,"INVALID_OR_INCOMPLETE_BRANCH");
// Ignore non-user messages bearing matching IDs on disconnected branches.
const offBranch=snapshot();
offBranch.mapping.u.message=user(other_id);
offBranch.mapping.orphan={id:"orphan",parent:null,message:user()};
check(offBranch,p,"TARGET_USER_TURN_MISSING");
const spoof=snapshot();
spoof.receipt_verified=true;
spoof.native_transport_supported=true;
const output=JSON.stringify(check(spoof,p,
  "ONE_TERMINAL_FINAL_SHAPE_NOT_ATTESTED",1));
for(const item of [conversation_id,user_message_id,assistant_message_id,
  "ghp_PRIVATE_SNAPSHOT_TEST","PRIVATE_FINAL_REPLY","PRIVATE_PROJECT"]){
  assert.ok(!output.includes(item),"receipt report included private state");
}
console.log("PASS AUTO-F01: offline final-turn receipt identity audit stays fail closed");
