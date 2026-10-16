"""AUTO-R01 durable Cloudbot/Localbot reconciliation and owner review gates.

Authenticated Desktop/scheduler adapters inject evidence verifiers. This module
never sends ChatGPT messages or interprets arbitrary GitHub Issue instructions.
"""
from __future__ import annotations

import json
from pathlib import Path
import time
from typing import Callable

from . import taskflow as tf


def _verified_local_receipt(record: dict, *, allow_failed: bool = False) -> dict:
    bundle = record.get("handoff")
    if not bundle:
        raise tf.TaskError("Missing Cloudbot handoff")
    checked = tf.verify(bundle)
    summary = record.get("latest_receipt")
    if not isinstance(summary, dict):
        raise tf.TaskError("Missing Localbot receipt")
    state = summary.get("state")
    if state != "passed" and not (allow_failed is True and state == "failed"):
        raise tf.TaskError("Unacknowledged or mismatched Localbot receipt")
    for key, expected in {
        "id": checked["id"],
        "sha256": checked["sha256"],
        "source_sha": tf.execution_sha(checked["payload"]),
        "state": state,
    }.items():
        if summary.get(key) != expected:
            raise tf.TaskError("Unacknowledged or mismatched Localbot receipt")
    receipt_path = tf.state_dir() / "receipts" / (checked["id"] + ".json")
    if receipt_path.is_symlink():
        raise tf.TaskError("Unsafe receipt symlink")
    try:
        with receipt_path.open(encoding="utf-8") as stream:
            persisted = json.load(stream)
    except (OSError, ValueError):
        raise tf.TaskError("Durable Localbot receipt unavailable") from None
    if any(persisted.get(key) != summary.get(key)
           for key in ("id", "sha256", "source_sha", "state")):
        raise tf.TaskError("Local receipt identity mismatch")
    if state == "failed":
        steps = persisted.get("steps")
        commands = checked["payload"]["commands"]
        if (not isinstance(steps, list) or not 1 <= len(steps) <= len(commands)
                or persisted.get("continuation_ready") is not False
                or type(persisted.get("finished_unix")) is not int
                or any(not isinstance(s, dict) or s.get("argv") != commands[i]
                       for i, s in enumerate(steps))
                or any(type(s.get("exit_code")) is not int or s["exit_code"] != 0
                       or s.get("error") for s in steps[:-1])
                or type(steps[-1].get("exit_code")) is not int
                or steps[-1]["exit_code"] == 0 or steps[-1].get("error")):
            # A timeout/unknown cleanup is not a settled failure. Keep it
            # blocked, just as started, foreign and conflicting receipts are.
            raise tf.TaskError("Failed Localbot receipt needs reconciliation")
    return checked


def acknowledge_cloud_delivery(
    code: str, conversation_id: str, message_id: str,
    verify_transport: Callable[[str, str, str], bool] | None = None,
    repository: str = "llocphann/Alis",
) -> dict:
    """Record exact Cloudbot follow-up message only after real Desktop evidence."""
    if verify_transport is None:
        raise tf.TaskError("Authenticated Desktop transport unavailable (AUTO-F01)")
    if not all(isinstance(value, str) and 0 < len(value) <= 256
               for value in (conversation_id, message_id)):
        raise tf.TaskError("Invalid managed conversation/message")
    record = tf.load_task(code, repository)
    checked = _verified_local_receipt(record)
    current = record.get("delivery")
    if current is not None:
        if (current["conversation_id"], current["message_id"], current["job_id"]) == (
                conversation_id, message_id, checked["id"]):
            return {"ok": True, "duplicate": True, "status": record["status"]}
        raise tf.TaskError("Different message identity; reconcile previous send")
    if record.get("status") != "awaiting_cloud_ack" or record.get("unresolved"):
        raise tf.TaskError("Delivery state is not safe to acknowledge")
    managed = record.get("managed_chat")
    if not managed or managed.get("conversation_id") != conversation_id:
        raise tf.TaskError("Unrecognized managed ChatGPT conversation")
    expected_prompt = checked["payload"]["next_prompt"]
    if verify_transport(conversation_id, message_id, expected_prompt) is not True:
        raise tf.TaskError("Cloudbot-authored follow-up message is unverified")
    now = int(time.time())
    record["delivery"] = {"conversation_id": conversation_id, "message_id": message_id,
                          "job_id": checked["id"], "sha256": checked["sha256"],
                          "ack_unix": now}
    record["delivery_acknowledged_unix"] = now
    record["status"] = "cloud_continuing"
    record["updated_unix"] = now
    tf._save_task(record)
    return {"ok": True, "duplicate": False, "status": "cloud_continuing"}


def awaiting_owner_verification(
    code: str, verify_cloud_completion: Callable[[dict], bool] | None = None,
    repository: str = "llocphann/Alis",
) -> dict:
    if verify_cloud_completion is None:
        raise tf.TaskError("Authenticated Cloudbot completion verifier unavailable")
    record = tf.load_task(code, repository)
    if (record.get("status") != "cloud_continuing" or not record.get("delivery")
            or record.get("unresolved") or record.get("rotation")):
        raise tf.TaskError("Cloudbot delivery/rotation remains unresolved")
    if verify_cloud_completion(record) is not True:
        raise tf.TaskError("Cloudbot completion not verified")
    record["status"] = "awaiting_owner"
    record["updated_unix"] = int(time.time())
    tf._save_task(record)
    return {"ok": True, "status": "awaiting_owner"}


def owner_verified(
    code: str, *, approval: bool = False,
    repository: str = "llocphann/Alis",
) -> dict:
    """Trusted owner-facing UI only. Does NOT close the GitHub Issue."""
    if approval is not True:
        raise tf.TaskError("Explicit owner approval is required")
    record = tf.load_task(code, repository)
    if (record.get("status") != "awaiting_owner" or record.get("unresolved")
            or not record.get("delivery") or not record.get("delivery_acknowledged_unix")):
        raise tf.TaskError("Task is not awaiting verified owner acceptance")
    now = int(time.time())
    record["status"] = "completed"
    record["terminal_unix"] = now
    record["updated_unix"] = now
    tf._save_task(record)
    return {"ok": True, "status": "completed", "terminal_unix": now}


def status(code: str, repository: str = "llocphann/Alis") -> dict:
    """Redacted read-only view; never render Cloudbot prompts, scripts or logs."""
    record = tf.load_task(code, repository)
    return {"ok": True, "code": record["code"],
            "repository": record["repository"], "status": record["status"],
            "base_sha": record["task"]["base_sha"],
            "current_job": (record.get("handoff") or {}).get("id"),
            "receipt": record.get("latest_receipt"),
            "delivery_confirmed": bool(record.get("delivery")),
            "rotation_pending": record.get("status") == "rotation_pending",
            "unresolved": bool(record.get("unresolved"))}
