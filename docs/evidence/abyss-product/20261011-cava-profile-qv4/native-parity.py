#!/usr/bin/env python3
"""Unpromoted candidate: actual typed QML vectors, scratch identity and NOTIFY."""
import json,sys,tempfile
from pathlib import Path
ROOT=Path(sys.argv[1]);sys.path.insert(0,str(ROOT/'scripts'))
from native_test_session import private_wayland,run_qs
with tempfile.TemporaryDirectory(prefix='alis-cava-profile-native-') as name:
 folder=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 (folder/'staged').mkdir()
 (folder/'staged/qmldir').write_text('module Staged\nCandidate 1.0 Candidate.qml\n')
 (folder/'staged/Candidate.qml').write_bytes((ROOT/'docs/evidence/abyss-product/20261010-hover-checkpoint/unpromoted/bar-cava-candidate.qml').read_bytes())
 (folder/'shell.qml').write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import "staged" as Staged
ShellRoot {
 id:root
 property int beforeNotify:0
 property int afterNotify:0
 property int frames:0
 property int checks:0
 Component.onCompleted:Quickshell.watchFiles=false
 FloatingWindow {
  visible:true;implicitWidth:800;implicitHeight:210;color:"#10242b"
  BarCavaVisualizer {id:before;x:0;y:0;width:256;height:96;spectrumOpacity:0;mirroredStereo:true;spectrumColor:"#a0d5ee";spectrumColors:["#a0d5ee"]}
  Staged.Candidate {id:after;x:384;y:0;width:256;height:96;spectrumOpacity:0;mirroredStereo:true;spectrumColor:"#a0d5ee";spectrumColors:["#a0d5ee"]}
 }
 TestCase {
  id:test;when:false;optional:true
  function check(v,m){root.checks++;if(!v)throw new Error(m)}
  function equal(a,b,name){check(a.length===b.length,name+" length");for(let i=0;i<a.length;i++)check(Object.is(a[i],b[i]),name+" at "+i+": "+a[i]+"/"+b[i])}
  function runChecks(){try{
   tryCompare(Config,"ready",true,6000)
   Config.setNestedValue("performance.reduceAnimations",true)
   before._levelsChanged.connect(()=>root.beforeNotify++)
   after._levelsChanged.connect(()=>root.afterNotify++)
   const oldSelected=before._selectedScratch,newSelected=after._selectedScratch
   const oldSmooth=before._smoothScratch,newSmooth=after._smoothScratch
   for(const item of [before,after])item.active=true
   for(const count of [0,1,2,3,8,64,128])for(const profile of ["flat","bass","warm","vocal","treble","smile","unknown"])
   for(const stereo of [false,true])for(const strength of [-.2,0,.7,1.4])for(const smoothing of [0,2])for(const mode of ["bars","wave"]){
    for(const item of [before,after]){item.frequencyProfile=profile;item.mirroredStereo=stereo;item.accentStrength=strength;item.smoothing=smoothing;item.visualizerType=mode}
    for(let frame=0;frame<3;frame++){
     const values=Array.from({length:count},(_,i)=>((i*179+frame*83)%1800)-300)
     if(count>8){values[2]="70";values[5]=undefined;values[7]=NaN}
     const oldLevels=before._levels,newLevels=after._levels
     before.points=values.slice();after.points=values.slice();root.frames++
     equal(before._selectedScratch,after._selectedScratch,"selected")
     equal(before._smoothScratch,after._smoothScratch,"smoothed")
     equal(before._levels,after._levels,"levels")
     check(before._selectedScratch===oldSelected && after._selectedScratch===newSelected,"selected scratch replacement")
     check(before._smoothScratch===oldSmooth && after._smoothScratch===newSmooth,"smooth scratch replacement")
     check((before._levels===oldLevels)===(after._levels===newLevels),"published identity transition")
     check((before._levels===before._levelScratchA)===(after._levels===after._levelScratchA),"A buffer selection")
     check((before._levels===before._levelScratchB)===(after._levels===after._levelScratchB),"B buffer selection")
     check(root.beforeNotify===root.afterNotify,"native levels NOTIFY count diverged")
    }
   }
   for(const active of [false,true,false,true]){before.active=active;after.active=active;equal(before._levels,after._levels,"active cycle");check(root.beforeNotify===root.afterNotify,"active NOTIFY diverged")}
   console.info("CAVA_NATIVE_PROFILE_PASS",JSON.stringify({frames:root.frames,checks:root.checks,beforeNotify:root.beforeNotify,afterNotify:root.afterNotify}))
  }catch(e){console.error("CAVA_NATIVE_PROFILE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer{interval:100;running:true;onTriggered:test.runChecks()}
}
''')
 with private_wayland(folder) as env:
  if env is None:raise SystemExit('SKIP: private Niri required')
  config=folder/'config/illogical-impulse/config.json';config.parent.mkdir(parents=True,exist_ok=True)
  data=json.loads((ROOT/'defaults/config.json').read_text());data['panelFamily']='abyss';data['abyss']['companion']['enabled']=False
  config.write_text(json.dumps(data));env['QSG_RHI_BACKEND']='opengl'
  result=run_qs(folder,env,timeout=100)
  Path('/tmp/alis-cava-native-parity-20261011.log').write_text(result.stdout)
  if result.returncode or 'CAVA_NATIVE_PROFILE_PASS' not in result.stdout or any(t in result.stdout for t in ['CAVA_NATIVE_PROFILE_FAIL','TypeError:','ReferenceError:','Binding loop','Unable to assign','Failed to load configuration']):
   print(result.stdout);raise SystemExit(1)
  for line in result.stdout.splitlines():
   if 'CAVA_NATIVE_PROFILE_PASS' in line:print(line)
