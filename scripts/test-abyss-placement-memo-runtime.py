#!/usr/bin/env python3
"""Exercise independent host-owned caches through real BodyHost destruction."""
import json
import os
import tempfile
from pathlib import Path
from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-placement-memo-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    config = folder / "config/alis"
    config.mkdir(parents=True)
    data = json.loads((ROOT / "defaults/config.json").read_text())
    data["abyss"]["companion"]["enabled"] = False
    (config / "config.json").write_text(json.dumps(data))
    (folder / "shell.qml").write_text(r'''
import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.abyss
import "modules/abyss/looks/AbyssPlacementMemo.js" as Memo
ShellRoot {
 id:root;property int checks:0;property int step:0;property int derivedDestroyed:0
 property var hosts:[];property int cycles:20
 Component.onCompleted:Quickshell.watchFiles=false
 function check(value,label){checks++;if(!value)throw new Error(label)}
 AbyssSurfaceController {id:liquid}
 Item {id:parentItem;width:1000;height:740}
 Component {
  id:factory
  AbyssBodyHost {controller:liquid;edge:"bottom";Component.onDestruction:root.derivedDestroyed++}
 }
 Timer {
  interval:15;running:true;repeat:true
  onTriggered:{if(!Config.ready)return;try{
   if(root.step%2===0){
    root.check(root.derivedDestroyed===root.step/2*8,"derived destruction handler was lost")
    if(root.step===root.cycles*2){
     console.info("ABYSS_PLACEMENT_MEMO_RUNTIME_PASS",root.checks,"checks;",root.derivedDestroyed,"real hosts released");Qt.quit();return
    }
    const batch=[]
    for(let i=0;i<8;i++){
     const host=factory.createObject(parentItem,{identity:"memo-"+root.step+"-"+i})
     root.check(!!host,"host construction failed")
     const placement=host.placement
     root.check(placement===null,"closed host fabricated an allocation")
     root.check(host.placementMemo.record===null,"host does not own its current placement")
     root.check(batch.every(other=>other.placementMemo!==host.placementMemo),"different hosts share a cache")
     root.check(Object.keys(host.placementMemo).length===1,"host retains placement history")
     batch.push(host)
    }
    root.hosts=batch
   }else{for(const host of root.hosts)host.destroy();root.hosts=[]}
   root.step++
  }catch(error){console.error("ABYSS_PLACEMENT_MEMO_RUNTIME_FAIL",error.message,error.stack);Qt.quit()}}
 }
}
''')
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_CONFIG_HOME=str(folder / "config"),
               XDG_STATE_HOME=str(folder / "state"), XDG_CACHE_HOME=str(folder / "cache"))
    env.pop("QS_CONFIG_NAME", None)
    env.pop("QS_CONFIG_PATH", None)
    result = run_qs(folder, env, timeout=25)
    destination = os.environ.get("ALIS_PLACEMENT_MEMO_LOG")
    if destination:
        Path(destination).write_text(result.stdout)
    bad = ["ABYSS_PLACEMENT_MEMO_RUNTIME_FAIL", "TypeError:", "ReferenceError:", "Binding loop",
           "Unable to assign", "Failed to load configuration"]
    if result.returncode or "ABYSS_PLACEMENT_MEMO_RUNTIME_PASS" not in result.stdout or any(x in result.stdout for x in bad):
        print(result.stdout)
        raise SystemExit(1)
    for line in result.stdout.splitlines():
        if "ABYSS_PLACEMENT_MEMO_RUNTIME_PASS" in line:
            print(line)
