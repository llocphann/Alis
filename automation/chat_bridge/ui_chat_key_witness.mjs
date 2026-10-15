/* AUTO-F01 local Desktop chat-key witness.
 * UI-only, read-only: compare raw ID values IN PROCESS, emit categories only.
 * Never treat a global selected chat, route, title, toolbar or turn key as
 * proof of ChatGPT Project membership or server-side identity.
 */
const PROJECT=/^[A-Za-z0-9 ._-]{1,80}$/;
const capped=n=>Math.min(3,n);
async function visible(locator){
  const n=await locator.count();
  if(!Number.isInteger(n)||n<0||n>100)
    throw Error("ALIS_UI_AMBIGUOUS_CONTROLS");
  const result=[];
  for(let i=0;i<n;i++){
    const item=locator.nth(i);
    if(await item.isVisible())result.push(item);
  }
  return result;
}
async function readChatKey(item){
  return await item.evaluate(el=>{
    const valid=/^[a-zA-Z0-9_-]{12,128}$/;
    for(const attr of ["data-conversation-id","data-chat-id"]){
      const raw=el.getAttribute(attr)||
        el.closest("["+attr+"]")?.getAttribute(attr);
      if(raw&&valid.test(raw))return raw;
    }
    const anchor=el.closest("a[href]")||el.querySelector("a[href]");
    const href=anchor?.getAttribute("href")??"";
    const match=href.match(/(?:^|\/)c\/([a-zA-Z0-9_-]{12,128})(?:$|[?#/])/);
    return match?.[1]??null;
  });
}
async function evidence(page,project){
  const lists=await visible(page.getByRole("list",{
    name:"Chats in "+project,exact:true
  }));
  const selectedProject=lists.length===1
    ?await visible(lists[0].locator(
      '[role="button"][aria-current="page"]'))
    :[];
  const global=await visible(page.locator('[aria-current="page"]'));
  async function validUnique(items){
    return items.length===1?await readChatKey(items[0]):null;
  }
  // Raw keys remain private in this lexical scope; never serialize them.
  const projectKey=await validUnique(selectedProject);
  const globalKey=await validUnique(global);
  return {
    projectKey,globalKey,
    projectListCount:capped(lists.length),
    projectSelectedCount:capped(selectedProject.length),
    globalSelectedCount:capped(global.length)
  };
}

export async function witnessUiChatKey(page,project="Automatic Alis",{
  delay=ms=>new Promise(resolve=>setTimeout(resolve,ms))
}={}){
  if(!PROJECT.test(project))throw Error("INVALID_PROJECT_NAME");
  if(page.url()!=="app://-/index.html")throw Error("WRONG_RENDERER");
  const first=await evidence(page,project);
  await delay(140);
  const second=await evidence(page,project);
  // Full raw equality, not mere equality of category/count fingerprints.
  // A different simultaneously selected global conversation cannot be
  // ignored just because a Project chat entry is stable in the sidebar.
  const globalConflicts=Boolean(first.globalKey&&
      first.globalKey!==first.projectKey) ||
    Boolean(second.globalKey&&second.globalKey!==second.projectKey);
  const projectStable=Boolean(first.projectKey)&&
    first.projectKey===second.projectKey &&
    first.projectSelectedCount===1&&second.projectSelectedCount===1 &&
    first.projectListCount===1&&second.projectListCount===1 &&
    first.globalSelectedCount<=1&&second.globalSelectedCount<=1 &&
    !globalConflicts;
  const globalStable=Boolean(first.globalKey)&&
    first.globalKey===second.globalKey &&
    first.globalSelectedCount===1&&second.globalSelectedCount===1;
  return {
    diagnosis:projectStable?"PROJECT_CHAT_KEY_STABLE_LOCAL_ONLY":
      globalStable?"GLOBAL_CHAT_KEY_STABLE_PROJECT_UNVERIFIED":
      "CHAT_KEY_MISSING_OR_CHANGED",
    project_list_count_capped:second.projectListCount,
    selected_project_chat_count_capped:second.projectSelectedCount,
    selected_global_item_count_capped:second.globalSelectedCount,
    project_chat_key_equal_across_samples:projectStable,
    global_chat_key_equal_across_samples:globalStable,
    // This bit explicitly distinguishes local UI continuity from the
    // ability to verify *server-side* Project/conversation membership.
    project_membership_server_attested:false,
    ui_scheduler_authorized:false
  };
}
