#!/usr/bin/env python3
"""THEME-PERF-08: opt-in live Auto Theming latency collector.

Default is read-only/passive; --trigger regenerates colors for the existing
wallpaper without switching the wallpaper or restarting Quickshell.
No raw Quickshell logs, wallpaper paths or palette values enter the report.
"""
from __future__ import annotations

import argparse
import ctypes
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
STAGE = re.compile(
    r"\[THEME-PERF-04\]\s+scope=([a-z0-9_-]+)\s+stage=([a-zA-Z0-9_-]+)"
    r"\s+ms=([0-9]+(?:\.[0-9]+)?)(?:\s+epoch_ms=([0-9]+))?"
)
WATCH_FILES = {
    "colors.json", "palette.json", "app-palette.json", "terminal.json",
    "material_colors.scss", "theme-meta.json", "chromium-theme.json",
    "theming_modules.log", "terminal_colors.log", "code_editor_themes.log",
}
IN_MODIFY = 0x00000002
IN_ATTRIB = 0x00000004
IN_CLOSE_WRITE = 0x00000008
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
IN_DELETE = 0x00000200
EVENT_MASK = IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE | IN_DELETE


def now_ms() -> int:
    return time.time_ns() // 1_000_000


def parse_stages(text: str, start_ms: int, end_ms: int, *, allow_untimed: bool) -> list[dict]:
    stages = []
    for line in text.splitlines():
        for scope, stage, millis, stamp in STAGE.findall(line):
            if stamp:
                when = int(stamp)
                if when < start_ms - 1500 or when > end_ms + 1500:
                    continue
            elif not allow_untimed:
                continue
            else:
                when = None
            stages.append({
                "scope": scope,
                "stage": stage,
                "duration_ms": float(millis),
                "epoch_ms": when,
            })
    return stages


def summarize(stages: list[dict]) -> dict:
    grouped: dict[str, list[float]] = {}
    for row in stages:
        grouped.setdefault(f'{row["scope"]}.{row["stage"]}', []).append(
            row["duration_ms"]
        )
    out = {}
    for key, values in sorted(grouped.items()):
        seq = sorted(values)
        out[key] = {
            "count": len(seq),
            "median_ms": round(
                (seq[(len(seq) - 1) // 2] + seq[len(seq) // 2]) / 2, 3
            ),
            "p95_ms": round(seq[max(0, (95 * len(seq) + 99) // 100 - 1)], 3),
        }
    return out


def first_interval(events: list[dict], from_name: str, to_name: str) -> float | None:
    starts = [row["epoch_ms"] for row in events
              if row["file"] == from_name and row["action"] in ("rename", "close")]
    ends = [row["epoch_ms"] for row in events
            if row["file"] == to_name and row["action"] in ("rename", "close", "write")]
    delays = [t - s for s in starts for t in ends if 0 <= t - s <= 15_000]
    return round(min(delays), 3) if delays else None


def runtime_dir() -> Path:
    raw = os.environ.get("XDG_RUNTIME_DIR")
    if raw:
        return Path(raw)
    return Path.home() / ".cache"


def generated_dir() -> Path:
    root = os.environ.get("XDG_STATE_HOME")
    base = Path(root) if root else Path.home() / ".local/state"
    return base / "quickshell/user/generated"


def candidate_wallpaper() -> Path | None:
    directory = generated_dir()
    metadata = directory / "theme-meta.json"
    try:
        data = json.loads(metadata.read_text())
        path = data.get("source_path")
        if data.get("source") == "image" and isinstance(path, str):
            candidate = Path(path.removeprefix("file://")).expanduser()
            if candidate.is_file():
                return candidate.resolve()
    except (OSError, ValueError):
        pass
    return None


def install_inotify(directory: Path) -> int | None:
    if not directory.is_dir():
        return None
    libc = ctypes.CDLL(None, use_errno=True)
    if not hasattr(libc, "inotify_init1"):
        return None
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    if fd < 0:
        return None
    if libc.inotify_add_watch(fd, os.fsencode(directory), EVENT_MASK) < 0:
        os.close(fd)
        return None
    return fd


def read_inotify(fd: int) -> list[dict]:
    rows = []
    try:
        payload = os.read(fd, 64 * 1024)
    except (BlockingIOError, OSError):
        return rows
    offset = 0
    while offset + 16 <= len(payload):
        _, mask, _, length = struct.unpack_from("iIII", payload, offset)
        offset += 16
        name = payload[offset: offset + length].rstrip(b"\x00").decode(
            "utf-8", "replace"
        )
        offset += length
        if name not in WATCH_FILES:
            continue
        action = (
            "rename" if mask & IN_MOVED_TO else
            "close" if mask & IN_CLOSE_WRITE else
            "write" if mask & (IN_MODIFY | IN_CREATE) else
            "delete" if mask & IN_DELETE else "attr"
        )
        rows.append({"file": name, "action": action, "epoch_ms": now_ms()})
    return rows


def snapshot(directory: Path) -> dict:
    result = {}
    for name in WATCH_FILES:
        try:
            file = directory / name
            stat = file.stat()
            result[name] = (stat.st_mtime_ns, stat.st_size, stat.st_ino)
        except OSError:
            result[name] = None
    return result


def qml_logs(start_ms: int, end_ms: int) -> dict:
    binary = shutil.which("qs") or shutil.which("quickshell")
    config = Path(os.environ.get("XDG_CONFIG_HOME") or
                  (Path.home() / ".config")) / "quickshell/alis"
    if binary is None or not config.is_dir():
        return {"status": "UNAVAILABLE", "stages": []}
    try:
        result = subprocess.run(
            [binary, "-p", str(config), "log", "--rules", "*=true"],
            capture_output=True, text=True, timeout=9,
        )
        if result.returncode != 0:
            return {"status": "UNAVAILABLE", "stages": []}
        stages = [
            event for event in parse_stages(
                result.stdout[-3_000_000:], start_ms, end_ms,
                allow_untimed=False,
            ) if event["scope"] == "qml"
        ]
        return {"status": "PASS" if stages else "NO_QML_PROFILE_EVENTS",
                "stages": stages}
    except (OSError, subprocess.TimeoutExpired):
        return {"status": "UNAVAILABLE", "stages": []}


def run_capture(args) -> dict:
    generated = generated_dir()
    profile_dir = runtime_dir() / "alis-theme-perf08"
    profile_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    if profile_dir.is_symlink():
        raise ValueError("Runtime profile directory must not be a symlink")
    lock = profile_dir / "collector.lock"
    marker = profile_dir / "enabled"
    trace = profile_dir / "trace.log"
    lock_fd = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.close(lock_fd)
    owns_marker = False
    owns_trace = False
    watcher = None
    process = None
    start = now_ms()
    events: list[dict] = []
    old_snapshot = snapshot(generated)
    trigger_status: dict = {"status": "NOT_REQUESTED"}
    source_kind = "none"
    try:
        if marker.exists():
            raise ValueError("Another runtime profiler is already enabled")
        trace_position = trace.stat().st_size if trace.is_file() else 0
        if not trace.is_file():
            fd = os.open(trace, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            os.close(fd)
            owns_trace = True
        fd = os.open(marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.write(fd, b"1\n")
        os.close(fd)
        owns_marker = True

        watcher = install_inotify(generated)
        if args.trigger:
            image = candidate_wallpaper()
            if image is None:
                trigger_status = {"status": "SKIPPED_NO_IMAGE"}
            else:
                # Quickshell's FileView reload poll is 1500ms. Allow the shell
                # to observe this opt-in marker without restarting it.
                time.sleep(1.8)
                env = os.environ.copy()
                env.update({
                    "ALIS_THEME_PROFILE": "1",
                    "ALIS_THEME_PROFILE_LOG": str(trace),
                    "ALIS_THEME_SKIP_SDDM_SYNC": "1",
                })
                process = subprocess.Popen(
                    ["bash", str(ROOT / "scripts/colors/switchwall.sh"),
                     "--image", str(image), "--noswitch", "--skip-config-write"],
                    cwd=ROOT, env=env,
                    stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                source_kind = image.suffix.lower()
                trigger_status = {"status": "STARTED", "recolor_existing_wallpaper": True}
        else:
            print("THEME-PERF-08 passive mode: change wallpaper or theme once in Alis during capture.")

        start = now_ms()
        deadline = time.monotonic() + args.duration
        while time.monotonic() < deadline:
            if watcher is not None:
                readable, _, _ = select.select([watcher], [], [], 0.05)
                if readable:
                    events.extend(read_inotify(watcher))
            else:
                time.sleep(0.05)
                current = snapshot(generated)
                for filename, status in current.items():
                    if old_snapshot.get(filename) != status:
                        events.append({
                            "file": filename, "action": "stat_change",
                            "epoch_ms": now_ms(),
                        })
                old_snapshot = current
            if len(events) > 3000:
                events = events[:3000]
            if process is not None and process.poll() is not None:
                trigger_status["status"] = (
                    "PASS" if process.returncode == 0 else "FAILED"
                )
                trigger_status["exit_code"] = process.returncode
                process = None
        end = now_ms()
        if process is not None:
            trigger_status = {"status": "STILL_RUNNING_AT_CAPTURE_END"}
        with trace.open("rb") as stream:
            stream.seek(trace_position)
            trace_content = stream.read(3_000_000).decode("utf-8", "replace")
        shell_stages = parse_stages(trace_content, start - 2_000, end,
                                    allow_untimed=True)
        qs = qml_logs(start, end)
        combined = shell_stages + qs["stages"]
        unique = {(row["scope"], row["stage"], row["duration_ms"],
                   row["epoch_ms"]): row for row in combined}
        all_stages = list(unique.values())
        event_count = len(events)
        evidence = {
            "qml_stage_count": len(qs["stages"]),
            "shell_stage_count": len(shell_stages),
            "file_event_count": event_count,
        }
        return {
            "schema": "THEME-PERF-08-v1",
            "git_sha": git_sha(),
            "captured_utc": datetime.now(timezone.utc).isoformat(),
            "capture_mode": "recolor_same_wallpaper" if args.trigger else "passive",
            "duration_ms": end - start,
            "generated_dir_present": generated.is_dir(),
            "source_kind": source_kind,
            "trigger": trigger_status,
            "qml_trace_status": qs["status"],
            "shell_trace_status": "PASS" if shell_stages else "NO_SHELL_PROFILE_EVENTS",
            "observed_events": events,
            "stages": summarize(all_stages),
            "stage_samples": all_stages,
            "evidence": evidence,
            "proxy_intervals_ms": {
                "colors_to_app_palette": first_interval(
                    events, "colors.json", "app-palette.json"
                ),
                "colors_to_terminal_json": first_interval(
                    events, "colors.json", "terminal.json"
                ),
                "colors_to_module_log": first_interval(
                    events, "colors.json", "theming_modules.log"
                ),
            },
            "limits": [
                "File events measure filesystem publication, not actual visible frames.",
                "QML stage timings require the installed shell to load the updated profiling code.",
                "Module trace totals can overlap; they are not a sum of end-to-end latency.",
                "The collector never restarts Quickshell or switches the wallpaper.",
            ],
        }
    finally:
        if watcher is not None:
            os.close(watcher)
        if owns_marker:
            try:
                if marker.read_text().strip() == "1":
                    marker.unlink()
            except OSError:
                pass
        if owns_trace:
            try:
                trace.unlink()
            except OSError:
                pass
        try:
            lock.unlink()
        except OSError:
            pass


def git_sha() -> str:
    try:
        r = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT,
                           capture_output=True, text=True, timeout=5)
        return r.stdout.strip() if r.returncode == 0 else "unknown"
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trigger", action="store_true",
                        help="Reapply current wallpaper colors without wallpaper switch")
    parser.add_argument("--duration", type=float, default=20,
                        help="Seconds to watch file and QML events (default 20)")
    parser.add_argument("--out", help="Save single sanitized JSON report here")
    args = parser.parse_args(argv)
    if not 0.1 <= args.duration <= 180:
        parser.error("--duration must be 0.1..180 seconds")
    os.umask(0o077)
    try:
        report = run_capture(args)
    except (OSError, ValueError) as error:
        print(f"THEME-PERF-08 capture error: {type(error).__name__}", file=sys.stderr)
        return 2
    location = (Path(args.out).expanduser() if args.out else
                Path(tempfile.gettempdir()) /
                ("alis-auto-theme-runtime-"
                 + datetime.now().strftime("%Y%m%d-%H%M%S") + ".json"))
    location.parent.mkdir(parents=True, exist_ok=True)
    location.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("THEME-PERF-08 diagnostic bundle: " + str(location))
    print("QML markers: " + report["qml_trace_status"] +
          "; Shell stages: " + report["shell_trace_status"])
    print("Filesystem events: " + str(report["evidence"]["file_event_count"]))
    print("Share this ONE JSON file; no wallpaper paths, raw logs or palette values.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
