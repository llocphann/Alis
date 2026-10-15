#!/usr/bin/env python3
"""Real config generator and QML owner, using only fixture audio processes."""
import configparser
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]


def executable(path, text):
    path.write_text(text)
    path.chmod(0o700)


with tempfile.TemporaryDirectory(prefix="alis-cava-refresh-") as name:
    folder = Path(name)
    binary = folder / "bin"
    binary.mkdir()
    state = {"source": "101", "output": "frames", "generation": "normal"}
    (folder / "state.json").write_text(json.dumps(state))
    (folder / "events.jsonl").touch()
    executable(binary / "pactl", '''#!/usr/bin/env python3
import json, os, pathlib, sys
s=json.loads((pathlib.Path(os.environ['CAVA_FIXTURE'])/'state.json').read_text())
args=sys.argv[1:]
if args==['info']: print('Server Name: PulseAudio (on PipeWire 1.4)')
elif args==['get-default-sink']: print('fixture-sink')
elif args==['list','sink-inputs']:
 print('Sink Input #1\\n\\tCorked: no\\n\\tProperties:\\n'
       '\\t\\tnode.name = "fixture-music"\\n'
       '\\t\\tobject.serial = "'+s['source']+'"\\n'
       '\\t\\tmedia.role = "music"\\n'
       '\\t\\tapplication.process.binary = "mpv"')
elif args!=['list','clients']: raise SystemExit(2)
''')
    env = dict(os.environ, CAVA_FIXTURE=str(folder), PATH=str(binary) + os.pathsep + os.environ["PATH"])
    output = folder / "generated.conf"

    def generate(*settings):
        return subprocess.run(
            ["bash", str(ROOT / "scripts/cava/generate_config.sh"), str(output), *settings, "--print-config"],
            env=env, capture_output=True, text=True, check=True,
        ).stdout

    baseline = generate("30", "100", "64", "true", "mpv")
    before = output.stat()
    assert generate("30", "100", "64", "true", "mpv") == baseline
    after = output.stat()
    assert (before.st_ino, before.st_mtime_ns) == (after.st_ino, after.st_mtime_ns)
    parsed = configparser.ConfigParser()
    parsed.read_string(baseline)
    assert parsed["input"]["source"] == "101"
    assert parsed["input"]["active"] == "0"
    assert parsed["output"]["channels"] == "stereo"
    assert parsed["output"]["ascii_max_range"] == "1000"
    for settings in [
        ("45", "100", "64", "true", "mpv"),
        ("45", "125", "64", "true", "mpv"),
        ("45", "125", "128", "true", "mpv"),
        ("45", "125", "128", "false", "mpv"),
    ]:
        previous = output.read_text()
        current = generate(*settings)
        assert current != previous and output.read_text() == current
    assert not list(folder.glob("generated.conf.*")), "generator leaked a candidate file"
    print("CAVA_CONFIG_PASS exact full config, unchanged inode/mtime, changed rate/sensitivity/bars/stereo, atomic candidate cleanup")

    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    scripts = folder / "scripts/cava"
    scripts.mkdir(parents=True)
    shutil.copy2(ROOT / "scripts/cava/generate_config.sh", scripts / "generate_config.real.sh")
    shutil.copy2(ROOT / "scripts/cava/resolve_audio_source.py", scripts / "resolve_audio_source.py")
    shutil.copy2(ROOT / "scripts/cava/run.sh", scripts / "run.sh")
    executable(scripts / "generate_config.sh", '''#!/usr/bin/env bash
exec python3 "$(dirname -- "$0")/generate_config.fixture.py" "$@"
''')
    executable(scripts / "generate_config.fixture.py", '''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys, time
root=pathlib.Path(os.environ['CAVA_FIXTURE'])
def state(): return json.loads((root/'state.json').read_text())
with (root/'events.jsonl').open('a') as f: f.write(json.dumps({'event':'generate','args':sys.argv[1:]})+'\\n')
while state()['generation']=='hold':
 (root/'waiting').touch();time.sleep(.01)
if state()['generation']=='fail': raise SystemExit(75)
raise SystemExit(subprocess.call(['bash',str(pathlib.Path(__file__).with_name('generate_config.real.sh')),*sys.argv[1:]]))
''')
    executable(binary / "cava", '''#!/usr/bin/env python3
import configparser, json, os, pathlib, signal, sys, time
root=pathlib.Path(os.environ['CAVA_FIXTURE'])
config=configparser.ConfigParser();config.read(sys.argv[-1]);count=int(config['general']['bars'])
assert config['input']['active']=='0'
def event(kind):
 overlap=[]
 if kind=='start':
  for line in (root/'events.jsonl').read_text().splitlines():
   item=json.loads(line)
   if item['event']=='start':
    try:
     stat=pathlib.Path('/proc',str(item['pid']),'stat').read_text()
     if stat.split(') ',1)[1][0]!='Z':overlap.append(item['pid'])
    except FileNotFoundError:pass
 with (root/'events.jsonl').open('a') as f:f.write(json.dumps({'event':kind,'pid':os.getpid(),'bars':count,'source':config['input']['source'],'rate':config['general']['framerate'],'overlap':overlap,'props':os.environ.get('PIPEWIRE_PROPS'),'latency':os.environ.get('PIPEWIRE_LATENCY')})+'\\n')
def stop(*_):event('stop');raise SystemExit(0)
signal.signal(signal.SIGTERM,stop);event('start')
while True:
 state=json.loads((root/'state.json').read_text());mode=state['output']
 if mode=='crash-once' and not (root/'crashed').exists():
  (root/'crashed').touch();event('crash');raise SystemExit(42)
 if mode!='stall':
  print(';'.join(['0' if mode=='silence' else '70']*count)+';',flush=True)
 time.sleep(.033)
''')
    executable(binary / "probe-cava-pids", '''#!/usr/bin/env python3
import json,os,pathlib
root=pathlib.Path(os.environ['CAVA_FIXTURE']);alive=[]
for line in (root/'events.jsonl').read_text().splitlines():
 item=json.loads(line)
 if item['event']=='start':
  try:
   stat=pathlib.Path('/proc',str(item['pid']),'stat').read_text()
   if stat.split(') ',1)[1][0]!='Z':alive.append(item['pid'])
  except FileNotFoundError:pass
print(json.dumps(alive))
''')
    (folder / "shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services.deferred
ShellRoot {
 id:root
 property int frames:0
 Component.onCompleted:Quickshell.watchFiles=false
 Connections {target:CavaService;function onFramePublished(){root.frames++}}
 FileView {id:state;path:Quickshell.env("CAVA_FIXTURE")+"/state.json";blockLoading:true;blockWrites:true}
 FileView {id:events;path:Quickshell.env("CAVA_FIXTURE")+"/events.jsonl";blockLoading:true}
 FileView {id:waiting;path:Quickshell.env("CAVA_FIXTURE")+"/waiting";blockLoading:true;printErrors:false}
 Process {id:pidProbe;command:["probe-cava-pids"];stdout:StdioCollector{id:livePids}}
 TestCase {
  id:test;when:false;optional:true
  function check(value,message){if(!value)throw new Error(message)}
  function change(values){state.reload();const s=JSON.parse(state.text());for(const key in values)s[key]=values[key];state.setText(JSON.stringify(s))}
  function log(kind){events.reload();return events.text().trim().split("\n").filter(s=>s).map(s=>JSON.parse(s)).filter(e=>e.event===kind)}
  function starts(count){tryVerify(()=>log("start").length===count,5000);check(log("start").length===count,"unexpected analyzer start count "+JSON.stringify(log("start")))}
  function setting(key,value){Config.setNestedValue("appearance.cava."+key,value)}
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000)
   Config.setNestedValues({"appearance.cava.bars":0,"appearance.cava.framerate":30,"appearance.cava.sensitivity":100,"appearance.cava.stereo":true})
   wait(150);check(log("start").length===0,"idle service captured audio")
   let token=CavaService.subscribe(64)
   tryVerify(()=>CavaService.points.length===64,4000);starts(1)
   const first=log("start")[0].pid,frameBefore=root.frames
   for(let i=0;i<3;i++){CavaService._scheduleSourceRefresh();wait(100)}
   wait(1300);check(log("start").length===1 && root.frames>frameBefore,"same-source refresh restarted or interrupted healthy frames")
   setting("framerate",45);starts(2)
   setting("sensitivity",125);starts(3)
   setting("stereo",false);starts(4)
   change({source:"102"});CavaService._scheduleSourceRefresh();starts(5)
   check(log("start")[4].source==="102","changed source was not applied")
   CavaService.updateSubscription(token,128);starts(6);tryVerify(()=>CavaService.points.length===128,2000)

   // Superseded config may be published while the old process is still alive.
   // Returning to its exact config must retain that process, not restart based
   // merely on the last generated file's content.
   change({generation:"hold"});setting("framerate",60)
   tryVerify(()=>{waiting.reload();return waiting.loaded},3000)
   const heldFrame=root.frames,generated=log("generate").length
   setting("framerate",45);wait(350);change({generation:"normal"})
   tryVerify(()=>log("generate").length>generated,4000);wait(700)
   check(log("start").length===6 && root.frames>heldFrame,"superseded generation churned the running analyzer")

   change({generation:"fail"});CavaService._scheduleSourceRefresh();wait(1400)
   check(log("start").length===6,"failed generation stopped the healthy analyzer")
   change({generation:"normal"});wait(1400)
   check(log("start").length===6,"retry of identical config restarted the analyzer")

   change({output:"stall"});starts(7);change({output:"frames"});wait(500)
   check(log("start").length===7,"watchdog caused duplicate recovery restart")
   change({output:"silence"});wait(2800)
   check(log("start").length===7 && !CavaService.audioSignalActive,"valid silence restarted or retained the signal")
   change({output:"crash-once"});starts(8);wait(400)
   check(log("start").length===8,"crash retry was not bounded")

   CavaService.unsubscribe(token);wait(250);token=CavaService.subscribe(64);wait(400)
   check(log("start").length===8 && CavaService.effectiveBars===128,"warm reopen restarted or shrank analyzer")
   CavaService.unsubscribe(token);wait(1000)
   check(!CavaService.active && CavaService._warmBars===0,"last consumer did not stop analyzer")
   pidProbe.running=true;tryCompare(pidProbe,"running",false,2000)
   check(JSON.parse(livePids.text).length===0,"idle analyzer process survived")
   token=CavaService.subscribe(64);starts(9)
   CavaService.unsubscribe(token);setting("framerate",50);wait(150)
   token=CavaService.subscribe(64);starts(10)
   check(log("start")[9].rate==="50","setting changed during warm grace was lost")
   change({generation:"hold"});CavaService._scheduleSourceRefresh();wait(1300)
   CavaService.unsubscribe(token);wait(1000);change({generation:"normal"});wait(1300)
   check(log("start").length===10 && !CavaService.active && CavaService._warmBars===0,"late generation restarted an idle analyzer")
   console.info("CAVA_REFRESH_PASS same-source no restart; changed full config; superseded/failed generation; watchdog; silence; crash; warm reopen; idle and in-flight teardown")
  }catch(error){console.error("CAVA_REFRESH_FAIL",error.message,error.stack,"state",CavaService.active,CavaService.points.length,CavaService._pendingConfigGeneration,CavaService._processConfigText,JSON.stringify(log("start")),JSON.stringify(log("generate")))}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
    with private_wayland(folder) as native_env:
        if native_env is None:
            print("SKIP: CAVA config refresh runtime requires private Niri; generator checks passed separately")
            raise SystemExit(0)
        config = folder / "config/alis"
        config.mkdir(parents=True, exist_ok=True)
        (config / "config.json").write_text((ROOT / "defaults/config.json").read_text())
        native_env.update(PATH=env["PATH"], CAVA_FIXTURE=str(folder), QSG_RHI_BACKEND="opengl")
        native_env.pop("PIPEWIRE_PROPS", None)
        native_env.pop("PIPEWIRE_LATENCY", None)
        result = run_qs(folder, native_env, 65)
        failures = ["CAVA_REFRESH_FAIL", "ReferenceError:", "TypeError:", "Binding loop", "Failed to load configuration"]
        if result.returncode or "CAVA_REFRESH_PASS" not in result.stdout or any(x in result.stdout for x in failures):
            print(result.stdout)
            raise SystemExit(1)
    records = [json.loads(line) for line in (folder / "events.jsonl").read_text().splitlines()]
    for record in records:
        if record["event"] == "start":
            assert not record["overlap"], f"overlapping analyzer processes: {record}"
            assert record["props"] == "{ node.latency = null }" and record["latency"] is None, record
    probe = subprocess.run([str(binary / "probe-cava-pids")], env=env, capture_output=True, text=True, check=True)
    assert json.loads(probe.stdout) == [], f"analyzer survived test teardown: {probe.stdout}"
    print("CAVA_REFRESH_PASS ten expected starts; no concurrent/idle capture; only fixture pactl/CAVA used")
