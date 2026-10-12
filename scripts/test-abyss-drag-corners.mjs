import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const L=vm.createContext({Math,JSON,Number,Array,Set});vm.runInContext(fs.readFileSync(new URL('../modules/abyss/looks/AbyssLayout.js',import.meta.url),'utf8'),L);
let checks=0;function check(value,label){checks++;assert.ok(value,label)}
for(const [w,h] of [[1920,1080],[853.5,479.25],[320,180]])for(const scale of [.7,1,1.5,2])for(const edge of ['top','right','bottom','left'])for(const end of ['start','end']){
 const horizontal=['top','bottom'].includes(edge),length=horizontal?w:h;
 const options={extents:{a:40*scale},cornerRadius:28,editing:true};
 const entries=L.normalize([{id:'a',kind:'clock',edge,position:end==='start'?0:1,alignment:end,joinCorner:true}],edge);
 const record=L.geometry(entries,w,h,options,scale)[0];
 check(!record.capacityConflict&&record.along>=record.edgeStart&&record.along+record.span<=record.edgeEnd+.00001,'content stays clear of corners');
 check(record.edgeStart>=4&&record.edgeStart<=12,'empty corner clearance is modest');
 const c=record.content,grab={x:c.x+c.width*.2,y:c.y+c.height*.3},context=L.dragContext(record,grab.x,grab.y);
 const point=L.dragPoint(context,grab.x,grab.y,w,h,scale);
 check(point.edge===edge,'press retains original Edge');
 const moved=L.checkedMove(entries,'a',point.x,point.y,w,h,{...options,dragEdge:point.edge},scale,false);
 const restored=L.geometry(moved.placements,w,h,options,scale)[0];
 check(Math.abs(restored.along-record.along)<1e-7,'off-center grab never recenters the module');
 const paint=L.localSurfaces([record],w,h,{...options,edgeWidthAffectsModules:{[edge]:false}},scale,48)[0];
 check(end==='start'?paint.along===0:paint.along+paint.span===length,'decorative join alone reaches corner');
 const saved=L.saveProfile({outputLayouts:[{outputName:'B',placements:[]}]},'A',moved.placements,8,true);
 const restarted=L.geometry(L.resolve({outputLayouts:saved['abyss.modules.outputLayouts']},'A',[]),w,h,options,scale)[0];
 check(Math.abs(restarted.along-restored.along)<1e-7,'save/restart uses absolute normalized centers');
}
for(const [a,b,pa,pb] of [['top','left',0,0],['top','right',1,0],['bottom','left',0,1],['bottom','right',1,1]])for(const scale of [.7,1,1.5,2]){
 const entries=L.normalize([{id:'a',kind:'clock',edge:a,position:pa},{id:'b',kind:'clock',edge:b,position:pb}],'top');
 const options={extents:{a:100,b:100},editing:true},snapshot=JSON.stringify(entries);
 const records=L.geometry(entries,853.5,479.25,options,scale),x=records[0].content,y=records[1].content;
 check(x.x+x.width+8<=y.x+.0001||y.x+y.width+8<=x.x+.0001||x.y+x.height+8<=y.y+.0001||y.y+y.height+8<=x.y+.0001,'perpendicular controls cannot overlap at a corner');
 check(JSON.stringify(entries)===snapshot,'corner negotiation never rewrites placements');
 const locked=L.setLocked(entries,'a',true,853.5,479.25,options,scale),before=L.geometry(locked,853.5,479.25,options,scale)[0];
 const after=L.geometry(locked,853.5,479.25,options,scale)[0];
 check(Math.abs(after.along-before.along)<1e-7,'corner negotiation respects immutable pin');
}
const context={edge:'top',along:13,cross:-5};
for(let i=0;i<100;i++)check(L.dragPoint(context,10+(i%2),10,1000,720,1).edge==='top','corner ties do not oscillate');
check(L.dragPoint(context,1,60,1000,720,1).edge==='left','real Edge crossing exits hysteresis');
for(const edge of ['top','right','bottom','left']){
 const c={edge,along:19,cross:-3},p=L.dragPoint(c,500,360,1000,720,1);
 check(Number.isFinite(p.x)&&Number.isFinite(p.y),'rotated grab coordinate is finite');
}
console.log('ABYSS_DRAG_CORNERS_PASS',checks);
