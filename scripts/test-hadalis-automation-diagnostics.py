#!/usr/bin/env python3
"""Behavioral contract for inline removal and bounded, private Activity logs."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import stat
import sys
import tempfile
import time
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from automation.manager import control, diagnostics, store  # noqa: E402


def service_snapshot(bridge="active"):
    return {
        key: {"state": bridge if key == "bridge" else "active",
              "detail": "running", "result": "", "exec_main_status": "0"}
        for key in control.UNITS
    }


def error(call, phrase):
    try:
        call()
    except ValueError as exc:
        assert phrase in str(exc), str(exc)
    else:
        raise AssertionError(f"expected {phrase}")


def main() -> None:
    # Actual frontend interaction is exercised by the opt-in shell-live test;
    # labels and QML spelling are not behavior contracts.
    with tempfile.TemporaryDirectory() as tmp:
        with patch.dict(os.environ, {
                "XDG_CONFIG_HOME": tmp + "/config",
                "XDG_STATE_HOME": tmp + "/state"}):
            pid = control.create_profile("Deletion test")["profile_id"]
            control.set_profile(pid, "prompt", '"SECRET-NOT-IN-LOGS"')
            def own(_config, state):
                state["owner_id"] = pid
                state["manager_heartbeat_at_unix"] = int(time.time())
                state["profiles"][pid]["desired"] = "stopped"
                state["profiles"][pid]["pending"] = {"response_action_count": 0}
            store.change_state(own)

            with patch.object(control, "service_states", return_value=service_snapshot("inactive")):
                error(lambda: control.remove_profile(pid), "current response")
            assert store.read_snapshot()[1]["owner_id"] == pid

            store.change_state(lambda _config, state:
                               state["profiles"][pid].update({"pending": None}))
            with patch.object(control, "service_states", return_value=service_snapshot()):
                error(lambda: control.remove_profile(pid), "scheduler still owns")
            assert pid in store.read_snapshot()[1]["profiles"]

            journal = SimpleNamespace(returncode=0,
                                      stdout="bridge service: synthetic failure trace\n", stderr="")
            with patch.object(control, "service_states", return_value=service_snapshot("inactive")), \
                 patch.object(diagnostics.subprocess, "run", return_value=journal):
                before = diagnostics.report()
                assert "SECRET-NOT-IN-LOGS" not in before
                assert "bridge service: synthetic failure trace" in before
                assert pid in before
                assert "exec_main_status=0" in before
                assert "pending=False" in before

                exported = Path(diagnostics.export_report())
                try:
                    assert exported.parent == Path("/tmp")
                    assert exported.name.startswith("hadalis-automation-")
                    assert stat.S_IMODE(exported.stat().st_mode) == 0o600
                    assert exported.read_text(encoding="utf-8") == before or (
                        "bridge service: synthetic failure trace" in exported.read_text(encoding="utf-8"))
                    assert "SECRET-NOT-IN-LOGS" not in exported.read_text(encoding="utf-8")
                finally:
                    exported.unlink(missing_ok=True)

                control.remove_profile(pid)
            runtime = store.read_snapshot()[1]
            assert runtime["owner_id"] is None
            assert pid not in runtime["profiles"]
            assert any(e["kind"] == "stale_owner_released" for e in runtime["events"])
            assert any(e["kind"] == "removed" and e["profile_id"] == pid
                       for e in runtime["events"])

            with patch.object(control, "service_states", return_value=service_snapshot()):
                control.remove_profile("strict-lossless-research")
            assert "strict-lossless-research" not in store.read_snapshot()[1]["profiles"]

            store.change_state(lambda _config, state: store.event(
                state, None, "detailed_error", "E" * 2200))
            assert len(store.read_snapshot()[1]["events"][-1]["detail"]) == 2200

    path = ROOT / "scripts/hadalis-automation-control.py"
    spec = importlib.util.spec_from_file_location("automation_cli_test", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with patch.object(module.diagnostics, "report", return_value="sample"):
        assert module.main(["logs"]) == {"ok": True, "text": "sample"}
    with patch.object(module.diagnostics, "export_report", return_value="/tmp/sample"):
        assert module.main(["logs-export"]) == {"ok": True, "path": "/tmp/sample"}
    with patch.object(module.control, "remove_profile", return_value={"ok": True}) as remove:
        module.main(["profile-remove", "active", "confirm-unresolved"])
        remove.assert_called_once_with("active", True)
    error(lambda: module.main(["profile-remove", "active", "not-confirmed"]),
          "invalid removal confirmation")

    print("PASS: removal, stale lease guard, bounded private diagnostics and export contracts")


if __name__ == "__main__":
    main()
