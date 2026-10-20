#!/usr/bin/env python3
"""DESK-CTX-R01: actual wl_pointer/keyboard and configured popup geometry.

Private nested Niri, including four exposed corner gaps, source-mask priority,
alternating desktop/item menus, rapid relocation, actions, outside and Escape.
This does not establish physical-output or Owner acceptance.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time

from native_test_session import private_wayland
from native_wayland_input import native_input

ROOT = Path(os.environ.get("ALIS_CONTEXT_MENU_SOURCE", Path(__file__).resolve().parents[1]))
QML = r'''
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
ShellRoot {
 id:root
 property int requestId:0
 property int actions:0
 property int moduleClicks:0
 property string source:""
 Component.onCompleted:Quickshell.watchFiles=false
 function openAt(item,x,y,managed){
  const point=item.mapToItem(null,x,y)
  keys.forceActiveFocus()
  root.requestId++;root.source=managed?"item":"desktop"
  if(managed){bare.close();owned.requestOpenAt(point.x,point.y)}
  else{owned.close();bare.requestOpenAt(point.x,point.y)}
 }
 PanelWindow {
  id:desktop;anchors{top:true;bottom:true;left:true;right:true}
  color:"#152128";exclusiveZone:0
  WlrLayershell.layer:WlrLayer.Bottom
  WlrLayershell.namespace:"alis-context-regression"
  WlrLayershell.keyboardFocus:WlrKeyboardFocus.OnDemand
  Item{id:anchor;width:1;height:1}
  FocusScope{id:keys;Keys.onEscapePressed:event=>{
   bare.close();owned.close();event.accepted=true}}
  MouseArea{id:hit;anchors.fill:parent;acceptedButtons:Qt.RightButton|Qt.LeftButton
   onClicked:mouse=>{if(mouse.button===Qt.RightButton)root.openAt(hit,mouse.x,mouse.y,false)
    else{bare.close();owned.close()}}}
  Rectangle{
   id:managed;x:desktop.width/2;y:desktop.height/2;width:100;height:70
   scale:1.15;color:"#29414b"
   MouseArea{anchors.fill:parent;acceptedButtons:Qt.RightButton
    onClicked:mouse=>root.openAt(managed,mouse.x,mouse.y,true)}
  }
  ContextMenu{
   id:bare;anchorItem:anchor;cursorAnchorWindow:desktop
   closeOnFocusLost:false;closeOnHoverLost:false;cursorSlide:true;scaleContent:false
   popupAbove:anchor.y>desktop.height-170
   popupAdjustment:PopupAdjustment.FlipX|PopupAdjustment.FlipY|PopupAdjustment.SlideX|PopupAdjustment.SlideY
   model:[{text:"Fixture action",action:()=>root.actions++},{text:"Second fixture"},{text:"Third fixture"}]
  }
  ContextMenu{
   id:owned;anchorItem:anchor;cursorAnchorWindow:desktop
   closeOnFocusLost:false;closeOnHoverLost:false;cursorSlide:true;scaleContent:false
   popupAbove:anchor.y>desktop.height-170
   popupAdjustment:PopupAdjustment.FlipX|PopupAdjustment.FlipY|PopupAdjustment.SlideX|PopupAdjustment.SlideY
   model:[{text:"Managed fixture",action:()=>root.actions++},{text:"Second fixture"}]
  }
 }
 // A separate higher layer owns only the module's pixels, leaving all four
 // corners exposed. A context menu must not capture clicks from that module.
 PanelWindow{
  id:edge;anchors{top:true;bottom:true;left:true;right:true}
  color:"transparent";exclusiveZone:0;WlrLayershell.layer:WlrLayer.Top
  WlrLayershell.namespace:"alis-context-source-mask"
  mask:Region{x:edge.width*.4;y:0;width:80;height:20}
  Rectangle{x:edge.width*.4;y:0;width:80;height:20;color:"#35717e"
   MouseArea{anchors.fill:parent;acceptedButtons:Qt.RightButton|Qt.LeftButton
    onClicked:root.moduleClicks++}}
 }
 IpcHandler{
  target:"contextRegression"
  function snapshot():string{
   const loader=bare.active?bare:owned.active?owned:null
   const popup=loader?.item
   const native=popup?._backingWindow
   return JSON.stringify({id:root.requestId,source:root.source,actions:root.actions,
    moduleClicks:root.moduleClicks,count:GlobalStates.activeContextMenuCount,
    active:!!loader,queued:loader?.relocationQueued??false,
    output:[desktop.width,desktop.height],scale:desktop.devicePixelRatio,
    anchor:popup?[popup.anchor.rect.x,popup.anchor.rect.y]:null,
    configured:native?[native.x,native.y,popup.width,popup.height]:null})
  }
  function quit():void{Qt.quit()}
 }
}
'''


def run(scale):
    with tempfile.TemporaryDirectory(prefix="alis-context-native-") as temporary:
        folder = Path(temporary)
        for name in ("modules", "services", "GlobalStates.qml", "qmldir", "assets",
                     "scripts", "defaults", "translations"):
            (folder/name).symlink_to(ROOT/name)
        (folder/"shell.qml").write_text(QML)
        with private_wayland(folder) as env:
            if not env:
                print("SKIP: context regression requires private Niri")
                return False
            outputs = json.loads(subprocess.check_output(
                ["niri", "msg", "--json", "outputs"], env=env, text=True, timeout=4))
            output = next(iter(outputs.values()))["name"]
            subprocess.run(["niri", "msg", "output", output, "scale", str(scale)],
                           env=env, check=True, capture_output=True, timeout=4)
            config = folder/"config/illogical-impulse"
            config.mkdir(parents=True, exist_ok=True)
            raw = json.loads((ROOT/"defaults/config.json").read_text())
            raw["panelFamily"] = "abyss"
            raw["performance"]["reduceAnimations"] = False
            (config/"config.json").write_text(json.dumps(raw))
            rows = []
            log = folder/"native.log"
            with log.open("w") as stream:
                process = subprocess.Popen(["dbus-run-session", "--", "qs", "-p",
                    str(folder), "--no-color"], env=dict(env, WAYLAND_DEBUG="client"),
                    stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)

            def snapshot():
                result = subprocess.run(["qs", "-p", str(folder), "ipc", "call",
                    "contextRegression", "snapshot"], env=env, capture_output=True,
                    text=True, timeout=3)
                if result.returncode:
                    raise RuntimeError("private context IPC unavailable")
                return json.loads(result.stdout)

            try:
                deadline = time.monotonic()+12
                while time.monotonic()<deadline:
                    try:
                        state = snapshot()
                        if state["output"][0]>500:
                            break
                    except (RuntimeError, ValueError):
                        pass
                    time.sleep(.1)
                else:
                    raise AssertionError("private desktop did not configure")
                width, height = state["output"]
                with native_input(folder, env) as pointer:
                    if pointer is None:
                        print("SKIP: native input protocols/compiler unavailable")
                        return False

                    def click(point, button=273):
                        pointer.move(*point, width, height)
                        time.sleep(.02)
                        pointer.click(button)

                    def settled(point):
                        time.sleep(.36)
                        state = snapshot()
                        rows.append(dict(state, expected=point))
                        assert state["active"] and not state["queued"], state
                        assert state["count"]==1, state
                        assert all(abs(a-b)<=1 for a, b in zip(state["anchor"], point)), state
                        x, y, w, h = state["configured"]
                        assert x>=-1 and y>=-1 and x+w<=width+2 and y+h<=height+2, state
                        # Flip is allowed, origin/stale coordinates are not.
                        assert min(abs(x-point[0]),abs(x+w-point[0]-1))<=2, state
                        assert min(abs(y-point[1]-1),abs(y+h-point[1]))<=2, state
                        return state

                    item = [width/2+40, height/2+30]
                    points = [[90,90],item,[200,350],[width-4,4],[4,4],
                              [4,height-4],[width-4,height-4],item]
                    for index in range(24):
                        point = points[index%len(points)]
                        click(point)
                        state = settled(point)
                        assert state["id"]==index+1, state
                        assert state["source"]==("item" if point is item else "desktop"), state
                    # Last request wins while the old slide-out is in flight.
                    for point in [[80,80],[width*.7,height*.3],[width*.2,height*.7]]:
                        click(point)
                    settled(point)
                    pointer.escape()
                    time.sleep(.24)
                    assert not snapshot()["active"], "native Escape did not close"
                    click([90,90]);settled([90,90])
                    click([width*.75,height*.75],272)
                    time.sleep(.24)
                    assert not snapshot()["active"], "outside click did not close"
                    click([90,90]);state=settled([90,90])
                    x,y,w,h=state["configured"]
                    click([x+w/2,y+26],272)
                    time.sleep(.24)
                    assert snapshot()["actions"]==1 and not snapshot()["active"], "menu action failed"
                    click([90,90]);settled([90,90])
                    click([width*.4+40,10],272)
                    assert snapshot()["moduleClicks"]==1, "menu stole source module input"
                    pointer.escape()
                subprocess.run(["qs", "-p", str(folder), "ipc", "call",
                    "contextRegression", "quit"], env=env, capture_output=True, timeout=3, check=True)
                code = process.wait(timeout=4)
                assert code==0, code
                text = log.read_text(errors="replace")
                assert not any(word in text for word in ("TypeError:","ReferenceError:",
                    "Binding loop", "Failed to load configuration")), text[-2000:]
                if os.environ.get("ALIS_CONTEXT_MENU_EVIDENCE"):
                    dest=Path(os.environ["ALIS_CONTEXT_MENU_EVIDENCE"])
                    dest.mkdir(parents=True,exist_ok=True)
                    (dest/f"native-{scale}.log").write_text(text)
                    (dest/f"result-{scale}.json").write_text(json.dumps({
                        "actual_exit":code,"scale":scale,"rows":rows,
                        "log_sha256":hashlib.sha256(log.read_bytes()).hexdigest(),
                        "scope":"private nested Niri; actual wl_pointer and Escape; not Owner acceptance"
                    },indent=2)+"\n")
                print(f"PASS: native context menu, scale {scale}, 24 consecutive clicks, rapid relocate, Escape/action/outside/source priority")
                return True
            finally:
                if process.poll() is None:
                    os.killpg(process.pid,signal.SIGTERM)
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid,signal.SIGKILL)
                        process.wait(timeout=3)
                if os.environ.get("ALIS_CONTEXT_MENU_EVIDENCE"):
                    dest=Path(os.environ["ALIS_CONTEXT_MENU_EVIDENCE"])
                    dest.mkdir(parents=True,exist_ok=True)
                    (dest/f"native-{scale}.log").write_bytes(log.read_bytes())
                    (dest/f"exit-{scale}.json").write_text(json.dumps({
                        "actual_native_exit":process.returncode,"rows":rows,
                        "source":str(ROOT),"scope":"private compositor, no owner desktop changes"
                    },indent=2)+"\n")


if __name__=="__main__":
    if shutil.which("qs") is None:
        print("SKIP: Quickshell unavailable")
    elif run(1):
        run(1.5)
