#!/usr/bin/env python3
"""Silent regression test for Settings Window Escape-to-close, Super+, single-instance toggle,
and Settings startup loading screen.
"""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile

from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]


def test_cli_settings_toggle_and_overlay() -> None:
    """Verify `scripts/alis settings` closes an open Settings window instead of opening Overlay,
    while `scripts/alis settings --overlay` invokes `ipc call settings openOverlay`.
    """
    with tempfile.TemporaryDirectory(prefix="alis-settings-cli-test-") as tmp:
        base = Path(tmp)
        fake_bin = base / "bin"
        fake_bin.mkdir()
        log_file = base / "qs.log"
        state_file = base / "running_qml.txt"

        fake_qs = fake_bin / "qs"
        fake_qs.write_text(
            f"""#!/usr/bin/env python3
import json, pathlib, sys
log = pathlib.Path({str(log_file)!r})
state = pathlib.Path({str(state_file)!r})
args = sys.argv[1:]
with log.open("a", encoding="utf-8") as fh:
    fh.write(json.dumps(args) + "\\n")

if len(args) >= 3 and args[0] == "-p":
    target = args[1]
    cmd = args[2]
    running = state.read_text(encoding="utf-8").strip() if state.exists() else ""
    if cmd == "list":
        if target == {str(ROOT)!r} or (running and target == running):
            print(f"Instance win1 (pid 999999) path={{target}}")
        else:
            print("No running instances for this configuration.")
        sys.exit(0)
    if cmd == "kill":
        if running and target == running:
            state.write_text("", encoding="utf-8")
        sys.exit(0)
    if cmd == "ipc":
        sys.exit(0)

sys.exit(0)
""",
            encoding="utf-8",
        )
        fake_qs.chmod(fake_qs.stat().st_mode | stat.S_IXUSR)

        env = dict(os.environ)
        env["PATH"] = f"{fake_bin}:{env.get('PATH', '')}"
        env["ALIS_QS_BIN"] = str(fake_qs)
        env["XDG_CONFIG_HOME"] = str(base / "config")
        env["XDG_STATE_HOME"] = str(base / "state")
        env["XDG_CACHE_HOME"] = str(base / "cache")
        env["ALIS_RUNTIME_DIR"] = str(ROOT)
        cfg_dir = base / "config/illogical-impulse"
        cfg_dir.mkdir(parents=True)
        (cfg_dir / "config.json").write_text('{"settingsUi": {"presentationMode": "overlay"}}', encoding="utf-8")

        # Case 1: settings.qml is already running -> `alis settings` closes it, NEVER opens overlay
        log_file.write_text("", encoding="utf-8")
        state_file.write_text(str(ROOT / "settings.qml"), encoding="utf-8")
        res = subprocess.run(["bash", str(ROOT / "scripts/alis"), "settings"], env=env, text=True, capture_output=True)
        assert res.returncode == 0, f"alis settings failed: {res.stdout}\n{res.stderr}"
        calls = log_file.read_text(encoding="utf-8")
        assert '"kill"' in calls and 'settings.qml' in calls, f"expected kill settings.qml, got:\n{calls}"
        assert '"ipc"' not in calls, f"alis settings must NOT open overlay while closing settings window:\n{calls}"

        # Case 2: waffleSettings.qml is already running -> `alis settings` closes it, NEVER opens overlay
        log_file.write_text("", encoding="utf-8")
        state_file.write_text(str(ROOT / "waffleSettings.qml"), encoding="utf-8")
        res = subprocess.run(["bash", str(ROOT / "scripts/alis"), "settings"], env=env, text=True, capture_output=True)
        assert res.returncode == 0, f"alis settings (waffle) failed: {res.stdout}\n{res.stderr}"
        calls = log_file.read_text(encoding="utf-8")
        assert '"kill"' in calls and 'waffleSettings.qml' in calls, f"expected kill waffleSettings.qml, got:\n{calls}"
        assert '"ipc"' not in calls, f"alis settings must NOT open overlay while closing waffleSettings window:\n{calls}"

        # Case 3: `alis settings --overlay` explicitly opens Overlay even when switching from Window
        log_file.write_text("", encoding="utf-8")
        state_file.write_text(str(ROOT / "settings.qml"), encoding="utf-8")
        res = subprocess.run(["bash", str(ROOT / "scripts/alis"), "settings", "--overlay"], env=env, text=True, capture_output=True)
        assert res.returncode == 0, f"alis settings --overlay failed: {res.stdout}\n{res.stderr}"
        calls = log_file.read_text(encoding="utf-8")
        assert '"openOverlay"' in calls, f"expected ipc call settings openOverlay, got:\n{calls}"

        # Case 4: No Settings window running + presentationMode=overlay -> normal ipc settings open
        log_file.write_text("", encoding="utf-8")
        state_file.write_text("", encoding="utf-8")
        res = subprocess.run(["bash", str(ROOT / "scripts/alis"), "settings"], env=env, text=True, capture_output=True)
        assert res.returncode == 0, f"alis settings (closed) failed: {res.stdout}\n{res.stderr}"
        calls = log_file.read_text(encoding="utf-8")
        assert '"settings", "open"' in calls, f"expected ipc call settings open, got:\n{calls}"

    print("PASS: scripts/alis settings window-toggle & --overlay contract")


def test_source_contracts() -> None:
    shell_qml = (ROOT / "shell.qml").read_text(encoding="utf-8")
    assert "function _closeRunningSettingsWindow()" in shell_qml
    assert "function openOverlay(): void" in shell_qml
    assert "root._closeRunningSettingsWindow()" in shell_qml

    settings_qml = (ROOT / "settings.qml").read_text(encoding="utf-8")
    assert "function dismissFromEscape(): void" in settings_qml
    assert "id: windowStartupLoadingScreen" in settings_qml
    assert "AlisLoadingScreen" in settings_qml
    assert '"--overlay"' in settings_qml

    waffle_qml = (ROOT / "waffleSettings.qml").read_text(encoding="utf-8")
    assert 'sequence: "Escape"' in waffle_qml
    assert "root.close()" in waffle_qml
    print("PASS: shell.qml / settings.qml / waffleSettings.qml contracts")


def _run_window_harness(qml_body: str, expected_tokens: list[str], label: str) -> None:
    with tempfile.TemporaryDirectory(prefix=f"alis-settings-{label}-") as tmp:
        root = Path(tmp)
        for entry in (
            "modules",
            "services",
            "GlobalStates.qml",
            "settings.qml",
            "waffleSettings.qml",
            "qmldir",
            "assets",
            "scripts",
            "defaults",
            "translations",
        ):
            (root / entry).symlink_to(ROOT / entry)
        for kind in ("config", "state", "cache", "data"):
            (root / kind).mkdir(parents=True, exist_ok=True)
        cfg_dir = root / "config/illogical-impulse"
        cfg_dir.mkdir(parents=True, exist_ok=True)
        (cfg_dir / "config.json").write_text((ROOT / "defaults/config.json").read_text(encoding="utf-8"), encoding="utf-8")
        (root / "shell.qml").write_text(qml_body, encoding="utf-8")

        with private_wayland(root) as env:
            if env is None:
                print(f"SKIP: Quickshell runtime check ({label}: private_wayland unavailable)")
                return
            env.update(
                QT_QUICK_BACKEND="software",
                XDG_DATA_HOME="/nonexistent",
                XDG_DATA_DIRS="/nonexistent",
            )
            res = run_qs(root, env, timeout=25)
            missing = [tok for tok in expected_tokens if tok not in res.stdout]
            if (
                res.returncode != 0
                or missing
                or "SETTINGS_ESC_FAIL" in res.stdout
                or "ReferenceError:" in res.stdout
                or "TypeError:" in res.stdout
            ):
                print(f"FAIL ({label}), missing={missing}, rc={res.returncode}")
                print(res.stdout)
                sys.exit(1)
            print(f"PASS: Quickshell runtime ({label})")


def test_qml_runtime_escape_and_loading() -> None:
    if not shutil.which("qs"):
        print("SKIP: Quickshell runtime check (qs unavailable)")
        return

    # 1. Verify settings.qml startup loading screen, search clear on first Escape,
    # and clean window close (Qt.quit via onClosing) on second Escape + WWin11SettingsRailHeader signal.
    settings_harness = r'''
//@ pragma UseQApplication
import QtQuick
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.waffle.settings as WaffleSettings

Scope {
    id: harness
    property var settingsWin: null
    property int phase: 0

    Component.onCompleted: {
        const sComp = Qt.createComponent(Quickshell.shellPath("settings.qml"))
        if (sComp.status !== Component.Ready) {
            console.error("SETTINGS_ESC_FAIL: settings.qml error:", sComp.errorString())
            Qt.quit()
            return
        }
        settingsWin = sComp.createObject(harness)
        settingsWin.closing.connect(function() {
            console.info("SETTINGS_WINDOW_CLOSING_SIGNAL")
        })
    }

    Timer {
        interval: 150
        running: true
        repeat: true
        property int waitTicks: 0
        onTriggered: {
            if (!Config.ready || !Persistent.ready || !harness.settingsWin)
                return
            if (harness.phase === 0) {
                if (harness.settingsWin.uiReady !== true) {
                    waitTicks++
                    if (waitTicks > 20) {
                        console.error("SETTINGS_ESC_FAIL: settings.qml uiReady stayed false")
                        Qt.quit()
                    }
                    return
                }
                harness.settingsWin.settingsSearchText = "wallpaper"
                harness.settingsWin.dismissFromEscape()
                if (harness.settingsWin.settingsSearchText !== "") {
                    console.error("SETTINGS_ESC_FAIL: first Escape did not clear settingsSearchText")
                    Qt.quit()
                    return
                }
                console.info("SETTINGS_STAGE1_SEARCH_CLEARED")
                harness.phase = 1
                return
            }
            if (harness.phase === 1) {
                // Survived 150ms after first Escape -> first Escape did NOT close the window.
                console.info("SETTINGS_STAGE2_ALIVE_BEFORE_CLOSE")
                harness.phase = 2
                harness.settingsWin.dismissFromEscape()
                return
            }
            console.error("SETTINGS_ESC_FAIL: second Escape did not close settings.qml")
            Qt.quit()
        }
    }
}
'''
    _run_window_harness(
        settings_harness,
        ["SETTINGS_STAGE1_SEARCH_CLEARED", "SETTINGS_STAGE2_ALIVE_BEFORE_CLOSE", "SETTINGS_WINDOW_CLOSING_SIGNAL"],
        "settings-window-escape",
    )

    # 2. Verify waffleSettings.qml Escape Shortcut clears search first and closes window on second press.
    waffle_harness = r'''
//@ pragma UseQApplication
import QtQuick
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common

Scope {
    id: harness
    property var waffleWin: null
    property int phase: 0

    Component.onCompleted: {
        const wComp = Qt.createComponent(Quickshell.shellPath("waffleSettings.qml"))
        if (wComp.status !== Component.Ready) {
            console.error("SETTINGS_ESC_FAIL: waffleSettings.qml error:", wComp.errorString())
            Qt.quit()
            return
        }
        waffleWin = wComp.createObject(harness)
        waffleWin.closing.connect(function() {
            console.info("WAFFLE_WINDOW_CLOSING_SIGNAL")
        })
    }

    function findEscapeShortcut(obj) {
        const pools = [obj?.data, obj?.contentData, obj?.contentItem?.data, obj?.contentItem?.resources]
        for (let p = 0; p < pools.length; p++) {
            const list = pools[p] || []
            for (let i = 0; i < list.length; i++) {
                const it = list[i]
                if (it && it.sequence !== undefined && String(it.sequence) === "Escape")
                    return it
            }
        }
        return null
    }

    Timer {
        interval: 220
        running: true
        repeat: true
        onTriggered: {
            if (!Config.ready || !harness.waffleWin)
                return
            const sc = harness.findEscapeShortcut(harness.waffleWin)
            if (!sc) {
                console.error("SETTINGS_ESC_FAIL: Escape Shortcut not found on waffleSettings.qml")
                Qt.quit()
                return
            }
            if (harness.phase === 0) {
                console.info("WAFFLE_SHORTCUT_FOUND")
                harness.phase = 1
                sc.activated()
                return
            }
            console.error("SETTINGS_ESC_FAIL: Escape Shortcut did not close waffleSettings.qml")
            Qt.quit()
        }
    }
}
'''
    _run_window_harness(
        waffle_harness,
        ["WAFFLE_SHORTCUT_FOUND", "WAFFLE_WINDOW_CLOSING_SIGNAL"],
        "waffle-settings-escape",
    )


if __name__ == "__main__":
    test_cli_settings_toggle_and_overlay()
    test_source_contracts()
    test_qml_runtime_escape_and_loading()
