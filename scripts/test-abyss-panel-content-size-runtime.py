#!/usr/bin/env python3
"""Four-edge production BodyHost reveal must keep static panel contents full size."""
import json,tempfile,os,re
from pathlib import Path
from native_test_session import private_wayland,run_qs
ROOT=Path(os.environ.get('ALIS_PANEL_CONTENT_SIZE_SOURCE',Path(__file__).resolve().parents[1])).resolve()
source=(ROOT/'modules/abyss/AbyssPerimeter.qml').read_text()
flags=[]
for identity in ['leftPanel','rightPanel','settings','controls','clipboardBody','wallpaperBody']:
 match=re.search(r'\bid:\s*'+re.escape(identity)+r'\b',source)
 assert match is not None,identity
 start=match.start();end=source.index('\n            Abyss',start)
 flags.append([identity,re.search(r'\bstableContentSize:\s*true\b',source[start:end])is not None])
with tempfile.TemporaryDirectory(prefix='alis-sidebar-content-size-')as name:
 folder=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 (folder/'pane.qml').write_text('''import QtQuick
Item {
 property int widthChanges:0;property int heightChanges:0
 onWidthChanged:widthChanges++
 onHeightChanged:heightChanges++
 Rectangle {anchors.fill:parent;color:"#142a38"}
 Text {anchors.centerIn:parent;text:"Full size Sidebar";color:"#8dd4d9";font.pixelSize:17}
}''')
 (folder/'shell.qml').write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.abyss
ShellRoot {
 id:root;property int checks:0;property bool shown:false;property real reveal:1
 property string side:"left";property bool fixedSize:false
 Component.onCompleted:{Quickshell.watchFiles=false;GlobalStates.deferredPanelsReady=true}
 AbyssSurfaceController {id:controller;outputWidth:scene.width;outputHeight:scene.height}
 FloatingWindow {
  visible:true;implicitWidth:1000;implicitHeight:740;color:"#111820"
  Item {id:scene;anchors.fill:parent
   AbyssBodyHost {
    id:body;identity:"sidebarQA";anchors.fill:parent;controller:controller
    edge:root.side;open:root.shown;span:560;depth:410;padding:14
    externalProgress:root.reveal;animatePresentation:false;animatePlacementChanges:false
    stableContentSize:root.fixedSize;source:"../../pane.qml"
   }
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(v,label){root.checks++;if(!v)throw new Error(label)}
  function geometry(){return JSON.stringify({record:body.record,input:body.inputBounds,target:body.targetRecord})}
  function run(){try{
   tryCompare(Config,"ready",true,5000);wait(150)
   for(const [identity,enabled] of FLAGS){
    root.fixedSize=enabled
    for(const edge of ["left","right","top","bottom"]){
     root.side=edge;root.reveal=1;root.shown=true
     tryVerify(()=>body.ready,3000);wait(50)
     const item=body.contentItem.item,full={width:item.width,height:item.height}
     check(full.width>0&&full.height>0,"fixture lacks full-size content")
     for(const progress of [.01,.08,.2,.42,.7,1,.76,.3,.64,1]){
      // Reference the existing immediate geometry with the original option off.
      root.fixedSize=false;root.reveal=progress;wait(0);const original=geometry()
      root.fixedSize=enabled;wait(0)
      check(geometry()===original,"content-sizing option changed surface/input geometry "+edge)
      check(item.width===full.width&&item.height===full.height,"Panel reflows during reveal "+identity+" "+edge+" progress="+progress+" dimensions="+item.width+"x"+item.height+" full="+full.width+"x"+full.height)
      check(body.contentItem.item===item&&body.acceptsInput,"reveal replaced content or lost input")
     }
     // Resize/reflow still changes final dimensions; this is a reveal-only fix.
     body.depth=120;wait(0);check(body.contentItem.item===item,"resize replaced content")
     check(item.width!==full.width||item.height!==full.height,"fixture did not exercise a real size change")
     check(item.width===body.targetRecord.content.width&&item.height===body.targetRecord.content.height,"content ignored a real target resize")
     body.depth=410;wait(0)
     root.shown=false;tryVerify(()=>body.contentItem.item===null,3000)
     check(!body.acceptsInput&&!body.ready,"closed panel retained content/input")
    }
   }
   console.info("PANEL_CONTENT_SIZE_PASS",root.checks,"four Edges, reversal, stable content, unchanged geometry/input, resize and unload")
  }catch(e){console.error("PANEL_CONTENT_SIZE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''.replace('FLAGS',json.dumps(flags)))
 # BodyHost resolves relative to modules/abyss, not the fixture's source file.
 qml=(folder/'shell.qml').read_text().replace('source:"../../pane.qml"','source:'+json.dumps(str(folder/'pane.qml')));(folder/'shell.qml').write_text(qml)
 with private_wayland(folder)as env:
  if env is None:raise SystemExit('Private Niri required')
  cfg=folder/'config/alis';cfg.mkdir(parents=True,exist_ok=True)
  (cfg/'config.json').write_text((ROOT/'defaults/config.json').read_text())
  result=run_qs(folder,env,30)
  log=os.environ.get('ALIS_SIDEBAR_CONTENT_SIZE_LOG')
  if log:Path(log).write_text(result.stdout)
  errors=['PANEL_CONTENT_SIZE_FAIL','ReferenceError:','TypeError:','Binding loop','Failed to load configuration']
  if result.returncode or 'PANEL_CONTENT_SIZE_PASS'not in result.stdout or any(e in result.stdout for e in errors):print(result.stdout);raise SystemExit(1)
  for line in result.stdout.splitlines():
   if 'PANEL_CONTENT_SIZE_PASS'in line:print(line)
