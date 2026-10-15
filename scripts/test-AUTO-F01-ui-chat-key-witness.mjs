#!/usr/bin/env node
/* Mock-only AUTO-F01 post-send key witness. Never connects to Desktop. */
import assert from "node:assert/strict";
import {witnessUiChatKey} from
  "../automation/chat_bridge/ui_chat_key_witness.mjs";
const ID_A="1234567890abcdef1234567890abcdef";
const ID_B="abcdef1234567890abcdef1234567890";
let mutation=0;
const makePage=({list=true,global=true,project=true,
  changing=false,duplicate=false,identityAbsent=false}={})=>{
  let sampled=0;
  const node=id=>({visible:true,id});
  const current=()=>sampled===0?ID_A:changing?ID_B:ID_A;
  const loc=(source,kind="none")=>({
    count:async()=>source().length,
    nth:i=>loc(()=>source()[i]?[source()[i]]:[],kind),
    isVisible:async()=>source()[0]?.visible===true,
    locator:s=>kind==="list"&&
      s==='[role="button"][aria-current="page"]'
      ?loc(()=>project?[node(current())]:[],"selected"):loc(()=>[]),
    evaluate:fn=>{
      const id=source()[0]?.id;
      const element={
        getAttribute:a=>a==="data-chat-id"&&!identityAbsent?id:null,
        closest:()=>null,querySelector:()=>null
      };
      return fn(element);
    },
    fill:()=>{mutation++;throw Error("SEND_FORBIDDEN")},
    click:()=>{mutation++;throw Error("CLICK_FORBIDDEN")}
  });
  return {
    url:()=>"app://-/index.html",
    page:{
      url:()=>"app://-/index.html",
      locator:s=>s==='[aria-current="page"]'
        ?loc(()=>global?duplicate?[node(current()),node(current())]:
          [node(current())]:[],"global"):loc(()=>[]),
      getByRole:(role,opt={})=>role==="list"&&opt.name==="Chats in Automatic Alis"
        ?loc(()=>list?[{visible:true}]:[],"list"):loc(()=>[])
    },
    advance:()=>{sampled++;}
  };
};
async function inspect(opts={}){
  const p=makePage(opts);
  const result=await witnessUiChatKey(p.page,"Automatic Alis",{
    delay:async()=>p.advance()
  });
  assert.equal(result.ui_scheduler_authorized,false);
  assert.equal(result.project_membership_server_attested,false);
  assert.equal(JSON.stringify(result).includes(ID_A),false);
  assert.equal(JSON.stringify(result).includes(ID_B),false);
  return result;
}
let x=await inspect();
assert.equal(x.diagnosis,"PROJECT_CHAT_KEY_STABLE_LOCAL_ONLY");
assert.equal(x.project_chat_key_equal_across_samples,true);
assert.equal(x.global_chat_key_equal_across_samples,true);
x=await inspect({list:false,project:false});
assert.equal(x.diagnosis,"GLOBAL_CHAT_KEY_STABLE_PROJECT_UNVERIFIED");
assert.equal(x.project_chat_key_equal_across_samples,false);
assert.equal(x.global_chat_key_equal_across_samples,true);
x=await inspect({list:false,project:false,changing:true});
assert.equal(x.diagnosis,"CHAT_KEY_MISSING_OR_CHANGED");
assert.equal(x.global_chat_key_equal_across_samples,false);
x=await inspect({list:false,project:false,duplicate:true});
assert.equal(x.diagnosis,"CHAT_KEY_MISSING_OR_CHANGED");
x=await inspect({identityAbsent:true});
assert.equal(x.diagnosis,"CHAT_KEY_MISSING_OR_CHANGED");
x=await inspect({list:false,global:false,project:false});
assert.equal(x.diagnosis,"CHAT_KEY_MISSING_OR_CHANGED");
assert.equal(mutation,0);
console.log("PASS AUTO-F01 post-send UI chat-key witness: raw equality, redacted and no queue authority");
