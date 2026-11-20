#!/usr/bin/env python3
"""Exercise production wallpaper search handlers across content lifetimes."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
subprocess.run(["node", "-e", r'''
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(process.argv[1],'utf8');
const field=source.slice(source.indexOf('id:search;'),source.indexOf('onAccepted:',source.indexOf('id:search;')));
const initial=field.match(/\n\s*text:([^\n]+)/)[1],changed=field.match(/onTextChanged:([^\n]+)/)[1];
const modeBody=source.match(/function setMode\([^)]*\):\s*void\s*\{([\s\S]*?)\n    \}/)[1];
const keyBody=source.match(/Keys.onPressed:event=>\{([\s\S]*?)\n    \}/)[1];
const GlobalStates={wallpaperLauncherMode:'static',wallpaperLauncherSearchText:'saved query',wallpaperLauncherOpen:true};
let focus=0,sync=0;
const Qt={Key_Escape:1,Key_Left:2,Key_Up:3,Key_Right:4,Key_Down:5,Key_Return:6,Key_Enter:7,Key_Tab:8,Key_Backtab:9,ControlModifier:1,callLater:fn=>fn()};
const context={GlobalStates,Qt,carousel:{scheduleIndexSync:()=>sync++},moveSelection:()=>{},activateCurrent:()=>{}};
vm.createContext(context);
context.setMode=mode=>{context.nextMode=mode;vm.runInContext('(function(){'+modeBody+'})()',context)};
function mount(){
 let value=vm.runInContext(initial,context);
 const search={forceActiveFocus:()=>focus++};
 Object.defineProperty(search,'text',{get:()=>value,set:v=>{value=v;context.text=v;vm.runInContext(changed,context)}});
 context.search=search;return search;
}
let search=mount();assert.equal(search.text,'saved query','new presentation lost persisted query');
search.text='room';assert.equal(GlobalStates.wallpaperLauncherSearchText,'room');
context.event={key:0,text:'x',modifiers:0,accepted:false};vm.runInContext(keyBody,context);
assert.equal(search.text,'roomx');assert.equal(GlobalStates.wallpaperLauncherSearchText,'roomx');assert.equal(focus,1);assert.equal(context.event.accepted,true);
context.event={key:0,text:'c',modifiers:Qt.ControlModifier,accepted:false};vm.runInContext(keyBody,context);assert.equal(search.text,'roomx','Ctrl shortcut polluted query');
search=mount();assert.equal(search.text,'roomx','content teardown lost query');
context.setMode('animated');assert.equal(GlobalStates.wallpaperLauncherMode,'animated');assert.equal(GlobalStates.wallpaperLauncherSearchText,'');assert.equal(sync,1);
search=mount();assert.equal(search.text,'');search.text='new';context.setMode('invalid');assert.equal(GlobalStates.wallpaperLauncherSearchText,'new');assert.equal(sync,1);
context.setMode('static');assert.equal(GlobalStates.wallpaperLauncherMode,'static');assert.equal(GlobalStates.wallpaperLauncherSearchText,'');assert.equal(sync,2);
console.log('Wallpaper query lifecycle: PASS restore typing shortcut teardown mode-clear invalid-mode');
for(const file of ['modules/ii/ShellIiPanelsImpl.qml','modules/waffle/ShellWafflePanelsImpl.qml']){
 const shell=fs.readFileSync(process.argv[2]+'/'+file,'utf8');
 const matches=[...shell.matchAll(/OnDemandPanelLoader\s*\{\s*identifier:\s*"iiWallpaperSelector";([\s\S]*?)component:\s*WallpaperLauncher\s*\{/g)];
 assert.equal(matches.length,1,file+' must have exactly one wallpaper presentation');
 assert.ok(!/identifier:\s*"iiWallpaperLauncher"|identifier:\s*"iiCoverflowSelector"/.test(shell),file+' retained a retired second presentation');
 const body=matches[0][1],open=body.match(/open:\s*([^;]+);/)[1],grace=body.match(/closeGraceMs:\s*([^;]+);/)[1];
 assert.ok(!/(retainAfterUse|keepLoaded):\s*true/.test(body),file+' retained wallpaper content while closed');
 const loader=shell.match(/component OnDemandPanelLoader:[^{]+\{([\s\S]*?)\n    \}/)[1];
 const defaults={};for(const [,name,value] of loader.matchAll(/property bool (\w+):\s*(true|false)\b/g))defaults[name]=value==='true';
 const resident=loader.match(/property bool resident:\s*([^\n]+)/)[1],close=loader.match(/onTriggered:\s*([^\n]+)/)[1];
 assert.equal(vm.runInNewContext(resident,{...defaults,open:false}),false,file+' closed host remained resident');
 assert.equal(vm.runInNewContext(resident,{...defaults,open:true}),true,file+' open host was not resident');
 const onDemandLoader={...defaults,open:false,resident:true};vm.runInNewContext(close,{onDemandLoader});assert.equal(onDemandLoader.resident,false,file+' close grace failed to release content');
 onDemandLoader.open=true;vm.runInNewContext(close,{onDemandLoader});assert.equal(onDemandLoader.resident,true,file+' reopened content was released by a stale close callback');
 for(const animationsEnabled of [true,false])for(const duration of [0,180,400,1500]){
  const scope={Appearance:{animationsEnabled,animation:{elementMoveExit:{duration}}},GlobalStates:{wallpaperLauncherOpen:true}};
  assert.equal(vm.runInNewContext(open,scope),true);scope.GlobalStates.wallpaperLauncherOpen=false;assert.equal(vm.runInNewContext(open,scope),false);
  assert.equal(vm.runInNewContext(grace,scope),animationsEnabled ? Math.max(240,duration+60) : 40);
 }
}
console.log('Wallpaper single presentation lifecycle: PASS ii and Waffle, open/close, motion grace, no hidden retention');
''', str(ROOT / "modules/wallpaperLauncher/WallpaperLauncherContent.qml"), str(ROOT)], check=True)
