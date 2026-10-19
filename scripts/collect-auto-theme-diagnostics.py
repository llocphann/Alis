#!/usr/bin/env python3
"""THEME-PERF-05: collect a single, shareable Auto Theming diagnostic JSON.

Run from the Alis dev checkout:
  python3 scripts/collect-auto-theme-diagnostics.py

All automated generation is sandboxed in temporary directories. Never starts,
kills or restarts Quickshell, applies apps, updates SDDM, or changes wallpapers.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import resource
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
THEME_RE = re.compile(
    r"\[THEME-PERF-04\]\s+scope=([a-z0-9_-]+)\s+stage=([a-zA-Z0-9_-]+)"
    r"\s+ms=([0-9]+(?:\.[0-9]+)?)"
)
OUTPUTS = ("json", "palette", "app-palette", "terminal", "meta", "scss")
SUITE_VERSION = "THEME-PERF-05-v1"
DEFAULT_TESTS = (
    ("file_publication", ["bash", "scripts/test-theme-file-publication.sh"]),
    ("cava_contract", [sys.executable, "scripts/test-cava-cover-color-refresh-contract.py"]),
    ("forced_dark_contract", [sys.executable, "scripts/test-forced-dark-seed-reuse.py"]),
    ("sddm_contract", [sys.executable, "scripts/test-theme-sddm-deferral.py"]),
    ("profiler_contract", [sys.executable, "scripts/test-theme-perf-04.py"]),
    ("loader_lifecycle", ["bash", "scripts/test-material-theme-loader-lifecycle.sh"]),
    ("liquid_deferral", [sys.executable, "scripts/test-wallpaper-liquid-theme-deferral.py"]),
    ("preview_cache", [sys.executable, "scripts/test-wallpaper-preview-palette-cache.py"]),
)


def quantiles(samples: list[float]) -> dict:
    samples = sorted(samples)
    if not samples:
        return {}
    return {
        "count": len(samples),
        "min_ms": round(samples[0], 3),
        "median_ms": round(statistics.median(samples), 3),
        "p95_ms": round(samples[max(0, (95 * len(samples) + 99) // 100 - 1)], 3),
        "max_ms": round(samples[-1], 3),
    }


def metrics_of(text: str) -> dict[str, float]:
    return {
        f"{scope}.{stage}": float(ms)
        for scope, stage, ms in THEME_RE.findall(text)
    }


def sanitized_error(text: str, image: Path | None = None) -> str:
    text = text.strip()[-700:]
    if image is not None:
        text = text.replace(str(image), "[source-image]")
    text = text.replace(str(Path.home()), "~")
    return re.sub(r"/tmp/[^\s'\"]+", "[temporary-path]", text)


def get_config() -> tuple[dict, dict]:
    state = Path(os.getenv("XDG_STATE_HOME") or (Path.home() / ".local/state"))
    config_root = Path(os.getenv("XDG_CONFIG_HOME") or (Path.home() / ".config"))
    config_file = config_root / "alis/config.json"
    meta_file = state / "quickshell/user/generated/theme-meta.json"
    try:
        config = json.loads(config_file.read_text())
    except (OSError, ValueError):
        config = {}
    try:
        meta = json.loads(meta_file.read_text())
    except (OSError, ValueError):
        meta = {}
    return config, meta


def walk(data: dict, *keys, default=None):
    current = data
    for key in keys:
        if not isinstance(current, dict):
            return default
        current = current.get(key)
    return default if current is None else current


def source_image(override: str | None, config: dict, meta: dict) -> Path | None:
    candidates = []
    if override:
        candidates = [override]
    else:
        # The most recent material generator's source is our best representation
        # of the real image used in the installed desktop session.
        if meta.get("source") == "image":
            candidates.append(meta.get("source_path"))
        family = config.get("panelFamily") or "ii"
        main = walk(config, "background", "wallpaperPath")
        if family == "waffle":
            main = (main if walk(config, "waffles", "background",
                                 "useMainWallpaper", default=True)
                    else walk(config, "waffles", "background", "wallpaperPath")) or main
        if walk(config, "appearance", "wallpaperTheming",
                "useBackdropForColors", default=False):
            if family == "waffle":
                candidates.append(walk(config, "waffles", "background", "backdrop", "wallpaperPath"))
            else:
                candidates.append(walk(config, "background", "backdrop", "wallpaperPath"))
        candidates.append(main)
    for raw in candidates:
        if not isinstance(raw, str) or not raw:
            continue
        raw = raw[7:] if raw.startswith("file://") else raw
        path = Path(raw).expanduser()
        if path.is_file():
            return path.resolve()
    return None


def locate_binary(explicit: str | None) -> tuple[Path | None, dict]:
    info = {}
    dispatcher = ROOT / "scripts/native-dispatch"
    if dispatcher.is_file():
        try:
            proc = subprocess.run(
                ["bash", str(dispatcher), "backend-info"],
                cwd=ROOT, text=True, capture_output=True, timeout=8,
            )
            if proc.returncode == 0:
                info = dict(line.split("=", 1) for line in proc.stdout.splitlines()
                            if "=" in line)
        except (OSError, subprocess.TimeoutExpired):
            pass
    options = []
    if explicit:
        options.append(Path(explicit).expanduser())
    elif os.getenv("ALIS_NATIVE_BIN_DIR"):
        options.append(Path(os.environ["ALIS_NATIVE_BIN_DIR"]) / "alis-theme")
    if not explicit:
        if info.get("bin_dir"):
            options.append(Path(info["bin_dir"]) / "alis-theme")
        options.extend((ROOT / "native/target/release/alis-theme",
                        ROOT / "native/bin/alis-theme"))
    for candidate in options:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate.resolve(), {
                "mode": info.get("mode", "unknown"),
                "alis_theme": info.get("alis-theme", "unknown"),
                "found": True,
            }
    return None, {
        "mode": info.get("mode", "unknown"),
        "alis_theme": info.get("alis-theme", "missing"),
        "found": False,
    }


def run_generator(binary: Path, work: Path, *, image: Path | None = None,
                  color: str = "#6489ab", size: int = 128, mode: str = "dark",
                  scheme: str = "auto", flags: tuple[str, ...] = (),
                  template_dir: Path | None = None, timeout: int = 45,
                  seed_cache_home: Path | None = None,
                  seed_cache_enabled: bool = True) -> dict:
    work.mkdir(parents=True, exist_ok=True)
    command = [
        str(binary), "--mode", mode, "--scheme", scheme,
        "--size", str(size),
        *(["--path", str(image)] if image else ["--color", color]),
        *flags,
    ]
    files = {}
    for name in OUTPUTS:
        path = work / (name + (".scss" if name == "scss" else ".json"))
        files[name] = path
        command += ["--" + name + "-output", str(path)]
    if template_dir is not None:
        command += ["--render-templates", str(template_dir)]
    env = os.environ.copy()
    env.update({
        "ALIS_THEME_PROFILE": "1",
        "ALIS_THEME_SKIP_SDDM_SYNC": "1",
        "HOME": str(work / "home"),
        "XDG_CONFIG_HOME": str(work / "config"),
        "XDG_STATE_HOME": str(work / "state"),
        "XDG_CACHE_HOME": str(seed_cache_home or (work / "cache")),
        "ALIS_THEME_SEED_CACHE": "1" if seed_cache_enabled else "0",
    })
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    started = time.perf_counter_ns()
    try:
        proc = subprocess.run(command, env=env, cwd=ROOT,
                              stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                              text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "timeout"}
    wall = (time.perf_counter_ns() - started) / 1_000_000
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    if proc.returncode != 0:
        return {"ok": False, "error": "generator_failed",
                "exit_code": proc.returncode,
                "details": sanitized_error(proc.stderr, image)}
    try:
        data = {}
        for name, path in files.items():
            if not path.is_file() or path.stat().st_size == 0:
                raise ValueError("missing_output:" + name)
            data[name] = path.read_text() if name == "scss" else json.loads(path.read_text())
    except (OSError, ValueError) as exc:
        return {"ok": False, "error": str(exc)}
    return {
        "ok": True,
        "wall_ms": round(wall, 3),
        "cpu_ms": round(((after.ru_utime - before.ru_utime)
                          + (after.ru_stime - before.ru_stime)) * 1000, 3),
        "stages_ms": metrics_of(proc.stderr),
        "data": data,
    }


def repeats(binary, tmp, n, warmup, **kwargs) -> dict:
    rows = []
    for i in range(n + warmup):
        result = run_generator(binary, tmp / f"run-{i}", **kwargs)
        if not result["ok"]:
            return {"status": "FAIL", "error": result.get("error"),
                    "details": result.get("details", "")}
        if i >= warmup:
            rows.append(result)
    stage_keys = sorted({stage for row in rows for stage in row["stages_ms"]})
    return {
        "status": "PASS",
        "wall": quantiles([r["wall_ms"] for r in rows]),
        "cpu": quantiles([r["cpu_ms"] for r in rows]),
        "stages": {
            stage: quantiles([r["stages_ms"][stage] for r in rows
                              if stage in r["stages_ms"]])
            for stage in stage_keys
        },
    }


def terminal_cfg() -> dict:
    state = Path(os.getenv("XDG_STATE_HOME") or (Path.home() / ".local/state"))
    generated = state / "quickshell/user/generated"
    assets = {}
    for name in ("colors.json", "palette.json", "app-palette.json",
                 "terminal.json", "theme-meta.json", "material_colors.scss"):
        path = generated / name
        if path.is_file():
            stat = path.stat()
            assets[name] = {
                "exists": True, "bytes": stat.st_size,
                "age_seconds": max(0, round(time.time() - stat.st_mtime)),
            }
        else:
            assets[name] = {"exists": False}
    return assets


def sanitized_system() -> dict:
    cpu = None
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name"):
                cpu = line.partition(":")[2].strip()
                break
    except OSError:
        pass
    try:
        from os import sysconf
        memory_gib = round(
            sysconf("SC_PAGE_SIZE") * sysconf("SC_PHYS_PAGES") / 1024 ** 3, 1
        )
    except (ValueError, OSError, AttributeError):
        memory_gib = None
    return {
        "platform": platform.system(),
        "kernel": platform.release(),
        "architecture": platform.machine(),
        "cpu_model": cpu,
        "logical_cpus": os.cpu_count(),
        "ram_gib": memory_gib,
    }


def git_short_sha():
    result = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True,
                            capture_output=True, timeout=5, check=False)
    return result.stdout.strip() if result.returncode == 0 else "unavailable"


def test_runner(binary: Path | None, image: Path | None, *, parity: bool) -> dict:
    checks = list(DEFAULT_TESTS)
    for file in ("scripts/colors/switchwall.sh",
                 "scripts/colors/applycolor.sh",
                 "scripts/colors/lib/theme-profile.sh"):
        checks.append(("shell_syntax_" + Path(file).stem, ["bash", "-n", file]))
    checks.append(("diag_source_compile", [
        sys.executable, "-c",
        "import ast,pathlib; ast.parse(pathlib.Path('scripts/collect-auto-theme-diagnostics.py').read_text())",
    ]))
    if binary is not None:
        checks.append(("seed_cache_integration", [
            sys.executable, "scripts/test-theme-seed-cache.py", str(binary)
        ]))
    if parity and binary is not None:
        checks.append(("rust_python_template_parity", [
            sys.executable, "native/scripts/check-theme-parity.py", str(binary)
        ]))
    results = {}
    for name, command in checks:
        t0 = time.perf_counter()
        try:
            proc = subprocess.run(command, cwd=ROOT, text=True,
                                  capture_output=True, timeout=120)
            status = "PASS" if proc.returncode == 0 else "FAIL"
            combined = proc.stderr + "\n" + proc.stdout
            if name in ("preview_cache", "rust_python_template_parity") and status == "FAIL":
                if ("No module named" in combined
                        or "no Python interpreter with" in combined):
                    status = "SKIP_DEPENDENCY"
            results[name] = {
                "status": status, "duration_ms": round(
                    (time.perf_counter() - t0) * 1000, 2),
            }
            if status not in ("PASS",):
                results[name]["reason"] = (
                    "missing_optional_dependency" if status == "SKIP_DEPENDENCY"
                    else "nonzero_exit"
                )
        except (subprocess.TimeoutExpired, OSError):
            results[name] = {"status": "FAIL", "reason": "timeout_or_spawn_error"}
    return results


def test_reuse_parity(binary: Path, tmp: Path, image: Path) -> dict:
    scenarios = (
        ("dark_auto", "dark", ()),
        ("light_auto", "light", ()),
        ("dark_inverted", "dark", ("--invert-hue",)),
        ("dark_softened", "dark", ("--soften",)),
        ("dark_weak_strength", "dark", ("--color-strength", "0.75")),
        ("dark_smart", "dark", ("--smart",)),
    )
    compared = ("json", "palette", "app-palette", "terminal", "scss")
    results = {}
    for name, mode, flags in scenarios:
        image_run = run_generator(
            binary, tmp / name / "image", image=image,
            mode=mode, scheme="auto", flags=flags,
        )
        if not image_run["ok"]:
            results[name] = {"status": "FAIL", "reason": image_run.get("error")}
            continue
        metadata = image_run["data"]["meta"]
        seed = metadata.get("seed_color")
        resolved_scheme = metadata.get("scheme")
        if not isinstance(seed, str) or not isinstance(resolved_scheme, str):
            results[name] = {"status": "FAIL", "reason": "missing_seed_metadata"}
            continue
        direct = run_generator(
            binary, tmp / name / "cached", color=seed,
            mode=mode, scheme=resolved_scheme, flags=flags,
        )
        if not direct["ok"]:
            results[name] = {"status": "FAIL", "reason": direct.get("error")}
            continue
        mismatch = [x for x in compared
                    if image_run["data"][x] != direct["data"][x]]
        results[name] = {
            "status": "PASS" if not mismatch else "FAIL",
            "mismatched_outputs": mismatch,
            "image_wall_ms": image_run["wall_ms"],
            "seed_reuse_wall_ms": direct["wall_ms"],
            "potential_saving_ms": round(
                image_run["wall_ms"] - direct["wall_ms"], 3),
            "scheme": resolved_scheme,
        }
    return results


def template_fixture(path: Path, count: int):
    templates = path / "templates"
    templates.mkdir(parents=True)
    entries = []
    for i in range(count):
        name = f"fixture-{i}"
        (templates / f"{name}.txt").write_text(
            "primary={{colors.primary.default.hex}}\n"
            "surface={{colors.surface.default.hex}}\n"
        )
        entries.append({
            "name": name, "input": f"{name}.txt",
            "output": str(path / "outputs" / f"{name}.txt"),
        })
    (path / "templates.json").write_text(json.dumps({"templates": entries}))


def template_benchmark(binary: Path, tmp: Path, image: Path, n: int) -> dict:
    matrix = {}
    for count in (0, 1, 8, 24):
        fixture = tmp / f"templates-{count}"
        if count:
            template_fixture(fixture, count)
        matrix[str(count)] = repeats(
            binary, tmp / f"runs-{count}", n, 1, image=image,
            mode="dark", scheme="auto",
            template_dir=fixture if count else None,
        )
    return matrix


def seed_cache_benchmark(binary: Path, tmp: Path, image: Path) -> dict:
    # Cache output stays in this private fixture; no installed cache changes.
    shared_cache = tmp / "seed-cache"
    cold = run_generator(binary, tmp / "cache-cold",
                         image=image, seed_cache_home=shared_cache)
    warm = run_generator(binary, tmp / "cache-warm",
                         image=image, seed_cache_home=shared_cache)
    bypass = run_generator(binary, tmp / "cache-disabled",
                           image=image, seed_cache_home=shared_cache,
                           seed_cache_enabled=False)
    if not all(x["ok"] for x in (cold, warm, bypass)):
        return {
            "status": "FAIL",
            "reason": "cache_generation_failed",
        }
    same = all(cold["data"][key] == warm["data"][key] == bypass["data"][key]
               for key in ("json", "palette", "app-palette", "terminal",
                           "meta", "scss"))
    hit = "rust.seed_cache_hit" in warm["stages_ms"]
    miss = "rust.seed_cache_miss" in cold["stages_ms"]
    return {
        "status": "PASS" if same and hit and miss else "FAIL",
        "identical_outputs": same,
        "confirmed_hit": hit,
        "confirmed_miss": miss,
        "cold_wall_ms": cold["wall_ms"],
        "warm_wall_ms": warm["wall_ms"],
        "disabled_wall_ms": bypass["wall_ms"],
        "potential_saving_ms": round(bypass["wall_ms"] - warm["wall_ms"], 3),
        "note": "Isolated sequential scenario; not live wallpaper-to-frame latency.",
    }


def image_size_matrix(binary: Path, tmp: Path, image: Path, n: int) -> dict:
    results = {}
    for size in (64, 96, 128, 192, 256):
        single = run_generator(binary, tmp / str(size) / "meta",
                               image=image, size=size, scheme="auto")
        timing = repeats(binary, tmp / str(size) / "timing", n, 1,
                         image=image, size=size, scheme="auto")
        entry = {
            "status": "PASS" if single["ok"] else "FAIL",
            "timing": timing,
        }
        if single["ok"]:
            entry["seed"] = single["data"]["meta"].get("seed_color")
            entry["scheme"] = single["data"]["meta"].get("scheme")
        else:
            entry["reason"] = single.get("error")
        results[str(size)] = entry
    return results


def runtime_log_summary(path: Path | None) -> dict:
    if path is None:
        return {
            "status": "NOT_COLLECTED",
            "reason": "No running-shell trace supplied. Existing Quickshell must "
                      "have ALIS_THEME_PROFILE=1 at startup to emit QML stages.",
        }
    try:
        with path.open("rb") as log:
            log.seek(0, os.SEEK_END)
            total_size = log.tell()
            log.seek(max(0, total_size - 8_000_000))
            if total_size > 8_000_000:
                log.readline()
            metrics: dict[str, list[float]] = {}
            for raw in log:
                decoded = raw.decode("utf-8", "replace")
                for scope, stage, ms in THEME_RE.findall(decoded):
                    metrics.setdefault(f"{scope}.{stage}", []).append(float(ms))
        return {
            "status": "PASS" if metrics else "NO_PROFILE_EVENTS",
            "last_bytes_scanned": min(total_size, 8_000_000),
            "stages": {name: quantiles(values)
                       for name, values in sorted(metrics.items())},
        }
    except OSError:
        return {"status": "FAIL", "reason": "runtime_log_not_readable"}


def collect(args) -> dict:
    config, meta = get_config()
    image = source_image(args.image, config, meta)
    binary, backend = locate_binary(args.binary)
    report = {
        "schema": SUITE_VERSION,
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "git_sha": git_short_sha(),
        "system": sanitized_system(),
        "backend": backend,
        "source": {
            "available": image is not None,
            "from": "explicit" if args.image else "auto",
            "size_bytes": image.stat().st_size if image else None,
            "suffix": image.suffix.lower() if image else None,
            "path_included": False,
        },
        "config": {
            "auto_theme": walk(config, "appearance", "theme") == "auto",
            "palette_type": walk(config, "appearance", "palette", "type"),
            "panel_family": config.get("panelFamily"),
            "forced_dark_terminal": walk(
                config, "appearance", "wallpaperTheming",
                "terminalGenerationProps", "forceDarkMode"),
            "apps_and_shell_enabled": walk(
                config, "appearance", "wallpaperTheming", "enableAppsAndShell"),
            "terminal_enabled": walk(
                config, "appearance", "wallpaperTheming", "enableTerminal"),
        },
        "generated_outputs": terminal_cfg(),
        "runtime_log": runtime_log_summary(
            Path(args.runtime_log).expanduser() if args.runtime_log else None
        ),
        "tests": test_runner(binary, image, parity=not args.no_parity),
        "benchmarks": {},
        "notes": [],
    }
    if not binary:
        report["notes"].append("Rust binary missing; isolated performance tests skipped.")
        return report
    if image is None:
        report["notes"].append(
            "No valid current image; provide --image PATH for an image-specific profile."
        )
    if image and image.stat().st_size > args.max_image_mb * 1024 * 1024:
        report["notes"].append("Image exceeds size limit; image tests skipped.")
        image = None
    with tempfile.TemporaryDirectory(prefix="alis-theme-diagnostics-") as tmpdir:
        tmp = Path(tmpdir)
        report["benchmarks"]["fixed_seed"] = repeats(
            binary, tmp / "fixed-seed", args.runs, args.warmup,
            scheme="scheme-tonal-spot",
        )
        if image:
            report["benchmarks"]["baseline"] = repeats(
                binary, tmp / "baseline", args.runs, args.warmup,
                image=image, mode="dark", scheme="auto",
            )
            report["benchmarks"]["size_matrix"] = image_size_matrix(
                binary, tmp / "size-matrix", image, args.matrix_runs,
            )
            report["benchmarks"]["production_seed_cache"] = seed_cache_benchmark(
                binary, tmp / "production-seed-cache", image,
            )
            report["benchmarks"]["seed_reuse_parity"] = test_reuse_parity(
                binary, tmp / "seed-reuse-parity", image,
            )
            report["benchmarks"]["template_matrix"] = template_benchmark(
                binary, tmp / "template-matrix", image, args.matrix_runs,
            )
    report["notes"].extend((
        "All generator benchmarks were isolated: only disposable temporary outputs.",
        "Seed reuse savings are upper-bound opportunities, not production speedups.",
        "No Quickshell/SDDM/app actions executed; live click-to-frame latency "
        "requires separate controlled session instrumentation.",
    ))
    return report


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", help="Optional explicit wallpaper; normally auto-detected")
    parser.add_argument("--binary", help="Optional Rust alis-theme binary path")
    parser.add_argument("--out", help="JSON report location (default: /tmp)")
    parser.add_argument("--runtime-log", help="Optional existing log; only timing markers are retained")
    parser.add_argument("--runs", type=int, default=8)
    parser.add_argument("--warmup", type=int, default=2)
    parser.add_argument("--matrix-runs", type=int, default=3)
    parser.add_argument("--max-image-mb", type=int, default=200)
    parser.add_argument("--no-parity", action="store_true",
                        help="Skip optional Rust/Python fixture parity")
    args = parser.parse_args(argv)
    if not (1 <= args.runs <= 50 and 0 <= args.warmup <= 10
            and 1 <= args.matrix_runs <= 10 and 1 <= args.max_image_mb <= 2000):
        parser.error("Invalid sample count/image limit")
    outfile = (Path(args.out).expanduser()
               if args.out else Path(tempfile.gettempdir()) /
               ("alis-auto-theme-diagnostics-"
                + datetime.now().strftime("%Y%m%d-%H%M%S") + ".json"))
    try:
        output = collect(args)
        outfile.parent.mkdir(parents=True, exist_ok=True)
        outfile.write_text(json.dumps(output, ensure_ascii=False, indent=2)
                           + "\n", encoding="utf-8")
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print("THEME-PERF-05 collection failed: " + sanitized_error(str(error)),
              file=sys.stderr)
        return 2
    statuses = [v.get("status") for v in output["tests"].values()]
    issues = sum(status == "FAIL" for status in statuses)
    print("THEME-PERF-05 diagnostic bundle: " + str(outfile))
    print(f"Regression tests: {statuses.count('PASS')} PASS, "
          f"{issues} FAIL, {statuses.count('SKIP_DEPENDENCY')} SKIP_DEPENDENCY")
    print("Source image: " + ("available" if output["source"]["available"] else "not detected"))
    print("Benchmark: " + ("collected" if output["benchmarks"] else "unavailable"))
    print("Share this ONE JSON file; it contains no image path or raw application log.")
    return 1 if issues else 0


if __name__ == "__main__":
    raise SystemExit(main())
