#!/usr/bin/env python3
"""Actual shared task tabs: theme/reflow, images, keys, disabled and dynamic models."""
import json, os, re, subprocess, tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs
ROOT = Path(__file__).resolve().parents[1]
QML = r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
Window {
 id:root;visible:true;width:920;height:650;color:Appearance.colors.colLayer0Base
 property int checks:0
 property int captures:0
 property int selections:0
 property int escapes:0
 Component.onCompleted: Quickshell.watchFiles=false
 Item {
  id:scene;anchors.fill:parent
  Keys.onEscapePressed:root.escapes++
  SettingsTaskNavigator {
   id:nav;x:20;y:20;width:840;showIntro:false
   onSelected:value=>{currentValue=value;root.selections++}
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(ok,message){root.checks++;if(!ok)throw new Error(message)}
  function find(item,name){if(item.objectName===name)return item;for(const child of item.children ?? []){const result=find(child,name);if(result)return result}return null}
  function buttons(array){return array.children.filter(item=>item.hasOwnProperty("modelData") && item.hasOwnProperty("toggled"))}
  function capture(name){
   const previous=root.captures
   check(scene.grabToImage(result=>{result.saveToFile(Quickshell.env("TASK_CAPTURE_DIR")+"/"+name+".png");root.captures++}),"capture request refused")
   tryVerify(()=>root.captures>previous,2500)
  }
  function theme(light){
   Object.assign(Appearance.m3colors,light
    ? {darkmode:false,m3background:"#f7f4f7",m3surface:"#faf7fa",m3surfaceContainerLow:"#f2eff2",m3surfaceContainer:"#ebe8ed",m3onSurface:"#1b1b20",m3onSurfaceVariant:"#49464e",m3primary:"#555ba4",m3onPrimary:"#ffffff",m3primaryContainer:"#e1e0ff",m3onPrimaryContainer:"#171852"}
    : {darkmode:true,m3background:"#15141b",m3surface:"#17161d",m3surfaceContainerLow:"#201f27",m3surfaceContainer:"#282731",m3onSurface:"#e8e0eb",m3onSurfaceVariant:"#ccc4d0",m3primary:"#bdc1ff",m3onPrimary:"#242960",m3primaryContainer:"#3c417a",m3onPrimaryContainer:"#e1e0ff"})
  }
  function run(){try{
   tryCompare(Config,"ready",true,4000)
   Config.setNestedValues({"panelFamily":"abyss","performance.reduceAnimations":true,"abyss.content.opacity":.8})
   const families=[
    ["Displays","Input","Layout","Animations","Rules"],
    ["Audio","Power","Fan Control","Locale","Input","Safety"],
    ["Outputs","ii surfaces","Desktop widgets","Popups"],
    ["Colors","Type","Motion","Advanced"],
    ["Overview","Behavior","Rendering","AI"],
    ["Obsidian","Calendar","Applications"],
    ["Waves","Spectrum","Interaction","A very long integration subsection label that must fit"]
   ]
   const icons=["monitor","tune","dashboard","animation","rule","security"]
   for(const light of [false,true]){
    theme(light)
    for(const scale of [1,1.25]){
     Config.setNestedValue("appearance.typography.sizeScale",scale)
     for(const width of [240,430,840]){
      nav.width=width
      for(let family=0;family<families.length;family++){
       nav.options=families[family].map((label,index)=>({displayName:label,icon:icons[index%icons.length],value:"v"+index}))
       nav.currentValue="v0";wait(45)
       const array=find(nav,"settingsTaskOptions"),rail=find(nav,"settingsTaskRail"),items=buttons(array)
       check(rail.visible && nav.abyssTaskStyle,"Abyss rail is absent")
       check(items.length===nav.options.length,"task model lost an option")
       check(items.filter(item=>item.toggled).length===1,"selection changed")
       for(const button of items){
        check(button.abyssTaskNavigation && !button.waveFace && button.waveFaceItem===null,"task tab spawned a separate liquid face")
        check(button.x>=-.01 && button.x+button.width<=array.width+.05,"tab escapes a narrow row")
        check(button.y+button.height<=array.implicitHeight+.05,"tab escapes its implicit height")
        check(button.height>=SettingsMaterialPreset.taskTabHeight-.05,"task hit target is too small")
        check(button.buttonText===button.modelData.displayName,"label changed")
       }
       check(ColorUtils.contrastRatio(SettingsMaterialPreset.taskTabInk,SettingsMaterialPreset.taskRailBase)>=4.49,"unselected ink contrast")
       check(ColorUtils.contrastRatio(SettingsMaterialPreset.taskTabSelectedInk,SettingsMaterialPreset.taskTabSelectedBase)>=4.49,"selected ink contrast")
       capture((light?"light":"dark")+"-s"+scale+"-w"+width+"-family"+family)
      }
     }
    }
   }
   Config.setNestedValue("appearance.typography.sizeScale",1)
   nav.width=600;nav.options=[{displayName:"First",value:"first"},{displayName:"Disabled",value:"disabled",enabled:false},{displayName:"Last",value:"last"}];nav.currentValue="first";wait(70)
   const array=find(nav,"settingsTaskOptions"),items=buttons(array)
   items[0].forceActiveFocus(Qt.TabFocusReason);wait(20)
   check(items[0].visualFocus && items[0].selectionOutlineWidth===1,"keyboard focus ring is missing")
   keyClick(Qt.Key_Right);check(nav.currentValue==="last" && items[2].activeFocus,"Right did not skip disabled tab")
   keyClick(Qt.Key_Left);check(nav.currentValue==="first" && items[0].activeFocus,"Left route/focus")
   keyClick(Qt.Key_End);check(nav.currentValue==="last","End route")
   keyClick(Qt.Key_Home);check(nav.currentValue==="first","Home route")
   const count=root.selections;keyClick(Qt.Key_Return);check(root.selections===count+1,"Enter did not activate")
   keyClick(Qt.Key_Tab);check(items[2].activeFocus,"Tab did not skip disabled option")
   keyClick(Qt.Key_Escape);check(root.escapes===1,"Escape did not propagate to page")
   const beforeDisabled=root.selections;mouseClick(items[1],items[1].width/2,items[1].height/2);check(root.selections===beforeDisabled,"disabled option activated")
   Config.setNestedValue("performance.reduceAnimations",false);wait(70)
   const beforeWidth=items[0].width;mouseMove(items[0],items[0].width/2,items[0].height/2);wait(60);mouseMove(scene,880,600);wait(60)
   check(items[0].width===beforeWidth && !items[0].waveFace,"hover reversal changed hit geometry/face")
   nav.options=[{displayName:"Replacement",value:"replacement"}];wait(50)
   check(buttons(array).length===1 && nav.currentValue==="first","dynamic model rewrote stored selection")
   mouseClick(buttons(array)[0],20,20);check(nav.currentValue==="replacement","dynamic option not operable")
   Config.setNestedValue("panelFamily","waffle");wait(80)
   check(!find(nav,"settingsTaskRail").visible && !buttons(array)[0].abyssTaskNavigation,"Waffle inherited Abyss style")
   check(!buttons(array)[0].waveFace,"Waffle gained a liquid face")
   Config.setNestedValue("panelFamily","abyss");wait(80)
   check(find(nav,"settingsTaskRail").visible && buttons(array)[0].toggled,"family switch lost selected value")
   Config.setNestedValue("abyss.content.opacity",0);wait(50)
   check(SettingsMaterialPreset.taskRailColor.a===0 && SettingsMaterialPreset.taskTabSelectedColor.a===0,"zero opacity not respected")
   check(buttons(array)[0].enabled,"zero alpha disabled input")
   console.info("SETTINGS_TASK_TABS_NATIVE_PASS",JSON.stringify({checks:root.checks,captures:root.captures,dpr:root.screen.devicePixelRatio}))
  }catch(e){console.error("SETTINGS_TASK_TABS_NATIVE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''
records=[]
for dpr in ['1','1.25']:
 with tempfile.TemporaryDirectory(prefix='alis-settings-task-tabs-') as name:
  folder=Path(name)
  for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
  (folder/'shell.qml').write_text(QML)
  with private_wayland(folder) as env:
   if env is None:print('SKIP: native task tabs require private Niri');raise SystemExit(0)
   config=folder/'config/illogical-impulse';config.mkdir(parents=True,exist_ok=True)
   value=json.loads((ROOT/'defaults/config.json').read_text());value['panelFamily']='abyss';(config/'config.json').write_text(json.dumps(value))
   evidence=os.environ.get('ALIS_SETTINGS_TASK_EVIDENCE','')
   capture_dir=Path(evidence)/('dpr'+dpr) if evidence else folder/'captures';capture_dir.mkdir(parents=True,exist_ok=True)
   env.update(QT_QUICK_BACKEND='software',QT_SCALE_FACTOR=dpr,TASK_CAPTURE_DIR=str(capture_dir))
   result=run_qs(folder,env,timeout=55);output=result.stdout
   if evidence:(Path(evidence)/('dpr'+dpr+'.log')).write_text(output)
   marker=re.search(r'SETTINGS_TASK_TABS_NATIVE_PASS (\{.+\})',output)
   if result.returncode or not marker or any(x in output for x in ['SETTINGS_TASK_TABS_NATIVE_FAIL','ReferenceError:','TypeError:','Unable to assign','Binding loop','Failed to load configuration']):print(output);raise SystemExit(1)
   row=json.loads(marker.group(1));row['exit_code']=result.returncode;records.append(row)
   assert len(list(capture_dir.glob('*.png')))==row['captures']==84,'missing native captures'
   print('PASS native task tabs '+json.dumps(row))
if os.environ.get('ALIS_SETTINGS_TASK_EVIDENCE'):(Path(os.environ['ALIS_SETTINGS_TASK_EVIDENCE'])/'native-results.json').write_text(json.dumps(records,indent=2)+'\n')
