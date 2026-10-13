#!/usr/bin/env python3
"""QV4 legacy parity, publication/cache lifetime, and optional GPU RGBA oracle."""
import argparse
import json
import os
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--gpu', action='store_true')
parser.add_argument('--output', type=Path)
args = parser.parse_args()
if args.output:
    args.output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='alis-cava-profile-') as name:
    folder = Path(name)
    for entry in ['modules', 'services', 'GlobalStates.qml', 'qmldir', 'assets',
                  'scripts', 'defaults', 'translations']:
        (folder / entry).symlink_to(ROOT / entry)
    (folder / 'reference.js').write_bytes(
        (ROOT / 'scripts/fixtures/bar-cava-profile-reference.js').read_bytes())
    (folder / 'visuals').mkdir()
    source = (ROOT / 'modules/common/widgets/BarCavaVisualizer.qml').read_text()
    # Numeric parity executes the actual production hot path without creating
    # thousands of scene delegates. The GPU run uses the complete component.
    if not args.gpu:
        source = source[:source.index('    function _cornerInset(')] + '}\n'
    source = source.replace('    id: root', '    id: root\n    property int profileCalls: 0\n    property bool traceProfile: false', 1)
    source = source.replace('function _profileWeight(position): real {',
        'function _profileWeight(position): real {\n        if (root.traceProfile) root.profileCalls++', 1)
    (folder / 'visuals/CandidateBar.qml').write_text(source)
    (folder / 'LegacyBar.qml').write_text('''
import "../visuals"
import "reference.js" as Reference
CandidateBar {
 id:root
 function _processedSource(): var { return Reference.processedSource(root) }
}
''')
    (folder / 'legacy').mkdir()
    (folder / 'LegacyBar.qml').rename(folder / 'legacy/LegacyBar.qml')
    (folder / 'reference.js').rename(folder / 'legacy/reference.js')
    body = r'''
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import "legacy"
import "visuals"
Window {
 id:root;visible:GPU;width:800;height:260;color:"#111820"
 property int checks:0
 property int captures:0
 property int oldPublications:0
 property int newPublications:0
 CandidateBar {id:candidate;x:16;y:24;width:720;height:96;visible:GPU}
 LegacyBar {id:baseline;x:16;y:140;width:720;height:96;visible:GPU}
 TestCase {
  id:test;when:false;optional:true
  function check(value,label){root.checks++;if(!value)throw new Error(label)}
  function equal(a,b,label){check(a.length===b.length,label+" length");for(let i=0;i<a.length;i++)check(Object.is(a[i],b[i]),label+" sample "+i)}
  function set(key,value){baseline[key]=value;candidate[key]=value}
  function parity(label){
   equal(candidate._processedSource(),baseline._processedSource(),label+" source")
   equal(candidate._levels,baseline._levels,label+" levels")
   check(root.oldPublications===root.newPublications,label+" publication count")
  }
  function grab(item,path){let done=false;check(item.grabToImage(result=>{check(result.saveToFile(path),"save GPU image");done=true}),"grab GPU image");tryVerify(()=>done,4000);root.captures++}
  function run(){try{
   tryCompare(Config,"ready",true,4000)
   Config.setNestedValue("performance.reduceAnimations",true)
   baseline._levelsChanged.connect(()=>root.oldPublications++)
   candidate._levelsChanged.connect(()=>root.newPublications++)
   const counts=GPU?[64,128]:[0,1,2,3,17,64,128,256,320]
   const profiles=["flat","warm","bass","vocal","treble","smile","unknown"]
   const special=[0,-2,NaN,Infinity,-Infinity,undefined,null,"80",.125]
   let cases=0
   for(const profile of GPU?["flat","bass"]:profiles)for(const stereo of [false,true])for(const strength of GPU?[.7]:[-1,0,.3,1,3,NaN]){
    set("frequencyProfile",profile);set("mirroredStereo",stereo);set("accentStrength",strength)
    for(const count of counts)for(const radius of [0,2,9])for(const kind of ["bars","wave"]){
     set("smoothing",radius);set("visualizerType",kind);set("active",true)
     for(let frame=0;frame<3;frame++){
      const values=Array.from({length:count},(_,i)=>frame===0?special[i%special.length]:((i*41+frame*53)%1000))
      set("points",values);parity("case "+cases+" frame "+frame)
      if(count>0){
       const a=candidate._levels,b=baseline._levels,flip=candidate._levelScratchFlip
       candidate._rebuildLevels();baseline._rebuildLevels();parity("explicit frame")
       check(candidate._levels!==a&&baseline._levels!==b,"fresh publication identity")
       check(candidate._levelScratchFlip!==flip,"alternate buffer")
       check(candidate._levels===candidate._levelScratchA||candidate._levels===candidate._levelScratchB,"owned buffer")
      }
     }
     set("active",false);parity("inactive")
     set("active",true);parity("warm return")
     if(GPU)wait(0)
     cases++
    }
   }
   set("points",Array(128).fill(80));set("frequencyProfile","bass");set("accentStrength",.7)
   const factors=candidate._profileCache.factors,cache=candidate._profileCache
   candidate.traceProfile=true
   for(let frame=0;frame<100;frame++)set("points",Array.from({length:128},(_,i)=>i+frame))
   check(candidate.profileCalls===0,"same configuration recomputed profile weights")
   check(candidate._profileCache===cache&&cache.factors===factors,"per-frame cache allocation")
   set("frequencyProfile","vocal");check(candidate.profileCalls===128,"profile invalidation")
   set("accentStrength",2);check(candidate.profileCalls===256,"clamped strength invalidation")
   set("accentStrength",3);check(candidate.profileCalls===256,"equal clamped strength recomputed")
   set("mirroredStereo",!candidate.mirroredStereo);check(candidate.profileCalls===384,"stereo invalidation")
   set("points",Array(64).fill(0));check(candidate.profileCalls===448&&factors.length===64,"sample count invalidation")
   set("frequencyProfile","flat");set("points",Array(320).fill(80));check(candidate.profileCalls===448,"flat must bypass profile")
   candidate.traceProfile=false
   const timings=[]
   set("visualizerType","bars");set("smoothing",2);set("points",Array.from({length:128},(_,i)=>i*3));set("accentStrength",.7)
   for(const profile of ["flat","bass","vocal","treble","smile"]){
    set("frequencyProfile",profile)
    for(let pair=0;pair<6;pair++){
     let result={profile:profile,pair:pair,iterations:6000,order:pair%2?"BA":"AB"}
     for(const item of pair%2?[candidate,baseline]:[baseline,candidate]){
      for(let j=0;j<100;j++)item._processedSource()
      const start=Date.now();for(let j=0;j<6000;j++)item._processedSource()
      result[item===baseline?"baseline_ms":"candidate_ms"]=Date.now()-start
     }
     timings.push(result)
    }
   }
   console.info("BAR_PROFILE_TIMINGS",JSON.stringify(timings))
   if(GPU){
    let scene=0
    for(const kind of ["bars","fill","line","ribbon"])for(const origin of ["bottom","top","center","mirror"]){
     set("visualizerType",kind==="bars"?"bars":"wave");set("waveMode",kind)
     set("barsOrigin",origin);set("frequencyProfile",profiles[scene%6]);set("mirroredStereo",scene%2===0)
     set("spectrumOpacity",scene%2?.67:.23);set("edgeInset",scene%3*2)
     set("topLeftRadius",scene%3*12);set("topRightRadius",scene%4*8)
     set("bottomLeftRadius",scene%4*8);set("bottomRightRadius",scene%3*12)
     set("points",Array.from({length:64+(scene%3)*32},(_,i)=>(i*59+scene*31)%1000))
     parity("GPU "+scene);wait(35)
     grab(baseline,Quickshell.env("PROFILE_OUTPUT")+"/baseline-"+scene+".png")
     grab(candidate,Quickshell.env("PROFILE_OUTPUT")+"/candidate-"+scene+".png")
     scene++
    }
   }
   console.info("BAR_PROFILE_PASS",root.checks,"exact checks",cases,"cases",root.captures,"graphics captures")
  }catch(e){console.error("BAR_PROFILE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Component.onCompleted:Quickshell.watchFiles=false
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''.replace('GPU', 'true' if args.gpu else 'false')
    (folder / 'shell.qml').write_text(body)
    destination = args.output or folder / 'captures'
    destination.mkdir(exist_ok=True)

    def execute(env):
        env.update(PROFILE_OUTPUT=str(destination), QSG_RHI_BACKEND='opengl')
        result = run_qs(folder, env, timeout=100)
        if args.output:
            (args.output / 'native.log').write_text(result.stdout)
        failures = ['BAR_PROFILE_FAIL', 'TypeError:', 'ReferenceError:',
                    'Binding loop', 'Unable to assign', 'Failed to load configuration']
        if result.returncode or 'BAR_PROFILE_PASS' not in result.stdout or any(t in result.stdout for t in failures):
            print(result.stdout)
            raise SystemExit(1)
        for line in result.stdout.splitlines():
            if 'BAR_PROFILE_TIMINGS ' in line:
                times = json.loads(line.split('BAR_PROFILE_TIMINGS ', 1)[1])
                if args.output:
                    (args.output / 'timings.json').write_text(json.dumps(times, indent=2)+'\n')
            if 'BAR_PROFILE_PASS' in line:
                print(line)
        if args.gpu:
            from PIL import Image
            for i in range(16):
                with Image.open(destination / f'baseline-{i}.png') as a, Image.open(destination / f'candidate-{i}.png') as b:
                    assert a.size == b.size and a.convert('RGBA').tobytes() == b.convert('RGBA').tobytes(), f'RGBA mismatch scene {i}'
            print('BAR_PROFILE_GPU_PASS 16 strict RGBA scene pairs')

    if args.gpu:
        with private_wayland(folder, capture_focus=True) as env:
            if env is None:
                print('SKIP: GPU oracle needs local private Niri')
                raise SystemExit(0)
            execute(env)
    else:
        env = dict(os.environ, QT_QPA_PLATFORM='offscreen')
        for key in ['QS_CONFIG_NAME', 'QS_CONFIG_PATH', 'QS_MANIFEST']:
            env.pop(key, None)
        for kind in ['config', 'state', 'cache', 'data']:
            env[f'XDG_{kind.upper()}_HOME'] = str(folder / kind)
        execute(env)
