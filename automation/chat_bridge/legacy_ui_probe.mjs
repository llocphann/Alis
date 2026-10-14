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

export async function inspectLegacyUiReadOnly(page,projectName="Automatic Alis"){
  if(!PROJECT.test(projectName))throw Error("INVALID_PROJECT_NAME");
  if(page.url()!==MAIN_URL)throw Error("WRONG_RENDERER");
  const composerName=new RegExp("^(Ask ChatGPT|Do anything|New chat in "+
    escapeRegex(projectName)+")$");
  const composers=page.getByRole("textbox",{name:composerName});
  const projectBadge=page.getByRole("button",{
    name:new RegExp("^(Project:|Change project:) "+escapeRegex(projectName)+"$")
  });
  const projectLists=page.getByRole("list",{name:"Chats in "+projectName,exact:true});
  const sends=page.getByRole("button",{name:"Send",exact:true});
  const stops=page.getByRole("button",{name:/stop/i});
  const [composerCount,badgeCount,listCount,sendCount,stopCount]=await Promise.all([
    countVisible(composers),countVisible(projectBadge),countVisible(projectLists),
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
    const editor=composers.first();
    draftPresent=await safe(()=>editor.evaluate(el=>{
      // Only a boolean leaves Desktop; do not export existing draft text.
      return (el.textContent??"").length!==0;
    }));
    composerDisabled=await safe(()=>editor.isDisabled());
  }
  const sendDisabled=sendCount===1?await safe(()=>sends.first().isDisabled()):null;
  return {
    purpose:"legacy-ui-read-only-probe",
    renderer_matches:true,
    composer_count_capped:composerCount,
    project_badge_count_capped:badgeCount,
    target_project_list_count_capped:listCount,
    selected_target_chat_count_capped:selectedCount,
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
  const targetView=s.project_badge_count_capped===1 ||
    (s.target_project_list_count_capped===1 &&
     s.selected_target_chat_count_capped===1);
  if(!targetView)add("PROJECT_UI_GUARD_NOT_UNIQUE");
  if(s.stop_count_capped!==0)add("GENERATION_BUSY_OR_UNVERIFIED");
  if(s.composer_draft_present!==false)add("COMPOSER_NOT_EMPTY_OR_UNVERIFIED");
  if(s.composer_disabled!==false)add("COMPOSER_DISABLED_OR_UNVERIFIED");
  if(s.send_count_capped!==1||s.send_disabled!==false)
    add("SEND_CONTROL_NOT_READY");
  return {
    purpose:"legacy-ui-transport-assessment",
    observation_ready:issues.length===0,
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
