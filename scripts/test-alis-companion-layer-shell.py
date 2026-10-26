#!/usr/bin/env python3
"""Actual Abyss perimeter boots without the optional package on isolated Wayland."""
import json
from pathlib import Path
import tempfile
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-without-companion-") as temporary:
    folder = Path(temporary)
    for name in ("modules", "services", "scripts", "defaults", "translations", "assets", "qmldir", "GlobalStates.qml"):
        (folder / name).symlink_to(ROOT / name)
    config = folder / "config/alis"
    config.mkdir(parents=True)
    options = json.loads((ROOT / "defaults/config.json").read_text())
    options["panelFamily"] = "abyss"
    options["enabledPanels"] = []
    options["abyss"]["companion"]["enabled"] = True
    (config / "config.json").write_text(json.dumps(options))
    (folder / "shell.qml").write_text('''
import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.abyss
ShellRoot {
    id:root
    property int ticks:0
    property var host:AlisCompanion
    property var settings:Config.options
    AbyssPerimeter { id:perimeter }
    Timer {
        interval:100;running:true;repeat:true
        onTriggered: {
            if(++root.ticks>80){console.error("ALIS_COMPANION_CORE_LAYER_FAIL timeout");Qt.quit();return}
            if(root.ticks<25 || !Config.ready || AlisCompanion.outputs.length===0)return
            let valid=!AlisCompanion.available && !AlisCompanion.enabled && AlisCompanion.session===null
                && Config.options.abyss.companion.enabled
            for(const surface of AlisCompanion.outputs)valid=valid && surface.extension===null
                && !surface.inputRegions.length && !surface.editing && !surface.curiosityOwned && !surface.waterLink
            console.info(valid ? "ALIS_COMPANION_CORE_LAYER_PASS" : "ALIS_COMPANION_CORE_LAYER_FAIL")
            Qt.quit()
        }
    }
}
''')
    with private_wayland(folder) as environment:
        if environment is None:
            print("SKIP: actual Abyss core boot needs an isolated Wayland backend")
            raise SystemExit(0)
        environment.update(ALIS_COMPANIOND="/nonexistent/never-run", ALIS_GGUF_ROOTS="[]",
                           QT_QUICK_BACKEND="software", QT_QUICK_CONTROLS_STYLE="Basic", QT_QPA_PLATFORMTHEME="generic")
        result = run_qs(folder, environment)
    errors = ("ALIS_COMPANION_CORE_LAYER_FAIL", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign", "is not a type")
    assert result.returncode == 0 and "ALIS_COMPANION_CORE_LAYER_PASS" in result.stdout and not any(e in result.stdout for e in errors), result.stdout[-18000:]
print("PASS: real Abyss perimeter imports/boots on isolated Wayland without Companion assets or daemon")
