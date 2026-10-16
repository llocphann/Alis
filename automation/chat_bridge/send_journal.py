"""Alis Chat Bridge: durable one-attempt UI send ledger.

The historical XDG 'hadalis-automation' directory is a migration alias; new
protocol/user-facing strings are Alis. This module NEVER submits a message.
An indeterminate UI click is deliberately NOT retried after a crash/restart.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import stat
import time
import uuid

SCHEMA = "alis.chat-ui-send.v1"
OPERATIONS = frozenset({"send", "rotate-send"})


def _private_directory(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_mode & 0o077:
        raise RuntimeError("ALIS_UI_JOURNAL_NOT_PRIVATE")
    return path


def _sync_directory(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def prepare_send(state_root: Path, command: str, prompt: str) -> tuple[Path, str]:
    """Persist an immutable intent *before* any composer filling or click.

    The one pending file is an anti-replay tombstone. If Desktop submission
    crashes, times out, or is ambiguous, it remains for manual reconciliation.
    No prompt or account identity appears in the journal.
    """
    if command not in OPERATIONS or not isinstance(prompt, str) or not prompt.strip():
        raise ValueError("invalid Alis UI send request")
    folder = _private_directory(state_root / "ui-send-journal")
    pending = folder / "pending.json"
    if pending.exists() or pending.is_symlink():
        raise RuntimeError("ALIS_UI_SEND_UNCERTAIN_RECONCILIATION_REQUIRED")
    attempt = str(uuid.uuid4())
    record = {
        "schema": SCHEMA, "id": attempt, "command": command,
        "prompt_sha256": hashlib.sha256(prompt.encode("utf-8")).hexdigest(),
        "phase": "attempted", "at_unix": int(time.time()),
    }
    fd = os.open(pending, os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                 getattr(os, "O_NOFOLLOW", 0), 0o600)
    try:
        data = (json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n").encode()
        os.write(fd, data)
        os.fsync(fd)
    finally:
        os.close(fd)
    _sync_directory(folder)
    return pending, attempt


def acknowledge_completed(pending: Path, attempt: str) -> None:
    """Retire the attempt only after a complete unique Desktop reply.

    A UI-visible response does not prove server identity. A caller must never
    use this acknowledgement to enable native managed transport.
    """
    if not isinstance(attempt, str) or not attempt:
        raise ValueError("invalid Alis send attempt")
    folder = _private_directory(pending.parent)
    if pending.name != "pending.json" or pending.is_symlink():
        raise RuntimeError("ALIS_UI_SEND_JOURNAL_MISMATCH")
    try:
        record = json.loads(pending.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        raise RuntimeError("ALIS_UI_SEND_JOURNAL_UNREADABLE") from None
    if (not isinstance(record, dict) or record.get("schema") != SCHEMA
            or record.get("id") != attempt or record.get("phase") != "attempted"):
        raise RuntimeError("ALIS_UI_SEND_JOURNAL_MISMATCH")
    archive = _private_directory(folder / "observed")
    os.replace(pending, archive / (attempt + ".json"))
    _sync_directory(archive)
    _sync_directory(folder)


def acknowledge_not_sent(pending: Path, attempt: str, digest: str,
                         *, evidence: str) -> None:
    """Keep an unsent tombstone; never count it as observed/delivered.

    Callers must bind either the child CLI's typed pre-Send failure receipt
    or a direct Owner confirmation to the exact pending attempt and hash.
    Unknown/crashed/possibly clicked attempts do not qualify.
    """
    try:
        valid_attempt = isinstance(attempt, str) and str(uuid.UUID(attempt)) == attempt
    except ValueError:
        valid_attempt = False
    if (not valid_attempt or not isinstance(digest, str) or len(digest) != 64
            or any(c not in "0123456789abcdef" for c in digest)):
        raise ValueError("Invalid not-sent attempt identity")
    if evidence not in {"desktop-pre-send-receipt", "owner-confirmed-not-sent"}:
        raise ValueError("Explicit not-sent evidence required")
    folder = _private_directory(pending.parent)
    if pending.name != "pending.json" or pending.is_symlink():
        raise RuntimeError("ALIS_UI_SEND_JOURNAL_MISMATCH")
    record = json.loads(pending.read_text(encoding="utf-8"))
    if (not isinstance(record, dict)
            or record.get("schema") != SCHEMA or record.get("id") != attempt
            or record.get("phase") != "attempted"
            or record.get("prompt_sha256") != digest):
        raise RuntimeError("ALIS_UI_SEND_JOURNAL_MISMATCH")
    archive = _private_directory(folder / "not-sent")
    destination = archive / (attempt + ".json")
    if destination.exists() or destination.is_symlink():
        raise RuntimeError("ALIS_UI_NOT_SENT_TOMBSTONE_CONFLICT")
    # Archive the original intent first, preserving no-replay identity even
    # if recording the Owner/CLI evidence is interrupted afterwards.
    os.replace(pending, destination)
    _sync_directory(archive)
    _sync_directory(folder)
    from automation.manager.store import _write
    _write(destination, {**record, "outcome": "not_sent", "evidence": evidence,
                         "delivery_acknowledged": False})


def acknowledge_interrupted(pending: Path, attempt: str, digest: str,
                            *, proof_sha256: str) -> None:
    """Archive observed delivery interrupted by Owner, never a completed turn.

    A manager receipt must already bind the original full input/target. Write
    the durable tombstone before removing pending so interrupted cleanup can
    finish without replaying a Send or incrementing counters twice.
    """
    if (not isinstance(attempt, str) or str(uuid.UUID(attempt)) != attempt
            or any(not isinstance(v, str) or len(v) != 64
                   or any(c not in "0123456789abcdef" for c in v)
                   for v in (digest, proof_sha256))):
        raise ValueError("Invalid interrupted identity")
    folder = _private_directory(pending.parent)
    if pending.name != "pending.json" or pending.is_symlink():
        raise RuntimeError("ALIS_UI_SEND_JOURNAL_MISMATCH")
    archive = _private_directory(folder / "interrupted")
    destination = archive / (attempt + ".json")
    expected = {"outcome": "interrupted_delivered", "proof_sha256": proof_sha256,
                "delivery_acknowledged": True, "completion_acknowledged": False}
    if destination.is_symlink():
        raise RuntimeError("ALIS_UI_INTERRUPTED_TOMBSTONE_CONFLICT")
    old = json.loads(destination.read_text()) if destination.exists() else None
    if old is not None and (not isinstance(old, dict) or old.get("id") != attempt
            or old.get("schema") != SCHEMA or old.get("prompt_sha256") != digest
            or any(old.get(k) != v for k, v in expected.items())):
        raise RuntimeError("ALIS_UI_INTERRUPTED_TOMBSTONE_CONFLICT")
    if not pending.exists():
        if old is not None:
            return
        raise RuntimeError("ALIS_UI_ORIGINAL_JOURNAL_REQUIRED")
    record = json.loads(pending.read_text())
    if (not isinstance(record, dict) or record.get("schema") != SCHEMA
            or record.get("id") != attempt or record.get("phase") != "attempted"
            or record.get("prompt_sha256") != digest):
        raise RuntimeError("ALIS_UI_SEND_JOURNAL_MISMATCH")
    from automation.manager.store import _write
    _write(destination, {**record, **expected})
    pending.unlink()
    _sync_directory(folder)
