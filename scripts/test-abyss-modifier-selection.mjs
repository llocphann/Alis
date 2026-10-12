import fs from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const source=fs.readFileSync(new URL("../modules/abyss/looks/AbyssSelection.js",import.meta.url),"utf8");
const ctx=vm.createContext({});
vm.runInContext(source,ctx);
const canon=v=>JSON.parse(JSON.stringify(v));
let checks=0;
function expect(actual,expected,label) {
    checks++;
    assert.deepEqual(canon(actual),expected,label);
}
const draft=[
    {id:"z",edge:"bottom",position:.2},
    {id:"b",edge:"top",position:.8},
    {id:"x",edge:"left",position:.2},
    {id:"a",edge:"top",position:.1},
    {id:"c",edge:"top",position:.5}
];
const order=canon(ctx.orderedIds(draft));
expect(order,["a","c","b","x","z"],"edge/date-independent spatial order");
let state={ids:[],primary:"",anchor:""};
const action=(id,ctrl=false,shift=false)=>state=canon(ctx.select(state.ids,state.primary,state.anchor,id,order,ctrl,shift));
action("a");
expect(state,{ids:["a"],primary:"a",anchor:"a"},"normal click selects one without a toggle");
action("c");
expect(state,{ids:["c"],primary:"c",anchor:"c"},"normal click replaces previous selection");
action("b",true);
expect(state,{ids:["c","b"],primary:"b",anchor:"b"},"Ctrl-click adds");
action("c",true);
expect(state,{ids:["b"],primary:"b",anchor:"b"},"Ctrl-click removes non-primary");
action("b",true);
expect(state,{ids:[],primary:"",anchor:""},"Ctrl-click removes last selection");
action("a");
action("b",false,true);
expect(state,{ids:["a","c","b"],primary:"b",anchor:"a"},"Shift-click selects entire visual interval");
action("x",false,true);
expect(state,{ids:["a","c","b","x"],primary:"x",anchor:"a"},"Shift-click keeps initial anchor");
action("c");
action("x",true,true);
expect(state,{ids:["c","b","x"],primary:"x",anchor:"c"},"Ctrl+Shift-click extends existing set");
action("z");
expect(state,{ids:["z"],primary:"z",anchor:"z"},"ordinary click collapses multiple selection");
action("missing",true,true);
expect(state,{ids:["z"],primary:"z",anchor:"z"},"stale item ignored");
expect(canon(draft),[
    {id:"z",edge:"bottom",position:.2},{id:"b",edge:"top",position:.8},
    {id:"x",edge:"left",position:.2},{id:"a",edge:"top",position:.1},
    {id:"c",edge:"top",position:.5}
],"selection does not mutate draft");
const editor=fs.readFileSync(new URL("../modules/abyss/AbyssEdgeEditor.qml",import.meta.url),"utf8");
for(const [match,label] of [
  ['import "looks/AbyssSelection.js" as ModuleSelection',"shared helper imported"],
  ['onPressed:mouse=>{',"pointer handler present"],
  ['const ctrl=!!(mouse.modifiers & Qt.ControlModifier)',"Ctrl pointer modifier present"],
  ['const shift=!!(mouse.modifiers & Qt.ShiftModifier)',"Shift pointer modifier present"],
  ['root.select(handle.modelData,ctrl,shift)',"pointer directly selects without toggle"],
  ['root.select(handle.modelData,!!(event.modifiers & Qt.ControlModifier)',"keyboard accessible modifier selection"],
  ['readonly property bool multiSelect: targetIds.length>1',"multi status inferred"],
  ['selectedIds=ModuleSelection.orderedIds(draft)',"Ctrl+A starts without toggle"]
]) {checks++;assert.ok(editor.includes(match),label)}
checks++;
assert.ok(!editor.includes("setMultiSelection(") && !editor.includes('objectName:"abyssMultiSelection"'),
    "obsolete select-mode toggle remains in editor");
console.log("ABYSS_MODIFIER_SELECTION_PASS",checks);
