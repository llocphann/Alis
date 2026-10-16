/* Local UI continuity only. These are submitted message/turn keys, never
 * server-attested conversation IDs or native transport authorization. */
const UUID=/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const MENTION=/^\[(?:@GitHub|\$github)\]\((?:plugin:\/\/github@openai-curated-remote|app:\/\/connector_76869538009648d5b282a4bb21c3d157)\)\s*/;
const normalize=text=>text.replace(/\s+/g," ").trim();

export function submittedPromptMatches(unit,prompt) {
  if(typeof unit?.text!=="string"||typeof prompt!=="string")return false;
  let actual=unit.text;
  if(unit.expand_control===true)
    actual=actual.replace(/\s*…?\s*Show (?:more|less)\s*$/,"");
  const mention=MENTION.test(prompt);
  if(mention)actual=actual.replace(/^GitHub\s+/,"");
  return normalize(actual)===normalize(prompt.replace(MENTION,""));
}

export function matchingSubmittedUnit(units,prompt) {
  const matches=units.map((unit,index)=>({unit,index}))
    .filter(({unit})=>submittedPromptMatches(unit,prompt));
  if(matches.length!==1)throw Error("ALIS_UI_SUBMITTED_PROMPT_NOT_UNIQUE");
  return matches[0];
}

export function uiAnchorSource(project,units,initialPrompt=null) {
  if(typeof project!=="string"||!/^[A-Za-z0-9 ._-]{1,80}$/.test(project)||
     !Array.isArray(units)||!units.length||units.length>200)
    throw Error("ALIS_UI_TURN_ANCHOR_UNAVAILABLE");
  const first=units[0];
  if(typeof first.turn_key!=="string"||first.turn_key.length!==36||!UUID.test(first.turn_key)||
     typeof first.message_id!=="string"||first.message_id.length!==36||!UUID.test(first.message_id)||
     units.filter(u=>u.turn_key===first.turn_key||u.message_id===first.message_id).length!==1)
    throw Error("ALIS_UI_TURN_ANCHOR_AMBIGUOUS");
  if(initialPrompt!==null&&(units.length!==1||!submittedPromptMatches(first,initialPrompt)))
    throw Error("ALIS_UI_INITIAL_PROMPT_MISMATCH");
  return `local-ui-user-turn-v1:${project}:${first.turn_key}:${first.message_id}`;
}
