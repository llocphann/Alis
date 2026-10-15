/* AUTO-F01: strictly read-only, redacted identity evidence after one-shot.
 * No DOM text, title, href, Project/conversation IDs, token or page URL emitted.
 * A global selected chat can be described diagnostically but never becomes
 * scheduler authority without an exact selected Project-list chat.
 */
const PROJECT=/^[A-Za-z0-9 ._-]{1,80}$/;
const bounded=n=>Math.min(3,Math.max(0,n));
async function visibleItems(locator){
  const n=await locator.count();
  if(!Number.isInteger(n)||n<0||n>100)throw Error("ALIS_UI_AMBIGUOUS_CONTROLS");
  const items=[];
  for(let i=0;i<n;i++){const x=locator.nth(i);if(await x.isVisible())items.push(x);}
  return items;
}
async function keyEvidence(selected){
  // Keep the raw key INSIDE the Desktop renderer. Only a source category
  // exits. A title, arbitrary href, Project button or turn-key is not a
  // durable conversation identity.
  return await selected.evaluate(node=>{
    const id=/^[a-zA-Z0-9_-]{12,128}$/;
    for(const field of ["data-conversation-id","data-chat-id"]){
      const raw=node.getAttribute(field)||
        node.closest("["+field+"]")?.getAttribute(field);
      if(raw&&id.test(raw))return "dom-conversation-attribute";
    }
    const link=node.closest("a[href]")||node.querySelector("a[href]");
    const href=link?.getAttribute("href")??"";
    if(/(?:^|\/)c\/[a-zA-Z0-9_-]{12,128}(?:$|[?#/])/.test(href))
      return "conversation-href";
    return "no-chat-key";
  });
}
async function sample(page,project){
  const list=await visibleItems(page.getByRole("list",{
    name:"Chats in "+project,exact:true
  }));
  const badge=await visibleItems(page.getByRole("button",{
    name:new RegExp("^(Project:|Change project:) "+
      project.replace(/[.*+?^$()|[\]{}\\]/g,"\\$&")+"$")
  }));
  const scoped=await visibleItems(page.getByRole("textbox",{
    name:"New chat in "+project,exact:true
  }));
  const global=await visibleItems(page.locator('[aria-current="page"]'));
  const projectSelected=list.length===1
    ?await visibleItems(list[0].locator('[role="button"][aria-current="page"]'))
    :[];
  const globalKeys=[];
  for(const item of global)globalKeys.push(await keyEvidence(item));
  const projectKeys=[];
  for(const item of projectSelected)projectKeys.push(await keyEvidence(item));
  const globalWithKey=globalKeys.filter(x=>x!=="no-chat-key");
  const projectWithKey=projectKeys.filter(x=>x!=="no-chat-key");
  return {
    project_list_count_capped:bounded(list.length),
    project_badge_count_capped:bounded(badge.length),
    exact_project_scoped_composer_count_capped:bounded(scoped.length),
    selected_project_chat_count_capped:bounded(projectSelected.length),
    selected_project_chat_with_key_count_capped:bounded(projectWithKey.length),
    global_current_item_count_capped:bounded(global.length),
    global_current_chat_with_key_count_capped:bounded(globalWithKey.length),
    global_chat_key_evidence:globalWithKey.length===1?globalWithKey[0]:
      globalWithKey.length>1?"ambiguous":"none",
    project_chat_key_evidence:projectWithKey.length===1?projectWithKey[0]:
      projectWithKey.length>1?"ambiguous":"none"
  };
}
export async function inspectUiSessionIdentity(page,project="Automatic Alis",{
  delay=ms=>new Promise(r=>setTimeout(r,ms))
}={}){
  if(!PROJECT.test(project))throw Error("INVALID_PROJECT_NAME");
  if(page.url()!=="app://-/index.html")throw Error("WRONG_RENDERER");
  const a=await sample(page,project);
  await delay(180);
  const b=await sample(page,project);
  const unchanged=JSON.stringify(a)===JSON.stringify(b);
  // No raw identifiers ever escape, so unchanged evidence is NOT proof that
  // two different conversations with similar DOM structures share an ID.
  // Do NOT claim selected_chat_identity_stable on this diagnostic alone.
  const projectBound=b.project_list_count_capped===1&&
    b.selected_project_chat_count_capped===1&&
    b.selected_project_chat_with_key_count_capped===1;
  const evidence=projectBound?"PROJECT_SIDEBAR_CHAT_KEY_OBSERVED":
    b.global_current_chat_with_key_count_capped===1
      ?"GLOBAL_SELECTED_CHAT_KEY_PROJECT_UNBOUND":
      b.exact_project_scoped_composer_count_capped===1&&
      b.project_badge_count_capped===1
        ?"PROJECT_EDITOR_VISIBLE_CHAT_KEY_UNAVAILABLE":
        "NO_UNAMBIGUOUS_UI_CHAT_KEY";
  return {
    purpose:"alis-ui-session-identity-diagnostics",
    status:"read-only",
    diagnosis:evidence,
    accessibility_counts_stable:unchanged,
    ...b,
    project_sidebar_identity_evidence_present:projectBound,
    selected_chat_identity_stable:false,
    server_identity_attested:false,
    message_submission_attempted:false,
    ui_scheduler_authorized:false,
    queue_started:false
  };
}
