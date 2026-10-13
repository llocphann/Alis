from pathlib import Path
import tempfile,json,sys,subprocess,os
r=Path.cwd();sys.path.insert(0,str(r/'scripts'))
from native_test_session import private_wayland,run_qs
out=Path('/home/llocphann/Shared_Documents/Obsidian-Vault/10_Projects/Alis/.git/maintainer-validation/20261014-tooltip-15-self-control')
with tempfile.TemporaryDirectory(prefix='alis-tooltip-paired-') as name:
 f=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(f/entry).symlink_to(r/entry)
 baseline='28bf63b93'
 for source,target in [('modules/common/widgets/PopupToolTip.qml','BaselinePopupToolTip.qml'),('modules/common/widgets/StyledToolTip.qml','BaselineStyledToolTip.qml'),('modules/waffle/looks/WPopupToolTip.qml','BaselineWPopupToolTip.qml')]:
  s=subprocess.check_output(['git','show',baseline+':'+source],text=True)
  if target!='BaselinePopupToolTip.qml':s=s.replace('PopupToolTip {','BaselinePopupToolTip {',1)
  (f/target).write_text(s)
 (f/'qmldir').unlink();(f/'qmldir').write_text((r/'qmldir').read_text()+'\nBaselinePopupToolTip 1.0 BaselinePopupToolTip.qml\nBaselineStyledToolTip 1.0 BaselineStyledToolTip.qml\nBaselineWPopupToolTip 1.0 BaselineWPopupToolTip.qml\n')
 (f/'shell.qml').write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
ShellRoot {
 id:root;property int checks:0
 Component.onCompleted:Quickshell.watchFiles=false
 PanelWindow {visible:true;implicitWidth:800;implicitHeight:400;color:"#111820";Button {id:anchor;x:300;y:160;width:180;height:60;text:"Tooltip QA"}}
 Component {id:oldPlain;BaselinePopupToolTip {text:"Longer tooltip QA text for live bindings"}}
 Component {id:newPlain;PopupToolTip {text:"Longer tooltip QA text for live bindings"}}
 Component {id:oldStyled;BaselineStyledToolTip {text:"Longer tooltip QA text for live bindings";font.pixelSize:23;font.family:"DejaVu Sans Mono"}}
 Component {id:newStyled;StyledToolTip {text:"Longer tooltip QA text for live bindings";font.pixelSize:23;font.family:"DejaVu Sans Mono"}}
 Component {id:oldWaffle;BaselineWPopupToolTip {text:"Longer tooltip QA text for live bindings"}}
 Component {id:newWaffle;WPopupToolTip {text:"Longer tooltip QA text for live bindings"}}
 Component {id:oldCustom;BaselinePopupToolTip {text:"Custom tooltip QA";contentItem:StyledToolTipContent {text:"Custom tooltip QA"}}}
 Component {id:newCustom;PopupToolTip {text:"Custom tooltip QA";contentItem:StyledToolTipContent {text:"Custom tooltip QA"}}}
 TestCase {
  id:test;when:false;optional:true
  function check(v,label){root.checks++;if(!v)throw new Error(label)}
  function shown(item){return item.shown!==undefined?item.shown:item.parent!==null&&item.visible}
  function capture(component,filename){
   const tip=component.createObject(anchor,{useParentHover:false,externalHoverState:false,alternativeVisibleCondition:false});wait(80)
   tip.externalHoverState=true;tryVerify(()=>shown(tip.contentItem),2000);wait(Appearance.animation.elementMoveFast.duration+120)
   const image=grabImage(tip.contentItem);image.save("CAPTURE/"+filename+".png")
   tip.externalHoverState=false;wait(80);tip.destroy();wait(30);return image
  }
  function run(){try{
   tryCompare(Config,"ready",true,5000);wait(700)
   for(const dark of [true,false]){
    Appearance.m3colors.darkmode=dark;wait(400)
    for(const pair of [[oldPlain,oldPlain,"plain"],[oldStyled,oldStyled,"styled"],[oldWaffle,oldWaffle,"waffle"],[oldCustom,oldCustom,"custom"]]){
     const name=(dark?"dark-":"light-")+pair[2]
     const before=capture(pair[0],name+"-before"),after=capture(pair[1],name+"-after")
     check(before.width===after.width&&before.height===after.height,"dimensions changed "+name)
     check(before.equals(after),"strict native QImage changed "+name)
    }
   }
   console.info("TOOLTIP_SELF_CONTROL_GPU_PASS",root.checks,"8 exact native QImage pairs")
  }catch(e){console.error("TOOLTIP_SELF_CONTROL_GPU_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {running:true;interval:120;onTriggered:test.run()}
}
'''.replace('CAPTURE',str(out)))
 with private_wayland(f) as env:
  assert env
  env["QT_SCALE_FACTOR"]="1.5"
  cfg=f/'config/illogical-impulse';cfg.mkdir(parents=True,exist_ok=True)
  v=json.loads((r/'defaults/config.json').read_text());v['panelFamily']='abyss';(cfg/'config.json').write_text(json.dumps(v))
  result=run_qs(f,env,40);(out/'native.log').write_text(result.stdout)
  print('exit',result.returncode)
  for line in result.stdout.splitlines():
   if 'TOOLTIP_SELF_CONTROL_GPU' in line:print(line)
  assert result.returncode==0 and 'TOOLTIP_SELF_CONTROL_GPU_PASS' in result.stdout
