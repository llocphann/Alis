#!/usr/bin/env python3
"""Private native carousel and liquid texture-priming regression."""
from pathlib import Path
import json,os,shutil,tempfile,subprocess
from native_test_session import private_wayland,run_qs
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='alis-wallpaper-carousel-') as name:
 folder=Path(name)
 (folder/"wallpapers").mkdir()
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 for name,color in [('a','#156c9c'),('b','#bb4c8c'),('c','#249b75'),('d','#ac7e22'),('e','#7c59b4')]:
  subprocess.run(['magick','-size','320x180','xc:'+color,str(folder/'wallpapers'/(name+'.png'))],check=True)
 odd=folder/"quoted ' $HOME `false`.png"
 subprocess.run(['magick','-size','64x64','xc:#334455',str(odd)],check=True)
 (folder/'shell.qml').write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.abyss.looks
import qs.modules.bar.weather
import qs.modules.wallpaperLauncher
import qs.services
Window {
 id:root;visible:true;width:980;height:680;color:"#111820"
 Component.onCompleted:Quickshell.watchFiles=false
 property string prefix:"file://"+Quickshell.env("WALLPAPER_FIXTURES")+"/"
 property int starts:0
 property int finishes:0
 WallpaperLauncherContent {id:picker;width:parent.width;height:300;monitorName:"fixture-output";browseFolder:Quickshell.env("WALLPAPER_FIXTURES")}
 AbyssOrbitalWeather {id:orbit;x:650;y:320;width:280;height:230}
 WallpaperCrossfader {
  id:wall;x:80;y:380;width:820;height:260;sourceSize:Qt.size(820,260)
  transitionType:"alisMelt";transitionBaseDuration:350
  onTransitionStarted:root.starts++
  onTransitionFinished:root.finishes++
 }
 ThumbnailImage {id:quoted;visible:false;sourcePath:Quickshell.env("QUOTED_IMAGE");generateThumbnail:true;sourceSize:Qt.size(64,64)}
 Timer {interval:16;repeat:true;running:true;onTriggered:root.contentItem.grabToImage(()=>{},Qt.size(64,36))}
 TestCase {
  id:test;when:false;optional:true
  function check(value,message){if(!value)throw new Error(message)}
  function named(item,name){if(item.objectName===name)return item;for(const child of item.data ?? item.children ?? []){const value=named(child,name);if(value)return value}return null}
  function allImages(item){let result=[];if(item.objectName==="wallpaperCardImage")result.push(item);for(const child of item.data ?? item.children ?? [])result=result.concat(allImages(child));return result}
  function allLabels(item){let result=[];if(item.objectName==="wallpaperCardLabel")result.push(item);for(const child of item.data ?? item.children ?? [])result=result.concat(allLabels(child));return result}
  function runChecks(){try {
   tryCompare(Config,"ready",true,4000)
   Config.setNestedValues({"background.transition.type":"alisMelt","background.transition.enable":true})
   check(!AwwwBackend.enabled,"liquid mode has two wallpaper owners")
   GlobalStates.wallpaperLauncherOpen=true
   tryVerify(()=>picker.count===5,7000)
   check(picker.displayMode==="static" && picker.entries.length===5,"library lost image files")
   const search=named(picker,"wallpaperSearch"),carousel=named(picker,"wallpaperCarousel")
   check(search.placeholderText==="Search wallpapers" && named(picker,"wallpaperSearchIcon").text==="search","search retained the old prefix or malformed glyph")
   const folderAction=named(picker,"wallpaperFolder")
   check(folderAction.description===FileUtils.folderNameForPath(picker.browseFolder)
     && !folderAction.description.includes("/") && picker.browseFolder===Quickshell.env("WALLPAPER_FIXTURES"),
     "wallpaper folder hint exposed its full path or lost directory identity")
   for(const name of ["wallpaperMode","wallpaperFolder","wallpaperRefresh","wallpaperClose"]){
    const button=named(picker,name)
    check(!button.outlined && button.background.border.width===0,"search action still has a decorative border")
   }
   const mode=named(picker,"wallpaperMode"),tip=findChild(mode,"abyssButtonToolTip")
   check(waitForPolish(root,1500),"wallpaper action layout is still pending")
   mouseMove(mode,mode.width/2,mode.height/2)
   tryCompare(mode,"hovered",true,1500,"native pointer did not enter the wallpaper action")
   tryVerify(()=>tip.contentItem.shown,2500,"wallpaper action hover did not show its tooltip");wait(200)
   const surface=findChild(tip.contentItem,"styledToolTipSurface")
   tryVerify(()=>surface.radius>=12,1500)
   check(tip.contentItem.abyss && surface.radius>=12 && surface.color===AbyssStyle.surface,"hover tip did not use the Abyss material")
   root.contentItem.grabToImage(result=>result.saveToFile("/tmp/alis-wallpaper-hover-20261007.png"))
   wait(120);mouseMove(search);tryVerify(()=>!tip.contentItem.shown,2000)
   Weather.data={hourly:[{label:"12:00",temp:"24°",code:0,isNight:false}]}
   tryVerify(()=>findChild(orbit,"abyssWeatherNode")!==null,2000)
   const weather=findChild(orbit,"abyssWeatherNode"),weatherTip=findChild(weather,"abyssButtonToolTip")
   mouseMove(weather,weather.width/2,weather.height/2);wait(800)
   check(!weatherTip.enabled && !weatherTip.internalVisibleCondition && orbit.activeIndex===0,"weather duplicated information in a hover popup or lost selection")
   mouseMove(search)
   search.text="b";tryCompare(picker,"count",1,2000)
   check(picker.selectedPath.endsWith('/b.png'),"search did not select the matching wallpaper")
   search.text="";tryCompare(picker,"count",5,2000);wait(80)
   picker.moveSelection(1);wait(230);check(carousel.currentIndex===1,"carousel navigation lost selection")
   tryVerify(()=>allImages(carousel).length>=5 && allImages(carousel).every(image=>image.status===Image.Ready),7000)
   const labels=allLabels(carousel)
   check(labels.length>=5 && labels.every(label=>picker.entries.some(entry=>entry.name===label.text)
     && !label.text.includes("/") && !label.text.includes("\\\\")),
     "wallpaper cards must show a basename with extension, never a directory or full path")
   tryCompare(quoted,"status",Image.Ready,7000)
   check(FileUtils.trimFileProtocol(named(carousel,"wallpaperCardImage").thumbnailPath).startsWith(Quickshell.env("XDG_CACHE_HOME")),"thumbnail escaped the private cache")
   wait(260)
   root.contentItem.grabToImage(result=>result.saveToFile(Quickshell.env("WALLPAPER_CAPTURE")))
   wall.source=root.prefix+"a.png";tryCompare(wall,"ready",true,3000)
   tryVerify(()=>!wall.transitionBusy,3000)
   const count=root.starts
   wall.source=root.prefix+"b.png"
   tryVerify(()=>wall._transitioning,3000)
   tryVerify(()=>root.starts>count,3000)
   check(!wall.shaderTransitionRequested && !wall._shaderTexturePrimePending && wall._effectiveType==="crossfade",
      "legacy melt retained a shader prime dependency")
   tryVerify(()=>!wall.transitionBusy,3000)
   check(wall.ready,"wallpaper disappeared at transition end")
   wall.source=root.prefix+"a.png";wait(25);wall.source=root.prefix+"c.png"
   tryVerify(()=>!wall.transitionBusy,4000)
   check(wall.ready && String(wall.data.find(c=>c.activeIndex!==undefined)?.displayedSource ?? '').endsWith('/c.png'),"rapid source changes did not coalesce to the final image")
   wall.enableTransitions=false;wall.source=root.prefix+"b.png";wait(80)
   check(!wall._transitioning,"disabled motion still rendered a liquid transition")
   console.info("WALLPAPER_CAROUSEL_PASS native-library search navigation single-owner safe-legacy-melt rapid-switch reduced-motion")
  }catch(e){
   const mode=named(picker,"wallpaperMode"),tip=findChild(mode,"abyssButtonToolTip")
   console.error("WALLPAPER_CAROUSEL_FAIL",e.message,e.stack,JSON.stringify({
    window:[root.width,root.height,root.visible,root.active],
    action:[mode.x,mode.y,mode.width,mode.height,mode.visible,mode.enabled,mode.hovered],
    position:mode.mapToItem(root.contentItem,0,0),
    tooltip:[tip.visible,tip.enabled,tip.parentHoverState,tip.internalVisibleCondition,tip.contentItem.shown]
   }))
  }Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
 with private_wayland(folder) as env:
  if env is None:print('SKIP: wallpaper native test requires private Niri');raise SystemExit(0)
  config=folder/'config/alis';config.mkdir(parents=True,exist_ok=True)
  data=json.loads((ROOT/'defaults/config.json').read_text());data.setdefault('wallpapers',{})['directory']=str(folder/'wallpapers');(config/'config.json').write_text(json.dumps(data))
  env.update(WALLPAPER_FIXTURES=str(folder/"wallpapers"),QUOTED_IMAGE=str(odd),WALLPAPER_CAPTURE='/tmp/alis-wallpaper-carousel-20261007.png',QSG_RHI_BACKEND='opengl',ALIS_DISABLE_LIQUID_SHADER='1')
  result=run_qs(folder,env,timeout=40);output=result.stdout
  if result.returncode or 'WALLPAPER_CAROUSEL_PASS' not in output or any(e in output for e in ['WALLPAPER_CAROUSEL_FAIL','ReferenceError:','TypeError:','Unable to assign','Binding loop','Failed to load configuration']):print(output);raise SystemExit(1)
  for line in output.splitlines():
   if 'WALLPAPER_CAROUSEL_PASS' in line:print(line)
