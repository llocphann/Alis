/* AUTO-F01: isolated, owner-approved harmless UI acceptance primitive.
 * NEVER imported from manager/native_cli; not usable for queued work.
 * No retries, no chat navigation, no credential access, no private APIs.
 * The journal MUST persist an immutable attempt BEFORE composer.fill/click.
 * A click error is indeterminate: never send the same acceptance ID again.
 */
import {inspectLegacyUiReadOnly,assessLegacyUiReadiness}
  from "./legacy_ui_probe.mjs";
const ID=/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const ACCEPTANCE_TEXT="AUTO-F01 UI transport acceptance test only. "+
  "Do not use any connectors or tools. Reply with exactly: HADALIS_LOOP:DONE";

export async function oneShotUiAcceptance({
  page,projectName="Automatic Alis",acceptanceId,
  ownerApproved=false,persistAttempt
}={}){
  if(ownerApproved!==true||!ID.test(acceptanceId)||
     typeof persistAttempt!=="function")
    return {status:"blocked",code:"OWNER_ACCEPTANCE_OR_DURABLE_JOURNAL_MISSING",
      submission_authorized:false};
  const inspection=await inspectLegacyUiReadOnly(page,projectName);
  const assessment=assessLegacyUiReadiness(inspection);
  // Only an empty, visibly corroborated new-chat landing in the exact
  // Project may enter the owner-only harmless acceptance. A disabled Send
  // button on that blank editor is EXPECTED. This is not Scheduler authority.
  const blankProjectPreflight=assessment.read_only_project_entry_ready===true &&
    assessment.empty_project_composer_observed===true &&
    inspection.project_scoped_composer_count_capped===1 &&
    inspection.project_badge_count_capped===1 &&
    inspection.target_project_list_count_capped===1 &&
    inspection.selected_target_chat_count_capped===0 &&
    assessment.project_landing_visual_evidence===
      "project-empty-landing-corroborated" &&
    inspection.send_count_capped===1 && inspection.send_disabled===true;
  if(!blankProjectPreflight)
    return {status:"blocked",code:"EMPTY_PROJECT_PREFLIGHT_NOT_READY",
      readiness_issues:assessment.readiness_issues,submission_authorized:false};
  // There is NO managed ChatGPT Project identity proof from these controls.
  // This function is only for a separately owner-approved harmless test.
  const editor=page.getByRole("textbox",{
    name:new RegExp("^(Ask ChatGPT|Do anything|New chat in "+
      projectName.replace(/[.*+?^$()|[\]{}\\]/g,"\\$&")+")$")
  });
  const send=page.getByRole("button",{name:"Send",exact:true});
  // The caller-supplied journal must fsync an immutable no-replay record and
  // reject IDs it has ever seen. No queue or prompt body is persisted here.
  // If a persist operation throws, NO UI mutation has occurred.
  await persistAttempt({
    id:acceptanceId,kind:"harmless-ui-acceptance",
    outcome:"indeterminate-once-attempted"
  });
  try {
    // Only one native semantic click. Unlike historical fallback chains,
    // never press Enter after an uncertain click.
    await editor.first().fill(ACCEPTANCE_TEXT);
    // Re-read the exact Project, editor and Send semantics AFTER filling.
    // If anything is ambiguous, leave the durable journal quarantined and
    // DO NOT click. Do not retry, press Enter or inspect message contents.
    const after=await inspectLegacyUiReadOnly(page,projectName);
    const projectStable=after.renderer_matches===true &&
      after.project_scoped_composer_count_capped===1 &&
      after.project_badge_count_capped===1 &&
      after.target_project_list_count_capped===1 &&
      after.selected_target_chat_count_capped===0 &&
      after.target_project_text_in_main_count_capped>=1 &&
      after.empty_project_state_in_main_count_capped===1 &&
      after.composer_count_capped===1 &&
      after.composer_draft_present===true &&
      after.composer_disabled===false &&
      after.stop_count_capped===0 &&
      after.send_count_capped===1 && after.send_disabled===false;
    if(!projectStable)
      return {status:"indeterminate",
        code:"POST_FILL_GUARD_FAILED_NO_SEND",
        acceptance_id_recorded:true,submission_authorized:false};
    // The categorical probe proves the draft is nonempty, NOT that it is
    // the harmless acceptance text. Do not risk clicking a user-owned or
    // externally replaced draft. Compare inside Desktop and return only a
    // boolean, never the actual draft or message contents.
    const exactHarmlessDraft=await editor.first().evaluate(
      (el,expected)=>el.textContent===expected,ACCEPTANCE_TEXT
    );
    if(exactHarmlessDraft!==true)
      return {status:"indeterminate",
        code:"HARMLESS_DRAFT_MISMATCH_NO_SEND",
        acceptance_id_recorded:true,submission_authorized:false};
    await send.first().evaluate(el=>el.click());
  }catch{
    return {status:"indeterminate",code:"UI_ATTEMPT_UNCERTAIN_NO_RETRY",
      acceptance_id_recorded:true,submission_authorized:false};
  }
  return {status:"indeterminate",code:"SINGLE_UI_CLICK_ISSUED_OBSERVE_ONLY",
    acceptance_id_recorded:true,submission_authorized:false};
}
