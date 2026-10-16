#!/usr/bin/env node
import assert from 'node:assert/strict';
import {uiAnchorSource,submittedPromptMatches,matchingSubmittedUnit} from '../automation/chat_bridge/ui_turn_anchor.mjs';
const one={turn_key:'12345678-1234-1234-1234-123456789012',message_id:'abcdefab-abcd-abcd-abcd-abcdefabcdef',text:'GitHub\n task exact body\n … Show more',expand_control:true};
const prompt='[$github](app://connector_76869538009648d5b282a4bb21c3d157)\n\ntask exact body';
assert(submittedPromptMatches(one,prompt));
assert(!submittedPromptMatches({...one,text:one.text.replace('exact','changed')},prompt));
assert(!submittedPromptMatches({...one,expand_control:false},prompt));
const source=uiAnchorSource('Automatic Alis',[one],prompt);
assert(source.startsWith('local-ui-user-turn-v1:'));
assert.equal(uiAnchorSource('Automatic Alis',[one]),source);
for(const bad of [[],[one,one],[{...one,turn_key:'title'}],[{...one,message_id:'https://example.invalid'}]])
  assert.throws(()=>uiAnchorSource('Automatic Alis',bad));
assert.throws(()=>uiAnchorSource('Automatic Alis',[one],prompt+' changed'));
assert.throws(()=>matchingSubmittedUnit([one,one],prompt));
assert.throws(()=>matchingSubmittedUnit([one],prompt+' changed'));
assert.equal(matchingSubmittedUnit([one],prompt).index,0);
console.log('PASS: full prompt match and local user-turn continuity, no native conversation authority');
