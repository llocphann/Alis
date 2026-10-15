"""Opt-in single-owner Alis UI protocol inside the existing manager service.

This is NOT the native managed transport. A UI controller cannot claim
server-attested identity, and it never bypasses automation.transport_gate.
It runs only with an explicit profile selection, under manager.daemon's
existing exclusive chat-bridge.lock. A send intent is retained before IPC;
after crash/uncertain completion the profile is quarantined, NEVER resent.
"""
from __future__ import annotations

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


def _owner(config: dict, state: dict, profile_id: str) -> tuple[dict, dict]:
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
    for other_id, other in state["profiles"].items():
        if other_id != profile_id and (other.get("desired") == "run"
                or other.get("pending") or other.get("job_id")
                or other.get("run_active")):
            raise RuntimeError("ALIS_UI_ANOTHER_PROFILE_UNSETTLED")
    if (store.state_dir() / "ui-send-journal" / "pending.json").exists():
        raise RuntimeError("ALIS_UI_SEND_UNCERTAIN_RECONCILIATION_REQUIRED")
    return profile, item


def _mark_unresolved(profile_id: str, detail: str) -> None:
    def pause(_config, state):
        item = state["profiles"].get(profile_id)
        if not item:
            return
        item["desired"] = "paused"
        item["status"] = "ui_reconciliation_required"
        item["last_error"] = detail[:160]
        store.event(state, profile_id, "ui_reconciliation_required",
                    "Preserved original pending intent; no resend")
    store.change_state(pause)


def ui_tick(profile_id: str, *, now: int | None = None,
            desktop=None) -> str:
    """One bounded scheduler admission. Never invokes a second native owner."""
    now = int(time.time()) if now is None else now
    desktop = runtime.desktop if desktop is None else desktop
    config, state, issues = store.read_snapshot()
    if issues:
        return "invalid_configuration"
    try:
        profile, item = _owner(config, state, profile_id)
    except RuntimeError as error:
        # Preserve every existing native/foreign receipt: no mutation at all.
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
        # The existing manager waits on GitHub/local worker receipt, never
        # authorizes or re-executes a pending job.
        from automation.manager import daemon
        daemon._wait_result(config, state, profile_id, now)
        return "waiting_result"
    if item.get("next_run_at_unix") and now < item["next_run_at_unix"]:
        return "scheduled"
    kind = item.get("request") or ("continuation" if item.get("session") else "initial")
    new_chat = kind in {"initial", "new", "rotation"}
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
    prompt_kind = ("rotation" if kind == "rotation" else
                   "initial" if new_chat else "continuation")
    prompt = model.effective_prompt(profile, prompt_kind)
    prompt += "\nManaged Alis profile ID: " + profile_id + "\n"
    if item.get("checkpoint"):
        prompt += "\nSaved checkpoint:\n" + json.dumps(
            item["checkpoint"], ensure_ascii=False)
    if item.get("last_job_id"):
        prompt += ("\nCheck exact GitHub result in automation/results/"
                   + item["last_job_id"] + ".json\n")
    if item.get("job_summary"):
        prompt += "\nWorker summary:\n" + json.dumps(
            item["job_summary"], ensure_ascii=False)
    command = "rotate-send" if new_chat else "send"
    attempt = str(uuid.uuid4())
    pending = {
        "transport": UI_TRANSPORT, "attempt_id": attempt,
        "phase": "dispatching", "kind": prompt_kind,
        "prompt_sha256": hashlib.sha256(prompt.encode()).hexdigest(),
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
        if not store.change_state(prepare):
            return "owner_changed"
        # UI journal fsync occurs in runtime.desktop BEFORE composer change.
        # Runtime must not retry an ambiguous/failed click.
        if pinned_target is not None:
            payload = desktop(command, prompt, target_key=pinned_target)
        else:
            payload = desktop(command, prompt)
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
        response_path = (store.state_dir() / "ui-responses" /
                         profile_id / (attempt + ".json"))
        store._write(response_path, {
            "transport": UI_TRANSPORT, "attempt_id": attempt,
            "directive": directive.kind.value, "response": text,
            "at_unix": int(time.time())})
    except Exception:
        _mark_unresolved(profile_id, "UI send or observation is uncertain")
        return "ui_reconciliation_required"

    def complete(_config, state):
        current = state["profiles"].get(profile_id)
        if not current or current.get("pending") != pending:
            return False
        current["pending"] = None
        current["last_success"] = directive.kind.value
        current["loop_state"] = directive.kind.value.lower()
        current["iterations"] += 1
        current["chat_iterations"] += 1
        current["prompts_sent"] += 1
        current["last_activity_at_unix"] = now
        current["last_error"] = ""
        if current.get("session") is None or new_chat:
            current["session"] = {
                "transport": UI_TRANSPORT,
                "project_name": profile["project_name"],
                "local_run_id": str(uuid.uuid4()),
                "ui_target_key": observed_target,
            }
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
        return True
    if not store.change_state(complete):
        return "owner_changed_after_response"
    return directive.kind.value


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
        if state == "ui_reconciliation_required":
            return 75
        time.sleep(POLL_SECONDS)
