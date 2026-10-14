#!/usr/bin/env python3
"""Native content lifecycle through the explicit external-hover adapter.

Physical-pointer/owner hover acceptance is separate.
"""
from pathlib import Path
import tempfile,json,os
from native_test_session import private_wayland,run_qs
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='alis-tooltip-content-') as name:
 folder=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 (folder/'shell.qml').write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
ShellRoot {
 id:root;property int checks:0;property string captureDir:""
 Component.onCompleted:Quickshell.watchFiles=false
 PanelWindow {
  visible:true;implicitWidth:700;implicitHeight:400;color:"#111820"
  Item {id:scene;anchors.fill:parent
   Button {id:anchor;width:180;height:60;x:160;y:130;text:"Tooltip QA"}
   Button {id:other;width:150;height:55;x:420;y:130;text:"Other"}
  }
 }
 Component {id:plain;PopupToolTip {text:"Default tooltip QA"}}
 Component {id:styled;StyledToolTip {text:"Styled tooltip QA"}}
 Component {id:waffle;WPopupToolTip {text:"Waffle tooltip QA"}}
 Component {id:custom;PopupToolTip {text:"Custom tooltip QA";contentItem:StyledToolTipContent {objectName:"customTooltipQA";text:"Custom tooltip QA"}}}
 TestCase {
  id:test;when:false;optional:true
  function check(v,label){root.checks++;if(!v)throw new Error(label)}
  function shown(item){return item.shown!==undefined?item.shown:item.parent!==null&&item.visible}
  function run(){try{
   tryCompare(Config,"ready",true,5000);wait(120)
   for(const dark of [true,false]){
    Appearance.m3colors.darkmode=dark
    for(const component of [plain,styled,waffle,custom]){
     const tip=component.createObject(anchor,{useParentHover:false,externalHoverState:false,alternativeVisibleCondition:false}),content=tip.contentItem
     check(content!==null,"default/override content unavailable at completed construction")
     check(content.implicitWidth>0&&content.implicitHeight>0,"initial dimensions absent")
     check(content.parent===null,"initial content visual parent changed")
     const textWidth=content.implicitWidth
     tip.text="Longer tooltip QA text for live bindings"
     wait(0)
     if(component!==custom)check(content.implicitWidth>textWidth,"text binding stopped after factory construction")
     if(component===styled){tip.font.pixelSize=23;tip.font.family="DejaVu Sans Mono";wait(0);check(content.font.pixelSize===23&&content.font.family==="DejaVu Sans Mono","font binding lost")}
     tip.externalHoverState=false;wait(60);tip.externalHoverState=true;wait(40);tryVerify(()=>shown(content),2500);wait(Appearance.animation.elementMoveFast.duration+100)
     check(tip.contentItem===content,"show replaced content identity")
     check(content.parent!==null&&content.visible,"presentation did not rehost content")
     check(content.implicitWidth>0&&content.implicitHeight>0,"shown dimensions collapsed")
     if(root.captureDir.length){
      const label=(dark?"dark":"light")+"-"+(component===plain?"plain":component===styled?"styled":component===waffle?"waffle":"custom")
      const surface=findChild(content,"styledToolTipSurface");if(surface)check(surface.opacity===1&&surface.scale===1&&surface.implicitWidth===content.implicitWidth&&surface.implicitHeight===content.implicitHeight,"captured before tooltip animation settled");
      const image=grabImage(content);check(image.width>0&&image.height>0,"empty GPU tooltip capture");image.save(root.captureDir+"/"+label+".png")
     }
     tip.anchorEdges=Edges.Left;tip.anchorGravity=Edges.Left;anchor.x+=15;wait(180)
     check(shown(content)&&tip.contentItem===content,"moving/reanchoring tooltip lost presentation")
     if(component===plain)check(content.position==="left","default position binding stopped")
     tip.externalPressedState=true;tryVerify(()=>!shown(content),1000);tip.externalPressedState=false;wait(80)
     check(!shown(content),"click resurrected tooltip")
     tip.externalHoverState=false;wait(90);tip.externalHoverState=true;tryVerify(()=>shown(content),2000)
     tip.parent=other;wait(90);check(!shown(content),"reparent retained old hover tooltip")
     tip.externalHoverState=false;wait(80);tip.externalHoverState=true;tryVerify(()=>shown(content),2000)
     other.visible=false;wait(90);check(!shown(content),"hidden parent retained tooltip")
     other.visible=true;tip.externalHoverState=false;wait(90)
     check(tip.contentItem===content,"hide/unload changed content identity")
     tip.destroy();wait(0);anchor.x=160
    }
   }
   console.info("TOOLTIP_CONTENT_PASS",root.checks,"default/custom/styled/Waffle, dark/light, dimensions/fonts, moving anchor, press/reparent/hide and identity")
  }catch(e){console.error("TOOLTIP_CONTENT_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {running:true;interval:120;onTriggered:test.run()}
}
''')
 capture=os.environ.get('ALIS_TOOLTIP_CAPTURE_DIR','')
 if capture:
  Path(capture).mkdir(parents=True,exist_ok=True)
  qml=(folder/'shell.qml').read_text().replace('property string captureDir:""', 'property string captureDir:'+json.dumps(capture));(folder/'shell.qml').write_text(qml)
 with private_wayland(folder) as env:
  if env is None:raise SystemExit('Private Niri required')
  cfg=folder/'config/alis';cfg.mkdir(parents=True,exist_ok=True)
  values=json.loads((ROOT/'defaults/config.json').read_text());values['panelFamily']='abyss';values['performance']['reduceAnimations']=False
  (cfg/'config.json').write_text(json.dumps(values))
  result=run_qs(folder,env,35)
  log=os.environ.get('ALIS_TOOLTIP_RUNTIME_LOG')
  if log:Path(log).write_text(result.stdout)
  errors=['TOOLTIP_CONTENT_FAIL','ReferenceError:','TypeError:','Binding loop','Failed to load configuration']
  if result.returncode or 'TOOLTIP_CONTENT_PASS' not in result.stdout or any(e in result.stdout for e in errors):print(result.stdout);raise SystemExit(1)
  for line in result.stdout.splitlines():
   if 'TOOLTIP_CONTENT_PASS' in line:print(line)
