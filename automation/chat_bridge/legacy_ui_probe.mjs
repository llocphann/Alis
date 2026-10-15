/* AUTO-F01 legacy UI bridge — READ-ONLY first-stage adapter.
 * Reuses historical ChatGPT Desktop accessibility selectors, not private
 * React provider Maps/resolvers. Report categorical data only.
 * NO composer.fill, click, keyboard, focus or send operation.
 */
const MAIN_URL="app://-/index.html";
const PROJECT=/^[A-Za-z0-9 ._-]{1,80}$/;
const escapeRegex=s=>s.replace(/[.*+?^$()|[\]{}\\]/g,"\\$&");
const bounded=n=>Math.min(3,Math.max(0,Number.isInteger(n)?n:0));
const countVisible=async locator=>{
  const n=await locator.count();
  if(!Number.isInteger(n)||n>100)throw Error("AMBIGUOUS_UI_COUNT");
  let visible=0;
  for(let i=0;i<n;i++)if(await locator.nth(i).isVisible())visible++;
  return bounded(visible);
};
const safe=async fn=>{try{return await fn();}catch{return null;}};
// The unique VISIBLE role match may not be .first() when the Desktop keeps
// hidden old editors/buttons mounted. Never read state from a hidden clone.
const oneVisible=async locator=>{
  const n=await locator.count();
  if(!Number.isInteger(n)||n<1||n>100)return null;
  let match=null;
  for(let i=0;i<n;i++){
    const item=locator.nth(i);
    if(await item.isVisible()){
      if(match!==null)return null;
      match=item;
    }
  }
  return match;
};

export async function inspectLegacyUiReadOnly(page,projectName="Automatic Alis"){
  if(!PROJECT.test(projectName))throw Error("INVALID_PROJECT_NAME");
  if(page.url()!==MAIN_URL)throw Error("WRONG_RENDERER");
  const composerName=new RegExp("^(Ask ChatGPT|Do anything|New chat in "+
    escapeRegex(projectName)+")$");
  const composers=page.getByRole("textbox",{name:composerName});
  // An open project sidebar is not proof that the CURRENT composer targets
  // that Project. Query an exact, project-scoped composer label separately.
  // Do not read/emit its text or the selected conversation title.
  const projectScopedComposers=page.getByRole("textbox",{
    name:"New chat in "+projectName,exact:true
  });
  const genericComposers=page.getByRole("textbox",{
    name:/^(Ask ChatGPT|Do anything)$/
  });
  // The original Desktop controller used these semantic Project actions
  // for navigation. This probe only counts them; it never clicks.
  const projectNewChatActions=page.getByRole("button",{
    name:new RegExp("^(Start new chat in|New chat in) "+
      escapeRegex(projectName)+"$")
  });
  const projectBadge=page.getByRole("button",{
    name:new RegExp("^(Project:|Change project:) "+escapeRegex(projectName)+"$")
  });
  const projectLists=page.getByRole("list",{name:"Chats in "+projectName,exact:true});
  // Inspect the MAIN content region separately from persistent sidebar
  // navigation. A visible Project heading there can indicate that the
  // landing view has changed even when the composer retains a generic name.
  // Never read/return current heading text, chat title, URL or Project ID.
  const mainRegions=page.getByRole("main");
  const projectHeadingsInMain=mainRegions.getByRole("heading",{
    name:projectName,exact:true
  });
  // The current Desktop Project landing (owner screenshot) renders the
  // visible Project title as ordinary text, not necessarily an ARIA heading.
  // The composer displays its Project as adjacent text/chip while its
  // editable element keeps a generic accessible name.
  // Test fixed literal text only, output counts; never read raw DOM/text.
  const projectTextInMain=mainRegions.getByText(projectName,{exact:true});
  const emptyProjectStateInMain=mainRegions.getByText("No chats yet",{
    exact:true
  });
  const projectComposerLabelInMain=mainRegions.getByText(
    "New chat in "+projectName,{exact:true}
  );
  // A pending confirmation modal can intercept Project navigation. Count
  // dialogs without reading their contents, titles, buttons or draft text.
  const dialogs=page.getByRole("dialog");
  const sends=page.getByRole("button",{name:"Send",exact:true});
  const stops=page.getByRole("button",{name:/stop/i});
  const [composerCount,scopedComposerCount,genericComposerCount,
    projectNewChatActionCount,badgeCount,listCount,mainCount,
    mainProjectHeadingCount,mainProjectTextCount,mainEmptyStateCount,
    mainComposerVisualLabelCount,dialogCount,sendCount,stopCount]=await Promise.all([
      countVisible(composers),countVisible(projectScopedComposers),
      countVisible(genericComposers),countVisible(projectNewChatActions),
      countVisible(projectBadge),countVisible(projectLists),
      countVisible(mainRegions),countVisible(projectHeadingsInMain),
      countVisible(projectTextInMain),countVisible(emptyProjectStateInMain),
      countVisible(projectComposerLabelInMain),countVisible(dialogs),
      countVisible(sends),countVisible(stops)
    ]);
  let selectedCount=0;
  if(listCount===1){
    selectedCount=await countVisible(projectLists.locator(
      '[role="button"][aria-current="page"]'
    ));
  }
  let draftPresent=null;
  let composerDisabled=null;
  if(composerCount===1){
    const editor=await safe(()=>oneVisible(composers));
    if(editor){
      draftPresent=await safe(()=>editor.evaluate(el=>{
        // Only a boolean leaves Desktop; do not export existing draft text.
        return (el.textContent??"").length!==0;
      }));
      composerDisabled=await safe(()=>editor.isDisabled());
    }
  }
  const visibleSend=sendCount===1?await safe(()=>oneVisible(sends)):null;
  const sendDisabled=visibleSend?
    await safe(()=>visibleSend.isDisabled()):null;
  return {
    purpose:"legacy-ui-read-only-probe",
    renderer_matches:true,
    composer_count_capped:composerCount,
    project_scoped_composer_count_capped:scopedComposerCount,
    generic_composer_count_capped:genericComposerCount,
    project_new_chat_action_count_capped:projectNewChatActionCount,
    project_badge_count_capped:badgeCount,
    target_project_list_count_capped:listCount,
    selected_target_chat_count_capped:selectedCount,
    main_region_count_capped:mainCount,
    target_project_heading_in_main_count_capped:mainProjectHeadingCount,
    target_project_text_in_main_count_capped:mainProjectTextCount,
    empty_project_state_in_main_count_capped:mainEmptyStateCount,
    project_composer_visual_label_in_main_count_capped:
      mainComposerVisualLabelCount,
    dialog_count_capped:dialogCount,
    send_count_capped:sendCount,
    stop_count_capped:stopCount,
    composer_draft_present:draftPresent,
    composer_disabled:composerDisabled,
    send_disabled:sendDisabled
  };
}

export function assessLegacyUiReadiness(snapshot){
  const s=snapshot&&typeof snapshot==="object"?snapshot:{};
  const issues=[];
  const add=x=>{if(!issues.includes(x))issues.push(x);};
  if(s.renderer_matches!==true)add("DESKTOP_RENDERER_UNVERIFIED");
  if(s.composer_count_capped!==1)add("COMPOSER_NOT_UNIQUE");
  const scopedComposer=s.composer_count_capped===1 &&
    s.project_scoped_composer_count_capped===1;
  const selectedTargetChat=s.target_project_list_count_capped===1 &&
    s.selected_target_chat_count_capped===1;
  const targetView=s.project_badge_count_capped===1 ||
    selectedTargetChat || scopedComposer;
  if(!targetView)add("PROJECT_UI_GUARD_NOT_UNIQUE");
  // A blank "New chat in <Project>" editor may have no Send control until
  // text is entered. This is a meaningful *read-only* observation, never
  // proof of server-side Project identity or submission readiness.
  const emptyProjectComposer=scopedComposer &&
    s.selected_target_chat_count_capped===0 &&
    s.composer_draft_present===false &&
    s.stop_count_capped===0;
  if(s.stop_count_capped!==0)add("GENERATION_BUSY_OR_UNVERIFIED");
  if(Number.isInteger(s.dialog_count_capped) && s.dialog_count_capped!==0)
    add("MODAL_OPEN_OR_UNVERIFIED");
  if(s.composer_draft_present!==false)add("COMPOSER_NOT_EMPTY_OR_UNVERIFIED");
  if(s.composer_disabled!==false)add("COMPOSER_DISABLED_OR_UNVERIFIED");
  const absentOnBlankProjectComposer=emptyProjectComposer &&
    s.send_count_capped===0;
  // The current Desktop exposes exactly one disabled Send button when the
  // target Project's new-chat editor is empty. That is an idle UI state,
  // NOT a usable sending control and NOT a failure of CDP compatibility.
  const disabledOnBlankProjectComposer=emptyProjectComposer &&
    s.send_count_capped===1 && s.send_disabled===true;
  const unscopedBlankComposer=s.composer_count_capped===1 &&
    s.generic_composer_count_capped===1 &&
    s.project_scoped_composer_count_capped===0 &&
    !targetView && s.composer_draft_present===false &&
    s.stop_count_capped===0;
  const absentOnBlankUnscopedComposer=unscopedBlankComposer &&
    s.send_count_capped===0;
  if(s.send_count_capped!==1||s.send_disabled!==false)
    add(absentOnBlankProjectComposer
      ? "SEND_ABSENT_ON_EMPTY_PROJECT_COMPOSER"
      : disabledOnBlankProjectComposer
        ? "SEND_DISABLED_ON_EMPTY_PROJECT_COMPOSER"
      : absentOnBlankUnscopedComposer
        ? "SEND_ABSENT_ON_EMPTY_UNSCOPED_COMPOSER"
        : "SEND_CONTROL_NOT_READY");
  const readOnlyProjectEntryReady=emptyProjectComposer &&
    (absentOnBlankProjectComposer||disabledOnBlankProjectComposer) &&
    issues.length===1 &&
    (issues[0]==="SEND_ABSENT_ON_EMPTY_PROJECT_COMPOSER" ||
     issues[0]==="SEND_DISABLED_ON_EMPTY_PROJECT_COMPOSER");
  return {
    purpose:"legacy-ui-transport-assessment",
    observation_ready:issues.length===0,
    read_only_project_entry_ready:readOnlyProjectEntryReady,
    empty_project_composer_observed:emptyProjectComposer,
    project_landing_visual_evidence:
      s.target_project_list_count_capped===1 &&
      s.target_project_text_in_main_count_capped>=1 &&
      s.empty_project_state_in_main_count_capped===1
        ? "project-empty-landing-corroborated"
        : s.empty_project_state_in_main_count_capped===1
          ? "empty-state-without-project-text-corroboration"
          : "not-corroborated",
    // Screenshot has a visually project-labelled composer while the
    // editable textbox may still expose generic ARIA name "Ask ChatGPT".
    // This is only read-only presentation evidence, never an identity
    // proof or permission to send/observe as a managed task.
    project_composer_visual_label_observed:
      s.project_composer_visual_label_in_main_count_capped>=1,
    main_project_view_evidence:
      s.main_region_count_capped===1 &&
      s.target_project_heading_in_main_count_capped===1
        ? "exact-project-heading-in-main"
        : s.main_region_count_capped===0
          ? "no-main-region" : s.main_region_count_capped===1
            ? "no-exact-project-heading-in-main"
            : "main-region-ambiguous-or-unverified",
    // Main-region headings only corroborate visual navigation. Never use
    // them to set project_view_visible, observation_ready or send authority.
    composer_scope_evidence:scopedComposer
      ? "exact-project-scoped-label"
      : unscopedBlankComposer ? "generic-label-without-project-guard"
        : s.generic_composer_count_capped===1 &&
          s.project_scoped_composer_count_capped===0
          ? "generic-label-with-other-or-unverified-guard"
          : "unknown-or-ambiguous",
    project_new_chat_action_visible:
      s.project_new_chat_action_count_capped===1,
    send_control_state:absentOnBlankProjectComposer
      ? "absent-on-empty-project-composer"
      : disabledOnBlankProjectComposer
        ? "disabled-on-empty-project-composer"
      : absentOnBlankUnscopedComposer
        ? "absent-on-empty-unscoped-composer"
        : s.send_count_capped===1 && s.send_disabled===false
          ? "visible-enabled" : "missing-disabled-or-ambiguous",
    readiness_issues:issues,
    transport_mode:"legacy-cdp-ui",
    project_view_visible:targetView,
    project_identity_verified:false,
    conversation_identity_verified:false,
    durable_server_receipt_verified:false,
    native_resolver_invoked:false,
    // UI guard NEVER authorizes a managed send; owner-accepted transport
    // requires a separate durable one-shot dispatch protocol.
    submission_authorized:false,
    scheduler_activation_authorized:false,
    supported_for_automated_tasks:false
  };
}
