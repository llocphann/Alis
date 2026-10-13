#!/usr/bin/env python3
"""Real Region cohort lifetime/coverage, publication cost and four-edge masks."""
import os
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='alis-region-cohort-') as name:
    folder = Path(name)
    for entry in ['modules', 'services', 'GlobalStates.qml', 'qmldir', 'assets', 'scripts', 'defaults', 'translations']:
        (folder / entry).symlink_to(ROOT / entry)
    (folder / 'shell.qml').write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.abyss
ShellRoot {
 id:root;property int checks:0;property int publications:0;property int regionObjects:0
 property int cohorts:0;property bool shown:false;property real depth:180
 property real span:280;property real along:180
 Component.onCompleted:Quickshell.watchFiles=false
 AbyssSurfaceController {id:controller;outputWidth:scene.width;outputHeight:scene.height}
 FloatingWindow {
  visible:true;implicitWidth:1000;implicitHeight:740;color:"#111820"
  Item {
   id:scene;anchors.fill:parent
   Repeater {
    id:hosts;model:["top","right","bottom","left"]
    delegate:AbyssBodyHost {
     id:host;required property string modelData
     identity:modelData;edge:modelData;controller:controller;anchors.fill:parent
     open:root.shown;span:root.span;depth:root.depth;along:root.along
     includeEdgeConnection:true;animatePresentation:false;animatePlacementChanges:false
     embeddedItem:Item {}
     onConnectionRegionsChanged:{root.publications++;root.regionObjects+=connectionRegions.length}
    }
   }
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(v,label){root.checks++;if(!v)throw new Error(label)}
  function coherent(host){
   const desired=host.connectionRects,actual=host.connectionRegions
   check(actual.length===desired.length,"native region cohort incomplete "+host.edge)
   check(host.connectionRegionState.objects.length===desired.length,"host retains removed Region wrappers")
   for(let i=0;i<desired.length;i++){
    check(actual[i]===host.connectionRegionState.objects[i],"Region identity/order changed")
    for(const key of ["x","y","width","height"])check(actual[i][key]===desired[i][key],"mask coverage changed "+key)
   }
  }
  function verifyAll(){for(let i=0;i<4;i++)coherent(hosts.itemAt(i))}
  function run(){try{
   tryCompare(Config,"ready",true,5000)
   Config.setNestedValue("performance.reduceAnimations",true)
   wait(200);verifyAll()
   for(const insets of [{left:16,top:16,right:16,bottom:16},{left:0,top:0,right:0,bottom:0},{left:0,top:16,right:0,bottom:16}]){
    controller.edgeInsets=insets
    controller.cornerWidthInsets=insets
    controller.roundZeroCorners={top:true,right:true,bottom:true,left:true}
    wait(0);verifyAll()
   for(let cycle=0;cycle<32;cycle++){
    root.depth=80+(cycle%5)*22;root.span=230+(cycle%4)*17;root.along=110+(cycle%3)*26
    const before=root.publications
    root.shown=true;verifyAll();wait(0);verifyAll()
    check(root.publications-before===4,"opening published partial masks: "+(root.publications-before))
    root.cohorts+=4
    const identities=Array.from({length:4},(_,i)=>hosts.itemAt(i).connectionRegions.slice())
    const stable=root.publications
    root.along+=3;wait(0);verifyAll()
    const changed=identities.filter((list,i)=>list.length!==hosts.itemAt(i).connectionRects.length).length
    check(root.publications-stable===changed,"tangent motion published partial or unchanged cohorts")
    for(let i=0;i<4;i++)if(identities[i].length===hosts.itemAt(i).connectionRects.length)
     for(let k=0;k<identities[i].length;k++)check(identities[i][k]===hosts.itemAt(i).connectionRegions[k],"stable strip count replaced Region")
    // Physical strip extent changes create/remove one synchronous cohort.
    root.depth+=17;wait(0);verifyAll()
    root.shown=false;verifyAll();wait(0);verifyAll()
    check(root.publications-stable-changed<=8,"resize/close published intermediate cohorts")
    root.cohorts+=4
   }
   }
   console.info("CONNECTION_REGION_PASS",root.checks,"coverage/lifetime checks",root.publications,"complete publications",root.regionObjects,"published Regions",root.cohorts,"open/close cohorts")
  }catch(e){console.error("CONNECTION_REGION_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
''')
    with private_wayland(folder) as env:
        if env is None:
            print('SKIP: Region validation requires local private Niri')
            raise SystemExit(0)
        result = run_qs(folder, env, timeout=45)
        destination = os.environ.get('ALIS_CONNECTION_REGION_LOG')
        if destination:
            Path(destination).write_text(result.stdout)
        bad = ['CONNECTION_REGION_FAIL', 'TypeError:', 'ReferenceError:', 'Binding loop', 'Failed to load configuration']
        if result.returncode or 'CONNECTION_REGION_PASS' not in result.stdout or any(t in result.stdout for t in bad):
            print(result.stdout)
            raise SystemExit(1)
        for line in result.stdout.splitlines():
            if 'CONNECTION_REGION_PASS' in line:
                print(line)
