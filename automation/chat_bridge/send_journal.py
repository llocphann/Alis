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
