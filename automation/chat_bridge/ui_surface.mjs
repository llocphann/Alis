/* A browser target identifies an owned UI window, never a ChatGPT chat. */
export const MAIN_URL="app://-/index.html";
export function checkedUiWindowTarget(value) {
  if(typeof value!=="string" || !/^[0-9a-f]{32}$/i.test(value))
    throw Error("ALIS_UI_WINDOW_TARGET_INVALID");
  return value;
}
export async function pinnedUiWindow(browser,target) {
  checkedUiWindowTarget(target);
  const pages=browser.contexts().flatMap(c=>c.pages()).filter(p=>p.url()===MAIN_URL);
  if(pages.length>8)throw Error("ALIS_UI_WINDOW_COUNT_EXCEEDED");
  const matches=[];
  for(const page of pages) {
    const session=await page.context().newCDPSession(page);
    try {
      const result=await session.send("Target.getTargetInfo");
      if(result?.targetInfo?.targetId===target)matches.push(page);
    } finally {await session.detach();}
  }
  if(matches.length!==1)throw Error("ALIS_UI_OWNED_WINDOW_UNAVAILABLE");
  return matches[0];
}
