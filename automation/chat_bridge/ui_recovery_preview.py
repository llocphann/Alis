"""Redacted, read-only preview of an original UI send awaiting reconciliation.

Not a response receipt, a send capability, or authority to advance a queue.
No Desktop access, service control, queue writes, credential access or replay.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import uuid

from automation import managed_tasks

_SHA = re.compile(r"[0-9a-f]{64}\Z")
_TAIL = re.compile(r"\nAlis UI request token: ([0-9a-f-]{36})\n\Z")
_MAX_PRIVATE_JOURNAL = 120_000


def preview(manifest: dict | None, config: dict, state: dict,
            journal_path: Path) -> dict:
    reply = {
        "phase": "not_eligible", "queue_state": "none",
        "active_code": None, "ui_pending": False,
        "original_prompt_integrity": False,
        "first_turn_anchor_present": False,
        "original_journal": "not_checked",
        "read_only_observation_candidate": False,
        "owner_confirmation_required": True,
        "send_or_queue_start_authorized": False,
        "reason": "NO_ACTIVE_ORIGINAL_UI_QUEUE",
    }
    if not isinstance(manifest, dict):
        return reply
    reply["queue_state"] = str(manifest.get("state", "invalid"))[:48]
    active = manifest.get("active")
    if (manifest.get("mode") != "ordered"
            or manifest.get("state") not in {"stopping", "stopped"}
            or not isinstance(active, dict)
            or not manifest.get("stop_requested")
            or manifest.get("approved_start") is True):
        return reply
    repository, code = active.get("repository"), active.get("code")
    if (not isinstance(repository, str) or not isinstance(code, str)
            or not re.fullmatch(r"[A-Z][A-Z0-9-]{1,63}", code)):
        return reply
    # Expose only the canonical Issue task code, not profile names or chat IDs.
    reply["active_code"] = code
    members = [item for item in manifest.get("items", [])
               if isinstance(item, dict)
               and item.get("code") == code
               and item.get("repository") == repository
               and item.get("state") == "active"]
    if len(members) != 1:
        reply["reason"] = "QUEUE_ACTIVE_MEMBER_UNVERIFIED"
        return reply
    try:
        pid = managed_tasks.profile_id(repository, code)
    except (ValueError, KeyError, TypeError):
        reply["reason"] = "QUEUE_ACTIVE_MEMBER_UNVERIFIED"
        return reply
    profiles = [profile for profile in config.get("profiles", [])
                if profile.get("id") == pid]
    item = state.get("profiles", {}).get(pid)
    if len(profiles) != 1 or not isinstance(item, dict):
        reply["reason"] = "ORIGINAL_PROFILE_MISSING"
        return reply
    if (managed_tasks.reference(profiles[0]) != (repository, code)
            or item.get("desired") not in {"paused", "stopped"}
            or item.get("run_active")
            or item.get("job_id")):
        reply["reason"] = "ORIGINAL_PROFILE_NOT_IDLE"
        return reply
    pending = item.get("pending")
    if not isinstance(pending, dict) or pending.get("transport") != "alis-ui-once":
        reply["reason"] = "ORIGINAL_UI_PENDING_NOT_FOUND"
        return reply
    reply["ui_pending"] = True
    prompt, attempt = pending.get("prompt"), pending.get("attempt_id")
    if not isinstance(prompt, str) or not isinstance(attempt, str):
        reply["reason"] = "ORIGINAL_PROMPT_UNVERIFIED"
        return reply
    try:
        valid_attempt = str(uuid.UUID(attempt)) == attempt
    except (ValueError, AttributeError):
        valid_attempt = False
    tokens = re.findall(r"\nAlis UI request token: [0-9a-f-]{36}\n", prompt)
    tail = _TAIL.search(prompt)
    digest = hashlib.sha256(prompt.encode("utf-8")).hexdigest()
    if (not valid_attempt or len(tokens) != 1 or tail is None
            or tail.group(1) != attempt
            or pending.get("prompt_sha256") != digest
            or pending.get("kind") not in {"continuation", "initial", "rotation"}
            or len(prompt) > 120_000):
        reply["reason"] = "ORIGINAL_PROMPT_UNVERIFIED"
        return reply
    reply["original_prompt_integrity"] = True
    target = (item.get("session") or {}).get("ui_target_key")
    if not isinstance(target, str) or not _SHA.fullmatch(target):
        reply["reason"] = "FIRST_TURN_ANCHOR_MISSING"
        return reply
    reply["first_turn_anchor_present"] = True
    # Read only the existing original journal. No recovery writes or
    # authorization from a file's mere presence.
    if journal_path.is_symlink() or journal_path.parent.is_symlink():
        reply["original_journal"] = "unsafe_path"
        reply["reason"] = "ORIGINAL_JOURNAL_UNVERIFIED"
        return reply
    try:
        if not journal_path.is_file():
            reply["original_journal"] = "missing"
            reply["reason"] = "ORIGINAL_JOURNAL_UNVERIFIED"
            return reply
        if journal_path.stat().st_size > _MAX_PRIVATE_JOURNAL:
            reply["original_journal"] = "invalid"
            reply["reason"] = "ORIGINAL_JOURNAL_UNVERIFIED"
            return reply
        journal = json.loads(journal_path.read_text(encoding="utf-8"))
    except (OSError, ValueError, UnicodeError):
        reply["original_journal"] = "unreadable"
        reply["reason"] = "ORIGINAL_JOURNAL_UNVERIFIED"
        return reply
    command = "send" if pending["kind"] == "continuation" else "rotate-send"
    journal_id = journal.get("id") if isinstance(journal, dict) else None
    try:
        valid_journal_id = (isinstance(journal_id, str)
                            and str(uuid.UUID(journal_id)) == journal_id)
    except (ValueError, AttributeError):
        valid_journal_id = False
    if (not valid_journal_id or not isinstance(journal, dict)
            or journal.get("schema") != "alis.chat-ui-send.v1"
            or journal.get("phase") != "attempted"
            or journal.get("prompt_sha256") != digest
            or journal.get("command") != command):
        reply["original_journal"] = "mismatch"
        reply["reason"] = "ORIGINAL_JOURNAL_UNVERIFIED"
        return reply
    reply["original_journal"] = "matching_attempt"
    reply["read_only_observation_candidate"] = True
    reply["phase"] = "original_observation_candidate"
    reply["reason"] = "LIVE_UI_CONTINUITY_AND_OWNER_REVIEW_REQUIRED"
    return reply
