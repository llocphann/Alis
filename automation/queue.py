"""AUTO-R01 sequential multi-Issue queue, without a competing scheduler.

Runtime Cloudbot prompts/scripts/reports remain in each <TASK-CODE>.json.
This file stores only one compact queue manifest and a durable selection record.
Only AUTO-F01's authenticated scheduler may claim/advance work.
"""
from __future__ import annotations

from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import re
import time
from typing import Callable

from . import taskflow as tf

QUEUE_SCHEMA = "alis.task-queue.v1"
MAX_ITEMS = 20
MODES = frozenset(("ordered", "cloud"))
SAFE_FINISHED = frozenset(("awaiting_owner", "completed"))
CHOICE_ID = re.compile(r"^[A-Za-z0-9_.:-]{8,160}$")


def _queue_path() -> Path:
    path = tf.state_dir() / "queue.json"
    if path.is_symlink():
        raise tf.TaskError("Unsafe queue manifest symlink")
    return path


@contextmanager
def _lock():
    root = tf.state_dir()
    lock = root / "queue.lock"
    if lock.is_symlink():
        raise tf.TaskError("Unsafe queue lock")
    with lock.open("a+", encoding="utf-8") as stream:
        os.chmod(lock, 0o600)
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def _load() -> dict | None:
    path = _queue_path()
    if not path.exists():
        return None
    try:
        with path.open(encoding="utf-8") as stream:
            manifest = json.load(stream)
    except (ValueError, OSError):
        raise tf.TaskError("Queue manifest incomplete; manual recovery required") from None
    if (not isinstance(manifest, dict) or manifest.get("schema") != QUEUE_SCHEMA
            or manifest.get("mode") not in MODES or not isinstance(manifest.get("items"), list)):
        raise tf.TaskError("Invalid queue manifest")
    return manifest


def _save(manifest: dict):
    tf._atomic_json(_queue_path(), manifest)


def parse_codes(raw: str) -> list[str]:
    if not isinstance(raw, str) or len(raw) > 3000:
        raise tf.TaskError("Task input is too long")
    values = [entry.strip() for entry in raw.split(";")]
    if not 1 <= len(values) <= MAX_ITEMS or any(not entry for entry in values):
        raise tf.TaskError("Enter 1–20 task codes, separated by semicolons")
    if any(not (tf.CODE.fullmatch(value) or tf.ISSUE_REF.fullmatch(value)) for value in values):
        raise tf.TaskError("Only task codes or owner/repo#issue references are allowed")
    if len(set(values)) != len(values):
        raise tf.TaskError("Duplicate task codes in queue")
    return values


def prepare(raw: str, mode: str = "ordered",
            resolver: Callable[[str], dict] = tf.resolve) -> dict:
    """Resolve ALL canonical Issues before writing any queue state.

    The queue is single-active and serial, never silently replaced while work
    is pending. Prepared task records are harmless and never auto-dispatched.
    """
    if mode not in MODES:
        raise tf.TaskError("Unsupported scheduling mode")
    inputs = parse_codes(raw)
    tasks = [resolver(code) for code in inputs]
    keys = [(t["repository"], t["code"]) for t in tasks]
    if len(set(keys)) != len(keys):
        raise tf.TaskError("Multiple references resolve to the same task")
    if any(t["repository"] not in tf.REPOSITORIES
           or t["branch"] != tf.REPOSITORIES[t["repository"]]
           or not tf.SHA.fullmatch(t["base_sha"]) for t in tasks):
        raise tf.TaskError("Issue is not pinned to an authorized repository")
    with _lock():
        current = _load()
        if current and current.get("state") not in {"finished", "cancelled"}:
            same = (current["mode"] == mode and
                    [(x["repository"], x["code"]) for x in current["items"]] == keys)
            if same:
                return {**view(current), "duplicate": True}
            raise tf.TaskError("An unfinished queue exists; reconcile before replacing")
        for task in tasks:
            previous = tf.intake(task)
            if previous["state"] not in {"prepared", "handoff_ready"}:
                raise tf.TaskError("Task already active elsewhere; queue not started")
        now = int(time.time())
        manifest = {
            "schema": QUEUE_SCHEMA, "mode": mode, "state": "prepared",
            "created_unix": now, "updated_unix": now,
            "active": None, "selection": None,
            "items": [
                {"code": task["code"], "repository": task["repository"],
                 "issue_number": task["issue_number"], "source_sha": task["base_sha"],
                 "state": "queued"} for task in tasks
            ],
        }
        _save(manifest)
        return {**view(manifest), "duplicate": False}


def view(manifest: dict | None = None) -> dict:
    if manifest is None:
        with _lock():
            manifest = _load()
    if manifest is None:
        return {"ok": True, "mode": "ordered", "state": "empty",
                "active": None, "items": [], "next": None}
    items = [{key: item[key] for key in ("code", "repository", "state")}
             for item in manifest["items"]]
    next_item = next((x for x in items if x["state"] == "queued"), None)
    return {"ok": True, "mode": manifest["mode"], "state": manifest["state"],
            "active": manifest["active"], "items": items,
            "next": next_item if manifest["mode"] == "ordered" else None,
            "cloud_selection_required": manifest["mode"] == "cloud"
                 and manifest["active"] is None and next_item is not None}


def claim(verified_start: Callable[[dict, dict], bool] | None = None,
          *, choice: str | None = None, decision_id: str | None = None) -> dict:
    """One run at a time. Cloud mode requires a verified Cloudbot decision.

    When AUTO-F01 is absent there is intentionally no public CLI claim action.
    A decision from an Issue body, user input or heuristic is not verification.
    """
    if verified_start is None:
        raise tf.TaskError("Authenticated scheduler not restored (AUTO-F01)")
    with _lock():
        manifest = _load()
        if not manifest or manifest["state"] not in {"prepared", "waiting"}:
            raise tf.TaskError("Queue is not ready for dispatch")
        if manifest["active"] is not None:
            raise tf.TaskError("A task is already active")
        pending = [item for item in manifest["items"] if item["state"] == "queued"]
        if not pending:
            raise tf.TaskError("No queued tasks")
        if manifest["mode"] == "ordered":
            selected = pending[0]
            if choice is not None and choice != selected["code"]:
                raise tf.TaskError("Ordered mode cannot skip an Issue")
        else:
            if not isinstance(choice, str) or not CHOICE_ID.fullmatch(decision_id or ""):
                raise tf.TaskError("Cloudbot choice and durable decision ID are required")
            matched = [x for x in pending if x["code"] == choice]
            if len(matched) != 1:
                raise tf.TaskError("Cloudbot choice not in pending tasks or ambiguous")
            selected = matched[0]
        task = tf.load_task(selected["code"], selected["repository"])
        if task.get("status") not in {"prepared", "handoff_ready"}:
            raise tf.TaskError("Selected task has unsafe state")
        # Verifier checks actual managed Cloudbot selection/transport readiness.
        if verified_start(selected, task) is not True:
            raise tf.TaskError("Cloudbot/transport did not authorize selection")
        selected["state"] = "active"
        manifest["active"] = {"code": selected["code"], "repository": selected["repository"]}
        manifest["selection"] = {
            "code": selected["code"], "decision_id": decision_id if manifest["mode"] == "cloud" else None,
            "selected_unix": int(time.time()),
        }
        manifest["state"] = "active"
        manifest["updated_unix"] = int(time.time())
        _save(manifest)
        return {"ok": True, "selected": manifest["active"],
                "state": "active", "mode": manifest["mode"]}


def advance(verify_completion: Callable[[dict], bool] | None = None) -> dict:
    """Advance only after Cloudbot completion is recorded; owner review stays separate."""
    if verify_completion is None:
        raise tf.TaskError("Authenticated completion verifier unavailable (AUTO-F01)")
    with _lock():
        manifest = _load()
        if not manifest or manifest["state"] != "active" or not manifest["active"]:
            raise tf.TaskError("Queue has no active job")
        selected = manifest["active"]
        item = next((x for x in manifest["items"]
                     if x["code"] == selected["code"] and x["repository"] == selected["repository"]), None)
        if item is None or item["state"] != "active":
            raise tf.TaskError("Active task identity mismatch")
        record = tf.load_task(item["code"], item["repository"])
        if (record["status"] not in SAFE_FINISHED or record.get("unresolved")
                or record.get("rotation") or not record.get("delivery_acknowledged_unix")):
            raise tf.TaskError("Current task still awaiting confirmed Cloudbot completion")
        if verify_completion(record) is not True:
            raise tf.TaskError("Completion evidence rejected")
        item["state"] = "awaiting_owner" if record["status"] == "awaiting_owner" else "completed"
        manifest["active"] = None
        manifest["selection"] = None
        manifest["updated_unix"] = int(time.time())
        manifest["state"] = ("waiting" if any(x["state"] == "queued" for x in manifest["items"])
                             else "finished")
        _save(manifest)
        return view(manifest)
