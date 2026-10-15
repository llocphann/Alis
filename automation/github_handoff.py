"""AUTO-F01 GitHub handoff signal for the existing SHA-pinned worker.

A reusable *single* remote automation/handoff/ACTIVE.json is a coordination
hint, NOT a ChatGPT Project/server message receipt. Only the exact approved
job digest plus an exact fresh DONE signal may release an opt-in job to the
existing deterministic worker. PREPARING is never authority to execute.
"""
from __future__ import annotations

import hashlib
import json
import re
import time
import uuid
from pathlib import Path

SCHEMA = "alis.github-handoff.v1"
PATH = "automation/handoff/ACTIVE.json"
MAX_BYTES = 2048
MAX_LIFETIME = 86400
CODE = re.compile(r"^[A-Z][A-Z0-9]{1,15}-(?:F|R|I)[0-9]{2,3}$")
JOB = re.compile(r"^JOB-[A-Za-z0-9._-]{1,120}$")
SHA = re.compile(r"^[0-9a-f]{40}$")
DIGEST = re.compile(r"^[0-9a-f]{64}$")
ALLOWED = frozenset(("schema", "task_code", "run_id", "job_id",
                     "base_sha", "job_sha256", "status",
                     "updated_unix", "expires_unix"))
STATUSES = frozenset(("PREPARING", "DONE"))


class HandoffWait(ValueError):
    """No execution and no receipt while an opt-in signal is not DONE."""


def job_digest(raw: str) -> str:
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def validate_signal(raw: str, *, now: int | None = None, require_fresh: bool = True) -> dict:
    if not isinstance(raw, str) or len(raw.encode("utf-8")) > MAX_BYTES:
        raise ValueError("handoff manifest exceeds bound")
    try:
        value = json.loads(raw)
    except (ValueError, TypeError):
        raise ValueError("handoff manifest invalid JSON") from None
    if not isinstance(value, dict) or set(value) != ALLOWED:
        raise ValueError("handoff manifest unexpected fields")
    if (value["schema"] != SCHEMA or
            not isinstance(value["task_code"], str) or
            not CODE.fullmatch(value["task_code"]) or
            not isinstance(value["job_id"], str) or
            not JOB.fullmatch(value["job_id"]) or
            not isinstance(value["run_id"], str) or
            not re.fullmatch(r"[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}", value["run_id"]) or
            not isinstance(value["base_sha"], str) or
            not SHA.fullmatch(value["base_sha"]) or
            not isinstance(value["job_sha256"], str) or
            not DIGEST.fullmatch(value["job_sha256"]) or
            not isinstance(value["status"], str) or
            value["status"] not in STATUSES or
            type(value["updated_unix"]) is not int or
            type(value["expires_unix"]) is not int):
        raise ValueError("handoff manifest invalid identity")
    at = int(time.time()) if now is None else now
    try:
        parsed_uuid = uuid.UUID(value["run_id"])
    except ValueError:
        raise ValueError("handoff manifest invalid run ID") from None
    if str(parsed_uuid) != value["run_id"]:
        raise ValueError("handoff manifest invalid run ID")
    if (value["updated_unix"] > at + 120 or
            (require_fresh and value["updated_unix"] < at - MAX_LIFETIME) or
            value["expires_unix"] <= value["updated_unix"] or
            value["expires_unix"] > value["updated_unix"] + MAX_LIFETIME):
        raise ValueError("handoff time window invalid")
    return value


def match_job(signal: dict, job: dict, raw_job: str) -> None:
    """Strict identity; a displayed DONE cannot substitute for the pinned job."""
    ref = job.get("handoff")
    if not isinstance(ref, dict) or set(ref) != {"task_code", "run_id"}:
        raise ValueError("job missing exact GitHub handoff identity")
    if (signal["task_code"] != ref["task_code"] or
            signal["run_id"] != ref["run_id"] or
            signal["job_id"] != job["id"] or
            signal["base_sha"] != job["base_sha"] or
            signal["job_sha256"] != job_digest(raw_job)):
        raise ValueError("GitHub handoff does not match pinned job")


def approval_path(state: Path, job_id: str) -> Path:
    if not isinstance(job_id, str) or not JOB.fullmatch(job_id):
        raise ValueError("invalid approval job")
    folder = state / "handoff-approvals"
    if folder.is_symlink():
        raise ValueError("unsafe approval directory")
    return folder / (job_id + ".json")


def approval_matches(state: Path, job: dict, raw_job: str) -> bool:
    path = approval_path(state, job["id"])
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 1024:
        return False
    try:
        receipt = json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        return False
    return (
        type(receipt) is dict and
        set(receipt) == {"job_id", "run_id", "job_sha256", "approved_unix"} and
        receipt["job_id"] == job["id"] and
        receipt["run_id"] == job["handoff"]["run_id"] and
        receipt["job_sha256"] == job_digest(raw_job) and
        type(receipt["approved_unix"]) is int and
        receipt["approved_unix"] > 0
    )


def ready(raw_signal: str, job: dict, raw_job: str, state: Path,
          *, now: int | None = None) -> dict:
    at = int(time.time()) if now is None else now
    signal = validate_signal(raw_signal, now=at)
    match_job(signal, job, raw_job)
    if signal["expires_unix"] < at:
        raise HandoffWait("handoff signal expired; issue new approved run")
    if signal["status"] != "DONE":
        raise HandoffWait("handoff not DONE")
    if not approval_matches(state, job, raw_job):
        raise HandoffWait("local owner approval of exact job unavailable")
    return {"ready": True, "job_id":job["id"], "run_id": signal["run_id"]}


def retire_after_receipt(raw_signal: str, payload: dict,
                         *, now: int | None = None) -> bool:
    """Retire only the exact acknowledged job; no unrelated/new signal."""
    if (not isinstance(payload, dict) or payload.get("status") not in
            {"passed", "failed", "cancelled"}):
        return False
    try:
        signal = validate_signal(raw_signal, now=now, require_fresh=False)
    except ValueError:
        return False
    return (signal["status"] == "DONE"
            and signal["job_id"] == payload.get("job")
            and signal["job_sha256"] == payload.get("input_sha256"))


EXPIRED_GRACE = 3600


def expired_for_retirement(raw_signal: str, *, now: int | None = None) -> str | None:
    """Return only an expired, structurally valid handoff job ID.

    This is not execution authorization and never removes pending worker
    receipts. The caller must still check local receipts under publication
    and use fast-forward-only Git commit semantics.
    """
    at = int(time.time()) if now is None else now
    try:
        signal = validate_signal(raw_signal, now=at, require_fresh=False)
    except ValueError:
        return None
    return (signal["job_id"] if signal["expires_unix"] + EXPIRED_GRACE < at
            else None)


def approval_payload(job: dict, raw_job: str, *, now: int | None = None) -> dict:
    if not isinstance(job.get("handoff"), dict):
        raise ValueError("job is not opted into GitHub handoff")
    return {"job_id": job["id"], "run_id": job["handoff"]["run_id"],
            "job_sha256": job_digest(raw_job),
            "approved_unix": int(time.time()) if now is None else now}
