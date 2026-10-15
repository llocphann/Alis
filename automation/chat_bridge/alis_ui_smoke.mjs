/* AUTO-F01: one owner-approved Desktop smoke test, never a queue transport.
 * One Project navigation (when needed), one immutable journaled harmless Send,
 * a bounded assistant-only response check and a local selected-chat ID check.
 * This module has no task/credential/worker imports. No retries or fallback.
 */
import {inspectLegacyUiReadOnly,assessLegacyUiReadiness} from "./legacy_ui_probe.mjs";
import {oneShotUiAcceptance} from "./legacy_ui_acceptance.mjs";
import {extractLoopResponse,uiTargetIdentity} from "./desktop_driver.mjs";

// Stable across invocations. The journal rejects another send even if the
// operator repeats the command after a timeout or ambiguous UI result.
export {SMOKE_ACCEPTANCE_ID} from "./alis_ui_smoke_id.mjs";
import {SMOKE_ACCEPTANCE_ID} from "./alis_ui_smoke_id.mjs";
const RESPONSE_ACTION=/regenerate|retry|try again|copy/i;
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));

async function visibleCount(locator){
  const n=await locator.count();
  if(!Number.isInteger(n)||n<0||n>100)throw Error("ALIS_UI_AMBIGUOUS_CONTROLS");
  let count=0;
  for(let i=0;i<n;i++)if(await locator.nth(i).isVisible())count++;
  return count;
}
const report=(code,extra={})=>({
  purpose:"alis-ui-one-shot-smoke",
  status:"blocked",
  code,
  navigation_click_attempted:false,
  message_send_click_attempted:false,
  journal_recorded:false,
  assistant_only_reply_observed:false,
  selected_chat_identity_stable:false,
  message_submission_verified:false,
  server_identity_attested:false,
  ui_scheduler_authorized:false,
  queue_started:false,
  ...extra
});
async function exactNavigationAction(page,projectName){
  const names=["Start new chat in "+projectName,"New chat in "+projectName];
  const matches=[];
  for(const name of names){
    const loc=page.getByRole("button",{name,exact:true});
    if(await loc.count()>1)return null;
    if(await loc.count()===1&&await loc.isVisible())matches.push(loc);
  }
  return matches.length===1&&!(await matches[0].isDisabled())?matches[0]:null;
}
async function scopedEntry(page,projectName){
  const observation=await inspectLegacyUiReadOnly(page,projectName);
  const assessment=assessLegacyUiReadiness(observation);
  return {observation,assessment,ready:assessment.read_only_project_entry_ready===true &&
    observation.project_badge_count_capped===1 &&
    // ChatGPT can collapse the Project's Chats list on a new-chat landing.
    // The exact scoped textbox + exact Project badge are BOTH required;
    // list absence is never treated as proof of Project membership alone.
    [0,1].includes(observation.target_project_list_count_capped) &&
    observation.selected_target_chat_count_capped===0 &&
    observation.project_scoped_composer_count_capped===1 &&
    observation.send_count_capped===1 &&
    observation.send_disabled===true &&
    observation.dialog_count_capped===0};
}

// Only bounded accessibility counts, enums and booleans, never URL, ID,
// title, draft text, screenshot, message body or raw DOM. Include the reason
// *after* one navigation click so an owner can diagnose without 3 commands.
function safeEntryDiagnostics(entry){
  if(!entry)return {inspection:"unavailable"};
  const s=entry.observation,a=entry.assessment;
  return {
    inspection:"completed",
    project_list_count_capped:s.target_project_list_count_capped,
    project_badge_count_capped:s.project_badge_count_capped,
    selected_chat_count_capped:s.selected_target_chat_count_capped,
    composer_count_capped:s.composer_count_capped,
    project_scoped_composer_count_capped:s.project_scoped_composer_count_capped,
    composer_scope_evidence:a.composer_scope_evidence,
    project_landing_visual_evidence:a.project_landing_visual_evidence,
    draft_present:s.composer_draft_present,
    dialog_count_capped:s.dialog_count_capped,
    composer_disabled:s.composer_disabled,
    generation_busy:s.stop_count_capped!==0,
    send_control_state:a.send_control_state,
    readiness_issues:a.readiness_issues
  };
}

export async function oneShotUiSmoke({page,projectName="Automatic Alis",
  persistAttempt,ownerApproved=false,wait=sleep,maxResponsePolls=36,
  maxNavigationPolls=18}={}){
  if(ownerApproved!==true||typeof persistAttempt!=="function")
    return report("EXPLICIT_APPROVAL_AND_JOURNAL_REQUIRED");
  let before;
  try{before=await scopedEntry(page,projectName);}
  catch{return report("ALIS_UI_PREFLIGHT_UNAVAILABLE");}
  let navigated=false;
  if(!before.ready){
    const s=before.observation;
    // Navigation is allowed away from a *foreign draft* without erasing it,
    // but never from a busy generation or ambiguous Project/sidebar.
    // A Project navigation button is usable even when the user's current
    // chat belongs to another Project: ChatGPT hides the target Project's
    // chat list in that view. We never treat the button as submission proof.
    // Require one uniquely named navigation control and re-verify the
    // exact Project badge/list/scoped EMPTY editor after navigating.
    const blockers=[];
    if(![0,1].includes(s.target_project_list_count_capped))
      blockers.push("TARGET_PROJECT_LIST_AMBIGUOUS");
    if(s.project_new_chat_action_count_capped!==1)
      blockers.push("PROJECT_NEW_CHAT_ACTION_NOT_UNIQUE");
    if(s.selected_target_chat_count_capped!==0)
      blockers.push("TARGET_CHAT_ALREADY_SELECTED");
    if(s.composer_count_capped!==1||s.composer_disabled!==false)
      blockers.push("ACTIVE_COMPOSER_NOT_UNIQUE_OR_DISABLED");
    if(s.stop_count_capped!==0)
      blockers.push("GENERATION_ACTIVE");
    if(s.dialog_count_capped!==0)
      blockers.push("MODAL_ALREADY_OPEN");
    if(blockers.length)
      return report("ALIS_UI_NAVIGATION_UNSAFE",{
        navigation_blockers:blockers
      });
    const action=await exactNavigationAction(page,projectName);
    if(!action)return report("ALIS_UI_PROJECT_NEW_CHAT_ACTION_AMBIGUOUS");
    navigated=true;
    try{await action.evaluate(button=>button.click());}
    catch{return report("ALIS_UI_NAVIGATION_UNCERTAIN_NO_RETRY",{
      status:"uncertain",navigation_click_attempted:true});}
    // Allow an async Desktop route transition (up to ~3.2 seconds).
    // Require two consecutive verified states before touching the editor;
    // one transient Project badge is never proof of the final destination.
    // Never click again, even if the navigation remains unverified.
    let stableReadiness=0;
    for(let i=0;i<maxNavigationPolls;i++){
      await wait(180);
      try{
        before=await scopedEntry(page,projectName);
        stableReadiness=before.ready?stableReadiness+1:0;
      }catch{
        stableReadiness=0;
      }
      if(stableReadiness>=2)break;
    }
    if(stableReadiness<2)return report("ALIS_UI_PROJECT_NAVIGATION_NOT_VERIFIED",{
      status:"unverified",navigation_click_attempted:true,
      post_navigation_diagnostics:safeEntryDiagnostics(before)});
  }

  let baseline;
  try{baseline=await visibleCount(page.getByRole("button",{
    name:RESPONSE_ACTION
  }));}
  catch{return report("ALIS_UI_RESPONSE_BASELINE_UNAVAILABLE",{
    navigation_click_attempted:navigated});}

  let result;
  try{
    result=await oneShotUiAcceptance({
      page,projectName,acceptanceId:SMOKE_ACCEPTANCE_ID,
      ownerApproved:true,persistAttempt
    });
  }catch{
    // A persisted ID, even if its IO status is unknown, must never be
    // reused or replaced by a new ID to force the test.
    return report("ALIS_UI_SMOKE_JOURNAL_OR_ATTEMPT_UNAVAILABLE_NO_RETRY",{
      status:"uncertain",navigation_click_attempted:navigated});
  }
  if(result.code!=="SINGLE_UI_CLICK_ISSUED_OBSERVE_ONLY")
    return report(result.code??"ALIS_UI_SMOKE_BLOCKED",{
      status:result.status,
      navigation_click_attempted:navigated,
      journal_recorded:result.acceptance_id_recorded===true
    });
  const sent=report("ALIS_UI_SMOKE_REPLY_PENDING_NO_RETRY",{
    status:"sent_unverified",
    navigation_click_attempted:navigated,
    message_send_click_attempted:true,
    journal_recorded:true
  });
  // The user's prompt itself contains ALIS_LOOP:DONE. Never count it as the
  // assistant's reply. Require a NEW assistant-owned response toolbar/turn
  // and the strict expected canonical directive.
  let replied=false;
  for(let i=0;i<maxResponsePolls;i++){
    try{
      const response=await extractLoopResponse(page,{
        baselineResponseActionCount:baseline
      });
      if(response.extractionSignal==="assistant-turn"&&
         response.markerCount===1&&response.text.trim()==="ALIS_LOOP:DONE")
        replied=true;
    }catch{}
    if(replied){
      try{
        const first=await uiTargetIdentity(page);
        await wait(130);
        const second=await uiTargetIdentity(page);
        if(first===second)return {
          ...sent,status:"observed",code:"ALIS_UI_SMOKE_ASSISTANT_AND_CHAT_OBSERVED",
          assistant_only_reply_observed:true,
          selected_chat_identity_stable:true
        };
      }catch{}
    }
    await wait(250);
  }
  return {
    ...sent,code:replied
      ?"ALIS_UI_SMOKE_REPLY_OBSERVED_CHAT_ID_UNAVAILABLE"
      :"ALIS_UI_SMOKE_REPLY_PENDING_NO_RETRY",
    assistant_only_reply_observed:replied
  };
}
