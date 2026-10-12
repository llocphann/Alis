#!/usr/bin/env python3
"""Bounded opt-in notification/recording frame correlation on an installed Abyss.

No media capture, notification content, screenshot pixels, recording commands,
configuration writes, shell restart, audio capture or privileged operations.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
FILES = (
    "shell.qml", "modules/abyss/AbyssPerimeter.qml",
    "modules/abyss/content/AbyssNotificationsContent.qml",
    "services/Notifications.qml",
)
PHASES = {"record-start", "record-stop", "edge-hover"}

def parse_ipc(raw):
    """Accept plain or JSON-string-encoded Quickshell IPC JSON, no eval."""
    decoder = json.JSONDecoder()
    for at, char in enumerate(raw):
        if char not in '{["':
            continue
        try:
            candidate, _ = decoder.raw_decode(raw[at:])
            if isinstance(candidate, str):
                candidate = json.loads(candidate)
            if isinstance(candidate, (list, dict)):
                return candidate
        except (ValueError, TypeError):
            continue
    raise ValueError("missing JSON IPC receipt")

def output_token(name):
    return hashlib.sha256(str(name).encode("utf-8")).hexdigest()[:12]

def number(value):
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return None
    if value != value or abs(value) == float("inf"):
        return None
    return round(value, 3)

def sanitize_snapshot(receipt):
    if not isinstance(receipt, dict) or receipt.get("family") != "abyss":
        raise ValueError("snapshot is not from an Abyss output")
    sampled = []
    for out in receipt.get("outputs", []):
        if not isinstance(out, dict):
            continue
        n = out.get("notificationPresentation") or {}
        slots = []
        for slot in out.get("popupSlots") or []:
            if not isinstance(slot, dict):
                continue
            if slot.get("kind") != "notificationCenter":
                continue
            slots.append({
                "active": bool(slot.get("active")),
                "requestedVisible": bool(slot.get("requestedVisible")),
                "bounds": {key: number((slot.get("bounds") or {}).get(key))
                           for key in ("x", "y", "w", "h")},
            })
        sampled.append({
            "outputId": output_token(out.get("output")),
            "presented": bool(out.get("presented")),
            "fieldReady": bool(out.get("fieldReady")),
            "toast": {key: bool(n.get(key)) for key in
                      ("inhibited", "recording", "centerOpen", "toastOpen",
                       "toastResident", "toastLayoutReady")},
            "measurements": {key: number(n.get(key)) for key in
                             ("toastCount", "toastRevealProgress", "toastSpan",
                              "toastDepth", "toastAlong", "toastDesiredHeight",
                              "toastMeasuredHeight")},
            "edge": str(n.get("toastEdge", "")) if
                    n.get("toastEdge") in ("top", "bottom", "left", "right") else "",
            "center": slots,
        })
    return {"timestampMs": number(receipt.get("timestamp")), "outputs": sampled}

def sanitize_frames(receipt):
    if not isinstance(receipt, list):
        raise ValueError("frame receipt must have a list of output samples")
    fields = ("count", "min", "p50", "p95", "p99", "max", "mean",
              "over16ms", "over33ms", "idleGapsOver100ms",
              "panelNonzeroFrames", "panelProgressChangedFrames",
              "popupOpenFrames", "barProgressChangedFrames",
              "heartbeatSampleCount", "heartbeatOver100Ms",
              "heartbeatMaxIntervalMs")
    frames = []
    for item in receipt:
        if not isinstance(item, dict):
            continue
        frames.append({
            "outputId": output_token(item.get("output")),
            "metrics": {key: number(item.get(key)) for key in fields},
            "slow": [
                {"timestampMs": number(e.get("timestampMs")),
                 "intervalMs": number(e.get("intervalMs")),
                 "liquidPopupsOpen": bool(e.get("liquidPopupsOpen"))}
                for e in (item.get("slowEvents") or [])[:40] if isinstance(e, dict)
            ],
            "heartbeat": [
                {"timestampMs": number(e.get("timestampMs")),
                 "intervalMs": number(e.get("intervalMs"))}
                for e in (item.get("heartbeatHistory") or [])[:160] if isinstance(e, dict)
            ],
        })
    return frames

def checked_call(config, name, timeout=5):
    result = subprocess.run(["qs", "-p", str(config), "ipc", "call",
                             "abyssHoverProbe", name], capture_output=True,
                            text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(name + ": qs exit " + str(result.returncode))
    return parse_ipc(result.stdout)

def git_sha():
    result = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"],
                            capture_output=True, text=True, check=True)
    return result.stdout.strip()

def preflight(config):
    if not config.is_dir() or not (config / "shell.qml").is_file():
        raise RuntimeError("missing installed iNiR config")
    if "//@ pragma ShellId inir" not in (config / "shell.qml").read_text(errors="replace"):
        raise RuntimeError("config is not the iNiR shell")
    dirty = subprocess.run(["git", "-C", str(ROOT), "status", "--porcelain"],
                           capture_output=True, text=True, check=True)
    if dirty.stdout.strip():
        raise RuntimeError("checkout has uncommitted changes: exact-SHA parity unavailable")
    for relative in FILES:
        installed = config / relative
        checked = ROOT / relative
        if not installed.is_file() or not checked.is_file():
            raise RuntimeError("missing compared file " + relative)
        if hashlib.sha256(installed.read_bytes()).digest() != hashlib.sha256(checked.read_bytes()).digest():
            raise RuntimeError("installed QML differs from checkout: " + relative)
    inventory = subprocess.run(["qs", "-p", str(config), "list"],
                               capture_output=True, text=True, timeout=5)
    if inventory.returncode or "No running instances" in inventory.stdout:
        raise RuntimeError("no running installed iNiR instance")
    snap = sanitize_snapshot(checked_call(config, "snapshot"))
    if not snap["outputs"] or not any(o["fieldReady"] for o in snap["outputs"]):
        raise RuntimeError("installed Abyss output is not ready")
    return snap

def sample_phase(config, seconds, interval, label):
    start = time.monotonic()
    initiated = False
    captures = []
    frames = []
    error = None
    try:
        ack = checked_call(config, "startFrames")
        if not isinstance(ack, list) or not any(
                isinstance(item, dict) and item.get("started") is True for item in ack):
            raise RuntimeError("startFrames did not acknowledge active capture")
        initiated = True
        while time.monotonic() - start < seconds:
            try:
                sample = sanitize_snapshot(checked_call(config, "snapshot"))
                captures.append(sample)
            except (ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
                error = type(exc).__name__ + " during snapshot"
                break
            time.sleep(interval)
    finally:
        if initiated:
            try:
                frames = sanitize_frames(checked_call(config, "stopFrames"))
            except (ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
                error = (error or "") + " " + type(exc).__name__ + " during stopFrames"
    if error:
        raise RuntimeError(error)
    observed = any(
        out["toast"]["recording"] if label == "record-start"
        else (out["measurements"]["toastCount"] or 0) > 0
        if label == "record-stop"
        else bool(out["center"]) or out["toast"]["toastOpen"]
        for sample in captures for out in sample["outputs"])
    return {"seconds": round(time.monotonic() - start, 3),
            "snapshots": captures[:40], "frames": frames,
            "eventObserved": bool(observed)}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=sorted(PHASES), required=True)
    parser.add_argument("--seconds", type=int, default=6)
    parser.add_argument("--interval", type=float, default=.25)
    parser.add_argument("--config", type=Path, default=Path(
        os.environ.get("HADALIS_QS_CONFIG",
                       str(Path.home() / ".config/quickshell/inir"))))
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()
    if not 2 <= args.seconds <= 8 or not .15 <= args.interval <= 1:
        parser.error("seconds must be 2–8 and interval 0.15–1")
    if not all(subprocess.run(["sh", "-c", "command -v " + tool],
                              capture_output=True).returncode == 0
               for tool in ("qs", "git")):
        parser.error("requires qs and git")
    # No user image, filename or notification body is ever read or persisted.
    output = args.output_dir or Path(tempfile.mkdtemp(prefix="alis-notification-phase-"))
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(output, 0o700)
    receipt = {"sourceSha": git_sha(), "phase": args.phase,
               "utcStarted": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
               "status": "NOT_RUN"}
    try:
        receipt["preflight"] = preflight(args.config)
        print("Baseline: do not interact with notifications or recording", flush=True)
        receipt["baseline"] = sample_phase(args.config, args.seconds, args.interval, "baseline")
        print("EVENT WINDOW: reproduce " + args.phase +
              " on your normal UI within the next " + str(args.seconds) + " seconds",
              flush=True)
        receipt["event"] = sample_phase(args.config, args.seconds, args.interval, args.phase)
        receipt["status"] = "CAPTURED" if receipt["event"]["eventObserved"] else "EVENT_NOT_OBSERVED"
    except (ValueError, RuntimeError, subprocess.SubprocessError, OSError) as exc:
        receipt["status"] = "BLOCKED"
        receipt["failureType"] = type(exc).__name__
        print("Blocked: " + str(exc), file=sys.stderr)
    path = output / "notification-presentation.json"
    path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    os.chmod(path, 0o600)
    print("Result:", receipt["status"], "\nSanitized receipt:", path)
    return 0 if receipt["status"] == "CAPTURED" else 2

if __name__ == "__main__":
    sys.exit(main())
