#!/usr/bin/env python3
"""Regression guards for the THEME-PERF-04 isolated benchmark and opt-in traces."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / "scripts/benchmark-auto-theming.py"
RUST = (ROOT / "native/alis-theme/src/main.rs").read_text()
QML = (ROOT / "services/MaterialThemeLoader.qml").read_text()
SWITCH = (ROOT / "scripts/colors/switchwall.sh").read_text()
EXTERNAL = (ROOT / "scripts/colors/applycolor.sh").read_text()


def require(ok, message):
    if not ok:
        raise AssertionError(message)


for name in ("seed_extract", "palette_build", "output_write",
             "template_render", "sddm_sync", "total"):
    require(f"stage={name} ms=" in RUST, f"Missing Rust stage: {name}")
require('var("ALIS_THEME_PROFILE")' in RUST, "Rust timing must be opt-in")
require('Quickshell.env("ALIS_THEME_PROFILE") === "1"' in QML
        and 'themeRuntimeEnabled: false' in QML,
        "QML timing must be opt-in")
for name in ("qml_palette_apply", "qml_watch_to_loaded",
             "qml_external_debounce", "qml_external_dispatch"):
    require(f'"{name}"' in QML, f"Missing QML stage: {name}")
for name in ("native_generation", "file_publication", "total"):
    require(f"theme_perf_stage switchwall {name} " in SWITCH,
            f"Missing switchwall stage: {name}")
require("theme_perf_stage applycolor total " in EXTERNAL,
        "Missing external total marker")
require('local _theme_perf_stderr="/dev/null"' in SWITCH
        and '_theme_perf_stderr="/dev/stderr"' in SWITCH
        and '2>>"$_theme_perf_stderr"' in SWITCH,
        "Rust stderr must remain silent by default but visible when profiling")

with tempfile.TemporaryDirectory(prefix="alis-perf-test-") as scratch:
    tmp = Path(scratch)
    binary = tmp / "mock-alis-theme"
    binary.write_text(
        "#!/usr/bin/env python3\n"
        "import json,sys,pathlib\n"
        "args=sys.argv\n"
        "for idx,arg in enumerate(args[:-1]):\n"
        "  if arg.endswith('-output'):\n"
        "    path=pathlib.Path(args[idx+1]);path.parent.mkdir(parents=True,exist_ok=True)\n"
        "    path.write_text('/* offline */' if arg=='--scss-output' "
        "else json.dumps({'background':'#123456'}))\n"
        "print('[THEME-PERF-04] scope=rust stage=seed_extract ms=1.250',file=sys.stderr)\n"
        "print('[THEME-PERF-04] scope=rust stage=total ms=3.750',file=sys.stderr)\n"
    )
    binary.chmod(0o755)
    state = tmp / "state"
    state.mkdir()
    marker = state / "must-remain"
    marker.write_text("untouched")
    env = os.environ.copy()
    env["XDG_STATE_HOME"] = str(state)
    env["HOME"] = str(tmp / "home")
    report = tmp / "results.json"
    run = subprocess.run([
        sys.executable, str(BENCH), "--binary", str(binary),
        "--runs", "3", "--warmup", "1", "--report", str(report)
    ], env=env, capture_output=True, text=True, timeout=25)
    require(run.returncode == 0, f"mock benchmark failed: {run.stderr}")
    output = json.loads(report.read_text())
    require(output["mode"] == "isolated-rust", "Incorrect report mode")
    require(output["repeats"] == 3 and len(output["samples"]) == 3,
            "Incorrect sample counts")
    require(output["samples_by_stage"]["rust.total"]["count"] == 3,
            "Missing per-stage statistics")
    require(marker.read_text() == "untouched", "Benchmark mutated user state")

    log = tmp / "quickshell.log"
    log.write_text(
        "[THEME-PERF-04] scope=qml stage=qml_palette_apply ms=6.250 epoch_ms=111\n"
        "noise from unrelated module\n"
        "[THEME-PERF-04] scope=qml stage=qml_palette_apply ms=8.000 epoch_ms=222\n"
        "[THEME-PERF-04] scope=applycolor stage=total ms=15 epoch_ms=333\n"
    )
    parsed = subprocess.run([
        sys.executable, str(BENCH), "--log", str(log)
    ], capture_output=True, text=True, timeout=25)
    require(parsed.returncode == 0, f"log parse failed: {parsed.stderr}")
    analysis = json.loads(parsed.stdout)
    require(analysis["samples_by_stage"]["qml.qml_palette_apply"]["count"] == 2,
            "Log analysis lost repeated QML samples")
    require(analysis["samples_by_stage"]["applycolor.total"]["median"] == 15,
            "Log analysis lost external stage")

    invalid = subprocess.run([
        sys.executable, str(BENCH), "--binary", str(binary), "--runs", "0"
    ], capture_output=True, text=True, timeout=25)
    require(invalid.returncode != 0, "Invalid sample count must fail closed")

print("THEME_PERF_04_PASS isolated benchmark, log parser, opt-in guards, unchanged local state")
