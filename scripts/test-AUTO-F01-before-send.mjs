#!/usr/bin/env node
/* UI focus/draft changes immediately before Send must remain proven unsent. */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'alis-pre-click-'));
try {
  const mock=path.join(dir,'playwright.mjs');fs.writeFileSync(mock,'export const chromium={};');
  process.env.ALIS_PLAYWRIGHT_MODULE=pathToFileURL(mock).href;
  const {submitPrompt}=await import('../automation/chat_bridge/desktop_driver.mjs');
  for(const scenario of ['project-left','draft-changed']) {
    let project=true,text='',clicks=0;
    const button={count:async()=>1,nth:()=>button,isVisible:async()=>true,isDisabled:async()=>false,
      evaluate:async fn=>fn({click:()=>{clicks++;}})};
    const empty={count:async()=>0};
    const composer={...button,fill:async s=>{text=s;},innerText:async()=>text,
      evaluate:async fn=>fn({textContent:text})};
    const page={getByRole:(role,q)=>{
      if(role==='textbox')return composer;
      if(role==='button'&&q.name==='Send')return button;
      if(role==='button'&&q.name?.test?.('Project: Automatic Alis'))return project?button:empty;
      return empty;},
      locator:s=>s==='body'?{innerText:async()=>''}:empty,
      waitForTimeout:async()=>{if(scenario==='project-left')project=false;else text='Owner changed this draft';}};
    await assert.rejects(()=>submitPrompt(page,'Exact private input'),error=>{
      assert.equal(error.uiSendAttempted,false);return true;});
    assert.equal(clicks,0,'foreign view or changed draft must never receive Send');
  }
  console.log('PASS: project and complete composer rechecked immediately before the single Send');
}finally{fs.rmSync(dir,{recursive:true,force:true});}
