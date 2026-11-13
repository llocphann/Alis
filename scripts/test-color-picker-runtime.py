#!/usr/bin/env python3
"""Native worker isolation: fresh capture, input, clipboard, crash and reentry."""
import json
import os
from pathlib import Path
import resource
import subprocess
import tempfile
from native_test_session import private_wayland, run_qs

resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

ROOT = Path(os.environ.get("ALIS_COLOR_PICKER_SOURCE", Path(__file__).resolve().parents[1])).resolve()
WORKER_TEST = r'''
    Process {
        id: crash
        command: ["kill", "-SEGV", String(Quickshell.processId)]
    }
    TestCase {
        id: test; when: false; optional: true
        function check(value, message) { if (!value) throw Error(message) }
        function sample(view, x, y, expected) {
            mouseMove(view.contentItem,x,y,10)
            tryCompare(view,"sampledColor",expected,2000)
            check(view.sampledColor===expected,"native pixel mismatch "+view.sampledColor+" / "+expected)
        }
        function run() { try {
            tryVerify(()=>root.overlays.length>0&&root.overlays.every(view=>view.ready),7000)
            check(root.overlays.length===Quickshell.screens.length,"missing output overlay")
            let view=root.overlays[0]
            check(view.ready,"capture not ready")
            const left=root.ticket%2===1?"#D24C0A":"#38A85B"
            const right=root.ticket%2===1?"#1A7FC3":"#AB39C4"
            sample(view,view.width*.25,view.height*.5,left)
            sample(view,view.width*.75,view.height*.5,right)
            sample(view,0,0,left)
            sample(view,view.width-1,view.height-1,right)
            // Moving also paints the actual magnifier Canvas from captured pixels.
            function descendants(item) { let result=[]; for(const child of item.children??[]) result=result.concat([child],descendants(child));return result }
            const previews=descendants(view.contentItem).filter(item=>item.width===166&&item.height===196)
            check(previews.length===1,"magnifier preview missing")
            sample(view,view.width*.25,view.height*.5,left)
            const canvas=previews[0].children.find(item=>item.width===143&&item.height===143)
            check(!!canvas,"magnifier canvas missing")
            canvas.requestPaint()
            function magnifiedColor(x=20,y=20) {
                const pixel=canvas.getContext("2d").getImageData(x,y,1,1).data
                return pixel[3]===255 ? "#"+[pixel[0],pixel[1],pixel[2]].map(value=>Number(value).toString(16).padStart(2,"0")).join("").toUpperCase() : "transparent"
            }
            console.info("COLOR_PICKER_MAGNIFIER_WAIT",root.ticket,previews[0].visible,canvas.available,magnifiedColor())
            tryVerify(()=>magnifiedColor()===left,2000)
            check(magnifiedColor()===left,"magnifier did not paint original pixels: "+magnifiedColor())
            for (const point of [[1,1],[20,20],[25,25],[40,40],[60,60],[90,90],[120,120],[141,141]])
                check(magnifiedColor(point[0],point[1])===left,"DPR magnifier gap at "+point)
            console.info("COLOR_PICKER_WORKER_NATIVE_READY",root.ticket,Quickshell.processId,view.width,view.height)
            if (root.ticket===5) { crash.running=true; return }
            if (root.ticket===28 || root.ticket===30) return
            if (root.ticket===2) mouseClick(view.contentItem,20,20,Qt.RightButton)
            else if (root.ticket===3) {
                tryVerify(()=>root.overlays.some(item=>item.contentItem.Window.active),2000)
                view=root.overlays.find(item=>item.contentItem.Window.active)
                check(!!view?.contentItem.Window.activeFocusItem,"picker keyboard focus missing")
                keyClick(Qt.Key_Escape,Qt.NoModifier,0)
            } else if (root.ticket===6) {
                tryVerify(()=>root.overlays.some(item=>item.contentItem.Window.active),2000)
                view=root.overlays.find(item=>item.contentItem.Window.active)
                const halfEdgeX=Math.max(0,(Math.floor(view.width*.5)-1))
                sample(view,halfEdgeX,view.height*.5,left)
                const startPx=view.currentPixelX
                keyClick(Qt.Key_Right,Qt.NoModifier,0)
                tryVerify(()=>view.currentPixelX===startPx+1,1000)
                // If DPR > 1, step remaining device pixels to cross exact midpoint, then verify 1px back/forth
                while (view.sampledColor===left && view.currentPixelX < startPx + 6) {
                    const prevPx=view.currentPixelX
                    keyClick(Qt.Key_Right,Qt.NoModifier,0)
                    tryVerify(()=>view.currentPixelX===prevPx+1,1000)
                }
                check(view.sampledColor===right,"arrow key Right did not cross pixel boundary to "+right+": "+view.sampledColor)
                const boundaryPx=view.currentPixelX
                keyClick(Qt.Key_Left,Qt.NoModifier,0)
                tryCompare(view,"currentPixelX",boundaryPx-1,1000)
                tryCompare(view,"sampledColor",left,1000)
                keyClick(Qt.Key_Right,Qt.NoModifier,0)
                tryCompare(view,"currentPixelX",boundaryPx,1000)
                tryCompare(view,"sampledColor",right,1000)
                keyClick(Qt.Key_Return,Qt.NoModifier,0)
            } else mouseClick(view.contentItem,view.width*.25,view.height*.5,Qt.LeftButton)
        } catch(error) { root.complete("failed","","TEST: "+error.message) } }
    }
    Timer { interval:200;running:true;onTriggered:test.run() }
'''
PARENT = r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
ShellRoot {
 id: root
 property int checks: 0
 property int picks: 0
 property string cliText: ""
 property int cliExit: -1
 property var workerPids: []
 Component.onCompleted: Quickshell.watchFiles=false
 Connections {
  target: ColorPickerService
  function onPicked(value) {
   root.picks++
   ColorPickerService.finish(ColorPickerService.requestId,"#FFFFFF")
  }
  function onWorkerProcessIdChanged() {
   if(ColorPickerService.workerProcessId) root.workerPids.push(Number(ColorPickerService.workerProcessId))
  }
 }
 Process {
  id: cli
  command:[Quickshell.env("COLOR_PICKER_CLI"),"colorpicker","--config",Quickshell.shellDir]
  stdout:StdioCollector {onStreamFinished:root.cliText=text.trim()}
  stderr:StdioCollector {onStreamFinished:if(text.trim())console.warn("CLI",text)}
  onExited:(code,status)=>root.cliExit=code
 }
 Variants {
  model:Quickshell.screens
  delegate:PanelWindow {
   required property var modelData
   screen:modelData
   anchors {top:true;bottom:true;left:true;right:true}
   exclusionMode:ExclusionMode.Ignore
   WlrLayershell.layer:WlrLayer.Background
   color:"#112233"
   Rectangle {width:parent.width/2;height:parent.height;color:ColorPickerService.requestId%2===1?"#D24C0A":"#38A85B"}
   Rectangle {x:parent.width/2;width:parent.width/2;height:parent.height;color:ColorPickerService.requestId%2===1?"#1A7FC3":"#AB39C4"}
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(value,message){root.checks++;if(!value)throw Error(message)}
  function done(ticket,expected){
   tryVerify(()=>ColorPickerService.status(ticket)!=="pending",12000)
   check(ColorPickerService.status(ticket)===expected,"ticket "+ticket+": "+ColorPickerService.status(ticket)+" "+ColorPickerService.lastError)
   check(!ColorPickerService.active,"request remains active")
   check(ColorPickerService.overlays.length===0,"native window leaked into host")
  }
  function begin(){
   const ticket=ColorPickerService.start()
   check(ColorPickerService.status(ticket)==="pending","new request not pending")
   check(ColorPickerService.start()===ticket,"repeated start was not coalesced")
   return ticket
  }
  function run(){try{
   wait(500)
   let ticket=begin();done(ticket,"#D24C0A")
   check(Quickshell.clipboardText==="#D24C0A","host clipboard not retained")
   check(root.picks===1,"completion reentered or emitted twice")
   wait(450)
   if(Quickshell.env("ALIS_COLOR_PICKER_PREVIEW_ONLY")==="1"){
    console.info("COLOR_PICKER_PREVIEW_PASS",root.checks,"screens",Quickshell.screens.length)
    Qt.quit();return
   }
   const completed=ticket
   ticket=begin();done(ticket,"cancelled")
   check(Quickshell.clipboardText==="#D24C0A","right cancel changed clipboard")
   check(ColorPickerService.status(completed)==="#D24C0A","prior ticket lost")
   ticket=begin();done(ticket,"cancelled")
   check(Quickshell.clipboardText==="#D24C0A","Escape changed clipboard")
   console.info("COLOR_PICKER_ESCAPE_CANCEL_PASS")
   ticket=begin();ColorPickerService.cancel(Number(ticket));wait(500)
   done(ticket,"cancelled")
   ColorPickerService.finish(Number(ticket),"#FFFFFF")
   ColorPickerService.fail(Number(ticket),"stale error")
   done(ticket,"cancelled")
   ticket=begin();done(ticket,"failed")
   check(Quickshell.clipboardText==="#D24C0A","child crash changed clipboard")
   console.info("COLOR_PICKER_CRASH_CONTAINMENT_PASS",Quickshell.processId)
   ticket=begin();done(ticket,"#AB39C4")
   check(Quickshell.clipboardText==="#AB39C4","keyboard selection not copied")
   // Captures alternate background colors every request, exposing stale frames.
   for(let n=0;n<21;n++){
    ticket=begin();const expected=Number(ticket)%2===1?"#D24C0A":"#38A85B"
    done(ticket,expected);check(Quickshell.clipboardText===expected,"stress clipboard mismatch")
   }
   check(new Set(root.workerPids).size===root.workerPids.length,"worker process reused")
   check(root.workerPids.length>=25,"missing fresh child processes")
   console.info("COLOR_PICKER_FRESH_PROCESS_STRESS_PASS",root.workerPids.length)
   ticket=begin()
   tryVerify(()=>ColorPickerService.active&&!!ColorPickerService.workerProcessId,3000)
   wait(1000) // child 28 captures natively and waits, then the host cancels it
   ColorPickerService.cancel(Number(ticket))
   const cancelled=ticket
   ticket=begin()
   ColorPickerService.finish(Number(cancelled),"#FFFFFF")
   done(ticket,"#D24C0A")
   check(ColorPickerService.status(cancelled)==="cancelled","old worker changed new request")
   ticket=begin();done(ticket,"failed")
   check(ColorPickerService.lastError==="Color picker capture timed out","silent child was not timed out")
   console.info("COLOR_PICKER_CANCEL_REENTRY_TIMEOUT_PASS")
   cli.running=true
   tryVerify(()=>root.cliExit!==-1,12000)
   check(root.cliExit===0,"CLI failed")
   check(root.cliText==="#D24C0A","CLI lost hex stdout: "+root.cliText)
   check(Quickshell.clipboardText===root.cliText,"CLI clipboard mismatch")
   ticket=begin();done(ticket,"failed")
   check(ColorPickerService.lastError==="Color picker did not exit","terminal reply hang was not bounded")
   check(Quickshell.clipboardText==="#D24C0A","hung terminal reply changed clipboard")
   ticket=begin();done(ticket,"#D24C0A")
   wait(450)
   console.info("COLOR_PICKER_TERMINAL_HANG_RECOVERY_PASS")
   console.info("COLOR_PICKER_NATIVE_PASS",root.checks,"screens",Quickshell.screens.length,"parent",Quickshell.processId)
  }catch(error){console.error("COLOR_PICKER_NATIVE_FAIL",error.message,error.stack)}
  Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''

with tempfile.TemporaryDirectory(prefix="alis-color-picker-worker-") as directory:
    folder=Path(directory)
    for entry in ("modules","GlobalStates.qml","qmldir","assets","scripts","defaults","translations"):
        (folder/entry).symlink_to(ROOT/entry)
    (folder/"services").mkdir()
    for entry in (ROOT/"services").iterdir():
        if entry.name!="ColorPickerService.qml": (folder/"services"/entry.name).symlink_to(entry)
    service=(ROOT/"services/ColorPickerService.qml").read_text()
    # Instrument only the disposable fixture to retain child native assertions.
    service=service.replace('function readReply(line: string): void {', 'function readReply(line: string): void {\n        console.info("COLOR_PICKER_CHILD",line)')
    (folder/"services/ColorPickerService.qml").write_text(service)
    worker=(ROOT/"color-picker-worker.qml").read_text()
    worker=worker.replace('quitTimer.restart()', 'if (ticket !== 32) quitTimer.restart() // test only: native child terminal-exit hang')
    worker=worker.replace('function notifyReady(): void {', 'function notifyReady(): void {\n        if (ticket === 30) return // test only: actual native child with a silent protocol')
    worker=worker.replace("import QtQuick", "import QtQuick\nimport QtQuick.Window\nimport QtTest\nimport Quickshell.Io",1)
    (folder/"color-picker-worker.qml").write_text(worker.rsplit("}",1)[0]+WORKER_TEST+"}\n")
    (folder/"shell.qml").write_text('''import QtQuick
import Quickshell
import qs.services
ShellRoot {
 property var picker:ColorPickerService
 Component.onCompleted:Quickshell.watchFiles=false
 Timer {interval:100;running:true;onTriggered:{
  console.info("COLOR_PICKER_OFFSCREEN_IMPORT_PASS",ColorPickerService.active,ColorPickerService.overlays.length)
  Qt.quit()
 }}
}''')
    env=dict(os.environ,QT_QPA_PLATFORM="offscreen",ALIS_TEST_WAYLAND_SOCKET="/__alis_offscreen_import__")
    env.pop("WAYLAND_DISPLAY",None)
    result=run_qs(folder,env,timeout=12)
    if result.returncode or "COLOR_PICKER_OFFSCREEN_IMPORT_PASS false 0" not in result.stdout:
        print(result.stdout);raise SystemExit("FAIL: unrelated offscreen service imports")
    print("COLOR_PICKER_OFFSCREEN_IMPORT_PASS")
    (folder/"shell.qml").write_text(PARENT)
    with private_wayland(folder) as env:
        if env is None:raise SystemExit("SKIP: private Wayland unavailable")
        if scale:=os.environ.get("ALIS_COLOR_PICKER_TEST_SCALE"):
            outputs=json.loads(subprocess.check_output(["niri","msg","--json","outputs"],env=env,text=True))
            for name in outputs:
                subprocess.run(["niri","msg","output",name,"scale",scale],env=env,check=True,capture_output=True,timeout=5)
        env["COLOR_PICKER_CLI"]=os.environ.get("ALIS_COLOR_PICKER_CLI",str(ROOT/"scripts/alis"))
        env["ALIS_RUNTIME_DIR"]=str(folder)
        env["QS_DISABLE_CRASH_HANDLER"]="1"
        result=run_qs(folder,env,timeout=150)
        output=Path(os.environ.get("ALIS_COLOR_PICKER_EVIDENCE","/tmp/alis-color-picker-runtime.log"))
        output.parent.mkdir(parents=True,exist_ok=True);output.write_text(result.stdout)
        print(result.stdout)
        marker="COLOR_PICKER_PREVIEW_PASS" if os.environ.get("ALIS_COLOR_PICKER_PREVIEW_ONLY")=="1" else "COLOR_PICKER_NATIVE_PASS"
        if result.returncode or marker not in result.stdout or "COLOR_PICKER_NATIVE_FAIL" in result.stdout:
            raise SystemExit(1)
        hist_rows=subprocess.check_output(["cliphist","list"],env=env,text=True).splitlines()
        pasted=subprocess.check_output(["wl-paste","--no-newline"],env=env,text=True,timeout=2)
    assert hist_rows and hist_rows[0].endswith("\t#D24C0A"), f"cliphist DB missing latest picked hex: {hist_rows[:5]}"
    if os.environ.get("ALIS_COLOR_PICKER_PREVIEW_ONLY") != "1":
        assert any(r.endswith("\t#AB39C4") for r in hist_rows), f"cliphist DB missing keyboard picked hex: {hist_rows[:5]}"
    assert pasted=="#D24C0A", f"Wayland clipboard missing picked hex: {pasted!r}"
