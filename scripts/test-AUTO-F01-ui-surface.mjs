#!/usr/bin/env node
import assert from "node:assert/strict";
import {pinnedUiWindow,checkedUiWindowTarget} from "../automation/chat_bridge/ui_surface.mjs";
const first="a".repeat(32),second="b".repeat(32);
function page(target,url="app://-/index.html") {
  const calls=[];
  const p={url:()=>url,context:()=>({newCDPSession:async()=>({
    send:async name=>{calls.push(name);return {targetInfo:{targetId:target}};},
    detach:async()=>calls.push("detach")
  })}),calls};
  return p;
}
const owner=page(first),bot=page(second),browser={contexts:()=>[{pages:()=>[owner,bot]}]};
assert.equal(await pinnedUiWindow(browser,second),bot);
assert.deepEqual(owner.calls,["Target.getTargetInfo","detach"]);
assert.deepEqual(bot.calls,["Target.getTargetInfo","detach"]);
await assert.rejects(()=>pinnedUiWindow(browser,"c".repeat(32)),/OWNED_WINDOW_UNAVAILABLE/);
await assert.rejects(()=>pinnedUiWindow({contexts:()=>[{pages:()=>[page(second),page(second)]}]},second),/OWNED_WINDOW_UNAVAILABLE/);
await assert.rejects(()=>pinnedUiWindow({contexts:()=>[{pages:()=>[page(second,"https://example.invalid")]}]},second),/OWNED_WINDOW_UNAVAILABLE/);
for(const invalid of [null,"","a".repeat(31),"a".repeat(32)+"\n","../../state",42])
  assert.throws(()=>checkedUiWindowTarget(invalid),/WINDOW_TARGET_INVALID/);
console.log("PASS: owned UI window pin, no fallback to owner/foreign/closed windows");
