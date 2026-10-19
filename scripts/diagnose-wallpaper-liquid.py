#!/usr/bin/env python3
"""WALL-R02: passive live shader/renderer diagnostic using existing Background IPC.

One command; while it runs, change the wallpaper twice in Alis.
No config writes, wallpaper changes, process restarts, screen recording or sudo.
The JSON contains only render statuses/counters, never image paths or raw logs.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def config_path() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or
                (Path.home() / ".config")) / "alis/config.json"


def shell_dir() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or
                (Path.home() / ".config")) / "quickshell/alis"


def get_config() -> dict:
    try:
        config = json.loads(config_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {"status": "UNAVAILABLE"}
    appearance = config.get("appearance") or {}
    bg = config.get("background") or {}
    transition = bg.get("transition") or {}
    parallax = bg.get("parallax") or {}
    perf = config.get("performance") or {}
    return {
        "status": "PASS",
        "panel_family": config.get("panelFamily"),
        "transition_type": transition.get("type"),
        "transition_enabled": transition.get("enable"),
        "transition_duration_ms": transition.get("duration"),
        "reduce_animations": perf.get("reduceAnimations"),
        "parallax_enabled": parallax.get("enable"),
        "wallpaper_hidden_by_backdrop": (bg.get("backdrop") or {}).get("hideWallpaper"),
        "has_wallpaper": bool(bg.get("wallpaperPath")),
    }


def parse_ipc(output: str) -> list[dict] | None:
    output = output.strip()
    candidates = [output]
    if "[" in output:
        candidates.append(output[output.index("["):])
    for candidate in candidates:
        try:
            value = json.loads(candidate)
            if isinstance(value, str):
                value = json.loads(value)
            if isinstance(value, list):
                return value
        except (ValueError, TypeError):
            continue
    return None


def normalize_source(value) -> str:
    src = str(value or "")
    return src.removeprefix("file://")


def sanitize(state: list[dict]) -> list[dict]:
    outputs = []
    for index, window in enumerate(state):
        if not isinstance(window, dict):
            continue
        wall = window.get("wallpaper") or {}
        configured = normalize_source(window.get("configuredPath"))
        displayed = normalize_source(wall.get("displayedSource"))
        pending = normalize_source(wall.get("pendingSource"))
        outputs.append({
            "index": index,
            "visible": window.get("visible"),
            "external": window.get("external"),
            "backdrop": window.get("backdrop"),
            "configured_matches_displayed": bool(configured and displayed and configured == displayed),
            "has_configured": bool(configured),
            "has_displayed": bool(displayed),
            "has_pending": bool(pending),
            "transitioning": wall.get("transitioning"),
            "prime_pending": wall.get("primePending"),
            "prime_swaps": wall.get("primeSwaps"),
            "shader": wall.get("shader") or "",
            "shader_requested": wall.get("shaderRequested"),
            "shader_ready": wall.get("shaderReady"),
            "shader_presented": wall.get("shaderPresented"),
            "shader_status": wall.get("shaderStatus"),
            "configured_transition": wall.get("configuredTransition"),
            "effective_type": wall.get("effectiveType"),
            "can_transition": wall.get("canTransition"),
            "graphics_api": wall.get("graphicsApi"),
            "opacity": wall.get("opacity"),
            "fallback_count": wall.get("shaderFallbackCount"),
            "success_count": wall.get("shaderSuccessCount"),
            "fallback_reason": wall.get("lastShaderFallback") or "",
            "window_visible": wall.get("windowVisible"),
            "slot0_status": wall.get("slot0Status"),
            "slot1_status": wall.get("slot1Status"),
        })
    return outputs


def ipc(binary: str, config_dir: Path, timeout: float = 2.5) -> tuple[str, list[dict]]:
    try:
        proc = subprocess.run(
            [binary, "-p", str(config_dir), "ipc", "call", "background", "wallpaperState"],
            capture_output=True, text=True, timeout=timeout,
        )
        if proc.returncode != 0:
            return "IPC_UNAVAILABLE", []
        state = parse_ipc(proc.stdout)
        return ("PASS", sanitize(state)) if state is not None else ("UNPARSEABLE", [])
    except (OSError, subprocess.TimeoutExpired):
        return "IPC_UNAVAILABLE", []


def log_evidence(binary: str, config_dir: Path) -> dict:
    try:
        proc = subprocess.run(
            [binary, "-p", str(config_dir), "log", "--rules", "*=true"],
            capture_output=True, text=True, timeout=7,
        )
        if proc.returncode:
            return {"status": "UNAVAILABLE"}
        lines = proc.stdout[-2_000_000:].splitlines()
        patterns = {
            "shader_compile_failed": re.compile(r"WallpaperCrossfader.*Shader failed", re.I),
            "transition_timed_out": re.compile(r"WallpaperCrossfader.*Transition timed out", re.I),
            "qml_binding_loop": re.compile(r"Binding loop", re.I),
            "shader_loader_error": re.compile(
                r"(Unable to load|failed to load|shader error|ShaderEffect.*error)", re.I
            ),
        }
        return {
            "status": "PASS",
            "counts": {
                name: sum(bool(pattern.search(line)) for line in lines)
                for name, pattern in patterns.items()
            },
            "note": "Counts from existing recent decoded logs, not exclusively this capture.",
        }
    except (OSError, subprocess.TimeoutExpired):
        return {"status": "UNAVAILABLE"}


def summary(frames: list[dict], cfg: dict) -> dict:
    samples = [output for frame in frames for output in frame["outputs"]]
    types = sorted({str(x["configured_transition"]) for x in samples
                    if x.get("configured_transition") is not None})
    reasons = sorted({x["fallback_reason"] for x in samples if x["fallback_reason"]})
    requested = any(x["shader_requested"] is True for x in samples)
    presented = any(x["shader_presented"] is True for x in samples)
    active_shader = any(x["shader"] == "alisMelt" for x in samples)
    max_success = max((x["success_count"] or 0 for x in samples), default=0)
    max_fallback = max((x["fallback_count"] or 0 for x in samples), default=0)
    seen_prime = any(x["prime_pending"] for x in samples)
    seen_anim = any(x["transitioning"] for x in samples)
    if types and not any(x in ("alisMelt", "inirMelt") for x in types):
        interpretation = "NOT_LIQUID_SELECTED"
    elif max_fallback > 0 and max_success == 0:
        interpretation = "FALLBACK_OBSERVED"
    elif presented or max_success > 0:
        interpretation = "LIQUID_SHADER_PRESENTED"
    elif not samples:
        interpretation = "IPC_UNAVAILABLE"
    elif not (seen_prime or seen_anim or active_shader):
        interpretation = "NO_TRANSITION_OBSERVED"
    else:
        interpretation = "SHADER_NOT_CONFIRMED"
    return {
        "interpretation": interpretation,
        "seen_types": types,
        "seen_liquid_requested": requested,
        "seen_shader_active": active_shader,
        "seen_shader_presented": presented,
        "seen_texture_prime": seen_prime,
        "seen_transition": seen_anim,
        "maximum_shader_success_count": max_success,
        "maximum_shader_fallback_count": max_fallback,
        "fallback_reasons": reasons,
        "caveat": "Counters may include earlier transitions; compare before/after "
                  "in the timeline. No screen/GPU pixel capture performed.",
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--duration", type=float, default=25.0)
    parser.add_argument("--interval", type=float, default=0.15)
    parser.add_argument("--out", help="Output JSON filename")
    args = parser.parse_args(argv)
    if not (0.5 <= args.duration <= 120 and 0.05 <= args.interval <= 2.0):
        parser.error("--duration 0.5..120 and --interval 0.05..2.0 required")
    binary = shutil.which("qs") or shutil.which("quickshell")
    if not binary:
        print("WALL-R02 requires quickshell qs command", file=sys.stderr)
        return 2
    config_dir = shell_dir()
    start = time.monotonic()
    states = []
    status_counts = {}
    print("WALL-R02: Change the wallpaper twice in Alis while sampling runs.")
    # Store changed states only, to keep the report bounded and useful.
    previous = None
    deadline = start + args.duration
    while time.monotonic() < deadline:
        status, outputs = ipc(binary, config_dir)
        status_counts[status] = status_counts.get(status, 0) + 1
        snapshot = json.dumps(outputs, sort_keys=True)
        if status == "PASS" and snapshot != previous:
            states.append({
                "elapsed_ms": round((time.monotonic() - start) * 1000),
                "outputs": outputs,
            })
            previous = snapshot
        if len(states) >= 500:
            break
        time.sleep(args.interval)
    cfg = get_config()
    result = {
        "schema": "WALL-R02-v1",
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "duration_ms": round((time.monotonic() - start) * 1000),
        "config": cfg,
        "sample_attempts": sum(status_counts.values()),
        "ipc_status_counts": status_counts,
        "timeline": states,
        "summary": summary(states, cfg),
        "existing_log_evidence": log_evidence(binary, config_dir),
        "notes": [
            "No wallpaper, configuration or service was modified.",
            "No source paths, filenames, image content or raw log lines are stored.",
            "If active Quickshell has old QML, fallback_reason/counters will be null; "
            "other existing renderer fields remain observable.",
            "The last state only is not evidence of the shader being displayed; "
            "a transition should occur during the capture.",
        ],
    }
    os.umask(0o077)
    destination = (Path(args.out).expanduser()
                   if args.out else Path(tempfile.gettempdir())
                   / f"alis-wallpaper-liquid-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print("WALL-R02 diagnostic bundle: " + str(destination))
    print("Result: " + result["summary"]["interpretation"]
          + "; sampled states: " + str(len(states)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
