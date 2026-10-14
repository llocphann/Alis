#!/usr/bin/env python3
"""Optional installation discovery and real core-only QML boot; no live session."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("discovery", ROOT / "scripts/hadanion-status.py")
discovery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(discovery)

with tempfile.TemporaryDirectory(prefix="hadanion-absent-") as temporary:
    private = Path(temporary)
    data = private / "data"
    assert discovery.inspect(private, data)["available"] is False
    package = private / "optional/hadanion"
    package.mkdir(parents=True)
    manifest = {"id": "hadanion", "hostApi": 1, "version": "fixture", **discovery.ENTRYPOINTS}
    for name in discovery.ENTRYPOINTS.values():
        p = package / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("fixture")
    (package / manifest["binary"]).chmod(0o755)
    (package / "manifest.json").write_text(json.dumps(manifest))
    assert discovery.inspect(private, data)["available"] is True
    for field, value in (("hostApi", 2), ("hostApi", True), ("id", "other"), ("session", "../../foreign.qml")):
        (package / "manifest.json").write_text(json.dumps({**manifest, field: value}))
        assert discovery.inspect(private, data)["available"] is False
    (package / "manifest.json").write_text("{}" * 9000)
    assert discovery.inspect(private, data)["available"] is False
    shutil.rmtree(private / "optional")
    data_package = data / "hadanion/releases/fixture"
    data_package.mkdir(parents=True)
    for name in discovery.ENTRYPOINTS.values():
        p = data_package / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("fixture")
    (data_package / manifest["binary"]).chmod(0o755)
    (data_package / "manifest.json").write_text(json.dumps(manifest))
    (data / "hadanion/current").symlink_to("releases/fixture")
    result = discovery.inspect(private, data)
    assert result["available"] and result["root"] == str(data_package.resolve())
    (data / "hadanion/current").unlink()
    assert discovery.inspect(private, data)["available"] is False

    qs = shutil.which("qs") or shutil.which("quickshell")
    assert qs and shutil.which("dbus-run-session"), "Quickshell and dbus-run-session are required"
    shell = private / "shell"
    shell.mkdir()
    for name in ("modules", "services", "scripts", "defaults", "translations", "assets", "qmldir", "GlobalStates.qml"):
        (shell / name).symlink_to(ROOT / name)
    config = private / "config/alis"
    config.mkdir(parents=True)
    options = json.loads((ROOT / "defaults/config.json").read_text())
    options["panelFamily"] = "abyss"
    options["enabledPanels"] = []
    options["abyss"]["companion"]["enabled"] = True  # a preserved old selection must fail closed when absent
    (config / "config.json").write_text(json.dumps(options))
    runtime = private / "runtime"
    runtime.mkdir(mode=0o700)
    fake = private / "never-start"
    marker = private / "started"
    fake.write_text("#!/usr/bin/python3\nfrom pathlib import Path\nPath(" + repr(str(marker)) + ").write_text('started')\n")
    fake.chmod(0o755)
    (shell / "shell.qml").write_text('''
import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.abyss
import qs.modules.settings
ShellRoot {
    id: root
    property int ticks: 0
    property var preferencesSnapshot: Config.options
    property var loadedOptions: Config.options
    property var optionalHost: Hadanion
    property var stubHost: ({outputName:"fixture"})
    HadanionSurface {
        host: root.stubHost
        hostLiquid: null; hostField: null; hostBar: null
        hostLeftPanel: null; hostRightPanel: null; hostCorners: null
        hostUtility: null; hostBarHover: null; hostRevealHover: null
    }
    CompanionConfig { width: 400; height: 300 }
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            ++root.ticks
            if (root.ticks < 20 || !Config.ready) return
            if (Hadanion.available || Hadanion.enabled || Hadanion.session !== null
                    || !Config.options.abyss.companion.enabled)
                {console.log("HADANION_ABSENT=FAIL");Qt.quit();return}
            Hadanion.chat()
            const state=JSON.parse(Hadanion.status())
            if (state.backend.ready || state.sessionVisible)
                {console.log("HADANION_ABSENT=FAIL");Qt.quit();return}
            for (const surface of Hadanion.outputs) {
                if (surface.extension !== null || surface.inputRegions.length
                        || surface.editing || surface.dockHeld || surface.waterLink !== null)
                    {console.log("HADANION_ABSENT=FAIL");Qt.quit();return}
            }
            console.log("HADANION_ABSENT=PASS")
            Qt.quit()
        }
    }
}
''')
    env = os.environ.copy()
    for name in ("NIRI_SOCKET", "HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY", "DISPLAY", "DBUS_SESSION_BUS_ADDRESS"):
        env.pop(name, None)
    env.update(QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QT_QUICK_CONTROLS_STYLE="Basic",
               XDG_CONFIG_HOME=str(private / "config"), XDG_DATA_HOME=str(data), XDG_RUNTIME_DIR=str(runtime),
               XDG_STATE_HOME=str(private / "state"), XDG_CACHE_HOME=str(private / "cache"),
               INIR_COMPANIOND=str(fake), INIR_GGUF_ROOTS="[]", QT_QPA_PLATFORMTHEME="generic")
    process = subprocess.Popen(["dbus-run-session", "--", qs, "--path", str(shell / "shell.qml")],
                               env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True)
    try:
        try:
            output, _ = process.communicate(timeout=25)
        except subprocess.TimeoutExpired as error:
            raise AssertionError(str(error.output)[-8000:]) from error
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=5)
    errors = ("ReferenceError:", "TypeError:", "Unable to assign", "Binding loop", "Failed to load configuration", "is not a type")
    assert process.returncode == 0 and "HADANION_ABSENT=PASS" in output and not any(e in output for e in errors), output[-12000:]
    assert not marker.exists(), "an inherited native override started without the optional package"

print("PASS: absent/incompatible/uninstalled discovery, preserved preference and actual core-only optional host boot/input")
