#!/usr/bin/env python3
"""Actual output utility retains Cheatsheet throughout its closing slide."""
import json,tempfile
from pathlib import Path
from native_test_session import private_wayland,run_qs
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-utility-close-") as name:
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
 Component.onCompleted:Quickshell.watchFiles=false
 AbyssPerimeter {id:perimeter}
 TestCase {
  id:test;when:false;optional:true
  function check(v,m){if(!v)throw new Error(m)}
  function find(item,p){if(p(item))return item;for(const c of item.children??[]){const r=find(c,p);if(r)return r}return null}
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000);GlobalStates.deferredPanelsReady=true
   GlobalStates.cheatsheetOpen=true
   tryVerify(()=>perimeter.outputHosts.length>0,5000)
   const host=perimeter.outputHosts[0]
   const utility=find(host.contentItem,i=>i.identity==="utility" && i.contentItem!==undefined)
   check(utility!==null,"utility output host missing")
   tryVerify(()=>utility.ready && utility.progress>.99,6000)
   const feature=utility.contentItem.item.feature
   check(utility.contentKind==="cheatsheet" && feature!==null,"Cheatsheet did not open")
   GlobalStates.cheatsheetOpen=false
   wait(40)
   check(utility.progress>0 && utility.progress<1,"close fixture lost animated retraction")
   check(utility.contentKind==="cheatsheet" && utility.contentItem.item.feature===feature && !ShellUpdates.overlayOpen,"close selected Update during Cheatsheet retraction")
   tryVerify(()=>!utility.visualResident && !utility.ready,3000)
   ShellUpdates.overlayOpen=true
   tryVerify(()=>utility.ready && utility.contentKind==="update",5000)
   check(utility.contentItem.item.feature!==feature,"real Update could not open after close")
   ShellUpdates.overlayOpen=false
   console.info("UTILITY_CLOSING_PASS Cheatsheet identity retained through close; explicit Update opens normally")
  }catch(e){console.error("UTILITY_CLOSING_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
 with private_wayland(folder) as env:
  if env is None:print("SKIP: utility slide test requires private Niri");raise SystemExit(0)
  cfg=folder/"config/illogical-impulse";cfg.mkdir(parents=True,exist_ok=True)
  data=json.loads((ROOT/"defaults/config.json").read_text());data["enabledPanels"]=["iiCheatsheet","iiShellUpdate","abyssSessionScreen"];data["abyss"]["companion"]["enabled"]=False
  (cfg/"config.json").write_text(json.dumps(data));env["QSG_RHI_BACKEND"]="opengl"
  result=run_qs(folder,env,25)
  if result.returncode or "UTILITY_CLOSING_PASS" not in result.stdout or any(x in result.stdout for x in ["UTILITY_CLOSING_FAIL","ReferenceError:","TypeError:","Binding loop","Failed to load configuration"]):print(result.stdout);raise SystemExit(1)
  print("UTILITY_CLOSING_PASS real output slide retains Cheatsheet; deliberate Update still opens")
