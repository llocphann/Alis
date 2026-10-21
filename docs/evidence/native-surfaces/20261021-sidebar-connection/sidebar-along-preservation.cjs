const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const root=process.argv[2],qml=fs.readFileSync(root+'/modules/abyss/AbyssPerimeter.qml','utf8');
const ctx=vm.createContext({});ctx.Presentation=vm.createContext({});ctx.Geometry=vm.createContext({});
vm.runInContext(fs.readFileSync(root+'/modules/abyss/looks/AbyssPresentation.js','utf8'),ctx.Presentation);
vm.runInContext(fs.readFileSync(root+'/modules/abyss/looks/AbyssGeometry.js','utf8'),ctx.Geometry);
const match=qml.match(/function sidebarAlong\(kind,edge,span\) \{[\s\S]*?\n\s*\}/);assert.ok(match,'actual production helper missing');
ctx.presentation=()=>ctx.saved;
vm.runInContext(qml.match(/function positionAlong\(kind,edge,span,fallback\) \{[^\n]*\}/)[0],ctx);
vm.runInContext(match[0],ctx);
let checks=0;
for(const [width,height] of [[1920,1200],[1280,800],[900,700]])
for(const insets of [{top:48,bottom:16,left:16,right:16},{top:0,bottom:32,left:40,right:4},{top:16,bottom:16,left:0,right:48}])
for(const edge of ['left','right','top','bottom'])
for(const span of [320,400])
for(const alignment of [undefined,'source','center','start','end','custom']) {
 Object.assign(ctx,{width,height,nativeInsets:insets,saved:{edge,alignment,position:.27,customWidth:360,customHeight:400}});
 const original=JSON.stringify(ctx.saved),horizontal=['top','bottom'].includes(edge),length=horizontal?width:height;
 const start=horizontal?insets.left:insets.top,end=length-(horizontal?insets.right:insets.bottom)-span;
 const expected=alignment==='start'?start:alignment==='end'?end:alignment==='custom'?start+.27*(end-start):(length-span)/2;
 assert.ok(Math.abs(ctx.sidebarAlong('leftPanel',edge,span)-expected)<1e-9,JSON.stringify({edge,alignment,expected}));
 assert.equal(JSON.stringify(ctx.saved),original,'position resolution mutated saved dimensions/position');checks++;
}
console.log('SIDEBAR_ALONG_PRESERVATION_PASS',checks,'actual QML center/source/start/end/custom, asymmetric insets, untouched saved values');
