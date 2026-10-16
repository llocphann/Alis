#!/usr/bin/env node
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {uiAnchorSource} from '../automation/chat_bridge/ui_turn_anchor.mjs';
import {virtualizedRecoveryEligible,validateVirtualizedHistory}
  from '../automation/chat_bridge/ui_history_witness.mjs';

const project='Automatic Alis',selected='id:original-project-chat-key';
const first={turn_key:'11111111-1111-1111-1111-111111111111',
  message_id:'22222222-2222-2222-2222-222222222222',
  text:'Oldest user prompt',inline_code:[]};
const token='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const prompt='GitHub inspect receipt\nAlis UI request token: '+token+'\n';
const latest={turn_key:'33333333-3333-3333-3333-333333333333',
  message_id:'44444444-4444-4444-4444-444444444444',
  text:prompt,inline_code:[]};
const targetKey=createHash('sha256')
  .update(uiAnchorSource(project,[first])).digest('hex');
const sample={project,targetKey,prompt,selectedBefore:selected,
  selectedAfter:selected,firstUnits:[first],
  latestUnits:[{...first},latest],
  oldestReached:true,newestReached:true};
assert(virtualizedRecoveryEligible(prompt,targetKey));
assert.deepEqual(validateVirtualizedHistory(sample),
  {turn_key:latest.turn_key,message_id:latest.message_id,selected});
const bad=[
  [{targetKey:'f'.repeat(64)},/ANCHOR_MISMATCH/],
  [{selectedAfter:'id:foreign-project-chat'},/CONTINUITY_UNVERIFIED/],
  [{selectedBefore:null},/CONTINUITY_UNVERIFIED/],
  [{oldestReached:false},/CONTINUITY_UNVERIFIED/],
  [{newestReached:false},/CONTINUITY_UNVERIFIED/],
  [{firstUnits:[]},/CONTINUITY_UNVERIFIED/],
  [{firstUnits:[{...first,turn_key:'bad'}]},/TURN_ANCHOR/],
  [{latestUnits:[{...first},latest,{...latest,turn_key:'55555555-5555-5555-5555-555555555555'}]},/ORIGINAL_PROMPT_UNVERIFIED/],
  [{latestUnits:[latest,{...first}]},/LATER_TURN_UNVERIFIED/],
  [{latestUnits:[{...first},{...latest,message_id:first.message_id}]},/LATER_TURN_UNVERIFIED/],
  [{latestUnits:[{...first},{...latest,text:'Other response token'}]},/ORIGINAL_PROMPT_UNVERIFIED/],
  [{prompt:'No request token'},/CONTINUITY_UNVERIFIED/],
];
for(const [change,error] of bad)
  assert.throws(()=>validateVirtualizedHistory({...sample,...change}),error);
for(const nonUnique of [
  null,'',targetKey.slice(0,63),'z'.repeat(64)
])assert(!virtualizedRecoveryEligible(prompt,nonUnique));
assert(!virtualizedRecoveryEligible(prompt,targetKey,3));
assert(!virtualizedRecoveryEligible('missing request token\n',targetKey));
console.log('PASS AUTO-F01: virtualized read-only chat history identity, no Send authority');
