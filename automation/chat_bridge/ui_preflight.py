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
    if "--ui-loop-profile" in exec_start:
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
        pid != profile_id and isinstance(item, dict) and
        (item.get("desired") == "run" or item.get("pending") or
         item.get("job_id") or item.get("run_active"))
        for pid, item in entries.items())
    native_unsettled = any(
        isinstance(item, dict) and
        ((item.get("pending") and
          (not isinstance(item["pending"], dict) or
           item["pending"].get("transport") != "alis-ui-once")) or
         (item.get("session") and
          (not isinstance(item["session"], dict) or
           item["session"].get("transport") != "alis-ui-once")))
        for item in entries.values()) if isinstance(entries, dict) else True
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
    if service_state in {"active", "activating"} and service_mode == "ui_mode":
        reasons.append("UI_SCHEDULER_ALREADY_RUNNING")
    if service_state != "inactive":
        reasons.append("SERVICE_NOT_INACTIVE_FOR_CUTOVER")
    if service_mode not in {"native_mode", "ui_mode"}:
        reasons.append("UNIT_ENTRYPOINT_UNKNOWN")
    return {
        "purpose": "auto-f01-ui-cutover-preflight",
        "status": "read-only",
        "service_state": service_state,
        "installed_service_mode": service_mode,
        "profile_found": len(profiles) == 1 and isinstance(own, dict),
        "profile_enabled": bool(profiles and profiles[0].get("enabled")),
        "foreign_work_unsettled": bool(foreign_unsettled),
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
