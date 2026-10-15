#!/usr/bin/env python3
"""Prepare an immutable /tmp-only paired diagnostic; never starts a native lane."""
import hashlib
import os
import json
from pathlib import Path
import shutil
import subprocess
import tarfile

BASE = Path(__file__).resolve().parent / "prepared"
BASE.mkdir(exist_ok=True)
REPO = Path(os.environ["ALIS_DIAGNOSTIC_REPO"]).resolve()
SHA = "77439bddc018cf6e9486c5088f72c76a0efaf060"
ORIGINAL = "docs/evidence/abyss-product/20261014-composed-async-diagnostics/composed-motion/shell.qml"
SOURCE = BASE / "source"
INSTRUMENTED = BASE / "instrumented-source"
if SOURCE.exists() or INSTRUMENTED.exists():
    raise SystemExit("Prepared source exists; preserve it and choose another diagnostic folder")
SOURCE.mkdir()
archive = BASE / "source.tar"
with archive.open("wb") as stream:
    subprocess.run(["git", "-C", str(REPO), "archive", SHA, "modules", "services", "assets", "scripts",
                    "defaults", "translations", "GlobalStates.qml", "qmldir"], stdout=stream, check=True)
with tarfile.open(archive) as stream:
    stream.extractall(SOURCE, filter="data")
archive.unlink()
shutil.copytree(SOURCE, INSTRUMENTED, symlinks=True)

canvas = INSTRUMENTED / "modules/dashboard/DashboardCanvas.qml"
original_canvas = canvas.read_text()
marker = """                    Loader {
                        anchors.fill: parent
                        sourceComponent: root._widgetMap[String(cardWrap.modelData)] ?? null
"""
assert original_canvas.count(marker) == 1
instrumentation = """                    Loader {
                        function diagnostic(event) {
                            console.info("R09_COMPONENT_EVENT", JSON.stringify({event:event,
                                epochMs:Date.now(), widget:String(cardWrap.modelData),
                                active:active, status:status, warm:root.warmContent,
                                visible:cardWrap.visible, width:width, height:height}))
                        }
                        onActiveChanged: diagnostic("widget.active")
                        onStatusChanged: diagnostic("widget.status")
                        onLoaded: diagnostic("widget.loaded")
                        Component.onCompleted: diagnostic("widget.completed")
                        Component.onDestruction: diagnostic("widget.destroyed")
                        anchors.fill: parent
                        sourceComponent: root._widgetMap[String(cardWrap.modelData)] ?? null
"""
canvas.write_text(original_canvas.replace(marker, instrumentation))

qml = subprocess.check_output(["git", "-C", str(REPO), "show", f"{SHA}:{ORIGINAL}"], text=True)
(BASE / "original-shell.qml").write_text(qml)

def replace(before, after, count=1):
    global qml
    assert qml.count(before) == count, (before, qml.count(before), count)
    qml = qml.replace(before, after)

replace(' Component.onCompleted:Quickshell.watchFiles=false', '''
 property bool captureEnabled:Quickshell.env("R09_CAPTURE_MODE")==="grab"
 property var pendingNoGrab:null
 property double lastHeartbeat:0
 property int captureSequence:0
 Component.onCompleted:{Quickshell.watchFiles=false;diagnostic("boot",{pid:Quickshell.processId})}
 function diagnostic(event,detail){console.info("R09_EVENT",JSON.stringify({event,detail,
  epochMs:Date.now(),caseIndex,phase,p:popup?.revealProgress??null}))}
 function action(label,callback){
  const before=Date.now();diagnostic(label+".before",{})
  callback();diagnostic(label+".after",{inclusiveMs:Date.now()-before})
 }
 function heartbeat(){
  const now=Date.now(),dt=lastHeartbeat?now-lastHeartbeat:0;lastHeartbeat=now
  if(current)current.heartbeats.push({ms:now-epoch,dt,phase,p:popup?.revealProgress??null,pending})
  if(dt>40)diagnostic("heartbeat.gap",{dt,pending})
 }
 function completeNoGrab(){
  if(!pendingNoGrab)return
  const capture=pendingNoGrab;pendingNoGrab=null
  capture.entry.captures.push({request:capture.request,phase,ms:Date.now()-epoch,
   p:popup?.revealProgress??null,kind:"frame-ack-no-readback"})
  pending=false
 }
 Connections {
  target:body
  function onReadyChanged(){root.diagnostic("body.ready",{ready:body.ready})}
  function onSourceChanged(){root.diagnostic("body.source",{source:String(body.source)})}
  function onVisualResidentChanged(){root.diagnostic("body.resident",{resident:body.visualResident})}
 }
 Connections {
  target:body.contentItem
  function onStatusChanged(){root.diagnostic("body.loader.status",{status:body.contentItem.status})}
  function onLoaded(){root.diagnostic("body.loader.loaded",{})}
 }
''')
replace('function phaseTo(value){phase=value;phaseStart=Date.now();current?.events.push({phase:value,ms:Date.now()-epoch,p:popup?.revealProgress??null,canvas:canvas?[canvas.width,canvas.height]:null})}',
        'function phaseTo(value){phase=value;phaseStart=Date.now();current?.events.push({phase:value,ms:Date.now()-epoch,p:popup?.revealProgress??null,canvas:canvas?[canvas.width,canvas.height]:null});diagnostic("phase",{value})}')
replace('COMPOSED_MOTION_RESULT', 'R09_PAIRED_RESULT')
replace('{error,checks,completed:results.length,caseIndex,phase,results,current,api:GraphicsInfo.api}',
        '{error,checks,completed:results.length,caseIndex,phase,results,current,api:GraphicsInfo.api,captureEnabled,epoch}')
replace('events:[],swaps:[],captures:[],signals:[]', 'events:[],heartbeats:[],swaps:[],captures:[],signals:[]')
replace('  root.shown=false;root.canvas=null;root.popup=null',
        '  root.diagnostic("case.begin",{case:cases[caseIndex]});root.action("body.hide",()=>root.shown=false);root.canvas=null;root.popup=null')
replace('  openingFrames=0;closingFrames=0;root.shown=true;phaseTo("loading")',
        '  openingFrames=0;closingFrames=0;root.action("body.show",()=>root.shown=true);phaseTo("loading")')
replace('  function onFrameSwapped(){\n', '  function onFrameSwapped(){\n   root.completeNoGrab()\n')
replace('  const request={phase,ms:Date.now()-epoch,p:popup.revealProgress},entry=current,index=caseIndex',
        '''  const request={phase,ms:Date.now()-epoch,p:popup.revealProgress,id:captureSequence++},entry=current,index=caseIndex
  if(!captureEnabled){pendingNoGrab={request,entry,index};return}
  diagnostic("grab.request",{id:request.id})''')
replace('   const record={request,phase,ms:Date.now()-epoch,p}',
        '   const record={request,phase,ms:Date.now()-epoch,p};diagnostic("grab.callback",{id:request.id,latencyMs:Date.now()-epoch-request.ms})')
replace('   if(root.ending)return\n', '   if(root.ending)return\n   root.heartbeat()\n')
replace('root.canvas.beginEditMode()', 'root.action("edit.begin",()=>root.canvas.beginEditMode())', count=3)
replace('root.canvas.cancelEditMode()', 'root.action("edit.cancel",()=>root.canvas.cancelEditMode())', count=3)
replace('root.check(root.current.openingImages>0,"no captured partial opening")',
        'if(root.captureEnabled)root.check(root.current.openingImages>0,"no captured partial opening")')
replace('root.check(root.current.closingImages>0,"no captured partial closing")',
        'if(root.captureEnabled)root.check(root.current.closingImages>0,"no captured partial closing")')
replace('    Config.setNestedValue("dashboard.canvas.widgets",root.canvas.defaultEntries().map(p=>Object.assign({},p,{visible:p.id==="notes",x:.15,y:.15,w:.3,h:.35})))',
        '    root.action("widgets.notes-only",()=>Config.setNestedValue("dashboard.canvas.widgets",root.canvas.defaultEntries().map(p=>Object.assign({},p,{visible:p.id==="notes",x:.15,y:.15,w:.3,h:.35}))))')
replace('    shared.focusEditor();note.text=', '    shared.focusEditor();root.diagnostic("notes.write.before",{});note.text=')
replace('    root.phaseTo("notes");return', '    root.diagnostic("notes.write.after",{});root.phaseTo("notes");return')
(BASE / "shell.qml").write_text(qml)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

manifest = {
    "source_sha": SHA, "source_repository": "https://github.com/llocphann/Alis", "source_ref": "dev",
    "original_fixture_path": ORIGINAL,
    "original_fixture_sha256": digest(BASE / "original-shell.qml"),
    "instrumented_fixture_sha256": digest(BASE / "shell.qml"),
    "temporary_source_changes": [{"path":"modules/dashboard/DashboardCanvas.qml",
        "before_sha256":digest(SOURCE / "modules/dashboard/DashboardCanvas.qml"),
        "after_sha256":digest(canvas),"scope":"Loader lifecycle logging only"}],
    "invariants": ["Original16 case order and sizes", "Four physical edges", "Original source easing/durations/geometry",
        "Original partial/reversal/close/input checks", "Original8ms asynchronous step loop", "Original note text",
        "No-grab lane retains pending flow with frame-swapped acknowledgment", "Canonical private XDG config/alis"],
    "not_started": ["native smoke", "paired measured reproduction", "owner smoothness acceptance"],
    "run_gate":"run_pair.py requires --host-quiet-confirmed; no native process starts during preparation",
    "classification":"A delayed grab callback alone is not GUI/motion stutter. Only explicitly intermediate-progress swap intervals are classified as active motion; endpoint-only gaps stay separate.",
}
(BASE / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(json.dumps({"prepared":str(BASE),"sha":SHA,"native_runs":0}))
