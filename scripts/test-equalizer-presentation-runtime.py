#!/usr/bin/env python3
"""Real DSP facade/panel; owned fake transport never changes desktop audio."""
import json, os, tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-eq-presentation-") as name:
    folder = Path(name)
    for entry in ["modules", "GlobalStates.qml", "qmldir", "assets", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    services = folder / "services"
    services.mkdir()
    for entry in (ROOT / "services").iterdir():
        if entry.name != "deferred": (services / entry.name).symlink_to(entry)
    deferred = services / "deferred"
    deferred.mkdir()
    for entry in (ROOT / "services/deferred").iterdir():
        if entry.name not in ["EasyEffects.qml", "CavaService.qml"]:
            (deferred / entry.name).symlink_to(entry)
    (deferred / "EasyEffects.qml").write_text('''pragma Singleton
import QtQuick
import Quickshell
Singleton {
 property bool available: true
 property bool active: true
 property bool nativeInstalled: true
 function fetchAvailability() {}
 function fetchActiveState() {}
 function enable() { active=true }
}
''')
    (deferred / "CavaService.qml").write_text('''pragma Singleton
import QtQuick
import Quickshell
Singleton {
 property var points: []
 property real normalizationCeiling: 100
 property bool audioSignalActive: false
 signal framePublished()
 function subscribe(count) { return 1 }
 function updateSubscription(token,count) {}
 function unsubscribe(token) {}
}
''')
    scripts = folder / "scripts"
    scripts.mkdir()
    helper = scripts / "equalizer-control.sh"
    helper.write_text('''#!/usr/bin/env python3
import json,os,sys,time
if sys.argv[1]=='get':
 print(json.dumps({'gains':[5,7,5,2,1,0,0,0,1,2],'preset':'Bass'}))
else:
 with open(os.environ['EQ_LOG'],'a') as f:f.write('begin '+ ' '.join(sys.argv[1:])+'\\n')
 time.sleep(.35)
 with open(os.environ['EQ_LOG'],'a') as f:f.write('complete\\n')
''')
    helper.chmod(0o700)
    (folder / "shell.qml").write_text(r'''
import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.mediaControls
import qs.services.deferred
ShellRoot {
 id:root
 Component.onCompleted:Quickshell.watchFiles=false
 FloatingWindow {
  id:window;visible:true;width:560;height:320;color:"#111820"
  Loader {id:panel;anchors.fill:parent;active:false;sourceComponent:EqualizerPanel {active:true}}
 }
 TestCase {
  id:test;when:false;optional:true
  function check(v,m){if(!v)throw new Error(m)}
  function sliders(item,result){if(item.userMoved!==undefined)result.push(item);for(const c of item.children??[])sliders(c,result);return result}
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000)
   for(let i=0;i<4;i++){
    GlobalStates.sidebarRightOpen=i===0
    GlobalStates.dashboardOpen=i===1
    GlobalStates.clipboardOpen=i===2
    GlobalStates.overviewOpen=i===3
    panel.active=true
    tryCompare(EqualizerService,"dspControlAvailable",true,3000)
    check(EqualizerService.dspPresetName==="Bass","presentation changed preset")
    const bands=sliders(panel.item,[])
    check(bands.length===10,"missing actual DSP sliders")
    for(const b of bands){b.pressed=true;b.pressed=false}
    check(!EqualizerService.busy,"non-edit press/release reapplied DSP")
    panel.active=false;wait(50)
    check(!EqualizerService.enabled,"idle presentation retained work")
   }
   panel.active=true;tryCompare(EqualizerService,"dspControlAvailable",true,3000)
   const b=sliders(panel.item,[])[0]
   b.forceActiveFocus();keyClick(Qt.Key_Up)
   tryCompare(EqualizerService,"busy",true,1000)
   panel.active=false
   check(EqualizerService.enabled,"closing killed active DSP transaction")
   tryCompare(EqualizerService,"busy",false,3000)
   tryCompare(EqualizerService,"enabled",false,1000)
   check(EqualizerService.dspPresetName==="Custom","keyboard edit did not commit")
   console.info("EQ_PRESENTATION_PASS non-flat reopen no-write keyboard transaction-survives-close idle-release")
  }catch(e){console.error("EQ_PRESENTATION_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
    with private_wayland(folder) as env:
        if env is None: print("SKIP: DSP presentation requires private Niri"); raise SystemExit(0)
        config = folder / "config/alis"
        config.mkdir(parents=True, exist_ok=True)
        value = json.loads((ROOT / "defaults/config.json").read_text())
        value["panelFamily"] = "abyss"
        (config / "config.json").write_text(json.dumps(value))
        env.update(EQ_LOG=str(folder / "transport.log"), QSG_RHI_BACKEND="opengl")
        result = run_qs(folder, env, 25)
        if result.returncode or "EQ_PRESENTATION_PASS" not in result.stdout or any(x in result.stdout for x in ["EQ_PRESENTATION_FAIL", "ReferenceError:", "TypeError:", "Binding loop", "Failed to load configuration"]):
            print(result.stdout); raise SystemExit(1)
        lines = (folder / "transport.log").read_text().splitlines()
        assert len(lines) == 2 and lines[0].startswith("begin apply native Custom ") and lines[1] == "complete", lines
        print("EQ_PRESENTATION_PASS 4 non-flat surface reopen cycles: 0 DSP writes; 1 user keyboard edit completed after close")
