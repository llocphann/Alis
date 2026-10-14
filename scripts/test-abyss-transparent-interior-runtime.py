#!/usr/bin/env python3
"""Strict GPU parity for a conservative transparent-interior candidate.

Native OpenGL offscreen readbacks, synthetic data, no desktop focus or user
configuration. This does not replay Companion G0 or qualify installed actors.
"""
from pathlib import Path
import argparse, tempfile, subprocess, os, json, hashlib
from PIL import Image
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"scripts"))
from native_test_session import run_qs
parser=argparse.ArgumentParser()
parser.add_argument('--scale',type=float,default=1.0)
parser.add_argument('--light',action='store_true')
parser.add_argument('--output',type=Path)
parser.add_argument('--width',type=int,default=1920)
parser.add_argument('--height',type=int,default=1080)
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
 # Full pre-culling computation with Qt's original default vertex transform.
 (variants/'OriginalField.qml').write_text(field.replace('        vertexShader: Qt.resolvedUrl("AbyssField.vert.qsb")\n',''))
 (variants/'CandidateField.qml').write_text(field.replace('AbyssField.frag.qsb','CandidateField.frag.qsb'))
 (variants/'AbyssGeometry.js').symlink_to(ROOT/'modules/abyss/looks/AbyssGeometry.js')
 shader=(ROOT/'modules/abyss/looks/AbyssField.frag').read_text()
 start=shader.index('    bool interior=');end=shader.index('    // Derivatives',start)
 reference=shader[:start]+"    vec2 wave=waveProfile(p);\n    vec2 interaction=waterInteraction(p);\n    float d=field(p)-wave.x-interaction.x;\n"+shader[end:]
 reference=reference.replace('layout(location=1) in vec4 clipBounds;\n','')
 ref_file=variants/'ReferenceField.frag';ref_file.write_text(reference)
 qsb='/usr/lib/qt6/bin/qsb'
 subprocess.run([qsb,'--qt6','-o',str(variants/'AbyssField.frag.qsb'),str(ref_file)],check=True,capture_output=True)
 for stage in ['vert','frag']:
  rebuilt=variants/('RebuiltField.'+stage+'.qsb')
  subprocess.run([qsb,'--qt6','-o',str(rebuilt),str(ROOT/('modules/abyss/looks/AbyssField.'+stage))],check=True,capture_output=True)
  assert rebuilt.read_bytes()==(ROOT/('modules/abyss/looks/AbyssField.'+stage+'.qsb')).read_bytes(),'Stale '+stage+' package'
 (variants/'AbyssField.vert.qsb').write_bytes((ROOT/'modules/abyss/looks/AbyssField.vert.qsb').read_bytes())
 package=(ROOT/'modules/abyss/looks/AbyssField.frag.qsb').read_bytes()
 (variants/'CandidateField.frag.qsb').write_bytes(package)
 immersion=(ROOT/'modules/abyss/looks/AbyssFieldImmersion.qml').read_text()
 (variants/'OriginalImmersion.qml').write_text(immersion.replace('    vertexShader:Qt.resolvedUrl("AbyssField.vert.qsb")\n',''))
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
 property bool maskMode:false;property bool liveMode:false;property bool liveResident:false;property bool bounded:true;property real providerCeiling:256
 property vector4d maskViewport:Qt.vector4d(120,-20,240,180)
 readonly property var sourcePass:field.item?.children.find(c=>c.fragmentShader!==undefined)??null
 Component.onCompleted:Quickshell.watchFiles=false
 Image {id:wave;width:128;height:1;source:"wave.png";visible:false;property bool activeProfile:root.waveOn;property real encodedHeightCeiling:root.providerCeiling}
 QtObject {
  id:water;property vector4d contact:root.contactOn?Qt.vector4d(270,12,1,.8):Qt.vector4d(0,0,0,0)
  property vector4d contactNormal:Qt.vector4d(0,1,0,0)
  property vector4d ripple:root.contactOn?Qt.vector4d(270,12,.4,.8):Qt.vector4d(0,0,1,0)
  property vector4d rippleNormal:Qt.vector4d(0,1,1,0)
 }
 FloatingWindow {visible:true;implicitWidth:__WIDTH__+80;implicitHeight:__HEIGHT__+100;color:"#111820"
  Item {id:scene;width:__WIDTH__;height:__HEIGHT__
   Loader {id:field;anchors.fill:parent;active:!root.liveMode;sourceComponent:root.before?original:candidate}
   Loader {id:liveField;anchors.fill:parent;active:root.liveResident;visible:root.liveMode;sourceComponent:candidate}
   Rectangle {id:sprite;width:240;height:180;gradient:Gradient {GradientStop {position:0;color:"#1ebbd5"}GradientStop {position:1;color:"#d2ef6b"}}}
   Loader {id:mask;active:root.maskMode&&field.item?.ready===true;width:240;height:180;sourceComponent:root.before?originalMask:candidateMask}
  }
 }
 Component {id:original;OriginalField {edgeInsets:root.insets;roundZeroCorners:root.choices;records:root.records;waveTexture:wave;waterLink:water}}
 Component {id:candidate;CandidateField {boundInterior:root.bounded;renderScale:__SCALE__;edgeInsets:root.insets;roundZeroCorners:root.choices;records:root.records;waveTexture:wave;waterLink:water}}
 Component {id:originalMask;OriginalImmersion {sourcePass:root.sourcePass;bodyItem:sprite;bodySourceRect:Qt.rect(0,0,240,180);renderRect:root.maskViewport}}
 Component {id:candidateMask;CandidateImmersion {sourcePass:root.sourcePass;bodyItem:sprite;bodySourceRect:Qt.rect(0,0,240,180);renderRect:root.maskViewport}}
 TestCase {
  id:test;when:false;optional:true
  function grab(label){
   const target=root.liveMode?liveField:field
   tryVerify(()=>target.item?.ready&&target.item.wallpaperReady,5000);wait(70)
   let done=false
   verify((root.maskMode?mask.item:target.item).grabToImage(result=>{verify(result.saveToFile(Quickshell.env("SUPPORT_OUTPUT")+"/"+label+".png"));done=true}))
   tryVerify(()=>done,5000)
  }
  function body(edge,start,span,depth,radius){
   const surface=edge==="top"?{x:start,y:-50,width:span,height:depth+50}:edge==="bottom"?{x:start,y:__HEIGHT__-depth,width:span,height:depth+50}:edge==="left"?{x:-50,y:start,width:depth+50,height:span}:{x:__WIDTH__-depth,y:start,width:depth+50,height:span}
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
   root.waveOn=false;root.contactOn=false
   root.insets={left:0,top:48,right:0,bottom:0};root.choices={top:true,right:true,bottom:true,left:true}
   for(const opacity of [0,.01,.5,1])for(const blur of [0,10,24]){
    Config.setNestedValues({"abyss.surface.opacity":opacity,"abyss.content.opacity":opacity,"abyss.effects.blur.radius":blur,"abyss.content.blurRadius":blur,"abyss.quality":"quality","abyss.autoQuality":false})
    root.records=[body("top",140,160,48,29),body("bottom",400,180,80,0),{surface:{x:__WIDTH__/2,y:__HEIGHT__/2,width:120,height:120},radius:12}]
    const name="material-"+opacity+"-"+blur
    root.before=true;grab(name+"-before");root.before=false;grab(name+"-after");root.pairs++
   }
   Config.setNestedValues({"abyss.surface.opacity":.78,"abyss.content.opacity":.78,"abyss.effects.blur.radius":10,"abyss.content.blurRadius":8})
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
   // Keep the candidate QObject alive across geometry, material and provider changes.
   root.liveResident=true;root.liveMode=true;wait(100);const held=liveField.item
   for(let step=0;step<24;step++){
    root.waveOn=step%3===0;root.contactOn=step%4===0;root.providerCeiling=step%5===0?0:256;root.bounded=step%7!==0
    root.insets=step%2?{left:0,top:0,right:0,bottom:0}:{left:16,top:16,right:16,bottom:16}
    root.records=[body(["top","right","bottom","left"][step%4],80+step*13,160,30+step*5,[0,12,29,64][step%4]),{surface:{x:__WIDTH__/2+step*7,y:__HEIGHT__/2,width:90,height:130},radius:step}]
    Config.setNestedValues({"abyss.surface.opacity":[0,.01,.5,1][step%4],"abyss.effects.blur.radius":[0,10,24][step%3],"abyss.perimeter.radius":[12,20,34,64][step%4],"abyss.surface.softness":[4,12,24,48][step%4]})
    const name="live-"+step
    root.liveMode=false;root.before=true;grab(name+"-before")
    root.liveMode=true;grab(name+"-after");root.pairs++
    compare(liveField.item,held)
   }
   console.info("FIELD_SUPPORT_CAPTURE_PASS",root.pairs)
  }catch(e){console.error("FIELD_SUPPORT_CAPTURE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''.replace('__SCALE__',str(args.scale)).replace('__WIDTH__',str(args.width)).replace('__HEIGHT__',str(args.height)))
 env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='rhi',QSG_RHI_BACKEND='opengl',QT_SCALE_FACTOR=str(args.scale),QT_NO_XDG_DESKTOP_PORTAL='1')
 for key in ['QS_CONFIG_PATH','QS_CONFIG_NAME','QS_MANIFEST']:env.pop(key,None)
 for key in ['config','state','cache','data']:
  path=folder/key;path.mkdir();env['XDG_'+key.upper()+'_HOME']=str(path)
 cfg=folder/'config/alis';cfg.mkdir(parents=True);(cfg/'config.json').write_text((ROOT/'defaults/config.json').read_text())
 env.update(SUPPORT_OUTPUT=str(out),SUPPORT_LIGHT='1'if args.light else'0')
 result=run_qs(folder,env,150);(out/'native.log').write_text(result.stdout)
 errors=['FIELD_SUPPORT_CAPTURE_FAIL','Failed to compile shader','Failed to build graphics pipeline state','ReferenceError:','TypeError:','Binding loop']
 assert result.returncode==0 and 'FIELD_SUPPORT_CAPTURE_PASS' in result.stdout and not any(e in result.stdout for e in errors),result.stdout
 with Image.open(out/'top-4-1-after.png')as proof:
  assert sum(a>0 for a in proof.convert('RGBA').getchannel('A').getdata())>10000,'Blank shader result'
 pairs=[]
 for before in sorted(out.glob('*-before.png')):
  after=before.with_name(before.name.replace('-before.png','-after.png'))
  with Image.open(before)as a,Image.open(after)as b:
   assert a.size==b.size and a.convert('RGBA').tobytes()==b.convert('RGBA').tobytes(),'Strict RGBA changed: '+before.name
  pairs.append(before.stem[:-7])
 assert len(pairs)==114,'Incomplete native readback matrix'
 (out/'receipt.json').write_text(json.dumps({'scale':args.scale,'light':args.light,'pairs':pairs,'product_qsb_sha256':hashlib.sha256(package).hexdigest(),'reference_source_sha256':hashlib.sha256(reference.encode()).hexdigest(),'scope':'strict whole RGBA actual product versus full pre-culling computation and original Qt vertex, full pass and synthetic immersion; no installed/owner/G0 acceptance','native_exit':result.returncode,'width':args.width,'height':args.height},indent=2)+'\n')
 print('FIELD_SUPPORT_GPU_PASS',len(pairs),'exact full/mask RGBA pairs, scale='+str(args.scale),'light='+str(args.light))
