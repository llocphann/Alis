#!/usr/bin/env python3
"""Reproduce native touchpad phase, modified-input and pager gates in private Niri.

ALIS_UTILITIES_SOURCE selects the production source under test. The guarded
fixture comes from this repository (or ALIS_UTILITIES_FIXTURE_SOURCE). Qt 6
Quick/Qml development headers, moc and g++ build a disposable input adapter;
no plugin or application is installed. Keep native runs serialized.
"""
from pathlib import Path
import importlib.util,json,os,shlex,subprocess,sys,tempfile
ROOT=Path(os.environ.get('ALIS_UTILITIES_FIXTURE_SOURCE',Path(__file__).resolve().parents[4])).resolve()
sys.path.insert(0,str(ROOT/'scripts'))
spec=importlib.util.spec_from_file_location('utilities_fixture',ROOT/'scripts/test-utilities-compact-runtime.py')
fixture=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixture)
QML=r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import Quickshell.Io
import AlisNativeInput 1.0
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss.content
ShellRoot {
 id:root;property int checks:0;property int frames:0;property var measurements:[]
 property real sceneWidth:560;property real sceneHeight:360
 Component.onCompleted:Quickshell.watchFiles=false
 FileView {id:report;path:Quickshell.env("ALIS_UTILITIES_REPORT")}
 WheelDriver {id:input}
 FloatingWindow {visible:true;implicitWidth:900;implicitHeight:640;color:"#111820"
  Item {id:scene;width:root.sceneWidth;height:root.sceneHeight
   AbyssUtilitiesPopup {id:utility;anchors.fill:parent}
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(ok,label){root.checks++;if(!ok)throw Error(label)}
  function find(item,predicate){if(predicate(item))return item;for(const child of item.children??[]){const found=find(child,predicate);if(found)return found}return null}
  function frame(){let done=false;check(scene.grabToImage(image=>{done=true;root.frames++}),"native frame refused");tryVerify(()=>done,4000);check(done,"native frame timed out")}
  function phaseSwipe(from,to){
   utility.currentPage=from;wait(350);frame()
   const dx=to>from?-8:8,x=utility.width*.65,y=utility.height*.75
   input.wheel(utility,x,y,0,0,0,0,Qt.ScrollBegin)
   for(let i=0;i<8;i++){input.wheel(utility,x,y,dx,1,dx*3,3,Qt.ScrollUpdate);wait(15)}
   for(let i=0;i<4;i++){input.wheel(utility,x,y,dx,0,0,0,Qt.ScrollMomentum);wait(20)}
   input.wheel(utility,x,y,0,0,0,0,Qt.ScrollEnd)
   wait(600);frame()
   root.measurements.push({kind:"pixel-phase-touchpad",from:from,to:utility.currentPage,width:utility.width,height:utility.height})
   check(utility.currentPage===to,"pixel-phase gesture "+from+" to "+to+" got "+utility.currentPage)
  }
  function run(){let error=null;try{
   tryCompare(Config,"ready",true,6000)
   Config.setNestedValues({"panelFamily":"abyss","performance.reduceAnimations":true,"interactions.scrolling.fasterTouchpadScroll":true})
   CompositorService.isNiri=true;wait(1300)
   NiriService.outputs={A:{logical:{x:0,y:0,width:1920,height:1080,scale:1,transform:"Normal"},make:"Fixture",model:"Synthetic"}}
   for(const [w,h,font] of [[560,360,1],[420,300,1],[320,240,1.5]]){
    root.sceneWidth=w;root.sceneHeight=h;Config.setNestedValue("appearance.typography.sizeScale",font)
    for(const [from,to] of [[0,1],[1,2],[2,3],[3,2],[2,1],[1,0]])phaseSwipe(from,to)
    utility.currentPage=2;wait(350);frame()
    const audio=findChild(utility,"utilitiesAudioScroll");audio.contentY=0
    input.wheel(utility,utility.width*.95,utility.height*.75,0,0,0,0,Qt.ScrollBegin)
    for(let i=0;i<8;i++){input.wheel(utility,utility.width*.95,utility.height*.75,1,-8,3,-24,Qt.ScrollUpdate);wait(15)}
    input.wheel(utility,utility.width*.95,utility.height*.75,0,0,0,0,Qt.ScrollEnd)
    wait(600);frame()
    check(utility.currentPage===2,"vertical touchpad gesture changed tabs")
    if(audio.contentHeight>audio.height)check(audio.contentY>0,"vertical touchpad scroll swallowed")
    check(!audio.moving,"Sound scroll did not settle after touchpad end")
   }
   root.sceneWidth=560;root.sceneHeight=360;Config.setNestedValue("appearance.typography.sizeScale",1)
   utility.currentPage=0;wait(350);frame()
   const canvas=findChild(utility,"monitorArrangementCanvas"),editor=find(utility,item=>item.monitorLayoutSnapshot!==undefined)
   check(!!canvas&&!!editor,"monitor page ready for modified-input controls")
   editor.syncMonitorLayoutSnapshot(true);canvas.fitOutputs();wait(100)
   const saved=JSON.stringify(editor.monitorLayoutSnapshot),zoom=canvas.zoomFactor
   mouseWheel(canvas,canvas.width*.7,canvas.height*.7,0,120,Qt.NoButton,Qt.ControlModifier,25);wait(200);frame()
   check(canvas.zoomFactor>zoom&&utility.currentPage===0,"Ctrl+wheel zoom retained")
   const beforePan=JSON.stringify(canvas.panOffset)
   mouseWheel(canvas,canvas.width*.7,canvas.height*.7,120,0,Qt.NoButton,Qt.ShiftModifier,25);wait(200);frame()
   check(JSON.stringify(canvas.panOffset)!==beforePan&&utility.currentPage===0,"Shift+horizontal wheel pans viewport")
   canvas.fitOutputs();wait(100)
   mouseDrag(canvas,canvas.width*.7,canvas.height*.7,40,-20,Qt.MiddleButton,Qt.NoModifier,20);wait(200);frame()
   check((canvas.panOffset.x!==0||canvas.panOffset.y!==0)&&utility.currentPage===0,"middle drag pans viewport")
   check(JSON.stringify(editor.monitorLayoutSnapshot)===saved&&!editor.monitorLayoutBusy,"modified view controls submitted output positions")
   const dots=findChild(utility,"utilitiesPageIndicators")
   const controls=dots.children.filter(child=>child.index!==undefined)
   check(controls.length===4,"four page indicator hit targets")
   for(let page=0;page<4;page++){mouseClick(controls[page]);wait(350);frame();check(utility.currentPage===page,"page indicator click "+page)}
   utility.forceActiveFocus();keyClick(Qt.Key_Left);wait(350);check(utility.currentPage===2,"Left key navigation")
   keyClick(Qt.Key_Right);wait(350);check(utility.currentPage===3,"Right key navigation")
   controls[1].forceActiveFocus();keyClick(Qt.Key_Space);wait(350);check(utility.currentPage===1,"Space page activation")
  }catch(e){error=String(e);console.error("UTILITIES_COMPACT_FAIL",error)}
  report.setText(JSON.stringify({checks:root.checks,frames:root.frames,measurements:root.measurements,error:error}))
  if(!error)console.info("UTILITIES_COMPACT_PASS",root.checks,root.frames)
  finish.start()
  }
  Component.onCompleted:Qt.callLater(run)
 }
 Timer {id:finish;interval:120;onTriggered:Qt.quit()}
}
'''

def main():
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix='alis-wheel-input-') as name:
        root=Path(name);folder=root/'AlisNativeInput';folder.mkdir()
        file=folder/'wheelinput.cpp';file.write_text(Path(__file__).with_name('wheelinput.cpp').read_text())
        (folder/'qmldir').write_text('module AlisNativeInput\nplugin nativeinput\nclassname NativeInputPlugin\n')
        flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','Qt6Quick','Qt6Qml'],text=True))
        commands=[['/usr/lib/qt6/moc',str(file),'-o',str(folder/'wheelinput.moc')]+[v for v in flags if v.startswith(('-I','-D'))],['g++','-shared','-fPIC','-O2',str(file),'-o',str(folder/'libnativeinput.so')]+flags]
        build=[]
        for argv in commands:
            result=subprocess.run(argv,capture_output=True,text=True,timeout=30)
            build.append({'argv':argv,'actual_exit':result.returncode,'diagnostic':result.stderr})
            if result.returncode:
                print(result.stderr);return 1
        if fixture.EVIDENCE:
            fixture.EVIDENCE.mkdir(parents=True,exist_ok=True)
            (fixture.EVIDENCE/'adapter-build.json').write_text(json.dumps(build,indent=2)+'\n')
        os.environ['QML_IMPORT_PATH']=str(root)
        fixture.QML=QML
        return fixture.main()

if __name__=='__main__':
    raise SystemExit(main())
