#!/usr/bin/env python3
"""Offline QV4 arithmetic/scratch identity; not QML NOTIFY/render qualification."""
import hashlib,json,re,sys
from pathlib import Path
from PySide6.QtCore import QCoreApplication, qVersion
from PySide6.QtQml import QJSEngine
root=Path(sys.argv[1])
paths=[root/'modules/common/widgets/BarCavaVisualizer.qml',root/'docs/evidence/abyss-product/20261010-hover-checkpoint/unpromoted/bar-cava-candidate.qml']
app=QCoreApplication([]);engine=QJSEngine()
def extract(path):
 s=path.read_text();out=[]
 for name in ['_profileWeight','_profileFactorsFor','_processedSource','_sampleAt','_nextLevelScratch','_rebuildLevels']:
  match=re.search(r'    function '+name+r'\(([^\n]*)\): \w+ \{',s)
  if not match:continue
  start=match.end()-1;depth=1;end=start+1
  while depth:
   if s[end]=='{':depth+=1
   elif s[end]=='}':depth-=1
   end+=1
  args=re.sub(r':\s*(?:int|real|var|string|bool)\b','',match[1])
  out.append('root.'+name+' = function('+args+') '+s[start:end]+';')
 return '\n'.join(out)
functions=[extract(p) for p in paths]
program='''
function createRoot(candidate){
 const root={points:[],active:true,visualizerType:"bars",frequencyProfile:"flat",accentStrength:.7,mirroredStereo:true,
  smoothing:0,normalizationCeiling:1000,width:240,edgeInset:0,pixelsPerBar:12,barSpacing:2,waveStripCap:72,
  _levels:[],_selectedScratch:[],_smoothScratch:[],_levelScratchA:[],_levelScratchB:[],_levelScratchFlip:false,
  _profileCache:{count:-1,profile:"",stereo:false,strength:0,factors:[]},weightCalls:0};
 Object.defineProperty(root,"_innerWidth",{get:()=>Math.max(1,root.width-root.edgeInset*2)});
 Object.defineProperty(root,"_barCount",{get:()=>root.active && root.visualizerType==="bars" ? Math.max(4,Math.floor((root._innerWidth+Math.max(0,root.barSpacing))/Math.max(3,root.pixelsPerBar))) : 0});
 if(candidate){CANDIDATE}else{BASELINE}
 const weight=root._profileWeight;
 root._profileWeight=function(x){root.weightCalls++;return weight(x)};
 return root;
}
const old=createRoot(false),next=createRoot(true);
let cases=0,checks=0;
function check(value,message){checks++;if(!value)throw Error(message)}
function equal(a,b,label){check(a.length===b.length,label+" length");for(let i=0;i<a.length;i++)check(Object.is(a[i],b[i]),label+" at "+i+": "+a[i]+"/"+b[i])}
const counts=[0,1,2,3,8,64,128,256], profiles=["flat","bass","warm","vocal","treble","smile","unknown"];
const strengths=[-.2,0,.7,1.4,NaN], smoothings=[0,2,100];
for(const count of counts)for(const profile of profiles)for(const stereo of [false,true])for(const strength of strengths)for(const smoothing of smoothings)for(const mode of ["bars","wave"]){
 for(const item of [old,next])Object.assign(item,{frequencyProfile:profile,mirroredStereo:stereo,accentStrength:strength,smoothing:smoothing,visualizerType:mode});
 for(let frame=0;frame<3;frame++){
  const points=Array.from({length:count},(_,i)=>((i*179+frame*83)%1800)-300);
  if(count>8){points[2]="70";points[5]=undefined;points[7]=NaN}
  old.points=points.slice();next.points=points.slice();
  const beforeOld=old._levels,beforeNext=next._levels;
  old._rebuildLevels();next._rebuildLevels();cases++;
  equal(old._selectedScratch,next._selectedScratch,"selected");equal(old._smoothScratch,next._smoothScratch,"smooth");equal(old._levels,next._levels,"levels");
  check(old._levelScratchFlip===next._levelScratchFlip,"buffer rotation");
  check((beforeOld===old._levels)===(beforeNext===next._levels),"level identity transition");
  check((old._levels===old._levelScratchA)===(next._levels===next._levelScratchA),"A buffer selection");
  check((old._levels===old._levelScratchB)===(next._levels===next._levelScratchB),"B buffer selection");
 }
}
for(const active of [false,true,false,true]){
 old.active=active;next.active=active;old._rebuildLevels();next._rebuildLevels();equal(old._levels,next._levels,"active cycle");cases++;
}
JSON.stringify({result:"PASS",cases:cases,checks:checks,baselineWeightCalls:old.weightCalls,candidateWeightCalls:next.weightCalls,
 boundary:"Extracted production arithmetic executed by QV4; no real-QML NOTIFY, dependency, shader, frame timing or whole-shell resource claim"});
'''.replace('CANDIDATE',functions[1]).replace('BASELINE',functions[0])
result=engine.evaluate(program,'spectrum-parity.js')
if result.isError():raise SystemExit(result.toString()+' line '+result.property('lineNumber').toString())
receipt=json.loads(result.toString());receipt['sources']={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
receipt['qtVersion']=qVersion()
print(json.dumps(receipt,indent=2))
