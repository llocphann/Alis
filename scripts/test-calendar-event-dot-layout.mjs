#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import {fileURLToPath} from "node:url";
const file=fileURLToPath(new URL("../modules/common/widgets/CalendarEventDotLayout.js", import.meta.url));
const ctx=vm.createContext({Number,Math,Array});
vm.runInContext(fs.readFileSync(file,"utf8"),ctx,{filename:file});
const colors=Array.from({length:30},(_,i)=>"event-"+i);
let checks=0;
function eq(a,b,msg) {assert.equal(JSON.stringify(a),JSON.stringify(b),msg);checks++}
for (const cap of [0,1,2,3,4,5]) for (const count of [0,1,2,3,4,5,6,7,8,9,10,11,12,13,30]) {
    const per=Math.min(3,cap),out=ctx.layoutDots(count,cap,colors,"default");
    eq(out.edges.map(x=>x.length),[0,1,2,3].map(i=>Math.max(0,Math.min(per,count-i*per))),"per-edge order");
    eq(out.edges.flat(),colors.slice(0,Math.min(count,per*4)),"ordered colors");
    eq(out.overflow,per>0 && count>per*4,"overflow");
}
for (const [count,want] of [[3,[3,0,0,0]],[4,[3,1,0,0]],[6,[3,3,0,0]],[7,[3,3,1,0]],[9,[3,3,3,0]],[10,[3,3,3,1]],[12,[3,3,3,3]],[13,[3,3,3,3]]])
    eq(ctx.layoutDots(count,3,colors,"default").edges.map(x=>x.length),want,"threshold "+count);
const partial=ctx.layoutDots(5,3,["red","green"],"accent");
eq(partial.edges[0],["red","green","accent"],"fallback Bottom");
eq(partial.edges[1],["accent","accent"],"fallback Right");
eq(ctx.layoutDots(20,0,colors,"accent").overflow,false,"no overflow when disabled");
eq(ctx.edgeLimit(-2),0,"invalid low limit");
eq(ctx.edgeLimit(100),3,"high limit capped");
console.log("CALENDAR_EVENT_DOT_LAYOUT_PASS: "+checks+" assertions");
