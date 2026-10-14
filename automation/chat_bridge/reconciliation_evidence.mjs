/* AUTO-F01: deterministic, OFFLINE reconciliation evidence classifier.
 * No Desktop connection, account inspection, API, renderer or scheduler.
 * It never returns IDs, message text, project names or send authority.
 * A unique match in an untrusted snapshot cannot prove project membership.
 */
const UUID=/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const CAP=16;
const decision=(code,hits=0,invalid=false)=>({
  purpose:"offline-reconciliation-identity-audit",
  status:"blocked",
  match_status:code,
  matched_conversation_count_capped:Math.min(CAP,hits),
  candidate_snapshot_truncated:invalid,
  active_branch_only:true,
  external_source_authenticated:false,
  project_membership_verified:false,
  conversation_identity_verified:false,
  submission_authorized:false
});
function hasTargetOnCurrentBranch(c,id){
  const mapping=c?.mapping,current=c?.current_node;
  if(!mapping||typeof mapping!=="object"||Array.isArray(mapping)||
     typeof current!=="string")return null;
  let nodeId=current;
  const seen=new Set();
  let matchingUserMessages=0;
  for(let steps=0;nodeId!=null&&steps<1000;steps++){
    if(typeof nodeId!=="string"||seen.has(nodeId))return null;
    seen.add(nodeId);
    const node=Object.prototype.hasOwnProperty.call(mapping,nodeId)
      ? mapping[nodeId] : null;
    if(!node||typeof node!=="object")return null;
    if(node.message?.id===id&&node.message?.author?.role==="user") {
      matchingUserMessages++;
      if(matchingUserMessages>1)return "duplicate-user-message-on-branch";
    }
    nodeId=node.parent;
  }
  if(nodeId!=null)return null;
  return matchingUserMessages===1;
}
export function auditReconciliationSnapshot(pending,candidates){
  if(!UUID.test(pending?.user_message_id)||
    (pending.conversation_id!=null&&!UUID.test(pending.conversation_id))||
    (pending.project_id!=null&&typeof pending.project_id!=="string"))
    return decision("PENDING_IDENTITY_INVALID");
  if(!Array.isArray(candidates)||candidates.length>CAP)
    return decision("CANDIDATE_SNAPSHOT_INVALID_OR_OVERSIZE",0,true);
  let hits=0,duplicate=false,invalid=false,conflict=false,duplicateUser=false;
  const seen=new Set();
  for(const c of candidates){
    if(!UUID.test(c?.conversation_id)){invalid=true;continue;}
    if(seen.has(c.conversation_id)){duplicate=true;continue;}
    seen.add(c.conversation_id);
    const onBranch=hasTargetOnCurrentBranch(c,pending.user_message_id);
    if(onBranch===null){invalid=true;continue;}
    if(onBranch==="duplicate-user-message-on-branch"){
      duplicateUser=true;continue;
    }
    if(!onBranch)continue;
    hits++;
    if(pending.conversation_id&&pending.conversation_id!==c.conversation_id)
      conflict=true;
  }
  if(invalid)return decision("SNAPSHOT_UNVERIFIED",hits,true);
  if(duplicateUser)return decision("DUPLICATE_USER_MESSAGE_ON_BRANCH",hits);
  if(duplicate)return decision("DUPLICATE_CONVERSATION_IDENTITY",hits);
  if(hits>1)return decision("AMBIGUOUS_USER_MESSAGE",hits);
  if(conflict)return decision("CONFLICTS_WITH_PENDING_CONVERSATION",hits);
  if(hits===0)return decision("NO_ACTIVE_BRANCH_MATCH",0);
  // Even here the list's source and the containing ChatGPT Project have
  // not been authenticated. This is NEVER a transport-ready verdict.
  return decision("ONE_SYNTACTIC_ACTIVE_BRANCH_MATCH_NOT_ATTESTED",1);
}
