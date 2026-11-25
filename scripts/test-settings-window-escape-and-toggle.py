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

    # 1. Verify settings.qml startup loading screen, real Qt.Key_Escape with Popup/ComboBox/TextField,
    # search clear, and clean window close without crashing.
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
    property var evSim: null
    property var subTf: null
    property var modalPop: null
    property var subCb: null
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
            if (harness.phase < 6) {
                console.error("SETTINGS_ESC_FAIL: settings.qml closed prematurely at phase=" + harness.phase)
            }
            console.info("SETTINGS_WINDOW_CLOSING_SIGNAL")
        })
        evSim = Qt.createQmlObject("import QtQuick; import QtTest; TestEvent {}", settingsWin.contentItem)
        subTf = Qt.createQmlObject("import QtQuick; import QtQuick.Controls; TextField { width: 120; height: 30 }", settingsWin.contentItem)
        modalPop = Qt.createQmlObject("import QtQuick; import QtQuick.Controls; Popup { width: 100; height: 100; focus: true; modal: true; closePolicy: Popup.CloseOnEscape }", settingsWin.contentItem)
        subCb = Qt.createQmlObject("import QtQuick; import QtQuick.Controls; ComboBox { width: 120; height: 30; model: [\"A\", \"B\"] }", settingsWin.contentItem)
    }

    Timer {
        interval: 160
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
                harness.settingsWin.requestActivate()
                harness.modalPop.open()
                harness.phase = 1
                return
            }
            if (harness.phase === 1) {
                // Real Escape closes open Popup, NOT the window
                Qt.callLater(() => harness.evSim.keyClick(Qt.Key_Escape, Qt.NoModifier, 0))
                harness.phase = 2
                return
            }
            if (harness.phase === 2) {
                if (harness.modalPop.opened) {
                    console.error("SETTINGS_ESC_FAIL: Escape did not close open Popup")
                    Qt.quit()
                    return
                }
                console.info("SETTINGS_STAGE_POPUP_CLOSED")
                harness.subCb.forceActiveFocus()
                harness.subCb.popup.open()
                harness.phase = 3
                return
            }
            if (harness.phase === 3) {
                // Real Escape closes open ComboBox dropdown, NOT the window
                Qt.callLater(() => harness.evSim.keyClick(Qt.Key_Escape, Qt.NoModifier, 0))
                harness.phase = 4
                return
            }
            if (harness.phase === 4) {
                if (harness.subCb.popup.opened) {
                    console.error("SETTINGS_ESC_FAIL: Escape did not close ComboBox popup")
                    Qt.quit()
                    return
                }
                console.info("SETTINGS_STAGE_COMBO_CLOSED")
                // Focus a subpage TextField -> real Escape must blur it, NOT close window
                harness.subTf.forceActiveFocus()
                Qt.callLater(() => harness.evSim.keyClick(Qt.Key_Escape, Qt.NoModifier, 0))
                harness.phase = 5
                return
            }
            if (harness.phase === 5) {
                if (harness.subTf.activeFocus) {
                    console.error("SETTINGS_ESC_FAIL: Escape did not blur focused subpage TextField")
                    Qt.quit()
                    return
                }
                console.info("SETTINGS_STAGE_TEXTFIELD_BLURRED")
                // Non-empty search cleared first without closing
                harness.settingsWin.settingsSearchText = "wallpaper"
                harness.settingsWin.dismissFromEscape()
                if (harness.settingsWin.settingsSearchText !== "") {
                    console.error("SETTINGS_ESC_FAIL: Escape did not clear settingsSearchText")
                    Qt.quit()
                    return
                }
                console.info("SETTINGS_STAGE1_SEARCH_CLEARED")
                harness.phase = 6
                return
            }
            if (harness.phase === 6) {
                // Survived all nested Escape steps; now real Escape closes the window cleanly!
                console.info("SETTINGS_STAGE2_ALIVE_BEFORE_CLOSE")
                harness.phase = 7
                Qt.callLater(() => harness.evSim.keyClick(Qt.Key_Escape, Qt.NoModifier, 0))
                return
            }
            console.error("SETTINGS_ESC_FAIL: final Escape did not close settings.qml")
            Qt.quit()
        }
    }
}
'''
    _run_window_harness(
        settings_harness,
        [
            "SETTINGS_STAGE_POPUP_CLOSED",
            "SETTINGS_STAGE_COMBO_CLOSED",
            "SETTINGS_STAGE_TEXTFIELD_BLURRED",
            "SETTINGS_STAGE1_SEARCH_CLEARED",
            "SETTINGS_STAGE2_ALIVE_BEFORE_CLOSE",
            "SETTINGS_WINDOW_CLOSING_SIGNAL",
        ],
        "settings-window-escape",
    )

    # 2. Verify waffleSettings.qml real Escape blurs subpage TextField first, then closes window cleanly.
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
    property var evSim: null
    property var subTf: null
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
            if (harness.phase < 2) {
                console.error("SETTINGS_ESC_FAIL: waffleSettings.qml closed prematurely at phase=" + harness.phase)
            }
            console.info("WAFFLE_WINDOW_CLOSING_SIGNAL")
        })
        evSim = Qt.createQmlObject("import QtQuick; import QtTest; TestEvent {}", waffleWin.contentItem)
        subTf = Qt.createQmlObject("import QtQuick; import QtQuick.Controls; TextField { width: 120; height: 30 }", waffleWin.contentItem)
    }

    Timer {
        interval: 200
        running: true
        repeat: true
        onTriggered: {
            if (!Config.ready || !harness.waffleWin)
                return
            if (harness.phase === 0) {
                harness.waffleWin.requestActivate()
                harness.subTf.forceActiveFocus()
                harness.phase = 1
                Qt.callLater(() => harness.evSim.keyClick(Qt.Key_Escape, Qt.NoModifier, 0))
                return
            }
            if (harness.phase === 1) {
                if (harness.subTf.activeFocus) {
                    console.error("SETTINGS_ESC_FAIL: waffleSettings Escape did not blur TextField")
                    Qt.quit()
                    return
                }
                console.info("WAFFLE_TEXTFIELD_BLURRED")
                harness.phase = 2
                Qt.callLater(() => harness.evSim.keyClick(Qt.Key_Escape, Qt.NoModifier, 0))
                return
            }
            console.error("SETTINGS_ESC_FAIL: final Escape did not close waffleSettings.qml")
            Qt.quit()
        }
    }
}
'''
    _run_window_harness(
        waffle_harness,
        ["WAFFLE_TEXTFIELD_BLURRED", "WAFFLE_WINDOW_CLOSING_SIGNAL"],
        "waffle-settings-escape",
    )


def test_pool_eviction_and_cold_open_gate() -> None:
    """Verify SettingsPageHost never deadlocks its 8-slot pool on >8 rapid page switches,
    and AbyssBodyHost honors _coldOpenSlideReady on frame 0 even when retainAfterFirstOpen=true.
    """
    if not shutil.which("qs"):
        print("SKIP: pool/cold-open runtime check (qs unavailable)")
        return

    with tempfile.TemporaryDirectory(prefix="alis-pool-cold-test-") as tmp:
        folder = Path(tmp)
        for entry in ("modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"):
            (folder / entry).symlink_to(ROOT / entry)
        for kind in ("config", "state", "cache"):
            (folder / kind).mkdir(parents=True)
        cfg = folder / "config/alis"
        cfg.mkdir(parents=True)
        (cfg / "config.json").write_text((ROOT / "defaults/config.json").read_text(encoding="utf-8"), encoding="utf-8")

        pages_js = []
        for i in range(10):
            (folder / f"DummyPage{i}.qml").write_text(
                f'import QtQuick\nRectangle {{ property int idx: {i}; color: "#222" }}\n',
                encoding="utf-8",
            )
            pages_js.append(f'{{ name: "P{i}", icon: "tune", component: Quickshell.shellPath("DummyPage{i}.qml") }}')

        (folder / "shell.qml").write_text(
            f'''
import QtQuick
import Quickshell
import qs
import qs.modules.abyss
import qs.modules.settings

ShellRoot {{
    id: root
    Component.onCompleted: {{
        Quickshell.watchFiles = false
        GlobalStates.deferredPanelsReady = true
    }}
    Item {{
        id: stage; width: 1000; height: 700
        SettingsPageHost {{
            id: host
            width: 600; height: 400
            pages: [{",".join(pages_js)}]
            requestedIndex: 0
            loadEnabled: true
        }}
        AbyssSurfaceController {{ id: ctrl; outputWidth: 1000; outputHeight: 700; presentationItem: stage }}
        AbyssBodyHost {{
            id: bodyHost
            anchors.fill: parent
            identity: "settings"
            edge: "bottom"
            controller: ctrl
            largeSurface: true
            showLoadingSurface: true
            retainAfterFirstOpen: true
            animatePresentation: true
            span: 680; depth: 480; along: 160
            open: false
            source: Qt.resolvedUrl("DummyPage0.qml")
        }}
    }}
    property int phase: 0
    property int ticks: 0
    Timer {{
        interval: 40; running: true; repeat: true
        onTriggered: {{
            if (root.phase === 0) {{
                // 1. Rapidly jump through 10 pages before async loaders settle -> slot pool must never deadlock
                for (let p = 0; p < 10; p++) {{
                    host.requestedIndex = p
                    host._requestPage()
                }}
                if (host._retainedIndices.length > host._slotPoolSize || host._loaderFor(9) === null) {{
                    console.error("SETTINGS_ESC_FAIL: slot pool overflowed or page 9 got no slot")
                    Qt.quit()
                    return
                }}
                // 2. Cold-open AbyssBodyHost with retainAfterFirstOpen=true must defer content.active at progress=0
                bodyHost.open = true
                if (bodyHost.openedOnce || bodyHost._coldOpenSlideReady || bodyHost.contentItem.active) {{
                    console.error("SETTINGS_ESC_FAIL: cold-open AbyssBodyHost bypassed _coldOpenSlideReady at progress="
                        + bodyHost.progress + " openedOnce=" + bodyHost.openedOnce + " active=" + bodyHost.contentItem.active)
                    Qt.quit()
                    return
                }}
                console.info("COLD_OPEN_DEFER_PASS")
                root.phase = 1
                return
            }}
            root.ticks++
            if (host.currentIndex === 9 && !host.loading && bodyHost.openedOnce && bodyHost.contentItem.status === Loader.Ready) {{
                console.info("POOL_AND_COLD_OPEN_SETTLED_PASS")
                Qt.quit()
            }} else if (root.ticks > 60) {{
                console.error("SETTINGS_ESC_FAIL: timeout currentIndex=" + host.currentIndex
                    + " loading=" + host.loading + " bodyOpenedOnce=" + bodyHost.openedOnce
                    + " bodyProgress=" + bodyHost.progress + " bodyStatus=" + bodyHost.contentItem.status)
                Qt.quit()
            }}
        }}
    }}
}}
''',
            encoding="utf-8",
        )
        env = os.environ.copy()
        for k in ("WAYLAND_DISPLAY", "DISPLAY", "QT_QUICK_BACKEND", "QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST"):
            env.pop(k, None)
        env.update(
            QT_QPA_PLATFORM="offscreen",
            XDG_CONFIG_HOME=str(folder / "config"),
            XDG_STATE_HOME=str(folder / "state"),
            XDG_CACHE_HOME=str(folder / "cache"),
        )
        res = subprocess.run(["qs", "-p", str(folder), "--no-color"], env=env, text=True, capture_output=True, timeout=20)
        log = res.stdout + res.stderr
        if (
            res.returncode != 0
            or "COLD_OPEN_DEFER_PASS" not in log
            or "POOL_AND_COLD_OPEN_SETTLED_PASS" not in log
            or "SETTINGS_ESC_FAIL" in log
        ):
            print("FAIL (pool-and-cold-open):\n" + log)
            sys.exit(1)
        print("PASS: SettingsPageHost 10-page pool eviction & AbyssBodyHost cold-open defer")


if __name__ == "__main__":
    test_cli_settings_toggle_and_overlay()
    test_source_contracts()
    test_qml_runtime_escape_and_loading()
    test_pool_eviction_and_cold_open_gate()
