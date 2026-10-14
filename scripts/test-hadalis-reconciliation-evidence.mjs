#!/usr/bin/env node
import assert from "node:assert/strict";
import {auditReconciliationSnapshot} from
  "../automation/chat_bridge/reconciliation_evidence.mjs";

const chatA="11111111-1111-4111-8111-111111111111";
const chatB="22222222-2222-4222-8222-222222222222";
const msg="33333333-3333-4333-8333-333333333333";
const different="44444444-4444-4444-8444-444444444444";
const pending={user_message_id:msg};
const snapshot=(conversation_id,userMessage=msg)=>({
  conversation_id,current_node:"final",
  mapping:{
    user:{id:"user",parent:null,message:{
      id:userMessage,author:{role:"user"},content:{parts:["ghp_PRIVATE_TOKEN"]}}},
    final:{id:"final",parent:"user",message:{
      id:"response",author:{role:"assistant"},end_turn:true}}
  },project_id:"UNTRUSTED_PROJECT",project_verified:true,
  supported:true,submission_authorized:true
});
const check=(p,c,status,hits=0)=> {
  const result=auditReconciliationSnapshot(p,c);
  assert.equal(result.status,"blocked");
  assert.equal(result.submission_authorized,false);
  assert.equal(result.match_status,status);
  assert.equal(result.matched_conversation_count_capped,hits);
  assert.equal(result.project_membership_verified,false);
  assert.equal(result.external_source_authenticated,false);
  return result;
};
const found=check(pending,[snapshot(chatA)],
  "ONE_SYNTACTIC_ACTIVE_BRANCH_MATCH_NOT_ATTESTED",1);
assert.equal(found.conversation_identity_verified,false);
check(pending,[snapshot(chatA),snapshot(chatB)],
  "AMBIGUOUS_USER_MESSAGE",2);
check(pending,[snapshot(chatA),snapshot(chatA)],
  "DUPLICATE_CONVERSATION_IDENTITY",1);
check({...pending,conversation_id:chatB},[snapshot(chatA)],
  "CONFLICTS_WITH_PENDING_CONVERSATION",1);
check({...pending,conversation_id:chatA},[snapshot(chatA)],
  "ONE_SYNTACTIC_ACTIVE_BRANCH_MATCH_NOT_ATTESTED",1);
check(pending,[snapshot(chatA,different)],"NO_ACTIVE_BRANCH_MATCH");
check({user_message_id:"UNSAFE_INVALID_ID"},[snapshot(chatA)],
  "PENDING_IDENTITY_INVALID");
check(pending,[snapshot("bad-id")],"SNAPSHOT_UNVERIFIED");
check(pending,Array(17).fill(snapshot(chatA)),
  "CANDIDATE_SNAPSHOT_INVALID_OR_OVERSIZE");

// Off-active-branch messages must not be proof of dispatch identity.
const offBranch=snapshot(chatA,different);
offBranch.mapping.orphan={id:"orphan",parent:null,
  message:{id:msg,author:{role:"user"}}};
check(pending,[offBranch],"NO_ACTIVE_BRANCH_MATCH");

// Branch node IDs alone are not proof of authored user-message identity.
const nodeOnly=snapshot(chatA,different);
nodeOnly.mapping.user.id=msg;
check(pending,[nodeOnly],"NO_ACTIVE_BRANCH_MATCH");

// Assistant message with same ID cannot impersonate the submitted user turn.
const assistant=snapshot(chatA);
assistant.mapping.user.message.author.role="assistant";
check(pending,[assistant],"NO_ACTIVE_BRANCH_MATCH");

// Corrupt pointers/cycles fail closed, with no guessed branch traversal.
const broken=snapshot(chatA);
broken.mapping.final.parent="missing";
check(pending,[broken],"SNAPSHOT_UNVERIFIED");
const cyc=snapshot(chatA);
cyc.mapping.final.parent="final";
check(pending,[cyc],"SNAPSHOT_UNVERIFIED");

// Even a spoofed "verified" project or transport capability is ignored.
const malicious=snapshot(chatA);
malicious.authorized=true;
const output=JSON.stringify(check(pending,[malicious],
  "ONE_SYNTACTIC_ACTIVE_BRANCH_MATCH_NOT_ATTESTED",1));
for(const value of ["ghp_PRIVATE_TOKEN","UNTRUSTED_PROJECT",
  chatA,chatB,msg,"PRIVATE","response"]) {
  assert.equal(output.includes(value),false,"private payload in report");
}
console.log("PASS AUTO-F01: offline identity reconciliation rejects ambiguous, off-branch and spoofed evidence");
