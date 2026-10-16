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
    reset_chat = commands.add_parser("queue-reset-chat")
    reset_chat.add_argument("--approve", action="store_true",
                            help="Request a fresh Project chat for the exact active task; no direct Send")
    reset_chat.add_argument("--expected-active", required=True)
    stage_queue = commands.add_parser("queue-stage-ui")
    stage_queue.add_argument("--approve", action="store_true",
                             help="Stage first task's profile only; no Send, Start or unit change")
    stage_queue.add_argument("--expected-first", required=True)
    stop_queue = commands.add_parser("queue-stop")
    stop_queue.add_argument("--approve", action="store_true")
    stop_queue.add_argument("--expected-active", required=True)
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
        elif args.action == "queue-stage-ui":
            result = managed_tasks.stage_ui_queue(
                approved=args.approve, expected_first=args.expected_first)
        elif args.action == "queue-reset-chat":
            result = managed_tasks.request_ui_chat_reset(
                approved=args.approve, expected_active=args.expected_active)
        elif args.action == "queue-stop":
            result = managed_tasks.stop_queue(
                approved=args.approve, expected_active=args.expected_active)
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
            ui_start_ready = (
                states["bridge"]["state"] == "active"
                and states["worker"]["state"] == "active"
                and ui_check.get("queue_state") == "prepared"
                and ui_check.get("taskflow_profile_present") is True
                and ui_check.get("installed_service_mode") == "ui_queue_mode"
                and ui_check.get("service_state") == "active"
                and set(ui_check.get("preflight_blockers", [])) == {
                    "SCHEDULER_CUTOVER_NOT_READY",
                    "UI_QUEUE_OWNER_ACCEPTANCE_REQUIRED",
                }
            )
            result = {"ok": True, "services": {
                kind: {"state": service.get("state", "unavailable"),
                       "unit": service.get("unit", "")}
                for kind, service in states.items()
            }, "installed": all(states[name]["state"] != "unavailable"
                               for name in ("bridge", "worker")),
            "ui_queue_start_available": ui_start_ready,
            "ui_queue_first_task": (
                ui_check.get("first_task_code") if ui_start_ready else None),
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
                expected_first=args.expected_first)
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
