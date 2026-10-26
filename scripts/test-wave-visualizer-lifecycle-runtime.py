#!/usr/bin/env python3
"""Real animated delegates survive resize/unload without dangling bindings."""
from pathlib import Path
import tempfile
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-wave-lifecycle-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
Window {
 id:root;visible:true;width:720;height:140;color:"#111820"
 Component.onCompleted:Quickshell.watchFiles=false
 Loader {id:loader;width:300;height:100;active:false
  sourceComponent:WaveVisualizer {points:Array.from({length:64},(_,i)=>(i%7+1)*110)}}
 TestCase {
  id:test;when:false;optional:true
  function check(v,m){if(!v)throw new Error(m)}
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000)
   loader.active=true;tryCompare(loader,"status",Loader.Ready,2000);wait(120)
   const wave=loader.item,row=wave.children[0]
   const bars=row.children.filter(child=>child.level!==undefined)
   check(bars.length===wave.activeBars,"wrong bar count")
   for(const bar of bars){
    check(Math.abs(bar.width-wave.actualBarWidth)<1e-8,"bar width changed")
    check(Math.abs(bar.height-Math.max(wave.minBarHeight,bar.level*wave.height*.96))<1e-6,"bar height changed")
    check(Math.abs(bar.y+bar.height-wave.height)<1e-6,"bar lost bottom alignment")
   }
   // During unloading the visual parent can disappear before an animated
   // delegate. Exercise that interval directly before deleting the owner.
   const retiring=bars[2]
   retiring.parent=null;retiring.level=1;wait(25)
   retiring.parent=row;wait(90)
   for(let i=0;i<60;i++){
    loader.active=true;tryCompare(loader,"status",Loader.Ready,2000)
    loader.width=320+(i%5)*80
    loader.item.points=Array.from({length:64},(_,k)=>((k+i)%9)*120)
    wait(12)
    loader.width=60+(i%3)*12
    wait(12)
    loader.active=false;wait(12)
    check(loader.item===null,"hidden wave retained its delegates")
   }
   console.info("WAVE_LIFECYCLE_PASS geometry and 60 animated resize/unload cycles")
  }catch(e){console.error("WAVE_LIFECYCLE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
    with private_wayland(folder) as env:
        if env is None:
            print("SKIP: wave lifecycle requires private Niri")
            raise SystemExit(0)
        result = run_qs(folder, env, timeout=25)
        if result.returncode or "WAVE_LIFECYCLE_PASS" not in result.stdout or any(word in result.stdout for word in [
                "WAVE_LIFECYCLE_FAIL", "TypeError:", "ReferenceError:", "Unable to assign", "Binding loop", "Failed to load configuration"]):
            print(result.stdout)
            raise SystemExit(1)
        print("WAVE_LIFECYCLE_PASS geometry and 60 animated resize/unload cycles; no dangling bindings")
