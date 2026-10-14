"""AUTO-R01 verified chat-capacity rollover adapter.

Consumes authenticated, structured context/turn-limit evidence from the future
AUTO-F01 Desktop transport. Never guesses limits by prompt counts or error text.
Never creates/resends chats without authenticated message acknowledgment.
"""
from __future__ import annotations

import time
from typing import Callable

from . import taskflow as tf

LIMIT_SIGNALS = frozenset({
    "context_window_exhausted", "context_window_near_limit",
    "conversation_turn_limit", "chat_capacity_exhausted",
})


def _identity(value: str, label: str) -> str:
    if not isinstance(value, str) or not 1 <= len(value) <= 256:
        raise tf.TaskError("Invalid " + label)
    if any(ord(ch) < 33 or ord(ch) > 126 for ch in value):
        raise tf.TaskError("Invalid " + label)
    return value


def bind_managed_chat(
    code: str, conversation_id: str, message_id: str,
    verify_session: Callable[[str, str, str], bool] | None = None,
    repository: str = "llocphann/Alis",
) -> dict:
    """Attach original managed project chat after authenticated server proof."""
    if verify_session is None:
        raise tf.TaskError("Authenticated Desktop session verifier unavailable (AUTO-F01)")
    cid, mid = _identity(conversation_id, "conversation id"), _identity(message_id, "message id")
    record = tf.load_task(code, repository)
    previous = record.get("managed_chat")
    if previous:
        if (previous["conversation_id"], previous["message_id"]) == (cid, mid):
            return {"ok": True, "duplicate": True}
        raise tf.TaskError("Managed chat already assigned; use verified rotation")
    if record["status"] not in {"prepared", "handoff_ready"}:
        raise tf.TaskError("Task is not ready for initial managed chat")
    if verify_session(cid, mid, record["cloud_prompt"]) is not True:
        raise tf.TaskError("Desktop did not confirm managed task chat")
    now = int(time.time())
    record["managed_chat"] = {"conversation_id": cid, "message_id": mid,
                              "assigned_unix": now}
    record["updated_unix"] = now
    tf._save_task(record)
    return {"ok": True, "duplicate": False}


def observe_chat_limit(
    code: str, signal: dict,
    verify_limit: Callable[[dict, str], bool] | None = None,
    repository: str = "llocphann/Alis",
) -> dict:
    """Durably reserve rollover based on trusted provider capacity evidence.

    The scheduler may advance only from a verified Cloudbot continuation state;
    never rotate if a Localbot receipt/delivery is still ambiguous.
    """
    if verify_limit is None:
        raise tf.TaskError("Authenticated capacity detection unavailable (AUTO-F01)")
    if not isinstance(signal, dict) or set(signal) != {"kind", "conversation_id", "message_id"}:
        raise tf.TaskError("Malformed Desktop capacity signal")
    if signal["kind"] not in LIMIT_SIGNALS:
        raise tf.TaskError("Unrecognized conversation capacity signal")
    cid = _identity(signal["conversation_id"], "conversation id")
    mid = _identity(signal["message_id"], "message id")
    record = tf.load_task(code, repository)
    managed = record.get("managed_chat")
    if not managed or managed.get("conversation_id") != cid:
        raise tf.TaskError("Capacity signal belongs to another managed chat")
    existing = record.get("rotation")
    if existing:
        if (record.get("status") == "rotation_pending"
                and (existing["from_conversation"], existing["trigger_message"],
                     existing["reason"]) == (cid, mid, signal["kind"])):
            return {"ok": True, "duplicate": True, "status": "rotation_pending"}
        raise tf.TaskError("Previous chat rotation needs reconciliation")
    if record.get("status") != "cloud_continuing" or record.get("unresolved"):
        raise tf.TaskError("Unacknowledged Localbot work prevents chat rotation")
    if verify_limit(signal, cid) is not True:
        raise tf.TaskError("Desktop capacity evidence is not verified")
    handoff = record.get("handoff")
    checkpoint = handoff["payload"]["checkpoint"] if handoff else ""
    receipt = record.get("latest_receipt")
    # The prompt is internal and stored inside the single TASK-CODE.json file.
    prompt = (
        "Resume the same GitHub task in this new managed chat. Never replay "
        "unacknowledged local actions. Inspect canonical GitHub Issue and evidence.\n"
        f"Task: {record['code']} repo={repository} issue={record['issue_number']}\n"
        f"Base SHA: {record['task']['base_sha']}\n"
        f"Checkpoint: {checkpoint[:5000]}\n"
        f"Durable receipt ID: {receipt.get('id', 'none') if isinstance(receipt, dict) else 'none'}\n"
        "Preserve Cloudbot/Localbot receipt and owner-verification gates."
    )
    record["rotation"] = {
        "reason": signal["kind"], "from_conversation": cid, "trigger_message": mid,
        "resume_prompt": prompt, "new_conversation": None, "new_message": None,
        "created_unix": int(time.time()),
    }
    record["status"] = "rotation_pending"
    record["updated_unix"] = int(time.time())
    tf._save_task(record)
    return {"ok": True, "duplicate": False, "status": "rotation_pending"}


def acknowledge_chat_rotation(
    code: str, new_conversation_id: str, new_message_id: str,
    verify_new_chat: Callable[[str, str, str, str], bool] | None = None,
    repository: str = "llocphann/Alis",
) -> dict:
    """Reconcile server-observed new chat and exact resume message, no blind retry."""
    if verify_new_chat is None:
        raise tf.TaskError("Authenticated rotation unavailable (AUTO-F01)")
    cid = _identity(new_conversation_id, "new conversation id")
    mid = _identity(new_message_id, "new message id")
    record = tf.load_task(code, repository)
    rotation = record.get("rotation")
    if not isinstance(rotation, dict):
        previous = record.get("last_rotation")
        if previous and (previous.get("new_conversation"), previous.get("new_message")) == (cid, mid):
            return {"ok": True, "duplicate": True, "status": record["status"]}
        raise tf.TaskError("No verified pending rotation")
    if record.get("status") != "rotation_pending":
        raise tf.TaskError("Rotation is not awaiting transport confirmation")
    if cid == rotation["from_conversation"]:
        raise tf.TaskError("New managed conversation must be distinct")
    if verify_new_chat(cid, mid, rotation["resume_prompt"],
                       rotation["from_conversation"]) is not True:
        raise tf.TaskError("New chat/message not authenticated")
    now = int(time.time())
    record["last_rotation"] = {
        "new_conversation": cid, "new_message": mid,
        "from_conversation": rotation["from_conversation"],
        "reason": rotation["reason"], "acknowledged_unix": now,
    }
    record["rotation"] = None
    record["managed_chat"] = {"conversation_id": cid, "message_id": mid,
                              "assigned_unix": now}
    record["status"] = "cloud_continuing"
    record["updated_unix"] = now
    tf._save_task(record)
    return {"ok": True, "duplicate": False, "status": "cloud_continuing"}
