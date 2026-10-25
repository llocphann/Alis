#!/usr/bin/env python3
"""Exercise production placement normalization, packing and output profiles."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
program = (root / "modules/abyss/looks/AbyssLayout.js").read_text() + r"""
const assert = require('node:assert/strict');
for(const edge of ['top','right','bottom','left'])for(const end of ['start','end']) {
 const horizontal=['top','bottom'].includes(edge),length=horizontal?1920:1080;
 const entries=normalize([{id:'nearest',kind:'clock',edge,alignment:end,position:end==='start'?0:1,joinCorner:true},
  {id:'inner',kind:'clock',edge,alignment:end,position:end==='start'?.12:.88,joinCorner:true}],edge);
 const options={edgeThicknesses:{[edge]:0},edgeWidthAffectsModules:{[edge]:false},edgeModuleRadii:{[edge]:0}};
 const foreground=geometry(entries,1920,1080,options,1),snapshot=JSON.stringify(foreground);
 const sorted=foreground.slice().sort((a,b)=>a.along-b.along),nearest=end==='start'?sorted[0]:sorted[1],inner=end==='start'?sorted[1]:sorted[0];
 assert(cornerForModule(foreground,nearest.id,1920,1080));assert.equal(cornerForModule(foreground,inner.id,1920,1080),'','inner modules cannot weld through their neighbor');
 const local=localSurfaces(foreground,1920,1080,options,1,48),joined=local.find(p=>p.content===nearest.content),separate=local.find(p=>p.content===inner.content);
 assert.equal(joined.radius,0,'square is a real override');assert.equal(separate.radius,0);
 assert.equal(end==='start'?joined.along:joined.along+joined.span,end==='start'?0:length,'paint reaches selected corner');
 assert.equal(separate.along,inner.along,'interior backing stays local');assert.equal(JSON.stringify(foreground),snapshot,'corner weld never moves input/modules');
 assert(localSurfaces(foreground,1920,1080,{...options,edgeModuleRadii:{[edge]:-1}},1,48).every(p=>p.radius===undefined),'inherit preserves the field material rounding');
 assert(localSurfaces(foreground,1920,1080,{...options,edgeModuleRadii:{[edge]:1000}},1,48).every(p=>p.radius===64),'rounding is bounded');
 const writes=saveProfile({outputLayouts:[{outputName:'B',placements:[],edgeModuleRadii:{left:24}}]},'A',entries,8,true,undefined,undefined,undefined,undefined,undefined,undefined,{[edge]:0});
 assert.equal(writes['abyss.modules.outputLayouts'][0].edgeModuleRadii.left,24);assert.equal(optionsForOutput({outputLayouts:writes['abyss.modules.outputLayouts']},'A').edgeModuleRadii[edge],0);
}
for(const edge of ['top','right','bottom','left']) {
 const placements=normalize([{id:'a',kind:'clock',edge,position:.35,depth:1.4},
  {id:'b',kind:'clock',edge,position:.35,depth:.7},{id:'far',kind:'clock',edge,position:.9}],edge);
 const options={edgeThickness:16,edgeThicknesses:{[edge]:0},edgeWidthAffectsModules:{[edge]:false}};
 const records=geometry(placements,1920,1080,options,1),snapshot=JSON.stringify(records);
 const separate=localSurfaces(records,1920,1080,options,1,48);
 const joined=localSurfaces(records,1920,1080,{...options,edgeJoinModules:{[edge]:true}},1,48);
 assert.equal(separate.length,3);assert.equal(joined.length,2,'join only the adjacent group on '+edge);
 assert(joined[0].span>=records[1].along+records[1].span-records[0].along,'joined backing bridges the internal gap');
 assert.equal(joined[0].depth,Math.max(separate[0].depth,separate[1].depth),'mixed heights retain the taller module');
 assert.equal(JSON.stringify(records),snapshot,'paint joins do not change foreground/input geometry');
 const all={edgeJoinModules:{top:false},outputLayouts:[{outputName:'B',placements:[],edgeJoinModules:{left:true}}]};
 const writes=saveProfile(all,'A',placements,8,true,undefined,undefined,undefined,undefined,{[edge]:false},{[edge]:true});
 assert.equal(writes['abyss.modules.outputLayouts'][0].edgeJoinModules.left,true,'preserve the other output');
 assert.equal(optionsForOutput({...all,outputLayouts:writes['abyss.modules.outputLayouts']},'A').edgeJoinModules[edge],true);
 assert.equal(saveProfile(all,'A',placements,8,false,undefined,undefined,undefined,undefined,undefined,{[edge]:true})['abyss.modules.edgeJoinModules'][edge],true);
}
for (const edge of ['top','right','bottom','left']) {
 const placements=normalize([{kind:'clock',edge},{kind:'battery',edge}],edge);
 const off={edgeThickness:16,edgeThicknesses:{[edge]:0}};
 assert.equal(edgeThickness(off,edge),0,'zero is a real off width');
 assert.equal(geometry(placements,1920,1080,off,1).length,0,'coupled zero releases inherited modules');
 assert.equal(edgeInsetsForModules(placements,off,1,16,48,true)[edge],0,'hidden modules reserve no space');
 const independent={...off,edgeWidthAffectsModules:{[edge]:false}};
 const records=geometry(placements,1920,1080,independent,1);
 assert.equal(records.length,2,'edge-only zero preserves foreground modules');
 assert.equal(edgeInsetsForModules(placements,independent,1,16,48,false)[edge],0,'bare edge stays off');
 assert.equal(localSurfaces(records,1920,1080,independent,1,48).length,2,'modules retain local backing');
 assert(edgeInsetsForModules(placements,independent,1,16,48,true)[edge]>=48,'module input remains protected');
 const custom=placements.map(p=>({...p,customSize:true,size:1.2}));
 assert.equal(localSurfaces(geometry(custom,1920,1080,off,1),1920,1080,off,1,48).length,2,'custom modules remain independent at zero');
 const writes=saveProfile({},'A',placements,8,true,undefined,undefined,undefined,{[edge]:0},{[edge]:false});
 assert.equal(optionsForOutput({outputLayouts:writes['abyss.modules.outputLayouts']},'A').edgeThicknesses[edge],0,'output save keeps zero');
}
for (const edge of ['top','right','bottom','left']) {
 const shared={edge,size:1,customSize:false}, custom={...shared,size:1.3,customSize:true};
 assert.equal(moduleSize(shared,{edgeThickness:32}),2,'thicker Edge scales shared modules');
 assert.equal(moduleSize(shared,{edgeThickness:10}),.625,'narrower Edge scales shared modules');
 assert.equal(moduleSize(custom,{edgeThickness:32}),1.3,'explicit custom size stays independent');
 assert.equal(moduleSize(shared,{edgeThickness:Infinity}),1,'invalid thickness is bounded');
}

for (const edge of ['top','right','bottom','left']) {
 const opts={edgeThickness:16,edgeThicknesses:{[edge]:32}}, other=['top','right','bottom','left'].find(e=>e!==edge);
 assert.equal(edgeThickness(opts,edge),32);assert.equal(edgeThickness(opts,other),16,'other physical Edges are unchanged');
 assert.equal(edgeInsetsForModules([],opts,1,16,48,false)[edge],32,'empty Edge has selected pixel thickness');
 assert.equal(moduleSize({edge,customSize:false},opts),2,'inherited module size follows selected physical Edge');
 assert.equal(moduleSize({edge,size:1.3,customSize:true},opts),1.3,'custom override remains independent');
 assert.equal(edgeThickness({edgeThickness:24,edgeThicknesses:{[edge]:-1}},edge),24,'inherit sentinel follows Surface thickness');
 assert.equal(edgeThickness({edgeThicknesses:{[edge]:Infinity}},edge),16,'invalid override degrades safely');
 const placements=normalize([{kind:'clock',edge}],edge);
 assert.equal(edgeInsetsForModules(placements,{...opts,singleModuleExpansion:{[edge]:'local'}},1,16,48,false)[edge],32,'local module retains chosen resting thickness');
}
for (const edge of ['top','right','bottom','left']) {
 const opts={edgeThickness:16,edgeThicknesses:{[edge]:32},edgeWidthAffectsModules:{[edge]:false}};
 const shared={edge,size:1,customSize:false},custom={...shared,size:1.4,customSize:true};
 assert.equal(moduleSize(shared,opts),1,'Edge-only width leaves inherited modules at their prior size');
 assert.equal(moduleSize(custom,opts),1.4,'custom size remains independent in both policies');
 const placements=normalize([{kind:'clock',edge},{kind:'battery',edge}],edge);
 assert.equal(edgeInsetsForModules(placements,opts,1,16,48,false)[edge],32,'painted Edge-only width is no longer masked by the module strip minimum');
 assert(edgeInsetsForModules(placements,opts,1,16,48,true)[edge]>=48,'reserved workspace still protects modules');
 const records=geometry(placements,1920,1080,opts,1);
 assert.equal(localSurfaces(records,1920,1080,opts,1,48).length,2,'both modules retain connected foreground backing');
 const all={outputLayouts:[{outputName:'B',placements:[],edgeWidthAffectsModules:{left:false}}]};
 const saved=saveProfile(all,'A',placements,8,true,undefined,undefined,undefined,{[edge]:32},{[edge]:false});
 assert.equal(saved['abyss.modules.outputLayouts'].find(p=>p.outputName==='B').edgeWidthAffectsModules.left,false);
 assert.equal(optionsForOutput({...all,outputLayouts:saved['abyss.modules.outputLayouts']},'A').edgeWidthAffectsModules[edge],false,'per-output Done retains policy');
 assert.equal(saveProfile(all,'A',placements,8,false,undefined,undefined,undefined,{[edge]:32},{[edge]:false})['abyss.modules.edgeWidthAffectsModules'][edge],false,'global Done stores policy');
}
const thicknessProfile={edgeThicknesses:{top:20},outputLayouts:[{outputName:'B',placements:[],edgeThicknesses:{left:28}}]};
const thicknessSaved=saveProfile(thicknessProfile,'A',[],8,true,undefined,undefined,undefined,{right:32});
assert.deepEqual(thicknessSaved['abyss.modules.outputLayouts'][0].edgeThicknesses,{left:28},'Done preserves another output thickness');
const thicknessA=optionsForOutput({...thicknessProfile,outputLayouts:thicknessSaved['abyss.modules.outputLayouts']},'A');
assert.equal(edgeThickness(thicknessA,'right'),32);assert.equal(edgeThickness(thicknessA,'top'),20,'profile overrides merge with global thickness');
assert.equal(saveProfile(thicknessProfile,'A',[],8,false,undefined,undefined,undefined,{bottom:30})['abyss.modules.edgeThicknesses'].bottom,30,'global Done stores physical Edge thickness');

assert(!catalog.includes('leftSidebarButton') && !catalog.includes('rightSidebarButton'));
assert(!catalog.includes('wifi') && !catalog.includes('bluetooth'),'connectivity lives in System Tray, not duplicate Edge modules');
assert(!catalog.includes('utilities'),'Utilities lives inside Quick Actions, not as a standalone Edge module');
assert.deepEqual(normalize([{id:'old-left',kind:'leftSidebarButton'},{id:'old-wifi',kind:'wifi'},{id:'old-util',kind:'utilities'},{id:'clock',kind:'clock'},{id:'old-bt',kind:'bluetooth'},{id:'old-right',kind:'rightSidebarButton'}],'top').map(p=>p.id),['clock']);
const initial = seed([catalog.slice(0,3),catalog.slice(3,5),[catalog[5]],catalog.slice(6,9),catalog.slice(9)],'top',1920,1200);
assert.equal(initial.length,catalog.length);
assert.equal(new Set(initial.map(p=>p.id)).size,initial.length);
assert(normalize([{kind:'clock',joinCorner:true}],'top')[0].joinCorner);
assert(!normalize([{kind:'clock'}],'top')[0].joinCorner);
for (const edge of ['top','right','bottom','left']) {
 const horizontal=edge==='top'||edge==='bottom', length=horizontal?1920:1200;
 assert.equal(adjacentEdge({edge,along:40,span:100},1920,1200),horizontal?'left':'top');
 assert.equal(adjacentEdge({edge,along:length-140,span:100},1920,1200),horizontal?'right':'bottom');
 assert.equal(adjacentEdge({edge,along:length/2,span:100},1920,1200),'');
}

const saved = JSON.stringify(initial);
for (const [w,h] of [[1920,1200],[1536,960],[960,600],[480,320]]) {
    for (const edge of ['top','right','bottom','left']) {
        const placements=initial.map(p=>({...p,edge}));
        const allRecords=geometry(placements,w,h,{gap:12},1.5);
        assert.equal(allRecords.length,placements.length,'rejected members remain in the saved/editor inventory');
        const records=allRecords.filter(p=>!p.capacityConflict);
        if(records.length!==allRecords.length) {
            assert(allRecords.every(p=>p.capacityConflict),'reject the overfull Edge as one explicit layout');
            assert(allRecords.every(p=>p.span===extent(p.kind,false)*1.5*moduleSize(p,{})), 'capacity never shrinks configured designs');
            assert.equal(localSurfaces(allRecords,w,h,{edgeWidthAffectsModules:{[edge]:false}},1.5,48).length,0,'rejected modules do not paint ghost backing');
            const notices=capacityNotices(allRecords,w,h,1.5);
            assert.equal(notices.length,1,'one visible repair action owns the rejected Edge');
            const c=notices[0].content;
            assert(c.x>=0&&c.y>=0&&c.x+c.width<=w+.001&&c.y+c.height<=h+.001,'repair target stays on output');
        }
        for (let i=0;i<records.length;i++) {
            const r=records[i],c=r.content;
            assert(c.x>=0 && c.y>=0 && c.x+c.width<=w+.001 && c.y+c.height<=h+.001);
            assert(r.span>0);
            if(i) assert(records[i-1].along+records[i-1].span <= r.along+.001,'no overlapping controls');
        }
    }
}
assert.equal(JSON.stringify(initial),saved,'resize never mutates persisted layout');
const disabled=initial.map((p,i)=>({...p,enabled:i!==0}));
assert.equal(geometry(disabled,1920,1200,{},1).length,initial.length-1);
const bad=normalize([{kind:'clock',position:Infinity,edge:'unknown'},{kind:'clock'},null,{kind:'unknown'},{kind:'media',size:100,depth:-3}], 'left');
assert.equal(bad.length,2);assert.equal(bad[0].edge,'left');assert.equal(bad[0].position,.5);
assert.equal(bad[1].size,1.8);assert.equal(bad[1].depth,.5);
const profile={configured:true,placements:initial,outputLayouts:[{outputName:'B',placements:[]}]};
assert.deepEqual(resolve(profile,'B',initial),[],'explicit empty output layout stays empty');
assert.deepEqual(resolve(profile,'A',[]),initial);
assert.deepEqual(resolve({configured:false},'A',initial),initial);
assert.equal(normalize(Array(100).fill(0).map((_,i)=>({id:String(i),kind:'clock'})),'top').length,24,'bounded renderer capacity');
const cross=move(initial,'clock',1890,540,1920,1080);
assert.equal(cross.find(p=>p.id==='clock').edge,'right');
assert.equal(cross.find(p=>p.id==='clock').position,.5);
assert.equal(initial.find(p=>p.id==='clock').edge,'top','draft does not mutate saved snapshot');
assert.equal(project(20,1060,1920,1080).edge,'bottom','corner projection deterministic');
const merged=saveProfile({outputLayouts:[{outputName:'B',placements:[],gap:3}]},'A',cross,16,true);
assert.equal(merged['abyss.modules.outputLayouts'][0].outputName,'B','save preserves another output');
assert.equal(optionsForOutput({gap:8,outputLayouts:merged['abyss.modules.outputLayouts']},'A').gap,16);
const measured=geometry(initial.filter(p=>['clock','timer'].includes(p.kind)),1920,1200,{extents:{clock:300,timer:0}},1.5);
assert.equal(measured.find(p=>p.kind==='clock').span,300,'mature module sizes already include font scale');
assert.equal(measured.some(p=>p.kind==='timer'),false,'idle indicators must not keep layout gaps or physical Edge deformations');
assert(geometry(initial,1920,1200,{extents:{timer:0},editing:true},1).find(p=>p.kind==='timer').span>0,'editor can select inactive indicators');
const conditional=normalize([{id:'timer',kind:'timer',edge:'top',position:.30},
    {id:'shellUpdate',kind:'shellUpdate',edge:'top',position:.45},
    {id:'clock',kind:'clock',edge:'top',position:.60}], 'top');
const empty=geometry(conditional,1920,1080,{edgeWidthAffectsModules:{top:false},
    edgeThickness:18,extents:{timer:0,shellUpdate:0,clock:120}},1);
assert.deepEqual(empty.map(p=>p.kind),['clock'],
    'Width affects modules off must not retain idle Timer/Update gaps');
assert.equal(localSurfaces(empty,1920,1080,{edgeWidthAffectsModules:{top:false}},1,32).length,1,
    'idle Timer/Update cannot leave tiny Edge backing deformations');
const populated=geometry(conditional,1920,1080,{edgeWidthAffectsModules:{top:false},
    edgeThickness:18,extents:{timer:65,shellUpdate:55,clock:120}},1);
assert.equal(populated.length,3,'Timer/Update return with content without changing placements');
assert.equal(geometry(conditional,1920,1080,{editing:true,edgeWidthAffectsModules:{top:false},
    edgeThickness:18,extents:{timer:0,shellUpdate:0,clock:120}},1).length,3,
    'editing must keep selectable placeholders for inactive indicator modules');
const sized=normalize([{id:'a',kind:'clock',edge:'top',position:.1},{id:'b',kind:'clock',edge:'top',position:.4},
    {id:'c',kind:'clock',edge:'right',position:.5},{id:'custom',kind:'clock',edge:'top',position:.8,size:1.6,customSize:true}], 'top');
const sizing={edgeSizes:{top:1.25,right:.8},extents:{a:100,b:100,c:100,custom:100}};
const sizes=geometry(sized,1920,1200,sizing,1);
assert.equal(sizes.find(p=>p.id==='a').span,125);assert.equal(sizes.find(p=>p.id==='b').span,125,'one edge inherits one size');
assert.equal(sizes.find(p=>p.id==='c').span,80,'another edge can have another size');
assert.equal(sizes.find(p=>p.id==='custom').span,160,'explicit custom size overrides shared edge size');
assert.equal(stripDepth(sized,'top',sizing,1),67.2,'reservation contains the largest custom module');
assert(normalize([{kind:'clock',size:1.3}], 'top')[0].customSize,'historic non-default sizes migrate to explicit overrides');
assert(!normalize([{kind:'clock',size:1.3,customSize:false}], 'top')[0].customSize,'unchecked override inherits even when old size is saved');
const inherited=saveProfile({edgeSizes:{top:1},outputLayouts:[{outputName:'B',placements:[],edgeSizes:{top:.7}}]},'A',sized,8,true,sizing.edgeSizes);
assert.equal(optionsForOutput({outputLayouts:inherited['abyss.modules.outputLayouts']},'A').edgeSizes.top,1.25);
assert.equal(inherited['abyss.modules.outputLayouts'][0].edgeSizes.top,.7,'save preserves another output size');
const customOutput={size:1.1,outputLayouts:[{outputName:'A',size:1.5,placements:[],futureOption:'preserved'},
    {outputName:'B',size:.8,placements:[]}]};
const scoped=saveProfile(customOutput,'A',sized,8,true,sizing.edgeSizes,{top:'local'},1.3);
assert.equal(scoped['abyss.modules.outputLayouts'][0].size,.8,'other output scale stays unchanged');
assert.equal(scoped['abyss.modules.outputLayouts'][1].futureOption,'preserved','unrelated output options survive editing');
assert.equal(optionsForOutput({...customOutput,outputLayouts:scoped['abyss.modules.outputLayouts']},'A').size,1.3);
assert.equal(optionsForOutput(customOutput,'missing').size,1.1,'global scale remains the fallback');
for(const edge of ['top','right','bottom','left']) {
    const single=normalize([{kind:'clock',edge}],edge), opts={edgeThickness:16,singleModuleExpansion:{[edge]:'local'}};
    const local=edgeInsetsForModules(single,opts,1,16,48,false);
    const reserved=edgeInsetsForModules(single,opts,1,16,48,true);
    assert.equal(local[edge],16,'local expansion leaves the remaining physical edge thin');
    assert.equal(reserved[edge],48,'local expansion still reserves application space');
    const records=geometry(single,1920,1200,opts,1), surfaces=localSurfaces(records,1920,1200,opts,1,48);
    assert.equal(surfaces.length,1);
    const c=records[0].content,s=surfaces[0].surface;
    assert.equal(surfaces[0].depth,48,'local expansion uses pixel extent rather than a placement depth multiplier');
    assert.equal(clearanceInsets(local,surfaces,edge,records[0].along,records[0].span)[edge],48,'a popup above this local module clears its foreground');
    assert.equal(clearanceInsets(local,surfaces,edge,records[0].along+records[0].span+20,20)[edge],16,'another source position retains the thin Edge attachment');
    assert.equal(local[edge],16,'per-popup clearance does not mutate the physical Edge');
    assert(s.x<=c.x && s.y<=c.y && s.x+s.width>=c.x+c.width && s.y+s.height>=c.y+c.height,'local surface contains the module');
    assert.equal(localSurfaces(records,1920,1200,{},1,48).length,0,'default whole-edge presentation remains flat');
    const pair=normalize(single.concat([{id:'second',kind:'clock',edge,position:.8}]),edge);
    assert.equal(edgeInsetsForModules(pair,opts,1,16,48,false)[edge],48,'multiple modules expand the whole edge');
    assert.equal(localSurfaces(geometry(pair,1920,1200,opts,1),1920,1200,opts,1,48).length,0);
}
for(const edge of ['top','right','bottom','left']) {
    const aligned=normalize([{id:'a',kind:'clock',edge,position:.2,alignment:'center'},
        {id:'b',kind:'clock',edge,position:.4,alignment:'center'}],edge);
    const length=['top','bottom'].includes(edge)?1920:1200;
    for(const alignment of ['start','center','end']) {
        const group=geometry(aligned.map(p=>({...p,alignment})),1920,1200,{gap:8,extents:{a:100,b:100}},1);
        assert.equal(group[1].along-group[0].along,108,'aligned groups preserve order and gap');
        assert.equal(group[0].along,alignment==='start'?group[0].edgeStart:alignment==='end'?group[0].edgeEnd-208:(length-208)/2);
    }
}
const solo=normalize([{id:'clock',kind:'clock',edge:'top',position:.2}], 'top');
const snapped=snapMove(solo,'clock',964,10,1920,1200,{extents:{clock:100}},1);
assert.equal(snapped.placements[0].position,.5);assert.equal(snapped.guides[0].along,960);
assert.equal(snapMove(solo,'clock',990,10,1920,1200,{},1).guides.length,0,'outside tolerance stays free');
assert.equal(snapMove(solo,'clock',1900,601,1920,1200,{},1).guides[0].horizontal,false,'vertical edge uses horizontal guide');
assert.equal(move([{...solo[0],alignment:'center'}],'clock',600,10,1920,1200)[0].alignment,'free','drag releases group alignment');
for(const [w,h] of [[1920,1200],[853.5,479.25],[480,320]]) {
 for(const edge of ['top','right','bottom','left']) {
  const horizontal=edge==='top'||edge==='bottom', length=horizontal?w:h;
  for(const position of [0,1]) {
   const placements=normalize([{id:'corner',kind:'clock',edge,position}],edge);
   const record=geometry(placements,w,h,{extents:{corner:60}},1)[0];
   assert.equal(record.along,position===0?record.edgeStart:record.edgeEnd-record.span,'free placements stop at modest corner clearance');
   const along=position===0?record.edgeStart+record.span/2:record.edgeEnd-record.span/2;
   const x=horizontal?along:(edge==='left'?8:w-8);
   const y=horizontal?(edge==='top'?8:h-8):along;
   const snapped=snapMove(placements,'corner',x,y,w,h,{extents:{corner:60}},1);
   assert.equal(snapped.guides[0].along,position===0?record.edgeStart:record.edgeEnd,'snap guides preserve content clearance');
   const restored=geometry(snapped.placements,w,h,{extents:{corner:60}},1)[0];
   assert(Math.abs(restored.along-record.along)<1e-9,'drag/snap/save geometry agree at fractional corner coordinates');
   assert(cornerForModule([record],'corner',w,h),'corner join remains available at the endpoint');
  }
 }
}
// ABYSS-R03: explicit per-module rotation (0/90/180/270), cross-edge preservation, and legacy defaults.
assert.equal(defaultRotationForEdge('top'),0);
assert.equal(defaultRotationForEdge('bottom'),0);
assert.equal(defaultRotationForEdge('right'),90);
assert.equal(defaultRotationForEdge('left'),270);
for(const edge of ['top','right','bottom','left']) {
 const legacy=normalize([{id:'leg',kind:'clock',edge,position:.5}],edge)[0];
 assert.equal(effectiveRotation(legacy),defaultRotationForEdge(edge),'legacy placement defaults to edge orientation');
 let cur=normalize([{id:'rot',kind:'clock',edge,position:.5,rotation:0}],edge);
 for(const expected of [90,180,270,0]) {
  const step=checkedBatch(cur,['rot'],'rotation','step',1920,1080,{extents:{rot:104}},1);
  assert.equal(step.rejected,'');
  cur=step.placements;
  assert.equal(cur[0].rotation,expected,'stepwise 90-degree rotation');
  const rec=geometry(cur,1920,1080,{extents:{rot:104}},1)[0];
  const verticalRot=expected===90||expected===270;
  assert.equal(rec.content.width,verticalRot?32:104,'rotated width matches module orientation');
  assert.equal(rec.content.height,verticalRot?104:32,'rotated height matches module orientation');
 }
 const rotated90=checkedBatch(cur,['rot'],'rotation',90,1920,1080,{extents:{rot:104}},1).placements;
 for(const [tx,ty,destEdge] of [[960,8,'top'],[1912,540,'right'],[960,1072,'bottom'],[8,540,'left']]) {
  const moved=checkedMove(rotated90,'rot',tx,ty,1920,1080,{extents:{rot:104}},1,false);
  assert(!moved.rejected);
  assert.equal(moved.placements[0].edge,destEdge);
  assert.equal(moved.placements[0].rotation,90,'cross-edge move preserves explicit rotation');
 }
}
console.log('PASS: normalized module packing, corner-safe content endpoints/snaps, all edges/scales, output profiles, disabled state and bounded malformed input');
"""
subprocess.run(["node", "-e", program], cwd=root, check=True)
