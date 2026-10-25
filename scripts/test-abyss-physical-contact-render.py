#!/usr/bin/env python3
"""Local GPU field contacts: off-state exact RGBA, moving curves and native masks."""
import argparse
import json
import math
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
    Appearance.m3colors.m3background="#faf3e8"
    Appearance.m3colors.m3surface="#faf3e8"
    Appearance.m3colors.m3surfaceContainerLow="#f3eadd"
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
    root.edge=edge;root.records=[body(edge,start,120,90,30)];root.choices={}
    pair(edge+"-"+start+"-off")
    root.choices={[edge]:true}
    const name=edge+"-"+start;pair(name)
    root.cases.push({name:name,edge:edge,start:start,span:120,depth:90,radius:30})
    const rows=Geometry.popupShoulders(850,480,root.insets,edge,root.records[0],34,24,30,root.choices,root.insets)
    check(rows.some(row=>row.width>0&&row.height>0),"0px physical contact has no hover region")
   }
   for(const width of [1,10,16,40]){
    root.insets={left:width,top:width,right:width,bottom:width};root.choices={top:true,right:true,bottom:true,left:true}
    root.records=[body("top",140,120,90,30),body("right",250,120,90,30),body("bottom",250,120,90,30),body("left",140,120,90,30)]
    pair("nonzero-"+width)
   }
   root.insets={left:0,top:0,right:0,bottom:0};root.before=false
   // Isolate geometry from the physically new contact's outside shadow.
   Config.setNestedValues({"abyss.surface.opacity":1,"abyss.content.opacity":1,"abyss.effects.shadowStrength":0,"abyss.effects.glow.strength":0,"abyss.effects.surfaceHighlight":0})
   for(const edge of ["top","right","bottom","left"])for(const bodyRadius of [-1,0,12,38,64])for(const curvature of [12,34,64]){
    Config.setNestedValue("abyss.perimeter.radius",curvature)
    const record=body(edge,140,220,48,bodyRadius<0?undefined:bodyRadius)
    root.records=[record];root.choices={}
    const label="thin-"+edge+"-"+bodyRadius+"-"+curvature
    grab(label+"-off");root.choices={[edge]:true};grab(label+"-on")
   }
   Config.setNestedValues({"abyss.surface.opacity":.78,"abyss.content.opacity":-1,"abyss.effects.shadowStrength":.24,"abyss.effects.glow.strength":.08,"abyss.effects.surfaceHighlight":.45})
   for(const edge of ["top","right","bottom","left"])for(const bodyRadius of [-1,12,38]){
    Config.setNestedValue("abyss.perimeter.radius",64)
    root.records=[body(edge,140,220,48,bodyRadius<0?undefined:bodyRadius)]
    const label="shadow-"+edge+"-"+bodyRadius
    root.choices={};grab(label+"-off");root.choices={[edge]:true};grab(label+"-on")
   }
   Config.setNestedValue("abyss.perimeter.radius",34)
   root.insets={left:0,top:0,right:0,bottom:0}
   root.edge="top";root.records=[body("top",8,120,90,34)];root.choices={top:true};grab("corner-cut")
   root.choices={};root.records=[body("top",250,120,90,0)];pair("zero-radius")
   console.info("PHYSICAL_CONTACT_CASES",JSON.stringify(root.cases))
   console.info("PHYSICAL_CONTACT_RENDER_PASS",root.checks,"checks",root.captures,"GPU captures")
  }catch(e){console.error("PHYSICAL_CONTACT_RENDER_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
''')
    with private_wayland(folder, capture_focus=False) as env:
        if env is None:
            raise SystemExit('Local private Niri is required')
        if args.scale != 1.0:
            outputs = json.loads(subprocess.check_output(['niri', 'msg', '--json', 'outputs'], env=env, text=True))
            subprocess.run(['niri', 'msg', 'output', next(iter(outputs)), 'scale', str(args.scale)], env=env, check=True, capture_output=True)
        env.update(CONTACT_OUTPUT=str(args.output), CONTACT_LIGHT='1' if args.light else '0',
                   QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='rhi', QSG_RHI_BACKEND='opengl',
                   QT_SCALE_FACTOR=str(args.scale))
        # The expanded inherited-rounding matrix captures 199 images (versus
        # the previous 55), including fractional-scale readbacks. Keep each
        # frame's existing readiness deadline and all exact pixel assertions.
        result = run_qs(folder, env, timeout=120)
        (args.output / 'native.log').write_text(result.stdout)
        bad = ['PHYSICAL_CONTACT_RENDER_FAIL', 'TypeError:', 'ReferenceError:', 'Binding loop', 'Failed to load configuration']
        if result.returncode or 'PHYSICAL_CONTACT_RENDER_PASS' not in result.stdout or any(t in result.stdout for t in bad):
            print('PHYSICAL_CONTACT_NATIVE_EXIT',result.returncode)
            print(result.stdout)
            raise SystemExit(1)
        from PIL import Image
        def pixels(box, capture):
            # grabToImage uses the output's device pixel ratio. Fixture geometry
            # is always 850x480 logical pixels, including fractional scaling.
            sx,sy=capture.width/850,capture.height/480
            return (math.ceil(box[0]*sx),math.ceil(box[1]*sy),math.floor(box[2]*sx),math.floor(box[3]*sy))
        exact = ['zero-empty', 'mixed-empty', 'regular-empty', 'zero-detached', 'mixed-detached', 'regular-detached', 'zero-radius']
        exact += [f'{edge}-{start}-off' for edge in ['top', 'right', 'bottom', 'left'] for start in [140,250]]
        exact += [f'nonzero-{width}' for width in [1,10,16,40]]
        for name in exact:
            with Image.open(args.output/(name+'-before.png')) as a, Image.open(args.output/(name+'-after.png')) as b:
                assert a.size == b.size and a.convert('RGBA').tobytes() == b.convert('RGBA').tobytes(), 'Off-state RGBA changed: '+name
        for edge in ['top', 'right', 'bottom', 'left']:
            for start in [140,250]:
                with Image.open(args.output/f'{edge}-{start}-before.png') as a, Image.open(args.output/f'{edge}-{start}-after.png') as b:
                    assert a.convert('RGBA').tobytes() != b.convert('RGBA').tobytes(), f'Contact missing: {edge} {start}'
                with Image.open(args.output/f'{edge}-{start}-off-after.png') as off, Image.open(args.output/f'{edge}-{start}-after.png') as on:
                    w,h=850,480
                    for box in [(0,0,32,32),(w-32,0,w,32),(0,h-32,32,h),(w-32,h-32,w,h)]:
                        box=pixels(box,on)
                        assert off.crop(box).convert('RGBA').tobytes()==on.crop(box).convert('RGBA').tobytes(), 'Detached corner geometry/shadow: '+edge

        lower_pairs=0
        for edge in ['top','right','bottom','left']:
            for body_radius in [-1,0,12,38,64]:
                effective=min(29 if body_radius<0 else body_radius,49)
                first=max(0,48-effective)+1
                for curvature in [12,34,64]:
                    label=f'thin-{edge}-{body_radius}-{curvature}'
                    with Image.open(args.output/(label+'-off.png')) as off, Image.open(args.output/(label+'-on.png')) as on:
                        w,h=850,480
                        box=(116,first,384,74) if edge=='top' else (116,h-74,384,h-first) if edge=='bottom' else (first,116,74,384) if edge=='left' else (w-74,116,w-first,384)
                        box=pixels(box,on)
                        assert off.crop(box).convert('RGBA').tobytes()==on.crop(box).convert('RGBA').tobytes(), 'Inherited/custom lower corner geometry changed: '+label
                        lower_pairs+=1
        shadow_pairs=0
        for edge in ['top','right','bottom','left']:
            for body_radius in [-1,12,38]:
                first=48-(29 if body_radius<0 else body_radius)+2
                label=f'shadow-{edge}-{body_radius}'
                with Image.open(args.output/(label+'-off.png')) as off, Image.open(args.output/(label+'-on.png')) as on:
                    w,h=850,480
                    # The new upper contact may cast shadow into its surrounding
                    # space. The near-body lower corner retains its own SDF.
                    box=(128,first,372,74) if edge=='top' else (128,h-74,372,h-first) if edge=='bottom' else (first,128,74,372) if edge=='left' else (w-74,128,w-first,372)
                    box=pixels(box,on)
                    assert off.crop(box).convert('RGBA').tobytes()==on.crop(box).convert('RGBA').tobytes(), 'Lower body shadow changed: '+label
                    shadow_pairs+=1

        print(f'PHYSICAL_CONTACT_RENDER_PASS {len(exact)} exact disabled/nonzero RGBA pairs, 8 moving four-edge enabled contacts, corner clipping, {lower_pairs} inherited/custom lower-corner silhouette pairs and {shadow_pairs} near-body shadow pairs')
