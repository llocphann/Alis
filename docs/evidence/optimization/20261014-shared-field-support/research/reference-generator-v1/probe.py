from pathlib import Path
import argparse,tempfile,subprocess,sys,json,math,hashlib
from PIL import Image
root=Path.cwd();source=json.loads((root/'.git/maintainer-validation/20261014-field-support-research/loop-v2/source.json').read_text());repo=Path('/tmp/alis-dynamic-exact-55b1fd183')
sys.path.insert(0,str(repo/'scripts'));from native_test_session import private_wayland,run_qs
parser=argparse.ArgumentParser();parser.add_argument('--scale',type=float,default=1);parser.add_argument('--light',action='store_true');args=parser.parse_args()
out=root/'.git/maintainer-validation/20261014-field-support-research/reference-generator-v1'/('light'if args.light else'dark');out=out/str(args.scale);out.mkdir(parents=True)
with tempfile.TemporaryDirectory(prefix='alis-field-support-')as name:
 folder=Path(name);variants=folder/'variants';variants.mkdir()
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(repo/entry)
 field=(repo/'modules/abyss/looks/AbyssField.qml').read_text().replace('import qs.services','import qs.services\nimport qs.modules.abyss.looks')
 old='readonly property string wallpaperUrl: wantsWallpaper\n        ? WallpaperListener.wallpaperUrlForScreen(root.Window.window?.screen ?? null) : ""'
 assert old in field
 field=field.replace(old,'readonly property string wallpaperUrl:Qt.resolvedUrl("fixture.png")')
 (variants/'OriginalField.qml').write_text(field)
 (variants/'CandidateField.qml').write_text(field.replace('AbyssField.frag.qsb','CandidateField.frag.qsb'))
 (variants/'AbyssGeometry.js').symlink_to(repo/'modules/abyss/looks/AbyssGeometry.js')
 (variants/'AbyssField.frag.qsb').write_bytes((repo/'modules/abyss/looks/AbyssField.frag.qsb').read_bytes())
 (variants/'CandidateField.frag.qsb').write_bytes((root/'.git/maintainer-validation/20261014-field-support-research/reference-generator-v1/ReferenceField.frag.qsb').read_bytes())
 image=Image.new('RGB',(160,100));image.putdata([(x*255//159,y*255//99,(x*7+y*3)%256)for y in range(100)for x in range(160)]);image.save(variants/'fixture.png')
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
  }
 }
 Component {id:original;OriginalField {edgeInsets:root.insets;roundZeroCorners:root.choices;records:root.records;waveTexture:wave;waterLink:water}}
 Component {id:candidate;CandidateField {edgeInsets:root.insets;roundZeroCorners:root.choices;records:root.records;waveTexture:wave;waterLink:water}}
 TestCase {
  id:test;when:false;optional:true
  function grab(label){
   tryVerify(()=>field.item?.ready&&field.item.wallpaperReady,5000);wait(70)
   let done=false
   verify(field.item.grabToImage(result=>{verify(result.saveToFile(Quickshell.env("SUPPORT_OUTPUT")+"/"+label+".png"));done=true}))
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
   console.info("FIELD_SUPPORT_CAPTURE_PASS",root.pairs)
  }catch(e){console.error("FIELD_SUPPORT_CAPTURE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
''')
 import os
 env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='rhi',QSG_RHI_BACKEND='opengl',QT_SCALE_FACTOR=str(args.scale))
 for key in ['QS_CONFIG_PATH','QS_CONFIG_NAME','QS_MANIFEST']:env.pop(key,None)
 for key in ['config','state','cache','data']:
  path=folder/key;path.mkdir();env['XDG_'+key.upper()+'_HOME']=str(path)
 if True:
  cfg=folder/'config/illogical-impulse';cfg.mkdir(parents=True,exist_ok=True);(cfg/'config.json').write_text((repo/'defaults/config.json').read_text())
  env.update(SUPPORT_OUTPUT=str(out),SUPPORT_LIGHT='1'if args.light else'0',QSG_RHI_BACKEND='opengl')
  result=run_qs(folder,env,65);(out/'native.log').write_text(result.stdout)
  (out/'receipt.json').write_text(json.dumps({'exit_code':result.returncode,'scale':args.scale,'light':args.light,'original_sha':'55b1fd183876543d51e8d36394c155b5c9c50a35','candidate_source':source,'scope':'research-only native OpenGL offscreen shader paired readback, synthetic wallpaper/wave/contact, no Wayland/owner/performance/Companion G0 claim'},indent=2)+'\n')
  assert result.returncode==0 and 'FIELD_SUPPORT_CAPTURE_PASS' in result.stdout and 'FIELD_SUPPORT_CAPTURE_FAIL' not in result.stdout and 'Failed to build graphics pipeline state' not in result.stdout and 'Failed to compile shader' not in result.stdout,result.stdout
 comparisons=[];failures=[]
 for a in sorted(out.glob('*-before.png')):
  b=a.with_name(a.name.replace('-before.png','-after.png'))
  with Image.open(a)as before,Image.open(b)as after:
   matched=before.size==after.size and before.convert('RGBA').tobytes()==after.convert('RGBA').tobytes()
   record={'pair':a.stem[:-7],'equal':matched,'size':before.size,'before_sha256':hashlib.sha256(a.read_bytes()).hexdigest(),'after_sha256':hashlib.sha256(b.read_bytes()).hexdigest()}
   if not matched:
    ab=before.convert('RGBA').tobytes();bb=after.convert('RGBA').tobytes();record['changed_channels']=sum(x!=y for x,y in zip(ab,bb));failures.append(record)
   comparisons.append(record)
 (out/'strict-pixels.json').write_text(json.dumps({'pairs':comparisons,'failures':failures,'oracle':'whole exact PNG RGBA bytes; no normalization or excluded area'},indent=2)+'\n')
 print('STRICT_RGBA',len(comparisons),'pairs','FAIL',len(failures),failures[:4],flush=True)
 if failures:raise SystemExit(1)
