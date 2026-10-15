#!/usr/bin/env python3
"""AUTO-F01: bounded, read-only health sample of three Automation systemd units.

No journal bodies, credentials, account IDs, PIDs or environment are emitted.
Does not start/stop/restart/reset services, touch queues, or use ChatGPT CDP.
"""
from __future__ import annotations

import json
import subprocess
import sys
import time

UNITS = (
    "hadalis-chatgpt.service",
    "hadalis-chat-bridge.service",
    "hadalis-worker.service",
)
FIELDS = (
    "LoadState", "ActiveState", "SubState", "Result", "ExecMainStatus",
    "NRestarts", "MainPID", "InvocationID", "ActiveEnterTimestampMonotonic",
)
WAIT_SECONDS = 12


def _snapshot(unit: str) -> dict:
    try:
        completed = subprocess.run(
            ["systemctl", "--user", "show", unit, "--no-pager",
             "--property=" + ",".join(FIELDS)],
            capture_output=True, text=True, timeout=7, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return {"available": False}
    if completed.returncode != 0 or len(completed.stdout) > 16384:
        return {"available": False}
    data = {}
    for line in completed.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            if key in FIELDS and key not in data:
                data[key] = value
    return {"available": all(k in data for k in FIELDS), **data}


def _counter(value: object) -> int | None:
    if not isinstance(value, str) or not value.isascii() or not value.isdecimal():
        return None
    number = int(value)
    return number if number < 1_000_000_000 else None


def _compare(first: dict, last: dict) -> dict:
    old = _counter(first.get("NRestarts"))
    new = _counter(last.get("NRestarts"))
    if not first.get("available") or not last.get("available") or old is None or new is None:
        status = "SAMPLE_UNAVAILABLE_OR_INCOMPLETE"
        delta = None
    elif new < old:
        status = "COUNTER_RESET_OR_UNIT_REPLACED"
        delta = None
    else:
        delta = new - old
        if delta:
            status = "RESTARTS_OBSERVED_IN_WINDOW"
        elif first.get("MainPID") != last.get("MainPID") or (
            first.get("InvocationID") != last.get("InvocationID")
        ) or (first.get("ActiveEnterTimestampMonotonic") !=
              last.get("ActiveEnterTimestampMonotonic")):
            status = "PROCESS_OR_INVOCATION_CHANGED_UNCOUNTED"
        elif last.get("LoadState") != "loaded" or last.get("ActiveState") != "active" or last.get("SubState") != "running":
            status = "SERVICE_NOT_RUNNING_AT_SAMPLE"
        else:
            status = "NO_RESTART_DETECTED_IN_SAMPLE"
    return {
        "diagnosis": status,
        "load_state": last.get("LoadState") if last.get("LoadState") in
        ("loaded", "not-found", "masked", "error", "bad-setting") else "unverified",
        "active_state": last.get("ActiveState") if last.get("ActiveState") in
        ("active", "inactive", "failed", "activating", "deactivating") else "unverified",
        "sub_state": last.get("SubState") if last.get("SubState") in
        ("running", "dead", "failed", "auto-restart", "exited", "start", "stop") else "other-or-unknown",
        "result": last.get("Result") if last.get("Result") in
        ("success", "exit-code", "signal", "timeout", "start-limit-hit", "core-dump", "oom-kill") else "other-or-unknown",
        "exit_code_zero": last.get("ExecMainStatus") == "0",
        "restart_count_before": old,
        "restart_count_after": new,
        "restart_delta": delta,
        "process_changed": (
            first.get("MainPID") != last.get("MainPID")
            if first.get("available") and last.get("available") else None
        ),
        "invocation_changed": (
            first.get("InvocationID") != last.get("InvocationID")
            if first.get("available") and last.get("available") else None
        ),
    }


def _self_test() -> None:
    def sample(restarts="8734", state="active", sub="running", pid="42", invocation="first", tick="120"):
        return dict(available=True, NRestarts=restarts, LoadState="loaded",
                    ActiveState=state, SubState=sub, Result="success",
                    ExecMainStatus="0", MainPID=pid, InvocationID=invocation,
                    ActiveEnterTimestampMonotonic=tick)

    same = _compare(sample(), sample())
    assert same["diagnosis"] == "NO_RESTART_DETECTED_IN_SAMPLE"
    assert same["restart_delta"] == 0
    restarted = _compare(sample(), sample(restarts="8736", pid="43", invocation="second", tick="121"))
    assert restarted["diagnosis"] == "RESTARTS_OBSERVED_IN_WINDOW"
    assert restarted["restart_delta"] == 2
    assert restarted["process_changed"] is True
    assert _compare(sample(), sample(pid="43"))["diagnosis"] == "PROCESS_OR_INVOCATION_CHANGED_UNCOUNTED"
    assert _compare(sample(), sample(state="failed", sub="failed"))["diagnosis"] == "SERVICE_NOT_RUNNING_AT_SAMPLE"
    assert _compare(sample(), sample(restarts="1"))["diagnosis"] == "COUNTER_RESET_OR_UNIT_REPLACED"
    assert _compare(sample(), {})["diagnosis"] == "SAMPLE_UNAVAILABLE_OR_INCOMPLETE"
    assert _compare(sample(restarts="PRIVATE_TOKEN"), sample())["restart_delta"] is None
    assert _compare(sample(restarts="-1"), sample())["restart_delta"] is None
    assert _compare(sample(restarts="1000000000"), sample())["restart_delta"] is None
    exposed = json.dumps(restarted)
    assert all(x not in exposed for x in ("8736_PRIVATE", "first", "second", "MainPID", "InvocationID", "42", "43"))
    print("PASS AUTO-F01: restart-window classification is read-only and redacted")


def main(argv: list[str]) -> int:
    if argv == ["self-test"]:
        _self_test()
        return 0
    if argv != ["probe"]:
        print(json.dumps({"purpose": "auto-f01-service-health",
                          "status": "blocked", "code": "READ_ONLY_PROBE_ONLY"}))
        return 2
    before = {unit: _snapshot(unit) for unit in UNITS}
    time.sleep(WAIT_SECONDS)
    after = {unit: _snapshot(unit) for unit in UNITS}
    report = {
        "purpose": "auto-f01-service-health",
        "status": "read-only",
        "sample_window_seconds": WAIT_SECONDS,
        "diagnosis_scope": "two-local-systemd-samples-only",
        "services": {unit.removesuffix(".service"): _compare(before[unit], after[unit])
                     for unit in UNITS},
        "chat_project_verified": False,
        "server_receipt_verified": False,
        "scheduler_submission_authorized": False,
    }
    print(json.dumps(report, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
