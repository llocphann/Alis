#!/usr/bin/env python3
"""Exact old/new arc arithmetic and native QV4 reactive geometry parity."""
import json,re,subprocess,tempfile
from pathlib import Path
from native_test_session import private_wayland,run_qs
ROOT=Path(__file__).resolve().parents[1]
source=(ROOT/'modules/bar/weather/OrbitalWeather.qml').read_text()
new='\n'.join(re.search(r'^    function '+name+r'\(.*?^    }',source,re.M|re.S)[0].replace('): real {',') {') for name in ['hourFromLabel','arcTable','arcAngle','orbitAngleForHour'])
old=(ROOT/'scripts/fixtures/weather-orbit-reference.js').read_text()
program=r'''
const vm=require('node:vm'),assert=require('node:assert/strict');
function context(code,rx,ry,liquid){const c={root:{orbitRadiusX:rx,orbitRadiusY:ry,liquidMode:liquid},builds:0};vm.createContext(c);vm.runInContext(code.replace('const samples = 72','builds++;const samples = 72'),c);c.root={...c.root,hourFromLabel:c.hourFromLabel,arcAngle:c.arcAngle,arcTable:c.arcTable};return c}
let cases=0,maxReduced=0;
const labels=['06:15','06:45','07:15','07:45','08:15','08:45','09:15','09:45','0','6','12','18','23:59','25:90','',null,'bad','-1',undefined,'06:01'];
for(const rx of [.0001,1,53.25,160,1000,-23])for(const ry of [.0001,1,83.75,500,-10])for(const liquid of [false,true])for(let count=0;count<=8;count++)for(let offset=0;offset<labels.length;offset++){
 const before=context(OLD,rx,ry,liquid),after=context(NEW,rx,ry,liquid),tables={};
 for(let i=0;i<count;i++){
  const label=labels[(i+offset)%labels.length],a=before.orbitAngleForHour(label),b=after.orbitAngleForHour(label,tables);
  assert.equal(b,a,'angle bits changed');assert.equal(Math.cos(b)*rx,Math.cos(a)*rx,'node x changed');assert.equal(Math.sin(b)*ry,Math.sin(a)*ry,'node y changed');
  assert.equal(after.orbitAngleForHour(label),a,'uncached public fallback changed');
 }
 // Fallback calls above are separately correct; their tables are outside the binding cache.
 const cached=context(NEW,rx,ry,liquid),cache={};for(let i=0;i<count;i++)cached.orbitAngleForHour(labels[(i+offset)%labels.length],cache);
 assert(cached.builds<=Math.min(4,before.builds));if(liquid)assert.equal(cached.builds,0);
 maxReduced=Math.max(maxReduced,before.builds-cached.builds);cases++;
}
const a=context(OLD,160,80,false),b=context(NEW,160,80,false),table={};for(const label of labels.slice(0,8)){a.orbitAngleForHour(label);b.orbitAngleForHour(label,table)}
assert.equal(a.builds,8);assert.equal(b.builds,1);
console.log('WEATHER_ORBIT_NODE_PASS',cases,'exact angle/node arithmetic; qualifying eight-hour table builds 8 -> 1');
'''
subprocess.run(['node','-e','const OLD='+json.dumps(old)+';const NEW='+json.dumps(new)+';\n'+program],check=True,cwd=ROOT)
with tempfile.TemporaryDirectory(prefix='alis-orbit-qv4-') as name:
 folder=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 (folder/'shell.qml').write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.bar.weather
import "scripts/fixtures/weather-orbit-reference.js" as Legacy
ShellRoot {
 Component.onCompleted:{Quickshell.watchFiles=false;Legacy.bind(reference)}
 QtObject {
  id:reference
  property real orbitRadiusX:orbit.orbitRadiusX
  property real orbitRadiusY:orbit.orbitRadiusY
  property bool liquidMode:orbit.liquidMode
  function hourFromLabel(label){return Legacy.hourFromLabel(label)}
  function arcAngle(start,end,fraction){return Legacy.arcAngle(start,end,fraction)}
 }
 FloatingWindow {visible:true;implicitWidth:1000;implicitHeight:700;color:"#111820"
  OrbitalWeather {id:orbit;width:360;height:230}
 }
 TestCase {
  id:test;when:false;optional:true
  function check(v,m){if(!v)throw new Error(m)}
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000)
   const labels=["06:15","06:45","07:15","07:45","08:15","08:45","09:15","09:45","00:00","12:00","18:00","bad",null,"23:59","25:90","06:01"]
   let cases=0
   for(const family of ["abyss","ii"])for(const liquid of [false,true])for(const size of [[360,230],[480,140],[160,600],[960,600]])for(let count=0;count<=8;count++)for(const offset of [0,8]){
    Config.setNestedValue("panelFamily",family);orbit.liquidMode=liquid;orbit.width=size[0];orbit.height=size[1]
    Weather.data={hourly:Array.from({length:count},(_,i)=>({label:labels[(offset+i)%labels.length],temp:"20",wCode:"113"}))}
    wait(1)
    check(orbit.hourAngles.length===count,"reactive hour count stale")
    for(let i=0;i<count;i++){
     const expected=Legacy.orbitAngleForHour(Weather.data.hourly[i].label)
     check(orbit.hourAngles[i]===expected,"QV4 resize/family/mode angle changed")
     const node=orbit.children.find(c=>c.modelData!==undefined && c.angle!==undefined && c.index===i)
     check(node && node.angle===expected,"real delegate did not follow cached binding")
     check(node.x===orbit.width/2+Math.cos(expected)*orbit.orbitRadiusX-node.width/2,"native node x changed")
     check(node.y===orbit.orbitStageHeight/2+Math.sin(expected)*orbit.orbitRadiusY-node.height/2,"native node y changed")
    }
    cases++
   }
   console.info("WEATHER_ORBIT_QV4_PASS",cases,"reactive count/resize/family/liquid changes retain exact angles")
  }catch(e){console.error("WEATHER_ORBIT_QV4_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
 with private_wayland(folder) as env:
  if env is None:print('SKIP: native orbit parity requires private Niri');raise SystemExit(0)
  cfg=folder/'config/illogical-impulse';cfg.mkdir(parents=True);(cfg/'config.json').write_text((ROOT/'defaults/config.json').read_text());env['QT_QUICK_BACKEND']='software'
  result=run_qs(folder,env,35)
  if result.returncode or 'WEATHER_ORBIT_QV4_PASS' not in result.stdout or any(w in result.stdout for w in ['WEATHER_ORBIT_QV4_FAIL','ReferenceError:','TypeError:','Binding loop','Failed to load configuration']):print(result.stdout);raise SystemExit(1)
  print('WEATHER_ORBIT_QV4_PASS 288 live model/size/family/mode evaluations match frozen baseline exactly')
