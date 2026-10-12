#!/usr/bin/env python3
"""Check real Sidebar Left inner material using a private disposable Niri session."""
import json,os,shutil,tempfile
from pathlib import Path
from native_test_session import private_wayland,run_qs

ROOT=Path(__file__).resolve().parents[1]
if not shutil.which("qs"):
    print("SKIP: Sidebar Left theme native check needs Quickshell")
    raise SystemExit(0)

QML=r"""
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.abyss.looks
import qs.modules.sidebarLeft
ShellRoot {
 id:root
 property int checks:0
 property int frames:0
 Component.onCompleted:Quickshell.watchFiles=false
 FloatingWindow {
  visible:true;implicitWidth:520;implicitHeight:700;color:"#161c24"
  SidebarLeftContent {
   id:sidebar;x:20;y:20;width:440;height:640
   panelVisible:true;externalConnectedSurface:true
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(v,message){root.checks++;if(!v)throw Error(message)}
  function sameColor(a,b){return Math.abs(a.r-b.r)<.005
    && Math.abs(a.g-b.g)<.005 && Math.abs(a.b-b.b)<.005
    && Math.abs(a.a-b.a)<.005}
  function capture(name) {
   const before=root.frames
   check(sidebar.grabToImage(img=>{
      img.saveToFile(Quickshell.env("SIDE_THEME_EVIDENCE")+"/"+name+".png")
      root.frames++
   }),"native frame was refused")
   tryVerify(()=>root.frames>before,3000)
  }
  function testRun(){try{
   tryCompare(Config,"ready",true,6000)
   Config.setNestedValue("panelFamily","abyss")
   tryVerify(()=>sidebar.abyssInnerMaterial,3000)
   const inner=findChild(sidebar,"sidebarLeftInnerSurface")
   check(!!inner,"missing shared inner plate")
   const expected=Qt.alpha(ColorUtils.mix(AbyssStyle.contentLayer,AbyssStyle.accent,.88),
       AbyssStyle.contentOpacity)
   tryVerify(()=>sameColor(inner.color,expected),3000)
   check(sameColor(sidebar.innerContentSurfaceColor,expected),
     "Abyss plate diverges from Weather Details theme material")
   check(!sameColor(inner.color,Appearance.colors.colLayer1)
     || sameColor(expected,Appearance.colors.colLayer1),
     "inner plate stayed a fixed neutral slab")
   check(inner.width>0 && inner.height>0,"inner panel lost usable bounds")
   check(sameColor(sidebar.connectedSurfaceColor,Appearance.colors.colLayer0),
     "outer connected material must retain original non-card layer")
   check(inner.radius===Appearance.rounding.normal,"inner card shape changed")
   capture("abyss")
   Config.setNestedValue("panelFamily","waffle")
   tryVerify(()=>!sidebar.abyssInnerMaterial,3000)
   check(sameColor(inner.color,Appearance.colors.colLayer1),
     "non-Abyss sidebar no longer uses its old material")
   capture("waffle")
   Config.setNestedValue("panelFamily","abyss")
   tryVerify(()=>sameColor(inner.color,Qt.alpha(
       ColorUtils.mix(AbyssStyle.contentLayer,AbyssStyle.accent,.88),
       AbyssStyle.contentOpacity)),3000)
   check(ColorUtils.ensureReadable(AbyssStyle.textColor,inner.color,4.5).a>0,
     "adaptive accessible text color unavailable")
   capture("restored")
   // Tint may alter RGB, never add invisible opacity back into 0% content.
   for(const alpha of [0,0.25,0.78,1]) {
    Config.setNestedValue("abyss.content.opacity",alpha)
    tryVerify(()=>Math.abs(inner.color.a-alpha)<.006,3000)
    check(Math.abs(inner.color.a-alpha)<.006,
        "sidebar background alpha does not follow saved content opacity "+alpha)
   }
   console.info("SIDEBAR_LEFT_THEME_NATIVE_PASS",root.checks,root.frames)
  }catch(error){
   console.error("SIDEBAR_LEFT_THEME_NATIVE_FAIL",error.message,error.stack)
  }Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.testRun()}
}
"""
with tempfile.TemporaryDirectory(prefix="alis-sidebar-theme-") as directory:
    folder=Path(directory)
    for entry in ("modules","services","qmldir","GlobalStates.qml","assets",
                  "scripts","defaults","translations"):
        (folder/entry).symlink_to(ROOT/entry)
    (folder/"shell.qml").write_text(QML)
    with private_wayland(folder) as env:
        if env is None:
            print("SKIP: Sidebar Left theme needs a private Niri session")
            raise SystemExit(0)
        conf=folder/"config/illogical-impulse";conf.mkdir(parents=True,exist_ok=True)
        data=json.loads((ROOT/"defaults/config.json").read_text())
        data["panelFamily"]="abyss"
        data["abyss"]["companion"]["enabled"]=False
        (conf/"config.json").write_text(json.dumps(data))
        folder_out=Path(os.environ.get("ALIS_SIDEBAR_THEME_EVIDENCE",folder/"captures"))
        folder_out.mkdir(parents=True,exist_ok=True)
        run=run_qs(folder,dict(env,SIDE_THEME_EVIDENCE=str(folder_out)),timeout=40)
        (folder_out/"native.log").write_text(run.stdout)
        if run.returncode or "SIDEBAR_LEFT_THEME_NATIVE_PASS" not in run.stdout or any(x in run.stdout for x in
                ("SIDEBAR_LEFT_THEME_NATIVE_FAIL","ReferenceError:","TypeError:",
                 "Binding loop","Unable to assign","Failed to load configuration")):
            print(run.stdout)
            raise SystemExit(1)
        for line in run.stdout.splitlines():
            if "SIDEBAR_LEFT_THEME_NATIVE_PASS" in line:
                print(line)
