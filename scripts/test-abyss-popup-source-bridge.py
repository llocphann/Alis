#!/usr/bin/env python3
"""The hover corridor is source-sized, painted, and outside source controls."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
geometry = (root/"modules/abyss/looks/AbyssGeometry.js").read_text()
program = geometry + r'''
{
const assert=require("node:assert/strict");
const width=1000,height=800,insets={left:48,top:48,right:48,bottom:48};
const cases=[
 ["top",{x:300,y:8,width:100,height:32},{x:200,y:48,width:300,height:200},{x:300,y:40,width:100,height:8}],
 ["bottom",{x:300,y:760,width:100,height:32},{x:200,y:552,width:300,height:200},{x:300,y:752,width:100,height:8}],
 ["left",{x:8,y:300,width:32,height:100},{x:48,y:200,width:200,height:300},{x:40,y:300,width:8,height:100}],
 ["right",{x:960,y:300,width:32,height:100},{x:752,y:200,width:200,height:300},{x:952,y:300,width:8,height:100}]
];
let pixels=0;
for(const [edge,source,body,expected] of cases){
 const bridge=popupSourceBridge(source,body,width,height,insets,edge);
 assert.deepEqual(bridge,expected,edge+" exact source-only corridor");
 for(let x=bridge.x+.5;x<bridge.x+bridge.width;x++)
  for(let y=bridge.y+.5;y<bridge.y+bridge.height;y++){
   assert(distance(x,y,width,height,insets,34,[],24,20)<=0,"corridor captures unpainted workspace");
   assert(!rectContains(source,x,y),"corridor captures a source control");
   assert(!rectContains(body,x,y),"negative control already owns corridor");
   pixels++;
  }
 // Closing/unready hosts supply an empty body, and no source is a default.
 assert.equal(popupSourceBridge(source,{x:0,y:0,width:0,height:0},width,height,insets,edge).width,0);
 assert.equal(popupSourceBridge(null,body,width,height,insets,edge).width,0);
 assert.equal(popupSourceBridge({...source,width:NaN},body,width,height,insets,edge).width,0);
 assert.equal(popupSourceBridge(source,body,width,height,{...insets,[edge]:0},edge).width,0);
}
const source={x:300,y:8,width:100,height:32};
assert.deepEqual(popupSourceBridge(source,{x:350,y:48,width:30,height:50},width,height,insets,"top"),
 {x:350,y:40,width:30,height:8},"only the overlapping source tangent belongs to this popup");
assert.equal(popupSourceBridge(source,{x:500,y:48,width:100,height:50},width,height,insets,"top").width,0);
assert.equal(popupSourceBridge(source,{x:300,y:16,width:100,height:50},width,height,
 {...insets,top:16},"top").width,0,"protruding modules need no extra corridor");
assert.equal(popupSourceBridge(source,{x:300,y:48,width:100,height:50},width,height,insets,"invalid").width,0);
console.log("POPUP_SOURCE_BRIDGE_PASS",pixels,"painted pixel centers; four edges, clipping and empty/invalid inputs");
}
'''
subprocess.run(["node"], input=program, text=True, check=True, timeout=15)
