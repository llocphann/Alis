#!/usr/bin/env python3
"""Offline contract and filesystem smoke test for THEME-PERF-08."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/collect-auto-theme-runtime.py"
QML = (ROOT / "services/MaterialThemeLoader.qml").read_text()
WALLPAPER = (ROOT / "services/Wallpapers.qml").read_text()
SHELL = (ROOT / "scripts/colors/switchwall.sh").read_text()
TRACE_HELPER = (ROOT / "scripts/colors/lib/theme-profile.sh").read_text()

spec = importlib.util.spec_from_file_location("theme_runtime_08", SCRIPT)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

# QML must provide a no-restart opt-in marker and propagate profiling to
# the child theme generator and external modules.
assert 'themeRuntimeEnabled: false' in QML
assert 'themeProfileControl.reload()' in QML
assert 'ALIS_THEME_PROFILE_LOG=' in QML
assert 'root.themeExternalCommand([' in QML
assert 'qml_wallpaper_request' in WALLPAPER
assert 'qml_switchwall_exited' in WALLPAPER
assert 'ALIS_THEME_PROFILE_LOG' in TRACE_HELPER
assert '2>>"$_theme_perf_stderr"' in SHELL

values = module.parse_stages(
    "[THEME-PERF-04] scope=qml stage=qml_palette_apply ms=4.25 epoch_ms=2040\n"
    "[THEME-PERF-04] scope=applycolor stage=total ms=23 epoch_ms=2035\n"
    "[THEME-PERF-04] scope=qml stage=stale ms=55 epoch_ms=450\n"
    "[THEME-PERF-04] scope=rust stage=seed_cache_hit ms=0.11\n",
    2000, 2100, allow_untimed=False,
)
assert len(values) == 2 and values[0]["duration_ms"] == 4.25
assert module.summarize(values)["qml.qml_palette_apply"]["median_ms"] == 4.25
events = [
    {"file": "colors.json", "action": "rename", "epoch_ms": 1200},
    {"file": "app-palette.json", "action": "rename", "epoch_ms": 1225},
]
assert module.first_interval(events, "colors.json", "app-palette.json") == 25
assert module.first_interval(events, "app-palette.json", "colors.json") is None

with tempfile.TemporaryDirectory(prefix="alis-runtime-perf08-test-") as folder:
    root = Path(folder)
    home = root / "home"
    xdg_runtime = root / "runtime"
    xdg_state = root / "state"
    xdg_config = root / "config"
    for directory in (home, xdg_runtime, xdg_state, xdg_config):
        directory.mkdir()
    report = root / "report.json"
    env = os.environ.copy()
    env.update({
        "HOME": str(home),
        "XDG_RUNTIME_DIR": str(xdg_runtime),
        "XDG_STATE_HOME": str(xdg_state),
        "XDG_CONFIG_HOME": str(xdg_config),
    })
    completed = subprocess.run(
        [sys.executable, str(SCRIPT), "--duration", "0.15", "--out", str(report)],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=15,
    )
    assert completed.returncode == 0, (
        f"collector failed: {completed.stderr[-600:]}"
    )
    data = json.loads(report.read_text())
    assert data["schema"] == "THEME-PERF-08-v1"
    assert data["capture_mode"] == "passive"
    assert data["qml_trace_status"] in ("UNAVAILABLE", "NO_QML_PROFILE_EVENTS")
    assert data["evidence"]["file_event_count"] == 0
    active = xdg_runtime / "alis-theme-perf08"
    assert not (active / "enabled").exists()
    assert not (active / "collector.lock").exists()
    assert not (active / "trace.log").exists()
    payload = report.read_text()
    assert str(home) not in payload, "report leaked private filesystem path"
    assert "palette" not in payload.lower() or "app-palette.json" not in payload

print("THEME_PERF_08_PASS no-restart controls, isolated capture, trace correlation, safe cleanup")
