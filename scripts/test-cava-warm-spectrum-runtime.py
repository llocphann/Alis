#!/usr/bin/env python3
"""Actual analyzer owner and spectrum, using an owned silent fake CAVA pipe."""
import json, os, tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="hadalis-cava-warm-") as name:
 folder=Path(name)
 for entry in ["modules","services","GlobalStates.qml","qmldir","assets","defaults","translations"]:(folder/entry).symlink_to(ROOT/entry)
 generator=folder/"scripts/cava/generate_config.sh";generator.parent.mkdir(parents=True)
 generator.write_text('#!/bin/sh\nprintf "%s\\n" "$4" > "$1"\nif [ "${7:-}" = "--print-config" ]; then cat "$1"; fi\n');generator.chmod(0o700)
 binary=folder/"bin";binary.mkdir();cava=binary/"cava"
 cava.write_text('''#!/usr/bin/env python3
import os,sys,time
count=int(open(sys.argv[-1]).read())
with open(os.environ['CAVA_LOG'],'a') as f:f.write(str(count)+'\\n')
try:
 while True:
  print(';'.join(['70']*count)+';',flush=True);time.sleep(.033)
except BrokenPipeError:pass
''');cava.chmod(0o700)
 (folder/"shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss
import qs.services.deferred
ShellRoot {
 id:root
 Component.onCompleted:Quickshell.watchFiles=false
 CavaProcess {id:background;active:false}
 CavaProcess {id:popup;active:false;sampleCount:64}
 CavaProcess {id:wide;active:false;sampleCount:128}
 AbyssWaveController {id:waves;outputWidth:1280;outputHeight:720}
 AbyssSpectrumController {id:spectrum;waves:waves;playing:false}
 TestCase {
  id:test;when:false;optional:true
  function check(v,m){if(!v)throw new Error(m)}
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000)
   Config.setNestedValues({"appearance.cava.bars":0,"abyss.waves.enabled":false,"abyss.spectrum.configured":true,"abyss.spectrum.enabled":true})
   background.active=true;tryVerify(()=>CavaService.points.length===64,4000)
   for(let i=0;i<5;i++){popup.active=true;wait(360);popup.active=false;wait(360)}
   check(CavaService.effectiveBars===64,"popup changed analyzer capacity")
   spectrum.playing=true;wait(150)
   const phase=spectrum.phase,revision=waves.revision
   wait(200)
   check(spectrum.phase!==phase && waves.revision>revision,"static frames lost old upstream wave phase")
   check(!waves.running && waves.simulation.steps===0 && waves.simulation.hasSpectrum,"audio started elastic solver")
   spectrum.playing=false;check(!waves.simulation.hasSpectrum,"pause retained spectrum")
   wide.active=true;tryVerify(()=>CavaService.points.length===128,3000)
   wide.active=false;wait(400)
   check(CavaService.effectiveBars===128,"consumer departure restarted smaller analyzer")
   background.active=false;wait(200);popup.active=true;wait(300)
   check(CavaService.effectiveBars===128 && CavaService.points.length===128,"warm reopen changed capacity or lost frame")
   popup.active=false;wait(1000)
   check(!CavaService.active && CavaService._warmBars===0,"idle analyzer did not release capacity")
   console.info("CAVA_WARM_PASS popup isolation static-frame bounce zero-solver bounded-capacity warm-reopen idle-stop")
  }catch(e){console.error("CAVA_WARM_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
 with private_wayland(folder) as env:
  if env is None:print("SKIP: CAVA warm spectrum requires private Niri");raise SystemExit(0)
  config=folder/"config/illogical-impulse";config.mkdir(parents=True,exist_ok=True)
  value=json.loads((ROOT/"defaults/config.json").read_text());value["panelFamily"]="abyss"
  (config/"config.json").write_text(json.dumps(value))
  env.update(PATH=str(binary)+os.pathsep+env["PATH"],CAVA_LOG=str(folder/"starts.log"),QSG_RHI_BACKEND="opengl")
  result=run_qs(folder,env,25)
  if result.returncode or "CAVA_WARM_PASS" not in result.stdout or any(x in result.stdout for x in ["CAVA_WARM_FAIL","ReferenceError:","TypeError:","Binding loop","Failed to load configuration"]):print(result.stdout);raise SystemExit(1)
  starts=(folder/"starts.log").read_text().splitlines()
  assert starts==["64","128"],starts
  print("CAVA_WARM_PASS 5 popup cycles: 0 analyzer restarts; 1 genuine capacity growth; warm reopen; static-frame bounce; 0 audio solver steps; idle teardown")
