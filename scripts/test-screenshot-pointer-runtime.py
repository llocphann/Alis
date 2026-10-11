#!/usr/bin/env python3
"""Actual region pointer/cancel and annotation export/close on an isolated Abyss host."""
import json, os, struct, sys, tempfile, subprocess, signal
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from native_test_session import private_wayland, run_qs
with tempfile.TemporaryDirectory(prefix='alis-host-capture-') as name:
 p=Path(name)
 for e in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:
  (p/e).symlink_to(ROOT/e)
 (p/'shell.qml').write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.regionSelector
import qs.modules.abyss
import qs.services.deferred
import qs.modules.common.widgets
ShellRoot {
 id:root
 readonly property string scratch: Quickshell.env("CAPTURE_TEST_ROOT")
 property int copies:0
 property int edits:0
 property int canceled:0
 Component.onCompleted: Quickshell.watchFiles=false
 AbyssPerimeter { id:perimeter }
 FloatingWindow {
  title:"Alis synthetic screenshot target"
  visible:true;implicitWidth:640;implicitHeight:480;color:"#10242b"
  Rectangle {anchors.fill:parent;color:Qt.hsla(root.copies/12,.35,.14,1)}
  CliphistImage {id:preview;x:24;y:24;maxWidth:160;maxHeight:108;width:implicitWidth;height:implicitHeight;entry:Cliphist.entries[0] ?? ""}
 }
 PanelWindow {
  anchors {left:true;right:true;top:true;bottom:true}
  color:"#10242b"
  Rectangle {anchors.fill:parent;color:"#10242b"}
 }
 Loader {
  id:selector
  active:GlobalStates.regionSelectorOpen
  sourceComponent:RegionSelection {
   screen:Quickshell.screens[0]
   screenshotDir:root.scratch+"/source"
   action:GlobalStates.regionSelectorAction
   onDismiss:GlobalStates.regionSelectorOpen=false
  }
 }
 Loader {
  id:annotation
  active:GlobalStates.annotationEditorOpen
  sourceComponent:AnnotationEditor {_outPath:root.scratch+"/annotated.png"}
 }
 TestCase {
  id:test;when:false;optional:true
  function check(v,m){if(!v)throw new Error(m)}
  function visual(item,predicate){
   if(predicate(item))return item
   for(const child of item.children ?? []){const found=visual(child,predicate);if(found)return found}
   return null
  }
  function releaseRegion(s){
   const area=visual(s.contentItem,item=>item.cursorShape===Qt.CrossCursor)
   check(area,"actual region MouseArea missing")
   mousePress(area,60,60,Qt.LeftButton)
   mouseMove(area,140,110,20)
   mouseMove(area,220,156,20)
   check(s.dragging && s.regionWidth===160 && s.regionHeight===96,"pointer did not update selected region")
   mouseRelease(area,220,156,Qt.LeftButton)
  }
  function openSelection(action,ready){
   GlobalStates.regionSelectorAction=action
   GlobalStates.regionSelectorMode=0
   GlobalStates.regionSelectorOpen=true
   tryVerify(()=>selector.item!==null,4000)
   check(selector.item!==null,"selector did not mount")
   if(ready){tryVerify(()=>selector.item?.screenshotReady && selector.item?.visible,6000);check(selector.item?.screenshotReady && selector.item?.visible,"private grim capture/menu was not ready");wait(50)}
  }
  function runChecks(){try{
   tryCompare(Config,"ready",true,8000)
   Config.setNestedValue("panelFamily","abyss")
   Config.setNestedValue("enabledPanels",["abyssPerimeter","abyssBar","abyssDock","abyssDashboard","abyssClipboard","abyssOverview"])
   Config.setNestedValue("abyss.companion.enabled",false)
   GlobalStates.shellEntryReady=true;GlobalStates.deferredPanelsReady=true
   wait(2500)
   Config.setNestedValue("regionSelector.targetRegions.content",false)
   Config.setNestedValue("regionSelector.savePath",root.scratch+"/saved")
   Config.setNestedValue("regionSelector.screenshotNameFormat","fixture-%Y%m%d-%H%M%S-%N")
   Config.setNestedValue("regionSelector.annotation.useNativeEditor",true)
   Config.setNestedValue("performance.reduceAnimations",true)
   console.info("CAPTURE_PHASE", "cancel");
   for(let i=0;i<10;i++){
    openSelection(RegionSelection.SnipAction.Copy,true)
    const close=visual(selector.item.contentItem,item=>item.iconText==="close")
    check(close,"actual close toolbar action missing")
    mouseClick(close);wait(40)
    check(!GlobalStates.regionSelectorOpen && selector.item===null,"canceled selector leaked a window")
    root.canceled++
   }
   console.info("CAPTURE_PHASE", "copy");
   for(let i=0;i<10;i++){
    openSelection(RegionSelection.SnipAction.Copy,true)
    const s=selector.item
    releaseRegion(s);wait(220)
    check(!GlobalStates.regionSelectorOpen && selector.item===null,"copy did not release selector")
    Cliphist.refresh();wait(350);root.copies++
   }
   console.info("CAPTURE_PHASE", "edit-export");
   for(let i=0;i<3;i++){
    openSelection(RegionSelection.SnipAction.Edit,true)
    const s=selector.item
    releaseRegion(s)
    tryVerify(()=>annotation.item!==null,5000)
    check(annotation.item!==null,"native editor did not receive crop")
    wait(180)
    annotation.item.exportImage()
    tryVerify(()=>!GlobalStates.annotationEditorOpen,5000)
    check(!GlobalStates.annotationEditorOpen,"annotation export did not close")
    wait(220);root.edits++
   }
   console.info("CAPTURE_PHASE", "export-close-race");
   for(let i=0;i<10;i++){
    openSelection(RegionSelection.SnipAction.Edit,true)
    const s=selector.item
    releaseRegion(s)
    tryVerify(()=>annotation.item!==null,5000);wait(180)
    annotation.item.exportImage();annotation.item.exportImage();annotation.item.close()
    tryVerify(()=>!GlobalStates.annotationEditorOpen,5000)
    check(!GlobalStates.annotationEditorOpen,"annotation close did not settle")
    wait(300)
   }
   console.info("CAPTURE_PHASE", "export-close-race-finished")
   console.info("HOST_CAPTURE_POINTER_PASS",root.copies,root.edits,root.canceled)
  }catch(e){console.error("HOST_CAPTURE_POINTER_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
 with private_wayland(p) as env:
  if env is None: raise SystemExit('SKIP: private Wayland needed')
  runtime=p/'private-runtime';runtime.mkdir(mode=0o700)
  env=dict(env,CAPTURE_TEST_ROOT=str(p),WAYLAND_DISPLAY=str(Path(env['XDG_RUNTIME_DIR'])/env['WAYLAND_DISPLAY']),XDG_RUNTIME_DIR=str(runtime))
  config=p/'config/illogical-impulse';config.mkdir(parents=True,exist_ok=True)
  data=json.loads((ROOT/'defaults/config.json').read_text())
  data['panelFamily']='abyss';data['abyss']['companion']['enabled']=False
  (config/'config.json').write_text(json.dumps(data))
  watcher=subprocess.Popen(["wl-paste","--type","image","--watch","cliphist","store"],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
  try: result=run_qs(p,env,timeout=110)
  finally:
   if watcher.poll() is None:
    os.killpg(watcher.pid,signal.SIGTERM);watcher.wait(timeout=5)
  if os.environ.get('ALIS_CAPTURE_TEST_LOG'):
   Path(os.environ['ALIS_CAPTURE_TEST_LOG']).write_text(result.stdout)
  print('qs_exit',result.returncode)
  for l in result.stdout.splitlines():
   if any(x in l for x in ['CAPTURE_PHASE','HOST_CAPTURE_POINTER','ERROR','WARN','TypeError','ReferenceError']):print(l)
  saved=list((p/'saved').glob('*.png'))
  print('synthetic_png_count',len(saved))
  for f in saved:
   data=f.read_bytes();assert data[:8]==b'\x89PNG\r\n\x1a\n'
   assert struct.unpack('>II',data[16:24])==(160,96),(f.name,struct.unpack('>II',data[16:24]))
  if result.returncode or 'HOST_CAPTURE_POINTER_PASS' not in result.stdout or any(x in result.stdout for x in ['HOST_CAPTURE_POINTER_FAIL','TypeError:','ReferenceError:','Binding loop','invalid context']):sys.exit(1)
  assert len(saved)==23,'accepted export/close lost a capture or duplicate export saved twice'
  print('PASS: 10 actual pointer copies, 10 toolbar cancels, 3 exports and 10 duplicate-export/close races; 23 PNG saves')
