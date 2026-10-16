#!/usr/bin/env python3
"""Alis Automation task-code intake (AUTO-R01), no implicit command execution."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
try:
    from automation import taskflow, credentials, lifecycle, queue, activity, managed_tasks, transport_gate
    from automation.manager import control as manager_control
except Exception as error:
    # Imports happen before argparse and the normal JSON reply contract.
    # Report a safe typed failure rather than an empty stdout and traceback.
    print(json.dumps({"ok": False,
                      "error": "Automation runtime import failed (" +
                               type(error).__name__ +
                               "); update the installed Alis Python modules"}), flush=True)
    raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser(description="Prepare task-code Automation handoff")
    commands = parser.add_subparsers(dest="action", required=True)
    for action in ("resolve", "prepare"):
        sub = commands.add_parser(action)
        sub.add_argument("code", help="AUTO-R01 or llocphann/Alis#104")
    batch = commands.add_parser("queue-prepare")
    batch.add_argument("codes", nargs="?", default="",
                       help="Optional codes; blank discovers Backend-first GitHub Issues")
    batch.add_argument("--mode", choices=["ordered", "cloud"], default="ordered")
    commands.add_parser("queue-status")
    legacy_stop = commands.add_parser("queue-stop-idle-legacy")
    legacy_stop.add_argument("--approve", action="store_true")
    legacy_stop.add_argument("--expected-snapshot-id", required=True)
    bridge_recover = commands.add_parser("queue-recover-bridge")
    bridge_recover.add_argument("--approve", action="store_true")
    bridge_recover.add_argument("--expected-snapshot-id", required=True)
    recheck = commands.add_parser("queue-recheck")
    recheck.add_argument("--expected-snapshot-id", required=True,
                         help="Version of the exact fully parked queue displayed in Settings")
    reset_chat = commands.add_parser("queue-reset-chat")
    reset_chat.add_argument("--approve", action="store_true",
                            help="Request a fresh Project chat for the exact active task; no direct Send")
    reset_chat.add_argument("--expected-active", required=True)
    stage_queue = commands.add_parser("queue-stage-ui")
    stage_queue.add_argument("--approve", action="store_true",
                             help="Stage first task's profile only; no Send, Start or unit change")
    stage_queue.add_argument("--expected-first", required=True)
    stage_queue.add_argument("--expected-snapshot-id",
                             help="Exact reviewed queue generation before profile staging")
    stop_queue = commands.add_parser("queue-stop")
    stop_queue.add_argument("--approve", action="store_true")
    stop_queue.add_argument("--expected-active", required=True)
    stop_queue.add_argument("--expected-snapshot-id",
                            help="Opaque queue generation previously confirmed by owner")
    clear_queue = commands.add_parser("queue-clear")
    clear_queue.add_argument("--approve", action="store_true",
                             help="Owner confirms pruning queued tasks without stopping active work")
    clear_queue.add_argument("--expected-queued", required=True,
                             help="Exact repo:code list shown when owner confirmed")
    clear_queue.add_argument("--expected-snapshot-id",
                             help="Opaque durable queue version from queue-status; reject stale UI Clear")
    commands.add_parser("sudo-status")
    commands.add_parser("sudo-authenticate")
    commands.add_parser("sudo-credential-status")
    commands.add_parser("sudo-credential-save")
    commands.add_parser("sudo-credential-clear")
    commands.add_parser("backend-status")
    start_queue = commands.add_parser("start-queue")
    start_queue.add_argument("--approve", action="store_true")
    ui_start = commands.add_parser("start-ui-queue")
    ui_start.add_argument("--approve", action="store_true")
    ui_start.add_argument("--accept-ui-only-receipts", action="store_true")
    ui_start.add_argument("--expected-first", required=True)
    ui_start.add_argument("--expected-snapshot-id",
                          help="Exact reviewed queue snapshot; reject stale UI Start")
    history = commands.add_parser("activity")
    history.add_argument("code")
    history.add_argument("--repo", choices=taskflow.REPOSITORIES,
                         default="llocphann/Alis")
    verify = commands.add_parser("verify")
    verify.add_argument("bundle", type=Path)
    execute = commands.add_parser("execute")
    execute.add_argument("bundle", type=Path)
    execute.add_argument("checkout", type=Path)
    execute.add_argument("--approve-local-tests", action="store_true")
    promote = commands.add_parser("continuation")
    promote.add_argument("bundle", type=Path)
    promote.add_argument("receipt", type=Path)
    store = commands.add_parser("save-handoff")
    store.add_argument("code")
    store.add_argument("--repo", default="llocphann/Alis", choices=taskflow.REPOSITORIES)
    run = commands.add_parser("run-task")
    run.add_argument("code")
    run.add_argument("checkout", type=Path)
    run.add_argument("--repo", default="llocphann/Alis", choices=taskflow.REPOSITORIES)
    run.add_argument("--approve-local-tests", action="store_true")
    accept = commands.add_parser("owner-verify")
    accept.add_argument("code")
    accept.add_argument("--repo", default="llocphann/Alis", choices=taskflow.REPOSITORIES)
    accept.add_argument("--approve", action="store_true")
    check = commands.add_parser("status")
    check.add_argument("code")
    check.add_argument("--repo", default="llocphann/Alis", choices=taskflow.REPOSITORIES)
    for action in ("github-token-status", "github-token-save", "github-token-clear"):
        token_cmd = commands.add_parser(action)
        token_cmd.add_argument("repository", choices=taskflow.REPOSITORIES)
    helper = commands.add_parser("git-credential")
    helper.add_argument("repository", choices=taskflow.REPOSITORIES)
    helper.add_argument("operation")
    gc = commands.add_parser("cleanup")
    gc.add_argument("--apply", action="store_true", help="Purge only terminal delivery-acknowledged payloads")
    args = parser.parse_args()
    if args.action == "git-credential":
        # Git expects the raw credential protocol; never wrap it in JSON.
        print(credentials.git_helper(args.repository, args.operation, sys.stdin.read(8193)), end="")
        return 0
    try:
        if args.action == "queue-prepare":
            result = (queue.prepare(args.codes, mode=args.mode)
                      if args.codes.strip() else queue.prepare_auto(mode=args.mode))
        elif args.action == "queue-status":
            result = queue.view()
        elif args.action == "queue-recheck":
            result = queue.recheck_review_queue(
                expected_snapshot_id=args.expected_snapshot_id)
        elif args.action == "queue-stop-idle-legacy":
            result = managed_tasks.stop_idle_legacy_default_for_ui_queue(
                approved=args.approve,
                expected_snapshot_id=args.expected_snapshot_id)
        elif args.action == "queue-recover-bridge":
            result = managed_tasks.recover_failed_ui_bridge(
                approved=args.approve,
                expected_snapshot_id=args.expected_snapshot_id)
        elif args.action == "queue-stage-ui":
            result = managed_tasks.stage_ui_queue(
                approved=args.approve, expected_first=args.expected_first,
                expected_snapshot_id=args.expected_snapshot_id)
        elif args.action == "queue-reset-chat":
            result = managed_tasks.request_ui_chat_reset(
                approved=args.approve, expected_active=args.expected_active)
        elif args.action == "queue-stop":
            result = managed_tasks.stop_queue(
                approved=args.approve, expected_active=args.expected_active,
                expected_snapshot_id=args.expected_snapshot_id)
        elif args.action == "queue-clear":
            result = queue.clear(approved=args.approve,
                                 expected_queued=args.expected_queued,
                                 expected_snapshot_id=args.expected_snapshot_id)
        elif args.action == "sudo-credential-status":
            from automation import sudo_credentials
            result = sudo_credentials.status()
        elif args.action == "sudo-credential-save":
            from automation import sudo_credentials
            result = sudo_credentials.save(sys.stdin.read(1026))
        elif args.action == "sudo-credential-clear":
            from automation import sudo_credentials
            result = sudo_credentials.clear()
        elif args.action == "sudo-status":
            from automation.worker import privilege
            result = privilege.auth_status()
        elif args.action == "sudo-authenticate":
            from automation.worker import privilege
            # Secret remains in this one-shot helper's stdin and the broker's
            # memory. Never write it to a config file, issue or activity log.
            result = privilege.authenticate(sys.stdin.read(1026))
        elif args.action == "backend-status":
            from automation.chat_bridge.ui_preflight import check_prepared_queue
            states = manager_control.service_states()
            ui_check = check_prepared_queue()
            blockers = set(ui_check.get("preflight_blockers", []))
            service = (ui_check.get("service_state"),
                       ui_check.get("installed_service_mode"))
            ready_conditions = (
                ui_check.get("queue_state") == "prepared"
                and isinstance(ui_check.get("first_task_code"), str)
                and bool(ui_check.get("first_task_code"))
                and states["worker"]["state"] == "active"
            )
            ui_stage_ready = (
                ready_conditions
                and ui_check.get("taskflow_profile_present") is False
                and ((
                    service == ("active", "ui_queue_mode")
                    and blockers == {
                        "TASKFLOW_PROFILE_NOT_MATERIALIZED",
                        "SCHEDULER_CUTOVER_NOT_READY",
                        "UI_QUEUE_OWNER_ACCEPTANCE_REQUIRED",
                    }
                ) or (
                    service[0] == "inactive"
                    and service[1] in {"native_mode", "ui_mode", "ui_queue_mode"}
                    and blockers == {
                        "TASKFLOW_PROFILE_NOT_MATERIALIZED",
                        "UI_TASK_QUEUE_INTEGRATION_NOT_ACCEPTED",
                    }
                ))
            )
            ui_start_ready = (
                ready_conditions
                and states["bridge"]["state"] == "active"
                and ui_check.get("taskflow_profile_present") is True
                and service == ("active", "ui_queue_mode")
                and blockers == {
                    "SCHEDULER_CUTOVER_NOT_READY",
                    "UI_QUEUE_OWNER_ACCEPTANCE_REQUIRED",
                }
            )
            with queue._lock():
                manifest = queue._load()
                inactive_prepared_queue = bool(
                    manifest and manifest.get("mode") == "ordered"
                    and manifest.get("state") == "prepared"
                    and manifest.get("approved_start") is False
                    and manifest.get("active") is None
                    and manifest.get("selection") is None
                    and not manifest.get("stop_requested")
                    and any(item.get("state") == "queued"
                            for item in manifest.get("items", [])))
            bridge = states["bridge"]
            # Read-only diagnostic; never grants UI Send, receipt acceptance or
            # queue Start. Preserve the original private files in place.
            from automation.chat_bridge.ui_recovery_preview import preview as recovery_preview
            from automation.manager import store as manager_store
            config, runtime_state, config_issues = manager_store.read_snapshot()
            recovery_status = recovery_preview(
                manifest, config if not config_issues else {},
                runtime_state if not config_issues else {},
                manager_store.state_dir() / "ui-send-journal" / "pending.json")
            recover_bridge_ready = (
                inactive_prepared_queue
                and bridge.get("state") in {"blocked", "failed"}
                and bridge.get("exec_main_status") == "75"
                and bridge.get("unit") == manager_control.UNITS["bridge"]
                and service == ("failed", "ui_queue_mode")
            )
            result = {"ok": True, "services": {
                kind: {"state": record.get("state", "unavailable"),
                       "unit": record.get("unit", ""),
                       "result": record.get("result", ""),
                       "exit_status": record.get("exec_main_status", "")}
                for kind, record in states.items()
            }, "installed": all(states[name]["state"] != "unavailable"
                               for name in ("bridge", "worker")),
            "ui_queue_bridge_recover_available": recover_bridge_ready,
            "ui_queue_pending_recovery_preview": recovery_status,
            "ui_queue_start_available": ui_start_ready,
            "ui_queue_stage_available": ui_stage_ready,
            "ui_queue_idle_legacy_stop_available": bool(
                ui_check.get("idle_default_stop_available")),
            "ui_queue_first_task": (
                ui_check.get("first_task_code")
                if ui_start_ready or ui_stage_ready else None),
            # Bounded enums only. Explain why Start is disabled without
            # exposing saved ChatGPT IDs, prompt text or private receipts.
            "ui_queue_state": ui_check.get("queue_state"),
            "ui_queue_service_mode": ui_check.get("installed_service_mode"),
            "ui_queue_service_state": ui_check.get("service_state"),
            "ui_queue_preflight_blockers": ui_check.get("preflight_blockers", []),
            "ui_queue_profile_counts": {
                "running": ui_check.get("foreign_running_count", 0),
                "pending": ui_check.get("foreign_pending_count", 0),
                "jobs": ui_check.get("foreign_job_count", 0),
                "native_unsettled": ui_check.get("native_unsettled_count", 0),
                "historical_sessions": ui_check.get("historical_native_session_count", 0),
            },
            "ui_queue_unsettled_profiles": ui_check.get(
                "foreign_unsettled_summary", []),
            "ui_queue_legacy_native_pending_retained": bool(
                ui_check.get("legacy_native_pending_retained")),
            **transport_gate.readiness()}
        elif args.action == "start-queue":
            mode = queue.view()["mode"]
            result = (managed_tasks.start_cloud_queue(approved=args.approve)
                      if mode == "cloud"
                      else managed_tasks.start_ordered_queue(approved=args.approve))
        elif args.action == "start-ui-queue":
            result = managed_tasks.start_ui_queue(
                approved=args.approve,
                accept_ui_only_receipts=args.accept_ui_only_receipts,
                expected_first=args.expected_first,
                expected_snapshot_id=args.expected_snapshot_id)
        elif args.action == "activity":
            result = activity.read(args.code, args.repo)
        elif args.action in ("resolve", "prepare"):
            task = taskflow.resolve(args.code)
            result = {"ok": True, "task": task} if args.action == "resolve" else taskflow.intake(task)
            if args.action == "prepare":
                result["task"] = {"code": task["code"], "repository": task["repository"],
                                  "issue_number": task["issue_number"], "branch": task["branch"],
                                  "base_sha": task["base_sha"], "issue_url": task["issue_url"]}
        elif args.action == "github-token-status":
            result = credentials.status(args.repository)
        elif args.action == "github-token-save":
            # QML passes the secret through stdin, never argv or XDG files.
            result = credentials.save(args.repository, sys.stdin.read(513))
        elif args.action == "github-token-clear":
            result = credentials.clear(args.repository)
        elif args.action == "cleanup":
            result = taskflow.cleanup(dry_run=not args.apply)
        elif args.action == "status":
            result = lifecycle.status(args.code, args.repo)
        elif args.action == "owner-verify":
            result = lifecycle.owner_verified(args.code, repository=args.repo,
                                               approval=args.approve)
        elif args.action == "save-handoff":
            bundle = json.load(sys.stdin)
            result = taskflow.save_handoff(args.code, bundle, args.repo)
        elif args.action == "run-task":
            receipt = taskflow.run_task(args.code, args.checkout, args.repo,
                                        approved=args.approve_local_tests)
            result = {"ok": True, "receipt": receipt}
        else:
            with args.bundle.open(encoding="utf-8") as stream:
                bundle = json.load(stream)
            if args.action == "verify":
                checked = taskflow.verify(bundle)
                result = {"ok": True, "id": checked["id"], "sha256": checked["sha256"]}
            elif args.action == "execute":
                receipt = taskflow.run_local(bundle, args.checkout, approved=args.approve_local_tests)
                result = {"ok": True, "receipt": receipt}
            else:
                with args.receipt.open(encoding="utf-8") as stream:
                    receipt = json.load(stream)
                result = {"ok": True, "next_prompt": taskflow.continuation(bundle, receipt)}
    except (taskflow.TaskError, credentials.CredentialError, OSError, ValueError, json.JSONDecodeError) as error:
        result = {"ok": False, "error": str(error)}
    except Exception as error:
        # Unexpected parser/runtime bugs must still produce exactly one JSON
        # failure. Never emit exception messages: they may contain private
        # Issue bodies, user paths, credentials or other untrusted data.
        result = {"ok": False, "error": "Automation helper internal error during " +
                  args.action + " (" + type(error).__name__ +
                  "); refresh queue status before any retry"}
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
