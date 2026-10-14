#!/usr/bin/env python3
"""Actual one-pass field: independent alpha/blur under wallpaper and power policy."""
import hashlib, json, os, shutil, tempfile
from pathlib import Path
from PIL import Image, ImageChops
from native_test_session import private_wayland, run_qs
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-panel-material-pixels-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    for tone in ["light", "dark"]:
        image = Image.new("RGB", (420, 300))
        image.putdata([tuple(min(255, max(0, v)) for v in (
            (90 if tone == "dark" else 175) + (73 if (x // 11 + y // 17) % 2 else -63),
            (65 if tone == "dark" else 145) + (x * 23 + y * 7) % 70,
            (100 if tone == "dark" else 195) + (x * 11 + y * 19) % 53 - 26
        )) for y in range(300) for x in range(420)])
        image.save(folder / (tone + ".png"))
    (folder / "shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.abyss.looks
ShellRoot {
    id: root
    property int captures: 0
    Component.onCompleted: Quickshell.watchFiles = false
    FloatingWindow {
        visible: true; implicitWidth: 420; implicitHeight: 300; color: "#111820"
        AbyssField {
            id: field; anchors.fill: parent; edgeInsets: ({left:10,right:10,top:10,bottom:10})
            records: [{surface:{x:100,y:140,width:220,height:210}}]
        }
    }
    TestCase {
        id: test; when: false; optional: true
        function check(v, m) { if (!v) throw new Error(m) }
        function capture(name) {
            const before = root.captures
            check(field.grabToImage(result => {
                if (!result.saveToFile(Quickshell.env("MATERIAL_OUTPUT") + "/" + name + ".png"))
                    console.error("PANEL_PIXEL_FAIL save", name)
                root.captures++
            }), "capture refused")
            tryVerify(() => root.captures > before, 4000)
        }
        function runChecks() { try {
            tryCompare(Config, "ready", true, 6000)
            Config.setNestedValues({"panelFamily":"abyss", "performance.reduceAnimations":true, "abyss.autoQuality":false,
                "abyss.surface.opacity":.85, "abyss.effects.blur.enabled":true, "abyss.effects.blur.radius":10,
                "abyss.effects.refraction.enabled":true, "abyss.effects.refraction.strength":1,
                "abyss.waves.enabled":false, "abyss.effects.surfaceHighlight":0,
                "abyss.effects.glow.strength":0, "abyss.effects.shadowStrength":0})
            tryCompare(field, "ready", true, 5000)
            for (const tone of ["light", "dark"]) for (const policy of ["quality", "performance", "effects-off"]) {
                const path = Quickshell.env("MATERIAL_OUTPUT") + "/" + tone + ".png"
                Config.setNestedValues({"background.wallpaperPath":path,
                    "abyss.quality":policy === "performance" ? "performance" : "quality",
                    "performance.lowPower":policy === "effects-off"})
                for (const percent of [0, 25, 50, 75, 100]) for (const radius of [0, 8, 16, 24]) {
                    Config.setNestedValues({"abyss.content.opacity":percent / 100, "abyss.content.blurRadius":radius})
                    wait(30)
                    check(AbyssStyle.contentOpacity === percent / 100, "wrong effective alpha")
                    check(AbyssStyle.cardOpacity === percent / 100 && Math.abs(AbyssStyle.contentLayer.a-percent/100)<.005, "card tint did not share panel alpha")
                    check(AbyssStyle.configuredContentBlurRadius === radius, "configured radius changed")
                    check(AbyssStyle.contentBlurRadius === (policy === "quality" ? radius : 0), "wrong effective blur policy")
                    if (field.wantsWallpaper) {
                        tryCompare(field, "wallpaperReady", true, 5000)
                        check(field.wallpaperUrl.includes(tone + ".png"), "wrong wallpaper source")
                    }
                    capture(tone + "_" + policy + "_" + percent + "_" + radius)
                }
            }
            console.info("PANEL_PIXEL_PASS", root.captures, "actual alpha/blur/policy/light-dark captures")
        } catch (e) { console.error("PANEL_PIXEL_FAIL", e.message, e.stack) } Qt.quit() }
    }
    Timer { interval: 100; running: true; onTriggered: test.runChecks() }
}
''')
    with private_wayland(folder) as env:
        if env is None:
            print("SKIP: material pixels require private Niri"); raise SystemExit(0)
        config = folder / "config/alis/config.json"
        config.parent.mkdir(parents=True, exist_ok=True)
        value = json.loads((ROOT / "defaults/config.json").read_text())
        value["panelFamily"] = "abyss"; value["abyss"]["companion"]["enabled"] = False
        config.write_text(json.dumps(value)); env.update(QSG_RHI_BACKEND="opengl", MATERIAL_OUTPUT=str(folder))
        result = run_qs(folder, env, timeout=180)
        bad = ["PANEL_PIXEL_FAIL", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign", "Failed to load configuration"]
        if result.returncode or "PANEL_PIXEL_PASS 120" not in result.stdout or any(s in result.stdout for s in bad):
            print(result.stdout); raise SystemExit(1)
        crop = (150, 190, 250, 250); stats = []; checks = 0
        for tone in ["light", "dark"]:
            for policy in ["quality", "performance", "effects-off"]:
                for percent in [0, 25, 50, 75, 100]:
                    images = {radius: Image.open(folder / f"{tone}_{policy}_{percent}_{radius}.png").convert("RGBA") for radius in [0, 8, 16, 24]}
                    clear = images[0]
                    assert abs(clear.getpixel((210, 220))[3] - round(percent * 2.55)) <= 1, (tone, policy, percent, "body alpha")
                    checks += 1
                    for radius, image in images.items():
                        assert image.getchannel("A").tobytes() == clear.getchannel("A").tobytes(), (tone, policy, percent, radius, "blur changed alpha/silhouette")
                        checks += 1
                        diff = ImageChops.difference(clear.crop(crop), image.crop(crop))
                        rgb = sum(diff.convert("RGB").tobytes())
                        if policy == "quality" and percent > 0 and radius > 0:
                            assert rgb > 500, (tone, percent, radius, "invisible blur change")
                        elif percent == 0 or policy != "quality":
                            assert rgb == 0, (tone, policy, percent, radius, "suppressed/transparent body differs")
                        checks += 1
                        stats.append({"tone":tone, "policy":policy, "opacityPercent":percent, "radius":radius,
                            "rgbDifferenceFromClear":rgb, "sha256":hashlib.sha256((folder / f"{tone}_{policy}_{percent}_{radius}.png").read_bytes()).hexdigest()})
        output = os.environ.get("ABYSS_MATERIAL_OUTPUT")
        if output:
            dest = Path(output); dest.mkdir(parents=True, exist_ok=True)
            for p in folder.glob("*.png"): shutil.copyfile(p, dest / p.name)
            (dest / "runtime.log").write_text(result.stdout)
            (dest / "matrix.json").write_text(json.dumps({"result":"PASS", "captures":120, "pixelChecks":checks, "cases":stats,
                "boundary":"Exact alpha equality across blur, explicit zero and policy suppression on test light/dark textures. No owner visual, video fallback, multi-output or cost claim."}, indent=2) + "\n")
        print("PASS: 120 field captures;", checks, "pixel checks; independent alpha, zero and policy suppression")
