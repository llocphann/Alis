#!/usr/bin/env python3
"""Actual palette backend, native shared field, cancellation and bounded cache."""
import json
import os
import subprocess
import tempfile
from pathlib import Path
from PIL import Image, ImageChops
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
WORKER = ROOT / "scripts/colors/preview-palette.py"
with tempfile.TemporaryDirectory(prefix="hadalis-color-preview-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    fixtures = folder / "images"
    fixtures.mkdir()
    for label, color in [("a", "#156c9c"), ("b", "#bd3754"), ("c", "#329759")]:
        Image.new("RGB", (320, 180), color).save(fixtures / (label + ".png"))
    hooks = folder / "app-hooks/colors"
    hooks.mkdir(parents=True)
    marker = folder / "external-applies"
    (hooks / "applycolor.sh").write_text('#!/bin/sh\nprintf "applied\\n" >> "$PREVIEW_EXTERNAL_MARKER"\n')
    (folder / "shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.abyss.looks
import qs.services
import "modules/abyss/looks/AbyssGeometry.js" as Geometry
ShellRoot {
 id: root
 property int frames:0
 readonly property string images:Quickshell.env("PREVIEW_IMAGES")+"/"
 readonly property var a:JSON.parse(Quickshell.env("PREVIEW_A"))
 readonly property var b:JSON.parse(Quickshell.env("PREVIEW_B"))
 readonly property var c:JSON.parse(Quickshell.env("PREVIEW_C"))
 Component.onCompleted:Quickshell.watchFiles=false
 FileView { id: external; path:Quickshell.env("PREVIEW_EXTERNAL_MARKER") }
 FloatingWindow {
  visible:true;implicitWidth:640;implicitHeight:360;color:"#111820"
  AbyssField {
   id:field;anchors.fill:parent;edgeInsets:({left:10,top:10,right:10,bottom:10})
   records:[Geometry.panel(width,height,edgeInsets,"top",140,300,180,1,14,[])]
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(v,m){if(!v)throw new Error(m)}
  function snapshot(){
   const result={}
   for(const key of Object.keys(Appearance.m3colors))
    if(key.startsWith("m3") || /^term\d+$/.test(key) || ["darkmode","transparent"].includes(key))
     if(typeof Appearance.m3colors[key]!=="function")result[key]=String(Appearance.m3colors[key])
   return JSON.stringify(result)
  }
  function paletteIs(value){return Appearance.m3colors.m3primary===Qt.color(value.primary) && Appearance.m3colors.m3background===Qt.color(value.background)}
  function capture(name){
   const before=root.frames
   check(field.grabToImage(image=>{if(image.saveToFile(Quickshell.env("PREVIEW_CAPTURE")+"/"+name+".png"))root.frames++}),"field capture refused")
   tryVerify(()=>root.frames>before,3000)
  }
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000)
   Config.blockWrites=true
   Directories.scriptsPath=Quickshell.env("PREVIEW_HOOKS")
   MaterialThemeLoader.filePath=Quickshell.env("PREVIEW_BASELINE")
   tryVerify(()=>MaterialThemeLoader.ready && paletteIs(root.a),3000)
   const revision=Config.revision, wallpaper=Config.options.background.wallpaperPath
   const initial=snapshot()
   capture("baseline")
   Wallpapers.previewWallpaper(root.images+"b.png")
   tryVerify(()=>paletteIs(root.b),4000)
   check(MaterialThemeLoader.previewActive && Config.options.background.wallpaperPath===wallpaper && Config.revision===revision,"browsing committed wallpaper or configuration")
   capture("highlighted")
   MaterialThemeLoader.requestExternalApply();wait(750)
   check(MaterialThemeLoader._previewExternalDeferred,"preview colors reached external application theming")
   external.reload();wait(80)
   check(!external.loaded || external.text()==="","preview executed the external theme hook")
   Wallpapers.cancelWallpaperPreview()
   check(snapshot()===initial && !MaterialThemeLoader.previewActive,"cancel did not restore every color and mode")
   wait(750);external.reload();wait(80)
   check(external.text()==="applied\n","deferred real application update did not resume after cancellation")
   Wallpapers.previewWallpaper(root.images+"b.png")
   Wallpapers.previewWallpaper(root.images+"a.png")
   Wallpapers.previewWallpaper(root.images+"c.png")
   tryVerify(()=>paletteIs(root.c),4000);wait(120)
   check(paletteIs(root.c),"an old generation replaced the latest highlighted wallpaper")
   MaterialThemeLoader.applyColors(JSON.stringify(root.b))
   check(paletteIs(root.c),"real theme update removed the current preview")
   Wallpapers.cancelWallpaperPreview()
   check(paletteIs(root.b),"cancel clobbered an authoritative theme update received during browsing")
   const updated=snapshot()
   Wallpapers.previewWallpaper(root.images+"a.png")
   Wallpapers.cancelWallpaperPreview();wait(500)
   check(snapshot()===updated,"late preview process resurrected colors after cancellation")
   Wallpapers.previewWallpaper(root.images+"c.png");tryVerify(()=>paletteIs(root.c),4000)
   Wallpapers.clearWallpaperPreview()
   check(snapshot()===updated && !Wallpapers.internalPreviewActive,"apply handoff persisted preview mode or wallpaper")
   Wallpapers.previewWallpaper(root.images+"c.png");tryVerify(()=>paletteIs(root.c),4000)
   Wallpapers.previewWallpaper(root.images+"missing.png");wait(500)
   check(snapshot()===updated,"failed latest generation left colors from a different wallpaper")
   Wallpapers.cancelWallpaperPreview()
   // Liquid previews must postpone CPU palette work until the previewed frame
   // is presented, then still apply/cancel the latest palette correctly.
   MaterialThemeLoader.previewWallpaperColors(root.images+"b.png","",true)
   check(MaterialThemeLoader._previewWaitingForPresentation,"Liquid preview palette started too early")
   check(MaterialThemeLoader._previewPending!==null,"deferred palette request was lost")
   MaterialThemeLoader.previewWallpaperPresented(root.images+"b.png")
   tryVerify(()=>paletteIs(root.b),4000)
   MaterialThemeLoader.cancelColorPreview()
   check(Config.revision===revision && Config.options.background.wallpaperPath===wallpaper,"preview mutated a durable setting")
   console.info("WALLPAPER_COLOR_PREVIEW_PASS")
  }catch(e){console.error("WALLPAPER_COLOR_PREVIEW_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer { interval:100;running:true;onTriggered:test.runChecks() }
}
''')
    with private_wayland(folder) as env:
        if env is None:
            raise SystemExit("SKIP: palette preview requires a private Niri surface")
        config = folder / "config/alis"
        config.mkdir(parents=True, exist_ok=True)
        data = json.loads((ROOT / "defaults/config.json").read_text())
        data["panelFamily"] = "abyss"
        data["abyss"]["companion"]["enabled"] = False
        data["abyss"]["effects"]["blur"]["enabled"] = False
        data["abyss"]["effects"]["refraction"]["enabled"] = False
        data["abyss"]["content"]["blurRadius"] = 0
        (config / "config.json").write_text(json.dumps(data))
        palettes = {}
        for label in ["a", "b", "c"]:
            result = subprocess.run(["python3", str(WORKER), str(fixtures / (label + ".png")), "{}"],
                                    env=env, check=True, text=True, capture_output=True, timeout=25)
            palettes[label] = json.loads(result.stdout)
        baseline = folder / "active-colors.json"
        original = json.dumps(palettes["a"])
        baseline.write_text(original)
        env.update(INIR_STANDALONE_WINDOW="0", PREVIEW_IMAGES=str(fixtures),
                   PREVIEW_A=json.dumps(palettes["a"]), PREVIEW_B=json.dumps(palettes["b"]),
                   PREVIEW_C=json.dumps(palettes["c"]), PREVIEW_HOOKS=str(hooks.parent),
                   PREVIEW_EXTERNAL_MARKER=str(marker), PREVIEW_BASELINE=str(baseline), PREVIEW_CAPTURE=str(folder))
        result = run_qs(folder, env, timeout=30)
        if result.returncode or "WALLPAPER_COLOR_PREVIEW_PASS" not in result.stdout or any(
            token in result.stdout for token in ["WALLPAPER_COLOR_PREVIEW_FAIL", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign", "Failed to load configuration"]
        ):
            print(result.stdout)
            raise SystemExit(1)
        assert baseline.read_text() == original, "preview overwrote the active colors file"
        first = Image.open(folder / "baseline.png").convert("RGB")
        highlighted = Image.open(folder / "highlighted.png").convert("RGB")
        assert ImageChops.difference(first, highlighted).crop((0, 0, 600, 180)).getbbox(), "shared field did not repaint highlighted colors"
        print("WALLPAPER_COLOR_PREVIEW_PASS native shared field, real generator, latest request, all-color restoration, authoritative update and deferred external theming")
