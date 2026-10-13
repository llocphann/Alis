#!/usr/bin/env python3
"""Local GPU field contacts: off-state exact RGBA, moving curves and native masks."""
import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path)
parser.add_argument('--light', action='store_true')
parser.add_argument('--scale', type=float, default=1.0)
args = parser.parse_args()
temporary_output = tempfile.TemporaryDirectory(prefix='alis-contact-images-') if args.output is None else None
if temporary_output:
    args.output = Path(temporary_output.name)
args.output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='alis-physical-contact-render-') as name:
    folder = Path(name)
    for entry in ['modules', 'services', 'GlobalStates.qml', 'qmldir', 'assets', 'scripts', 'defaults', 'translations']:
        (folder / entry).symlink_to(ROOT / entry)
    original = folder / 'original'
    original.mkdir()
    for source, target in [('AbyssField.qml', 'OriginalField.qml'), ('AbyssField.frag.qsb', 'AbyssField.frag.qsb'), ('AbyssGeometry.js', 'AbyssGeometry.js')]:
        data = subprocess.check_output(['git', 'show', '180b9682e:modules/abyss/looks/'+source], cwd=ROOT)
        if source.endswith('.qml'):
            data = data.replace(b'import qs.services', b'import qs.services\nimport qs.modules.abyss.looks')
        (original / target).write_bytes(data)
    (folder / 'shell.qml').write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.abyss.looks
import "original"
import "modules/abyss/looks/AbyssGeometry.js" as Geometry
ShellRoot {
 id:root;property bool before:false;property int checks:0;property int captures:0
 property var records:[];property var insets:({left:0,top:0,right:0,bottom:0})
 property var choices:({});property string edge:"top"
 property var cases:[]
 Component.onCompleted:Quickshell.watchFiles=false
 FloatingWindow {
  visible:true;implicitWidth:1000;implicitHeight:740;color:"#111820"
  Item {
   id:scene;width:850;height:480
   Loader {id:field;anchors.fill:parent;sourceComponent:root.before?legacy:current}
  }
 }
 Component {id:legacy;OriginalField {records:root.records;edgeInsets:root.insets;roundZeroCorners:root.choices}}
 Component {id:current;AbyssField {records:root.records;edgeInsets:root.insets;roundZeroCorners:root.choices}}
 TestCase {
  id:test;when:false;optional:true
  function check(v,label){root.checks++;if(!v)throw new Error(label)}
  function grab(label){tryVerify(()=>field.item?.ready,5000);wait(35);let done=false;check(field.item.grabToImage(result=>{check(result.saveToFile(Quickshell.env("CONTACT_OUTPUT")+"/"+label+".png"),"save field");done=true;root.captures++}),"field refused capture");tryVerify(()=>done,5000)}
  function body(edge,start,span,depth,radius){
   const rect=edge==="top"?{x:start,y:-50,width:span,height:depth+50}:edge==="bottom"?{x:start,y:480-depth,width:span,height:depth+50}:edge==="left"?{x:-50,y:start,width:depth+50,height:span}:{x:850-depth,y:start,width:depth+50,height:span}
   return {edge:edge,surface:rect,radius:radius}
  }
  function pair(name){root.before=true;grab(name+"-before");root.before=false;grab(name+"-after")}
  function run(){try{
   tryCompare(Config,"ready",true,5000)
   Config.setNestedValues({"performance.reduceAnimations":true,"abyss.effects.blur.enabled":false,"abyss.content.blurRadius":0,"abyss.effects.refraction.enabled":false})
   if(Quickshell.env("CONTACT_LIGHT")==="1"){
    Appearance.m3colors.darkmode=false
    Appearance.m3colors.m3surface="#faf3e8"
    Appearance.m3colors.m3surfaceContainer="#eee4d9"
    Appearance.m3colors.m3primary="#285f71"
   }
   for(const mode of ["zero","mixed","regular"]){
    root.insets=mode==="zero"?{left:0,top:0,right:0,bottom:0}:mode==="mixed"?{left:0,top:16,right:0,bottom:16}:{left:16,top:16,right:16,bottom:16}
    root.records=[];pair(mode+"-empty")
    root.records=[{surface:{x:260,y:140,width:240,height:160},radius:24}];pair(mode+"-detached")
   }
   root.insets={left:0,top:0,right:0,bottom:0}
   for(const edge of ["top","right","bottom","left"])for(const start of [140,250]){
    root.edge=edge;root.records=[body(edge,start,120,90,30)]
    const name=edge+"-"+start;pair(name)
    root.cases.push({name:name,edge:edge,start:start,span:120,depth:90,radius:30})
    const rows=Geometry.popupShoulders(850,480,root.insets,edge,root.records[0],34,24,30)
    check(rows.some(row=>row.width>0&&row.height>0),"0px physical contact has no hover region")
   }
   root.edge="top";root.records=[body("top",8,120,90,34)];root.choices={top:true};grab("corner-cut")
   root.choices={};root.records=[body("top",250,120,90,0)];pair("zero-radius")
   console.info("PHYSICAL_CONTACT_CASES",JSON.stringify(root.cases))
   console.info("PHYSICAL_CONTACT_RENDER_PASS",root.checks,"checks",root.captures,"GPU captures")
  }catch(e){console.error("PHYSICAL_CONTACT_RENDER_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
''')
    with private_wayland(folder, capture_focus=True) as env:
        if env is None:
            raise SystemExit('Local private Niri is required')
        if args.scale != 1.0:
            outputs = json.loads(subprocess.check_output(['niri', 'msg', '--json', 'outputs'], env=env, text=True))
            subprocess.run(['niri', 'msg', 'output', next(iter(outputs)), 'scale', str(args.scale)], env=env, check=True, capture_output=True)
        env.update(CONTACT_OUTPUT=str(args.output), CONTACT_LIGHT='1' if args.light else '0', QSG_RHI_BACKEND='opengl')
        result = run_qs(folder, env, timeout=55)
        (args.output / 'native.log').write_text(result.stdout)
        bad = ['PHYSICAL_CONTACT_RENDER_FAIL', 'TypeError:', 'ReferenceError:', 'Binding loop', 'Failed to load configuration']
        if result.returncode or 'PHYSICAL_CONTACT_RENDER_PASS' not in result.stdout or any(t in result.stdout for t in bad):
            print(result.stdout)
            raise SystemExit(1)
        from PIL import Image
        for name in ['zero-empty', 'mixed-empty', 'regular-empty', 'zero-detached', 'mixed-detached', 'regular-detached', 'zero-radius']:
            with Image.open(args.output/(name+'-before.png')) as a, Image.open(args.output/(name+'-after.png')) as b:
                assert a.size == b.size and a.convert('RGBA').tobytes() == b.convert('RGBA').tobytes(), 'Off-state RGBA changed: '+name
        for edge in ['top', 'right', 'bottom', 'left']:
            for start in [140,250]:
                with Image.open(args.output/f'{edge}-{start}-before.png') as a, Image.open(args.output/f'{edge}-{start}-after.png') as b:
                    assert a.convert('RGBA').tobytes() != b.convert('RGBA').tobytes(), f'Contact missing: {edge} {start}'
        print('PHYSICAL_CONTACT_RENDER_PASS 7 exact off-state RGBA pairs, 8 moving four-edge contacts and corner clipping')
