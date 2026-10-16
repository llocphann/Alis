import { spawnSync } from "node:child_process";
import {requireFreshAssistantTurn} from "./ui_response_gate.mjs";
import {pinnedUiWindow} from "./ui_surface.mjs";
import {createHash,randomUUID} from "node:crypto";
import {uiAnchorSource,matchingSubmittedUnit,submittedPromptMatches} from "./ui_turn_anchor.mjs";
import {virtualizedRecoveryEligible,validateVirtualizedHistory} from "./ui_history_witness.mjs";

const PLAYWRIGHT = process.env.ALIS_PLAYWRIGHT_MODULE ?? process.env.HADALIS_PLAYWRIGHT_MODULE ?? "file:///usr/lib/chatgpt/resources/cua_node/lib/node_modules/playwright-core/index.mjs";
const { chromium } = await import(PLAYWRIGHT);

const CDP = process.env.ALIS_CHATGPT_CDP_URL ?? process.env.HADALIS_CHATGPT_CDP_URL ?? "http://127.0.0.1:9222";
const MAIN_URL = "app://-/index.html";
const PROJECT_NAME = process.env.ALIS_CHATGPT_PROJECT ?? process.env.HADALIS_CHATGPT_PROJECT ?? "Automatic Alis";
if (!/^[A-Za-z0-9 ._-]{1,80}$/.test(PROJECT_NAME))
  throw new Error("invalid configured ChatGPT project name");
const escapedProject = PROJECT_NAME.replaceAll(".", "\\.");
const COMPOSER = new RegExp(`^(Ask ChatGPT|Do anything|New chat in ${escapedProject})$`);
const ANY_COMPOSER = /^(Ask ChatGPT|Do anything|New chat in .+)$/;
const PROJECT = new RegExp(`^(Project:|Change project:) ${escapedProject}$`);
const GITHUB_MENTION = "[@GitHub](plugin://github@openai-curated-remote)";
const GITHUB_APP_MENTION = "[$github](app://connector_76869538009648d5b282a4bb21c3d157)";
const LOOP_MARKER = /^(?:ALIS|HADALIS)_LOOP:(?:WAIT_RESULT|CONTINUE|ROTATE|DONE|CONNECTOR_BLOCKED)(?:[ \\t]+[A-Za-z0-9._/-]+)?[ \\t]*$/m;
const RESPONSE_ACTION = /regenerate|retry|try again|copy/i;
const STREAM_ERROR = /error in message stream|there was an error generating a response/i;

export function scanLoopMarkerTokens(text) {
  const token = /(?:ALIS|HADALIS)_LOOP:(?:CONTINUE|ROTATE|DONE)\b|(?:ALIS|HADALIS)_LOOP:WAIT_RESULT[ \\t]+JOB-[A-Za-z0-9._-]+|(?:ALIS|HADALIS)_LOOP:CONNECTOR_BLOCKED[ \\t]+GITHUB\b/g;
  return Array.from(String(text).matchAll(token), match => match[0].trim());
}

export function markerAfterBaseline(markers, baselineMarkerCount) {
  if (!Number.isInteger(baselineMarkerCount) || baselineMarkerCount < 0)
    throw new Error("baselineMarkerCount must be a non-negative integer");

  const fresh = markers.slice(baselineMarkerCount);
  if (fresh.length === 0)
    return null;
  if (fresh.length !== 1)
    throw new Error(
      `expected exactly one post-submit ALIS_LOOP marker, got ${fresh.length}: ${JSON.stringify(fresh)}`
    );
  return fresh[0];
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function visibleCount(locator) {
  const count = await locator.count();
  let visible = 0;
  for (let i = 0; i < count; i += 1) {
    try {
      if (await locator.nth(i).isVisible()) visible += 1;
    } catch {}
  }
  return visible;
}

async function requireOne(locator, label) {
  const count = await locator.count();
  const visible = await visibleCount(locator);
  if (count !== 1 || visible !== 1)
    throw new Error(`${label}: expected one visible element, got count=${count}, visible=${visible}`);
  return locator;
}

async function semanticClick(locator, label) {
  await requireOne(locator, label);
  if (await locator.isDisabled()) throw new Error(`${label} is disabled`);
  await locator.evaluate(el => el.click());
}

async function findMainPage(browser) {
  if(process.env.ALIS_CHATGPT_UI_TARGET_ID)
    return pinnedUiWindow(browser,process.env.ALIS_CHATGPT_UI_TARGET_ID);
  const matches=[];
  for (const context of browser.contexts()) {
    for (const page of context.pages()) {
      if (page.url() !== MAIN_URL) continue;
      const composer = page.getByRole("textbox", { name: ANY_COMPOSER });
      const newChat = page.getByRole("button", {
        name: new RegExp(`^(Start new chat in|New chat in) ${escapedProject}$`)
      });
      if ((await visibleCount(composer)) === 1 || (await visibleCount(newChat)) > 0)
        matches.push(page);
    }
  }
  if(matches.length===1)return matches[0];
  throw new Error(matches.length ? "ALIS_UI_MULTIPLE_WINDOWS_REQUIRE_TARGET" : "main ChatGPT renderer not found");
}

async function projectGuardCount(page) {
  const guard = page.getByRole("button", { name: PROJECT });
  if ((await guard.count()) === 1 && (await visibleCount(guard)) === 1)
    return 1;
  // Desktop removes the composer's project badge after the first prompt.
  // The selected chat's containing project list remains the semantic proof
  // of project membership; a sidebar project heading alone is insufficient.
  const list = page.getByRole("list", { name: `Chats in ${PROJECT_NAME}`, exact: true });
  if ((await list.count()) !== 1) return 0;
  const selected = list.locator('[role="button"][aria-current="page"]');
  return (await selected.count()) === 1 && (await visibleCount(selected)) === 1 ? 1 : 0;
}

// Read a stable UI sidebar chat key, never a title, visible text or Project
// label. This is local UI continuity evidence, NOT server attestation. Builds
// without a unique chat ID/href fail closed before a continuation can send.
export async function uiTargetIdentity(page) {
  await verifyProject(page);
  const selected = page.getByRole("list", {
    name: `Chats in ${PROJECT_NAME}`, exact: true
  }).locator('[role="button"][aria-current="page"]');
  if ((await selected.count()) !== 1 || (await visibleCount(selected)) !== 1)
    throw new Error("ALIS_UI_CHAT_IDENTITY_UNAVAILABLE");
  const source = await selected.evaluate(node => {
    for (const key of ["data-conversation-id", "data-chat-id"]) {
      const value = node.getAttribute(key) || node.closest(`[${key}]`)?.getAttribute(key);
      if (value && /^[a-zA-Z0-9_-]{12,128}$/.test(value))
        return `id:${value}`;
    }
    const link = node.closest('a[href]') || node.querySelector('a[href]');
    const href = link?.getAttribute("href");
    // Only an actual conversation path, never a label or generic sidebar URL.
    if (href && /(?:^|\/)c\/[a-zA-Z0-9_-]{12,128}(?:$|[?#/])/.test(href))
      return `href:${href.split(/[?#]/)[0]}`;
    return null;
  });
  if (!source) throw new Error("ALIS_UI_CHAT_IDENTITY_UNAVAILABLE");
  return source;
}

async function submittedUnits(page,items=null) {
  items??=await visibleItems(page.locator('[data-chatgpt-search-unit-key$=":user"]'));
  return Promise.all(items.map(item=>item.evaluate(node=>({text:node.innerText,
      turn_key:node.closest('[data-turn-key]')?.getAttribute('data-turn-key'),
      message_id:node.getAttribute('data-chatgpt-search-message-ids'),
      inline_code:[...node.querySelectorAll('code')].map(n=>n.textContent),
      expand_control:[...node.querySelectorAll('button')].some(b=>
        /^Show (more|less)$/.test(b.innerText.trim()))}))));
}

export async function uiOnlyTurnIdentity(page,{initialPrompt=null}={}) {
  await verifyProject(page);
  return uiAnchorSource(PROJECT_NAME,await submittedUnits(page),initialPrompt);
}

export async function resumeUiChat(page,label,{
  targetKey=null,initialPrompt=null,readOnlyHistory=false
}={}) {
  if(!process.env.ALIS_CHATGPT_UI_TARGET_ID||typeof label!=='string'||
     !label.trim()||label.length>250||/[\x00-\x1f]/.test(label)||
     (targetKey===null&&initialPrompt===null))throw Error('ALIS_UI_RESUME_BINDING_REQUIRED');
  const matches=async()=>{
    const source=await uiOnlyTurnIdentity(page,{initialPrompt});
    return targetKey===null||createHash('sha256').update(source).digest('hex')===targetKey;
  };
  try {if(await matches())return;}catch{}
  const row=page.getByRole('list',{name:`Chats in ${PROJECT_NAME}`,exact:true})
    .getByRole('button',{name:label,exact:true});
  await requireOne(row,'owned chat navigation candidate');
  await row.click({timeout:3000});
  await sleep(400);
  // A title only locates a candidate. The original full prompt/turn anchor
  // must still match before observing a response or touching its composer.
  // The read-only observer may restore the first-turn anchor by scrolling
  // an already-selected, uniquely named Project thread. No sender/composer
  // may use this exception: a full anchor must be verified before receipts.
  if(!readOnlyHistory && !await matches())
    throw Error('ALIS_UI_RESUME_TARGET_MISMATCH');
  if(readOnlyHistory)await verifyProject(page);
}

async function captureHistoryScope(page) {
  // A short-lived DOM witness for READ-ONLY recovery. Desktop does not
  // always expose conversation IDs in its sidebar. Keep the actual selected
  // row and message scroller alive instead; neither a label nor this local
  // nonce is a chat identity. The saved first-turn key is still mandatory.
  await verifyProject(page);
  const selected=page.getByRole('list',{name:`Chats in ${PROJECT_NAME}`,exact:true})
    .locator('[role="button"][aria-current="page"]');
  if(await selected.count()!==1||await visibleCount(selected)!==1)
    throw Error('ALIS_UI_HISTORY_CHAT_CHANGED');
  const row=await selected.elementHandle();
  const fingerprint=node=>JSON.stringify(['aria-label','data-chat-id','data-conversation-id','href']
    .map(k=>node.getAttribute(k)));
  const signature=await row.evaluate(fingerprint);
  async function firstItem() {
    const items=await visibleItems(page.locator('[data-chatgpt-search-unit-key$=":user"]'));
    if(!items.length)throw Error('ALIS_UI_HISTORY_SCROLL_UNVERIFIED');
    return items[0];
  }
  const item=await firstItem();
  const handle=await item.evaluateHandle(node=>{
    const hosts=[];
    for(let n=node.parentElement;n&&n!==document.body;n=n.parentElement)
      if(/(auto|scroll)/.test(getComputedStyle(n).overflowY)
         &&n.scrollHeight>n.clientHeight+80)hosts.push(n);
    return hosts.length===1?hosts[0]:null;
  });
  const host=handle.asElement();
  if(!host){await handle.dispose();await row.dispose();throw Error('ALIS_UI_HISTORY_SCROLL_UNVERIFIED');}
  const witness='local-ui-history:'+randomUUID();
  async function check() {
    await verifyProject(page);
    if(await selected.count()!==1||await visibleCount(selected)!==1
       ||!await selected.evaluate((node,original)=>node===original,row)
       ||!await row.evaluate((node,sig)=>node.isConnected
          &&node.getAttribute('aria-current')==='page'
          &&JSON.stringify(['aria-label','data-chat-id','data-conversation-id','href']
             .map(k=>node.getAttribute(k)))===sig,signature)
       ||!await host.evaluate(node=>node.isConnected))
      throw Error('ALIS_UI_HISTORY_CHAT_CHANGED');
    const current=await firstItem();
    if(!await current.evaluate((node,original)=>{
      for(let n=node.parentElement;n;n=n.parentElement)if(n===original)return true;
      return false;
    },host))throw Error('ALIS_UI_HISTORY_CHAT_CHANGED');
    return witness;
  }
  async function scroll(boundary) {
    await check();
    return host.evaluate((node,which)=>{
      const extent=node.scrollHeight-node.clientHeight;
      const reverse=getComputedStyle(node).flexDirection==='column-reverse'
        ||(node.firstElementChild
           &&getComputedStyle(node.firstElementChild).flexDirection==='column-reverse');
      node.scrollTop=which==='oldest'?(reverse?-node.scrollHeight:0)
        :(reverse?0:node.scrollHeight);
      const top=node.scrollTop;
      return {ok:which==='oldest'
        ?(reverse?top<=-extent+3:Math.abs(top)<=3)
        :(reverse?Math.abs(top)<=3:top>=extent-3)};
    },boundary);
  }
  return {check,scroll,dispose:async()=>{await handle.dispose();await row.dispose();}};
}

async function observeVirtualizedSubmittedPrompt(page,prompt,targetKey) {
  // Recovery observation ONLY, never used as a composer admission signal.
  // Keep one selected-chat UI identity across scrolling to both endpoints;
  // no title-only match, chat switch, Send, draft edit or journal mutation.
  if(await visibleCount(page.getByRole('button',{name:/stop/i})))
    return {completed:false};
  const scope=await captureHistoryScope(page);
  try {
  const selectedBefore=await scope.check();
  let firstUnits=null,oldestReached=false;
  for(let attempt=0;attempt<6;attempt++) {
    const step=await scope.scroll('oldest');
    if(!step.ok)throw Error('ALIS_UI_HISTORY_SCROLL_UNVERIFIED');
    oldestReached=true;
    await sleep(300);
    if(await scope.check()!==selectedBefore)
      throw Error('ALIS_UI_HISTORY_CHAT_CHANGED');
    const units=await submittedUnits(page);
    try {
      const key=createHash('sha256').update(uiAnchorSource(PROJECT_NAME,units)).digest('hex');
      if(key===targetKey){firstUnits=units;break;}
    } catch {}
  }
  if(!firstUnits)throw Error('ALIS_UI_HISTORY_ANCHOR_MISMATCH');
  const lastStep=await scope.scroll('newest');
  if(!lastStep.ok)throw Error('ALIS_UI_HISTORY_SCROLL_UNVERIFIED');
  await sleep(350);
  async function lastSample() {
    if(await scope.check()!==selectedBefore)
      throw Error('ALIS_UI_HISTORY_CHAT_CHANGED');
    const items=await visibleItems(page.locator('[data-chatgpt-search-unit-key$=":user"]'));
    const units=await submittedUnits(page,items);
    const bound=validateVirtualizedHistory({
      project:PROJECT_NAME,targetKey,prompt,
      selectedBefore,selectedAfter:await scope.check(),
      firstUnits,latestUnits:units,
      oldestReached,newestReached:true
    });
    const i=units.findIndex(u=>u.turn_key===bound.turn_key
                            && u.message_id===bound.message_id);
    const result=await items[i].evaluate(node=>{
      const turn=node.closest('[data-turn-key]');
      if(!turn)return {text:'',assistant_count:0,action_count:0};
      const assistants=[...turn.querySelectorAll('[data-chatgpt-search-unit-key$=":assistant"]')];
      const actions=[...turn.querySelectorAll('button')].filter(b=>
        !b.closest('[data-chatgpt-search-unit-key$=":user"]')
        &&/copy|regenerate/i.test(b.getAttribute('aria-label')??''));
      return {text:assistants.map(n=>n.innerText).join('\n'),
              assistant_count:assistants.length,action_count:actions.length};
    });
    return {...result,turn_key:bound.turn_key,message_id:bound.message_id,
      stops:await visibleCount(page.getByRole('button',{name:/stop/i}))};
  }
  const first=await lastSample();
  if(first.stops||!first.assistant_count||!first.action_count)
    return {completed:false};
  await sleep(450);
  const next=await scope.scroll('newest');
  if(!next.ok)throw Error('ALIS_UI_HISTORY_SCROLL_UNVERIFIED');
  const second=await lastSample();
  if(JSON.stringify(first)!==JSON.stringify(second)||second.stops)
    return {completed:false};
  const markers=scanLoopMarkerTokens(second.text);
  if(second.text.length>120000
     ||markers.length!==1
     ||/error in message stream|there was an error generating a response/i.test(second.text))
    throw Error('ALIS_UI_HISTORY_ORIGINAL_FINAL_UNVERIFIED');
  if(await scope.check()!==selectedBefore)
    throw Error('ALIS_UI_HISTORY_CHAT_CHANGED');
  return {completed:true,delivery_observed:true,idle_observed:true,
    attestation:'local-ui-user-turn-v1',
    prompt_sha256:createHash('sha256').update(prompt).digest('hex'),
    ui_target_key:targetKey,
    ui_chat_label:await page.getByRole('list',{name:`Chats in ${PROJECT_NAME}`,exact:true})
      .locator('[role="button"][aria-current="page"]').getAttribute('aria-label'),
    response:{text:second.text,markerCount:markers.length,
      extractionSignal:'submitted-user-turn-assistant'}};
  } finally {await scope.dispose();}
}

export async function observeSubmittedPrompt(page,prompt,{
  targetKey=null,archivedReadOnly=false,expectedUserCount=null
}={}) {
  // An archived chat has no selected Project row. Observation alone may use
  // a previously bound first-turn hash; this never grants composer access.
  if(archivedReadOnly&&(typeof targetKey!=='string'||!/^[0-9a-f]{64}$/.test(targetKey)))
    throw Error('ALIS_UI_ARCHIVE_REQUIRES_ORIGINAL_TARGET');
  if(expectedUserCount!==null&&(!Number.isInteger(expectedUserCount)||expectedUserCount<1||expectedUserCount>200||
      typeof targetKey!=='string'||!/^[0-9a-f]{64}$/.test(targetKey)))
    throw Error('ALIS_UI_LEGACY_COUNT_BINDING_REQUIRED');
  async function sample() {
    if(!archivedReadOnly)await verifyProject(page);
    const items=await visibleItems(page.locator('[data-chatgpt-search-unit-key$=":user"]'));
    const units=await submittedUnits(page,items);
    const source=uiAnchorSource(PROJECT_NAME,units);
    const key=createHash('sha256').update(source).digest('hex');
    if(targetKey!==null&&targetKey!==key)throw Error('ALIS_UI_TARGET_CHANGED_NO_SEND');
    if(expectedUserCount!==null&&(units.length!==expectedUserCount||
        new Set(units.map(u=>u.turn_key)).size!==units.length||
        new Set(units.map(u=>u.message_id)).size!==units.length))
      throw Error('ALIS_UI_UNEXPECTED_USER_TURN_COUNT');
    let index;
    try {({index}=matchingSubmittedUnit(units,prompt));}
    catch(error) {
      // Old schedulers submitted identical continuation text. A known
      // first-turn key plus the exact prior accepted count can bind the
      // newest original unit; normal observation remains strictly unique.
      if(expectedUserCount===null||error.message!=='ALIS_UI_SUBMITTED_PROMPT_NOT_UNIQUE'||
          !submittedPromptMatches(units.at(-1),prompt))throw error;
      index=units.length-1;
    }
    if(index!==units.length-1)throw Error('ALIS_UI_LATER_USER_TURN_REQUIRES_REVIEW');
    const unit=items[index];
    const result=await unit.evaluate(node=>{
      const turn=node.closest('[data-turn-key]');
      const assistants=[...turn.querySelectorAll('[data-chatgpt-search-unit-key$=":assistant"]')];
      const text=assistants.map(n=>n.innerText).join('\n');
      const actions=[...turn.querySelectorAll('button')].filter(b=>
        !b.closest('[data-chatgpt-search-unit-key$=":user"]')&&
        /copy|regenerate/i.test(b.getAttribute('aria-label')??''));
      return {text,assistant_count:assistants.length,action_count:actions.length};
    });
    const stops=await visibleCount(page.getByRole('button',{name:/stop/i}));
    return {key,...result,stops};
  }
  let first;
  try {first=await sample();}
  catch(error) {
    // A long thread may unmount its original first-turn DOM node. The only
    // fallback is a read-only full history continuity walk bound to the
    // already pinned target and unique saved Alis request token.
    if(!archivedReadOnly
       &&virtualizedRecoveryEligible(prompt,targetKey,expectedUserCount)
       &&['ALIS_UI_TARGET_CHANGED_NO_SEND',
           'ALIS_UI_TURN_ANCHOR_UNAVAILABLE',
           'ALIS_UI_SUBMITTED_PROMPT_NOT_UNIQUE'].includes(error?.message))
      return observeVirtualizedSubmittedPrompt(page,prompt,targetKey);
    throw error;
  }
  if(first.stops||!first.assistant_count||(!archivedReadOnly&&!first.action_count))return {completed:false};
  await sleep(450);
  const second=await sample();
  if(JSON.stringify(first)!==JSON.stringify(second)||second.stops)return {completed:false};
  const markers=scanLoopMarkerTokens(second.text);
  const complete=second.action_count>0&&markers.length===1&&!/error in message stream|there was an error generating a response/i.test(second.text);
  if(!complete&&!(archivedReadOnly&&markers.length===0))
    throw Error('ALIS_UI_ORIGINAL_ASSISTANT_FINAL_UNVERIFIED');
  if(second.text.length>120000)throw Error('ALIS_UI_RESPONSE_EXCEEDS_BOUND');
  return {completed:complete,delivery_observed:true,idle_observed:true,
    attestation:'local-ui-user-turn-v1',
    prompt_sha256:createHash('sha256').update(prompt).digest('hex'),
    ui_target_key:second.key,
    ui_chat_label:archivedReadOnly?null:await page.getByRole('list',{name:`Chats in ${PROJECT_NAME}`,exact:true})
      .locator('[role="button"][aria-current="page"]').getAttribute('aria-label'),
    response:{text:second.text,markerCount:markers.length,
      extractionSignal:'submitted-user-turn-assistant'}};
}

export async function waitForSubmittedPrompt(page,prompt,{
  targetKey=null,chatLabel=null,timeoutMs=600000,pollMs=2000
}={}) {
  // Cached/virtualized chats can reduce global Copy counts between turns.
  // Only the exact submitted input and its own settled assistant can finish
  // this send. A different visible chat is never a completion signal.
  const deadline=Date.now()+timeoutMs;
  let key=targetKey,label=chatLabel;
  while(Date.now()<deadline) {
    try {
      if(key===null) {
        key=createHash('sha256').update(
          await uiOnlyTurnIdentity(page,{initialPrompt:prompt})).digest('hex');
      }
      if(label!==null)await resumeUiChat(page,label,{targetKey:key});
      const result=await observeSubmittedPrompt(page,prompt,{targetKey:key});
      if(result.completed)return result;
      // A title is only a navigation candidate. Retain the first-turn key
      // and verify it again if this owned window later shows another chat.
      const selected=page.getByRole('list',{name:`Chats in ${PROJECT_NAME}`,exact:true})
        .locator('[role="button"][aria-current="page"]');
      if(await selected.count()===1&&await selected.isVisible()) {
        const next=await selected.getAttribute('aria-label');
        if(typeof next==='string'&&next.trim()&&next.length<=250&&!/[\x00-\x1f]/.test(next))label=next;
      }
    } catch(error) {
      // DOM publication can lag the acknowledged click. Retry observation
      // only; a later user turn, changed target or invalid final fails closed.
      if(!['ALIS_UI_TURN_ANCHOR_UNAVAILABLE','ALIS_UI_SUBMITTED_PROMPT_NOT_UNIQUE']
          .includes(error.message))throw error;
    }
    await sleep(pollMs);
  }
  throw Error('ALIS_UI_ORIGINAL_RESPONSE_TIMEOUT_NO_RESEND');
}

async function verifyProject(page) {
  if ((await projectGuardCount(page)) !== 1) {
    const error = new Error(`${PROJECT_NAME} project guard is not visible; waiting for target chat`);
    error.code = "HADALIS_DESKTOP_VIEW_CHANGED";
    throw error;
  }
}

async function resolveComposer(page) {
  return requireOne(page.getByRole("textbox", { name: COMPOSER }), "composer");
}

async function newChatFootprint(page) {
  const selected = await visibleItems(page.locator(
    '[role="list"][aria-label^="Chats in "] [aria-current="page"][role="button"]'
  ));
  if (selected.length > 1)
    throw new Error("multiple selected ChatGPT chats");
  return {
    sameProject: (await projectGuardCount(page)) === 1,
    responseActions: await visibleCount(page.getByRole("button", { name: RESPONSE_ACTION })),
    markers: await loopMarkerCount(page),
    selectedChat: selected.length === 1 ? await selected[0].getAttribute("aria-label") : null
  };
}

export async function openHadalisNewChat(page, {
  unownedPreviousChat = false, ownerChatReset = false
} = {}) {
  // A new owner may arrive while an unrelated chat is generating. Opening a
  // project chat must not depend on that chat's composer or Stop control.
  // Rotations of an owned chat still require the idle guard below.
  if (!unownedPreviousChat && !ownerChatReset)
    await requireIdleComposer(page, false);
  const before = await newChatFootprint(page);
  if (!ownerChatReset && before.sameProject && before.responseActions === 0 &&
      before.markers === 0 && before.selectedChat === null) {
    // Reuse a verified empty project chat, including after another process
    // navigated there first. A busy target-project chat may belong to an
    // earlier run, so never leave it before completion.
    await requireIdleComposer(page);
    return page;
  }
  // Only a separately owner-approved manual reset may abandon an old
  // same-Project editor that has become stuck. The manager verified that
  // the preceding attempt is settled and has no active worker job.
  if (unownedPreviousChat && before.sameProject && !ownerChatReset)
    await requireIdleComposer(page);
  let button = null;
  for (const name of [`Start new chat in ${PROJECT_NAME}`, `New chat in ${PROJECT_NAME}`]) {
    // Current Desktop presents both a labeled button and a second button
    // whose accessible name comes from nested content. Prefer the exact
    // aria-labeled project action; fail closed if it is not unique.
    const exact = page.locator(`button[aria-label="${name}"]`);
    if (await visibleCount(exact) === 1) {
      button = exact;
      break;
    }
    const visible = await visibleItems(page.getByRole("button", { name }));
    if (visible.length === 1) {
      button = visible[0];
      break;
    }
  }
  if (button === null)
    throw new Error(`${PROJECT_NAME} new-chat control is unavailable or ambiguous`);
  await semanticClick(button, `${PROJECT_NAME} new chat`);

  const browser = page.context().browser();
  const deadline = Date.now() + 15000;
  let lastReason = "no observable transition";

  while (Date.now() < deadline) {
    try {
      const resolved = browser ? await findMainPage(browser) : page;
      await requireIdleComposer(resolved);
      const after = await newChatFootprint(resolved);
      if (after.responseActions !== 0 || after.markers !== 0 ||
          (before.sameProject && before.selectedChat === after.selectedChat &&
           before.responseActions === 0 && before.markers === 0))
        throw new Error("previous chat is still visible");
      await sleep(250);
      await requireIdleComposer(resolved);
      const stable = await newChatFootprint(resolved);
      if (stable.responseActions !== 0 || stable.markers !== 0)
        throw new Error("new chat did not stay empty");
      return resolved;
    } catch (error) {
      lastReason = String(error?.message ?? error);
    }
    await sleep(250);
  }

  throw new Error(`new chat did not become ready: ${lastReason}`);
}

export async function requireIdleComposer(page, requireProject = true) {
  if (requireProject) await verifyProject(page);
  const composer = await resolveComposer(page);
  if ((await visibleCount(page.getByRole("button", { name: /stop/i }))) > 0) {
    const error = new Error("ChatGPT generation is active; waiting before rotating the owned chat");
    error.code = "HADALIS_DESKTOP_BUSY";
    throw error;
  }
  // Empty ProseMirror editors can report a layout newline via innerText.
  // textContent is empty in that state and still detects whitespace drafts.
  if (await composer.evaluate(element => (element.textContent ?? "").length > 0))
    throw new Error("refusing to rotate with a non-empty ChatGPT composer");
  return composer;
}

async function submissionStarted(page, composer) {
  try {
    if ((await composer.innerText()).trim() === "")
      return true;
  } catch {}

  return (await visibleCount(
    page.getByRole("button", { name: /stop/i })
  )) > 0;
}

async function waitForSubmissionStart(page, composer, timeoutMs = 1500) {
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    if (await submissionStarted(page, composer))
      return true;
    await sleep(100);
  }

  return submissionStarted(page, composer);
}

async function dispatchCdpEnter(page) {
  const session = await page.context().newCDPSession(page);

  try {
    const event = {
      key: "Enter",
      code: "Enter",
      windowsVirtualKeyCode: 13,
      nativeVirtualKeyCode: 13
    };

    await session.send("Input.dispatchKeyEvent", {
      type: "rawKeyDown",
      ...event
    });
    await session.send("Input.dispatchKeyEvent", {
      type: "keyUp",
      ...event
    });
  } finally {
    await session.detach();
  }
}

async function dispatchSemanticClick(send) {
  await send.evaluate(element => {
    element.dispatchEvent(new PointerEvent("pointerdown", {
      bubbles: true,
      cancelable: true,
      composed: true,
      button: 0,
      buttons: 1,
      pointerId: 1,
      pointerType: "mouse",
      isPrimary: true
    }));
    element.dispatchEvent(new MouseEvent("mousedown", {
      bubbles: true,
      cancelable: true,
      composed: true,
      button: 0,
      buttons: 1
    }));
    element.dispatchEvent(new MouseEvent("mouseup", {
      bubbles: true,
      cancelable: true,
      composed: true,
      button: 0,
      buttons: 0
    }));
    element.dispatchEvent(new MouseEvent("click", {
      bubbles: true,
      cancelable: true,
      composed: true,
      button: 0
    }));
  });
}

function runNative(argv, timeout = 3000) {
  const result = spawnSync(argv[0], argv.slice(1), {
    encoding: "utf8",
    timeout,
    env: process.env
  });

  return {
    argv,
    status: result.status,
    signal: result.signal,
    stdout: (result.stdout ?? "").trim().slice(0, 2000),
    stderr: (result.stderr ?? "").trim().slice(0, 2000),
    error: result.error ? String(result.error) : null
  };
}

async function dispatchNativeWaylandEnter() {
  const windowsResult = runNative(["niri", "msg", "--json", "windows"]);
  if (windowsResult.status !== 0) {
    return {
      ok: false,
      stage: "niri-windows",
      windowsResult
    };
  }

  let windows;
  try {
    windows = JSON.parse(windowsResult.stdout);
  } catch (error) {
    return {
      ok: false,
      stage: "parse-windows",
      error: String(error),
      windowsResult
    };
  }

  if (!Array.isArray(windows)) {
    return {
      ok: false,
      stage: "windows-shape",
      windowsResult
    };
  }

  const candidates = windows.filter(window => {
    const haystack = [
      window?.app_id,
      window?.title
    ]
      .filter(value => typeof value === "string")
      .join(" ")
      .toLowerCase();

    return haystack.includes("chatgpt");
  });

  const target =
    candidates.find(window =>
      typeof window?.title === "string" &&
      window.title.toLowerCase().includes("hadalis cloud")
    ) ??
    candidates.find(window => window?.is_focused === true) ??
    (candidates.length === 1 ? candidates[0] : null);

  if (!target || target.id == null) {
    return {
      ok: false,
      stage: "select-window",
      candidates: candidates.map(window => ({
        id: window?.id ?? null,
        app_id: window?.app_id ?? null,
        title: window?.title ?? null,
        is_focused: window?.is_focused ?? null
      }))
    };
  }

  const focusResult = runNative([
    "niri",
    "msg",
    "action",
    "focus-window",
    "--id",
    String(target.id)
  ]);

  if (focusResult.status !== 0) {
    return {
      ok: false,
      stage: "focus-window",
      target,
      focusResult
    };
  }

  await sleep(250);

  let keyResult = runNative([
    "wtype",
    "-P",
    "Return",
    "-p",
    "Return"
  ]);

  if (keyResult.status !== 0) {
    keyResult = runNative([
      "wtype",
      "-k",
      "Return"
    ]);
  }

  await sleep(250);

  return {
    ok: keyResult.status === 0,
    stage: "wtype",
    target: {
      id: target.id,
      app_id: target.app_id ?? null,
      title: target.title ?? null,
      is_focused: target.is_focused ?? null
    },
    focusResult,
    keyResult
  };
}

async function visibleItems(locator) {
  const items = [];
  const count = await locator.count();

  for (let index = 0; index < count; index += 1) {
    const item = locator.nth(index);
    try {
      if (await item.isVisible())
        items.push(item);
    } catch {}
  }

  return items;
}

function splitGitHubMentionPrompt(prompt) {
  const lines = prompt.split(/\r?\n/);
  const index = lines.findIndex(line => line.trim());

  if (index < 0 || ![GITHUB_MENTION, GITHUB_APP_MENTION].includes(lines[index].trim()))
    return null;

  return lines.slice(index + 1).join("\n");
}

async function clickGitHubPicker(page) {
  // Other plugins mention GitHub in their descriptions (e.g. Code Review).
  // Match the entry's leading name instead of any word in its description.
  const pickerName = /^GitHub(?:\s|$)/i;
  const roleLocators = [
    page.getByRole("option", { name: pickerName }),
    page.getByRole("menuitem", { name: pickerName }),
    page.getByRole("menuitemradio", { name: pickerName }),
    page.getByRole("button", { name: pickerName })
  ];
  // A chat title/header can itself begin with GitHub. Only actual mention
  // menu entries may qualify; a matching name elsewhere is never a picker.
  const inPicker = item => item.evaluate(element => Boolean(element.closest(
    '[data-mention-section-items], [role="listbox"], [role="menu"]'
  )));

  for (const locator of roleLocators) {
    const candidates = [];
    for (const item of await visibleItems(locator))
      if (await inPicker(item)) candidates.push(item);
    if (!candidates.length) continue;
    if (candidates.length !== 1) throw new Error("GitHub mention picker is ambiguous");

    await candidates[0].evaluate(element => element.click());
    await sleep(500);
    return "role-click";
  }

  const exactText = page.getByText(/^GitHub$/i);
  for (const item of await visibleItems(exactText)) {
    const clickable = item.locator(
      'xpath=ancestor-or-self::*[@role="option" or @role="menuitem" or @role="menuitemradio" or self::button][1]'
    );

    if ((await clickable.count()) === 1 && await inPicker(clickable)) {
      await clickable.evaluate(element => element.click());
      await sleep(500);
      return "text-ancestor-click";
    }
  }

  return null;
}

export async function selectGitHubMention(page, composer) {
  await composer.fill("");
  await composer.focus();
  await page.keyboard.insertText("@");
  await sleep(700);
  let selected=await clickGitHubPicker(page);
  if (selected) return selected;
  // Filter a long picker, then inspect its actual options again. Enter can
  // submit an ordinary composer when no picker owns focus: never use it.
  await page.keyboard.insertText("GitHub");
  await sleep(700);
  selected=await clickGitHubPicker(page);
  if (selected) return selected;
  throw new Error("ALIS_UI_GITHUB_PICKER_UNAVAILABLE");
}

async function populatePrompt(page, composer, prompt) {
  const rest = splitGitHubMentionPrompt(prompt);

  if (rest === null) {
    await composer.fill(prompt);
    if ((await composer.innerText()).trim() !== prompt.trim())
      throw new Error("composer text mismatch");
    return { githubMention: false };
  }

  const method = await selectGitHubMention(page, composer);
  await composer.focus();
  await page.keyboard.insertText(rest);

  const composerText = (await composer.innerText()).trim();
  const firstBodyLine = rest
    .split(/\r?\n/)
    .map(line => line.trim())
    .find(Boolean);

  const richMention = await composer.evaluate(element => element.querySelectorAll(
    '[app-mention-name="github"], [data-prompt-link-href="plugin://github@openai-curated-remote"]'
  ).length === 1);
  if (!richMention)
    throw new Error("GitHub rich mention is missing after selection");

  if (firstBodyLine && !composerText.includes(firstBodyLine))
    throw new Error("prompt body is missing after GitHub mention selection");

  return { githubMention: true, method };
}

export async function submitPrompt(page, prompt, {targetKey=null}={}) {
  let sendAttempted=false;
  try {
  const composer = await requireIdleComposer(page);

  await populatePrompt(page, composer, prompt);

  const send = page.getByRole("button", { name: "Send" });
  await requireOne(send, "Send");

  const completionBaseline = {
    markerCount: await loopMarkerCount(page),
    responseActionCount: await visibleCount(
      page.getByRole("button", { name: RESPONSE_ACTION })
    )
  };

  // A send is an irreversible operation. Attempt one semantic click only.
  // If the UI does not acknowledge it, the result is INDETERMINATE: do not
  // try Enter, CDP, Wayland or another click. The owning Python bridge has
  // already fsynced a one-shot intent before invoking this subprocess.
  await page.waitForTimeout(300);
  await verifyProject(page);
  if(targetKey!==null&&createHash('sha256').update(await uiOnlyTurnIdentity(page)).digest('hex')!==targetKey)
    throw Error('ALIS_UI_TARGET_CHANGED_NO_SEND');
  const body=splitGitHubMentionPrompt(prompt);
  const live=await composer.innerText();
  const normalized=value=>value.replace(/\s+/g,' ').trim();
  if(normalized(body??prompt)!==normalized(body===null?live:live.replace(/^GitHub\s*/,'')))
    throw Error('ALIS_UI_COMPOSER_CHANGED_NO_SEND');
  if(body!==null&&!await composer.evaluate(element=>element.querySelectorAll(
    '[app-mention-name="github"], [data-prompt-link-href="plugin://github@openai-curated-remote"]'
  ).length===1))throw Error('GitHub rich mention was removed before Send');
  if (await send.isDisabled())
    throw new Error("ALIS_UI_SEND_DISABLED_NO_ATTEMPT");

  sendAttempted=true;
  await send.evaluate(element => element.click());
  if (!await waitForSubmissionStart(page, composer, 2500))
    throw new Error("ALIS_UI_SEND_UNCERTAIN_NO_RETRY");

  return completionBaseline;
  } catch (error) {
    // Only this in-process boundary can prove a normal failure preceded the
    // single Send click. Crashes/timeouts have no such receipt and stay unsure.
    error.uiSendAttempted=sendAttempted;
    error.uiFailureCode=String(error.message).includes("ALIS_UI_GITHUB_PICKER_UNAVAILABLE")
      ? "ALIS_UI_GITHUB_PICKER_UNAVAILABLE"
      : String(error.message).includes("rich mention")
        ? "ALIS_UI_GITHUB_MENTION_UNVERIFIED"
        : "ALIS_UI_PRE_SEND_FAILED";
    throw error;
  }
}

async function loopMarkerTokens(page) {
  const bodyText = await page.locator("body").innerText();
  return scanLoopMarkerTokens(bodyText);
}

async function loopMarkerCount(page) {
  return (await loopMarkerTokens(page)).length;
}

export async function managedBaseline(page) {
  await requireIdleComposer(page);
  return {
    markerCount: await loopMarkerCount(page),
    responseActionCount: await visibleCount(
      page.getByRole("button", { name: RESPONSE_ACTION })
    )
  };
}

async function failedStreamAction(page, baseline) {
  const actions = await visibleItems(page.getByRole("button", { name: RESPONSE_ACTION }));
  for (const action of actions.slice(baseline.responseActionCount).reverse()) {
    const isFailedStream = await action.evaluate((button, source) => {
      const label = (button.getAttribute("aria-label") ?? button.innerText ?? "").trim();
      if (!/^(retry|try again)$/i.test(label)) return false;
      let node = button;
      for (let depth = 0; depth < 8 && node && node.tagName !== "BODY";
           depth += 1, node = node.parentElement) {
        if (new RegExp(source, "i").test(node.innerText ?? "")) return true;
      }
      return false;
    }, STREAM_ERROR.source);
    if (isFailedStream) return action;
  }
  return null;
}

export async function retryFailedStream(page, baseline) {
  if (!Number.isInteger(baseline?.responseActionCount) ||
      baseline.responseActionCount < 0)
    throw new Error("invalid managed completion baseline");
  await verifyProject(page);
  if (await visibleCount(page.getByRole("button", { name: /stop/i })) !== 0)
    throw new Error("ChatGPT generation is still active; cannot retry failed stream");
  const action = await failedStreamAction(page, baseline);
  if (!action) throw new Error("current failed stream Retry control is unavailable");
  await semanticClick(action, "failed stream Retry");
  return { retryTriggered: true };
}

export async function managedPoll(page, baseline) {
  if (!Number.isInteger(baseline?.responseActionCount) ||
      baseline.responseActionCount < 0)
    throw new Error("invalid managed completion baseline");
  // The user can navigate Desktop between ticks. Reject a response when the
  // configured project guard is no longer visible.
  await verifyProject(page);
  const actions = page.getByRole("button", { name: RESPONSE_ACTION });
  const count = await visibleCount(actions);
  const stops = await visibleCount(page.getByRole("button", { name: /stop/i }));
  if (count <= baseline.responseActionCount || stops !== 0)
    return { completed: false, responseActionCount: count, generationActive: stops > 0 };
  await sleep(900);
  await verifyProject(page);
  const secondCount = await visibleCount(actions);
  const secondStops = await visibleCount(page.getByRole("button", { name: /stop/i }));
  if (secondCount <= baseline.responseActionCount || secondStops !== 0)
    return { completed: false, responseActionCount: secondCount, generationActive: secondStops > 0 };
  if (await failedStreamAction(page, baseline))
    return { completed: false, streamError: true, responseActionCount: secondCount };
  const response = await extractNearResponseAction(page, baseline.responseActionCount);
  await verifyProject(page);
  if (!response || response.markerCount !== 1)
    throw new Error("new assistant response has no unique ALIS_LOOP marker");
  return { completed: true, response };
}

export async function waitForCompletion(
  page,
  timeoutMs = 600000,
  completionBaseline = null
) {
  const deadline = Date.now() + timeoutMs;
  const hasSubmitBaseline = completionBaseline?.markerCount != null;
  const baselineMarkerCount =
    completionBaseline?.markerCount ?? await loopMarkerCount(page);
  const baselineResponseActionCount =
    completionBaseline?.responseActionCount ??
    await visibleCount(page.getByRole("button", { name: RESPONSE_ACTION }));

  while (Date.now() < deadline) {
    const markerCount = await loopMarkerCount(page);
    const responseActionCount = await visibleCount(
      page.getByRole("button", { name: RESPONSE_ACTION })
    );
    const stopCount = await visibleCount(
      page.getByRole("button", { name: /stop/i })
    );

    const markerAdvanced = markerCount > baselineMarkerCount;
    const responseActionAdvanced =
      responseActionCount > baselineResponseActionCount;

    // Prompts often contain ALIS_LOOP examples, so whole-page marker counts
    // are never proof that a NEW assistant generation has completed.
    // The send path requires a NEW assistant action and a subsequent
    // assistant-only extraction. Non-send observation retains its baseline.
    const completionAdvanced = hasSubmitBaseline
      ? responseActionAdvanced
      : (markerAdvanced || responseActionAdvanced);

    if (completionAdvanced && stopCount === 0) {
      await sleep(900);

      const markerCount2 = await loopMarkerCount(page);
      const responseActionCount2 = await visibleCount(
        page.getByRole("button", { name: RESPONSE_ACTION })
      );
      const stopCount2 = await visibleCount(
        page.getByRole("button", { name: /stop/i })
      );

      const markerAdvanced2 = markerCount2 > baselineMarkerCount;
      const responseActionAdvanced2 =
        responseActionCount2 > baselineResponseActionCount;
      const completionAdvanced2 = hasSubmitBaseline
        ? responseActionAdvanced2
        : (markerAdvanced2 || responseActionAdvanced2);

      if (completionAdvanced2 && stopCount2 === 0) {
        if (hasSubmitBaseline) {
          // User Copy controls can appear before generation begins. A new
          // toolbar is only a hint; wait for a settled assistant-only final.
          const response=await extractNearResponseAction(page,baselineResponseActionCount);
          try {
            requireFreshAssistantTurn({response,
              baselineActionCount:baselineResponseActionCount,
              currentActionCount:responseActionCount2,generationActive:false});
          } catch {await sleep(250);continue;}
        }
        return {
          completed: true,
          baselineMarkerCount,
          markerCount: markerCount2,
          baselineResponseActionCount,
          responseActionCount: responseActionCount2,
          completionSignal: markerAdvanced2 ? "loop-marker" : "response-action"
        };
      }
    }

    await sleep(250);
  }

  throw new Error("generation completion timeout");
}

async function extractNearResponseAction(page, baselineActionCount = 0) {
  // Retry belongs to a failed response, not to a completed assistant turn.
  const actions = await visibleItems(page.getByRole("button", { name: RESPONSE_ACTION }));
  for (let index = actions.length - 1; index >= baselineActionCount; index -= 1) {
    const action = actions[index];

    try {
      if (/^(retry|try again)$/i.test((await action.getAttribute("aria-label") ??
                                      await action.innerText()).trim()))
        continue;

      const result = await action.evaluate((button) => {
        const token = /(?:ALIS|HADALIS)_LOOP:(?:CONTINUE|ROTATE|DONE)\b|(?:ALIS|HADALIS)_LOOP:WAIT_RESULT[ \\t]+JOB-[A-Za-z0-9._-]+|(?:ALIS|HADALIS)_LOOP:CONNECTOR_BLOCKED[ \\t]+GITHUB\b/g;
        const turn = button.closest?.('[data-turn-key]');
        if (turn) {
          // Current Desktop places the answer toolbar next to a shared turn
          // containing both the user prompt and the assistant reply. Read
          // only its assistant message units, never the combined turn text.
          if (button.closest('[data-chatgpt-search-unit-key$=":user"]')) return null;
          let units = Array.from(turn.querySelectorAll(
            '[data-chatgpt-search-unit-key$=":assistant"]'
          ));
          if (!units.length) units = Array.from(turn.querySelectorAll(
            '[data-message-author-role="assistant"]'
          ));
          const text = units.map(unit => unit.innerText ?? "").join("\n");
          if (/error in message stream|there was an error generating a response/i.test(text))
            return null;
          const markers = Array.from(text.matchAll(token), match => match[0].trim());
          return markers.length ? {
            depth: 0, text: markers[markers.length - 1], markerCount: markers.length,
            extractionSignal: "assistant-turn"
          } : null;
        }
        let node = button;

        for (let depth = 0; depth < 12 && node && node.tagName !== "BODY";
             depth += 1) {
          const text = (node.innerText ?? "").trim();
          // Reaching the user turn can pick up the protocol example from the
          // prompt itself. Only a marker inside the assistant turn is valid.
          if (/(^|\n)You said:/m.test(text) ||
              /error in message stream|there was an error generating a response/i.test(text))
            return null;
          const markers = Array.from(text.matchAll(token), match => match[0].trim());

          if (markers.length)
            return {
              depth,
              text: markers[markers.length - 1],
              markerCount: markers.length
            };

          node = node.parentElement;
        }

        return null;
      });

      if (result)
        return result;
    } catch {}
  }

  return null;
}

export async function extractLoopResponse(
  page,
  { allowMarkerOnly = false, baselineMarkerCount = null,
    baselineResponseActionCount = null } = {}
) {
  if (baselineResponseActionCount !== null) {
    const actions = page.getByRole("button", { name: RESPONSE_ACTION });
    const count = await visibleCount(actions);
    const stops = await visibleCount(page.getByRole("button", { name: /stop/i }));
    // The response must be inside the newest assistant container associated
    // with a newly exposed response toolbar, never body-wide prompt text.
    const response = count > baselineResponseActionCount && stops === 0
      ? await extractNearResponseAction(page, baselineResponseActionCount)
      : null;
    await verifyProject(page);
    return requireFreshAssistantTurn({
      response, baselineActionCount: baselineResponseActionCount,
      currentActionCount: count, generationActive: stops !== 0
    });
  }

  if (baselineMarkerCount !== null) {
    // Legacy marker-only observations cannot prove which side authored the
    // text. Refuse to use this branch for a new send/turn completion.
    throw new Error("ALIS_UI_ASSISTANT_BASELINE_REQUIRED");
  }

  const anchored = await extractNearResponseAction(page);
  if (anchored)
    return anchored;

  if (allowMarkerOnly) {
    const markers = await loopMarkerTokens(page);
    if (markers.length) {
      return {
        depth: 0,
        text: markers[markers.length - 1],
        markerOnly: true,
        markerCount: markers.length
      };
    }
  }

  throw new Error("No completed assistant ALIS_LOOP response found");
}

export async function handoverCheck(page) {
  // Observational only: parking is a separate explicit control action.
  const composers = await visibleItems(page.getByRole("textbox", {
    name: ANY_COMPOSER
  }));
  let draftPresent = false;
  if (composers.length === 1) {
    try {
      draftPresent = await composers[0].evaluate(
        element => (element.textContent ?? "").length > 0
      );
    } catch {
      draftPresent = true;
    }
  }
  return {
    projectGuardVisible: await projectGuardCount(page),
    generationActive: (await visibleCount(
      page.getByRole("button", { name: /stop/i })
    )) > 0,
    composerReady: composers.length === 1,
    draftPresent
  };
}


export async function observeDesktop(page) {
  const composer = page.getByRole("textbox", { name: COMPOSER });
  const send = page.getByRole("button", { name: "Send" });
  return {
    title: await page.title(),
    url: page.url(),
    composerVisible: await visibleCount(composer),
    projectGuardVisible: await projectGuardCount(page),
    sendVisible: await visibleCount(send),
    sendDisabled: (await send.count()) === 1 ? await send.isDisabled() : null
  };
}

export async function connectDesktop() {
  const browser = await chromium.connectOverCDP(CDP,{timeout:6500});
  try {
    const page = await findMainPage(browser);
    return { browser, page };
  } catch (error) {await browser.close();throw error;}
}
