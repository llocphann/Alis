/* AUTO-F01: offline final-turn receipt evidence, never a send capability.
 * Only validates bounded snapshot syntax. A valid-looking snapshot from an
 * unauthenticated source cannot verify project membership or receipt origin.
 * No message bodies, node IDs or conversation/project IDs leave this module.
 */
const UUID=/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const LIMIT=1000;
const result=(status, finals=0,next=false)=>({
  purpose:"offline-final-turn-receipt-audit",
  status:"blocked",
  receipt_shape_status:status,
  terminal_final_count_capped:Math.min(4,finals),
  subsequent_user_turn_present:next,
  active_branch_complete:status!=="INVALID_OR_INCOMPLETE_BRANCH",
  snapshot_origin_verified:false,
  project_membership_verified:false,
  conversation_identity_verified:false,
  response_receipt_verified:false,
  submission_authorized:false
});
export function auditFinalTurnReceipt(conversation,pending){
  if(!UUID.test(pending?.user_message_id) ||
     !UUID.test(pending?.conversation_id) ||
     (pending.assistant_message_id!=null &&
      !UUID.test(pending.assistant_message_id)))
    return result("PENDING_IDENTITY_INVALID");
  if(conversation?.conversation_id!==pending.conversation_id)
    return result("CONVERSATION_IDENTITY_MISMATCH");
  const mapping=conversation?.mapping;
  if(!mapping||typeof mapping!=="object"||Array.isArray(mapping)||
     typeof conversation.current_node!=="string")
    return result("INVALID_OR_INCOMPLETE_BRANCH");
  const chain=[],seen=new Set();
  let id=conversation.current_node;
  while(id!=null && chain.length<LIMIT){
    if(typeof id!=="string"||seen.has(id) ||
       !Object.prototype.hasOwnProperty.call(mapping,id))
      return result("INVALID_OR_INCOMPLETE_BRANCH");
    seen.add(id);
    const node=mapping[id];
    if(!node||typeof node!=="object")
      return result("INVALID_OR_INCOMPLETE_BRANCH");
    chain.push(node);
    id=node.parent;
  }
  if(id!=null || chain.length===0)
    return result("INVALID_OR_INCOMPLETE_BRANCH");
  chain.reverse();
  const matching=[];
  for(let i=0;i<chain.length;i++){
    const message=chain[i].message;
    if(message?.id!==pending.user_message_id)continue;
    if(message.author?.role!=="user")
      return result("TARGET_MESSAGE_ROLE_MISMATCH");
    matching.push(i);
  }
  if(matching.length>1)return result("DUPLICATE_USER_MESSAGE_ON_BRANCH");
  if(matching.length===0)return result("TARGET_USER_TURN_MISSING");
  let finals=0,matchedAssistant=false,nextUser=false,failedTerminal=false;
  for(const node of chain.slice(matching[0]+1)){
    const m=node.message;
    if(m?.author?.role==="user"){nextUser=true;break;}
    if(m?.author?.role!=="assistant")continue;
    if(["failed","error","cancelled"].includes(m.status) &&
       m.end_turn===true)failedTerminal=true;
    if(m.recipient!=="all" ||
       (m.channel!=null && m.channel!=="final") ||
       m.status!=="finished_successfully" || m.end_turn!==true)continue;
    finals++;
    if(m.id===pending.assistant_message_id)matchedAssistant=true;
  }
  if(finals>1)return result("MULTIPLE_TERMINAL_FINALS",finals,nextUser);
  if(finals===0)return result(failedTerminal
    ? "TERMINAL_FAILURE_NO_SUCCESSFUL_FINAL" :
      nextUser?"TARGET_TURN_SUPERSEDED":"TARGET_FINAL_NOT_COMPLETE",
    0,nextUser);
  if(pending.assistant_message_id!=null&&!matchedAssistant)
    return result("ASSISTANT_RECEIPT_ID_MISMATCH",finals,nextUser);
  // Status is deliberately not "verified": snapshots aren't authenticated.
  return result("ONE_TERMINAL_FINAL_SHAPE_NOT_ATTESTED",finals,nextUser);
}
