#!/usr/bin/env python3
"""Compare cached mass kernels and full wave evolution in Qt's actual JS VM."""
import os
import tempfile
from pathlib import Path
from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-mass-oracle-") as name:
    folder = Path(name)
    (folder / "wave.js").write_bytes((ROOT / "modules/abyss/looks/AbyssWave.js").read_bytes())
    (folder / "memo.js").write_bytes((ROOT / "modules/abyss/looks/AbyssPlacementMemo.js").read_bytes())
    (folder / "shell.qml").write_text(r'''
import QtQuick
import Quickshell
import "wave.js" as Wave
import "memo.js" as Memo
ShellRoot {
 id:root;property int checks:0
 Component.onCompleted:Quickshell.watchFiles=false
 function check(v,label){checks++;if(!v)throw new Error(label)}
 function arrayEqual(a,b,label){check(a.length===b.length,label+" length");for(let i=0;i<a.length;i++)check(Object.is(a[i],b[i]),label+" at "+i)}
 function run(){try{
  for(const count of [128,256])for(const dims of [[1920,1200],[853.5,479.25]]){
   const opts=Wave.parameters({preset:"balanced"}),a=Wave.create(count,dims[0],dims[1],opts),b=Wave.create(count,dims[0],dims[1],opts),cache=new Map()
   for(let frame=0;frame<80;frame++){
    const records=Array.from({length:12},(_,i)=>({edge:["top","right","bottom","left"][i%4],along:(i*27.25+(i===frame%12?frame*.125:0)),span:20+i*17.75,mass:i%5+.25,progress:i%3===0?0:(frame%17)/16}))
    if(frame%11===0)records.reverse()
    if(frame%7===0)records.push(Object.assign({},records[1]))
    Wave.setMass(a,records);Wave.setMassCached(b,records,cache);arrayEqual(a.mass,b.mass,"mass")
    b.mass.fill(2);Wave.setMassCached(b,records,cache);arrayEqual(a.mass,b.mass,"cached snapshot restores exact mass")
    check(cache.size<=records.length,"cache retains old geometry history")
    if(frame%9===0){Wave.impulse(a,"top",frame*11,110,.35,1);Wave.impulse(b,"top",frame*11,110,.35,1)}
    Wave.advance(a,1/120);Wave.advance(b,1/120)
    for(const key of ["displacement","velocity","acceleration"])arrayEqual(a[key],b[key],key)
    Wave.projectCrests(a,true);Wave.projectCrests(b,true);arrayEqual(a.crests,b.crests,"crests");arrayEqual(a.whitewater,b.whitewater,"whitewater")
   }
   Wave.setMassCached(b,[],cache);check(cache.size===0,"empty records retain kernels");arrayEqual(b.mass,Array(count).fill(1),"empty mass")
  }
  const one={},two={};check(one!==two,"host caches collide")
  const p={visible:true,along:12.5,inward:0,span:200,depth:100,content:{x:12.5,y:8,width:200,height:100}}
  check(Memo.stable(one,p)===p,"first placement is cloned")
  for(let i=0;i<100;i++)check(Memo.stable(one,JSON.parse(JSON.stringify(p)))===p,"unchanged placement not stable")
  const changed=Object.assign({},p,{along:13});check(Memo.stable(one,changed)===changed,"changed geometry ignored")
  const signed=Object.assign({},changed,{inward:-0});check(Memo.stable(one,signed)===signed,"signed zero collapsed")
  check(!Memo.equal({a:undefined},{}),"missing vs undefined field collapsed")
  check(!Memo.equal([1,2],{0:1,1:2}),"array and object collapsed")
  check(!Memo.equal({v:Infinity},{v:null}),"nonfinite field collapsed")
  check(Memo.equal({v:NaN},{v:NaN}),"equal NaN is unstable")
  const extra=Object.assign({},p,{borrowedFrom:"notes"});check(Memo.stable(two,extra)===extra,"new allocation metadata ignored")
  check(Object.keys(one).length===1&&Object.keys(two).length===1,"cache retains placement history")
  console.info("ABYSS_MASS_MEMO_QV4_PASS",checks,"exact checks; mass/evolution/crests/cache lifecycle")
 }catch(e){console.error("ABYSS_MASS_MEMO_QV4_FAIL",e.message,e.stack)}Qt.quit()}
 Timer {interval:10;running:true;onTriggered:root.run()}
}
''')
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
    env.pop("QS_CONFIG_NAME", None)
    env.pop("QS_CONFIG_PATH", None)
    result = run_qs(folder, env, timeout=35)
    destination = os.environ.get("ALIS_MASS_ORACLE_LOG")
    if destination:
        Path(destination).write_text(result.stdout)
    errors = ["ABYSS_MASS_MEMO_QV4_FAIL", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign", "Failed to load configuration"]
    if result.returncode or "ABYSS_MASS_MEMO_QV4_PASS" not in result.stdout or any(t in result.stdout for t in errors):
        print(result.stdout)
        raise SystemExit(1)
    for line in result.stdout.splitlines():
        if "ABYSS_MASS_MEMO_QV4_PASS" in line:
            print(line)
