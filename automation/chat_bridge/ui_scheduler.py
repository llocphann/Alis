"""Opt-in single-owner Alis UI protocol inside the existing manager service.

This is NOT the native managed transport. A UI controller cannot claim
server-attested identity, and it never bypasses automation.transport_gate.
It runs only with an explicit profile selection, under manager.daemon's
existing exclusive chat-bridge.lock. A send intent is retained before IPC;
after crash/uncertain completion the profile is quarantined, NEVER resent.
"""
from __future__ import annotations

import fcntl
import hashlib
import json
import os
import time
import uuid

from automation.chat_bridge import runtime
from automation.chat_bridge.protocol import DirectiveKind, parse_loop_directive
from automation.manager import store, model

POLL_SECONDS = 2
UI_TRANSPORT = "alis-ui-once"
PRIVATE_RESPONSE_LIMIT = 120000


def _owner(config: dict, state: dict, profile_id: str, *, allow_journal=False) -> tuple[dict, dict]:
    profile = next((p for p in config["profiles"] if p["id"] == profile_id), None)
    item = state["profiles"].get(profile_id)
    if profile is None or item is None:
        raise RuntimeError("ALIS_UI_PROFILE_NOT_FOUND")
    if profile["project_name"] != os.environ.get(
            "ALIS_CHATGPT_PROJECT",
            os.environ.get("HADALIS_CHATGPT_PROJECT", model.DEFAULT_PROJECT)):
        raise RuntimeError("ALIS_UI_PROJECT_CONFIG_MISMATCH")
    # Old sessions may have an in-flight native message. They must be
    # reconciled by the native owner; UI cannot adopt a server message ID.
    if item.get("session") and item["session"].get("transport") != UI_TRANSPORT:
        raise RuntimeError("ALIS_UI_NATIVE_SESSION_REQUIRES_REVIEW")
    from automation.chat_bridge.ui_preflight import inert_legacy_native_owner
    for other_id, other in state["profiles"].items():
        if other_id == profile_id:
            continue
        # The native scheduler is excluded by manager's single flock. Its
        # disabled/stopped old pending records are NOT our UI send intents;
        # retain them untouched and never use them as evidence for this owner.
        if inert_legacy_native_owner(config, other_id, other):
            continue
        if (other.get("desired") == "run" or other.get("pending")
                or other.get("job_id") or other.get("run_active")):
            raise RuntimeError("ALIS_UI_ANOTHER_PROFILE_UNSETTLED")
    if not allow_journal and (store.state_dir() / "ui-send-journal" / "pending.json").exists():
        raise RuntimeError("ALIS_UI_SEND_UNCERTAIN_RECONCILIATION_REQUIRED")
    return profile, item


def _mark_unresolved(profile_id: str, detail: str) -> None:
    def pause(_config, state):
        item = state["profiles"].get(profile_id)
        if not item:
            return
        item["desired"] = "stopped" if item.get("desired") == "stopped" else "paused"
        item["status"] = "ui_reconciliation_required"
        item["last_error"] = detail[:160]
        store.event(state, profile_id, "ui_reconciliation_required",
                    "Preserved original pending intent; no resend")
    store.change_state(pause)


def _same_pending(current, expected):
    # Pause/Stop adjust polling only. They cannot change which immutable
    # request owns a returning response, or discard its completed delivery.
    return (isinstance(current, dict) and isinstance(expected, dict)
            and {k: v for k, v in current.items() if k != "poll_after_unix"}
                == {k: v for k, v in expected.items() if k != "poll_after_unix"})


def _read_private_receipt(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > PRIVATE_RESPONSE_LIMIT * 3:
        raise RuntimeError("ALIS_UI_ORIGINAL_JOURNAL_REQUIRED")
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise RuntimeError("ALIS_UI_ORIGINAL_JOURNAL_REQUIRED")
    return value


def _finish_committed_journal(profile_id, item):
    """Finish a post-manager-commit crash without UI observation or recount."""
    attempt = item.get("last_ui_response_attempt")
    if not isinstance(attempt, str) or str(uuid.UUID(attempt)) != attempt:
        raise RuntimeError("ALIS_UI_ORIGINAL_JOURNAL_REQUIRED")
    response = _read_private_receipt(store.state_dir() / "ui-responses" /
                                     profile_id / (attempt + ".json"))
    intent = response.get("ui_send_intent")
    if (response.get("transport") != UI_TRANSPORT or response.get("attempt_id") != attempt
            or not isinstance(intent, dict) or set(intent) != {"id", "command", "prompt_sha256"}
            or response.get("ui_target_key") != (item.get("session") or {}).get("ui_target_key")
            or response.get("directive") != item.get("last_success")):
        raise RuntimeError("ALIS_UI_COMMITTED_RECEIPT_MISMATCH")
    path = store.state_dir() / "ui-send-journal/pending.json"
    journal = _read_private_receipt(path)
    if (journal.get("schema") != "alis.chat-ui-send.v1" or journal.get("phase") != "attempted"
            or any(journal.get(k) != v for k, v in intent.items())):
        raise RuntimeError("ALIS_UI_COMMITTED_RECEIPT_MISMATCH")
    runtime.acknowledge_completed(path, intent["id"])
    def settled(_config, state):
        current = state["profiles"].get(profile_id)
        if (current and current.get("pending") is None
                and current.get("last_ui_response_attempt") == attempt
                and current.get("desired") != "run"):
            if current.get("status") == "ui_reconciliation_required":
                current["status"] = "paused" if current["desired"] == "paused" else "idle"
                current["last_error"] = ""
    store.change_state(settled)
    return "ui_committed_journal_retired"


def _complete_observed(profile_id, profile, pending, directive, observed_target,
                       checkpoint, now, new_chat, chat_label=None):
    def complete(_config, state):
        current = state["profiles"].get(profile_id)
        if not current or not _same_pending(current.get("pending"), pending):
            return False
        current["pending"] = None
        current["last_success"] = directive.kind.value
        current["last_ui_response_attempt"] = pending["attempt_id"]
        current["loop_state"] = directive.kind.value.lower()
        current["iterations"] += 1
        current["chat_iterations"] += 1
        current["prompts_sent"] += 1
        current["last_activity_at_unix"] = now
        current["last_error"] = ""
        current["ui_pre_send_failures"] = 0
        if current.get("session") is None or new_chat:
            current["session"] = {
                "transport": UI_TRANSPORT,
                "project_name": profile["project_name"],
                "local_run_id": str(uuid.uuid4()),
                "ui_target_key": observed_target,
            }
        if chat_label is not None:
            current["session"]["ui_chat_label"] = chat_label
        if checkpoint is not None:
            current["checkpoint"] = checkpoint
        store.event(state, profile_id, "ui_response", directive.kind.value)
        if directive.kind is DirectiveKind.WAIT_RESULT:
            current.update(job_id=directive.argument,
                           next_job_poll_at_unix=now, request="continuation",
                           status="waiting_result")
        elif directive.kind is DirectiveKind.CONNECTOR_BLOCKED:
            current.update(desired="paused", status="connector_blocked")
        elif directive.kind is DirectiveKind.DONE:
            current.update(desired="stopped", status="completed", run_active=False)
        elif directive.kind is DirectiveKind.ROTATE:
            if checkpoint is None:
                current.update(desired="paused",
                               status="checkpoint_required", run_active=False)
            else:
                current.update(request="rotation", status="rotating")
        else:
            current.update(request="continuation", status="continuing")
        if current["desired"] != "run":
            current["run_active"] = False
            if current["status"] in {"continuing", "rotating"}:
                current["status"] = "paused" if current["desired"] == "paused" else "idle"
        return True
    if not store.change_state(complete):
        return "owner_changed_after_response"
    return directive.kind.value


def pending_prompt(profile, item, kind):
    prompt = model.effective_prompt(profile, "rotation" if kind == "manual_reset" else kind)
    if kind == "manual_reset":
        prompt += (
            "\nOWNER-APPROVED CHAT RESET: the previous chat was abandoned "
            "because its UI/generation became unreliable. This is a NEW "
            "conversation, NOT permission to repeat previous jobs or "
            "unverified changes. Read the pinned GitHub Issue, current dev "
            "state, saved local receipts and checkpoint before proposing "
            "the next distinct step. Reconcile prior effects first; do not "
            "claim a result without fresh evidence.\n"
        )
    prompt += "\nManaged Alis profile ID: " + profile["id"] + "\n"
    if item.get("checkpoint"):
        prompt += "\nSaved checkpoint:\n" + json.dumps(
            item["checkpoint"], ensure_ascii=False)
    if item.get("last_job_id"):
        prompt += ("\nCheck exact GitHub result in automation/results/"
                   + item["last_job_id"] + ".json\n")
    if item.get("job_summary"):
        prompt += "\nWorker summary:\n" + json.dumps(
            item["job_summary"], ensure_ascii=False)
    return prompt


def ui_tick(profile_id: str, *, now: int | None = None,
            desktop=None, queue_owner: tuple[str, str, str] | None = None) -> str:
    """One bounded scheduler admission. Never invokes a second native owner."""
    now = int(time.time()) if now is None else now
    managed_ack = desktop is None or desktop is runtime.desktop
    desktop = runtime.desktop if desktop is None else desktop
    config, state, issues = store.read_snapshot()
    if issues:
        return "invalid_configuration"
    try:
        profile, item = _owner(config, state, profile_id)
    except RuntimeError as error:
        # Preserve every existing native/foreign receipt; an abandoned
        # UI attempt must never automatically clear a pending tombstone.
        if str(error) == "ALIS_UI_SEND_UNCERTAIN_RECONCILIATION_REQUIRED":
            _mark_unresolved(profile_id, str(error))
        return str(error)
    if item.get("pending"):
        # Anything left after a previous process boundary is potentially sent.
        # Never poll/submit it as a *new* UI message.
        if item["pending"].get("transport") == UI_TRANSPORT:
            _mark_unresolved(profile_id, "Unresolved UI send after prior tick")
        return "ui_reconciliation_required"
    if not profile["enabled"] or item["desired"] != "run":
        return "idle"
    if item.get("job_id"):
        # A legacy/public result with no owner is NOT authority to resume
        # this specific Alis task. Identity and SHA-256 are mandatory; never
        # accept somebody else's historical JOB-* as a wakeup.
        job_id = item["job_id"]
        if item.get("next_job_poll_at_unix") and now < item["next_job_poll_at_unix"]:
            return "waiting_result"
        from automation.manager import daemon
        try:
            payload = daemon.job_result(job_id)
            if payload is not None:
                digest = payload.get("input_sha256")
                if (payload.get("job") != job_id
                        or payload.get("profile_id") != profile_id
                        or payload.get("status") not in
                        {"passed", "failed", "cancelled", "indeterminate"}
                        or not isinstance(digest, str) or len(digest) != 64
                        or any(c not in "0123456789abcdef" for c in digest)):
                    raise RuntimeError("ALIS_UI_FOREIGN_JOB_RESULT")
                from automation.worker.privacy import chat_result
                summary = chat_result(payload)
            else:
                summary = None
        except Exception:
            _mark_unresolved(profile_id, "Worker receipt needs reconciliation")
            return "ui_reconciliation_required"

        def observed(_config, state):
            current = state["profiles"].get(profile_id)
            if not current or current.get("job_id") != job_id:
                return
            if payload is None:
                # After a restart, keep observing the *same* worker job ID.
                # An absent receipt cannot distinguish a slow worker from
                # a crashed one: NEVER start an additional local job.
                last_activity = current.get("last_activity_at_unix")
                age = (max(0, now - last_activity)
                       if type(last_activity) is int and last_activity > 0 else 0)
                stalled = age >= 180
                if stalled and current.get("status") != "waiting_result_stalled":
                    store.event(state, profile_id, "ui_job_stalled",
                                "No verified worker receipt; polling original job")
                current["next_job_poll_at_unix"] = now + (
                    min(60, 10 + (age // 60) * 10) if stalled else 10)
                current["status"] = ("waiting_result_stalled" if stalled
                                     else "waiting_result")
                return
            current.update(
                last_job_id=job_id, last_result=payload["status"],
                job_id=None, next_job_poll_at_unix=None,
                request="continuation", status="continuing",
                job_summary=summary)
            current["job_evidence"] = (
                current.get("job_evidence", []) + [
                    a["evidence_id"] for a in summary.get("actions", [])
                    if a.get("evidence_id")])[-128:]
            store.event(state, profile_id, "ui_job_result", job_id)
        store.change_state(observed)
        return "waiting_result"
    if item.get("next_run_at_unix") and now < item["next_run_at_unix"]:
        return "scheduled"
    kind = item.get("request") or ("continuation" if item.get("session") else "initial")
    new_chat = kind in {"initial", "new", "rotation", "manual_reset"}
    if kind in {"restart", "recovery"}:
        return "ALIS_UI_UNCERTAIN_RESTART_REQUIRES_REVIEW"
    if not new_chat and item.get("session") is None:
        return "ALIS_UI_SESSION_NOT_BOUND"
    pinned_target = ((item.get("session") or {}).get("ui_target_key")
                     if not new_chat else None)
    if not new_chat and (not isinstance(pinned_target, str)
            or len(pinned_target) != 64
            or any(c not in "0123456789abcdef" for c in pinned_target)):
        return "ALIS_UI_TARGET_IDENTITY_REQUIRES_REVIEW"
    if kind == "rotation" and not item.get("checkpoint"):
        return "ALIS_UI_ROTATION_CHECKPOINT_REQUIRED"
    prompt_kind = ("rotation" if kind in {"rotation", "manual_reset"} else
                   "initial" if new_chat else "continuation")
    prompt = pending_prompt(profile, item, kind if kind == "manual_reset" else prompt_kind)
    command = "rotate-send" if new_chat else "send"
    attempt = str(uuid.uuid4())
    pending = {
        "transport": UI_TRANSPORT, "attempt_id": attempt,
        "phase": "dispatching", "kind": prompt_kind,
        "prompt_sha256": hashlib.sha256(prompt.encode()).hexdigest(),
        # Private manager state already owns task prompts. Retain this exact
        # immutable input so source/config changes cannot corrupt recovery.
        "prompt": prompt,
        "prepared_at_unix": now,
    }

    def prepare(config, state):
        checked, current = _owner(config, state, profile_id)
        if (not checked["enabled"] or current["desired"] != "run"
                or current.get("pending") or current.get("job_id")
                or current.get("request") != item.get("request")
                or current.get("command_seq") != item.get("command_seq")):
            return False
        current["pending"] = pending
        current["status"] = "ui_dispatching"
        current["run_active"] = True
        store.event(state, profile_id, "ui_send_prepared", attempt)
        return True
    try:
        if queue_owner is not None:
            from automation import queue as task_queue
            with task_queue._lock():
                current_queue = task_queue._load()
                expected_repo, expected_code, expected_sha = queue_owner
                if (not current_queue
                        or current_queue.get("mode") != "ordered"
                        or current_queue.get("state") != "active"
                        or current_queue.get("approved_start") is not True
                        or current_queue.get("stop_requested")
                        or current_queue.get("active") != {
                            "repository": expected_repo, "code": expected_code}
                        or sum(
                            1 for entry in current_queue.get("items", [])
                            if isinstance(entry, dict)
                            and entry.get("repository") == expected_repo
                            and entry.get("code") == expected_code
                            and entry.get("source_sha") == expected_sha
                            and entry.get("state") == "active"
                        ) != 1):
                    return "ALIS_UI_QUEUE_STOPPED_BEFORE_SUBMISSION"
                # The intent is durable while queue.lock excludes Stop.
                admitted = store.change_state(prepare)
        else:
            admitted = store.change_state(prepare)
        if not admitted:
            return "owner_changed"
        # UI journal fsync occurs in runtime.desktop BEFORE composer change.
        # Runtime must not retry an ambiguous/failed click.
        ack_options = {"defer_acknowledgement": True} if managed_ack else {}
        if pinned_target is not None:
            label = (item.get("session") or {}).get("ui_chat_label")
            kwargs = {"target_key": pinned_target}
            if label is not None:
                kwargs["chat_label"] = label
            payload = desktop(command, prompt, **kwargs, **ack_options)
        elif kind == "manual_reset":
            # Explicit owner escape from a stuck OLD chat. A distinct fresh
            # Project composer must be checked before any new UI send. This
            # does not clear the old session/receipt or retry an old prompt.
            payload = desktop(command, prompt, new_chat_unowned=True,
                              owner_chat_reset=True, **ack_options)
        elif new_chat and item.get("session") is None:
            # An initial task owns no earlier UI chat. Navigate to its Project
            # without touching a foreign composer or stopping its generation.
            payload = desktop(command, prompt, new_chat_unowned=True, **ack_options)
        else:
            payload = desktop(command, prompt, **ack_options)
        text = runtime.extract_response_text(payload)
        directive = parse_loop_directive(text)
        observed_target = payload.get("ui_target_key")
        if (not isinstance(observed_target, str)
                or len(observed_target) != 64
                or any(c not in "0123456789abcdef" for c in observed_target)
                or (pinned_target is not None and observed_target != pinned_target)):
            raise RuntimeError("ALIS_UI_CHAT_IDENTITY_UNVERIFIED")
        if len(text) > PRIVATE_RESPONSE_LIMIT:
            raise RuntimeError("ALIS_UI_RESPONSE_EXCEEDS_BOUND")
        from automation.manager import daemon
        checkpoint = daemon._checkpoint(text)
        intent = payload.get("ui_send_intent")
        if managed_ack and (not isinstance(intent, dict)
                or set(intent) != {"id", "command", "prompt_sha256"}
                or str(uuid.UUID(intent.get("id", ""))) != intent["id"]
                or intent["command"] != command or intent["prompt_sha256"] != pending["prompt_sha256"]):
            raise RuntimeError("ALIS_UI_SEND_INTENT_MISMATCH")
        response_path = (store.state_dir() / "ui-responses" /
                         profile_id / (attempt + ".json"))
        store._write(response_path, {
            "transport": UI_TRANSPORT, "attempt_id": attempt,
            "directive": directive.kind.value, "response": text,
            "ui_target_key": observed_target,
            **({"ui_send_intent": intent} if managed_ack else {}),
            "at_unix": int(time.time())})
    except runtime.UiNotSent as error:
        # Auto-recover only a cryptographically matched, explicit NO-SEND
        # receipt. Unknown send/click outcomes are intentionally NOT here.
        # The journal must also be gone after acknowledge_not_sent.
        journal = store.state_dir() / "ui-send-journal" / "pending.json"
        safely_not_sent = not journal.exists() and not journal.is_symlink()
        def unsent(_config, state):
            current = state["profiles"].get(profile_id)
            if (not current or not _same_pending(current.get("pending"), pending)
                    or pending["prompt_sha256"] != error.prompt_sha256):
                return False
            count = current.get("ui_pre_send_failures", 0)
            if type(count) is not int or count < 0 or count > 3:
                # A corrupt recovery counter is not a restart invitation.
                current.update(desired="paused", run_active=False,
                               status="ui_recovery_requires_review",
                               last_error="Invalid pre-send retry evidence")
                return True
            count += 1
            if safely_not_sent and current.get("desired") == "run" and count < 3:
                # 5s then 15s; third proven failure pauses. The task
                # checkpoint, original prompt, SHA pin and queue approval
                # are unchanged; no worker job can be resubmitted here.
                current.update(pending=None, run_active=False,
                               ui_pre_send_failures=count,
                               next_run_at_unix=now + (5 if count == 1 else 15),
                               status="ui_retry_wait", last_error=str(error))
                store.event(state, profile_id, "ui_pre_send_retry_scheduled",
                            "Exact no-send receipt; bounded delayed retry")
                return True
            current.update(pending=None, run_active=False,
                           ui_pre_send_failures=count,
                           desired="paused" if current["desired"] == "run"
                               else current["desired"],
                           status="ui_composition_failed",
                           last_error=str(error))
            store.event(state, profile_id, "ui_not_sent",
                        "Max attempts or journal uncertainty; no automatic retry")
            return True
        if store.change_state(unsent):
            return "ui_retry_wait" if (safely_not_sent and
                store.read_snapshot()[1]["profiles"][profile_id].get("status")
                == "ui_retry_wait") else "ui_composition_failed"
        _mark_unresolved(profile_id, "Pre-Send failure identity mismatch")
        return "ui_reconciliation_required"
    except Exception:
        _mark_unresolved(profile_id, "UI send or observation is uncertain")
        return "ui_reconciliation_required"

    status = _complete_observed(profile_id, profile, pending, directive,
                                observed_target, checkpoint, now, new_chat,
                                payload.get("ui_chat_label"))
    if managed_ack and status != "owner_changed_after_response":
        try:
            runtime.acknowledge_completed(store.state_dir() / "ui-send-journal/pending.json",
                                          intent["id"])
        except Exception:
            _mark_unresolved(profile_id, "Result committed; original send journal cleanup required")
            return "ui_reconciliation_required"
    return status



def reconcile_pending(profile_id: str, *, chat_label: str | None = None,
                      observer=None, original_prompt: str | None = None) -> str:
    """Observe the exact original submitted turn. Never sends or resumes.

    An explicit supervised recovery holds the existing manager lock. A crash
    before journal retirement remains blocked, preserving the original intent.
    """
    with runtime.lock_path().open("a+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return "manager_busy"
        config, state, issues = store.read_snapshot()
        if issues:
            raise RuntimeError("ALIS_UI_INVALID_CONFIGURATION")
        profile, item = _owner(config, state, profile_id, allow_journal=True)
        pending = item.get("pending")
        if pending is None and item.get("desired") != "run":
            return _finish_committed_journal(profile_id, item)
        if (not isinstance(pending, dict) or pending.get("transport") != UI_TRANSPORT
                or pending.get("kind") not in {"initial", "continuation", "rotation"}
                or item.get("desired") == "run"):
            raise RuntimeError("ALIS_UI_RECONCILE_PAUSED_ORIGINAL_REQUIRED")
        if (not isinstance(pending.get("attempt_id"), str)
                or str(uuid.UUID(pending["attempt_id"])) != pending["attempt_id"]):
            raise RuntimeError("ALIS_UI_ORIGINAL_JOURNAL_REQUIRED")
        prompt = pending.get("prompt") or original_prompt or pending_prompt(profile, item, pending["kind"])
        if not isinstance(prompt, str) or len(prompt) > PRIVATE_RESPONSE_LIMIT:
            raise RuntimeError("ALIS_UI_ORIGINAL_PROMPT_REQUIRED")
        digest = hashlib.sha256(prompt.encode()).hexdigest()
        path = store.state_dir() / "ui-send-journal/pending.json"
        command = "send" if pending["kind"] == "continuation" else "rotate-send"
        legacy_response = None
        retired = False
        if not path.exists() and not path.is_symlink():
            # Legacy runtime retired the journal before the manager commit.
            # Require the same manager-attempt response, one matching archived
            # intent within its original time window, AND fresh full-turn UI
            # proof. Never restore a retired journal or infer another Send.
            legacy_response = _read_private_receipt(store.state_dir() / "ui-responses" /
                                        profile_id / (pending["attempt_id"] + ".json"))
            if (legacy_response.get("transport") != UI_TRANSPORT
                    or legacy_response.get("attempt_id") != pending["attempt_id"]
                    or not isinstance(legacy_response.get("response"), str)
                    or type(legacy_response.get("at_unix")) is not int):
                raise RuntimeError("ALIS_UI_LEGACY_RESPONSE_MISMATCH")
            archive = store.state_dir() / "ui-send-journal/observed"
            if archive.is_symlink() or not archive.is_dir():
                raise RuntimeError("ALIS_UI_ORIGINAL_JOURNAL_REQUIRED")
            matches = []
            for candidate in archive.glob("*.json"):
                record = _read_private_receipt(candidate)
                if (record.get("prompt_sha256") == digest and record.get("command") == command
                        and type(record.get("at_unix")) is int
                        and pending["prepared_at_unix"] <= record["at_unix"] <= legacy_response["at_unix"]):
                    if (not isinstance(record.get("id"), str)
                            or str(uuid.UUID(record["id"])) != record["id"]
                            or candidate.name != record["id"] + ".json"):
                        raise RuntimeError("ALIS_UI_ORIGINAL_JOURNAL_REQUIRED")
                    matches.append(record)
            if len(matches) != 1:
                raise RuntimeError("ALIS_UI_ORIGINAL_JOURNAL_REQUIRED")
            journal = matches[0]
            retired = True
        else:
            journal = _read_private_receipt(path)
        if (pending.get("prompt_sha256") != digest or journal.get("prompt_sha256") != digest
                or journal.get("schema") != "alis.chat-ui-send.v1"
                or journal.get("phase") != "attempted" or journal.get("command") != command):
            raise RuntimeError("ALIS_UI_ORIGINAL_PROMPT_CHANGED")
        target = (item.get("session") or {}).get("ui_target_key") if command == "send" else None
        observe = runtime.desktop if observer is None else observer
        payload = observe("observe-submitted", prompt, target_key=target,
                          chat_label=chat_label or (item.get("session") or {}).get("ui_chat_label"))
        if payload.get("completed") is not True:
            return "original_turn_in_progress"
        observed_target = payload.get("ui_target_key")
        if (payload.get("attestation") != "local-ui-user-turn-v1"
                or payload.get("prompt_sha256") != digest
                or not isinstance(observed_target, str) or len(observed_target) != 64
                or any(c not in "0123456789abcdef" for c in observed_target)
                or (target is not None and target != observed_target)
                or payload.get("response", {}).get("extractionSignal") != "submitted-user-turn-assistant"):
            raise RuntimeError("ALIS_UI_ORIGINAL_RESPONSE_MISMATCH")
        text = runtime.extract_response_text(payload)
        if len(text) > PRIVATE_RESPONSE_LIMIT:
            raise RuntimeError("ALIS_UI_RESPONSE_EXCEEDS_BOUND")
        if legacy_response is not None and text != legacy_response["response"]:
            raise RuntimeError("ALIS_UI_LEGACY_RESPONSE_MISMATCH")
        directive = parse_loop_directive(text)
        from automation.manager import daemon
        checkpoint = daemon._checkpoint(text)
        store._write(store.state_dir() / "ui-responses" / profile_id /
                     (pending["attempt_id"] + ".json"), {
            "transport": UI_TRANSPORT, "attempt_id": pending["attempt_id"],
            "directive": directive.kind.value, "response": text,
            "ui_target_key": observed_target,
            "ui_send_intent": {"id": journal["id"], "command": command,
                               "prompt_sha256": digest},
            "attestation": "local-ui-user-turn-v1", "at_unix": int(time.time())})
        status = _complete_observed(profile_id, profile, pending, directive,
                                    observed_target, checkpoint, int(time.time()),
                                    command != "send", payload.get("ui_chat_label"))
        if status == "owner_changed_after_response":
            return status
        # Commit the bound manager receipt first. No subsequent send can pass
        # the retained journal if this final archival step is interrupted.
        if not retired:
            runtime.acknowledge_completed(path, journal["id"])
        return "ui_reconciled_" + status


def reconcile_interrupted_pending(profile_id: str, *, approved=False, observer=None) -> str:
    """Owner-stopped delivery is a terminal interruption, never task success.

    Observe the full original input and previously bound local UI anchor.
    No Send, queue admission, worker replay or native attestation is granted.
    A durable witness permits finishing journal archival after a crash without
    observing/sending again or counting delivery twice.
    """
    if approved is not True:
        raise RuntimeError("ALIS_UI_INTERRUPTION_APPROVAL_REQUIRED")
    from automation.chat_bridge.send_journal import acknowledge_interrupted
    def digest(value):
        return hashlib.sha256(json.dumps(value, sort_keys=True,
            separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
    def witness_path(attempt):
        if not isinstance(attempt, str) or str(uuid.UUID(attempt)) != attempt:
            raise RuntimeError("ALIS_UI_INTERRUPTION_IDENTITY_INVALID")
        return store.state_dir() / "ui-interrupted" / profile_id / (attempt + ".json")
    with runtime.lock_path().open("a+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return "manager_busy"
        config, state, issues = store.read_snapshot()
        if issues:
            raise RuntimeError("ALIS_UI_INVALID_CONFIGURATION")
        _, item = _owner(config, state, profile_id, allow_journal=True)
        if item.get("desired") != "stopped" or item.get("run_active") or item.get("job_id"):
            raise RuntimeError("ALIS_UI_STOPPED_OWNER_REQUIRED")
        path = store.state_dir() / "ui-send-journal/pending.json"
        pending = item.get("pending")
        if pending is None:
            failed = item.get("failed_turn") or {}
            if (failed.get("transport") != UI_TRANSPORT
                    or failed.get("outcome") != "interrupted_delivered"):
                raise RuntimeError("ALIS_UI_ORIGINAL_INTERRUPTION_REQUIRED")
            evidence_path = witness_path(failed.get("ui_attempt_id"))
            if evidence_path.is_symlink() or evidence_path.stat().st_size > 500000:
                raise RuntimeError("ALIS_UI_INTERRUPTION_WITNESS_INVALID")
            evidence = json.loads(evidence_path.read_text())
            if digest(evidence) != failed.get("receipt_sha256"):
                raise RuntimeError("ALIS_UI_INTERRUPTION_WITNESS_INVALID")
            acknowledge_interrupted(path, failed["journal_attempt_id"],
                                    failed["prompt_sha256"], proof_sha256=failed["receipt_sha256"])
            return "ui_interrupted_already_recorded"
        if (not isinstance(pending, dict) or pending.get("transport") != UI_TRANSPORT
                or pending.get("kind") not in {"initial", "continuation", "rotation"}
                or not isinstance(pending.get("prompt"), str) or not callable(observer)):
            raise RuntimeError("ALIS_UI_ORIGINAL_OBSERVATION_REQUIRED")
        prompt = pending["prompt"]
        prompt_hash = hashlib.sha256(prompt.encode()).hexdigest()
        target = (item.get("session") or {}).get("ui_target_key")
        if (pending.get("prompt_sha256") != prompt_hash or len(prompt) > PRIVATE_RESPONSE_LIMIT
                or not isinstance(target, str) or len(target) != 64):
            raise RuntimeError("ALIS_UI_ORIGINAL_PROMPT_CHANGED")
        if path.is_symlink() or not path.is_file() or path.stat().st_size > 4096:
            raise RuntimeError("ALIS_UI_ORIGINAL_JOURNAL_REQUIRED")
        journal = json.loads(path.read_text())
        witness_path(journal.get("id"))  # Validate before changing manager state.
        command = "send" if pending.get("kind") == "continuation" else "rotate-send"
        if (journal.get("schema") != "alis.chat-ui-send.v1" or journal.get("phase") != "attempted"
                or journal.get("command") != command or journal.get("prompt_sha256") != prompt_hash):
            raise RuntimeError("ALIS_UI_ORIGINAL_JOURNAL_MISMATCH")
        payload = observer("observe-submitted", prompt, target_key=target)
        text = runtime.extract_response_text(payload)
        if (payload.get("completed") is not False or payload.get("delivery_observed") is not True
                or payload.get("idle_observed") is not True
                or payload.get("attestation") != "local-ui-user-turn-v1"
                or payload.get("prompt_sha256") != prompt_hash or payload.get("ui_target_key") != target
                or payload.get("response", {}).get("extractionSignal") != "submitted-user-turn-assistant"
                or payload.get("response", {}).get("markerCount") != 0
                or "ALIS_LOOP:" in text or "HADALIS_LOOP:" in text or len(text) > PRIVATE_RESPONSE_LIMIT):
            raise RuntimeError("ALIS_UI_INTERRUPTED_DELIVERY_UNVERIFIED")
        evidence = {"schema": "alis.ui-interrupted-delivery.v1", "pending": pending,
                    "journal": journal, "observation": payload,
                    "reason": "Owner-requested stop; completion unverified"}
        proof = digest(evidence)
        store._write(witness_path(pending["attempt_id"]), evidence)
        def retire(_config, current_state):
            current = current_state["profiles"].get(profile_id)
            if (not current or current.get("pending") != pending
                    or current.get("desired") != "stopped" or current.get("run_active")):
                return False
            current.update(pending=None, status="ui_interrupted_delivered", run_active=False,
                prompts_sent=current["prompts_sent"] + 1,
                last_error="Original delivery observed; interrupted, not completed",
                failed_turn={"transport": UI_TRANSPORT, "outcome": "interrupted_delivered",
                    "ui_attempt_id": pending["attempt_id"], "journal_attempt_id": journal["id"],
                    "prompt_sha256": prompt_hash, "receipt_sha256": proof},
                checkpoint={"phase": "interrupted-delivered", "summary":
                    "Prior turn was delivered and intentionally stopped. No completion accepted.",
                    "next": "Inspect canonical GitHub HEAD and earlier source effects before any distinct continuation; never replay the stopped prompt or approved job.",
                    "evidence_ids": []})
            store.event(current_state, profile_id, "ui_interrupted_delivery",
                        "Original intent archived; no success or queue advance")
            return True
        if not store.change_state(retire):
            return "owner_changed_after_observation"
        acknowledge_interrupted(path, journal["id"], prompt_hash, proof_sha256=proof)
        return "ui_interrupted_delivered"


def queue_tick(*, now: int | None = None, desktop=None) -> str:
    """Admit only the owner-approved, exact active ordered queue member.

    This NEVER claims a task, approves Start, changes transport gates, or
    advances a DONE receipt. A prepared queue cannot send anything.
    """
    from automation import managed_tasks, queue, taskflow as tf
    with queue._lock():
        document = queue._load()
        if not document:
            return "queue_idle"
        if document.get("mode") != "ordered":
            return "ALIS_UI_QUEUE_MODE_UNSUPPORTED"
        if document.get("state") in {
                "prepared", "waiting", "stopping", "stopped",
                "finished", "cancelled", "review_required"}:
            return "queue_idle"
        if (document.get("state") != "active"
                or document.get("approved_start") is not True
                or document.get("stop_requested")
                or not isinstance(document.get("active"), dict)):
            return "ALIS_UI_QUEUE_NOT_AUTHORIZED"
        active = document["active"]
        members = [
            member for member in document.get("items", [])
            if (isinstance(member, dict) and
                member.get("repository") == active.get("repository")
                and member.get("code") == active.get("code")
                and member.get("state") == "active")
        ]
        if (len(members) != 1
                or active.get("repository") not in tf.REPOSITORIES
                or not isinstance(active.get("code"), str)
                or not tf.CODE.fullmatch(active["code"])):
            return "ALIS_UI_QUEUE_OWNER_MISMATCH"
        source_sha = members[0].get("source_sha")
        if not isinstance(source_sha, str) or not tf.SHA.fullmatch(source_sha):
            return "ALIS_UI_QUEUE_OWNER_MISMATCH"
        pid = managed_tasks.profile_id(active["repository"], active["code"])
        config, state, issues = store.read_snapshot()
        owner = next((p for p in config["profiles"] if p["id"] == pid), None)
        runtime = state["profiles"].get(pid)
        if (issues or owner is None or runtime is None
                or managed_tasks.reference(owner) !=
                (active["repository"], active["code"])
                or not owner["enabled"]):
            return "ALIS_UI_QUEUE_PROFILE_NOT_RUNNING"
        if (runtime.get("desired") == "stopped"
                and runtime.get("status") == "completed"
                and runtime.get("last_success") == "DONE"
                and not runtime.get("pending") and not runtime.get("job_id")):
            return "queue_completed_pending_reconciliation"
        if (runtime.get("desired") == "stopped"
                and runtime.get("status") in {"idle", "disabled", "scheduled"} 
                and not runtime.get("pending") and not runtime.get("job_id")
                and not runtime.get("run_active")):
            # Queue claim and profile Start have separate durable records.
            # The single manager waits for explicit profile scheduling.
            return "queue_claim_waiting_profile_start"
        if runtime.get("desired") != "run":
            return "ALIS_UI_QUEUE_PROFILE_NOT_RUNNING"
        record = tf.load_task(active["code"], active["repository"])
        if (record.get("unresolved")
                or record.get("task", {}).get("base_sha") != source_sha
                or record.get("status") not in
                {"prepared", "handoff_ready", "awaiting_owner", "awaiting_cloud_ack"}):
            return "ALIS_UI_QUEUE_TASK_CHANGED"
        if record.get("status") == "awaiting_cloud_ack":
            from automation.lifecycle import _verified_local_receipt
            try:
                _verified_local_receipt(record)
            except tf.TaskError:
                return "ALIS_UI_QUEUE_LOCAL_RECEIPT_REQUIRES_REVIEW"
    # Do not hold queue.lock while observing the Desktop response; Stop can
    # revoke approval while waiting. The actual first send also needs an
    # atomic latest-state recheck inside ui_tick's durable prepare transaction.
    return ui_tick(pid, now=now, desktop=desktop,
                   queue_owner=(active["repository"], active["code"], source_sha))


def queue_loop(*, once: bool = False) -> int:
    """A queue-only alternate manager; no pending tasks implicitly started."""
    from automation.manager import daemon
    while True:
        now = int(time.time())
        store.change_state(lambda _c, s: daemon._heartbeat(s, now))
        status = queue_tick(now=now)
        if status in {"DONE", "queue_completed_pending_reconciliation"}:
            from automation import managed_tasks, taskflow
            try:
                managed_tasks.reconcile_ui_once()
            except (taskflow.TaskError, ValueError, RuntimeError, OSError):
                # Original local UI receipt and queue ownership are retained.
                # An unverified DONE cannot silently schedule a new Issue.
                status = "ALIS_UI_QUEUE_RECONCILIATION_REQUIRED"
        if once:
            return 0
        if status == "ui_reconciliation_required" or status.startswith("ALIS_UI_"):
            return 75
        time.sleep(POLL_SECONDS)


def loop(profile_id: str, *, once: bool = False) -> int:
    """Called ONLY by manager.daemon after its exclusive shared lock."""
    while True:
        now = int(time.time())
        # Keep Settings heartbeat and Start command acknowledgements within
        # the existing single manager service, without starting native ticks.
        from automation.manager import daemon
        store.change_state(lambda _c, s: daemon._heartbeat(s, now))
        state = ui_tick(profile_id, now=now)
        if once:
            return 0
        if state == "ui_reconciliation_required" or state.startswith("ALIS_UI_"):
            return 75
        time.sleep(POLL_SECONDS)
