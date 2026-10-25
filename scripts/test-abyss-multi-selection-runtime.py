#!/usr/bin/env python3
"""Actual QV4 multi-selection input, transaction/Undo and private JSON restart."""
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
 property string action:Quickshell.env("MULTI_ACTION")
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
  function children(item){let all=[];for(const child of item.children??[])all=all.concat([child],children(child));return all}
  function handle(id){return children(editor).find(item=>item.objectName==="abyssModuleHandle"&&item.modelData===id)}
  function rec(id){return layer.layoutRecords.find(p=>p.id===id)}
  function capture(label){let done=false;scene.grabToImage(result=>{done=result.saveToFile(Quickshell.env("MULTI_EVIDENCE")+"/"+root.action+"-"+label+".png")});tryVerify(()=>done,4000);root.frames++}
  function control(name){
   const item=findChild(editor,name);let view=item.parent
   while(view && view.contentHeight===undefined)view=view.parent
   check(!!view,"control must have a scrolling viewport")
   const point=item.mapToItem(view.contentItem,0,0)
   view.contentY=Math.max(0,Math.min(view.contentHeight-view.height,point.y-view.height/2));wait(80)
   capture(name)
   const actual=item.mapToItem(view,0,0)
   check(actual.y>=-1&&actual.y+item.height<=view.height+1&&actual.x>=-1&&actual.x+item.width<=view.width+1,"control must be fully inside its input clip")
   return item
  }
  function point(edge,along){return {x:["top","bottom"].includes(edge)?along:edge==="left"?8:editor.width-8,y:["left","right"].includes(edge)?along:edge==="top"?8:editor.height-8}}
  function drag(id,edge,along){
   const item=handle(id),dest=point(edge,along)
   mousePress(item,item.width/2,item.height/2)
   const local=item.mapFromItem(scene,dest.x,dest.y)
   mouseMove(item,local.x,local.y,50);mouseRelease(item,local.x,local.y);wait(100)
  }
  function saved(predicate){disk.reload();wait(70);return predicate(disk.snapshot)}
  function run(){try{
   tryCompare(Config,"ready",true,6000)
   Config.setNestedValue("panelFamily","abyss");Config.setNestedValue("performance.reduceAnimations",true);GlobalStates.deferredPanelsReady=true
   if(root.action==="restart"){
    capture("saved")
    check(layer.placements.filter(p=>["a","b"].includes(p.id)).every(p=>p.locked&&p.customSize&&p.size===1.1),"batch saved flags/sizes did not survive process restart")
    check(Config.options.abyss.modules.outputLayouts.some(p=>p.outputName==="B"),"another output was lost at restart")
    GlobalStates.abyssEditing=true;wait(100)
    check(!editor.multiSelect&&editor.targetIds.length===0,"transient selection leaked into restart")
    editor.finish(false)
   } else {
    Config.setNestedValue("abyss.modules.configured",true)
    Config.setNestedValue("abyss.modules.placements",[{id:"a",kind:"clock",edge:"top",position:.2},{id:"b",kind:"clock",edge:"top",position:.38},{id:"c",kind:"clock",edge:"top",position:.84},{id:"d",kind:"clock",edge:"left",position:.2}])
    Config.setNestedValue("abyss.modules.outputLayouts",[{outputName:"B",placements:[],edgeJoinModules:{left:true}}])
    const original=JSON.stringify(Config.options.abyss.modules.placements),other=JSON.stringify(Config.options.abyss.modules.outputLayouts[0])
    GlobalStates.abyssEditing=true;wait(100)
    const mature=layer.itemForId("c")
    check(!findChild(editor,"abyssMultiSelection"),"obsolete selection-mode toggle remains visible")
    mouseClick(handle("a"))
    mouseClick(handle("b"),handle("b").width/2,handle("b").height/2,Qt.LeftButton,Qt.ControlModifier)
    wait(80);capture("two-selected")
    check(editor.targetIds.length===2&&findChild(editor,"abyssSelectionCount").text.startsWith("2 selected"),"pointer adds/count/glyph selection")
    mouseClick(handle("b"),handle("b").width/2,handle("b").height/2,Qt.LeftButton,Qt.ControlModifier)
    check(editor.targetIds.length===1&&editor.selectedId==="a","Ctrl-click did not remove target coherently")
    handle("b").forceActiveFocus();keyClick(Qt.Key_Space,Qt.ControlModifier);check(editor.targetIds.length===2,"Ctrl+Space did not add accessible target")
    // The editor has no selection-mode switch: Shift forms a contiguous visual
    // interval from the last ordinary-click anchor, Ctrl+Shift extends it.
    mouseClick(handle("a"))
    mouseClick(handle("c"),handle("c").width/2,handle("c").height/2,Qt.LeftButton,Qt.ShiftModifier)
    check(JSON.stringify(editor.targetIds)===JSON.stringify(["a","b","c"]), "Shift-click failed ordered three-module range")
    mouseClick(handle("d"),handle("d").width/2,handle("d").height/2,Qt.LeftButton,Qt.ControlModifier|Qt.ShiftModifier)
    check(editor.targetIds.length===4&&editor.targetIds.includes("d"),"Ctrl+Shift-click failed cross-Edge range extension")
    mouseClick(handle("a"));mouseClick(handle("b"),handle("b").width/2,handle("b").height/2,Qt.LeftButton,Qt.ControlModifier)
    check(editor.targetIds.length===2,"ordinary click did not collapse range back to a single anchor")
    const offset=rec("b").along-rec("a").along
    drag("a","top",editor.width*.3);capture("horizontal-drag")
    check(editor.targetIds.length===2,"selected group collapsed on drag press")
    check(!editor.feedback&&Math.abs(rec("b").along-rec("a").along-offset)<.1,"same Edge group drag distorted rendered spacing")
    const group=JSON.stringify(editor.draft)
    // A click on an already selected handle (without dragging) must still
    // collapse a group to a single ordinary selection.
    mouseClick(handle("a"));check(editor.targetIds.length===1&&editor.selectedId==="a",
        "ordinary click did not collapse existing group on release")
    mouseClick(handle("b"),handle("b").width/2,handle("b").height/2,Qt.LeftButton,Qt.ControlModifier)
    check(editor.targetIds.length===2,"Ctrl-click did not restore group after ordinary click")
    const lock=control("abyssModulePositionLock");lock.forceActiveFocus();keyClick(Qt.Key_Return);wait(80)
    check(editor.allTargetsLocked&&lock.text==="Unlock position","Enter did not lock exact group")
    const locked=JSON.stringify(editor.draft)
    editor.change("size",1.8);check(editor.feedback.length>0&&JSON.stringify(editor.draft)===locked,"mixed locked resize was not atomic")
    drag("a","bottom",editor.width*.6);check(editor.feedback.length>0&&JSON.stringify(editor.draft)===locked,"locked group drag partially changed source")
    editor.forceActiveFocus();keyClick(Qt.Key_Z,Qt.ControlModifier);wait(80)
    check(JSON.stringify(editor.draft)===group&&editor.targetIds.length===2,"Undo Lock lost exact targets/placement")
    for(const edge of ["right","bottom","left","top"]){
     const length=["top","bottom"].includes(edge)?editor.width:editor.height
     const gap=rec("b").along-rec("a").along-rec("a").span
     drag("a",edge,length*.3);capture(edge+"-drag")
     check(!editor.feedback&&editor.targets.every(p=>p.edge===edge),"group did not cross to "+edge+": "+editor.feedback)
     check(rec("a").along+rec("a").span<=rec("b").along+.1,"group order/overlap after "+edge)
     check(Math.abs(rec("b").along-rec("a").along-rec("a").span-gap)<.1,"rendered gap changed across "+edge)
     check(layer.itemForId("c")===mature,"group drag recreated an unrelated mature module")
    }
    mouseClick(handle("d"),handle("d").width/2,handle("d").height/2,Qt.LeftButton,Qt.ControlModifier);
    check(editor.targets.length===3,"cross-Edge Ctrl-click add failed")
    const mixed=JSON.stringify(editor.draft);drag("a","top",editor.width*.6)
    check(editor.feedback.length>0&&JSON.stringify(editor.draft)===mixed,"mixed Edge drag must reject entire transaction")
    editor.change("customSize",true);editor.change("size",1.1);wait(80)
    check(editor.targets.every(p=>p.customSize&&p.size===1.1)&&!editor.draft.find(p=>p.id==="c").customSize,"cross-Edge size batch changed an unrelated module")
    const disabled=control("abyssSelectionEnabled");mouseClick(disabled);wait(80)
    check(editor.targets.every(p=>!p.enabled),"Disable did not apply coherently")
    mouseClick(disabled);wait(80);check(editor.targets.every(p=>p.enabled),"Enable lost exact disabled selection")
    const beforeRemove=JSON.stringify(editor.draft)
    mouseClick(control("abyssSelectionRemove"));wait(80)
    check(editor.draft.length===1&&editor.draft[0].id==="c"&&editor.targetIds.length===0,"Remove left stale targets or removed unrelated module")
    editor.undo();wait(80);check(JSON.stringify(editor.draft)===beforeRemove&&editor.targetIds.length===3,"Undo Remove lost placement or selection")
    mouseClick(control("abyssSelectionClear"));check(editor.targetIds.length===0,"Clear selection did not clear primary/targets")
    editor.forceActiveFocus();keyClick(Qt.Key_A,Qt.ControlModifier);check(editor.targetIds.length===4,"Ctrl+A did not select all this output's modules")
    editor.reset();wait(80);editor.undo();wait(80)
    check(JSON.stringify(editor.draft)===beforeRemove&&editor.targetIds.length===4,"Undo Reset lost draft or selection")
    check(JSON.stringify(Config.options.abyss.modules.placements)===original,"batch draft mutated saved global options")
    editor.clearSelection();editor.select("a");editor.select("b",true)
    editor.startDrag("a");const pending=point("bottom",editor.width*.4)
    editor.move("a",pending.x,pending.y,true);editor.reset()
    const reset=JSON.stringify(editor.draft);wait(100)
    check(JSON.stringify(editor.draft)===reset&&!editor._dragging,"queued group reflow overwrote Reset")
    editor.undo();wait(80)
    editor.startDrag("a");editor.move("a",pending.x,pending.y,true);editor.endDrag();editor.finish(false);wait(100)
    check(!editor._dragging&&JSON.stringify(Config.options.abyss.modules.placements)===original,"queued group settle survived Cancel or wrote saved data")
    GlobalStates.abyssEditing=true;wait(80)
    check(JSON.stringify(editor.draft)===JSON.stringify(layer.placements)&&!editor.multiSelect,"Cancel did not discard batch draft")
    editor.select("a");editor.select("b",true);editor.change("customSize",true);editor.change("size",1.1);editor.lockSelection();wait(80)
    editor.finish(true)
    tryVerify(()=>saved(data=>data?.abyss?.modules?.outputLayouts?.find(p=>p.outputName==="A")?.placements?.filter(p=>["a","b"].includes(p.id)).every(p=>p.locked&&p.size===1.1)),5000)
    check(JSON.stringify(Config.options.abyss.modules.outputLayouts.find(p=>p.outputName==="B"))===other,"output-only batch Save replaced other output")
    check(JSON.stringify(Config.options.abyss.modules.placements)===original,"output-only batch Save changed global source")
    GlobalStates.abyssEditing=true;wait(80);editor.outputOnly=false;editor.finish(true)
    tryVerify(()=>saved(data=>data?.abyss?.modules?.placements?.filter(p=>["a","b"].includes(p.id)).every(p=>p.locked&&p.size===1.1)&&!data.abyss.modules.outputLayouts.some(p=>p.outputName==="A")),5000)
    check(!JSON.stringify(Config.options.abyss.modules.placements).includes("selectedIds"),"selection metadata persisted")
    capture("saved-global")
   }
   console.info("ABYSS_MULTI_NATIVE_PASS",root.action,root.checks,"checks",root.frames,"frames")
  }catch(error){console.error("ABYSS_MULTI_NATIVE_FAIL",error.message,error.stack,JSON.stringify(editor.layoutConflicts),JSON.stringify(editor.targetIds))}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''
with tempfile.TemporaryDirectory(prefix="alis-edge-multi-") as name:
    folder=Path(name)
    for entry in ["modules","services","GlobalStates.qml","qmldir","assets","scripts","defaults","translations"]:(folder/entry).symlink_to(ROOT/entry)
    (folder/"shell.qml").write_text(QML)
    dest=Path(os.environ.get("ALIS_MULTI_EVIDENCE",folder/"evidence")).resolve();dest.mkdir(parents=True,exist_ok=True)
    with private_wayland(folder, capture_focus=False) as env:
        if not env:print("SKIP: multi-selection native test requires private Niri");raise SystemExit(0)
        cfg=folder/"config/illogical-impulse";cfg.mkdir(parents=True,exist_ok=True)
        data=json.loads((ROOT/"defaults/config.json").read_text());data["panelFamily"]="abyss"
        data["abyss"]["modules"]["configured"]=True
        data["abyss"]["modules"]["placements"]=[{"id":id,"kind":"clock","edge":"top","position":pos} for id,pos in [("a",.2),("b",.38),("c",.84)]]
        (cfg/"config.json").write_text(json.dumps(data))
        env.update(MULTI_EVIDENCE=str(dest),QT_QUICK_BACKEND="software")
        for action in ["exercise","restart"]:
            result=run_qs(folder,dict(env,MULTI_ACTION=action),timeout=60)
            (dest/(action+".log")).write_text(result.stdout)
            if result.returncode or "ABYSS_MULTI_NATIVE_PASS" not in result.stdout or any(token in result.stdout for token in ["ABYSS_MULTI_NATIVE_FAIL","ReferenceError:","TypeError:","Binding loop","Unable to assign","is not a type","Failed to load configuration"]):
                print(result.stdout);raise SystemExit(1)
            assert (cfg/"config.json").read_text() == json.dumps(data)
            receipt=json.loads((folder/"config/alis/config.json").read_text())
            assert all(p["locked"] and p["size"]==1.1 for p in receipt["abyss"]["modules"]["placements"] if p["id"] in ["a","b"])
            assert not any(key in json.dumps(receipt["abyss"]["modules"]) for key in ["selectedIds","multiSelect"])
            (dest/(action+"-config.json")).write_text(json.dumps(receipt["abyss"]["modules"],indent=2)+"\n")
            for line in result.stdout.splitlines():
                if "ABYSS_MULTI_NATIVE_PASS" in line:print(line)
