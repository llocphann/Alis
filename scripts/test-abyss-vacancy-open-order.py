#!/usr/bin/env python3
"""Exercise actual allocator, vacancy and painted geometry in both open orders."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parts = ["const g={},b={},v={};"]
for name, filename, exports in (
    ("g", "AbyssGeometry.js", "panel,placedPanel"),
    ("b", "AbyssBodyPlacement.js", "arrange"),
    ("v", "AbyssVacancyBorrowing.js", "resolve"),
):
    source = (ROOT / "modules/abyss/looks" / filename).read_text()
    parts.append(f"Object.assign({name},(function(){{{source}\nreturn {{{exports}}};}})());")
parts.append(r'''
const assert=require("node:assert/strict"), IN={left:16,right:16,top:16,bottom:16};
let checks=0;
function rotate(r,W,H){
 const c=r.record.content,e={left:"top",top:"right",right:"bottom",bottom:"left"}[r.record.edge];
 const content={x:H-c.y-c.height,y:c.x,width:c.height,height:c.width};
 const along=(e==="top"||e==="bottom"?content.x:content.y)-r.padding;
 return {...r,record:{...r.record,edge:e,along,content}};
}
for(const pair of [["featureSidebar","quickNotes"],["systemSidebar","notificationCenter"]]){
 for(let rotation=0;rotation<4;rotation++)for(const order of [[1,2],[2,1]]){
  let W=1800,H=1000;
  function req(id,edge,along,span,depth,n){return {id,open:true,order:n,priority:2,padding:14,
   minSpan:220,minDepth:120,record:g.panel(W,H,IN,edge,along,span,depth,1,14,[],false)}}
  let requests=[req("sidebar","left",110,720,440,order[0]),req("edgebar","bottom",510,380,340,order[1])];
  for(let n=0;n<rotation;n++){requests=requests.map(r=>rotate(r,W,H));[W,H]=[H,W];}
  const metadata=[{id:"sidebar",role:pair[0]},{id:"edgebar",role:pair[1]}];
  const base=b.arrange(requests,W,H,IN), out=v.resolve(requests,metadata,base,W,H,IN,24);
  const newer=order[0]>order[1]?"sidebar":"edgebar",older=newer==="sidebar"?"edgebar":"sidebar";
  assert(out[newer].vacancyBorrowed,`newer ${newer} lost strip at rotation ${rotation}`);checks++;
  assert.deepEqual(out[older],base[older],"earlier peer changed its requested dimensions");checks++;
  const a=out.sidebar.content,c=out.edgebar.content;
  assert(!(a.x<c.x+c.width+23.99&&a.x+a.width+23.99>c.x&&a.y<c.y+c.height+23.99&&a.y+a.height+23.99>c.y));checks++;
  for(const r of requests){
   const p=out[r.id],record=g.placedPanel(W,H,IN,r.record.edge,r.record.along,r.record.span,r.record.targetDepth,1,14,[],false,p);
   assert.deepEqual(record.content,p.content,"painted content dropped vacancy dimensions");checks++;
  }
  const closed=requests.map(r=>r.id===older?{...r,open:false}:r),solo=b.arrange(closed,W,H,IN);
  assert.deepEqual(v.resolve(closed,metadata,solo,W,H,IN,24),solo,"closed peer left stale expansion");checks++;
  assert.deepEqual(v.resolve(requests,metadata,b.arrange(requests,W,H,IN),W,H,IN,24),out,"reopen changed placement");checks++;
 }
}
console.log(`PASS: ${checks} allocator/vacancy/paint checks, both orders, both pairs, four edges`);
''')
raise SystemExit(subprocess.run(["node", "-e", "\n".join(parts)], cwd=ROOT).returncode)
