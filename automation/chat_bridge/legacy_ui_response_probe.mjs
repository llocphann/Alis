/* AUTO-F01: post-send UI observation ONLY. No message submission, no
 * private HTTP endpoints, DOM internals, navigation or message extraction.
 * Fixed public acceptance strings are queried by equality; raw chat text,
 * tokens, Project/conversation/message IDs and titles are NEVER returned.
 *
 * This CANNOT attest server-side identity or turn completion. A visible pair
 * is a useful smoke observation, not an accepted manager receipt.
 */
import {inspectLegacyUiReadOnly} from "./legacy_ui_probe.mjs";
const ACCEPTANCE_TEXT="AUTO-F01 UI transport acceptance test only. "+
  "Do not use any connectors or tools. Reply with exactly: HADALIS_LOOP:DONE";
const EXPECTED_REPLY="HADALIS_LOOP:DONE";

const visibleCount=async locator=>{
  const total=await locator.count();
  if(!Number.isInteger(total)||total<0||total>100)
    throw Error("AMBIGUOUS_UI_COUNT");
  let count=0;
  for(let i=0;i<total;i++)
    if(await locator.nth(i).isVisible())count++;
  return Math.min(3,count);
};
export async function observeHarmlessUiResponse(page,projectName="Automatic Alis"){
  // Reuse renderer, project-name and bounded-read-only checks from preflight;
  // a chat after Send is not an empty Project landing. Do not require an
  // empty composer, disabled Send or even a selected Project conversation.
  const snapshot=await inspectLegacyUiReadOnly(page,projectName);
  const [requestCount,replyCount]=await Promise.all([
    visibleCount(page.getByText(ACCEPTANCE_TEXT,{exact:true})),
    visibleCount(page.getByText(EXPECTED_REPLY,{exact:true}))
  ]);
  const visualContext=snapshot.renderer_matches===true &&
    (snapshot.project_badge_count_capped===1 ||
     snapshot.project_scoped_composer_count_capped===1 ||
     snapshot.selected_target_chat_count_capped===1);
  const pairUnique=requestCount===1 && replyCount===1;
  return {
    purpose:"legacy-ui-harmless-response-observation",
    status:"read-only",
    visual_pair_status:pairUnique&&visualContext
      ?"ONE_VISIBLE_HARMLESS_PAIR_NOT_ATTESTED":
      pairUnique?"HARMLESS_PAIR_VISIBLE_PROJECT_CONTEXT_UNVERIFIED":
      requestCount>1||replyCount>1?"AMBIGUOUS_VISIBLE_HARMLESS_MESSAGES":
      "HARMLESS_PAIR_NOT_VISIBLE_OR_INCOMPLETE",
    request_visible_count_capped:requestCount,
    reply_visible_count_capped:replyCount,
    visual_project_guard_observed:visualContext,
    server_project_membership_verified:false,
    server_conversation_identity_verified:false,
    server_user_message_identity_verified:false,
    final_receipt_verified:false,
    submission_authorized:false,
    scheduler_activation_authorized:false,
    supported_for_automated_tasks:false
  };
}
