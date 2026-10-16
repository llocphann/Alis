/* Local, read-only history continuity for ChatGPT's virtualized turns.
 * Never a server receipt or authorization to send. Every sample must retain
 * the selected Project chat and independently prove the original first user
 * turn plus the exact newest saved input; do not infer IDs from titles.
 */
import {createHash} from "node:crypto";
import {uiAnchorSource,matchingSubmittedUnit,submittedPromptMatches} from "./ui_turn_anchor.mjs";

const SHA=/^[0-9a-f]{64}$/;
const UUID=/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const TOKEN=/\nAlis UI request token: [0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\n/;

export function virtualizedRecoveryEligible(prompt,targetKey,expectedUserCount=null) {
  return typeof prompt==="string" && TOKEN.test(prompt)
    && typeof targetKey==="string" && SHA.test(targetKey)
    && expectedUserCount===null;
}

export function validateVirtualizedHistory({
  project, targetKey, prompt, selectedBefore, selectedAfter,
  firstUnits, latestUnits, oldestReached, newestReached
}) {
  if (!virtualizedRecoveryEligible(prompt,targetKey)
      || typeof selectedBefore!=="string" || selectedBefore.length<12
      || selectedBefore!==selectedAfter
      || oldestReached!==true || newestReached!==true)
    throw Error("ALIS_UI_HISTORY_CONTINUITY_UNVERIFIED");
  if (!Array.isArray(firstUnits)||!Array.isArray(latestUnits)
      || !firstUnits.length || !latestUnits.length
      || firstUnits.length>200 || latestUnits.length>200)
    throw Error("ALIS_UI_HISTORY_CONTINUITY_UNVERIFIED");
  const anchored=createHash("sha256")
    .update(uiAnchorSource(project,firstUnits)).digest("hex");
  if (anchored!==targetKey)
    throw Error("ALIS_UI_HISTORY_ANCHOR_MISMATCH");
  let match;
  try {match=matchingSubmittedUnit(latestUnits,prompt);}
  catch {throw Error("ALIS_UI_HISTORY_ORIGINAL_PROMPT_UNVERIFIED");}
  if (match.index!==latestUnits.length-1
      || !submittedPromptMatches(match.unit,prompt)
      || typeof match.unit.turn_key!=="string" || !UUID.test(match.unit.turn_key)
      || typeof match.unit.message_id!=="string" || !UUID.test(match.unit.message_id)
      || latestUnits.filter(u=>u.turn_key===match.unit.turn_key
                        || u.message_id===match.unit.message_id).length!==1)
    throw Error("ALIS_UI_HISTORY_LATER_TURN_UNVERIFIED");
  return {turn_key:match.unit.turn_key,message_id:match.unit.message_id,
          selected:selectedBefore};
}
