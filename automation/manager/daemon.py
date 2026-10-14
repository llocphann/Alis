"""Independent, durable profile sessions. Quickshell is a control client only."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import fcntl
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import time
import uuid

from automation.chat_bridge.protocol import DirectiveKind, parse_loop_directive
from automation.manager.model import effective_prompt, limit_decision
from automation.manager.store import (archive_removed_profile, change, change_state,
                                      event, read_snapshot, state_dir, state_path, _write)

ROOT = Path(__file__).resolve().parents[2]
NATIVE_CLI = ROOT / "automation/chat_bridge/native_cli.mjs"
RESULTS = "automation/results"
POLL_SECONDS = 2
CONCURRENCY = max(1, min(8, int(os.environ.get("HADALIS_MANAGER_CONCURRENCY", "4"))))
_INFLIGHT = {}


def native_command(op: str, **payload) -> dict:
    result = subprocess.run(["node", str(NATIVE_CLI)], cwd=ROOT,
        input=json.dumps({"op": op, **payload}), capture_output=True, text=True,
        timeout=45, check=False)
    if result.returncode:
        # Native adapter never returns request headers or credentials.
        raise RuntimeError((result.stderr or "Desktop operation failed").strip()[:500])
    if len(result.stdout) > 120000:
        raise RuntimeError("Desktop response exceeded capture bound")
    value = json.loads(result.stdout)
    if not isinstance(value, dict):
        raise RuntimeError("invalid Desktop response")
    return value


def _profile(config: dict, profile_id: str) -> dict:
    return next(p for p in config["profiles"] if p["id"] == profile_id)


def _heartbeat(state: dict, now: int) -> None:
    state["manager_heartbeat_at_unix"] = now
    state["command_ack_seq"] = state["command_seq"]
    for profile_id, item in state["profiles"].items():
        if item["status"] == "scheduler_unavailable" and item["desired"] == "run":
            item["status"] = "recovering_pending" if item["pending"] else "scheduled"
            item["last_error"] = ""
            event(state, profile_id, "scheduler_recovered")


def _configuration_problem(state: dict, issues: list[str]) -> None:
    detail = ("Invalid Automation configuration: " + "; ".join(issues))[:2000]
    for profile_id, item in state["profiles"].items():
        if item["desired"] == "run":
            if item["status"] != "invalid_configuration" or item["last_error"] != detail:
                item.update(status="invalid_configuration", last_error=detail)
                event(state, profile_id, "invalid_configuration", detail)


def migrate_runtime(config: dict, state: dict) -> None:
    if state.get("engine_version") == 2:
        return
    backup = state_dir() / "migration-v1.json"
    if not backup.exists():
        _write(backup, {"config": config, "state": state, "at_unix": int(time.time())})
    old_owner = state.get("owner_id")
    for profile_id, item in state["profiles"].items():
        profile=next((p for p in config["profiles"] if p["id"]==profile_id),None)
        actions=[e["kind"] for e in state["events"] if e.get("profile_id")==profile_id and e.get("kind") in {"start","resume","restart","pause","stop"}]
        if profile and profile["enabled"] and item["desired"]=="paused" and item["pending"] and actions and actions[-1] in {"start","resume","restart"} and profile["max_poll_errors"]>0 and item["poll_errors"]>=profile["max_poll_errors"] and item["last_error"]:
            # v1 automatically overwrote the maintainer's last Resume when DOM
            # polling failed. Recover only with that explicit command evidence;
            # a later user Pause/Stop always wins.
            item["desired"]="run"
            event(state,profile_id,"legacy_error_pause_recovered","Restored last explicit run command; original pending message will only be observed")
        item["run_active"] = bool(profile_id == old_owner or item["pending"] or item["job_id"])
        if item["pending"] and not item["pending"].get("user_message_id"):
            item["recovery"] = {"kind": "legacy_identity", "next_at_unix": 0}
            item["status"] = "recovering_pending"
        elif item["status"] == "waiting_owner":
            item["status"] = "scheduled"
            item["status_detail"] = ""
        if item.get("park_requested"):
            item["park_requested"] = False
    state.update(engine_version=2, owner_id=None, requested_profile_id=None)
    event(state, None, "sessions_migrated", "Legacy state retained privately; profiles now progress independently")


def _claim(config: dict, state: dict, now: int, profile_id: str) -> bool:
    item, profile = state["profiles"][profile_id], _profile(config, profile_id)
    if item["run_active"]:
        return True
    if not profile["enabled"] or item["desired"] != "run" or now < (item["next_run_at_unix"] or 0):
        return False
    item.update(run_active=True, status="starting", started_at_unix=now,
        run_start_iterations=item["iterations"], run_start_prompts=item["prompts_sent"],
        last_run_at_unix=now, next_run_at_unix=None)
    failed=(item["failed_turn"] or {}).get("conversation_id")
    item["request"] = item["request"] or ("recovery" if failed and (item["session"] or {}).get("conversation_id")==failed else "continuation" if item["session"] else "initial")
    event(state, profile_id, "started")
    return True


def _release(state: dict, profile_id: str, now: int, status: str) -> None:
    item = state["profiles"][profile_id]
    item.update(run_active=False, request=None, status=status, status_detail="",
                last_activity_at_unix=now)
    # Keep chat identity/checkpoint/job receipts for resume and removal recovery.
    event(state, profile_id, status)


def _handle_removals(config: dict, state: dict, protected=()) -> bool:
    ids = [p["id"] for p in config["profiles"] if
           state["profiles"][p["id"]].get("remove_requested") and p["id"] not in protected]
    if not ids:
        return False
    def remove(c, s):
        for profile_id in ids:
            item = s["profiles"].get(profile_id)
            if not item or not item["remove_requested"]:
                continue
            path = archive_removed_profile(_profile(c, profile_id), item)
            c["profiles"] = [p for p in c["profiles"] if p["id"] != profile_id]
            s["profiles"].pop(profile_id)
            if s.get("owner_id") == profile_id: s["owner_id"] = None
            if s.get("requested_profile_id") == profile_id: s["requested_profile_id"] = None
            event(s, profile_id, "removed", f"ChatGPT history retained; private recovery copy: {path}")
    change(remove)
    return True


def _pending_key(pending: dict) -> str:
    return pending.get("user_message_id") or hashlib.sha256(json.dumps(pending, sort_keys=True).encode()).hexdigest()


def _same_pending(item: dict | None, pending: dict) -> bool:
    return bool(item and item["pending"] and _pending_key(item["pending"]) == _pending_key(pending))


def _observe_failure(profile_id: str, now: int, exc: Exception, *, pending=None, job=False) -> None:
    def record(config, state):
        item = state["profiles"].get(profile_id)
        if not item or item["remove_requested"] or (pending and not _same_pending(item, pending)):
            return
        key = "job_poll_errors" if job else "poll_errors"
        item[key] += 1
        item["failures"] += 1
        delay = min(300, _profile(config, profile_id)["retry_delay_seconds"] * 2 ** min(item[key] - 1, 4))
        if pending:
            item["pending"]["poll_after_unix"] = now + delay
        elif job:
            item["next_job_poll_at_unix"] = now + delay
        else:
            item["next_run_at_unix"] = now + delay
        detail = str(exc)[:1000]
        if item["last_error"] != detail or item[key] == 1:
            event(state, profile_id, "observation_retry", detail)
        item.update(last_error=detail, status="transport_unavailable")
        # Observations are bounded/backed off, but never disabled by navigation,
        # a finite error counter, Desktop/network downtime or shell crashes.
    change_state(record)


def _legacy_adopt(config: dict, item: dict, profile_id: str, now: int) -> None:
    pending = item["pending"]
    if now < (item.get("recovery") or {}).get("next_at_unix", 0):
        return
    profile = _profile(config, profile_id)
    body = effective_prompt(profile, pending.get("kind", "continuation"))
    lines = [line.strip() for line in body.splitlines() if line.strip() and not line.strip().startswith("[@")]
    identity = native_command("adopt", project_name=item["active_project_name"] or profile["project_name"],
        prepared_at_unix=pending["prepared_at_unix"], match_text=lines[0])
    def adopted(c, s):
        current = s["profiles"].get(profile_id)
        if not _same_pending(current, pending): return
        current["pending"].update(identity, phase="acknowledged", poll_after_unix=now)
        current["session"] = {"conversation_id": identity["conversation_id"], "project_id": identity["project_id"]}
        current["recovery"] = None
        current["parked_pending"] = False
        event(s, profile_id, "legacy_identity_verified", identity["conversation_id"])
    change_state(adopted)


def _submit(config: dict, state: dict, profile_id: str, now: int) -> None:
    profile, item = _profile(config, profile_id), state["profiles"][profile_id]
    kind = item["request"] or "continuation"
    new_chat = kind in {"initial", "new", "rotation", "restart", "recovery"}
    session = None if new_chat else item["session"]
    if not new_chat and not session:
        raise RuntimeError("Previous session identity needs reconciliation; no new prompt was sent")
    project_id = session.get("project_id") if session else native_command("project", name=profile["project_name"])["project_id"]
    parent = str(uuid.uuid4())
    if session:
        cursor = native_command("cursor", conversation_id=session["conversation_id"])
        if cursor["current_node"] != item["response_message_id"]:
            def changed(c, s):
                current = s["profiles"].get(profile_id)
                if current:
                    current.update(desired="paused", status="session_changed",
                        last_error="Managed chat changed outside Automation; checkpoint retained")
                    event(s, profile_id, "session_changed")
            change_state(changed)
            return
        parent = cursor["current_node"]
    if profile["requires_github"]:native_command("preflight",requires_github=True)
    prompt_kind = "rotation" if kind in {"rotation","recovery"} else "initial" if new_chat else "continuation"
    prompt = effective_prompt(profile, prompt_kind)
    prompt += "\nManaged profile ID: " + profile_id + "\n"
    if kind=="recovery":
        prompt += "\nThe server confirmed that the previous generation ended with failure. This is a new recovery step, not a replay. Inspect current dev, private worker receipt summaries and evidence before any mutation. Do not repeat commands/jobs whose outcome is uncertain. Reconcile existing effects and continue from the checkpoint.\n"+json.dumps(item["failed_turn"])
    if item["checkpoint"]:
        prompt += "\n\nDurable profile checkpoint:\n" + json.dumps(item["checkpoint"], ensure_ascii=False)
    if item["last_job_id"]:
        prompt += f"\n\nLocal result: {RESULTS}/{item['last_job_id']}.json ({item['last_result']}). Inspect the evidence before the next decision.\n"
    if item["job_summary"]:
        prompt += "\nPrivate worker result projection (raw evidence remains local):\n"+json.dumps(item["job_summary"],ensure_ascii=False)
    pending = {"user_message_id": str(uuid.uuid4()), "parent_message_id": parent,
        "conversation_id": session.get("conversation_id") if session else None,
        "project_id": project_id, "kind": prompt_kind, "prepared_at_unix": now,
        "poll_after_unix": now + POLL_SECONDS, "counted": False, "phase": "dispatching"}
    def prepare(c, s):
        current = s["profiles"].get(profile_id)
        if not current or current["pending"] or current["desired"] != "run" or current["remove_requested"]:
            return False
        if current["command_seq"] != item["command_seq"]: return False
        if session and any(pid!=profile_id and other.get("session",{}).get("conversation_id")==session["conversation_id"] and other["run_active"] for pid,other in s["profiles"].items() if other.get("session")):
            current.update(desired="paused",status="session_conflict",last_error="Another profile already manages this conversation; original receipt retained")
            return False
        current.update(pending=pending, status="thinking", status_detail="", last_activity_at_unix=now)
        if new_chat:
            current.update(session={"conversation_id":None, "project_id":project_id},
                active_project_name=profile["project_name"], chat_started_at_unix=now, chat_iterations=0)
            if kind == "restart":
                current.update(started_at_unix=now, run_start_iterations=current["iterations"], run_start_prompts=current["prompts_sent"])
        event(s, profile_id, "prompt_prepared", pending["user_message_id"])
        return True
    if not change_state(prepare): return
    try:
        receipt = native_command("submit", **pending, prompt=prompt, requires_github=profile["requires_github"])
    except Exception as exc:
        _observe_failure(profile_id, now, exc, pending=pending)
        return # Dispatch was persisted: next step can only observe this message.
    def acknowledged(c, s):
        current = s["profiles"].get(profile_id)
        if not _same_pending(current, pending): return
        chat = receipt.get("conversation_id")
        if chat:
            current["pending"].update(conversation_id=chat, phase="acknowledged")
            current["session"]["conversation_id"] = chat
        if receipt.get("dispatched"):
            current["pending"]["counted"] = True
            current["prompts_sent"] += 1
        current["request"] = "continuation" if current["request"] != "restart" else "restart"
        event(s, profile_id, "prompt_submitted", pending["user_message_id"])
    change_state(acknowledged)


def _checkpoint(text: str) -> dict | None:
    lines = [line[len("HADALIS_CHECKPOINT:"):].strip() for line in text.splitlines() if line.startswith("HADALIS_CHECKPOINT:")]
    if not lines: return None
    if len(lines) != 1 or len(lines[0]) > 6000: raise ValueError("invalid checkpoint envelope")
    data = json.loads(lines[0])
    if not isinstance(data, dict) or set(data) - {"phase", "summary", "next", "evidence_ids"}:
        raise ValueError("invalid checkpoint fields")
    for key in ("phase", "summary", "next"):
        if key in data and (not isinstance(data[key], str) or len(data[key]) > 2000):
            raise ValueError("invalid checkpoint text")
    ids = data.get("evidence_ids", [])
    if not isinstance(ids, list) or len(ids) > 32 or any(not isinstance(x,str) or len(x)>128 for x in ids):
        raise ValueError("invalid checkpoint evidence")
    return data


def _reports(text, evidence_ids):
    lines=[x[len("HADALIS_DIAGNOSIS:"):] for x in text.splitlines() if x.startswith("HADALIS_DIAGNOSIS:")]
    if len(lines)>16:raise ValueError("diagnosis report exceeds bound")
    reports=[]
    for line in lines:
        if len(line)>4000:raise ValueError("diagnosis report exceeds bound")
        data=json.loads(line)
        if not isinstance(data,dict) or set(data)!={"conclusion","evidence_ids"} or not isinstance(data["conclusion"],str):
            raise ValueError("diagnosis requires conclusion and evidence IDs")
        ids=data["evidence_ids"]
        if not isinstance(ids,list) or not ids or len(ids)>32 or any(i not in evidence_ids for i in ids):
            raise ValueError("diagnosis cites unavailable evidence")
        reports.append(data)
    return reports


def _poll(config: dict, state: dict, profile_id: str, now: int) -> None:
    item = state["profiles"][profile_id]
    pending = item["pending"]
    if now < pending.get("poll_after_unix", 0): return
    try:
        if not pending.get("user_message_id"):
            _legacy_adopt(config, item, profile_id, now)
            return
        cache = state_dir() / "responses" / profile_id / f"{pending['user_message_id']}.json"
        if cache.exists():
            receipt = json.loads(cache.read_text())
            if receipt["user_message_id"] != pending["user_message_id"]:
                raise ValueError("response receipt identity mismatch")
            result = {"completed":True, "conversation_id":receipt["conversation_id"], "response":receipt["response"]}
        else:
            result = native_command("poll", pending=pending)
        if not result.get("completed"):
            if result.get("superseded"):
                # A user advanced this managed conversation before its final
                # response. Reattaching the conversation's current stream could
                # follow that different turn. Retain the original receipt and
                # isolate the conflict; ordinary navigation never reaches here.
                def superseded(c,s):
                    current=s["profiles"].get(profile_id)
                    if not _same_pending(current,pending):return
                    prior=current.get("recovery") or {}
                    successor=result.get("successor_user_message_id")
                    if prior.get("kind")!="session_superseded" or prior.get("successor_user_message_id")!=successor:
                        event(s,profile_id,"session_changed","Later user turn observed; original submission retained")
                    if current["desired"]=="run":current["desired"]="paused"
                    current.update(status="session_changed",poll_errors=0,
                        last_error="A later user message superseded the managed turn; original receipt retained",
                        recovery={"kind":"session_superseded","successor_user_message_id":successor})
                    current["pending"]["poll_after_unix"]=now+60
                change_state(superseded);return
            if result.get("terminal_failed"):
                # The server has proved that generation ended. Archive this
                # turn and ask the reasoning agent for a distinct recovery step.
                failed_path=state_dir()/"failed-turns"/profile_id/(pending["user_message_id"]+".json")
                _write(failed_path,{"pending":pending,"at_unix":now,"evidence":"server terminal failure"})
                def failed_generation(c,s):
                    current=s["profiles"].get(profile_id)
                    if not _same_pending(current,pending):return
                    if not current["pending"].get("counted"):current["prompts_sent"]+=1
                    current["failures"]+=1
                    current["failed_turn"]={"conversation_id":result["conversation_id"],"user_message_id":pending["user_message_id"],"observed_at_unix":now,"error_code":"server_terminal_failed"}
                    current.update(pending=None,generation_recoveries=current["generation_recoveries"]+1,request="recovery",status="recovering_generation",next_run_at_unix=now+30)
                    if current["generation_recoveries"]>3:current.update(desired="paused",status="recovery_required")
                    event(s,profile_id,"generation_terminal_failed","Distinct evidence/reconciliation step scheduled; original prompt never replayed")
                change_state(failed_generation);return
            resume_due = result.get("submitted") and result.get("conversation_id") and now-pending["prepared_at_unix"]>=60 and pending.get("resume_attempts",0)<3 and now>=pending.get("resume_after_unix",0)
            if resume_due:
                # Resume reattaches an existing stream only. Persist the bounded
                # attempt before IPC, including when its acknowledgement is lost.
                def resume_intent(c,s):
                    current=s["profiles"].get(profile_id)
                    if not _same_pending(current,pending):return False
                    current["pending"].update(resume_attempts=pending.get("resume_attempts",0)+1,resume_after_unix=now+300)
                    event(s,profile_id,"stream_reattach",pending["user_message_id"]);return True
                if change_state(resume_intent):
                    try:native_command("resume",pending={**pending,"conversation_id":result["conversation_id"]})
                    except Exception:pass # Observations continue even if reattachment is unsupported/offline.
            def waiting(c, s):
                current = s["profiles"].get(profile_id)
                if not _same_pending(current, pending): return
                if result.get("conversation_id"):
                    current["pending"]["conversation_id"] = result["conversation_id"]
                    current["session"]["conversation_id"] = result["conversation_id"]
                current["pending"]["poll_after_unix"] = now + (30 if result.get("uncertain") or result.get("streamError") else POLL_SECONDS)
                current["poll_errors"] = 0
                current["status"] = "submission_uncertain" if result.get("uncertain") else "stream_failed" if result.get("streamError") else "thinking"
                current["status_detail"] = "Observing the original message; no prompt resend" if result.get("uncertain") else ""
            change_state(waiting)
            return
        response = result["response"]
        path = cache
        _write(path, {"conversation_id": result.get("conversation_id"), "user_message_id":pending["user_message_id"],
                      "response":response, "at_unix":now})
        protocol_error=None;directive=None;checkpoint=None
        try:
            directive = parse_loop_directive(response["text"])
            checkpoint = _checkpoint(response["text"])
            reports=_reports(response["text"],item["job_evidence"])
            if reports:_write(path.with_suffix(".diagnosis.json"),{"reports":reports,"source_message_id":response["message_id"],"at_unix":now})
        except (ValueError,TypeError):protocol_error="Completed response has invalid directive/checkpoint or unsupported diagnosis; private receipt retained"
    except Exception as exc:
        _observe_failure(profile_id, now, exc, pending=pending)
        return
    def complete(c, s):
        current = s["profiles"].get(profile_id)
        if not _same_pending(current, pending): return
        if not current["pending"].get("counted"): current["prompts_sent"] += 1
        if result.get("conversation_id"):
            current["session"] = {"conversation_id":result["conversation_id"], "project_id":pending["project_id"]}
        current.update(pending=None, response_message_id=response["message_id"],
            iterations=current["iterations"]+1, chat_iterations=current["chat_iterations"]+1,
            poll_errors=0, last_error="", last_activity_at_unix=now,
            last_success=directive.kind.value if directive else "protocol_error", loop_state=directive.kind.value.lower() if directive else "protocol_error")
        if protocol_error:
            current.update(desired="paused",status="evidence_required",last_error=protocol_error)
            event(s,profile_id,"response_protocol_error",protocol_error);return
        if checkpoint is not None: current["checkpoint"] = checkpoint
        event(s, profile_id, "response", directive.kind.value)
        if current["request"] == "restart" and current["desired"] == "run":
            current["status"] = "rotating"; return
        if directive.kind is DirectiveKind.WAIT_RESULT:
            current.update(job_id=directive.argument, next_job_poll_at_unix=now, status="waiting_result")
            return
        profile = _profile(c, profile_id)
        if directive.kind is DirectiveKind.CONNECTOR_BLOCKED:
            current.update(desired="paused", status="connector_blocked", last_error="GitHub connector needs attention")
            return
        if current["desired"] != "run" or not profile["enabled"]:
            _release(s, profile_id, now, "paused" if current["desired"] == "paused" else "idle")
            return
        decision = limit_decision(profile, current, now)
        if decision in {"stop", "pause"} or (directive.kind is DirectiveKind.DONE and
                (profile["mode"] != "continuous" or profile.get("stop_on_done", False))):
            current["desired"] = "paused" if decision == "pause" else "stopped"
            _release(s, profile_id, now, "paused" if decision == "pause" else "completed")
        elif decision == "rotate" or directive.kind is DirectiveKind.ROTATE:
            current.update(request="rotation", status="rotating")
            if decision == "rotate" and profile["mode"] == "duration": current["started_at_unix"] = now
        elif profile["mode"] == "interval":
            _release(s, profile_id, now, "scheduled")
            current.update(desired="run", request="new", next_run_at_unix=now+profile["interval_seconds"])
        else:
            current.update(request="continuation", status="continuing")
    change_state(complete)
    # Private receipts are bounded by count; checkpoint and latest IDs are durable.
    for old in sorted(path.parent.glob("*.json"), key=lambda p:p.stat().st_mtime, reverse=True)[32:]:
        old.unlink(missing_ok=True)


def job_result(job_id: str) -> dict | None:
    # Local completed receipt is usable while publication/network is recovering.
    local = state_dir() / "worker" / "receipts" / f"{job_id}.json"
    if local.exists():
        receipt = json.loads(local.read_text())
        if receipt.get("result") is not None:
            payload=receipt["result"]
            if not isinstance(payload,dict) or payload.get("job")!=job_id:raise ValueError("private job result identity mismatch")
            return payload
    with (state_dir()/"git-observe.lock").open("a+") as lock:
        try:fcntl.flock(lock, fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:return None
        from .credentials import git_options,git_env
        _,snapshot,_=read_snapshot()
        owner=next((pid for pid,item in snapshot["profiles"].items() if item.get("job_id")==job_id),None)
        remote=subprocess.run(["git","remote","get-url","origin"],cwd=ROOT,capture_output=True,text=True,timeout=5)
        options=git_options(owner,remote.stdout.strip()) if owner else []
        fetched = subprocess.run(["git",*options,"fetch","origin","dev"],cwd=ROOT,capture_output=True,text=True,timeout=30,env=git_env())
        if fetched.returncode: raise RuntimeError("Cannot fetch dev for job result; observation will retry")
        shown = subprocess.run(["git","show",f"origin/dev:{RESULTS}/{job_id}.json"],cwd=ROOT,capture_output=True,text=True,timeout=15)
    if shown.returncode: return None
    payload = json.loads(shown.stdout)
    if not isinstance(payload,dict) or payload.get("job") != job_id: raise ValueError("job result identity mismatch")
    return payload


def _wait_result(config: dict, state: dict, profile_id: str, now: int) -> None:
    item = state["profiles"][profile_id]
    if now < (item["next_job_poll_at_unix"] or 0): return
    try:
        payload = job_result(item["job_id"])
        if payload and payload.get("profile_id") not in {None, profile_id}: raise ValueError("job belongs to another profile")
        if payload:
            from automation.worker.privacy import chat_result
            summary=chat_result(payload)
    except Exception as exc:
        _observe_failure(profile_id,now,exc,job=True); return
    def ready(c,s):
        current = s["profiles"].get(profile_id)
        if not current or current["job_id"] != item["job_id"]: return
        if payload is None:
            current.update(next_job_poll_at_unix=now+10,status="waiting_result"); return
        current.update(last_job_id=current["job_id"],last_result=str(payload.get("status","unknown")),job_id=None,
                       next_job_poll_at_unix=None,job_poll_errors=0,request="continuation",status="continuing")
        ids=[a["evidence_id"] for a in summary["actions"] if a.get("evidence_id")]
        current["job_evidence"]=(current["job_evidence"]+ids)[-128:]
        current["job_summary"]=summary
        event(s,profile_id,"job_result",current["last_job_id"]+" "+current["last_result"])
    change_state(ready)


def _step(profile_id: str, now: int) -> None:
    _,state,_=read_snapshot()
    item=state["profiles"].get(profile_id,{})
    conversation=(item.get("pending") or item.get("session") or {}).get("conversation_id")
    resource=hashlib.sha256((conversation or profile_id).encode()).hexdigest()
    with (state_dir()/("conversation-"+resource+".lock")).open("a+") as lease:
        try:fcntl.flock(lease,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:return
        _step_session(profile_id,now)


def _step_session(profile_id: str, now: int) -> None:
    config,state,issues = read_snapshot()
    if profile_id not in state["profiles"] or not any(p["id"]==profile_id for p in config["profiles"]): return
    item = state["profiles"][profile_id]
    if item["remove_requested"]: return
    if item["pending"]:
        _poll(config,state,profile_id,now); return
    if item["desired"] != "run" or not _profile(config,profile_id)["enabled"]:
        if item["run_active"]:
            review={"connector_blocked","evidence_required","session_changed","session_conflict","recovery_required"}
            status=item["status"] if item["status"] in review else "paused" if item["desired"]=="paused" else "idle"
            change_state(lambda c,s:_release(s,profile_id,now,status))
        return
    if item["job_id"]:
        _wait_result(config,state,profile_id,now); return
    if now < (item["next_run_at_unix"] or 0): return
    try: _submit(config,state,profile_id,now)
    except Exception as exc: _observe_failure(profile_id,now,exc)


def tick(now: int | None = None, executor: ThreadPoolExecutor | None = None) -> None:
    now = int(time.time()) if now is None else now
    config,state,issues = read_snapshot()
    if issues:
        def quarantine(c,s):
            detail="Quarantined malformed profile configuration; valid workflows continue"
            if not s["events"] or s["events"][-1].get("detail")!=detail:event(s,None,"invalid_configuration",detail)
        change_state(quarantine)
    def prepare(c,s):
        migrate_runtime(c,s)
        _heartbeat(s,now)
        for p in c["profiles"]: _claim(c,s,now,p["id"])
    change_state(prepare)
    for pid,future in list(_INFLIGHT.items()):
        if future.done():
            try: future.result()
            except Exception as exc:
                _observe_failure(pid,now,exc)
            del _INFLIGHT[pid]
    config,state,issues = read_snapshot()
    if not issues:_handle_removals(config,state,protected=_INFLIGHT)
    config,state,_ = read_snapshot()
    due = []
    for p in config["profiles"]:
        item=state["profiles"][p["id"]]
        if p["id"] in _INFLIGHT or item["remove_requested"]: continue
        if item["pending"]:
            at=item["pending"].get("poll_after_unix",0)
        elif item["job_id"]: at=item["next_job_poll_at_unix"] or 0
        elif item["run_active"] or item["desired"]=="run": at=item["next_run_at_unix"] or 0
        else: continue
        if at<=now: due.append(p["id"])
    due.sort(key=lambda pid:state["profiles"][pid]["last_transport_at_unix"])
    chosen=due if executor is None else due[:max(0,CONCURRENCY-len(_INFLIGHT))]
    def scheduled(c,s):
        for pid in chosen:
            if pid in s["profiles"]:s["profiles"][pid]["last_transport_at_unix"]=now
    if chosen:change_state(scheduled)
    if executor is None:
        with ThreadPoolExecutor(max_workers=CONCURRENCY) as pool:
            futures=[pool.submit(_step,pid,now) for pid in due]
            for future in futures: future.result()
    else:
        for pid in chosen:
            _INFLIGHT[pid]=executor.submit(_step,pid,now)


def main() -> int:
    parser=argparse.ArgumentParser(description="Independent Hadalis workflow scheduler")
    parser.add_argument("--once",action="store_true")
    parser.add_argument("--reset-state",action="store_true")
    args=parser.parse_args()
    lock_path=state_dir()/"chat-bridge.lock";lock_path.parent.mkdir(parents=True,exist_ok=True)
    with lock_path.open("a+") as handle:
        try: fcntl.flock(handle,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError: raise SystemExit("another Hadalis scheduler is running")
        if args.reset_state:
            _,state,_=read_snapshot()
            if any(i["pending"] or i["job_id"] for i in state["profiles"].values()):
                raise SystemExit("cannot reset unresolved submissions/jobs; recovery metadata must be retained")
            state_path().unlink(missing_ok=True);return 0
        with ThreadPoolExecutor(max_workers=CONCURRENCY) as pool:
            while True:
                from automation.worker.deployment import recover
                try:recover()
                except (OSError,ValueError,KeyError):
                    # Quarantine malformed deployment recovery without stopping
                    # independent chat/job observation. Keep the journal intact.
                    change_state(lambda c,s:event(s,None,"deployment_recovery_failed","Private rollback journal needs inspection"))
                tick(executor=None if args.once else pool)
                if args.once:return 0
                time.sleep(POLL_SECONDS)


if __name__=="__main__":
    raise SystemExit(main())
