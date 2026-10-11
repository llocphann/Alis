#!/usr/bin/env python3
"""Ready-slot correctness and bounded transition failure recovery in private Qt."""
import hashlib,json,os,shutil,sys,tempfile
from pathlib import Path
from PIL import Image
ROOT=Path(os.environ.get('ALIS_WALLPAPER_ROOT',str(Path(__file__).resolve().parents[1]))).resolve()
sys.path.insert(0,str(ROOT/'scripts'))
from native_test_session import private_wayland,run_qs
with tempfile.TemporaryDirectory(prefix='alis-wallpaper-recovery-') as temporary:
 folder=Path(temporary)
 for name in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/name).symlink_to(ROOT/name)
 colors={'a':(21,108,156),'b':(187,76,140),'c':(36,155,117)}
 for name,color in colors.items():Image.new('RGB',(320,180),color).save(folder/(name+'.png'))
 (folder/'shell.qml').write_text(r"""
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
Window {
 id:root;visible:true;width:320;height:180;color:'#111820'
 property int checks:0
 property int captures:0
 property bool pauseNext:false
 property bool paused:false
 property string prefix:Quickshell.env('RECOVERY_PREFIX')+'/'
 Component.onCompleted:Quickshell.watchFiles=false
 WallpaperCrossfader {
  id:wall;anchors.fill:parent;source:root.prefix+'a.png';enableTransitions:false;transitionBaseDuration:180
  onTransitionStarted:if(root.pauseNext){root.pauseNext=false;Qt.callLater(()=>{test.animation().pause();root.paused=true})}
 }
 Component{id:detachedWall;WallpaperCrossfader{width:320;height:180;transitionType:'inirMelt';transitionBaseDuration:180}}
 TestCase {
  id:test;when:false;optional:true
  function check(value,message){root.checks++;if(!value)throw new Error(message+' '+JSON.stringify(wall.renderState()))}
  function shown(image){return String(image.renderState().displayedSource).replace(/^file:\/\//,'')}
  function animation(){return wall.data.find(item=>item.property==='progress' && typeof item.restart==='function')}
  function settled(image,source){tryVerify(()=>!image.transitionBusy && image.ready && shown(image)===source,4500);check(!image.transitionBusy && image.ready && shown(image)===source,'switch did not settle to '+source)}
  function capture(image,label){const n=root.captures;check(image.grabToImage(result=>{check(result.saveToFile(Quickshell.env('RECOVERY_CAPTURE')+'/'+label+'.png'),'capture write failed');root.captures++}),'capture rejected');tryVerify(()=>root.captures>n,3000);check(root.captures>n,'capture did not finish')}
  function runChecks(){try{
   tryCompare(Config,'ready',true,4000)
   Config.blockWrites=true
   settled(wall,root.prefix+'a.png');capture(wall,'initial')
   wall.source=root.prefix+'missing.png';wait(350)
   check(wall.ready && shown(wall)===root.prefix+'a.png','OFF failed load replaced the last ready image')
   check(!wall.transitionBusy,'OFF failed load stayed busy');capture(wall,'invalid-off')
   wall.source=root.prefix+'b.png';settled(wall,root.prefix+'b.png');capture(wall,'valid-off')
   // Pause the actual NumberAnimation after a real Ready-slot switch starts.
   // This models absent presentation progress without replacing its slots/API.
   wall.enableTransitions=true;root.paused=false;root.pauseNext=true;wall.source=root.prefix+'a.png'
   tryCompare(root,'paused',true,3000);check(wall._transitioning,'paused transition did not start')
   wall.enableTransitions=false;wall.source=root.prefix+'c.png'
   settled(wall,root.prefix+'c.png');capture(wall,'disabled-mid-flight')
   wall.enableTransitions=true;root.paused=false;root.pauseNext=true;wall.source=root.prefix+'b.png'
   tryCompare(root,'paused',true,3000);check(wall._transitioning,'deadline fixture was not busy')
   settled(wall,root.prefix+'b.png');capture(wall,'stalled-animation')
   wall.source=root.prefix+'a.png';wait(15);wall.source=root.prefix+'b.png';wait(15);wall.source=root.prefix+'c.png'
   settled(wall,root.prefix+'c.png');capture(wall,'rapid-latest')
   wall.source=root.prefix+'c.png';wait(220);check(!wall.transitionBusy,'repeat selection became busy')
   wall.source=root.prefix+'missing.png';wait(350);check(wall.ready && shown(wall)===root.prefix+'c.png','animated failed load replaced the current image');capture(wall,'invalid-animated')
   root.visible=false;wall.source=root.prefix+'a.png';settled(wall,root.prefix+'a.png')
   root.visible=true;wait(80);capture(wall,'hidden-window')
   wall.visible=false;wall.source=root.prefix+'b.png';settled(wall,root.prefix+'b.png')
   wall.visible=true;wait(80);capture(wall,'hidden-item')
   const detached=detachedWall.createObject(null,{source:root.prefix+'a.png'})
   settled(detached,root.prefix+'a.png');detached.source=root.prefix+'c.png';settled(detached,root.prefix+'c.png')
   detached.parent=root.contentItem;wait(80);capture(detached,'detached');detached.destroy()
   wall.transitionType='inirMelt'
   // Force a real unsupported QSB in the private ShaderEffect, leaving
   // production shader binaries unchanged. Software must bypass it too.
   const shader=wall.children.find(item=>item.samplerFromIndex!==undefined)
   check(shader!==undefined,'real ShaderEffect missing')
   shader.fragmentShader=root.prefix+'unavailable.frag.qsb'
   wall.source=root.prefix+'c.png';settled(wall,root.prefix+'c.png');capture(wall,'unavailable-shader')
   console.info('WALLPAPER_RECOVERY_PASS',root.checks,root.captures,JSON.stringify(wall.renderState()))
  }catch(error){console.error('WALLPAPER_RECOVERY_FAIL',error.message,error.stack)}Qt.quit()}
 }
 Timer{interval:100;running:true;onTriggered:test.runChecks()}
}
""")
 # Candidate diagnostics replace only this component inside the private tree.
 candidate=os.environ.get('ALIS_WALLPAPER_COMPONENT')
 if candidate:
  target=folder/'modules';target.unlink();target.mkdir()
  for entry in (ROOT/'modules').iterdir():
   if entry.name!='common':(target/entry.name).symlink_to(entry)
  common=target/'common';common.mkdir()
  for entry in (ROOT/'modules/common').iterdir():
   if entry.name!='widgets':(common/entry.name).symlink_to(entry)
  widgets=common/'widgets';widgets.mkdir()
  for entry in (ROOT/'modules/common/widgets').iterdir():
   if entry.name!='WallpaperCrossfader.qml':(widgets/entry.name).symlink_to(entry)
  shutil.copy2(candidate,widgets/'WallpaperCrossfader.qml')
 with private_wayland(folder) as env:
  if env is None:raise SystemExit('SKIP: private Niri unavailable')
  cfg=folder/'config/illogical-impulse/config.json';cfg.parent.mkdir(parents=True,exist_ok=True)
  data=json.loads((ROOT/'defaults/config.json').read_text());data['abyss']['companion']['enabled']=False
  data['background']['transition']['type']='crossfade';data['performance']['reduceAnimations']=False
  for backend in ['opengl','software']:
   cfg.write_text(json.dumps(data))
   env.update(RECOVERY_PREFIX=str(folder),RECOVERY_CAPTURE=str(folder),QSG_RHI_BACKEND='opengl',INIR_EXPERIMENTAL_MELT='1')
   if backend=='software':env['QT_QUICK_BACKEND']='software'
   else:env.pop('QT_QUICK_BACKEND',None)
   result=run_qs(folder,env,timeout=65)
   log=os.environ.get('ALIS_WALLPAPER_RECOVERY_LOG')
   if log:Path(log+'-'+backend+'.log').write_text(result.stdout+'\nprocessExit='+str(result.returncode)+'\n')
   print(backend,'process exit',result.returncode)
   if result.returncode or 'WALLPAPER_RECOVERY_PASS' not in result.stdout or any(token in result.stdout for token in ['WALLPAPER_RECOVERY_FAIL','TypeError:','ReferenceError:','Binding loop','Failed to load configuration']):print(result.stdout);raise SystemExit(1)
   expected={'initial':'a','invalid-off':'a','valid-off':'b','disabled-mid-flight':'c','stalled-animation':'b','rapid-latest':'c','invalid-animated':'c','hidden-window':'a','hidden-item':'b','detached':'c','unavailable-shader':'c'}
   for label,color in expected.items():
    image=Image.open(folder/(label+'.png')).convert('RGB')
    assert image.getpixel((160,90))==colors[color],(backend,label,image.getpixel((160,90)),colors[color])
   if log:
    capture=Path(log+'-'+backend);capture.mkdir(exist_ok=True)
    for label in expected:shutil.copy2(folder/(label+'.png'),capture/(label+'.png'))
   print('WALLPAPER_RECOVERY_PASS',backend,len(expected),'exact center-pixel checks, Ready preservation, stalled/hidden/disabled/unsupported recovery')
