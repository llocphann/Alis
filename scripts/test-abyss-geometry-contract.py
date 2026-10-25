#!/usr/bin/env python3
"""Evaluate the same geometry/SDF contract consumed by the QML field."""
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]
program = (
    (root / "modules/abyss/looks/AbyssGeometry.js").read_text()
    + "\n"
    + (root / "modules/abyss/looks/AbyssPyramidMotion.js").read_text()
    + r"""
const assert = require('node:assert/strict');
for(const owner of ['top','bottom','left','right']) {
 const ins={left:40,top:40,right:40,bottom:40};
 for(const scale of [1,1.25,1.5,2]) {
  const w=1920/scale,h=1200/scale;
  for(const progress of [0,.2,.5,1]) {
   const rec=panel(w,h,ins,owner,100,240,180,progress,14);
   const original=JSON.stringify(rec.content);
   const hit=popupInput(rec.content,w,h,ins,owner);
   const paintedHit=popupInput(rec.content,w,h,ins,owner,rec.surface);
   assert.equal(JSON.stringify(rec.content),original,'connection hitbox must not alter presentation geometry');
   assert(hit.x>=0 && hit.y>=0 && hit.x+hit.width<=w && hit.y+hit.height<=h);
   assert(paintedHit.x>=0 && paintedHit.y>=0 && paintedHit.x+paintedHit.width<=w && paintedHit.y+paintedHit.height<=h);
   if(progress===0) { assert.equal(hit.width*hit.height,0); assert.equal(paintedHit.width*paintedHit.height,0); continue; }
   const contains=(x,y)=>x>=paintedHit.x && y>=paintedHit.y && x<=paintedHit.x+paintedHit.width && y<=paintedHit.y+paintedHit.height;
   const c=rec.content;
   for(const [x,y] of [[c.x-7,c.y+c.height/2],[c.x+c.width+7,c.y+c.height/2],[c.x+c.width/2,c.y-7],[c.x+c.width/2,c.y+c.height+7]]){
    assert(distance(x,y,w,h,ins,34,[rec],24)<0,'tested padding is actually painted');
    assert(contains(x,y),'painted padding must retain body/bridge hover');
   }
   if(horizontal(owner)) {
    assert.equal(paintedHit.x,rec.surface.x);assert.equal(paintedHit.width,rec.surface.width,'painted input is bounded to body tangent footprint');
    assert.equal(hit.x,rec.content.x);assert.equal(hit.width,rec.content.width,'no output-wide hover strip');
    assert.equal(owner==='top'?hit.y:hit.y+hit.height,owner==='top'?ins.top:h-ins.bottom);
   } else {
    assert.equal(paintedHit.y,rec.surface.y);assert.equal(paintedHit.height,rec.surface.height,'painted input is bounded to body tangent footprint');
    assert.equal(hit.y,rec.content.y);assert.equal(hit.height,rec.content.height,'no output-wide hover strip');
    assert.equal(owner==='left'?hit.x:hit.x+hit.width,owner==='left'?ins.left:w-ins.right);
   }
  }
 }
}
// Pixel-center oracle for the small native shoulder masks. No painted
// connection pixel is dropped; no empty pixel is intercepted by the addition.
for(const owner of ['top','bottom','left','right']) {
 for(const scale of [1,1.25,1.5,2]) for(const softness of [4,24,48]) {
  const w=1920/scale,h=1200/scale,ins={left:40,top:40,right:40,bottom:40};
  for(const progress of [0,.2,1]) for(const radius of [20,29,38]) for(const nativeThickness of [8,40]) {
   const placementInsets={left:40,top:40,right:40,bottom:40};
   ins[owner]=nativeThickness;
   const rec=panel(w,h,placementInsets,owner,100.25,240.5,180,progress,14);
   const original=JSON.stringify(rec);
   const rows=popupShoulders(w,h,ins,owner,rec,34,softness,radius);
   assert.equal(JSON.stringify(rec),original,'native input does not mutate paint records');
   if(progress===0) {assert.equal(rows.length,0);continue;}
   const hit=popupInput(rec.content,w,h,ins,owner,rec.surface);
   const tangent=horizontal(owner)?rec.content.x+rec.content.width/2:rec.content.y+rec.content.height/2;
   const bridgeX=owner==='left'?nativeThickness+2:owner==='right'?w-nativeThickness-2:tangent;
   const bridgeY=owner==='top'?nativeThickness+2:owner==='bottom'?h-nativeThickness-2:tangent;
   assert(distance(bridgeX,bridgeY,w,h,ins,34,[rec],softness,radius)<0,'bridge probe is painted');
   assert(rectContains(hit,bridgeX,bridgeY),'module clearance must not truncate physical Edge bridge');
   for(const row of rows){
    assert(row.x>=0 && row.y>=0 && row.x+row.width<=w && row.y+row.height<=h);
    for(let y=row.y;y<row.y+row.height;y++) for(let x=row.x;x<row.x+row.width;x++)
     assert(distance(x+.5,y+.5,w,h,ins,34,[rec],softness,radius)<0,'extra native mask captures empty desktop');
   }
   const hEdge=horizontal(owner),start=Math.floor(hEdge?rec.surface.x:rec.surface.y),end=Math.ceil(hEdge?rec.surface.x+rec.surface.width:rec.surface.y+rec.surface.height);
   const seam=owner==='top'?ins.top:owner==='bottom'?h-ins.bottom:owner==='left'?ins.left:w-ins.right;
   const leading=owner==='top'||owner==='left';
   for(let i=0;i<=Math.ceil(softness);i++){
    const cross=(leading?Math.floor(seam):Math.ceil(seam)-1)+(leading?i:-i);
    for(const [first,last] of [[start-Math.ceil(softness),start],[end,end+Math.ceil(softness)]]) for(let t=first;t<last;t++){
     const x=(hEdge?t:cross)+.5,y=(hEdge?cross:t)+.5;
     if(x<0 || y<0 || x>=w || y>=h)continue;
     // Existing perimeter/corner paint alone does not grant this popup a lease.
     if(distance(x,y,w,h,ins,34,[],softness,radius)>0
         && distance(x,y,w,h,ins,34,[rec],softness,radius)<0)
      assert(rectContains(hit,x,y)||rows.some(row=>rectContains(row,x,y)),'painted connection shoulder missing from native mask');
    }
   }
  }
 }
}
for(const edge of ['top','right','bottom','left']) {
 const ins={left:16,top:16,right:16,bottom:16,[edge]:0};
 const x=edge==='left'?0.5:edge==='right'?1919.5:960;
 const y=edge==='top'?0.5:edge==='bottom'?1199.5:600;
 assert(distance(x,y,1920,1200,ins,34,[],24,24)>24,'disabled edge has no residual rim/shadow');
}
for(const [x,y] of [[.5,.5],[1919.5,.5],[.5,1199.5],[1919.5,1199.5],[960,600]])
 assert(distance(x,y,1920,1200,{left:0,top:0,right:0,bottom:0},34,[],24,24)>24,'all-off includes corners');
for(const owner of ['top','right','bottom','left']) {
  for(const adjacent of horizontal(owner)?['left','right']:['top','bottom']) {
    const ins=insets(16,owner,48,true);
    const length=horizontal(owner)?1920:1200;
    const trailing=adjacent==='right'||adjacent==='bottom';
    const base=panel(1920,1200,ins,owner,trailing?length-430:40,390,280,1,14);
    const original=JSON.stringify(base);
    const joined=joinCorner(base,adjacent,1920,1200,ins);
    assert.equal(JSON.stringify(base),original,'joining never mutates its original record');
    assert.deepEqual(joined.content,base.content,'joining preserves content geometry');
    assert.equal(joined.joinedEdge,adjacent);
    const boundary=adjacent==='left'?joined.surface.x:adjacent==='right'?joined.surface.x+joined.surface.width
        :adjacent==='top'?joined.surface.y:joined.surface.y+joined.surface.height;
    assert.equal(boundary,trailing?length+50:-50);
    assert.equal(joinCorner(base,'',1920,1200,ins),base,'joining is opt-in');
    const far=panel(1920,1200,ins,owner,500,390,280,1,14);
    assert.equal(joinCorner(far,adjacent,1920,1200,ins),far,'independently positioned distant popup does not bridge workspace');
    const closed=panel(1920,1200,ins,owner,40,390,280,0,14);
    assert.equal(joinCorner(closed,adjacent,1920,1200,ins),closed,'closed popup paints no corner connector');
    const pyramidClosed=interpolateRecord(collapsedRecord(base,null),base,0);
    assert.equal(joinCorner(pyramidClosed,adjacent,1920,1200,ins),pyramidClosed,'unrevealed Pyramid popup at progress 0 paints no corner connector');
    assert.equal(joinCorner(base,owner,1920,1200,ins),base,'only an adjacent Edge can join');
  }
}
// A joined native core adds only painted pixels, even at fractional output
// sizes and during reveal. The unjoined core remains the negative control.
let joinedPixels=0,joinedCases=0;
for(const owner of ['top','right','bottom','left'])
 for(const adjacent of horizontal(owner)?['left','right']:['top','bottom'])
  for(const scale of [1,1.25,1.5,2]) for(const progress of [.2,1]) {
   const w=1920/scale,h=1200/scale,ins=insets(16,owner,48,true);
   const extent=horizontal(owner)?w:h;
   const trailing=adjacent==='right'||adjacent==='bottom';
   const raw=panel(w,h,ins,owner,trailing?extent-320:40,280,180,progress,14);
   const joined=joinCorner(raw,adjacent,w,h,ins);
   assert.equal(joined.joinedEdge,adjacent);
   assert.deepEqual(joined.content,raw.content,'joinCorner ON/OFF keeps clipped content bounds identical during reveal');
   const c=raw.content;
   const adjX=adjacent==='left'?ins.left+(raw.surface.x-ins.left)/2
    :adjacent==='right'?raw.surface.x+raw.surface.width+(w-ins.right-raw.surface.x-raw.surface.width)/2
    :c.x+c.width/2;
   const adjY=adjacent==='top'?ins.top+(raw.surface.y-ins.top)/2
    :adjacent==='bottom'?raw.surface.y+raw.surface.height+(h-ins.bottom-raw.surface.y-raw.surface.height)/2
    :c.y+c.height/2;
   assert(distance(adjX,adjY,w,h,ins,34,[raw],24,38)>0,'unjoined adjacent gap stays open workspace');
   assert(distance(adjX,adjY,w,h,ins,34,[joined],24,38)<0,'joined adjacent seam is continuously painted');
   const farShadowX=horizontal(owner)?(trailing?raw.surface.x-4:raw.surface.x+raw.surface.width+4)
    :(owner==='left'?raw.surface.x+raw.surface.width+4:raw.surface.x-4);
   const farShadowY=!horizontal(owner)?(trailing?raw.surface.y-4:raw.surface.y+raw.surface.height+4)
    :(owner==='top'?raw.surface.y+raw.surface.height+4:raw.surface.y-4);
   const dOff=distance(farShadowX,farShadowY,w,h,ins,34,[raw],24,38);
   const dOn=distance(farShadowX,farShadowY,w,h,ins,34,[joined],24,38);
   assert(dOff>0 && dOff<24 && dOn>0 && dOn<24,'workspace-facing shadow band preserved across joinCorner ON/OFF');
   const before=popupInput(raw.content,w,h,ins,owner,raw.surface);
   const after=popupInput(joined.content,w,h,ins,owner,joined.surface);
   const primaryRimX=owner==='left'?4:owner==='right'?w-4:c.x+c.width/2;
   const primaryRimY=owner==='top'?4:owner==='bottom'?h-4:c.y+c.height/2;
   const cornerRimX=(owner==='left'||adjacent==='left')?4:w-4;
   const cornerRimY=(owner==='top'||adjacent==='top')?4:h-4;
   assert(rectContains(after,primaryRimX,primaryRimY),'joined popupInput covers primary Screen Edge');
   assert(rectContains(after,cornerRimX,cornerRimY),'joined popupInput covers shared Screen Edge corner');
   let added=0;
   for(let y=Math.floor(after.y);y<after.y+after.height;y++)
    for(let x=Math.floor(after.x);x<after.x+after.width;x++) {
     if(!rectContains(after,x+.5,y+.5)||rectContains(before,x+.5,y+.5))continue;
     assert(distance(x+.5,y+.5,w,h,ins,34,[joined],24,38)<0,
       'adjacent native core must not capture blank desktop');
     added++;joinedPixels++;
    }
   assert(added>0,'joined fixture did not add an adjacent weld');
   const shoulders=popupShouldersSnapshot(w,h,ins,adjacent,joined,34,24,38);
   for(const row of shoulders) for(let y=row.y;y<row.y+row.height;y++)
    for(let x=row.x;x<row.x+row.width;x++)
     assert(distance(x+.5,y+.5,w,h,ins,34,[joined],24,38)<0,
       'adjacent shoulder must not capture blank desktop');
   joinedCases++;
  }
console.log('JOINED_POPUP_PAINT_PASS',joinedCases,joinedPixels,'added painted pixel centers');
assert.equal(edge(false,false),'top'); assert.equal(edge(false,true),'bottom');
assert.equal(edge(true,false),'left'); assert.equal(edge(true,true),'right');
assert(targets('DP-2',['missing'],['DP-1','DP-2']));
assert(!targets('DP-2',['DP-1'],['DP-1','DP-2']));
for (const scale of [1,1.25,1.5,2]) {
    const w=1920/scale,h=1200/scale;
    for (const owner of ['top','bottom','left','right']) {
        const ins=insets(8,owner,48,true);
        assert.equal(ins[owner],48);
        for (const dock of ['top','bottom','left','right']) {
            for (const progress of [0,0.25,0.5,1,1.025]) {
                const records=[panel(w,h,ins,dock,200,300,70,progress,20),
                    panel(w,h,ins,'right',100,h-180,320,1,20),
                    panel(w,h,ins,owner,200,360,250,1,20)];
                for (const rec of records) {
                    const c=rec.content;
                    assert(c.x>=0 && c.y>=0 && c.width>=0 && c.height>=0);
                    assert(c.x+c.width<=w && c.y+c.height<=h);
                    if (c.width>0 && c.height>0)
                        assert(distance(c.x+c.width/2,c.y+c.height/2,w,h,ins,34,records,24)<0);
                }
                assert(distance(w/2,h/2,w,h,ins,34,records,24)>0, 'clean workspace center');
                // Every physical edge remains one connected body, even with
                // intersecting deformations and fractional logical dimensions.
                for(let i=1;i<100;i++) {
                    assert(distance(w*i/100,0,w,h,ins,34,records,24)<0);
                    assert(distance(w*i/100,h,w,h,ins,34,records,24)<0);
                    assert(distance(0,h*i/100,w,h,ins,34,records,24)<0);
                    assert(distance(w,h*i/100,w,h,ins,34,records,24)<0);
                }
            }
        }
    }
}

// Perpendicular placement must stay bounded even on a very small logical view.
for (const [w,h] of [[480,320],[800,600],[960,600],[1920,1200]]) {
    for (const owner of ['top','bottom','left','right']) {
        const ins=insets(8,owner,48,true);
        const sides=[panel(w,h,ins,'left',90,h-180,370,1,20),panel(w,h,ins,'right',90,h-180,390,1,20)];
        const rec=panel(w,h,ins,owner,100,380,320,1,20,sides);
        const c=rec.content;
        assert(c.x>=0 && c.y>=0 && c.x+c.width<=w && c.y+c.height<=h);
    }
}
// Flood-fill the actual inverse-opening/smooth-union distance. Each layout
// retains one workspace opening; no sealed corner pockets may appear.
for (const owner of ['top','bottom','left','right']) {
    const w=1100,h=700,ins=insets(8,owner,48,true);
    const side=panel(w,h,ins,'right',90,480,360,1,20);
    const popup=panel(w,h,ins,owner,390,380,300,1,20,[side]);
    const dock=panel(w,h,ins,'bottom',350,400,80,1,12,[side,popup]);
    for (const records of [[],[dock],[side],[popup],[dock,side],[popup,side],[popup,side,dock]]) {
        const cols=110,rows=70,seen=new Set(); let components=0;
        for(let y=0;y<rows;y++) for(let x=0;x<cols;x++) {
            const index=y*cols+x;
            if(seen.has(index) || distance((x+.5)*10,(y+.5)*10,w,h,ins,34,records,24,29)<=0) continue;
            components++;
            const queue=[index]; seen.add(index);
            while(queue.length) {
                const cell=queue.pop(),cx=cell%cols,cy=Math.floor(cell/cols);
                for(const [nx,ny] of [[cx-1,cy],[cx+1,cy],[cx,cy-1],[cx,cy+1]]) {
                    const next=ny*cols+nx;
                    if(nx<0 || nx>=cols || ny<0 || ny>=rows || seen.has(next)) continue;
                    if(distance((nx+.5)*10,(ny+.5)*10,w,h,ins,34,records,24,29)>0) { seen.add(next); queue.push(next); }
                }
            }
        }
        assert.equal(components,1,'one clean workspace opening: '+owner);
    }
}
assert.deepEqual(barZones({left:['media','tray'],centerLeft:['media','resources'],center:['workspaces'],right:['sysTray','weather']},false,{resources:false}),[['media','tray'],[],['workspaces'],[],['weather']]);
assert.deepEqual(barZones({top:['clock'],center:['workspaces'],bottom:['media']},true,{}),[['clock'],[],['workspaces'],[],['media']]);
const host = require('node:fs').readFileSync('modules/abyss/AbyssPerimeter.qml','utf8');
assert(host.includes('exclusionMode: ExclusionMode.Ignore'));
assert(host.includes('exclusiveZone: 0'));
assert(host.includes('mask: Region {}'));
assert(host.includes('model: Quickshell.screens'));
"""
)
subprocess.run(["node", "-e", program], cwd=root, check=True)
print("ok - connected four-edge SDF, orientations, content bounds and output policy")
