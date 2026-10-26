#!/usr/bin/env python3
"""New local edits must survive FileView completing an older async save."""
import json
import os
import tempfile
from pathlib import Path
from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-config-write-race-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "qmldir", "GlobalStates.qml", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
ShellRoot {
    Component.onCompleted: Quickshell.watchFiles = false
    TestCase {
        id: test; when: false; optional: true
        function check(value, message) { if (!value) throw new Error(message) }
        function runChecks() {
            try {
                tryCompare(Config, "ready", true, 4000)
                for (let round = 0; round < 4; ++round) {
                    const older = [{id: "notes", visible: true, x: .1, y: .1, w: .3, h: .4}]
                    const newer = [{id: "notes", visible: false, x: .2, y: .3, w: .4, h: .5}]
                    Config.setNestedValues({"dashboard.canvas.widgets": older,
                        "todo.obsidian.vaultPath": "old-" + round,
                        "abyss.companionMind.obsidianEnabled": false})
                    Config.flushWrites()
                    check(Config._writeInFlight, "test did not overlap an asynchronous save")
                    Config.setNestedValues({"dashboard.canvas.widgets": newer,
                        "todo.obsidian.vaultPath": "new-" + round,
                        "abyss.companionMind.obsidianEnabled": true})
                    if (round % 2) Config.flushWrites()
                    wait(200)
                    tryVerify(() => !Config._writeInFlight && !Config._pendingWrite, 3000)
                    const actual = Config.options.dashboard.canvas.widgets
                    check(actual.length === newer.length && Object.keys(newer[0]).every(key => actual[0][key] === newer[0][key]),
                        "older save restored the Dashboard layout, round " + round + ": " + JSON.stringify(actual))
                    check(Config.options.todo.obsidian.vaultPath === "new-" + round
                        && Config.options.abyss.companionMind.obsidianEnabled,
                        "older save restored the Obsidian context, round " + round)
                }
                console.info("CONFIG_WRITE_RACE_PASS four overlapping saves: debounce and explicit flush; layout and journal context")
            } catch (e) { console.error("CONFIG_WRITE_RACE_FAIL", e.message, e.stack) }
            Qt.quit()
        }
    }
    Timer { interval: 100; running: true; onTriggered: test.runChecks() }
}
''')
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_CONTROLS_STYLE="Basic",
               QT_QUICK_BACKEND="software")
    for kind in ["config", "state", "cache", "data"]:
        path = folder / kind
        path.mkdir()
        env[f"XDG_{kind.upper()}_HOME"] = str(path)
    config = folder / "config/alis/config.json"
    config.parent.mkdir()
    config.write_text((ROOT / "defaults/config.json").read_text())
    result = run_qs(folder, env, timeout=15)
    bad = ["CONFIG_WRITE_RACE_FAIL", "ReferenceError:", "TypeError:", "Binding loop", "Failed to load configuration"]
    if result.returncode or "CONFIG_WRITE_RACE_PASS" not in result.stdout or any(s in result.stdout for s in bad):
        print(result.stdout)
        raise SystemExit(1)
    saved = json.loads(config.read_text())
    assert saved["todo"]["obsidian"]["vaultPath"] == "new-3"
    assert saved["abyss"]["companionMind"]["obsidianEnabled"] is True
    assert saved["dashboard"]["canvas"]["widgets"][0]["visible"] is False
    print("CONFIG_WRITE_RACE_PASS in-memory and persisted state survive all four overlapping saves")
