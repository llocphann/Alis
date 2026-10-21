#!/usr/bin/env python3
"""Independent material Settings handlers, explicit zero and durable choices."""
import json, os, tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs
ROOT = Path(os.environ.get("ABYSS_MATERIAL_TEST_ROOT", str(Path(__file__).resolve().parents[1]))).resolve()
with tempfile.TemporaryDirectory(prefix="alis-panel-material-settings-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.abyss.settings
import qs.modules.abyss.looks
ShellRoot {
    id: root
    property int checks: 0
    Component.onCompleted: Quickshell.watchFiles = false
    FloatingWindow {
        visible: true; implicitWidth: 720; implicitHeight: 650; color: "#111820"
        Flickable {
            id: view; anchors.fill: parent; contentWidth: width; contentHeight: settings.implicitHeight; clip: true
            AbyssStyleSettings { id: settings; width: view.width; activeSection: "surface" }
        }
    }
    TestCase {
        id: test; when: false; optional: true
        function check(v, m) { root.checks++; if (!v) throw new Error(m) }
        function find(item, p) {
            if (p(item)) return item
            for (const child of item.children ?? []) { const x = find(child, p); if (x) return x }
            return null
        }
        function setFollow(control,checked) {
            if (control.checked !== checked) control.clicked()
            check(control.checked === checked, "follow icon did not reflect its click")
        }
        function slider(row) {
            return find(row, i => i !== row && typeof i.value === "number"
                && i.from === row.from && i.to === row.to && typeof i.moved === "function")
        }
        function runChecks() { try {
            tryCompare(Config, "ready", true, 6000)
            if (Quickshell.env("MATERIAL_RESTART") === "1") {
                check(Config.options.abyss.content.opacity === .75, "saved opacity lost")
                check(Config.options.abyss.content.blurRadius === 12, "saved blur lost")
                check(AbyssStyle.contentOpacity === .75 && AbyssStyle.contentBlurRadius === 12, "restart resolved wrong material")
                check(AbyssStyle.cardOpacity === .75 && Math.abs(AbyssStyle.contentLayer.a-.75)<.005, "restart restored independent card alpha")
                console.info("PANEL_MATERIAL_RESTART_PASS", root.checks)
                Qt.quit(); return
            }
            Config.setNestedValues({"panelFamily":"abyss", "performance.reduceAnimations":true, "performance.lowPower":false,
                "abyss.quality":"quality", "abyss.autoQuality":false, "abyss.surface.opacity":.62,
                "abyss.effects.blur.radius":12, "abyss.effects.blur.enabled":true,
                "abyss.content.opacity":.25, "abyss.content.blurRadius":17})
            // The old label allows the same reproducer to detect the original defect.
            const opacityFollow = find(settings, i => i.objectName === "abyssPanelOpacityFollow" || i.text === "Panel background follows Screen Edge")
            check(opacityFollow !== null, "opacity follow control missing")
            setFollow(opacityFollow,true)
            check(Config.options.abyss.content.blurRadius === 17, "opacity inheritance overwrote independent blur: " + Config.options.abyss.content.blurRadius)
            check(Config.options.abyss.content.opacity === -1 && opacityFollow.checked, "opacity inheritance not active")
            check(AbyssStyle.contentBlurRadius === 17, "opacity inheritance changed resolved blur")
            const blurFollow = findChild(settings, "abyssPanelBlurFollow")
            const opacityRow = findChild(settings, "abyssPanelOpacity")
            const opacitySlider = slider(opacityRow)
            const blurRow = findChild(settings, "abyssPanelBlur")
            const blurSlider = slider(blurRow)
            check(blurFollow !== null && opacitySlider !== null && blurSlider !== null, "separate controls missing")
            check(opacityRow.text === "Panel & content opacity", "shared slider label missing")
            check(find(settings, i => i.text === "Content card opacity") === null, "retired card slider still visible")
            for (const alpha of [-1, 0, .25, .5, .75, 1]) for (const radius of [-1, 0, 8, 16, 24]) {
                Config.setNestedValues({"abyss.content.opacity":alpha, "abyss.content.blurRadius":radius})
                const beforeBlur = Config.options.abyss.content.blurRadius
                setFollow(opacityFollow,true)
                check(Config.options.abyss.content.blurRadius === beforeBlur, "opacity follow wrote blur")
                setFollow(opacityFollow,false)
                check(Config.options.abyss.content.opacity === .62, "opacity detach changed inherited value")
                check(Config.options.abyss.content.blurRadius === beforeBlur, "opacity detach wrote blur")
                opacitySlider.value = alpha < 0 ? 0 : alpha; opacitySlider.moved()
                check(Config.options.abyss.content.opacity === (alpha < 0 ? 0 : alpha), "opacity slider ignored explicit value")
                check(AbyssStyle.cardOpacity === AbyssStyle.contentOpacity && Math.abs(AbyssStyle.contentLayer.a-AbyssStyle.contentOpacity)<.005, "shared slider did not update cards")
                check(Config.options.abyss.content.blurRadius === beforeBlur, "opacity slider wrote blur")
                const beforeAlpha = Config.options.abyss.content.opacity
                setFollow(blurFollow,true)
                check(Config.options.abyss.content.opacity === beforeAlpha, "blur follow wrote opacity")
                check(Config.options.abyss.content.blurRadius === -1 && blurFollow.checked, "blur inheritance not active")
                setFollow(blurFollow,false)
                check(Config.options.abyss.content.blurRadius === 12, "blur detach lost configured Edge value")
                check(Config.options.abyss.content.opacity === beforeAlpha, "blur detach wrote opacity")
                blurSlider.value = radius < 0 ? 0 : radius; blurSlider.moved()
                check(Config.options.abyss.content.blurRadius === (radius < 0 ? 0 : radius), "blur slider ignored explicit zero")
                check(Config.options.abyss.content.opacity === beforeAlpha, "blur slider wrote opacity")
                check(!blurFollow.checked && !opacityFollow.checked, "explicit value was treated as inherit")
            }
            for (const policy of ["performance", "effects-off", "quality"]) {
                Config.setNestedValues({"abyss.quality":policy === "performance" ? "performance" : "quality",
                    "performance.lowPower":policy === "effects-off", "abyss.content.opacity":.75, "abyss.content.blurRadius":17})
                check(AbyssStyle.configuredContentBlurRadius === 17, "policy overwrote configured blur")
                check(AbyssStyle.contentBlurRadius === (policy === "quality" ? 17 : 0), "policy did not suppress only effective radius")
                setFollow(blurFollow,true); setFollow(blurFollow,false)
                check(Config.options.abyss.content.blurRadius === 12, "detach saved temporary policy zero")
                check(Config.options.abyss.content.opacity === .75, "policy/detach changed opacity")
            }
            // SET-R04 retired the opaque batch preset. Exercise the same durable
            // material choices through the current independent value controls.
            const retired = Config.options.abyss.content.cardOpacity
            opacitySlider.value=1;opacitySlider.moved()
            blurSlider.value=0;blurSlider.moved()
            check(AbyssStyle.contentOpacity === 1 && AbyssStyle.cardOpacity === 1, "opaque action did not set shared alpha")
            check(Config.options.abyss.content.cardOpacity === retired, "opaque action wrote retired card preference")
            check(Config.options.abyss.content.blurRadius === 0, "opaque action retained blur")
            Config.setNestedValues({"abyss.quality":"quality", "performance.lowPower":false,
                "abyss.content.opacity":.75, "abyss.content.blurRadius":12})
            Config.flushWrites(); wait(200)
            tryVerify(() => !Config._writeInFlight && !Config._pendingWrite, 4000)
            console.info("PANEL_MATERIAL_SETTINGS_PASS", root.checks, "independent axes, inheritance, zero, policy and disk")
        } catch (e) { console.error("PANEL_MATERIAL_SETTINGS_FAIL", e.message, e.stack) } Qt.quit() }
    }
    Timer { interval: 150; running: true; onTriggered: test.runChecks() }
}
''')
    with private_wayland(folder) as env:
        if env is None:
            print("SKIP: material Settings require private Niri"); raise SystemExit(0)
        config = folder / "config/illogical-impulse/config.json"
        config.parent.mkdir(parents=True, exist_ok=True)
        value = json.loads((ROOT / "defaults/config.json").read_text())
        value["panelFamily"] = "abyss"; value["abyss"]["companion"]["enabled"] = False
        config.write_text(json.dumps(value)); env["QSG_RHI_BACKEND"] = "opengl"
        for restart in [False, True]:
            env["MATERIAL_RESTART"] = "1" if restart else "0"
            result = run_qs(folder, env, timeout=45)
            marker = "PANEL_MATERIAL_RESTART_PASS" if restart else "PANEL_MATERIAL_SETTINGS_PASS"
            if result.returncode or marker not in result.stdout or any(s in result.stdout for s in
                ["PANEL_MATERIAL_SETTINGS_FAIL", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign", "Failed to load configuration"]):
                print(result.stdout); raise SystemExit(1)
            for line in result.stdout.splitlines():
                if marker in line: print(line)
            # Config.filePath writes Alis; keep the legacy fixture seed untouched.
            assert config.read_text() == json.dumps(value)
            saved = json.loads((folder / "config/alis/config.json").read_text())
            assert saved["abyss"]["content"]["opacity"] == .75
            assert saved["abyss"]["content"]["blurRadius"] == 12
    print("PASS: actual Settings callbacks and Config disk readback/restart; owner config untouched")
