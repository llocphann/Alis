#!/usr/bin/env python3
"""Execute the actual QML anchor method against affine source rectangles."""
import os
from pathlib import Path
import re
import subprocess

root = Path(os.environ.get("ALIS_POPUP_ANCHOR_SOURCE", Path(__file__).resolve().parents[1]))
source = (root / "modules/bar/StyledPopup.qml").read_text()
method = re.search(r"^    function _anchorRect\(.*?^    }", source, re.M | re.S)
assert method is not None
program = r'''
const assert=require('node:assert/strict');
const Qt={rect:(x,y,width,height)=>({x,y,width,height})};
let checks=0;
function near(a,b,label){assert(Math.abs(a-b)<1e-7,`${label}: ${a} != ${b}`);checks++}
const make=root=>{METHOD;return _anchorRect};
for(const edge of ['top','right','bottom','left'])
for(const angle of [0,90,-90,30])
for(const scale of [.75,1,1.5])
for(const sub of [null,{x:17,y:4,width:50,height:12}])
for(const alignment of ['source','center','start','end']){
 const width=1240,height=735,cx=620,cy=257.25;
 const a=angle*Math.PI/180,c=Math.cos(a)*scale,s=Math.sin(a)*scale;
 const map=(x,y)=>({x:cx+c*(x-107)-s*(y-16),y:cy+s*(x-107)+c*(y-16)});
 const target={x:0,y:0,width:214,height:32,parent:null,rotation:angle,scale,
  QsWindow:{mapFromItem:(_,x,y)=>map(x,y)}};
 const vertical=edge==='left'||edge==='right',trailing=edge==='right'||edge==='bottom';
 const root={hoverTarget:target,_anchorWindow:{windowTransform:{}},_anchorScreen:{},
  anchorRect:sub,_barSurfaceThickness:48,_attachmentVertical:vertical,
  _attachmentTrailing:trailing,centerOnOutput:alignment==='center',
  tangentEdgeOverride:['start','end'].includes(alignment)?alignment:''};
 const r=make(root)(width,height),local=sub??{x:0,y:0,width:214,height:32};
 const mid=map(local.x+local.width/2,local.y+local.height/2);
 const extent=vertical?Math.abs(s)*local.width+Math.abs(c)*local.height
  :Math.abs(c)*local.width+Math.abs(s)*local.height;
 const length=vertical?height:width;
 const expectedStart=alignment==='center'?(length-extent)/2:alignment==='start'?0
  :alignment==='end'?length-extent:(vertical?mid.y:mid.x)-extent/2;
 near(vertical?r.height:r.width,extent,'projected tangent extent');
 near(vertical?r.y:r.x,expectedStart,'projected tangent start');
 near(vertical?r.width:r.height,48,'Bar thickness');
 near(vertical?r.x:r.y,trailing?(vertical?width:height)-48:0,'physical Edge');
}
const empty={x:0,y:0,width:0,height:0};
assert.deepEqual(make({hoverTarget:null})(1240,735),empty);
console.log('TRANSFORMED_POPUP_ANCHOR_PASS',checks,'checks: rotation, scale, sub-rect, four Edges and overrides');
'''.replace("METHOD", method.group(0))
subprocess.run(["node"], input=program, text=True, check=True, timeout=15)
