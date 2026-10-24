#!/usr/bin/env python3
"""UTIL-F01: actual compact QML in private Niri, synthetic output metadata.

No display/audio actions are clicked. A dispatch/PATH guard blocks writes,
PipeWire is disconnected, and all HOME/XDG paths are disposable. Physical
hotplug, output application/rollback and hardware audio are separate gates.
"""
import json
import os
from pathlib import Path
import tempfile
from native_test_session import private_wayland, run_qs

ROOT = Path(os.environ.get('ALIS_UTILITIES_SOURCE', Path(__file__).resolve().parents[1])).resolve()
EVIDENCE = Path(os.environ['ALIS_UTILITIES_EVIDENCE']).resolve() if os.environ.get('ALIS_UTILITIES_EVIDENCE') else None
QML = r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss.content
ShellRoot {
 id:root;property int checks:0;property int frames:0;property var measurements:[]
 property real sceneWidth:560;property real sceneHeight:360
 Component.onCompleted:Quickshell.watchFiles=false
 FileView {id:report;path:Quickshell.env("ALIS_UTILITIES_REPORT")}
 FloatingWindow {
  id:window;visible:true;implicitWidth:900;implicitHeight:640;color:"#111820"
  Item {id:scene;width:root.sceneWidth;height:root.sceneHeight
   AbyssUtilitiesPopup {id:utility;anchors.fill:parent}
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(value,label){root.checks++;if(!value)throw Error(label)}
  function find(item,predicate){if(predicate(item))return item;for(const child of item.children??[]){const found=find(child,predicate);if(found)return found}return null}
  function tiles(item){let result=[];if(item.logicalWidth!==undefined&&item.canvasScale!==undefined)result.push(item);for(const child of item.children??[])result=result.concat(tiles(child));return result}
  function frame(){let done=false;check(scene.grabToImage(image=>{done=true;root.frames++}),"native frame refused");tryVerify(()=>done,4000)}
  function output(x,y,width,height){return {logical:{x:x,y:y,width:width,height:height,scale:1,transform:"Normal"},make:"Fixture",model:"Synthetic"}}
  function run(){let failure=null;try{
   tryCompare(Config,"ready",true,6000)
   Config.setNestedValues({"panelFamily":"abyss","performance.reduceAnimations":true})
   CompositorService.isNiri=true;wait(1300)
   check(utility.implicitWidth===560&&utility.implicitHeight===360,"compact preferred footprint")
   const layouts=[
    {A:output(0,0,1920,1080)},
    {A:output(0,0,1920,1080),B:output(1920,-400,1080,1920)},
    {A:output(-7680,-1000,7680,4320),B:output(0,0,7680,4320),C:output(7680,-1000,7680,4320)},
    {A:output(-500,-8640,2160,3840),B:output(0,-4320,2160,3840),C:output(500,0,2160,3840)}
   ]
   for(const [w,h,fontScale] of [[560,360,1],[420,300,1],[320,240,1.5]]){
    root.sceneWidth=w;root.sceneHeight=h;Config.setNestedValue("appearance.typography.sizeScale",fontScale)
    for(let index=0;index<layouts.length;index++){
     utility.currentPage=0;NiriService.outputs=layouts[index];wait(100)
     const canvas=findChild(utility,"monitorArrangementCanvas")
     check(!!canvas,"production monitor canvas loaded")
     const editor=find(utility,item=>item.monitorLayoutSnapshot!==undefined)
     check(!!editor,"production monitor editor loaded")
     editor.syncMonitorLayoutSnapshot(true);canvas.fitOutputs();frame()
     const saved=JSON.stringify(editor.monitorLayoutSnapshot)
     const actual=tiles(canvas);check(actual.length===Object.keys(layouts[index]).length,"one tile per output identity")
     for(const tile of actual){
      check(tile.x>=-.5&&tile.y>=-.5&&tile.x+tile.width<=canvas.width+.5&&tile.y+tile.height<=canvas.height+.5,"fitted tile clipped "+tile.outputName)
     }
     const zoomIn=findChild(canvas,"monitorViewportAction2"),fit=findChild(canvas,"monitorViewportAction1")
     check(!!zoomIn&&!!fit&&zoomIn.enabled,"viewport controls enabled")
     const before=canvas.canvasScale;mouseClick(zoomIn);wait(25);frame()
     check(canvas.zoomFactor>1&&canvas.canvasScale>before,"native zoom button changes view scale")
     canvas.panTo(100,-80);check(canvas.panOffset.x!==0||canvas.panOffset.y!==0,"pan changes view")
     check(JSON.stringify(editor.monitorLayoutSnapshot)===saved,"zoom/pan changed staged output positions")
     editor.draggingLayoutOutput="fixture-drag";const heldZoom=canvas.zoomFactor;canvas.zoomAt(2,10,10)
     check(canvas.zoomFactor===heldZoom&&!zoomIn.enabled,"viewport frozen during monitor drag")
     editor.draggingLayoutOutput="";mouseClick(fit);wait(25);frame()
     check(canvas.zoomFactor===1&&canvas.panOffset.x===0&&canvas.panOffset.y===0,"fit resets view only")
     check(JSON.stringify(editor.monitorLayoutSnapshot)===saved&&!editor.monitorLayoutBusy,"viewport controls submitted a display action")
     root.measurements.push({width:w,height:h,fontScale:fontScale,outputs:actual.length,canvasWidth:canvas.width,canvasHeight:canvas.height})
    }
    for(const page of [1,2,3,0]){
     utility.currentPage=page;wait(100);frame()
     check(utility.currentFeature!==null,"Utilities page did not load: "+page)
     check(utility.loadedPageCount<=3,"bounded page loader window")
     check(utility.implicitWidth===560&&utility.implicitHeight===360,"page changed footprint")
    }
   }
  }catch(error){failure=String(error);console.error("UTILITIES_COMPACT_FAIL",failure)}
  report.setText(JSON.stringify({checks:root.checks,frames:root.frames,measurements:root.measurements,error:failure}))
  if(!failure)console.info("UTILITIES_COMPACT_PASS",root.checks,root.frames)
  finish.start()
  }
  Component.onCompleted:Qt.callLater(run)
 }
 Timer {id:finish;interval:120;onTriggered:Quickshell.quit()}
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix='alis-utilities-native-') as name:
        folder = Path(name)
        for entry in ['modules', 'services', 'GlobalStates.qml', 'qmldir', 'assets', 'defaults', 'translations']:
            (folder / entry).symlink_to(ROOT / entry)
        scripts = folder / 'scripts'
        scripts.mkdir()
        for entry in (ROOT / 'scripts').iterdir():
            if entry.name != 'native-dispatch':
                (scripts / entry.name).symlink_to(entry)
        guard = '''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
with open(os.environ['ALIS_UTILITIES_GUARD'],'a') as f:print(json.dumps(sys.argv[1:]),file=f)
if sys.argv[1:]==['niri','get-hot-corners']:
 print('{}');sys.exit(0)
sys.exit(77)
'''
        (scripts / 'native-dispatch').write_text(guard)
        (scripts / 'native-dispatch').chmod(0o700)
        binary = folder / 'bin'
        binary.mkdir()
        for command in ['pkill', 'pactl', 'wpctl', 'hyprsunset', 'gammastep']:
            path = binary / command
            path.write_text(guard)
            path.chmod(0o700)
        (folder / 'shell.qml').write_text(QML)
        with private_wayland(folder, capture_focus=True) as env:
            if env is None:
                print('SKIP: private Niri/Wayland unavailable; native Utilities is UNRUN')
                return 0
            report, calls = folder / 'report.json', folder / 'guard.jsonl'
            env.update(HOME=str(folder), PIPEWIRE_REMOTE='alis-utilities-no-pipewire',
                       PATH=str(binary) + ':' + env.get('PATH', ''),
                       ALIS_UTILITIES_REPORT=str(report), ALIS_UTILITIES_GUARD=str(calls))
            result = run_qs(folder, env, timeout=75)
            data = json.loads(report.read_text()) if report.exists() else None
            actions = [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []
            display_writes = [args for args in actions if args[:2] == ['niri', 'persist-layout']]
            if EVIDENCE:
                EVIDENCE.mkdir(parents=True, exist_ok=True)
                (EVIDENCE / 'native.log').write_text(result.stdout)
                (EVIDENCE / 'report.json').write_text(json.dumps(data, indent=2) + '\n')
                (EVIDENCE / 'guard.jsonl').write_text(calls.read_text() if calls.exists() else '')
            errors = ['UTILITIES_COMPACT_FAIL', 'ReferenceError:', 'TypeError:', 'Binding loop', 'is not a type', 'Unable to assign']
            if result.returncode != 0 or display_writes or 'UTILITIES_COMPACT_PASS' not in result.stdout or any(e in result.stdout for e in errors):
                print(result.stdout[-8000:])
                print('actual_native_exit', result.returncode)
                print('unexpected_display_write_attempts', len(display_writes))
                return 1
            print('UTILITIES_COMPACT_NATIVE_PASS', data['checks'], 'checks', data['frames'], 'frames; synthetic outputs, guarded backends')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
