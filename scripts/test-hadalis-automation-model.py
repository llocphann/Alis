#!/usr/bin/env python3
"""Behavioral regression for Automation profiles and serialized control."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from automation.manager import control, model, store  # noqa: E402


def expect_error(call, message: str) -> None:
    try:
        call()
    except ValueError as exc:
        assert message in str(exc), str(exc)
    else:
        raise AssertionError(f"expected {message}")


def main() -> None:
    initial = model.default_profile()
    assert model.effective_prompt(initial, "initial") == model.default_prompt()
    assert model.effective_prompt(initial, "continuation").startswith(model.GITHUB_MENTION)
    assert "Do NOT switch to Work mode" in initial["prompt"]
    custom = model.new_profile("UI research", copy=initial)
    custom["prompt"] = "Investigate UI behavior\nPreserve this exact line.  \n"
    wrapped = model.effective_prompt(custom, "initial")
    assert wrapped.startswith(model.GITHUB_MENTION)
    assert "ChatGPT is the only reasoning agent" in wrapped
    assert wrapped.endswith(custom["prompt"])
    assert custom["prompt"].endswith("  \n")
    assert custom["id"] != initial["id"] and not custom["enabled"]
    assert custom["project_name"] == "Hadalis Cloud"
    assert "Profile objective:" in model.effective_prompt(custom, "rotation")

    older = {"profiles": [{"id": custom["id"], "name": "Older", "prompt": custom["prompt"]}]}
    loaded, issues = model.normalize_config(older)
    assert not issues and loaded["profiles"][0]["mode"] == "manual"
    malformed, issues = model.normalize_config({"profiles": [older["profiles"][0], {"id": "bad/id"}]})
    assert len(malformed["profiles"]) == 1 and len(issues) == 1
    empty, issues = model.normalize_config({"profiles": []})
    assert empty["profiles"] == [] and not issues
    expect_error(lambda: model.update_profile(initial, {"delete_completed": True}), "confirmation")
    generic = model.update_profile(initial, {"requires_github": False})
    generic["id"] = "general-workflow"
    assert not model.effective_prompt(generic, "continuation").startswith(model.GITHUB_MENTION)
    fresh = model.new_profile("General objective")
    assert fresh["prompt"] == model.GENERIC_PROMPT and fresh["stop_on_done"]
    expect_error(lambda: model.update_profile(initial, {"project_name": "Wrong; project"}), "project name")
    expect_error(lambda: model.update_profile(initial, {"mode": "iterations"}), "iteration limit")

    run = {"started_at_unix": 100, "chat_started_at_unix": 150,
           "iterations": 4, "chat_iterations": 2, "prompts_sent": 5}
    limits = dict(initial, mode="iterations", iteration_limit=4, rotate_after_iterations=2)
    assert model.limit_decision(limits, run, 200) == "stop"
    limits.update(mode="continuous", iteration_limit=0)
    assert model.limit_decision(limits, run, 200) == "rotate"
    limits.update(mode="duration", duration_seconds=60, duration_action="pause")
    assert model.limit_decision(limits, run, 200) == "pause"
    limits.update(mode="continuous", rotate_after_iterations=0, prompt_limit=0,
                  rotate_after_seconds=0)
    assert model.limit_decision(limits, run, 200) is None
    state = {"owner_id": None, "profiles": {
        initial["id"]: {"desired": "run", "next_run_at_unix": 220},
        custom["id"]: {"desired": "run", "next_run_at_unix": 200},
    }}
    config = {"profiles": [initial, dict(custom, enabled=True)]}
    assert model.choose_profile(config, state, 210) == custom["id"]
    state["owner_id"] = initial["id"]
    assert model.choose_profile(config, state, 210) == initial["id"]

    def systemctl(argv, **_kwargs):
        unit = argv[3]
        if unit == "hadalis-chat-bridge.service":
            value = "LoadState=loaded\nActiveState=failed\nSubState=failed\nResult=exit-code\nExecMainStatus=75\n"
        elif unit == "hadalis-worker.service":
            value = "LoadState=loaded\nActiveState=inactive\nSubState=dead\nResult=success\nExecMainStatus=0\n"
        else:
            value = "LoadState=loaded\nActiveState=active\nSubState=running\nResult=success\nExecMainStatus=0\n"
        return SimpleNamespace(returncode=0, stdout=value, stderr="")
    with patch.object(control.subprocess, "run", side_effect=systemctl):
        services = control.service_states()
        assert services["bridge"]["state"] == "blocked"
        assert services["worker"]["state"] == "inactive"
        assert services["chatgpt"]["state"] == "active"
    expect_error(lambda: control.control_service("reload-or-arbitrary", "bridge"), "allowlisted")

    with tempfile.TemporaryDirectory() as tmp:
        with patch.dict(os.environ, {"XDG_CONFIG_HOME": tmp + "/config", "XDG_STATE_HOME": tmp + "/state"}):
            config, runtime, _ = store.read_snapshot()
            assert len(config["profiles"]) == 1 and len(runtime["profiles"]) == 1
            created = control.create_profile("A second session")
            pid = created["profile_id"]
            control.set_profile(pid, "enabled", "true")
            control.set_profile(pid, "mode", json.dumps("interval"))
            control.set_profile(pid, "interval_seconds", "120")
            control.set_profile(pid, "prompt", json.dumps(custom["prompt"]))
            control.set_profile(pid, "project_name", json.dumps("Hadalis Local"))
            with patch.object(control, "_ensure_runtime_services"), patch.object(control, "_await_dispatch"):
                control.profile_action("start", pid)
            config, runtime, _ = store.read_snapshot()
            edited = next(p for p in config["profiles"] if p["id"] == pid)
            assert edited["prompt"] == custom["prompt"]
            assert edited["project_name"] == "Hadalis Local"
            assert runtime["profiles"][pid]["desired"] == "run"
            store.change_state(lambda _config, state: state.__setitem__("owner_id", pid))
            control.set_profile(pid, "project_name", json.dumps("Another Project"))
            config, runtime, _ = store.read_snapshot()
            assert next(p for p in config["profiles"] if p["id"] == pid)["project_name"] == "Another Project"
            assert runtime["profiles"][pid]["active_project_name"] == "Hadalis Local"
            store.change_state(lambda _config, state: state.__setitem__("owner_id", None))
            control.profile_action("pause", pid)
            assert store.read_snapshot()[1]["profiles"][pid]["desired"] == "paused"
            with patch.object(control, "_ensure_runtime_services"), patch.object(control, "_await_dispatch"):
                control.profile_action("resume", pid)
            control.profile_action("stop", pid)
            expect_error(lambda: control.set_maintenance("delete_completed", "true"), "confirmation")
            control.set_maintenance("archive_completed", "false")
            control.set_maintenance("delete_completed", "true", confirm_delete=True)
            assert store.read_snapshot()[0]["maintenance"]["delete_completed"] is True
            assert control.reset_prompt(pid, "continuation_prompt")["reload_draft"]
            assert next(p for p in store.read_snapshot()[0]["profiles"] if p["id"] == pid)["continuation_prompt"] == model.CUSTOM_CONTINUATION_PROMPT
            control.remove_profile(pid)
            assert pid not in store.read_snapshot()[1]["profiles"]
            assert len(store.read_snapshot()[1]["events"]) <= store.EVENT_LIMIT
    print("PASS: Automation migration, profiles, limits, queue, and guarded controls")


if __name__ == "__main__":
    main()
