#!/usr/bin/env python3
"""Explicitly gated, serialized paired native diagnostic; no production edits."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

BASE = Path(__file__).resolve().parent / "prepared"
parser = argparse.ArgumentParser()
parser.add_argument("--host-quiet-confirmed", action="store_true")
parser.add_argument("--order", default="grab,no-grab")
parser.add_argument("--output", type=Path)
parser.add_argument("--timeout", type=int, default=120)
args = parser.parse_args()
if not args.host_quiet_confirmed:
    raise SystemExit("NOT_STARTED: require explicit root confirmation that canonical/native jobs have stopped and the host is quiet")
order = args.order.split(",")
if not 10 <= args.timeout <= 120:
    raise SystemExit("Each lane must be bounded to10–120 seconds")
if len(order) not in (2, 4) or set(order) != {"grab", "no-grab"} or order.count("grab") != order.count("no-grab"):
    raise SystemExit("Use a balanced pair or four-lane order, e.g. grab,no-grab or grab,no-grab,no-grab,grab")
manifest = json.loads((BASE / "manifest.json").read_text())
assert hashlib.sha256((BASE / "shell.qml").read_bytes()).hexdigest() == manifest["instrumented_fixture_sha256"]
source = BASE / "instrumented-source"
sys.path.insert(0, str(source / "scripts"))
from native_test_session import private_wayland

output = args.output or BASE / ("run-" + time.strftime("%Y%m%d-%H%M%S"))
output.mkdir(parents=True, exist_ok=False)


def proc_sample(pid):
    try:
        stat = Path(f"/proc/{pid}/stat").read_text().split(") ", 1)[1].split()
        sample = {"pid": pid, "state": stat[0], "utime_ticks": int(stat[11]),
                  "stime_ticks": int(stat[12]), "rss_pages": int(stat[21])}
        try:
            sample["main_wchan"] = Path(f"/proc/{pid}/wchan").read_text().strip()
        except OSError:
            pass
        return sample
    except (OSError, ValueError, IndexError):
        return None


def terminate_group(process):
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=3)


summaries = []
for index, mode in enumerate(order):
    lane = output / f"{index:02d}-{mode}"
    lane.mkdir()
    runtime = lane / "runtime"
    runtime.mkdir()
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (runtime / entry).symlink_to(source / entry)
    (runtime / "shell.qml").write_bytes((BASE / "shell.qml").read_bytes())
    (lane / "frames").mkdir()
    started = time.time_ns()
    start_load = list(os.getloadavg())
    native_exit = None
    timed_out = False
    result = None
    qs_pid = None
    process = None
    try:
        with private_wayland(runtime) as env:
            if env is None:
                raise RuntimeError("Private Niri is unavailable; no native result")
            config = runtime / "config/alis"
            config.mkdir(parents=True, exist_ok=True)
            value = json.loads((source / "defaults/config.json").read_text())
            value["panelFamily"] = "abyss"
            value["abyss"]["companion"]["enabled"] = False
            (config / "config.json").write_text(json.dumps(value))
            env.update(R09_CAPTURE_MODE=mode, COMPOSED_CAPTURE=str(lane / "frames"),
                       QSG_RHI_BACKEND="opengl", QT_NO_XDG_DESKTOP_PORTAL="1")
            command = ["dbus-run-session", "--", "qs", "-p", str(runtime), "--no-color"]
            with (lane / "raw.log").open("wb") as log:
                process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            deadline = time.monotonic() + args.timeout
            offset = 0
            partial_line = ""
            with (lane / "external.jsonl").open("w") as external:
                while process.poll() is None:
                    # This clock is independent of the Qt GUI/event loop. No
                    # host process, audio route, preference or focus is changed.
                    with (lane / "raw.log").open() as log:
                        log.seek(offset)
                        chunk = partial_line + log.read()
                        offset = log.tell()
                        lines = chunk.split("\n")
                        partial_line = lines.pop()
                        for line in lines:
                            if "R09_EVENT " in line:
                                try:
                                    event = json.loads(line.split("R09_EVENT ", 1)[1])
                                    if event["event"] == "boot":
                                        qs_pid = event["detail"]["pid"]
                                except (ValueError, KeyError):
                                    pass
                    external.write(json.dumps({"monotonic_ns": time.monotonic_ns(), "wall_ns": time.time_ns(),
                        "qs": proc_sample(qs_pid) if qs_pid else None}) + "\n")
                    external.flush()
                    if time.monotonic() > deadline:
                        timed_out = True
                        terminate_group(process)
                        break
                    time.sleep(.1)
            native_exit = process.wait(timeout=3)
    finally:
        if process is not None:
            if process.poll() is None:
                terminate_group(process)
            else:
                # Do not retain orphaned fixture children after a normal exit.
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        raw = (lane / "raw.log").read_text(errors="replace") if (lane / "raw.log").exists() else ""
        for line in raw.splitlines():
            if "R09_PAIRED_RESULT " in line:
                result = json.loads(line.split("R09_PAIRED_RESULT ", 1)[1])
        if result is not None:
            (lane / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        receipt = {"source_sha": manifest["source_sha"], "mode": mode, "index": index,
            "native_exit": native_exit, "os_timeout": timed_out, "started_ns": started,
            "ended_ns": time.time_ns(), "qs_pid": qs_pid, "explicit_focus": False,
            "host_quiet_confirmed_by_caller": True, "instrumented": True,
            "loadavg_start":start_load,"loadavg_end":list(os.getloadavg()),
            "clock_ticks_per_second":os.sysconf("SC_CLK_TCK"),"page_size":os.sysconf("SC_PAGE_SIZE"),
            "os_deadline_seconds":args.timeout,
            "scope": "Diagnostic composed sequence; no source promotion, performance gain or owner acceptance",
            "result_present": result is not None, "hashes": {name: hashlib.sha256((lane / name).read_bytes()).hexdigest()
                for name in ["raw.log", "external.jsonl", "result.json"] if (lane / name).exists()}}
        (lane / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        summaries.append({**receipt, "error": result.get("error") if result else "No QML result",
                          "completed": result.get("completed") if result else 0})
        print(json.dumps({"lane": str(lane), "exit": native_exit, "timeout": timed_out,
                          "completed": summaries[-1]["completed"], "error": summaries[-1]["error"]}), flush=True)

(output / "pair.json").write_text(json.dumps({"order": order, "source": manifest, "lanes": summaries}, indent=2) + "\n")
print("Evidence directory:", output)
raise SystemExit(1 if any(lane["native_exit"] != 0 or lane["error"] for lane in summaries) else 0)
