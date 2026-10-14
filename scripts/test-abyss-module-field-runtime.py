#!/usr/bin/env python3
"""Actual GPU local field: inherited/square/rounded backing and corner weld."""
import json,os,shutil,subprocess,tempfile
from pathlib import Path
from PIL import Image,ImageChops
ROOT=Path(__file__).resolve().parents[1]
if not shutil.which('qs') or not (os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY')):
 print('SKIP: module field GPU requires Quickshell/display');raise SystemExit(0)
with tempfile.TemporaryDirectory(prefix='hadalis-module-field-') as name:
 folder=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 cfg=folder/'config/alis';cfg.mkdir(parents=True)
 data=json.loads((ROOT/'defaults/config.json').read_text());data['panelFamily']='abyss'
 (cfg/'config.json').write_text(json.dumps(data))
 (folder/'shell.qml').write_text(r'''
import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.abyss.looks
import "modules/abyss/looks/AbyssLayout.js" as Layout
ShellRoot {
 id:root
 property int step:0
 property int radius:-1
 property bool joined:false
 function capture(name) {scene.grabToImage(result=>{result.saveToFile(Quickshell.env("FIELD_TEST_OUTPUT")+"/"+name+".png");root.step++})}
 FloatingWindow {
  visible:true;implicitWidth:420;implicitHeight:240;color:"#111820"
  Item {id:scene;anchors.fill:parent
   AbyssField {
    id:field;anchors.fill:parent;edgeInsets:({top:0,right:0,bottom:0,left:0})
    property var options:({edgeThicknesses:{top:0},edgeWidthAffectsModules:{top:false},edgeModuleRadii:{top:root.radius}})
    records:Layout.localSurfaces(Layout.geometry(Layout.normalize([{id:"clock",kind:"clock",edge:"top",position:.3,joinCorner:root.joined}],"top"),width,height,options,1),width,height,options,1,64)
   }
  }
 }
 Timer {interval:160;running:true;repeat:true;onTriggered:{
  if(!Config.ready)return
  if(root.step===0){Config.setNestedValues({"abyss.effects.blur.enabled":false,"abyss.content.blurRadius":0,"abyss.effects.refraction.enabled":false});root.step++}
  else if(root.step===1){root.step=2;root.capture("inherit")}
  else if(root.step===3){root.radius=AbyssStyle.neckRadius;root.step++}
  else if(root.step===4){root.step=5;root.capture("explicitDefault")}
  else if(root.step===6){root.radius=0;root.step++}
  else if(root.step===7){root.step=8;root.capture("square")}
  else if(root.step===9){root.radius=64;root.step++}
  else if(root.step===10){root.step=11;root.capture("round")}
  else if(root.step===12){root.joined=true;root.step++}
  else if(root.step===13){root.step=14;root.capture("joined")}
  else if(root.step===15){console.info("MODULE_FIELD_PASS");Qt.quit()}
 }}
}
''')
 env=os.environ.copy()
 for key in ['QS_CONFIG_PATH','QS_CONFIG_NAME','QS_MANIFEST']:env.pop(key,None)
 env.update(QT_QPA_PLATFORM='offscreen',QSG_RHI_BACKEND='opengl',QT_QUICK_BACKEND='rhi',FIELD_TEST_OUTPUT=str(folder),XDG_CONFIG_HOME=str(folder/'config'),XDG_STATE_HOME=str(folder/'state'),XDG_CACHE_HOME=str(folder/'cache'))
 result=subprocess.run(['qs','-p',str(folder),'--no-color'],env=env,text=True,capture_output=True,timeout=18)
 log=result.stdout+result.stderr
 if result.returncode or 'MODULE_FIELD_PASS' not in log or any(w in log for w in ['ReferenceError:','TypeError:','Binding loop','shader preparation failed']):print(log);raise SystemExit(1)
 images={name:Image.open(folder/(name+'.png')).convert('RGB') for name in ['inherit','explicitDefault','square','round','joined']}
 assert ImageChops.difference(images['inherit'],images['explicitDefault']).getbbox() is None,'inherited radius changes default pixels'
 assert ImageChops.difference(images['square'],images['round']).crop((50,35,220,100)).getbbox(),'square and round radii did not affect real shader'
 assert ImageChops.difference(images['round'],images['joined']).crop((0,0,50,50)).getbbox(),'corner weld did not reach output corner'
 print('MODULE_FIELD_PASS real GPU default parity, square/rounded contour and corner fill')
