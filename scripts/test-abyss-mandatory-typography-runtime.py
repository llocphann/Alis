#!/usr/bin/env python3
"""Real mandatory loader, optional off preferences and rotated shared typography."""
import os,json,tempfile
from pathlib import Path
from native_test_session import private_wayland,run_qs
ROOT=Path(__file__).resolve().parents[1]
OUTPUT=Path(os.environ['ALIS_TYPE_CAPTURE_DIR']).resolve() if os.environ.get('ALIS_TYPE_CAPTURE_DIR') else None
with tempfile.TemporaryDirectory(prefix='alis-mandatory-type-') as name:
 folder=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 dest=OUTPUT or folder/'evidence';dest.mkdir(parents=True,exist_ok=True)
 (folder/'shell.qml').write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss.bar
import qs.modules.bar as Shared
import qs.modules.settings
ShellRoot {
 id:root;property int checks:0;property int frames:0;property string edge:"top"
 Component.onCompleted:Quickshell.watchFiles=false
 FileView {id:disk;path:Config.filePath;watchChanges:true;property var snapshot:null;onLoaded:{try{snapshot=JSON.parse(text())}catch(error){snapshot=null}}}
 Loader {id:critical;active:Config.ready&&Config.options.panelFamily==="abyss";source:"modules/abyss/critical/ShellAbyssCriticalPanels.qml"}
 FloatingWindow {
  visible:true;implicitWidth:1000;implicitHeight:720;color:"#111820"
  Item {id:scene;anchors.fill:parent
   AbyssBarModule {id:clock;kind:"clock";attachedEdge:root.edge;outputName:"";width:contentVertical?32*Appearance.fontSizeScale:Math.max(40,naturalSpan);height:contentVertical?Math.max(40,naturalSpan):32*Appearance.fontSizeScale;x:(scene.width-width)/2;y:80}
   Shared.ClockWidget {id:legacy;x:20;y:300;width:implicitWidth;height:implicitHeight}
   Loader {id:settings;active:false;sourceComponent:BarConfig {embedded:true;activeSection:"behavior"} anchors.fill:parent}
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(v,m){root.checks++;if(!v)throw new Error(m)}
  function children(item){let all=[];for(const child of item.children??[])all=all.concat([child],children(child));return all}
  function frame(name){let done=false;check(clock.grabToImage(result=>{if(name)check(result.saveToFile(Quickshell.env("TYPE_EVIDENCE")+"/"+name+".png"),"capture write");root.frames++;done=true}),"render refused");tryVerify(()=>done,5000)}
  function persisted(predicate){disk.reload();wait(60);return predicate(disk.snapshot)}
  function run(){try{
   tryCompare(Config,"ready",true,6000);GlobalStates.deferredPanelsReady=true
   check(Config.options.enabledPanels.includes("abyssPerimeter"),"cold old saved-off host not reconciled")
   check(!Config.options.enabledPanels.includes("abyssPolkit")&&!Config.options.enabledPanels.includes("abyssLock")&&!Config.options.enabledPanels.includes("abyssBackground"),"required reconciliation enabled optional workflows")
   tryVerify(()=>critical.item&&findChild(critical.item,"abyssPerimeterLoader")?.active&&findChild(critical.item,"abyssPerimeterLoader")?.item?.nativeInputFramesReady,12000)
   Config.setNestedValue("enabledPanels",[]);check(JSON.stringify(Config.options.enabledPanels)==='["abyssPerimeter"]',"runtime disabled required host")
   Config.setNestedValue("enabledPanels",["abyssDock","extra-package"]);check(Config.options.enabledPanels.includes("abyssDock")&&Config.options.enabledPanels.includes("extra-package"),"optional enable/package lost")
   Config.setNestedValue("enabledPanels",[]);check(!Config.options.enabledPanels.includes("abyssDock"),"optional disable rejected")
   Config.setNestedValues({"panelFamily":"waffle","enabledPanels":[]});wait(100);check(Config.options.enabledPanels.length===0,"Abyss required set forced on Waffle")
   Config.setNestedValue("panelFamily","abyss");wait(100);check(Config.options.enabledPanels.includes("abyssPerimeter"),"Abyss switch lacks required field")
   if(Quickshell.env("TYPE_ACTION")==="restart"){
    check(Config.options.appearance.typography.mainFont==="DejaVu Sans"&&Config.options.appearance.typography.sizeScale===1.25,"global typography did not survive restart")
   }else{
    Config.setNestedValues({"performance.reduceAnimations":true,"bar.verbose":true,"bar.height":80,"bar.clock.timeFontFamily":"DejaVu Sans Mono","bar.clock.timePixelSize":39,"bar.clock.dateFontFamily":"DejaVu Sans Mono","bar.clock.datePixelSize":31})
    tryVerify(()=>clock.feature!==null,5000);const resident=clock.feature
    for(const font of ["DejaVu Sans","DejaVu Sans Mono"])for(const scale of [.75,1.25,1.75]){
     Config.setNestedValues({"appearance.typography.mainFont":font,"appearance.typography.sizeScale":scale})
     for(const edge of ["top","right","bottom","left"]){
      root.edge=edge;frame(font.replace(/ /g,"-")+"-"+scale+"-"+edge)
      const time=findChild(clock.feature,"sharedClockTime"),date=findChild(clock.feature,"sharedClockDate")
      check(clock.feature===resident,"typography/orientation reloads resident clock")
      check(time.font.family===Appearance.font.family.main&&date.font.family===Appearance.font.family.main,"Abyss ignores global font")
      check(time.font.pixelSize===Appearance.font.pixelSize.large&&date.font.pixelSize===Appearance.font.pixelSize.small,"global size is scaled twice or legacy px wins")
      check(time.text===DateTime.timeDisplay&&date.text===DateTime.date,"time/date format changed")
     }
    }
    check(findChild(legacy,"sharedClockTime").font.family==="DejaVu Sans Mono"&&findChild(legacy,"sharedClockTime").font.pixelSize===78,"legacy consumer typography changed")
    settings.active=true;tryVerify(()=>settings.item!==null,6000);wait(100)
    check(!children(settings.item).some(item=>["Time font","Time size (px)","Date font","Date size (px)"].includes(item.text??item.label)),"Abyss still instantiates separate font controls")
    Config.setNestedValues({"appearance.typography.mainFont":"DejaVu Sans","appearance.typography.sizeScale":1.25});frame("saved-font")
   }
   tryVerify(()=>persisted(data=>data?.enabledPanels?.includes("abyssPerimeter")&&data.appearance.typography.mainFont==="DejaVu Sans"&&data.appearance.typography.sizeScale===1.25),6000)
   check(!disk.snapshot.enabledPanels.includes("abyssPolkit"),"saved optional consent changed")
   console.info("ABYSS_MANDATORY_TYPE_NATIVE_PASS",Quickshell.env("TYPE_ACTION"),root.checks,"checks",root.frames,"frames")
  }catch(e){console.error("ABYSS_MANDATORY_TYPE_NATIVE_FAIL",e.message,e.stack)}critical.active=false;wait(80);Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
''')
 with private_wayland(folder,capture_focus=OUTPUT is not None) as env:
  if env is None:raise SystemExit('SKIP: mandatory/type native requires private Niri')
  cfg=folder/'config/alis';cfg.mkdir(parents=True,exist_ok=True)
  data=json.loads((ROOT/'defaults/config.json').read_text());data['panelFamily']='abyss';data['panelStyleVersion']=1;data['enabledPanels']=[];data['knownPanels']=['abyssPerimeter','abyssDock'];data['visitedPanelFamilies']=['abyss','waffle'];data['abyss']['companion']['enabled']=False
  (cfg/'config.json').write_text(json.dumps(data))
  for action in ['exercise','restart']:
   result=run_qs(folder,dict(env,TYPE_EVIDENCE=str(dest),TYPE_ACTION=action),timeout=90)
   (dest/(action+'.log')).write_text(result.stdout)
   if result.returncode or 'ABYSS_MANDATORY_TYPE_NATIVE_PASS' not in result.stdout or any(t in result.stdout for t in ['ABYSS_MANDATORY_TYPE_NATIVE_FAIL','Binding loop','TypeError:','ReferenceError:','Unable to assign','Failed to load configuration']):print(result.stdout);raise SystemExit(1)
   data=json.loads((cfg/'config.json').read_text());(dest/(action+'-readback.json')).write_text(json.dumps({'enabledPanels':data['enabledPanels'],'typography':data['appearance']['typography'],'legacyClock':data['bar']['clock']},indent=2)+'\n')
   for line in result.stdout.splitlines():
    if 'ABYSS_MANDATORY_TYPE_NATIVE_PASS' in line:print(line)
  focus=folder/'native-test-capture-focus.json'
  if focus.exists():(dest/'focus.json').write_bytes(focus.read_bytes())
