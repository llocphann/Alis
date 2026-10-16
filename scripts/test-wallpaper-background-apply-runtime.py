#!/usr/bin/env python3
"""Real desktop/picker apply, owned color helper, and presented wallpaper pixels."""
import json, subprocess, tempfile
from pathlib import Path
from PIL import Image, ImageChops
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="hadalis-background-apply-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "wallpapers").mkdir()
    for name, color in [("a", "#156c9c"), ("b", "#bb4c8c"), ("c", "#249b75")]:
        subprocess.run(["magick", "-size", "320x180", "xc:" + color,
                        str(folder / "wallpapers" / (name + ".png"))], check=True)
    helper = folder / "scripts/colors/switchwall.sh"
    helper.parent.mkdir(parents=True)
    helper.write_text("#!/usr/bin/env python3\nimport json,os,sys\nwith open(os.environ['APPLY_LOG'],'a') as f:f.write(json.dumps(sys.argv[1:])+'\\n')\n")
    helper.chmod(0o700)
    (folder / "shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.background
import qs.modules.wallpaperLauncher
import qs.modules.abyss
import qs.services
ShellRoot {
 id: root
 Component.onCompleted: Quickshell.watchFiles=false
 property string prefix: Quickshell.env("WALLPAPER_FIXTURES")+"/"
 property int captures: 0
 readonly property var picker:body.contentItem.item
 Component {id: detachedWall; WallpaperCrossfader {width:320;height:180;transitionBaseDuration:100}}
 Background { id: background }
 PanelWindow {
  visible:true;color:"transparent";exclusionMode:ExclusionMode.Ignore
  anchors {top:true;bottom:true;left:true;right:true}
  AbyssBodyHost {
   id:body;identity:"wallpaper";anchors.fill:parent;edge:"bottom";along:width*.05;span:width*.9;depth:320
   open:GlobalStates.wallpaperLauncherOpen
   source:Qt.resolvedUrl("modules/wallpaperLauncher/WallpaperLauncherContent.qml")
   onReadyChanged:if(ready){contentItem.item.embedded=true;contentItem.item.browseFolder=Quickshell.env("WALLPAPER_FIXTURES")}
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(v,m){if(!v)throw new Error(m)}
  function capture(item,name){
   const count=root.captures
   check(item.grabToImage(result=>{result.saveToFile(Quickshell.env("CAPTURE_DIR")+"/"+name+".png");root.captures++}),"capture rejected")
   tryVerify(()=>root.captures>count,3000)
  }
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000)
   GlobalStates.deferredPanelsReady=true
   const variants=qtest_results.findChild(background,"desktopBackgroundOutputs")
   check(variants,"missing real desktop variants")
   tryVerify(()=>variants.instances.length>0,3000)
   const window=variants.instances[0]
   const wall=findChild(window.contentItem,"desktopWallpaper")
   check(wall,"missing desktop crossfader")
   tryCompare(wall,"ready",true,4000)
   tryVerify(()=>!wall.transitionBusy,4000)
   check(wall.visible && wall.opacity===1,"desktop wallpaper is hidden")
   // Parallax is explicitly off in this fixture, even though its workspace
   // and sidebar sub-flags stay true as in a normal saved configuration.
   // Internal Liquid must not keep a zoomed/shifted parallax container.
   const layout=findChild(window.contentItem,"desktopWallpaperContainer")
   check(layout && !window.dynamicParallaxRequested && !layout.useParallax,
       "disabled parallax still owns desktop wallpaper geometry")
   const sw=window.screen.width, sh=window.screen.height
   const neutral=()=>Math.abs(layout.x)<0.5 && Math.abs(layout.y)<0.5
       && Math.abs(layout.width-sw)<0.5 && Math.abs(layout.height-sh)<0.5
   check(neutral(),"disabled parallax displaced desktop wallpaper")
   const oldWidth=window.wallpaperWidth, oldHeight=window.wallpaperHeight
   // Simulate async magick identify replacing the wallpaper dimensions
   // during Liquid; only the decoded crop may change, not container geometry.
   window.wallpaperWidth=1536
   window.wallpaperHeight=2048
   check(neutral(),"new wallpaper metrics shifted desktop with parallax off")
   window.wallpaperWidth=oldWidth
   window.wallpaperHeight=oldHeight
   check(neutral(),"wallpaper metrics restoration moved desktop with parallax off")
   capture(wall,"before")
   check(!AwwwBackend.enabled && !window.externalMainWallpaperActive,"liquid mode has another wallpaper owner")
   GlobalStates.wallpaperLauncherOpen=true
   tryCompare(body,"ready",true,5000)
   tryCompare(picker,"count",3,5000)
   const carousel=findChild(picker,"wallpaperCarousel")
   picker.moveSelection(1)
   tryCompare(picker,"selectedPath",root.prefix+"b.png",2000)
   tryCompare(window,"wallpaperPath",root.prefix+"b.png",3000)
   tryVerify(()=>!wall.transitionBusy,5000)
   mouseClick(carousel.currentItem,carousel.currentItem.width/2,40)
   check(Config.options.background.wallpaperPath===root.prefix+"b.png","picker failed to save wallpaper")
   tryCompare(window,"wallpaperPath",root.prefix+"b.png",1000)
   tryVerify(()=>!wall.transitionBusy,5000)
   tryCompare(body,"ready",false,2500)
   check(String(wall.data.find(item=>item.displayedSource!==undefined).displayedSource).endsWith('/b.png'),"desktop did not finish applying selected image")
   capture(wall,"after")
   Wallpapers.previewWallpaper(root.prefix+"c.png")
   tryVerify(()=>!wall.transitionBusy,5000)
   Wallpapers.cancelWallpaperPreview()
   tryVerify(()=>!wall.transitionBusy,5000)
   capture(wall,"cancel")
   window.visible=false
   Wallpapers.applySelectionTarget(root.prefix+"c.png")
   wait(350)
   window.visible=true
   tryVerify(()=>!wall.transitionBusy,5000)
   check(wall.renderState().displayedSource.endsWith('/c.png'),"hidden desktop apply did not catch up when shown: "+JSON.stringify(wall.renderState()))
   // Hidden/instant swaps cannot emit transitionFinished. Verify that the
   // deferred color helper still runs through its bounded safety deadline.
   tryVerify(()=>Wallpapers._pendingLiquidThemePath==="",3500)
   capture(wall,"shown")
   // A loaded image with no presentation window must never wait forever for
   // frameSwapped. Attach it only after the handoff has finished, then capture
   // the actual incoming pixels rather than trusting a source-path binding.
   const detached=detachedWall.createObject(null,{source:root.prefix+"a.png"})
   tryCompare(detached,"ready",true,3000)
   tryVerify(()=>!detached.transitionBusy,3500)
   detached.source=root.prefix+"b.png"
   tryVerify(()=>!detached.transitionBusy,3500)
   check(detached.renderState().displayedSource.endsWith('/b.png'),"missing presented frames pinned the old image")
   detached.parent=window.contentItem
   wait(120)
   capture(detached,"detached")
   detached.destroy()
   console.info("WALLPAPER_BACKGROUND_PASS actual-picker config path render apply preview cancel")
  }catch(e){console.error("WALLPAPER_BACKGROUND_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
    with private_wayland(folder) as env:
        if env is None:
            print("SKIP: wallpaper background apply requires private Niri"); raise SystemExit(0)
        config = folder / "config/alis"
        config.mkdir(parents=True, exist_ok=True)
        data = json.loads((ROOT / "defaults/config.json").read_text())
        data["panelFamily"] = "abyss"
        data["background"]["wallpaperPath"] = str(folder / "wallpapers/a.png")
        # Exercise an existing user config: legacy melt must remain usable without shader priming.
        data["background"]["transition"]["type"] = "inirMelt"
        data["background"]["parallax"]["enable"] = False
        data["background"]["parallax"]["enableWorkspace"] = True
        data["background"]["parallax"]["enableSidebar"] = True
        data["background"]["pan"] = {"x": 0, "y": 0, "zoom": 1}
        data["background"]["effects"]["enableBlur"] = False
        data["background"]["widgets"] = {"clock": {"enable": False}}
        data.setdefault("wallpapers", {})["directory"] = str(folder / "wallpapers")
        env.update(WALLPAPER_FIXTURES=str(folder / "wallpapers"), APPLY_LOG=str(folder / "apply.log"),
                   CAPTURE_DIR=str(folder), QSG_RHI_BACKEND="opengl")
        for backend in ["opengl", "software"]:
            (config / "config.json").write_text(json.dumps(data))
            (folder / "apply.log").unlink(missing_ok=True)
            if backend == "software":
                env["QT_QUICK_BACKEND"] = "software"
            else:
                env.pop("QT_QUICK_BACKEND", None)
            result = run_qs(folder, env, timeout=40)
            log = result.stdout
            if result.returncode or "WALLPAPER_BACKGROUND_PASS" not in log or any(word in log for word in [
                    "WALLPAPER_BACKGROUND_FAIL", "ReferenceError:", "TypeError:", "Binding loop", "Failed to load configuration"]):
                print(backend, log); raise SystemExit(1)
            before, after, cancel, shown = [Image.open(folder / (name + ".png")).convert("RGB") for name in ["before", "after", "cancel", "shown"]]
            assert ImageChops.difference(before, after).getbbox(), "applied wallpaper pixels did not change"
            assert ImageChops.difference(after, cancel).getbbox() is None, "cancel preview did not restore exact applied image"
            assert ImageChops.difference(after, shown).getbbox(), "hidden apply retained the old wallpaper pixels"
            assert Image.open(folder / "detached.png").convert("RGB").getpixel((160, 90)) == (187, 76, 140), "frame-starved wallpaper did not present the selected image"
            calls = [json.loads(line) for line in (folder / "apply.log").read_text().splitlines()]
            assert len(calls) == 2 and calls[0][1].endswith("/b.png") and calls[1][1].endswith("/c.png"), calls
            print("WALLPAPER_BACKGROUND_PASS", backend, "desktop/picker pixels, hidden apply, missing frame handoff, exact preview cancel, no duplicate color requests")
