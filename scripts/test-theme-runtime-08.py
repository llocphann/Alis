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
assert 'pid=%s ppid=%s source=%s' in TRACE_HELPER
assert 'collector|qml-generator|qml-external' in TRACE_HELPER
assert 'ALIS_THEME_PROFILE_SOURCE=qml-generator' in QML
assert 'ALIS_THEME_PROFILE_SOURCE=qml-external' in QML
assert '"ALIS_THEME_PROFILE_SOURCE": "collector"' in SCRIPT.read_text()
SERVICE = (ROOT / "services/ThemeService.qml").read_text()
WALLPAPER_MARKERS = [
    "qml_switchwall_dispatch", "qml_wallpaper_request",
    "qml_fallback_picker_generator_request", "qml_backdrop_generator_request",
]
LOADER_MARKERS = [
    "qml_dark_mode_generator_request",
    "qml_scheme_variant_generator_request",
    "qml_color_invert_generator_request",
]
SERVICE_MARKERS = [
    "qml_theme_service_apply_current",
    "qml_auto_regen_request_", "qml_auto_regen_dispatch_",
]
for marker in WALLPAPER_MARKERS:
    assert marker in WALLPAPER, f"Missing wallpaper provenance marker: {marker}"
for marker in LOADER_MARKERS:
    assert marker in QML, f"Missing MaterialThemeLoader marker: {marker}"
for marker in SERVICE_MARKERS:
    assert marker in SERVICE, f"Missing ThemeService marker: {marker}"
for reason in ("live-config", "cooldown", "theme-selection"):
    assert 'regenerateAutoTheme("' + reason + '")' in SERVICE
assert '2>>"$_theme_perf_stderr"' in SHELL

values = module.parse_stages(
    "[THEME-PERF-04] scope=qml stage=qml_palette_apply ms=4.25 epoch_ms=2040\n"
    "[THEME-PERF-04] scope=applycolor stage=total ms=23 epoch_ms=2035\n"
    "[THEME-PERF-04] scope=qml stage=stale ms=55 epoch_ms=450\n"
    "[THEME-PERF-04] scope=rust stage=seed_cache_hit ms=0.11\n",
    2000, 2100, allow_untimed=False,
)
assert len(values) == 2 and values[0]["duration_ms"] == 4.25
tagged = module.parse_stages(
    "[THEME-PERF-04] scope=switchwall stage=total ms=358 epoch_ms=2040 "
    "pid=123 ppid=99 source=collector\n"
    "[THEME-PERF-04] scope=applycolor stage=total ms=945 epoch_ms=2050 "
    "pid=456 ppid=88 source=qml-external\n",
    2000, 2100, allow_untimed=False,
)
assert len(tagged) == 2
assert tagged[0]["pid"] == 123 and tagged[0]["ppid"] == 99
assert tagged[0]["source"] == "collector"
assert tagged[1]["source"] == "qml-external"
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
    assert data["run_inventory"] == []
    active = xdg_runtime / "alis-theme-perf08"
    assert not (active / "enabled").exists()
    assert not (active / "collector.lock").exists()
    assert not (active / "trace.log").exists()
    payload = report.read_text()
    assert str(home) not in payload, "report leaked private filesystem path"
    assert "palette" not in payload.lower() or "app-palette.json" not in payload

print("THEME_PERF_08_PASS no-restart controls, isolated capture, trace correlation, safe cleanup")
