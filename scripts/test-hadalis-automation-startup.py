#!/usr/bin/env python3
"""Regression: profile controls activate the scheduler and expose failures."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import tempfile
import time
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation.manager import control, daemon, store  # noqa: E402


def services(**overrides):
    return {key: {"state": overrides.get(key, "active"),
                  "detail": "running", "result": ""}
            for key in control.UNITS}


def main() -> None:
    initial = services(chatgpt="inactive", worker="inactive", bridge="inactive")
    with patch.object(control, "service_states", return_value=initial):
        with patch.object(control.subprocess, "run",
                          return_value=SimpleNamespace(returncode=0, stdout="", stderr="")) as run:
            control._ensure_runtime_services()
            assert [call.args[0][-1] for call in run.call_args_list] == [
                control.UNITS["worker"], control.UNITS["bridge"], control.UNITS["chatgpt"]]

    with patch.object(control, "service_states",
                      return_value=services(bridge="unavailable")):
        try:
            control._ensure_runtime_services()
        except RuntimeError as exc:
            assert "install-hadalis-automation.py" in str(exc)
        else:
            raise AssertionError("uninstalled scheduler must not report ready")

    with tempfile.TemporaryDirectory() as tmp:
        with patch.dict(os.environ, {
                "XDG_CONFIG_HOME": tmp + "/config",
                "XDG_STATE_HOME": tmp + "/state"}):
            pid = "strict-lossless-research"

            def stale(_config, runtime):
                runtime["owner_id"] = pid
                runtime["manager_heartbeat_at_unix"] = int(time.time()) - 200
                runtime["profiles"][pid]["status"] = "continuing"

            store.change_state(stale)

            failed_host = services(chatgpt="failed", bridge="inactive")
            failed_host["chatgpt"]["exec_main_status"] = "76"
            with patch.object(control, "service_states", return_value=failed_host):
                assert "Close ChatGPT once" in control.status()["scheduler_problem"]

            with patch.object(control, "service_states",
                              return_value=services(bridge="inactive")):
                snapshot = control.status()
                repeated = control.status()
            item = repeated["runtime"]["profiles"][pid]
            assert item["status"] == "continuing"  # Reads cannot mutate live state.
            assert "Chat bridge is inactive" in snapshot["scheduler_problem"]
            assert not repeated["runtime"]["events"]
            assert snapshot["services"]["bridge"]["state"] == "inactive"

            with patch.object(control, "service_states", return_value=services()):
                stale_heartbeat = control.status()
            assert "heartbeat is older" in stale_heartbeat["scheduler_problem"]

            store.change_state(lambda _config, runtime: daemon._heartbeat(runtime, int(time.time())))
            assert store.read_snapshot()[1]["profiles"][pid]["status"] == "continuing"

            with patch.object(control, "_ensure_runtime_services",
                              side_effect=RuntimeError("ChatGPT CDP endpoint unavailable")):
                try:
                    control.profile_action("start", pid)
                except RuntimeError as exc:
                    assert "CDP endpoint" in str(exc)
                else:
                    raise AssertionError("failed runtime start must fail the action")
            item = store.read_snapshot()[1]["profiles"][pid]
            assert item["status"] == "scheduler_unavailable"
            assert "CDP endpoint" in item["last_error"]
            assert any(entry["kind"] == "start_failed"
                       for entry in store.read_snapshot()[1]["events"])

            def waiting_job(_config, runtime):
                runtime["profiles"][pid].update({
                    "job_id": "JOB-STUCK", "status": "waiting_result",
                    "pending": None, "next_job_poll_at_unix": int(time.time()) + 10})

            store.change_state(waiting_job)
            with patch.object(control, "_ensure_runtime_services"), patch.object(control, "_await_dispatch"):
                control.profile_action("restart", pid)
            item = store.read_snapshot()[1]["profiles"][pid]
            assert item["job_id"] is None and item["request"] == "restart"
            assert item["status"] == "scheduled"
            assert any(entry["kind"] == "job_wait_abandoned"
                       for entry in store.read_snapshot()[1]["events"])

            store.change_state(lambda _config, runtime: daemon._configuration_problem(
                runtime, ["malformed profile"]))
            item = store.read_snapshot()[1]["profiles"][pid]
            assert item["status"] == "invalid_configuration"
            assert any(entry["kind"] == "invalid_configuration"
                       for entry in store.read_snapshot()[1]["events"])
    print("PASS: Automation runtime startup, heartbeat, errors and restart")


if __name__ == "__main__":
    main()
