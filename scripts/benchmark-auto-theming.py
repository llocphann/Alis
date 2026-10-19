#!/usr/bin/env python3
"""THEME-PERF-04: isolated Rust palette benchmark and opt-in runtime trace analysis.

Default mode does not modify the active wallpaper, settings, SDDM, app themes,
Quickshell, or generated files. All generator outputs live in a temporary dir.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import resource
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
MARKER = re.compile(
    r"\[THEME-PERF-04\]\s+scope=([a-z0-9_-]+)\s+stage=([a-zA-Z0-9_-]+)"
    r"\s+ms=([0-9]+(?:\.[0-9]+)?)"
)
OUTPUTS = ("json", "palette", "app-palette", "terminal", "meta", "scss")


def percentiles(values: list[float]) -> dict[str, float]:
    if not values:
        raise ValueError("No samples")
    ordered = sorted(values)
    p95 = ordered[max(0, (95 * len(ordered) + 99) // 100 - 1)]
    return {
        "min": round(ordered[0], 3),
        "median": round(statistics.median(ordered), 3),
        "p95": round(p95, 3),
        "max": round(ordered[-1], 3),
    }


def measurements(lines) -> dict[str, list[float]]:
    result: dict[str, list[float]] = {}
    for line in lines:
        match = MARKER.search(line)
        if match:
            scope, stage, millis = match.groups()
            result.setdefault(f"{scope}.{stage}", []).append(float(millis))
    return result


def summarize_metrics(metrics: dict[str, list[float]]) -> dict:
    return {
        stage: {"count": len(samples), **percentiles(samples)}
        for stage, samples in sorted(metrics.items())
        if samples
    }


def runtime_log(path: Path) -> dict:
    if not path.is_file():
        raise ValueError("Log file does not exist")
    # Bound memory for logs that have accumulated over many desktop sessions.
    with path.open("rb") as log:
        log.seek(0, os.SEEK_END)
        size = log.tell()
        log.seek(max(0, size - 8_000_000))
        if size > 8_000_000:
            log.readline()
        lines = (line.decode("utf-8", "replace") for line in log)
        metrics = measurements(lines)
    return {
        "schema": "alis-theme-perf-04-v1",
        "mode": "runtime-log-analysis",
        "samples_by_stage": summarize_metrics(metrics),
        "note": "Stage durations are independent observations, not end-to-end latency; "
                "live Quickshell and external targets may overlap.",
    }


def choose_binary(value: str | None) -> Path:
    if value:
        candidate = Path(value).expanduser().resolve()
    else:
        root = os.environ.get("ALIS_NATIVE_BIN_DIR")
        candidate = (Path(root) / "alis-theme") if root else ROOT / "native/target/release/alis-theme"
    if not candidate.is_file() or not os.access(candidate, os.X_OK):
        raise ValueError(
            "Rust alis-theme binary unavailable. Build with: "
            "cargo build --release --manifest-path native/Cargo.toml -p alis-theme "
            "(or pass --binary PATH)"
        )
    return candidate


def isolated_benchmark(args) -> dict:
    binary = choose_binary(args.binary)
    if args.runs < 1 or args.runs > 100 or args.warmup < 0 or args.warmup > 20:
        raise ValueError("--runs must be 1..100 and --warmup must be 0..20")
    image = Path(args.image).expanduser().resolve() if args.image else None
    if image and not image.is_file():
        raise ValueError("The specified image is not a readable file")
    env = os.environ.copy()
    env["ALIS_THEME_PROFILE"] = "1"
    env["ALIS_THEME_SKIP_SDDM_SYNC"] = "1"

    samples: list[dict] = []
    stage_samples: dict[str, list[float]] = {}
    with tempfile.TemporaryDirectory(prefix="alis-theme-perf04-") as tmp:
        for i in range(args.runs + args.warmup):
            work = Path(tmp) / f"sample-{i}"
            work.mkdir()
            command = [
                str(binary), "--mode", args.mode, "--scheme", args.scheme,
                *(
                    ["--path", str(image)] if image
                    else ["--color", args.color]
                ),
            ]
            for name in OUTPUTS:
                destination = work / (name + (".scss" if name == "scss" else ".json"))
                option = "--" + name + "-output"
                command.extend((option, str(destination)))
            before = resource.getrusage(resource.RUSAGE_CHILDREN)
            start_ns = time.monotonic_ns()
            completed = subprocess.run(
                command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                env=env, check=False, timeout=args.timeout, text=True,
            )
            elapsed_ms = (time.monotonic_ns() - start_ns) / 1_000_000
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            if completed.returncode:
                message = (completed.stderr or "").strip()[:1200]
                if image:
                    message = message.replace(str(image), "<selected-image>")
                raise ValueError(f"Rust generator exited {completed.returncode}: {message}")
            for name in OUTPUTS:
                out = work / (name + (".scss" if name == "scss" else ".json"))
                if not out.is_file() or out.stat().st_size == 0:
                    raise ValueError(f"Missing or empty isolated output: {name}")
                if name != "scss":
                    with out.open(encoding="utf-8") as f:
                        json.load(f)
            if i < args.warmup:
                continue
            metrics = measurements(completed.stderr.splitlines())
            for stage, values in metrics.items():
                stage_samples.setdefault(stage, []).extend(values)
            samples.append({
                "wall_ms": round(elapsed_ms, 3),
                "cpu_ms": round(
                    ((after.ru_utime - before.ru_utime)
                     + (after.ru_stime - before.ru_stime)) * 1000, 3
                ),
                "stages_ms": {key: values[-1] for key, values in metrics.items()},
            })
    return {
        "schema": "alis-theme-perf-04-v1",
        "mode": "isolated-rust",
        "source_kind": "image" if image else "color",
        "repeats": len(samples),
        "warmup": args.warmup,
        "wall_ms": percentiles([s["wall_ms"] for s in samples]),
        "cpu_ms": percentiles([s["cpu_ms"] for s in samples]),
        "samples_by_stage": summarize_metrics(stage_samples),
        "samples": samples,
        "safety": "No --render-templates, no active state, no app integrations, "
                  "no SDDM; isolated temp outputs removed after each run.",
        "limitation": "Not a measurement of wallpaper-to-QML latency or external "
                      "integration completion; use opt-in runtime trace separately.",
    }


def cli(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--image", help="Wallpaper file to benchmark (read-only)")
    group.add_argument("--log", help="Existing runtime log file to summarize, without running generators")
    parser.add_argument("--color", default="#6489ab", help="Seed when --image is not provided")
    parser.add_argument("--mode", choices=("dark", "light"), default="dark")
    parser.add_argument("--scheme", default="auto")
    parser.add_argument("--runs", type=int, default=7)
    parser.add_argument("--warmup", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument("--binary", help="Path to compiled Rust alis-theme")
    parser.add_argument("--report", help="Optional JSON report destination")
    args = parser.parse_args(argv)
    try:
        if args.log:
            result = runtime_log(Path(args.log).expanduser())
        else:
            if args.timeout <= 0:
                raise ValueError("--timeout must be greater than zero")
            result = isolated_benchmark(args)
    except (ValueError, OSError, subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
        print(f"THEME-PERF-04: {exc}", file=sys.stderr)
        return 2
    output = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.report:
        dest = Path(args.report).expanduser()
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(output, encoding="utf-8")
        print(f"THEME-PERF-04 report: {dest}")
    else:
        print(output, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(cli())
