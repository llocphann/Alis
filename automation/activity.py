"""AUTO-R01 bounded activity and diagnostics, embedded in each task-code file.

No extra log files or raw commands, credentials, Cloudbot prompts, scripts, or
private evidence are copied to the Settings activity surface.
"""
from __future__ import annotations

import re
import time

from . import taskflow as tf

EVENT_LIMIT = 60
DISPLAY_LIMIT = 40
BODY_LIMIT = 700

TOKEN = re.compile(
    r"(?:ghp_[A-Za-z0-9]{15,}|github_pat_[A-Za-z0-9_]{15,}|"
    r"gho_[A-Za-z0-9]{15,}|sk-[A-Za-z0-9_-]{16,})"
)
BEARER = re.compile(r"(?i)(authorization:\s*bearer\s+)\S+")
EVENT_TYPES = frozenset({
    "task_prepared", "handoff_ready", "awaiting_cloud_ack",
    "cloud_continuing", "needs_review", "rotation_pending",
    "awaiting_owner", "completed", "retired", "cancelled",
    "queued", "diagnostic", "test", "status",
})


def redact(text: str) -> str:
    """Bound and sanitize diagnostic excerpts before persistence and display."""
    value = text[:BODY_LIMIT] if isinstance(text, str) else ""
    return BEARER.sub(r"\1[REDACTED]", TOKEN.sub("[REDACTED]", value))


def append_event(record: dict, kind: str, detail: str = "",
                 *, now: int | None = None) -> None:
    if kind not in EVENT_TYPES:
        raise tf.TaskError("Unknown Automation activity type")
    events = record.get("activity", [])
    if not isinstance(events, list):
        events = []
    events.append({
        "at_unix": int(time.time()) if now is None else now,
        "kind": kind, "detail": redact(detail),
    })
    record["activity"] = events[-EVENT_LIMIT:]


def read(code: str, repository: str = "llocphann/Alis") -> dict:
    """Two separate views: event lifecycle and short bounded diagnostics."""
    record = tf.load_task(code, repository)
    timeline = record.get("activity", [])
    reports = record.get("reports", [])
    if not isinstance(timeline, list) or not isinstance(reports, list):
        raise tf.TaskError("Invalid activity history")
    status = record.get("status", "unknown")
    events = [
        {"at_unix": int(x.get("at_unix", 0)), "kind": str(x.get("kind", ""))[:60],
         "detail": redact(x.get("detail", ""))}
        for x in timeline[-DISPLAY_LIMIT:] if isinstance(x, dict)
    ]
    logs = [
        {"at_unix": int(x.get("at_unix", 0)), "kind": str(x.get("kind", ""))[:60],
         "text": redact(x.get("text", ""))}
        for x in reports[-tf.REPORT_LIMIT:] if isinstance(x, dict)
    ]
    receipt = record.get("latest_receipt")
    if isinstance(receipt, dict):
        logs.append({"at_unix": int(receipt.get("finished_unix") or 0),
                     "kind": "local_receipt",
                     "text": "Job %s · %s · source %s" % (
                         str(receipt.get("id", ""))[:40],
                         str(receipt.get("state", ""))[:40],
                         str(receipt.get("source_sha", ""))[:12])})
    return {"ok": True, "code": record["code"], "repository": record["repository"],
            "status": status, "events": events, "logs": logs}
