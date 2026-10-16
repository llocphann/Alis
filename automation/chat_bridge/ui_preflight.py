"""Read-only, redacted Alis UI bridge cutover checks.

No Desktop/CDP connection, no systemd action, no writes, no manager lock
creation, no journal repair. A positive result is *not* send permission:
the installed Desktop target also needs independent UI observation.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess

from automation.manager import model, store

UNIT = "hadalis-chat-bridge.service"  # persisted compatibility unit


def inert_legacy_native_owner(config: dict, profile_id: str,
                              item: dict) -> bool:
    """Recognize a *preserved*, disabled old native conversation.

    This does not resolve, clear, send or adopt its original pending message.
    Only the separately opted-in single-owner UI scheduler may disregard
    this inert record; the native scheduler must still be stopped at cutover.
    """
    if not isinstance(item, dict):
        return False
    owners = [p for p in config.get("profiles", [])
              if p.get("id") == profile_id]
    if len(owners) != 1:
        return False
    profile = owners[0]
    if (profile.get("enabled") is not False
            or profile.get("description", "").startswith("taskflow:")
            or profile.get("description") == "taskflow-selector"
            or item.get("desired") != "stopped"
            or item.get("job_id") or item.get("remove_requested")):
        return False
    pending, session = item.get("pending"), item.get("session")
    if not isinstance(pending, dict) or not isinstance(session, dict):
        return False
    if (pending.get("transport") == "alis-ui-once"
            or session.get("transport") == "alis-ui-once"):
        return False
    return bool(pending) and bool(session)


def inert_native_session_history(config: dict, profile_id: str,
                                 item: dict) -> bool:
    """Historical-only native session cannot dispatch from an idle profile.

    A preserved conversation identifier is not itself an in-flight Send.
    This narrow exception never applies to an uncertain pending prompt,
    running/scheduled profile, local job, removal or recovery state.
    It changes admission classification only, not the durable record.
    """
    if not isinstance(item, dict):
        return False
    profiles = [p for p in config.get("profiles", [])
                if p.get("id") == profile_id]
    if len(profiles) != 1:
        return False
    session = item.get("session")
    return bool(
        isinstance(session, dict) and session
        and session.get("transport") != "alis-ui-once"
        and item.get("desired") == "stopped"
        and item.get("status") in {"idle", "completed", "disabled"}
        and item.get("pending") is None
        and item.get("job_id") is None
        and item.get("run_active") is False
        and not item.get("remove_requested")
        and item.get("recovery") is None
        and item.get("failed_turn") is None
    )


def idle_legacy_default_can_stop(config: dict, state: dict) -> bool:
    """Only the original, non-taskflow default profile can be stopped safely.

    Merely scheduled, without a pending send, worker job or dispatch intent;
    the user must still explicitly confirm before any state is mutated.
    """
    owners = [p for p in config.get("profiles", [])
              if p.get("id") == model.DEFAULT_ID]
    if len(owners) != 1:
        return False
    profile = owners[0]
    item = state.get("profiles", {}).get(model.DEFAULT_ID)
    return bool(
        isinstance(item, dict)
        and not str(profile.get("description", "")).startswith("taskflow:")
        and item.get("desired") == "run"
        and item.get("status") in {"scheduled", "idle", "scheduler_unavailable"}
        and item.get("pending") is None
        and item.get("job_id") is None
        and item.get("run_active") is False
        and item.get("recovery") is None
        and item.get("failed_turn") is None
        and not item.get("remove_requested")
    )


def has_unresolved_native_transport(item: dict) -> bool:
    """Inspect both session and pending; an UI pending cannot mask native session."""
    if not isinstance(item, dict):
        return True
    return any(
        bool(item.get(key)) and (
            not isinstance(item[key], dict)
            or item[key].get("transport") != "alis-ui-once")
        for key in ("pending", "session")
    )


def _document(path: Path) -> dict | None:
    if path.is_symlink():
        raise ValueError("ALIS_UI_SOURCE_IS_SYMLINK")
    if not path.exists():
        return None
    if not path.is_file() or path.stat().st_size > 4_000_000:
        raise ValueError("ALIS_UI_SOURCE_NOT_BOUNDED")
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise ValueError("ALIS_UI_SOURCE_UNREADABLE") from exc
    if not isinstance(raw, dict):
        raise ValueError("ALIS_UI_SOURCE_INVALID")
    return raw


def _unit_state() -> tuple[str, str]:
    try:
        completed = subprocess.run(
            ["systemctl", "--user", "show", UNIT,
             "--property=LoadState,ActiveState,ExecStart"],
            capture_output=True, text=True, check=False, timeout=4)
    except (OSError, subprocess.TimeoutExpired):
        return "unavailable", "unknown"
    if completed.returncode or len(completed.stdout) > 16000:
        return "unavailable", "unknown"
    fields = dict(line.split("=", 1) for line in completed.stdout.splitlines()
                  if "=" in line)
    if fields.get("LoadState") != "loaded":
        return "not_loaded", "unknown"
    active = fields.get("ActiveState")
    exec_start = fields.get("ExecStart", "")
    if "-m automation.manager.daemon" not in exec_start:
        return "unexpected_entrypoint", "unknown"
    if "--ui-loop-queue" in exec_start:
        mode = "ui_queue_mode"
    elif "--ui-loop-profile" in exec_start:
        mode = "ui_mode"
    else:
        mode = "native_mode"
    return active if active in {"active", "inactive", "failed", "activating"} else "unknown", mode


def examine(config: dict, state: dict, profile_id: str,
            *, service_state: str, service_mode: str,
            journal_pending: bool, issues: list[str] | None = None) -> dict:
    """Pure safety classification; no IDs, prompts, tokens or receipt data returned."""
    profiles = [p for p in config.get("profiles", []) if p.get("id") == profile_id]
    entries = state.get("profiles", {})
    own = entries.get(profile_id) if isinstance(entries, dict) else None
    foreign_unsettled = isinstance(entries, dict) and any(
        pid != profile_id and isinstance(item, dict)
        and not inert_legacy_native_owner(config, pid, item)
        and (item.get("desired") == "run" or item.get("pending")
             or item.get("job_id") or item.get("run_active"))
        for pid, item in entries.items())
    native_unsettled = any(
        has_unresolved_native_transport(item)
        for pid, item in entries.items()
        if not (pid != profile_id and (
            inert_legacy_native_owner(config, pid, item)
            or inert_native_session_history(config, pid, item)))
        ) if isinstance(entries, dict) else True
    own_pending = isinstance(own, dict) and bool(own.get("pending"))
    own_scheduled = isinstance(own, dict) and (
        own.get("desired") == "run" or bool(own.get("run_active")))
    own_job_waiting = isinstance(own, dict) and bool(own.get("job_id"))
    reasons = []
    if issues:
        reasons.append("PROFILE_CONFIGURATION_INVALID")
    if len(profiles) != 1 or not isinstance(own, dict):
        reasons.append("PROFILE_UNAVAILABLE")
    elif not profiles[0].get("enabled"):
        reasons.append("PROFILE_NOT_ENABLED")
    if foreign_unsettled:
        reasons.append("FOREIGN_PROFILE_UNSETTLED")
    if native_unsettled:
        reasons.append("NATIVE_SESSION_REQUIRES_REVIEW")
    if own_pending:
        reasons.append("ORIGINAL_SEND_UNRESOLVED")
    if own_scheduled:
        reasons.append("PROFILE_SCHEDULED_REQUIRES_EXPLICIT_STOP")
    if own_job_waiting:
        reasons.append("PROFILE_WAITING_ON_JOB")
    if journal_pending:
        reasons.append("UI_JOURNAL_UNRESOLVED")
    if service_state in {"active", "activating"} and service_mode != "ui_mode":
        reasons.append("NATIVE_SCHEDULER_ACTIVE")
    if service_state in {"active", "activating"} and service_mode in {"ui_mode", "ui_queue_mode"}:
        reasons.append("UI_SCHEDULER_ALREADY_RUNNING")
    if service_state != "inactive":
        reasons.append("SERVICE_NOT_INACTIVE_FOR_CUTOVER")
    if service_mode not in {"native_mode", "ui_mode", "ui_queue_mode"}:
        reasons.append("UNIT_ENTRYPOINT_UNKNOWN")
    return {
        "purpose": "auto-f01-ui-cutover-preflight",
        "status": "read-only",
        "service_state": service_state,
        "installed_service_mode": service_mode,
        "profile_found": len(profiles) == 1 and isinstance(own, dict),
        "profile_enabled": bool(profiles and profiles[0].get("enabled")),
        "foreign_work_unsettled": bool(foreign_unsettled),
        "legacy_native_pending_retained": any(
            pid != profile_id and inert_legacy_native_owner(config, pid, it)
            for pid, it in entries.items()) if isinstance(entries, dict) else False,
        "native_session_unsettled": bool(native_unsettled),
        "ui_manager_send_unsettled": bool(own_pending),
        "profile_already_scheduled": bool(own_scheduled),
        "profile_waiting_on_job": bool(own_job_waiting),
        "ui_journal_unsettled": bool(journal_pending),
        "preflight_blockers": reasons,
        "mode_change_preflight_clear": not reasons,
        "ui_target_identity_checked": False,
        "submission_authorized": False,
        "service_modified": False,
    }



def check_prepared_queue() -> dict:
    """Read-only AUTO-R01 queue admission diagnosis, never auto-create a profile.

    A generic, enabled Automation profile is NOT the owner of a prepared
    task-code queue. The queue's first SHA-pinned Issue will acquire its own
    deterministic profile only after separately authorized queue admission.
    """
    from automation import managed_tasks, queue, taskflow
    result = {
        "purpose": "auto-f01-queue-ui-readiness",
        "status": "read-only",
        "queue_state": "unknown",
        "queue_item_count": 0,
        "first_task_code": None,
        "taskflow_profile_present": False,
        "queue_ui_admission_available": False,
        "foreign_running_count": 0,
        "foreign_pending_count": 0,
        "foreign_job_count": 0,
        "native_unsettled_count": 0,
        "historical_native_session_count": 0,
        "idle_default_stop_available": False,
        "native_transport_authorized": False,
        "submission_authorized": False,
        "service_modified": False,
        "preflight_blockers": [],
    }
    try:
        raw_queue = _document(store.state_dir() / "taskflow" / "queue.json")
        raw_config = _document(store.config_path())
        config, issues = model.normalize_config(
            raw_config if raw_config is not None else model.default_config())
        raw_state = _document(store.state_path())
        state = store.normalize_state(
            raw_state if raw_state is not None else store.default_state(config),
            config)
    except (OSError, ValueError):
        result["preflight_blockers"] = ["LOCAL_STATE_UNREADABLE"]
        return result
    blockers = result["preflight_blockers"]
    if issues:
        blockers.append("PROFILE_CONFIGURATION_INVALID")
    if raw_queue is None:
        result["queue_state"] = "empty"
        blockers.append("NO_PREPARED_QUEUE")
        return result
    mode = raw_queue.get("mode")
    queue_state = raw_queue.get("state")
    if (raw_queue.get("schema") != queue.QUEUE_SCHEMA
            or not isinstance(mode, str) or mode not in queue.MODES
            or not isinstance(queue_state, str)
            or queue_state not in {
                "prepared", "active", "waiting", "stopping", "stopped",
                "finished", "cancelled",
            }
            or not isinstance(raw_queue.get("items"), list)):
        blockers.append("QUEUE_MANIFEST_INVALID")
        return result
    items = raw_queue["items"]
    result["queue_state"] = queue_state
    result["queue_item_count"] = len(items)
    if (raw_queue.get("state") != "prepared"
            or raw_queue.get("active") is not None
            or raw_queue.get("approved_start") is not False):
        blockers.append("QUEUE_NOT_IDLE_PREPARED")
        return result
    if not (1 <= len(items) <= queue.MAX_ITEMS):
        blockers.append("QUEUE_MANIFEST_INVALID")
        return result
    if any(not isinstance(entry, dict)
           or entry.get("state") not in {"queued", "deferred"}
           or entry.get("repository") not in taskflow.REPOSITORIES
           or not isinstance(entry.get("code"), str)
           or not taskflow.CODE.fullmatch(entry["code"])
           or not isinstance(entry.get("source_sha"), str)
           or not taskflow.SHA.fullmatch(entry["source_sha"])
           for entry in items):
        blockers.append("QUEUE_MANIFEST_INVALID")
        return result
    first = next((entry for entry in items if entry["state"] == "queued"), None)
    if first is None:
        blockers.append("NO_ELIGIBLE_NEW_TASK")
        return result
    result["first_task_code"] = first["code"]
    expected_id = managed_tasks.profile_id(first["repository"], first["code"])
    profile = next((p for p in config["profiles"]
                    if p["id"] == expected_id), None)
    result["taskflow_profile_present"] = bool(
        profile and managed_tasks.reference(profile)
        == (first["repository"], first["code"]))
    if not result["taskflow_profile_present"]:
        blockers.append("TASKFLOW_PROFILE_NOT_MATERIALIZED")
    else:
        # A profile merely existing in config cannot unlock Start. It may
        # retain an original uncertain UI send or a worker receipt.
        # Match start_ui_queue's actual idle/owner checks, without reads
        # that expose the private session or changing any state.
        runtime = state.get("profiles", {}).get(expected_id)
        if (not profile.get("enabled")
                or profile.get("project_name") != model.DEFAULT_PROJECT
                or not isinstance(runtime, dict)
                or runtime.get("desired") != "stopped"
                or runtime.get("pending") or runtime.get("job_id")
                or runtime.get("session") or runtime.get("run_active")
                or runtime.get("last_ui_response_attempt")):
            blockers.append("TASKFLOW_PROFILE_NOT_IDLE")
    entries = state.get("profiles", {})
    isolated = {
        pid for pid, item in entries.items()
        if pid != expected_id and inert_legacy_native_owner(config, pid, item)
    }
    history_only = {
        pid for pid, item in entries.items()
        if pid != expected_id
        and inert_native_session_history(config, pid, item)
    }
    result["legacy_native_pending_retained"] = bool(isolated)
    result["historical_native_session_count"] = len(history_only)
    result["idle_default_stop_available"] = (
        idle_legacy_default_can_stop(config, state)
        and expected_id != model.DEFAULT_ID)
    foreign = [
        item for pid, item in entries.items()
        if pid != expected_id and isinstance(item, dict) and pid not in isolated
    ]
    result["foreign_running_count"] = sum(
        item.get("desired") == "run" or bool(item.get("run_active"))
        for item in foreign)
    result["foreign_pending_count"] = sum(
        bool(item.get("pending")) for item in foreign)
    result["foreign_job_count"] = sum(
        bool(item.get("job_id")) for item in foreign)
    if any((item.get("pending") or item.get("job_id")
            or item.get("run_active") or item.get("desired") == "run")
           for item in foreign):
        blockers.append("FOREIGN_PROFILE_UNSETTLED")
    result["native_unsettled_count"] = sum(
        has_unresolved_native_transport(item)
        for pid, item in entries.items()
        if pid not in isolated and pid not in history_only)
    if result["native_unsettled_count"]:
        blockers.append("NATIVE_SESSION_REQUIRES_REVIEW")
    service, mode = _unit_state()
    result["installed_service_mode"] = mode
    result["service_state"] = service
    if service != "inactive" or mode not in {"native_mode", "ui_mode", "ui_queue_mode"}:
        blockers.append("SCHEDULER_CUTOVER_NOT_READY")
    # Native Start remains server-receipt-gated. The separate queue-only
    # UI path requires explicit, informed owner acceptance of UI-only receipts.
    if service == "active" and mode == "ui_queue_mode":
        blockers.append("UI_QUEUE_OWNER_ACCEPTANCE_REQUIRED")
    else:
        blockers.append("UI_TASK_QUEUE_INTEGRATION_NOT_ACCEPTED")
    return result


def check(profile_id: str) -> dict:
    if not re.fullmatch(r"[A-Za-z0-9._:-]{1,100}", profile_id):
        raise ValueError("ALIS_UI_PROFILE_ID_INVALID")
    try:
        config_raw = _document(store.config_path())
        config, issues = model.normalize_config(
            config_raw if config_raw is not None else model.default_config())
        state_raw = _document(store.state_path())
        state = store.normalize_state(
            state_raw if state_raw is not None else store.default_state(config),
            config)
    except ValueError:
        return examine({}, {"profiles": {}}, profile_id,
                       service_state="unknown", service_mode="unknown",
                       journal_pending=True,
                       issues=["ALIS_UI_LOCAL_STATE_UNREADABLE"])
    service, mode = _unit_state()
    tombstone = store.state_dir() / "ui-send-journal" / "pending.json"
    return examine(config, state, profile_id, service_state=service,
                   service_mode=mode,
                   journal_pending=tombstone.exists() or tombstone.is_symlink(),
                   issues=issues)
