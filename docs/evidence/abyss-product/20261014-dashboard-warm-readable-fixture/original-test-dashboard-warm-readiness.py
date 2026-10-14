#!/usr/bin/env python3
"""Large real canvases reuse briefly while hidden, then release their tree."""
import json,tempfile
from pathlib import Path
from native_test_session import private_wayland,run_qs
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="hadalis-dashboard-warm-") as name:
 folder=Path(name)
 for entry in ["modules","services","GlobalStates.qml","qmldir","assets","scripts","defaults","translations"]:(folder/entry).symlink_to(ROOT/entry)
 (folder/"shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss
ShellRoot {
 id:root
 property bool shown:false
 property string route:"Dashboard"
 Component.onCompleted:Quickshell.watchFiles=false
 PanelWindow {
  id:window;visible:true;color:"#111820"
  anchors {top:true;bottom:true;left:true;right:true}
  exclusionMode:ExclusionMode.Ignore
  AbyssBodyHost {
   id:body;anchors.fill:parent;identity:"dashboard";edge:"bottom"
   open:root.shown;animatePresentation:false;stableContentSize:true;warmContent:true;largeSurface:true
   span:width*.88;depth:height*.88;along:width*.06
   source:Qt.resolvedUrl("modules/abyss/content/Abyss"+root.route+"Content.qml")
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(v,m){if(!v)throw new Error(m)}
  function find(item,p){if(p(item))return item;for(const c of item.children??[]){const r=find(c,p);if(r)return r}return null}
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000);GlobalStates.deferredPanelsReady=true
   check(!body.ready,"closed canvas eagerly allocated")
   for(const route of ["Dashboard","Overview"]){
    root.route=route;root.shown=true;tryVerify(()=>body.ready,6000)
    const content=body.contentItem.item,canvas=find(content,i=>typeof i.beginEditMode==="function")
    check(canvas!==null,"missing real canvas")
    Config.setNestedValue("dashboard.canvas.widgets",canvas.defaultEntries().map(p=>Object.assign({},p,{visible:["system","weather","media"].includes(p.id),x:p.id==="media"?.66:p.id==="weather"?.33:0,y:0,w:.31,h:.8})))
    wait(200)
    const weather=find(content,i=>i.hasData!==undefined && i.now!==undefined)
    const media=find(content,i=>i.hasPlayer!==undefined && i.presentationActive!==undefined)
    check(weather?.visible && media?.presentationActive,"fixture missed active cards "+route+" weather="+weather+" visible="+weather?.visible+" media="+media+" active="+media?.presentationActive+" body="+body.progress+" visibleIds="+JSON.stringify(canvas.visibleIds)+" dimensions="+canvas.width+"x"+canvas.height)
    check(ResourceUsage._persistentConsumers>0,"system card never acquired sampling")
    if(route==="Overview")check(content.heldLease!=="","overview sorting not acquired")
    canvas.beginEditMode();canvas.setWidgetVisible("notes",true)
    root.shown=false;wait(150)
    check(body.ready && body.contentItem.item===content && !content.visible && !weather.visible,"hidden tree not retained without paint")
    check(!body.acceptsInput && !canvas.editMode && !media.presentationActive,"warm tree held input or edit session")
    check(ResourceUsage._persistentConsumers===0,"hidden system retained sampling lease")
    if(route==="Overview")check(content.heldLease==="","hidden overview retained sorting")
    root.shown=true;wait(60)
    check(body.contentItem.item===content && find(content,i=>typeof i.beginEditMode==="function")===canvas,"rapid reopen rebuilt canvas")
    check(content.visible && body.acceptsInput && weather.visible && media.presentationActive,"reopen did not restore presentation")
    if(route==="Overview")check(content.heldLease!=="","reopen failed to acquire sorting")
    root.shown=false;wait(1500)
    check(!body.ready && body.contentItem.item===null && !body.warmHeld,"cache expiry did not release canvas")
   }
   console.info("DASHBOARD_WARM_PASS both routes: no eager allocation, hidden leases/input off, immediate reuse, bounded unload")
  }catch(e){console.error("DASHBOARD_WARM_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
 with private_wayland(folder) as env:
  if env is None:print("SKIP: Dashboard warm test requires private Niri");raise SystemExit(0)
  cfg=folder/"config/illogical-impulse";cfg.mkdir(parents=True,exist_ok=True)
  data=json.loads((ROOT/"defaults/config.json").read_text());data["panelFamily"]="abyss";data["abyss"]["companion"]["enabled"]=False
  (cfg/"config.json").write_text(json.dumps(data));env["QSG_RHI_BACKEND"]="opengl"
  result=run_qs(folder,env,35)
  if result.returncode or "DASHBOARD_WARM_PASS" not in result.stdout or any(x in result.stdout for x in ["DASHBOARD_WARM_FAIL","ReferenceError:","TypeError:","Binding loop","Failed to load configuration"]):print(result.stdout);raise SystemExit(1)
  print("DASHBOARD_WARM_PASS both real routes retain identity, hide paint/input, release sampling/sorting, expire at 1.2 s")
