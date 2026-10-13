#!/usr/bin/env python3
"""Exact GPU parity against an unoptimized ordered fold of the current field.

Native OpenGL offscreen readbacks, synthetic data, no desktop focus or user
configuration. This does not replay Companion G0 or qualify installed actors.
"""
from pathlib import Path
import argparse, tempfile, subprocess, os, json, hashlib
from PIL import Image
from native_test_session import run_qs
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--scale',type=float,default=1.0)
parser.add_argument('--light',action='store_true')
parser.add_argument('--output',type=Path)
args=parser.parse_args()
images=tempfile.TemporaryDirectory(prefix='alis-support-images-')if args.output is None else None
out=Path(images.name)if images else args.output
out.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='alis-field-support-')as name:
 folder=Path(name);variants=folder/'variants';variants.mkdir()
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 field=(ROOT/'modules/abyss/looks/AbyssField.qml').read_text().replace('import qs.services','import qs.services\nimport qs.modules.abyss.looks')
 old='readonly property string wallpaperUrl: wantsWallpaper\n        ? WallpaperListener.wallpaperUrlForScreen(root.Window.window?.screen ?? null) : ""'
 assert old in field
 field=field.replace(old,'readonly property string wallpaperUrl:Qt.resolvedUrl("fixture.png")')
 (variants/'OriginalField.qml').write_text(field)
 (variants/'CandidateField.qml').write_text(field.replace('AbyssField.frag.qsb','CandidateField.frag.qsb'))
 (variants/'AbyssGeometry.js').symlink_to(ROOT/'modules/abyss/looks/AbyssGeometry.js')
 # Independent linear fold: preserve current distance/material/wave semantics,
 # remove only the optimization, and keep every one of the40 slots in order.
 shader=(ROOT/'modules/abyss/looks/AbyssField.frag').read_text()
 start=shader.index('    // Conservative lower bound for the box')
 end=shader.index('    return fuse(d,min(roundedBox',start)
 reference=shader[:start]+shader[end:]
 start=reference.index('    vec4 rectangles[40]');end=reference.index('    return d;',start)
 calls=['    d=record(d,p,rect'+str(i)+',radii'+str(i//4)+'.'+'xyzw'[i%4]+',boundPoint,support);'for i in range(40)]
 reference=reference[:start]+'\n'.join(calls)+'\n'+reference[end:]
 ref_file=variants/'ReferenceField.frag';ref_file.write_text(reference)
 qsb='/usr/lib/qt6/bin/qsb'
 subprocess.run([qsb,'--qt6','-o',str(variants/'AbyssField.frag.qsb'),str(ref_file)],check=True,capture_output=True)
 subprocess.run([qsb,'--qt6','-o',str(variants/'RebuiltField.frag.qsb'),str(ROOT/'modules/abyss/looks/AbyssField.frag')],check=True,capture_output=True)
 package=(ROOT/'modules/abyss/looks/AbyssField.frag.qsb').read_bytes()
 assert package==(variants/'RebuiltField.frag.qsb').read_bytes(),'Product shader package is stale'
 (variants/'CandidateField.frag.qsb').write_bytes(package)
 immersion=(ROOT/'modules/abyss/looks/AbyssFieldImmersion.qml').read_text()
 (variants/'OriginalImmersion.qml').write_text(immersion)
 (variants/'CandidateImmersion.qml').write_text(immersion.replace('AbyssField.frag.qsb','CandidateField.frag.qsb'))
 image=Image.new('RGB',(160,100));image.putdata([(x*255//159,y*255//99,(x*7+y*3)%256)for y in range(100)for x in range(160)]);image.save(variants/'fixture.png')
 import math
 image=Image.new('RGBA',(128,1));pixels=[]
 for i in range(128):
  v=round((6+3*math.sin(i*.23))/256*65535);pixels.append((v>>8,v&255,50,255))
 image.putdata(pixels);image.save(folder/'wave.png')
 (folder/'shell.qml').write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.abyss.looks
import "variants"
ShellRoot {
 id:root;property bool before:true;property int pairs:0
 property var records:[];property var insets:({left:16,top:16,right:16,bottom:16})
 property var choices:({});property bool waveOn:false;property bool contactOn:false
 property bool maskMode:false
 property vector4d maskViewport:Qt.vector4d(120,-20,240,180)
 readonly property var sourcePass:field.item?.children.find(c=>c.fragmentShader!==undefined)??null
 Component.onCompleted:Quickshell.watchFiles=false
 Image {id:wave;width:128;height:1;source:"wave.png";visible:false;property bool activeProfile:root.waveOn}
 QtObject {
  id:water;property vector4d contact:root.contactOn?Qt.vector4d(270,12,1,.8):Qt.vector4d(0,0,0,0)
  property vector4d contactNormal:Qt.vector4d(0,1,0,0)
  property vector4d ripple:root.contactOn?Qt.vector4d(270,12,.4,.8):Qt.vector4d(0,0,1,0)
  property vector4d rippleNormal:Qt.vector4d(0,1,1,0)
 }
 FloatingWindow {visible:true;implicitWidth:720;implicitHeight:460;color:"#111820"
  Item {id:scene;width:640;height:360
   Loader {id:field;anchors.fill:parent;sourceComponent:root.before?original:candidate}
   Rectangle {id:sprite;width:240;height:180;gradient:Gradient {GradientStop {position:0;color:"#1ebbd5"}GradientStop {position:1;color:"#d2ef6b"}}}
   Loader {id:mask;active:root.maskMode&&field.item?.ready===true;width:240;height:180;sourceComponent:root.before?originalMask:candidateMask}
  }
 }
 Component {id:original;OriginalField {edgeInsets:root.insets;roundZeroCorners:root.choices;records:root.records;waveTexture:wave;waterLink:water}}
 Component {id:candidate;CandidateField {edgeInsets:root.insets;roundZeroCorners:root.choices;records:root.records;waveTexture:wave;waterLink:water}}
 Component {id:originalMask;OriginalImmersion {sourcePass:root.sourcePass;bodyItem:sprite;bodySourceRect:Qt.rect(0,0,240,180);renderRect:root.maskViewport}}
 Component {id:candidateMask;CandidateImmersion {sourcePass:root.sourcePass;bodyItem:sprite;bodySourceRect:Qt.rect(0,0,240,180);renderRect:root.maskViewport}}
 TestCase {
  id:test;when:false;optional:true
  function grab(label){
   tryVerify(()=>field.item?.ready&&field.item.wallpaperReady,5000);wait(70)
   let done=false
   verify((root.maskMode?mask.item:field.item).grabToImage(result=>{verify(result.saveToFile(Quickshell.env("SUPPORT_OUTPUT")+"/"+label+".png"));done=true}))
   tryVerify(()=>done,5000)
  }
  function body(edge,start,span,depth,radius){
   const surface=edge==="top"?{x:start,y:-50,width:span,height:depth+50}:edge==="bottom"?{x:start,y:360-depth,width:span,height:depth+50}:edge==="left"?{x:-50,y:start,width:depth+50,height:span}:{x:640-depth,y:start,width:depth+50,height:span}
   return {surface:surface,radius:radius}
  }
  function run(){try{
   tryCompare(Config,"ready",true,5000)
   Config.setNestedValues({"performance.reduceAnimations":true,"abyss.effects.blur.enabled":true,"abyss.content.blurRadius":8,"abyss.effects.refraction.enabled":true})
   if(Quickshell.env("SUPPORT_LIGHT")==="1"){
    Appearance.m3colors.darkmode=false;Appearance.m3colors.m3background="#faf3e8";Appearance.m3colors.m3surface="#faf3e8";Appearance.m3colors.m3surfaceContainerLow="#f3eadd";Appearance.m3colors.m3surfaceContainer="#eee4d9";Appearance.m3colors.m3primary="#285f71"
   }
   wait(500)
   for(const edge of ["top","right","bottom","left"])for(const count of [1,4,16,40])for(const progress of [.08,.42,1]){
    root.insets=progress===.08?{left:0,top:0,right:0,bottom:0}:progress===.42?{left:0,top:16,right:0,bottom:16}:{left:16,top:16,right:16,bottom:16}
    root.choices={top:true,right:true,bottom:true,left:true};root.waveOn=progress===1;root.contactOn=count===4
    let records=[]
    for(let i=0;i<count;i++)records.push(body(i<4?edge:["top","right","bottom","left"][i%4],20+(i%4)*70,90+(i%3)*35,(42+(i%5)*22)*progress,[0,12,29,64][i%4]))
    root.records=records
    const name=edge+"-"+count+"-"+progress
    root.before=true;grab(name+"-before");root.before=false;grab(name+"-after");root.pairs++
   }
   root.maskMode=true
   root.insets={left:0,top:0,right:0,bottom:0};root.choices={top:true,right:true,bottom:true,left:true}
   for(const edge of ["top","right","bottom","left"])for(const progress of [.08,.42,1])for(const waves of [false,true]){
    root.waveOn=waves;root.contactOn=waves
    root.maskViewport=edge==="top"?Qt.vector4d(120,-20,240,180):edge==="right"?Qt.vector4d(480,50,240,180):edge==="bottom"?Qt.vector4d(120,260,240,180):Qt.vector4d(-20,50,240,180)
    root.records=[body(edge,140,160,100*progress,29),body(edge,300,100,60*progress,0)]
    const name="mask-"+edge+"-"+progress+"-"+waves
    root.before=true;grab(name+"-before");root.before=false;grab(name+"-after");root.pairs++
   }
   root.maskMode=false
   for(const radius of [-10,40000])for(const surface of [{x:120,y:-50,width:100,height:160},{x:-40000,y:-40000,width:80000,height:80000},{x:40000,y:-50,width:100,height:160}]){
    root.records=[{surface:surface,radius:radius}]
    const name="fallback-"+radius+"-"+surface.x
    root.before=true;grab(name+"-before");root.before=false;grab(name+"-after");root.pairs++
   }
   console.info("FIELD_SUPPORT_CAPTURE_PASS",root.pairs)
  }catch(e){console.error("FIELD_SUPPORT_CAPTURE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
''')
 env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='rhi',QSG_RHI_BACKEND='opengl',QT_SCALE_FACTOR=str(args.scale),QT_NO_XDG_DESKTOP_PORTAL='1')
 for key in ['QS_CONFIG_PATH','QS_CONFIG_NAME','QS_MANIFEST']:env.pop(key,None)
 for key in ['config','state','cache','data']:
  path=folder/key;path.mkdir();env['XDG_'+key.upper()+'_HOME']=str(path)
 cfg=folder/'config/illogical-impulse';cfg.mkdir(parents=True);(cfg/'config.json').write_text((ROOT/'defaults/config.json').read_text())
 env.update(SUPPORT_OUTPUT=str(out),SUPPORT_LIGHT='1'if args.light else'0')
 result=run_qs(folder,env,75);(out/'native.log').write_text(result.stdout)
 errors=['FIELD_SUPPORT_CAPTURE_FAIL','Failed to compile shader','Failed to build graphics pipeline state','ReferenceError:','TypeError:','Binding loop']
 assert result.returncode==0 and 'FIELD_SUPPORT_CAPTURE_PASS' in result.stdout and not any(e in result.stdout for e in errors),result.stdout
 pairs=[]
 for before in sorted(out.glob('*-before.png')):
  after=before.with_name(before.name.replace('-before.png','-after.png'))
  with Image.open(before)as a,Image.open(after)as b:
   assert a.size==b.size and a.convert('RGBA').tobytes()==b.convert('RGBA').tobytes(),'Strict RGBA changed: '+before.name
  pairs.append(before.stem[:-7])
 assert len(pairs)==78,'Incomplete native readback matrix'
 (out/'receipt.json').write_text(json.dumps({'scale':args.scale,'light':args.light,'pairs':pairs,'product_qsb_sha256':hashlib.sha256(package).hexdigest(),'reference_source_sha256':hashlib.sha256(reference.encode()).hexdigest(),'scope':'strict whole RGBA current field versus its ordered unoptimized fold, full pass and synthetic immersion; no installed/owner/G0 acceptance','native_exit':result.returncode},indent=2)+'\n')
 print('FIELD_SUPPORT_GPU_PASS',len(pairs),'exact full/mask RGBA pairs, scale='+str(args.scale),'light='+str(args.light))
