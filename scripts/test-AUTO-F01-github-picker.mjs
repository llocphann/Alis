#!/usr/bin/env node
// No Desktop connection. Missing/ambiguous mention options cannot press Enter.
import assert from "node:assert/strict";
process.env.ALIS_PLAYWRIGHT_MODULE="data:text/javascript,export const chromium={};";
const {selectGitHubMention}=await import("../automation/chat_bridge/desktop_driver.mjs");
function fixture(matches=0,filteredMatches=matches) {
  const events=[];
  let filtered=false;
  const locator=(count=0)=>({count:async()=>count,nth:()=>({
    isVisible:async()=>true,evaluate:async()=>events.push("picker-click")
  })});
  const page={getByRole:role=>locator(role==="option"?(filtered?filteredMatches:matches):0),
    getByText:()=>locator(),keyboard:{
      insertText:async text=>{events.push("insert:"+text);if(text==="GitHub")filtered=true;},
      press:async key=>{events.push("press:"+key);throw Error("UNSAFE_PICKER_KEYPRESS");}
    }};
  const composer={fill:async text=>events.push("fill:"+text),focus:async()=>events.push("focus")};
  return {page,composer,events};
}
const missing=fixture();
await assert.rejects(()=>selectGitHubMention(missing.page,missing.composer),
  /ALIS_UI_GITHUB_PICKER_UNAVAILABLE/);
assert.deepEqual(missing.events,["fill:","focus","insert:@","insert:GitHub"]);
const filtered=fixture(0,1);
assert.equal(await selectGitHubMention(filtered.page,filtered.composer),"role-click");
assert.equal(filtered.events.filter(x=>x==="picker-click").length,1);
const unique=fixture(1);
assert.equal(await selectGitHubMention(unique.page,unique.composer),"role-click");
assert.equal(unique.events.filter(x=>x==="picker-click").length,1);
assert.ok(!unique.events.some(x=>x.startsWith("press:")));
const ambiguous=fixture(2);
await assert.rejects(()=>selectGitHubMention(ambiguous.page,ambiguous.composer),/ambiguous/);
assert.ok(!ambiguous.events.includes("picker-click"));
assert.ok(!ambiguous.events.some(x=>x.startsWith("press:")));
console.log("PASS: GitHub picker requires one grounded option; no Enter fallback or Send");
