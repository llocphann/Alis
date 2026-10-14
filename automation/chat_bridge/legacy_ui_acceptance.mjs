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
  if(!assessment.observation_ready)
    return {status:"blocked",code:"UI_NOT_READY",
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
    await send.first().evaluate(el=>el.click());
  }catch{
    return {status:"indeterminate",code:"UI_ATTEMPT_UNCERTAIN_NO_RETRY",
      acceptance_id_recorded:true,submission_authorized:false};
  }
  return {status:"indeterminate",code:"SINGLE_UI_CLICK_ISSUED_OBSERVE_ONLY",
    acceptance_id_recorded:true,submission_authorized:false};
}
