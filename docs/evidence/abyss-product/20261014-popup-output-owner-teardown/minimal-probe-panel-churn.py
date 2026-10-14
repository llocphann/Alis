from pathlib import Path
import tempfile,subprocess,sys,json,shutil
source=Path(sys.argv[1]);label=sys.argv[2];root=Path.cwd();out=root/'.git/maintainer-validation/20261014-perimeter-teardown';sys.path.insert(0,str(source/'scripts'));from native_test_session import private_wayland,run_qs
with tempfile.TemporaryDirectory(prefix='alis-perimeter-teardown-') as name:
 f=Path(name)
 for entry in['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(f/entry).symlink_to(source/entry)
 q=r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
ShellRoot {
 id:root;property int cycles:0
 Component.onCompleted:Quickshell.watchFiles=false
 Loader {id:critical;active:Config.ready&&Config.options.panelFamily==="abyss";source:"modules/abyss/critical/ShellAbyssCriticalPanels.qml"}
 TestCase {
  id:test;when:false;optional:true
  function run(){try{
   tryCompare(Config,"ready",true,5000);GlobalStates.deferredPanelsReady=true
   GlobalStates.abyssColdPerimeterRecreatePending=false
   for(let i=0;i<3;i++){
    Config.setNestedValue("panelFamily","abyss")
    tryVerify(()=>critical.item && findChild(critical.item,"abyssPerimeterLoader")?.item?.nativeInputFramesReady,12000)
    Config.setNestedValue("enabledPanels",[])
    Config.setNestedValue("enabledPanels",["abyssDock","extra-package"])
    Config.setNestedValue("enabledPanels",[])
    Config.setNestedValue("panelFamily","waffle");wait(200)
    if(critical.item!==null)throw new Error("family switch retained critical host")
    root.cycles++
   }
   console.info("PERIMETER_TEARDOWN_DIAGNOSTIC_PASS",root.cycles)
  }catch(e){console.error("PERIMETER_TEARDOWN_DIAGNOSTIC_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:150;running:true;onTriggered:test.run()}
}
'''
 (out/'probe-shell.qml').write_text(q);(f/'shell.qml').write_text(q)
 with private_wayland(f) as env:
  cfg=f/'config/illogical-impulse';cfg.mkdir(parents=True);x=json.loads((source/'defaults/config.json').read_text());x['panelFamily']='abyss';x['abyss']['companion']['enabled']=False;x['bar']['weather']['enable']=False;x['performance']['reduceAnimations']=True;x['enabledPanels']=[];x['panelStyleVersion']=1;x['knownPanels']=['abyssPerimeter','abyssDock'];x['visitedPanelFamilies']=['abyss','waffle'];(cfg/'config.json').write_text(json.dumps(x));p=run_qs(f,env,55)
 (out/(label+'-raw.log')).write_text(p.stdout)
 errors=[line for line in p.stdout.splitlines()if 'TypeError:'in line or 'ReferenceError:'in line]
 receipt={'source_path':str(source),'exit':p.returncode,'cycles_marker':'PERIMETER_TEARDOWN_DIAGNOSTIC_PASS'in p.stdout,'runtime_errors':errors,'scope':'actual critical host/family removal three times, isolated config, weather network and Companion disabled; private no-focus; no owner restart'};(out/(label+'-receipt.json')).write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt));print(p.stdout[-1100:])
