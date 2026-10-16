#!/usr/bin/env node
/* Offline DOM replicas: no CDP, service, Send, keyboard or owner state. */
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {uiAnchorSource} from '../automation/chat_bridge/ui_turn_anchor.mjs';
process.env.ALIS_PLAYWRIGHT_MODULE='data:text/javascript,export const chromium={};';
process.env.ALIS_CHATGPT_UI_TARGET_ID='f'.repeat(32);
const {waitForSubmittedPrompt}=await import('../automation/chat_bridge/desktop_driver.mjs');
const forbidden=()=>{throw Error('UI_MUTATION_FORBIDDEN');};
function fixture() {
  const first={text:'Original input',turn_key:'11111111-1111-1111-1111-111111111111',
    message_id:'22222222-2222-2222-2222-222222222222',assistant:'Old reply\nALIS_LOOP:CONTINUE',actions:1};
  const pending={text:'Exact pending input',turn_key:'33333333-3333-3333-3333-333333333333',
    message_id:'44444444-4444-4444-4444-444444444444',assistant:'Original final\nALIS_LOOP:DONE',actions:1};
  let rows=[first,pending],busy=false;
  const node=u=>({innerText:u.text,getAttribute:k=>k==='data-chatgpt-search-message-ids'?u.message_id:null,
    querySelectorAll:()=>[],closest:()=>({getAttribute:()=>u.turn_key,
      querySelectorAll:s=>s==='button'?(u.actions?[{getAttribute:()=> 'Copy',closest:()=>null}]:[]):
        u.assistant?[{innerText:u.assistant}]:[]})});
  const locator=items=>({count:async()=>items.length,nth:i=>locator([items[i]]),
    isVisible:async()=>true,evaluate:async fn=>fn(node(items[0])),
    click:forbidden,fill:forbidden,press:forbidden});
  const selected={count:async()=>1,isVisible:async()=>true,getAttribute:async()=> 'Private fixture chat'};
  const page={locator:s=>{
      assert.equal(s,'[data-chatgpt-search-unit-key$=":user"]');return locator(rows);},
    getByRole:(role,q)=>{
      if(role==='list')return {locator:()=>selected};
      if(role==='button'&&q.name?.test?.('Project: Automatic Alis'))return selected;
      if(role==='button'&&q.name?.test?.('Stop'))return locator(busy?[{}]:[]);
      throw Error('Global response counts must not be queried');
    },keyboard:{insertText:forbidden}};
  // Project guard uses nth for its visibility check.
  selected.nth=()=>selected;
  const key=createHash('sha256').update(uiAnchorSource('Automatic Alis',[first])).digest('hex');
  return {page,key,first,pending,setRows:v=>{rows=v;},setBusy:v=>{busy=v;}};
}
const ready=fixture();
const final=await waitForSubmittedPrompt(ready.page,'Exact pending input',{targetKey:ready.key});
assert.equal(final.completed,true);assert.equal(final.response.markerCount,1);
assert.equal(final.response.text,'Original final\nALIS_LOOP:DONE');
const later=fixture();later.setRows([later.first,later.pending,{...later.pending,text:'Later user input',
  turn_key:'55555555-5555-5555-5555-555555555555',message_id:'66666666-6666-6666-6666-666666666666'}]);
await assert.rejects(()=>waitForSubmittedPrompt(later.page,'Exact pending input',{targetKey:later.key}),/LATER_USER_TURN/);
const wrong=fixture();
await assert.rejects(()=>waitForSubmittedPrompt(wrong.page,'Exact pending input',{targetKey:'b'.repeat(64)}),/TARGET_CHANGED/);
const busy=fixture();busy.setBusy(true);
await assert.rejects(()=>waitForSubmittedPrompt(busy.page,'Exact pending input',{
  targetKey:busy.key,timeoutMs:8,pollMs:0}),/TIMEOUT_NO_RESEND/);
const missing=fixture();missing.setRows([missing.first]);
await assert.rejects(()=>waitForSubmittedPrompt(missing.page,'Exact pending input',{
  targetKey:missing.key,timeoutMs:8,pollMs:0}),/TIMEOUT_NO_RESEND/);
const initial=fixture();initial.setRows([initial.first]);
assert.equal((await waitForSubmittedPrompt(initial.page,'Original input')).completed,true);
console.log('PASS: exact submitted-turn wait survives global-count changes and rejects later/foreign/missing/busy responses without Send');
