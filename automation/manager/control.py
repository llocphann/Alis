from __future__ import annotations

import json
import fcntl
import subprocess
import time

from .model import (CUSTOM_CONTINUATION_PROMPT, CUSTOM_ROTATION_PROMPT,
                    DEFAULT_ID, MAX_PROFILES, MAINTENANCE_DEFAULTS, PROFILE_DEFAULTS,
                    default_prompt, new_profile, update_profile)
from .store import change, change_state, event, profile_state, read_snapshot, state_dir, _write

UNITS = {
    "chatgpt": "hadalis-chatgpt.service",
    "worker": "hadalis-worker.service",
    "bridge": "hadalis-chat-bridge.service",
}
SERVICE_ACTIONS = {"start", "stop", "restart"}
PROFILE_ACTIONS = {"start", "pause", "resume", "stop", "restart"}
HEARTBEAT_STALE_SECONDS = 180
DISPATCH_ACK_SECONDS = 12


def _ensure_runtime_services() -> None:
    """Backend/worker stay available even if the Desktop transport is down."""
    current = service_states()
    required = ("worker", "bridge")
    for key in required:
        if current[key]["state"] == "unavailable":
            raise RuntimeError("Automation units unavailable; run python3 scripts/install-hadalis-automation.py --enable-now")
        if current[key]["state"] != "active":
            result = subprocess.run(["systemctl", "--user", "start", UNITS[key]],
                capture_output=True, text=True, timeout=20, check=False)
            if result.returncode:
                raise RuntimeError("could not start " + UNITS[key])
    if current["chatgpt"]["state"] not in {"active", "unavailable"}:
        # Desktop failure is a transport condition, not a backend dependency.
        try:
            subprocess.run(["systemctl", "--user", "start", UNITS["chatgpt"]],
                capture_output=True, text=True, timeout=20, check=False)
        except (OSError, subprocess.TimeoutExpired):
            pass


def control_unit_name(key: str) -> str:
    return UNITS[key]


def _scheduler_problem(services: dict, state: dict, now: int) -> str:
    host = services["chatgpt"]
    if host["state"] != "active" and host.get("exec_main_status") == "76":
        return ("ChatGPT was opened without the Automation connection. "
                "Close ChatGPT once, reopen it from Applications, then press Start. "
                "Your existing response and chat history are kept.")
    bridge = services["bridge"]
    if bridge["state"] != "active":
        detail = bridge.get("result") or bridge.get("detail") or "not running"
        return f'Chat bridge is {bridge["state"]} ({detail}); start the Automation services'
    heartbeat = state.get("manager_heartbeat_at_unix")
    if type(heartbeat) is int and now - heartbeat > HEARTBEAT_STALE_SECONDS:
        return (f"Chat bridge scheduler heartbeat is older than {HEARTBEAT_STALE_SECONDS}s; "
                "inspect its user journal")
    for key in ("chatgpt", "worker"):
        service = services[key]
        if service["state"] != "active":
            return f"{control_unit_name(key)} is {service['state']} ({service.get('result') or service.get('detail') or 'not running'})"
    if heartbeat is None:
        due = [item.get("next_run_at_unix") for item in state["profiles"].values()
               if item.get("desired") == "run" and type(item.get("next_run_at_unix")) is int]
        if due and now - min(due) > HEARTBEAT_STALE_SECONDS:
            return "Chat bridge is active but has never reported a scheduler tick"
    return ""




def service_states() -> dict:
    result = {}
    for key, unit in UNITS.items():
        try:
            output = subprocess.run(
                ["systemctl", "--user", "show", unit,
                 "--property=LoadState,ActiveState,SubState,Result,ExecMainStatus,WorkingDirectory,ExecStart"],
                capture_output=True, text=True, timeout=4, check=False,
            )
            values = dict(line.split("=", 1) for line in output.stdout.splitlines() if "=" in line)
            active = values.get("ActiveState", "unknown")
            loaded = values.get("LoadState", "unknown")
            outcome = values.get("Result", "")
            if loaded != "loaded":
                state = "unavailable"
            elif active in {"active", "activating", "deactivating", "failed", "inactive"}:
                state = {"activating": "starting", "deactivating": "stopping"}.get(active, active)
            else:
                state = "unavailable"
            if key == "bridge" and state == "failed" and values.get("ExecMainStatus") == "75":
                state = "blocked"
            if key == "bridge" and state == "inactive" and outcome not in {"", "success"}:
                state = "failed"
            result[key] = {"unit": unit, "state": state,
                           "detail": values.get("SubState", ""), "result": outcome,
                           "exec_main_status": values.get("ExecMainStatus", ""),
                           "working_directory": values.get("WorkingDirectory", ""),
                           "exec_start": values.get("ExecStart", "")}
        except (OSError, subprocess.TimeoutExpired):
            result[key] = {"unit": unit, "state": "unavailable",
                           "detail": "systemd user manager unavailable", "result": "",
                           "exec_main_status": "", "working_directory": "", "exec_start": ""}
    return result


def status() -> dict:
    """Observe health without mutating the scheduler's own run status.

    UI status polling must not fight the manager heartbeat over its state or
    flood the 100-entry Activity ring with false recovery events.
    """
    config, state, issues = read_snapshot()
    services = service_states()
    pool_path=state_dir()/"worker/pool.json"
    try:pool=json.loads(pool_path.read_text()) if pool_path.exists() else {}
    except (OSError,ValueError):pool={"last_error":"Worker status receipt unreadable"}
    from .credentials import status as credential_status
    return {"ok": True, "config": config, "runtime": state, "issues": issues,
            "credentials":credential_status(),
            "services": services,"worker_pool":pool,
            "scheduler_problem": _scheduler_problem(services, state, int(time.time())),
            "capabilities": {
                "archive_chat": False, "delete_chat": False,
                "stuck_generation_recovery": False, "composer_recovery": False,
                "stream_poll_recovery": True, "transport_retry": True,
                "single_transport_owner": False, "independent_sessions": True,
                "concurrent_profiles": True, "shell_independent": True,
            }}


def control_service(action: str, key: str) -> dict:
    if action not in SERVICE_ACTIONS or key not in UNITS:
        raise ValueError("service action or unit not allowlisted")
    result = subprocess.run(["systemctl", "--user", action, UNITS[key]],
                            capture_output=True, text=True, timeout=20, check=False)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()[:2000]
        change_state(lambda _config, state: event(
            state, None, "service_action_failed", f"{action} {UNITS[key]}: {detail}"))
        raise RuntimeError(detail)
    change_state(lambda _config, state: event(state, None, "service_" + action, UNITS[key]))
    return {"ok": True}


def _await_dispatch(profile_id: str, command_seq: int) -> None:
    deadline = time.monotonic() + DISPATCH_ACK_SECONDS
    while time.monotonic() < deadline:
        _, state, issues = read_snapshot()
        item = state["profiles"].get(profile_id)
        if not item: raise RuntimeError("profile removed before dispatch")
        heartbeat = state.get("manager_heartbeat_at_unix")
        if type(heartbeat) is int and 0 <= int(time.time()) - heartbeat <= 15 and state["command_ack_seq"] >= command_seq:
            if item["desired"] != "run": raise RuntimeError("profile stopped before dispatch")
            if item["run_active"] or item["pending"] or item["job_id"]:
                return
        time.sleep(0.25)
    raise RuntimeError("Start saved, but no fresh scheduler acknowledgement; inspect the backend service")


def profile_action(action: str, profile_id: str) -> dict:
    if action not in PROFILE_ACTIONS: raise ValueError("profile action not allowlisted")
    def mutate(config, state):
        profile = next((p for p in config["profiles"] if p["id"] == profile_id), None)
        if profile is None: raise ValueError("profile not found")
        item = state["profiles"][profile_id]
        if item["remove_requested"]: raise ValueError("this profile is being removed")
        if action in {"start", "resume", "restart"}:
            if not profile["enabled"]: raise ValueError("enable the profile first")
            if action == "resume" and item["desired"] != "paused": raise ValueError("profile is not paused")
            state["command_seq"] += 1
            item.update(desired="run", command_seq=state["command_seq"], next_run_at_unix=int(time.time()),
                        poll_errors=0, job_poll_errors=0, status_detail="")
            if item["pending"]:
                item["pending"]["poll_after_unix"] = int(time.time())
                item["status"] = "recovering_pending"
                event(state, profile_id, "pending_recovery_requested", "Observe original message; never resend")
            else:
                item["status"] = "scheduled"
            if action == "restart":
                if item["job_id"] and not item["pending"]:
                    _write(state_dir()/"worker/cancellations"/item["job_id"],{"profile_id":profile_id,"reason":"profile restart","at_unix":int(time.time())})
                    event(state, profile_id, "job_wait_abandoned", item["job_id"])
                    item.update(job_id=None, next_job_poll_at_unix=None)
                item["request"] = "restart"
            elif action == "start" and not item["pending"] and not item["job_id"]:
                item["request"] = "new"
            elif not item["request"]:
                item["request"] = "continuation" if item["session"] else "initial"
        else:
            item["desired"] = "paused" if action == "pause" else "stopped"
            item["status"] = "pausing" if item["pending"] else "paused" if action == "pause" else "idle"
            item["status_detail"] = ""
            # Monitoring remains available after Stop, including an uncertain send.
            if item["pending"]: item["pending"]["poll_after_unix"] = int(time.time())
        event(state, profile_id, action)
        return item["command_seq"]
    seq = change_state(mutate)
    if action in {"start", "resume", "restart"}:
        try:
            _ensure_runtime_services()
            _await_dispatch(profile_id, seq)
        except RuntimeError as exc:
            def failed(c, s):
                item = s["profiles"].get(profile_id)
                if item:
                    item.update(status="scheduler_unavailable", last_error=str(exc)[:1000])
                    event(s, profile_id, "start_failed", item["last_error"])
            change_state(failed)
            raise
    return {"ok": True}


def cancel_job(profile_id):
    def cancel(c,s):
        item=s["profiles"].get(profile_id)
        if not item or not item["job_id"]:raise ValueError("profile has no active local job")
        job=item["job_id"]
        if not isinstance(job,str) or not __import__('re').fullmatch(r"JOB-[A-Za-z0-9._-]+",job):raise ValueError("invalid job identity")
        _write(state_dir()/"worker/cancellations"/job,{"profile_id":profile_id,"reason":"user cancellation","at_unix":int(time.time())})
        event(s,profile_id,"job_cancel_requested",job)
    change_state(cancel)
    return {"ok":True}


def request_park_unresolved(owner_id: str) -> dict:
    # Compatibility endpoint only. Isolation makes transport handover obsolete.
    raise ValueError("Profiles run independently; unresolved sessions are retained and reconciled without parking")


def create_profile(name: str, duplicate_id: str | None = None) -> dict:
    def mutate(config: dict, state: dict):
        if len(config["profiles"]) >= MAX_PROFILES:
            raise ValueError("profile limit reached")
        source = None
        if duplicate_id:
            source = next((item for item in config["profiles"] if item["id"] == duplicate_id), None)
            if source is None:
                raise ValueError("source profile not found")
        profile = new_profile(name, copy=source)
        config["profiles"].append(profile)
        state["profiles"][profile["id"]] = profile_state()
        event(state, profile["id"], "created")
        return {"ok": True, "profile_id": profile["id"]}
    return change(mutate)


def set_profile(profile_id: str, field: str, value_json: str, confirm_delete: bool = False) -> dict:
    value = json.loads(value_json)

    def mutate(config: dict, state: dict):
        for index, profile in enumerate(config["profiles"]):
            if profile["id"] == profile_id:
                item = state["profiles"][profile_id]
                if (field == "project_name" and not item.get("active_project_name")
                        and (state["owner_id"] == profile_id or item["pending"] is not None)):
                    # Migration-safe staging: capture the project of an
                    # already-open/pending chat before editing its next-chat target.
                    item["active_project_name"] = profile["project_name"]
                config["profiles"][index] = update_profile(
                    profile, {field: value}, confirm_delete=confirm_delete)
                if field == "enabled" and value is False:
                    item["desired"] = "stopped"
                    item["status"] = ("parked_unresolved" if item.get("parked_pending")
                                      else "stopping" if item["run_active"] or item["pending"]
                                      else "disabled")
                elif field == "enabled" and value is True:
                    item["status"] = "parked_unresolved" if item.get("parked_pending") else "idle"
                event(state, profile_id, "updated", field)
                return
        raise ValueError("profile not found")

    change(mutate)
    return {"ok": True}


def reset_prompt(profile_id: str, field: str) -> dict:
    defaults = {"prompt": default_prompt(),
                "continuation_prompt": PROFILE_DEFAULTS["continuation_prompt"] if profile_id == DEFAULT_ID else CUSTOM_CONTINUATION_PROMPT,
                "rotation_prompt": PROFILE_DEFAULTS["rotation_prompt"] if profile_id == DEFAULT_ID else CUSTOM_ROTATION_PROMPT}
    if field not in defaults:
        raise ValueError("prompt field not allowlisted")

    def mutate(config: dict, state: dict):
        for index, profile in enumerate(config["profiles"]):
            if profile["id"] == profile_id:
                config["profiles"][index] = update_profile(profile, {field: defaults[field]})
                event(state, profile_id, "prompt_reset", field)
                return
        raise ValueError("profile not found")
    change(mutate)
    return {"ok": True, "reload_draft": True}


def set_maintenance(field: str, value_json: str, confirm_delete: bool = False) -> dict:
    if field not in MAINTENANCE_DEFAULTS:
        raise ValueError("maintenance field not allowlisted")
    value = json.loads(value_json)
    if type(value) is not bool:
        raise ValueError("maintenance value must be boolean")
    if field == "delete_completed" and value and not confirm_delete:
        raise ValueError("delete requires explicit confirmation")

    def mutate(config: dict, state: dict):
        if value and field in {"archive_completed", "delete_completed"}:
            other = "delete_completed" if field == "archive_completed" else "archive_completed"
            if config["maintenance"][other]:
                raise ValueError("archive and delete are mutually exclusive")
        config["maintenance"][field] = value
        event(state, None, "maintenance_updated", field)
    change(mutate)
    return {"ok": True}


def remove_profile(profile_id: str, confirmed_unresolved: bool = False) -> dict:
    if confirmed_unresolved:
        # Only the single transport owner processes live removal between
        # ticks. Never delete a profile while its Desktop command is in flight.
        def request(config: dict, state: dict):
            if profile_id not in state["profiles"]:
                raise ValueError("profile not found")
            item = state["profiles"][profile_id]
            profile = next(p for p in config["profiles"] if p["id"] == profile_id)
            profile["enabled"] = False
            item["desired"] = "stopped"
            item["remove_requested"] = True
            item["status_detail"] = "Removal queued; a private recovery copy will be saved. ChatGPT history stays."
            if state.get("requested_profile_id") == profile_id:
                state["requested_profile_id"] = None
            event(state, profile_id, "removal_requested",
                  "Explicit confirmation to stop tracking and remove; ChatGPT history retained")
        change(request)
        # A stopped/failed bridge has no consumer. Process only this local
        # removal under the same transport lock, without starting ChatGPT.
        with (state_dir() / "chat-bridge.lock").open("a+") as handle:
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return {"ok": True}
            from .daemon import _handle_removals
            config, state, _issues = read_snapshot()
            _handle_removals(config, state)
        return {"ok": True}

    # If a dead scheduler stranded ownership, a fully stopped profile without
    # an in-flight ChatGPT response can release that stale lease safely.
    # Never discard a pending (possibly submitted) prompt.
    config, state, _issues = read_snapshot()
    if state["owner_id"] == profile_id:
        item = state["profiles"][profile_id]
        if item["desired"] != "stopped" or item["pending"] is not None:
            raise ValueError("stop the profile and finish its current response before removing it")
        if not _scheduler_problem(service_states(), state, int(time.time())):
            raise ValueError("the scheduler still owns this profile; retry after it releases the chat")

    def mutate(config: dict, state: dict):
        if profile_id not in state["profiles"]:
            raise ValueError("profile not found")
        item = state["profiles"][profile_id]
        if item["pending"] is not None and not item.get("parked_pending"):
            raise ValueError("cannot remove profile with a pending ChatGPT response")
        if state["owner_id"] == profile_id:
            item = state["profiles"][profile_id]
            if item["desired"] != "stopped" or item["pending"] is not None:
                raise ValueError("the profile is still running or has a pending response")
            state["owner_id"] = None
            event(state, profile_id, "stale_owner_released")
        config["profiles"] = [item for item in config["profiles"] if item["id"] != profile_id]
        if state.get("requested_profile_id") == profile_id:
            state["requested_profile_id"] = None
        parked = bool(state["profiles"][profile_id].get("parked_pending"))
        state["profiles"].pop(profile_id)
        event(state, profile_id, "removed",
              "ChatGPT history retained; parked recovery metadata discarded"
              if parked else "ChatGPT history retained")
    change(mutate)
    return {"ok": True}
