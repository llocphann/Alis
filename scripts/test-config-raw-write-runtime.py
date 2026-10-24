#!/usr/bin/env python3
"""Real Config raw-save acknowledgements, custom data and error recovery."""
import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(os.environ.get("ALIS_CONFIG_TEST_ROOT", Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(ROOT / "scripts"))
from native_test_session import run_qs

QML = r'''
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.modules.common
ShellRoot {
    Component.onCompleted: Quickshell.watchFiles = false
    FileView { id: disk; path: Config.filePath; blockAllReads: true }
    Process { id: permission; property int completed: 0; onExited: completed++ }
    TestCase {
        id: test; when: false; optional: true
        property int checks: 0
        function check(value, message) { checks++; if (!value) throw new Error(message) }
        function readDisk() { disk.reload(); return JSON.parse(disk.text()) }
        function trace(stage) {
            console.info("CONFIG_RAW_WRITE_TRACE", stage, JSON.stringify({
                busy: Config._writeInFlight, pending: Config._pendingWrite,
                inject: Config._pendingCustomInject, retries: Config._writeRetries,
                value: Config.options.abyss.surface.opacity,
                disk: readDisk().abyss.surface.opacity
            }))
        }
        function settle(stage) {
            wait(100)
            tryVerify(() => !Config._writeInFlight && !Config._pendingWrite, 1800,
                      "write did not settle: " + stage)
            trace(stage)
        }
        function mode(value) {
            const done = permission.completed + 1
            permission.command = ["/usr/bin/chmod", value, Quickshell.env("CONFIG_TEST_FILE")]
            permission.running = true
            tryCompare(permission, "completed", done, 1500)
        }
        function stored(value, stage) {
            const raw = readDisk()
            check(raw.abyss.surface.opacity === value, "disk lost latest edit: " + stage)
            check(JSON.stringify(raw.optionalPackageData) === JSON.stringify({keep:[0,"future",null]}),
                  "raw save lost optional keys: " + stage)
            if (Quickshell.env("CUSTOM") === "1")
                check(JSON.stringify(raw.background.widgets.custom) === JSON.stringify({example:{keep:[0,"test",null]}}),
                      "raw save lost custom data: " + stage)
        }
        function runChecks() {
            try {
                tryCompare(Config, "ready", true, 5000)
                const action = Quickshell.env("ACTION")
                if (action === "restart") {
                    settle("restart")
                    stored(.73, "restart")
                    check(Config.options.abyss.surface.opacity === .73, "restart did not load saved value")
                } else {
                    settle("startup/migration")
                    if (action === "migration") {
                        const migrated = readDisk().abyss.content
                        check(migrated.opacity === .35 && migrated.opacityVersion === 1,
                              "actual migration did not reach disk")
                        Config.setNestedValue("abyss.surface.opacity", .73)
                        settle("edit after migration")
                        stored(.73, "edit after migration")
                    } else if (action === "debounce") {
                        // Ordinary settings controls debounce; they do not
                        // call flushWrites(). Preserve foreign/optional data
                        // on this path too, including a later scalar edit.
                        Config.setNestedValue("abyss.surface.opacity", .41)
                        settle("ordinary debounced edit")
                        stored(.41, "ordinary debounced edit")
                        Config.setNestedValues({"abyss.surface.opacity": .73})
                        settle("later debounced edit")
                        stored(.73, "later debounced edit")
                    } else {
                        Config.blockWrites = Quickshell.env("SYNC") === "1"
                        Config.setNestedValue("abyss.surface.opacity", .41)
                        Config.flushWrites()
                        settle("first raw save")
                        stored(.41, "first raw save")
                        for (let index = 0; index < 3; index++) {
                            Config.flushWrites()
                            settle("unchanged flush " + index)
                            stored(.41, "unchanged flush " + index)
                        }
                        if (action === "failure") {
                            mode("400")
                            Config.setNestedValue("abyss.surface.opacity", .73)
                            Config.flushWrites()
                            settle("failed save acknowledgement")
                            stored(.41, "failed save left disk intact")
                            check(Config.options.abyss.surface.opacity === .73,
                                  "failed save discarded desired value")
                            mode("600")
                            Config.flushWrites()
                        } else {
                            Config.setNestedValue("abyss.surface.opacity", .73)
                            Config.flushWrites()
                            // A genuinely later edit overlaps the accepted raw save.
                            Config.setNestedValue("abyss.surface.opacity", .67)
                            Config.setNestedValue("abyss.surface.opacity", .73)
                            Config.flushWrites()
                        }
                        settle("later edit/retry")
                        stored(.73, "later edit/retry")
                    }
                }
                console.info("CONFIG_RAW_WRITE_PASS", action, Quickshell.env("CUSTOM"), Quickshell.env("SYNC"), checks)
            } catch (error) {
                trace("failure")
                console.error("CONFIG_RAW_WRITE_FAIL", error.message, error.stack)
            }
            Qt.quit()
        }
    }
    Timer { interval: 100; running: true; onTriggered: test.runChecks() }
}
'''

logs = []
checks = 0
matrix = [("migration", True, False), ("flush", True, False),
          ("flush", False, False), ("flush", True, True),
          ("debounce", False, False), ("debounce", True, False),
          ("failure", True, False), ("failure", False, False)]
if os.environ.get("ALIS_CONFIG_TEST_CASE"):
    matrix = [entry for entry in matrix if entry[0] == os.environ["ALIS_CONFIG_TEST_CASE"]]
with tempfile.TemporaryDirectory(prefix="alis-config-raw-write-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "qmldir", "GlobalStates.qml", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "shell.qml").write_text(QML)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QSG_RHI_BACKEND="software")
    for key in ["WAYLAND_DISPLAY", "DISPLAY", "NIRI_SOCKET", "QS_CONFIG_NAME", "QS_CONFIG_PATH", "QS_MANIFEST", "HYPRLAND_INSTANCE_SIGNATURE"]:
        env.pop(key, None)
    runtime = folder / "runtime"
    runtime.mkdir(mode=0o700)
    env["XDG_RUNTIME_DIR"] = str(runtime)
    for kind in ["config", "state", "cache", "data"]:
        path = folder / kind
        path.mkdir()
        env[f"XDG_{kind.upper()}_HOME"] = str(path)
    config = folder / "config/alis/config.json"
    config.parent.mkdir(parents=True)
    for action, custom, synchronous in matrix:
        raw = json.loads((ROOT / "defaults/config.json").read_text())
        raw["abyss"]["companion"]["enabled"] = False
        raw["optionalPackageData"] = {"keep": [0, "future", None]}
        raw["background"]["widgets"]["custom"] = {"example": {"keep": [0, "test", None]}} if custom else {}
        if action == "migration":
            raw["abyss"]["content"] = {"cardOpacity": .35, "blurRadius": 12}
        config.write_text(json.dumps(raw, indent=4))
        for stage in [action, "restart"]:
            result = run_qs(folder, dict(env, CONFIG_TEST_FILE=str(config),
                ACTION=stage, CUSTOM=str(int(custom)), SYNC=str(int(synchronous))), timeout=25)
            logs.append(result.stdout)
            bad = ["CONFIG_RAW_WRITE_FAIL", "ReferenceError:", "TypeError:", "Binding loop", "Failed to load configuration"]
            if result.returncode or "CONFIG_RAW_WRITE_PASS" not in result.stdout or any(item in result.stdout for item in bad):
                print(result.stdout)
                print("FAILED_DISK", config.read_text()[:200])
                if os.environ.get("ALIS_CONFIG_RAW_WRITE_LOG"):
                    Path(os.environ["ALIS_CONFIG_RAW_WRITE_LOG"]).write_text("\n".join(logs))
                raise SystemExit(1)
            saved = json.loads(config.read_text())
            assert saved["abyss"]["surface"]["opacity"] == .73
            assert saved["optionalPackageData"] == raw["optionalPackageData"]
            assert saved["background"]["widgets"]["custom"] == raw["background"]["widgets"]["custom"]
            checks += 1
    if os.environ.get("ALIS_CONFIG_RAW_WRITE_LOG"):
        Path(os.environ["ALIS_CONFIG_RAW_WRITE_LOG"]).write_text("\n".join(logs))
print(f"CONFIG_RAW_WRITE_PASS {checks} startup/restart processes: migration, custom/no-custom, unchanged saves, async/sync, failed-save retry; actual private disk readbacks, no windows")
