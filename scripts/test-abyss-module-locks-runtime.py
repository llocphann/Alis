#!/usr/bin/env python3
"""Real QV4/bar/editor reservation, input, undo and private JSON restart."""
import json, os, tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs
ROOT=Path(__file__).resolve().parents[1]
QML=r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss
import qs.modules.abyss.bar
import qs.modules.abyss.looks
ShellRoot {
 id:root
 property int checks:0
 property int frames:0
 property string action:Quickshell.env("LOCK_ACTION")
 Component.onCompleted:Quickshell.watchFiles=false
 AbyssSurfaceController {id:liquid}
 FileView {id:disk;path:Config.filePath;watchChanges:true;property var snapshot:null;onFileChanged:reload();onLoaded:{try{snapshot=JSON.parse(text())}catch(error){snapshot=null}}}
 FloatingWindow {
  visible:true;implicitWidth:1000;implicitHeight:740;color:"#111820"
  Item {
   id:scene;anchors.fill:parent
   AbyssBar {id:layer;anchors.fill:parent;outputName:"A";edge:"top";editing:editor.visible;draftPlacements:!Config.ready?[]:editor.visible?editor.draft:null;draftOptions:editor.visible?editor.draftOptions:null;liquidController:liquid}
   AbyssEdgeEditor {id:editor;anchors.fill:parent;outputName:"A";moduleLayer:layer;controller:liquid;visible:GlobalStates.abyssEditing}
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(ok,label){root.checks++;if(!ok)throw new Error(label)}
  function record(id){return layer.layoutRecords.find(p=>p.id===id)}
  function capture(label){let done=false;scene.grabToImage(result=>{done=result.saveToFile(Quickshell.env("LOCK_EVIDENCE")+"/"+root.action+"-"+label+".png")});tryVerify(()=>done,4000);root.frames++}
  function handle(id){return children(editor).find(item=>item.objectName==="abyssModuleHandle"&&item.modelData===id)}
  function children(item){let all=[];for(const child of item.children??[])all=all.concat([child],children(child));return all}
  function onOutput(edge,point){return {x:["top","bottom"].includes(edge)?point:edge==="left"?8:editor.width-8,y:["left","right"].includes(edge)?point:edge==="top"?8:editor.height-8}}
  function drag(item,point){mousePress(item,item.width/2,item.height/2);const local=item.mapFromItem(scene,point.x,point.y);mouseMove(item,local.x,local.y,50);mouseRelease(item,local.x,local.y);wait(60)}
  function visibleControl(name){
   const item=findChild(editor,name);let view=item.parent
   while(view && view.contentHeight===undefined)view=view.parent
   check(!!view,"control must have a scrolling viewport")
   const point=item.mapToItem(view.contentItem,0,0)
   view.contentY=Math.max(0,Math.min(view.contentHeight-view.height,point.y-view.height/2));wait(80)
   capture(name)
   const actual=item.mapToItem(view,0,0)
   check(actual.y>=-1&&actual.y+item.height<=view.height+1,"control must be inside its input clip")
   return item
  }
  function stable(id,before){const actual=record(id);check(actual.edge===before.edge&&Math.abs(actual.along-before.along)<.05&&Math.abs(actual.span-before.span)<.05,"locked rendered slot changed")}
  function saved(predicate){disk.reload();wait(70);return predicate(disk.snapshot)}
  function run(){try{
   tryCompare(Config,"ready",true,6000)
   Config.setNestedValue("panelFamily","abyss");Config.setNestedValue("performance.reduceAnimations",true)
   GlobalStates.deferredPanelsReady=true
   if(root.action==="restart"){
    capture("saved")
    check(layer.placements.find(p=>p.id==="a")?.locked,"global lock did not survive actual process restart")
    check(layer.placements.find(p=>p.id==="b")?.edge==="left","global neighbor placement did not survive restart")
    check(Config.options.abyss.modules.outputLayouts.some(p=>p.outputName==="B"),"other output profile lost at restart")
   } else {
    Config.setNestedValue("abyss.modules.configured",true)
    Config.setNestedValue("abyss.modules.placements",[{id:"a",kind:"clock",edge:"top",position:.2},{id:"b",kind:"clock",edge:"top",position:.55},{id:"c",kind:"clock",edge:"top",position:.82}])
    Config.setNestedValue("abyss.modules.outputLayouts",[{outputName:"B",placements:[],edgeJoinModules:{left:true}}])
    const original=JSON.stringify(Config.options.abyss.modules.placements)
    GlobalStates.abyssEditing=true;wait(120);capture("initial")
    const mature=layer.itemForId("a")
    for(const edge of ["top","right","bottom","left"]){
     const length=["top","bottom"].includes(edge)?editor.width:editor.height
     const center=onOutput(edge,length*.3)
     editor.move("a",center.x,center.y,false);wait(60);capture(edge+"-unlocked")
     editor.selectedId="a"
     const control=visibleControl("abyssModulePositionLock")
     if(edge==="top")mouseClick(control)
     else {control.forceActiveFocus();keyClick(Qt.Key_Return)}
     wait(60);capture(edge+"-locked")
     const own=JSON.parse(JSON.stringify(record("a")))
     check(own.locked&&control.text==="Unlock position","lock control/glyph did not reflect selection")
     const raw=JSON.stringify(editor.draft.find(p=>p.id==="a"))
     drag(handle("a"),onOutput(edge,length*.8));stable("a",own)
     check(editor.feedback.length>0,"locked drag lacks feedback")
     const target=onOutput(edge,own.along+own.span/2)
     editor.move("b",target.x,target.y,true);capture(edge+"-collision");stable("a",own)
     check(JSON.stringify(editor.draft.find(p=>p.id==="a"))===raw,"neighbor snap rewrote saved lock metadata")
     editor.selectedId="b";editor.change("customSize",true);editor.change("size",1.8);wait(60);capture(edge+"-resize");stable("a",own)
     check(layer.itemForId("a")===mature,"editing replaced mature module instance")
     check(!editor.layoutConflicts.length,"ordinary neighbor edits made feasible locks invalid")
     editor.selectedId="a";handle("a").forceActiveFocus();keyClick(Qt.Key_L);wait(60)
     check(!editor.selected.locked,"accessible handle shortcut failed to Unlock")
     check(JSON.stringify(Config.options.abyss.modules.placements)===original,"draft wrote global Config before Done")
     editor.finish(false);GlobalStates.abyssEditing=true;wait(80)
    }
    editor.selectedId="a";editor.change("alignment","start");wait(60);editor.toggleLock("a");wait(60);capture("undo-before")
    const locked=JSON.stringify(editor.draft),own=JSON.parse(JSON.stringify(record("a")))
    editor.moduleScale=1.8;wait(60);capture("infeasible-size")
    check(editor.layoutConflicts.length>0,"infeasible output size lacks visible conflict")
    editor.finish(true);check(GlobalStates.abyssEditing,"Done accepted an infeasible lock fallback")
    check(JSON.stringify(Config.options.abyss.modules.placements)===original,"conflict mutated saved placement")
    editor.forceActiveFocus();keyClick(Qt.Key_Z,Qt.ControlModifier);wait(60);capture("undo-size")
    check(editor.moduleScale===1&&!editor.layoutConflicts.length,"Undo did not restore feasible geometry")
    stable("a",own)
    editor.reset();wait(60);check(!editor.draft.some(p=>p.locked),"Reset left old locks active")
    editor.undo();wait(60);check(JSON.stringify(editor.draft)===locked,"Undo Reset lost per-ID locks")
    editor.finish(true);tryVerify(()=>saved(data=>data?.abyss?.modules?.outputLayouts?.find(p=>p.outputName==="A")?.placements?.find(p=>p.id==="a")?.locked),5000)
    check(Config.options.abyss.modules.outputLayouts[0].outputName==="B","output-only Done replaced another profile")
    GlobalStates.abyssEditing=true;wait(80);check(editor.draft.find(p=>p.id==="a").locked,"saved profile did not reopen with Lock")
    editor.outputOnly=false;editor.selectedId="b";editor.move("b",8,editor.height*.7,false);wait(60)
    editor.finish(true);tryVerify(()=>saved(data=>data?.abyss?.modules?.placements?.find(p=>p.id==="a")?.locked&&!data.abyss.modules.outputLayouts.some(p=>p.outputName==="A")),5000)
    capture("saved-global")
    GlobalStates.abyssEditing=true;wait(80);editor.selectedId="a";editor.toggleLock("a");wait(60)
    const concurrent=Array.from(Config.options.abyss.modules.placements).map(p=>p.id==="c"?Object.assign({},p,{position:.97}):p)
    Config.setNestedValue("abyss.modules.placements",concurrent)
    editor.reset();wait(60);editor.undo();wait(60);editor.finish(true)
    check(GlobalStates.abyssEditing&&editor.feedback.length>0,"Undo Reset accepted a concurrent external layout")
    check(Config.options.abyss.modules.placements.find(p=>p.id==="c").position===.97&&Config.options.abyss.modules.placements.find(p=>p.id==="a").locked,"refused Save overwrote external geometry/locks")
    editor.finish(false)
   }
   console.info("ABYSS_LOCK_NATIVE_PASS",root.action,root.checks,"checks",root.frames,"frames")
  }catch(error){console.error("ABYSS_LOCK_NATIVE_FAIL",error.message,error.stack,JSON.stringify(editor.layoutConflicts))}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''
with tempfile.TemporaryDirectory(prefix="alis-edge-locks-") as name:
    folder=Path(name)
    for entry in ["modules","services","GlobalStates.qml","qmldir","assets","scripts","defaults","translations"]:(folder/entry).symlink_to(ROOT/entry)
    (folder/"shell.qml").write_text(QML)
    dest=Path(os.environ.get("ALIS_LOCK_EVIDENCE",folder/"evidence")).resolve();dest.mkdir(parents=True,exist_ok=True)
    with private_wayland(folder, capture_focus=False) as env:
        if not env:print("SKIP: lock native test requires private Niri");raise SystemExit(0)
        cfg=folder/"config/illogical-impulse";cfg.mkdir(parents=True,exist_ok=True)
        data=json.loads((ROOT/"defaults/config.json").read_text());data["panelFamily"]="abyss"
        data["abyss"]["modules"]["configured"]=True
        data["abyss"]["modules"]["placements"]=[{"id":id,"kind":"clock","edge":"top","position":position} for id,position in [("a",.2),("b",.55),("c",.82)]]
        (cfg/"config.json").write_text(json.dumps(data))
        env.update(LOCK_EVIDENCE=str(dest),QT_QUICK_BACKEND="software")
        for action in ["exercise","restart"]:
            result=run_qs(folder,dict(env,LOCK_ACTION=action),timeout=50)
            (dest/(action+".log")).write_text(result.stdout)
            if result.returncode or "ABYSS_LOCK_NATIVE_PASS" not in result.stdout or any(token in result.stdout for token in ["ABYSS_LOCK_NATIVE_FAIL","ReferenceError:","TypeError:","Binding loop","Unable to assign","is not a type","Failed to load configuration"]):
                print(result.stdout);raise SystemExit(1)
            # QML saves through Config.filePath in the canonical Alis namespace.
            # The historical seed must remain intact rather than be read as output.
            assert (cfg/"config.json").read_text() == json.dumps(data)
            receipt=json.loads((folder/"config/alis/config.json").read_text())
            assert receipt["abyss"]["modules"]["placements"][0]["locked"]
            (dest/(action+"-config.json")).write_text(json.dumps(receipt["abyss"]["modules"],indent=2)+"\n")
            for line in result.stdout.splitlines():
                if "ABYSS_LOCK_NATIVE_PASS" in line:print(line)
