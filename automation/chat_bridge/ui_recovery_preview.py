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
_MAX_ARCHIVE_ENTRIES = 512


def _private_record(path: Path) -> dict | None:
    """Bounded, no-follow read; not a receipt acceptance or a write."""
    import os
    import stat
    if path.parent.is_symlink() or path.is_symlink():
        return None
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            info = os.fstat(fd)
            if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1
                    or not 0 < info.st_size <= _MAX_PRIVATE_JOURNAL):
                return None
            with os.fdopen(fd, "r", encoding="utf-8") as stream:
                fd = -1
                data = json.load(stream)
        finally:
            if fd >= 0:
                os.close(fd)
    except (OSError, ValueError, UnicodeError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None


def _retired_attempt_evidence(journal_path: Path, profile_id: str,
                              attempt: str, digest: str, command: str,
                              prepared_at: object) -> str:
    """Archived journal classification only; never a completion signal."""
    if type(prepared_at) is not int or prepared_at < 0:
        return "retired_evidence_unverified"
    if journal_path.parent.is_symlink() or journal_path.parent.parent.is_symlink():
        return "unsafe_path"
    # Journal attempt UUID and manager UI attempt UUID are deliberately
    # different. Find exact SHA-bound archived attempts, not a filename
    # constructed from the manager's pending attempt ID.
    tombstones = []
    for directory, outcome in (
            ("interrupted", "interrupted_delivered"),
            ("not-sent", "not_sent")):
        archive_dir = journal_path.parent / directory
        if archive_dir.is_symlink():
            return "tombstone_review_required"
        if not archive_dir.exists():
            continue
        if not archive_dir.is_dir():
            return "tombstone_review_required"
        count = 0
        try:
            for location in archive_dir.glob("*.json"):
                count += 1
                if count > _MAX_ARCHIVE_ENTRIES:
                    return "tombstone_review_required"
                record = _private_record(location)
                if record is None:
                    return "tombstone_review_required"
                if (record.get("prompt_sha256") != digest
                        or record.get("command") != command
                        or record.get("outcome") != outcome):
                    continue
                rid = record.get("id")
                try:
                    valid_id = isinstance(rid, str) and str(uuid.UUID(rid)) == rid
                except (ValueError, AttributeError):
                    valid_id = False
                if (not valid_id or location.name != rid + ".json"
                        or record.get("schema") != "alis.chat-ui-send.v1"
                        or type(record.get("at_unix")) is not int
                        or record["at_unix"] < prepared_at):
                    return "tombstone_review_required"
                if outcome == "interrupted_delivered":
                    if (record.get("delivery_acknowledged") is not True
                            or record.get("completion_acknowledged") is not False
                            or not isinstance(record.get("proof_sha256"), str)
                            or not _SHA.fullmatch(record["proof_sha256"])):
                        return "tombstone_review_required"
                elif (record.get("delivery_acknowledged") is not False
                      or record.get("evidence") not in {
                          "desktop-pre-send-receipt", "owner-confirmed-not-sent"}):
                    return "tombstone_review_required"
                tombstones.append(outcome)
        except (OSError, ValueError):
            return "tombstone_review_required"
    if len(tombstones) > 1:
        return "tombstone_conflict"
    if tombstones:
        # A retained "observed" journal and an interrupted/not-sent
        # tombstone for the SAME SHA are contradictory, irrespective of
        # their distinct journal IDs. Never accept either as authoritative.
        observed = journal_path.parent / "observed"
        if observed.is_symlink():
            return "archive_review_required"
        if observed.exists():
            if not observed.is_dir():
                return "archive_review_required"
            count = 0
            try:
                for path in observed.glob("*.json"):
                    count += 1
                    if count > _MAX_ARCHIVE_ENTRIES:
                        return "archive_review_required"
                    record = _private_record(path)
                    if record is None:
                        return "archive_review_required"
                    if (record.get("prompt_sha256") == digest
                            and record.get("command") == command):
                        return "tombstone_conflict"
            except (OSError, ValueError):
                return "archive_review_required"
        return ("original_interrupted_delivery" if tombstones[0] == "interrupted_delivered"
                else "original_confirmed_not_sent")
    root = journal_path.parent.parent
    if (journal_path.parent.is_symlink()
            or root.is_symlink()):
        return "unsafe_path"
    response = _private_record(root / "ui-responses" / profile_id /
                               (attempt + ".json"))
    if (response is None or response.get("transport") != "alis-ui-once"
            or response.get("attempt_id") != attempt
            or not isinstance(response.get("response"), str)
            or type(response.get("at_unix")) is not int
            or response["at_unix"] < prepared_at):
        return "retired_evidence_unverified"
    archive = journal_path.parent / "observed"
    if archive.is_symlink() or not archive.is_dir():
        return "retired_evidence_unverified"
    matches = 0
    visited = 0
    try:
        for record_path in archive.glob("*.json"):
            visited += 1
            if visited > _MAX_ARCHIVE_ENTRIES:
                return "archive_review_required"
            record = _private_record(record_path)
            if record is None:
                return "archive_review_required"
            if (record.get("schema") == "alis.chat-ui-send.v1"
                    and record.get("phase") == "attempted"
                    and record.get("prompt_sha256") == digest
                    and record.get("command") == command
                    and type(record.get("at_unix")) is int
                    and prepared_at <= record["at_unix"] <= response["at_unix"]):
                record_id = record.get("id")
                try:
                    valid_id = (isinstance(record_id, str)
                                and str(uuid.UUID(record_id)) == record_id)
                except (ValueError, AttributeError):
                    valid_id = False
                if not valid_id or record_path.name != record_id + ".json":
                    return "archive_review_required"
                matches += 1
                matched_id = record_id
    except (OSError, ValueError):
        return "retired_evidence_unverified"
    if matches != 1:
        return "archive_ambiguous" if matches > 1 else "retired_evidence_unverified"
    # A legacy response may predate ui_send_intent. If it does carry that
    # provenance, do not classify a different archived journal as the
    # original, even when both share a full prompt SHA and time window.
    if "ui_send_intent" in response:
        intent = response["ui_send_intent"]
        if (not isinstance(intent, dict)
                or set(intent) != {"id", "command", "prompt_sha256"}
                or intent != {"id": matched_id, "command": command,
                              "prompt_sha256": digest}):
            return "retired_response_intent_mismatch"
        return "unique_retired_attempt_bound"
    return "unique_retired_attempt"


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
    # State is a fixed protocol enum, never echo untrusted disk text.
    state_name = manifest.get("state")
    reply["queue_state"] = (
        state_name if isinstance(state_name, str)
        and state_name in {"prepared", "waiting", "active", "stopping",
                           "stopped", "review_required", "finished",
                           "cancelled", "empty"}
        else "invalid")
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
    configured = config.get("profiles") if isinstance(config, dict) else None
    running = state.get("profiles") if isinstance(state, dict) else None
    if (not isinstance(configured, list)
            or not isinstance(running, dict)
            or any(not isinstance(profile, dict) for profile in configured)):
        reply["reason"] = "ORIGINAL_PROFILE_MISSING"
        return reply
    profiles = [profile for profile in configured if profile.get("id") == pid]
    item = running.get(pid)
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
    session = item.get("session")
    target = session.get("ui_target_key") if isinstance(session, dict) else None
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
    command = "send" if pending["kind"] == "continuation" else "rotate-send"
    if not journal_path.exists():
        status = _retired_attempt_evidence(
            journal_path, pid, attempt, digest, command,
            pending.get("prepared_at_unix"))
        reply["original_journal"] = status
        if status in {"unique_retired_attempt",
                      "unique_retired_attempt_bound"}:
            reply["phase"] = "retired_original_observation_candidate"
            reply["read_only_observation_candidate"] = True
            reply["reason"] = "LIVE_UI_AND_RETIRED_RESPONSE_COMPARISON_REQUIRED"
        else:
            reply["reason"] = "ORIGINAL_JOURNAL_UNVERIFIED"
        return reply
    journal = _private_record(journal_path)
    if journal is None:
        reply["original_journal"] = "unreadable"
        reply["reason"] = "ORIGINAL_JOURNAL_UNVERIFIED"
        return reply
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
