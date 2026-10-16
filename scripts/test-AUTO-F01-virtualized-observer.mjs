#!/usr/bin/env node
/* Read-only simulated virtualized Project thread; no Desktop/CDP/network. */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {uiAnchorSource} from '../automation/chat_bridge/ui_turn_anchor.mjs';
const home=fs.mkdtempSync(path.join(os.tmpdir(),'alis-history-observer-'));
try {
  const mock=path.join(home,'playwright.mjs');
  fs.writeFileSync(mock,'export const chromium={connectOverCDP:()=>{throw Error("NO_CDP");}};');
  process.env.ALIS_PLAYWRIGHT_MODULE=pathToFileURL(mock).href;
  process.env.ALIS_CHATGPT_UI_TARGET_ID='a'.repeat(32);
  const {observeSubmittedPrompt,resumeUiChat,uiOnlyTurnIdentity}=await import('../automation/chat_bridge/desktop_driver.mjs');
  const first={turn_key:'11111111-1111-1111-1111-111111111111',
    message_id:'22222222-2222-2222-2222-222222222222',
    text:'Original submitted task',inline_code:[]};
  const prompt='Some Cloudbot diagnostic\nAlis UI request token: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\n';
  const latest={turn_key:'33333333-3333-3333-3333-333333333333',
    message_id:'44444444-4444-4444-4444-444444444444',
    text:prompt,inline_code:[],assistant:'Diagnostic result\nALIS_LOOP:CONTINUE',actions:1};
  const key=createHash('sha256').update(uiAnchorSource('Automatic Alis',[first])).digest('hex');
  let mode='newest',selector='original-ui-chat-id-12345',navigation=0;
  let changedChatOnOldest=false,stopGeneration=false,alterFirst=false,extraUser=false;
  let metadata=false,reverse=true,rowConnected=true,hostConnected=true;
  let replacedRow=false,foreignHost=false,detachOnOldest=false,replaceOnOldest=false;
  const forbid=()=>{throw Error('SEND_OR_EDIT_FORBIDDEN');};
  class Handle {
    constructor(value){this.value=value;}
    async evaluate(fn,arg){return fn(this.value,arg instanceof Handle?arg.value:arg);}
    async evaluateHandle(fn){return new Handle(fn(this.value));}
    asElement(){return this.value?this:null;}
    async dispose(){}
  }
  const viewport={
    parentElement:null,scrollHeight:1000,clientHeight:300,firstElementChild:{},
    get isConnected(){return hostConnected;},
    get scrollTop(){return mode==='oldest'?(reverse?-700:0):(reverse?0:700);},
    set scrollTop(v){
      mode=reverse?(v<0?'oldest':'newest'):(v>0?'newest':'oldest');
      if(mode==='oldest'){
        if(changedChatOnOldest)selector='foreign-ui-chat-id-12345';
        if(detachOnOldest)rowConnected=false;
        if(replaceOnOldest)replacedRow=true;
      }
    }
  };
  const fakeDocument={body:{},querySelector:()=>({parentElement:viewport})};
  viewport.parentElement=fakeDocument.body;
  globalThis.document=fakeDocument;
  globalThis.getComputedStyle=el=>el===viewport?{overflowY:'scroll',flexDirection:reverse?'column-reverse':'column'}:
    {overflowY:'visible',flexDirection:'row'};
  const currentRows=()=>mode==='oldest'
    ?[{...(alterFirst?{...first,turn_key:'99999999-9999-9999-9999-999999999999'}:first)}]
    :extraUser?[latest,{...first}]:[latest];
  const node=u=>({
    innerText:u.text,
    parentElement:foreignHost?fakeDocument.body:viewport,
    getAttribute:k=>k==='data-chatgpt-search-message-ids'?u.message_id:null,
    querySelectorAll:()=>[],
    closest:q=>q==='[data-turn-key]'?{
      getAttribute:()=>u.turn_key,
      querySelectorAll:x=>x==='button'
        ?(u.actions?[{getAttribute:()=> 'Copy',closest:()=>null}]:[])
        :u.assistant?[{innerText:u.assistant}]:[]
    }:null
  });
  const locator=()=>({
    count:async()=>currentRows().length,
    nth:i=>({
      isVisible:async()=>true,
      evaluate:async(fn,arg)=>fn(node(currentRows()[i]),arg instanceof Handle?arg.value:arg),
      evaluateHandle:async fn=>new Handle(fn(node(currentRows()[i]))),
      elementHandle:async()=>new Handle(node(currentRows()[i])),
      click:forbid,fill:forbid
    })
  });
  const selectedNode={
    get isConnected(){return rowConnected;},
    getAttribute:k=>k==='data-chat-id'?(metadata?selector:null)
      :k==='aria-label'?selector:k==='aria-current'?'page':null,
    closest:()=>null,querySelector:()=>null
  };
  const selected={
    count:async()=>1,isVisible:async()=>true,
    nth:()=>({isVisible:async()=>true}),
    getAttribute:async key=>key==='aria-label'?'Cloudbot original chat':null,
    elementHandle:async()=>new Handle(replacedRow?{...selectedNode}:selectedNode),
    evaluate:async(fn,arg)=>fn(replacedRow?{...selectedNode}:selectedNode,
                             arg instanceof Handle?arg.value:arg)
  };
  const candidate={
    count:async()=>1,isVisible:async()=>true,
    nth:()=>({isVisible:async()=>true}),
    click:async()=>{navigation++;},
    evaluate:forbid
  };
  const page={
    locator:q=>{
      assert.equal(q,'[data-chatgpt-search-unit-key$=":user"]');return locator();},
    evaluate:async(fn,arg)=>fn(arg),
    getByRole:(role,q)=>{
      if(role==='button')return {
        count:async()=>stopGeneration&&/stop/i.test('Stop')&&q.name.test('Stop')?1:0,
        nth:i=>({isVisible:async()=>true})
      };
      assert.equal(role,'list');
      assert.equal(q.name,'Chats in Automatic Alis');
      return {count:async()=>1,locator:()=>selected,getByRole:()=>candidate};
    },
    keyboard:{insertText:forbid}
  };
  const good=await observeSubmittedPrompt(page,prompt,{targetKey:key});
  assert.equal(good.completed,true);
  assert.equal(good.ui_target_key,key);
  assert.equal(good.response.extractionSignal,'submitted-user-turn-assistant');
  assert.equal(good.response.markerCount,1);
  assert.equal(navigation,0);
  // The real desktop has no sidebar conversation ID. A label is never
  // substituted for the saved first-turn key or the actual DOM handles.
  for(const direction of [false,true]){
    mode='newest';reverse=direction;
    assert.equal((await observeSubmittedPrompt(page,prompt,{targetKey:key})).completed,true);
  }
  metadata=true;mode='newest';
  assert.equal((await observeSubmittedPrompt(page,prompt,{targetKey:key})).completed,true);
  metadata=false;
  mode='newest';
  await resumeUiChat(page,'Cloudbot original chat',{targetKey:key});
  assert.equal(mode,'oldest');
  assert.equal(createHash('sha256').update(await uiOnlyTurnIdentity(page)).digest('hex'),key);
  mode='newest';alterFirst=true;
  await assert.rejects(()=>resumeUiChat(page,'Cloudbot original chat',{targetKey:key}),
                       /RESUME_TARGET_MISMATCH/);
  alterFirst=false;
  mode='newest';
  await resumeUiChat(page,'Cloudbot original chat',
                     {targetKey:key,readOnlyHistory:true});
  assert.equal(navigation,3);
  mode='newest';changedChatOnOldest=true;
  await assert.rejects(()=>observeSubmittedPrompt(page,prompt,{targetKey:key}),
                       /HISTORY_CHAT_CHANGED/);
  changedChatOnOldest=false;selector='original-ui-chat-id-12345';
  for(const fault of ['detach','replace']){
    mode='newest';detachOnOldest=fault==='detach';replaceOnOldest=fault==='replace';
    await assert.rejects(()=>observeSubmittedPrompt(page,prompt,{targetKey:key}),/HISTORY_CHAT_CHANGED/);
    rowConnected=true;replacedRow=false;detachOnOldest=false;replaceOnOldest=false;
  }
  mode='newest';hostConnected=false;
  await assert.rejects(()=>observeSubmittedPrompt(page,prompt,{targetKey:key}),/HISTORY_CHAT_CHANGED/);
  hostConnected=true;
  mode='newest';foreignHost=true;
  await assert.rejects(()=>observeSubmittedPrompt(page,prompt,{targetKey:key}),/HISTORY_SCROLL_UNVERIFIED/);
  foreignHost=false;
  mode='newest';alterFirst=true;
  await assert.rejects(()=>observeSubmittedPrompt(page,prompt,{targetKey:key}),
                       /HISTORY_ANCHOR_MISMATCH/);
  alterFirst=false;mode='newest';extraUser=true;
  await assert.rejects(()=>observeSubmittedPrompt(page,prompt,{targetKey:key}),
                       /HISTORY_LATER_TURN_UNVERIFIED/);
  extraUser=false;mode='newest';
  await assert.rejects(()=>observeSubmittedPrompt(page,
       'No saved unique request token',{targetKey:key}),/TARGET_CHANGED_NO_SEND/);
  assert.equal(selector,'original-ui-chat-id-12345');
  console.log('PASS AUTO-F01: mocked virtualized scroll bound to one chat, observer-only, no sends');
} finally {
  delete globalThis.document;
  delete globalThis.getComputedStyle;
  fs.rmSync(home,{recursive:true,force:true});
}
