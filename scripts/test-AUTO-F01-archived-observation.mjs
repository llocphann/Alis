#!/usr/bin/env node
/* Synthetic archived UI. No account/CDP connection or UI mutations. */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {uiAnchorSource} from '../automation/chat_bridge/ui_turn_anchor.mjs';

const root=fs.mkdtempSync(path.join(os.tmpdir(),'alis-archive-observe-'));
try {
  const mock=path.join(root,'playwright.mjs');
  fs.writeFileSync(mock,'export const chromium={connectOverCDP:()=>{throw Error("NO_CDP");}};');
  process.env.ALIS_PLAYWRIGHT_MODULE=pathToFileURL(mock).href;
  const {observeSubmittedPrompt}=await import('../automation/chat_bridge/desktop_driver.mjs');
  const a={turn_key:'11111111-1111-1111-1111-111111111111',message_id:'22222222-2222-2222-2222-222222222222',text:'Original input',visible:true};
  const b={turn_key:'33333333-3333-3333-3333-333333333333',message_id:'44444444-4444-4444-4444-444444444444',text:'Pending input',visible:true,assistant:'Partial source report',actions:0};
  let rows=[{...b,visible:false},a,b],busy=false;
  const forbidden=()=>{throw Error('UI_MUTATION_FORBIDDEN');};
  const node=u=>({innerText:u.text,
    getAttribute:key=>key==='data-chatgpt-search-message-ids'?u.message_id:null,
    querySelectorAll:()=>[],
    closest:()=>({getAttribute:()=>u.turn_key,querySelectorAll:selector=>
      selector==='button'?(u.actions?[{getAttribute:()=> 'Copy',closest:()=>null}]:[]):
        u.assistant?[{innerText:u.assistant}]:[]})});
  const locator=items=>({count:async()=>items.length,nth:n=>locator([items[n]]),
    isVisible:async()=>items[0].visible,evaluate:async fn=>fn(node(items[0])),
    click:forbidden,fill:forbidden,press:forbidden});
  const page={locator:selector=>{
      assert.equal(selector,'[data-chatgpt-search-unit-key$=":user"]');return locator(rows);},
    getByRole:(role,q)=>{
      if(role==='button'&&q.name instanceof RegExp&&q.name.test('Stop'))
        return locator(busy?[{visible:true}]:[]);
      throw Error('PROJECT_GUARD_REQUIRED');},keyboard:{insertText:forbidden}};
  const key=createHash('sha256').update(uiAnchorSource('Automatic Alis',[a])).digest('hex');
  const options={targetKey:key,archivedReadOnly:true};
  const partial=await observeSubmittedPrompt(page,'Pending input',options);
  assert.equal(partial.completed,false);
  assert.equal(partial.delivery_observed,true);
  assert.equal(partial.idle_observed,true);
  assert.equal(partial.response.markerCount,0);
  assert.equal(partial.ui_chat_label,null);
  await assert.rejects(()=>observeSubmittedPrompt(page,'Pending input',{archivedReadOnly:true}),/ORIGINAL_TARGET/);
  await assert.rejects(()=>observeSubmittedPrompt(page,'Pending input',{...options,targetKey:'f'.repeat(64)}),/TARGET_CHANGED/);
  await assert.rejects(()=>observeSubmittedPrompt(page,'Changed input',options),/NOT_UNIQUE/);
  busy=true;assert.equal((await observeSubmittedPrompt(page,'Pending input',options)).delivery_observed,undefined);busy=false;
  rows.push({...b,visible:true});
  await assert.rejects(()=>observeSubmittedPrompt(page,'Pending input',options),/NOT_UNIQUE/);
  rows.pop();
  const repeated={...b,turn_key:'55555555-5555-5555-5555-555555555555',
    message_id:'66666666-6666-6666-6666-666666666666'};
  rows.push(repeated);
  await assert.rejects(()=>observeSubmittedPrompt(page,'Pending input',options),/NOT_UNIQUE/);
  assert.equal((await observeSubmittedPrompt(page,'Pending input',{
    ...options,expectedUserCount:3})).delivery_observed,true);
  await assert.rejects(()=>observeSubmittedPrompt(page,'Pending input',{
    ...options,expectedUserCount:2}),/UNEXPECTED_USER_TURN_COUNT/);
  repeated.message_id=b.message_id;
  await assert.rejects(()=>observeSubmittedPrompt(page,'Pending input',{
    ...options,expectedUserCount:3}),/UNEXPECTED_USER_TURN_COUNT/);
  rows.pop();
  await assert.rejects(()=>observeSubmittedPrompt(page,'Pending input',{targetKey:key}),/PROJECT_GUARD_REQUIRED/);
  b.assistant='Verified source report.\nALIS_LOOP:DONE';b.actions=1;
  assert.equal((await observeSubmittedPrompt(page,'Pending input',options)).completed,true);
  console.log('PASS: visible-only archived original input, idle interruption, strict final and no UI mutations');
} finally {fs.rmSync(root,{recursive:true,force:true});}
