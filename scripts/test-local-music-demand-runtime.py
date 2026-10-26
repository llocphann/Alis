#!/usr/bin/env python3
"""Actual LocalMusic presentation events with private MPD/status processes."""
import os
from pathlib import Path
import tempfile
from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-music-demand-") as name:
    shell = Path(name)
    def write(path, text):
        target = shell / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
    write("qmldir", "module qs\nsingleton GlobalStates 1.0 GlobalStates.qml\n")
    write("GlobalStates.qml", '''pragma Singleton
import QtQuick
QtObject { property bool dashboardOpen:false; property bool overviewOpen:false
 property string overviewMode:"dashboard"; property int dashboardPage:0
 property bool sidebarLeftOpen:false }
''')
    write("services/qmldir", "module qs.services\nsingleton LocalMusic 1.0 LocalMusic.qml\nsingleton MprisController 1.0 MprisController.qml\n")
    source = (ROOT / "services/LocalMusic.qml").read_text()
    assert source.count("id: root") == 1 and source.count("id: pollTimer") == 1
    # Test-only timer reference: retain every production expression/callback.
    write("services/LocalMusic.qml", source.replace("id: root", "id: root\n    readonly property var fixturePollTimer: pollTimer"))
    write("services/MprisController.qml", '''pragma Singleton
import QtQuick
QtObject { property var mpdPlayer:null; function ensureMpdMprisBridge(host,port) {} }
''')
    write("modules/common/qmldir", "module qs.modules.common\nsingleton Config 1.0 Config.qml\nsingleton Directories 1.0 Directories.qml\n")
    write("modules/common/Config.qml", '''pragma Singleton
import QtQuick
QtObject { property bool ready:true
 property var options:({dashboard:{music:{enable:false}},sidebar:{music:{mpdHost:"fixture.invalid",mpdPort:6600}}}) }
''')
    write("modules/common/Directories.qml", '''pragma Singleton
import QtQuick
import Quickshell
QtObject {
 readonly property string scriptsPath:Quickshell.env("FIXTURE_ROOT")+"/bin"
 readonly property string stateUserPath:Quickshell.env("FIXTURE_ROOT")+"/state"
 readonly property string music:Quickshell.env("FIXTURE_ROOT")+"/music"
}
''')
    write("modules/common/functions/qmldir", "module qs.modules.common.functions\nsingleton FileUtils 1.0 FileUtils.qml\n")
    write("modules/common/functions/FileUtils.qml", r'''pragma Singleton
import QtQuick
QtObject { function trimFileProtocol(value){return String(value).replace(/^file:\/\//,"")} }
''')
    write("bin/native-dispatch", r'''#!/usr/bin/python3
import json,os,sys
from pathlib import Path
with (Path(os.environ["FIXTURE_ROOT"])/"calls").open("a") as f:
    f.write(json.dumps(sys.argv[1:])+"\n")
if sys.argv[1:]==["backend-info"]: print("mode=python\nalis-mpdd=missing")
else: print(json.dumps({"connected":True,"tracks":[],"queue":[],"playlists":[],"state":"stop"}))
''')
    (shell / "bin/native-dispatch").chmod(0o755)
    (shell / "state").mkdir()
    (shell / "calls").touch()
    write("shell.qml", '''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
ShellRoot {
 FileView {id:calls;path:Quickshell.env("FIXTURE_ROOT")+"/calls";blockLoading:true}
 TestCase {
  id:test;when:false;optional:true
  function check(value,message){if(!value)throw new Error(message)}
  function statuses(){calls.reload();return calls.text().trim().split("\\n").filter(line=>{
    if(!line)return false;const args=JSON.parse(line);return args[0]==="mpd" && args[1]==="status"}).length}
  function snapshots(){calls.reload();return calls.text().trim().split("\\n").filter(line=>line).map(line=>JSON.parse(line)).filter(args=>args[0]==="mpd" && args[1]==="snapshot")}
  function quiet(before,message){wait(250);check(statuses()===before,message)}
  function requested(before,message){tryVerify(()=>statuses()===before+1,1500);wait(80);check(statuses()===before+1,message)}
  function runChecks(){try{
   if(Quickshell.env("FIXTURE_COLD")==="1"){
    check(LocalMusic.enabled,"cold selected Music lost enable intent")
    tryVerify(()=>LocalMusic.available && !LocalMusic.scanning,1500)
    check(LocalMusic.fixturePollTimer.interval===900,"cold selected Music retained hidden cadence")
    console.info("LOCAL_MUSIC_DEMAND_PASS cold selected Music without initialization errors")
    Qt.quit();return
   }
   check(!LocalMusic.enabled,"fixture started enabled")
   Config.options={dashboard:{music:{enable:true}},sidebar:{music:{mpdHost:"fixture.invalid",mpdPort:6600}}}
   tryVerify(()=>LocalMusic.available && !LocalMusic.scanning,1500)
   wait(350)
   tryVerify(()=>snapshots().length>0,1500)
   const scans=snapshots()
   check(scans.length>0 && scans.every(args=>args[args.length-1]==="--lean"),"internal scans did not request the additive lean route: "+JSON.stringify(scans))
   const timer=LocalMusic.fixturePollTimer
   check(timer && timer.interval===30000,"hidden fallback cadence changed")
   check(timer.running,"enabled fallback clock is stopped")
   LocalMusic._mpdSubscriptionActive=true
   check(!timer.running,"native subscription retained periodic fallback")
   LocalMusic._mpdSubscriptionActive=false
   check(timer.running,"fallback did not resume after the native lease ended")
   // Isolate event-driven refresh from the separately verified periodic clock.
   timer.running=false
   let before=statuses()
   GlobalStates.sidebarLeftOpen=true
   quiet(before,"retired sidebar triggered Music sampling")
   GlobalStates.dashboardOpen=true
   quiet(before,"non-Music Dashboard triggered sampling")
   GlobalStates.dashboardPage=1
   requested(before,"Music entry did not request exactly one status")
   check(timer.interval===900,"presented Music did not use active cadence")
   before=statuses();GlobalStates.dashboardOpen=false
   quiet(before,"hidden Music exit requested status")
   check(timer.interval===30000,"hidden Music retained active cadence")
   GlobalStates.overviewOpen=true
   requested(before,"Overview Music entry did not refresh")
   before=statuses();GlobalStates.overviewMode="overview"
   quiet(before,"other Overview mode sampled Music")
   GlobalStates.overviewMode="dashboard"
   requested(before,"Overview mode reentry did not refresh")
   before=statuses();GlobalStates.dashboardOpen=true
   quiet(before,"overlapping Dashboard routes doubled refresh")
   GlobalStates.overviewOpen=false
   quiet(before,"leaving one of two routes requested refresh")
   GlobalStates.dashboardPage=0
   quiet(before,"non-Music page requested refresh")
   LocalMusic._mpdSubscriptionActive=true
   GlobalStates.dashboardPage=1
   quiet(before,"active native subscription received duplicate fallback")
   LocalMusic._mpdSubscriptionActive=false
   Config.options={dashboard:{music:{enable:false}},sidebar:{music:{}}}
   GlobalStates.dashboardOpen=false;GlobalStates.dashboardOpen=true
   quiet(before,"disabled Music triggered status")
   console.info("LOCAL_MUSIC_DEMAND_PASS actual event requests, both routes, hidden cadence, overlap, subscription and disabled guards")
  }catch(error){console.error("LOCAL_MUSIC_DEMAND_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:50;running:true;onTriggered:test.runChecks()}
}
''')
    runtime = shell / "runtime"
    runtime.mkdir(mode=0o700)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=str(runtime),
               FIXTURE_ROOT=str(shell), XDG_CONFIG_HOME=str(shell / "config"),
               XDG_CACHE_HOME=str(shell / "cache"), XDG_DATA_HOME=str(shell / "data"),
               XDG_STATE_HOME=str(shell / "state"))
    for key in ("NIRI_SOCKET", "WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
        env.pop(key, None)
    result = run_qs(shell, env, timeout=20)
    if result.returncode or "LOCAL_MUSIC_DEMAND_PASS" not in result.stdout or any(token in result.stdout for token in ("LOCAL_MUSIC_DEMAND_FAIL", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign", "Failed to load configuration")):
        print(result.stdout)
        raise SystemExit(1)
    path = shell / "modules/common/Config.qml"
    path.write_text(path.read_text().replace("enable:false", "enable:true"))
    path = shell / "GlobalStates.qml"
    path.write_text(path.read_text().replace("dashboardOpen:false", "dashboardOpen:true").replace("dashboardPage:0", "dashboardPage:1"))
    result = run_qs(shell, dict(env, FIXTURE_COLD="1"), timeout=8)
    if result.returncode or "LOCAL_MUSIC_DEMAND_PASS cold" not in result.stdout or any(token in result.stdout for token in ("LOCAL_MUSIC_DEMAND_FAIL", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign", "Failed to load configuration")):
        print(result.stdout)
        raise SystemExit(1)
    print("LOCAL_MUSIC_DEMAND_PASS private real QML/process contract; no owner MPD or desktop")
