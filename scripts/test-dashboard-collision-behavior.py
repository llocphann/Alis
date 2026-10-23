#!/usr/bin/env python3
"""Run the production collision functions against packed and migrated layouts."""
from pathlib import Path
import json, re, subprocess
root = Path(__file__).resolve().parents[1]
source = (root / "modules/dashboard/DashboardCanvas.qml").read_text()
functions = []
for match in re.finditer(r"    function (\w+)\([^\{]*\) \{", source):
    start = source.index("{", match.start())
    depth, end = 1, start + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    functions.append("root." + match[1] + " = " + source[match.start():end].strip() + ";")
program = "const assert=require('node:assert/strict');const root={collisionGap:8};const canvas={width:1000,height:700};\n" + "\n".join(functions) + r"""
// The real QML root owns the viewport dimensions used by _minimumSize.
// Follow every fixture resize rather than leaving those Item properties absent.
Object.defineProperties(root, {
 width: {get:()=>canvas.width}, height: {get:()=>canvas.height}
});
const rect=(x,y,width,height)=>({x,y,width,height});
const clone=value=>JSON.parse(JSON.stringify(value));
let baseline={notes:rect(30,30,240,160),system:rect(650,30,260,180),clock:rect(650,100,200,100)};
root.visibleIds=Object.keys(baseline);
const before=clone(baseline);
assert(root._layoutHasOverlap(baseline));
let result=root._resolveFeasibleLayout('notes',baseline.notes,rect(30,30,340,220),baseline,false,true);
assert.equal(result.notes.width,340,'unrelated old overlap must not freeze resizing');
assert.deepEqual(result.system,baseline.system);assert.deepEqual(result.clock,baseline.clock);
assert.deepEqual(baseline,before,'immutable interaction snapshot');
assert(!root._layoutHasOverlap(result,baseline),'only unchanged existing overlap is tolerated');
result.clock.x-=1;
assert(root._layoutHasOverlap(result,baseline),'changing an overlapping pair does not waive collisions');
canvas.width=640;canvas.height=240;
baseline={notes:rect(0,0,300,240),system:rect(308,0,332,240)};
root.visibleIds=Object.keys(baseline);
for(const desired of [rect(200,0,300,240),rect(308,0,300,240),rect(0,0,500,240)]) {
    for(const resize of [false,true]) {
        result=root._resolveFeasibleLayout('notes',baseline.notes,desired,baseline,false,resize);
        assert(!root._layoutHasOverlap(result),'no-room move/resize never introduces overlap');
        for(const id of root.visibleIds) {
            assert.equal(result[id].height,baseline[id].height);
            assert(result[id].x>=0 && result[id].x+result[id].width<=canvas.width+.001);
        }
    }
}
canvas.width=1000;canvas.height=700;
baseline={notes:rect(0,0,240,160),system:rect(300,0,260,180),clock:rect(700,0,200,100)};
root.visibleIds=Object.keys(baseline);
result=root._resolveFeasibleLayout('notes',baseline.notes,rect(300,0,240,160),baseline,false,false);
assert.equal(result.notes.x,300,'insertion works when space exists');
assert(!root._layoutHasOverlap(result));
for(const id of root.visibleIds) {assert.equal(result[id].width,baseline[id].width);assert.equal(result[id].height,baseline[id].height);}
root.responsiveWorkspace=true;
for(const desired of [rect(300,0,240,160),rect(0,0,700,300)]) {
 result=root._resolveFeasibleLayout('notes',baseline.notes,desired,baseline,true,false);
 assert(!root._layoutHasOverlap(result),'finite Dashboard rejects occupied space');
 assert.deepEqual(result.system,baseline.system,'other cards never shuffle');
 assert.deepEqual(result.clock,baseline.clock,'far cards never shuffle');
}
console.log('PASS: Dashboard collision rollback, free insertion, local resize and migrated overlap isolation');
"""
subprocess.run(["node", "-e", program], check=True, cwd=root)
