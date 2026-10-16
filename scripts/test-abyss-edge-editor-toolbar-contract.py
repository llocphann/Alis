#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
text = (root / "modules/abyss/AbyssEdgeEditor.qml").read_text()

required = [
    'property string toolbarEdge: "bottom"',
    'function toolbarFootprint(edge): var',
    'editorBody.targetRecord?.content',
    'Geometry.panel(width,height,edgeInsets,edge,',
    'function bestToolbarEdge(): string',
    'Placement.toolbarEdgeForRects(toolbarEdge,footprints,',
    'moduleLayer.layoutRecords,previewRects)',
    'function scheduleToolbarRelocation(): void',
    'function relocateToolbar(): void',
    'onEditingEdgeChanged: root.scheduleToolbarRelocation()',
    'onLayoutRecordsChanged(){root.scheduleToolbarRelocation()}',
    'id: toolbarRelocate',
    'interval: 90',
    'edge: root.toolbarEdge',
    'root.toolbarOnHorizontalEdge',
]
for needle in required:
    assert needle in text, needle

# The old edge-wide score moved the controls when Bottom was merely selected.
assert 'function toolbarEdgeScore(' not in text
assert 'score += 220' not in text
assert 'score += selected ? 54 : 12' not in text
assert re.search(r"onDraftChanged\s*:\s*(?:\{[^}]*?root\.|root\.)scheduleToolbarRelocation\(\)", text)
assert 'edge: "bottom"; identity: "edgeEditor"' not in text

# Exercise the production JS decision function against physical rectangles:
# only intersections of visible module/IPC content may trigger a relocation.
node = r"""
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ctx = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[1], 'utf8'), ctx);
const rects = {
  bottom: {x:400,y:850,width:600,height:100},
  top:    {x:400,y:20,width:600,height:100},
  right:  {x:1250,y:260,width:120,height:470},
  left:   {x:25,y:260,width:120,height:470}
};
const mod = (edge,content,enabled=true) => ({
  edge,content,enabled
});
const select = (edge,records,previews=[]) =>
  ctx.toolbarEdgeForRects(edge,rects,records,previews);
const bottomHit = mod('bottom',{x:580,y:885,width:100,height:45});
const bottomLeft = mod('bottom',{x:20,y:885,width:120,height:45});
const bottomRight = mod('bottom',{x:1190,y:885,width:120,height:45});
const topHit = mod('top',{x:580,y:40,width:100,height:45});
const rightHit = mod('right',{x:1280,y:450,width:40,height:100});
const leftHit = mod('left',{x:75,y:450,width:40,height:100});

assert.equal(select('bottom',[]),'bottom');
assert.equal(select('bottom',[bottomLeft,bottomRight]),'bottom',
  'Module(s) on Bottom but away from controls must not relocate them');
assert.equal(select('bottom',[mod('bottom',{x:700,y:851,width:100,height:1})]),'bottom',
  'Touching or sub-3px jitter is not a real obstruction');
assert.equal(select('bottom',[bottomHit]),'top',
  'A Bottom module overlapping the toolbar must relocate it');
assert.equal(select('bottom',[bottomHit,topHit]),'right');
assert.equal(select('bottom',[bottomHit,topHit,rightHit]),'left');
assert.equal(select('bottom',[bottomHit,topHit,rightHit,leftHit]),'bottom',
  'No less-obstructed edge: do not bounce');
assert.equal(select('bottom',[{...bottomHit,enabled:false}]),'bottom');
assert.equal(select('right',[]),'right',
  'Safe existing toolbar placement is sticky, even when Bottom is empty');
assert.equal(select('bottom',[],[{x:30,y:880,width:110,height:40}]),'bottom',
  'A nearby IPC preview on Bottom must not force movement');
assert.equal(select('bottom',[],[{x:560,y:890,width:110,height:40}]),'top',
  'Actual IPC preview overlap should relocate the controls');
console.log('toolbar geometric overlap cases: ok');
"""
subprocess.run(
    ["node", "-e", node, str(root / "modules/abyss/looks/AbyssLayout.js")],
    check=True,
)
print("abyss edge editor toolbar relocation contract: ok")
