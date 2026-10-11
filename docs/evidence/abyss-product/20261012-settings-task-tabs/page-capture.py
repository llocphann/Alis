import json,os,sys,tempfile
from pathlib import Path
ROOT=Path(os.environ['CAPTURE_ROOT']);sys.path.insert(0,str(ROOT/'scripts'))
from native_test_session import private_wayland,run_qs
q=r'''
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.settings
Window {
 id:root;visible:true;width:1120;height:820;color:"#111820";property int frames:0
 Component.onCompleted:Quickshell.watchFiles=false
 Item {id:host;anchors.fill:parent}
 SettingsOverlay {id:overlay;embeddedHost:host;settingsOpen:true}
 TestCase {
 id:test;when:false;optional:true
 function run(){try{
 tryCompare(Config,"ready",true,4000);tryCompare(Persistent,"ready",true,4000);tryCompare(overlay,"_navigationInitialized",true,4000)
 Config.setNestedValues({"panelFamily":"abyss","performance.reduceAnimations":true})
 for(const key of ["compositor","system","panels","themes"]){
  if(!SettingsPageRegistry.navigateToKey(key,""))throw new Error("missing route "+key)
  tryVerify(()=>overlay.pageHost?.currentIndex===SettingsPageRegistry.pageIndexForKey(key) && overlay.pageHost?.currentItem?.settingsTaskNavigator!==null,8000)
  wait(350);const count=root.frames
  if(!host.grabToImage(image=>{image.saveToFile(Quickshell.env("CAPTURE_DIR")+"/"+key+".png");root.frames++}))throw new Error("capture refused")
  tryVerify(()=>root.frames>count,3000)
 }
 console.info("SETTINGS_PAGE_CAPTURE_PASS",root.frames)
 }catch(e){console.error("SETTINGS_PAGE_CAPTURE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''
with tempfile.TemporaryDirectory(prefix='alis-task-settings-pages-') as name:
 folder=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 (folder/'shell.qml').write_text(q)
 with private_wayland(folder) as env:
  if not env:raise RuntimeError('private Niri missing')
  config=folder/'config/illogical-impulse';config.mkdir(parents=True,exist_ok=True)
  raw=json.loads((ROOT/'defaults/config.json').read_text());raw['panelFamily']='abyss'
  (config/'config.json').write_text(json.dumps(raw));dest=Path(os.environ['CAPTURE_DIR']);dest.mkdir(parents=True,exist_ok=True)
  env.update(CAPTURE_DIR=str(dest),QT_QUICK_BACKEND='software');result=run_qs(folder,env,timeout=45)
  (dest/'native.log').write_text(result.stdout)
  print(result.stdout[-2500:]);assert result.returncode==0 and 'SETTINGS_PAGE_CAPTURE_PASS 4' in result.stdout
