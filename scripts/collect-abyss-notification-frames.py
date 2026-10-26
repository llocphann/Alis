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
PHASES = {"record-start", "record-stop", "edge-hover", "toast-open", "toast-close"}
# Exact opt-in runtime instrumentation from AbyssPerimeter.qml at this source SHA.
EXPECTED_NOTIFICATION_FRAME_LIMIT = 160

class StaleRuntimeError(RuntimeError):
    """Installed QML bytes match, but the running Quickshell engine is older."""


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
                              "toastDepth", "toastPaintDepth", "toastTargetDepth", "toastAlong", "toastDesiredHeight",
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
              "heartbeatMaxIntervalMs", "notificationFramesDropped",
              "notificationFrameLimit", "notificationRecordUpdates",
              "fieldRecordUpdates", "allocatorUpdates")
    frames = []
    for item in receipt:
        if not isinstance(item, dict):
            continue
        # The production probe is a bounded, opt-in frameSwapped trace.
        # Copy only known primitive fields: no icon, title, user file path
        # or arbitrary extra field can pass through this sanitizer.
        trace = []
        for sample in (item.get("notificationFrames") or [])[:160]:
            if not isinstance(sample, dict):
                continue
            trace.append({
                "timestampMs": number(sample.get("timestampMs")),
                "intervalMs": number(sample.get("intervalMs")),
                "progress": number(sample.get("progress")),
                "progressDelta": number(sample.get("progressDelta")),
                "paintDepth": number(sample.get("paintDepth")),
                "targetDepth": number(sample.get("targetDepth")),
                "visualInward": number(sample.get("visualInward")),
                "pyramidActive": bool(sample.get("pyramidActive")),
                "pyramidClosing": bool(sample.get("pyramidClosing")),
                "pyramidReopening": bool(sample.get("pyramidReopening")),
                "recordingVisible": bool(sample.get("recordingVisible")),
                "notificationRecordChanges": number(sample.get("notificationRecordChanges")),
                "fieldRecordChanges": number(sample.get("fieldRecordChanges")),
                "allocatorChanges": number(sample.get("allocatorChanges")),
                "fieldRecordCount": number(sample.get("fieldRecordCount")),
            })
        frames.append({
            "outputId": output_token(item.get("output")),
            "notificationFrames": trace,
            "metrics": {
                **{key: number(item.get(key)) for key in fields},
                "exhausted": item.get("exhausted") is True,
                "heartbeatHistoryExhausted":
                    item.get("heartbeatHistoryExhausted") is True,
            },
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

def validate_frame_probe_start(ack):
    """Reject a live engine that has not loaded the notification frame probe."""
    if not isinstance(ack, list) or not any(
            isinstance(item, dict) and item.get("started") is True for item in ack):
        raise RuntimeError("startFrames did not acknowledge active capture")
    if any(not isinstance(item, dict) or item.get("started") is not True
           or item.get("notificationFrameLimit") != EXPECTED_NOTIFICATION_FRAME_LIMIT
           for item in ack):
        raise StaleRuntimeError(
            "STALE_RUNTIME: installed QML may match checkout, but running "
            "Quickshell lacks the notification frame probe; capture refused")


def validate_frame_probe_stop(raw):
    """Fail closed if the engine changes while a capture is in progress."""
    if not isinstance(raw, list) or not raw:
        raise RuntimeError("stopFrames returned no output samples")
    if any(not isinstance(item, dict)
           or item.get("notificationFrameLimit") != EXPECTED_NOTIFICATION_FRAME_LIMIT
           or not isinstance(item.get("notificationFrames"), list)
           or not isinstance(item.get("notificationFramesDropped"), (int, float))
           or not isinstance(item.get("exhausted"), bool)
           or not isinstance(item.get("heartbeatHistoryExhausted"), bool)
           for item in raw):
        raise StaleRuntimeError(
            "STALE_RUNTIME: stopFrames lacks the notification frame schema")


def trace_incomplete(*phases):
    """A bounded capture is not evidence for an entire unobserved interval."""
    for phase in phases:
        for output in phase.get("frames", []):
            metrics = output.get("metrics") or {}
            if (metrics.get("exhausted")
                    or metrics.get("heartbeatHistoryExhausted")
                    or (metrics.get("notificationFramesDropped") or 0) > 0):
                return True
    return False


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
        raise RuntimeError("missing installed Alis config")
    if "//@ pragma ShellId alis" not in (config / "shell.qml").read_text(errors="replace"):
        raise RuntimeError("config is not the Alis shell")
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
        raise RuntimeError("no running installed Alis instance")
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
        # startFrames can arm an *old* engine before returning its old schema.
        # Always disarm that session in finally even when the handshake fails.
        initiated = isinstance(ack, list) and any(
            isinstance(item, dict) and item.get("started") is True for item in ack)
        validate_frame_probe_start(ack)
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
                raw_frames = checked_call(config, "stopFrames")
                validate_frame_probe_stop(raw_frames)
                frames = sanitize_frames(raw_frames)
            except (ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
                error = (error or "") + " " + type(exc).__name__ + " during stopFrames"
    if error:
        raise RuntimeError(error)
    return {"seconds": round(time.monotonic() - start, 3),
            "snapshots": captures[:40], "frames": frames}

def phase_observed(phase, baseline, event):
    """Check a *transition on one output*, never an unrelated static popup."""
    if phase in ("toast-open", "toast-close"):
        # The old 150-250ms snapshot cadence misses a ~228ms banner.
        # Here only the frameSwapped timeline is authoritative for observing
        # motion. An explicit progress direction, not idle frame gaps alone,
        # is required before reporting CAPTURED.
        direction = 1 if phase == "toast-open" else -1
        for output in event.get("frames", []):
            samples = output.get("notificationFrames") or []
            delta = 0.0
            for first, second in zip(samples, samples[1:]):
                a, b = first.get("progress"), second.get("progress")
                if a is None or b is None:
                    continue
                step = (b - a) * direction
                if step > 0:
                    delta += step
            if delta > 0.06:
                return True
        return False
    last = baseline.get("snapshots", [])[-1:]  # Resting state near event start.
    if not last or not event.get("snapshots"):
        return False
    before = {o["outputId"]: o for o in last[0]["outputs"]}
    count = lambda o: o["measurements"].get("toastCount") or 0
    for sample in event["snapshots"]:
        for out in sample["outputs"]:
            prior = before.get(out["outputId"])
            if prior is None:
                continue
            if phase == "record-start" and (not prior["toast"]["recording"]
                    and out["toast"]["recording"]):
                return True
            if phase == "record-stop" and (prior["toast"]["recording"]
                    and not out["toast"]["recording"] and count(out) > 0):
                return True
            if phase == "edge-hover" and (
                    not any(slot["active"] for slot in prior["center"])
                    and any(slot["active"] for slot in out["center"])):
                return True
    return False

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=sorted(PHASES), required=True)
    parser.add_argument("--seconds", type=int, default=6)
    parser.add_argument("--interval", type=float, default=.25)
    parser.add_argument("--config", type=Path, default=Path(
        os.environ.get("ALIS_QS_CONFIG",
                       str(Path.home() / ".config/quickshell/alis"))))
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
        observed = phase_observed(args.phase, receipt["baseline"], receipt["event"])
        has_frames = any((f["metrics"].get("count") or 0) > 0
                         for f in receipt["event"]["frames"])
        receipt["event"]["eventObserved"] = observed
        receipt["status"] = (
            "INCOMPLETE_TRACE" if trace_incomplete(receipt["baseline"], receipt["event"]) else
            "CAPTURED" if observed and has_frames else
            "NO_FRAME_SAMPLES" if observed else "EVENT_NOT_OBSERVED")
    except (ValueError, RuntimeError, subprocess.SubprocessError, OSError) as exc:
        receipt["status"] = "BLOCKED"
        receipt["failureType"] = type(exc).__name__
        if isinstance(exc, StaleRuntimeError):
            receipt["failureCode"] = "STALE_RUNTIME"
        print("Blocked: " + str(exc), file=sys.stderr)
    path = output / "notification-presentation.json"
    path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    os.chmod(path, 0o600)
    print("Result:", receipt["status"], "\nSanitized receipt:", path)
    return 0 if receipt["status"] == "CAPTURED" else 2

if __name__ == "__main__":
    sys.exit(main())
