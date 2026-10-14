#!/usr/bin/env python3
"""Alis Automation task-code intake (AUTO-R01), no implicit command execution."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation import taskflow, credentials, lifecycle


def main():
    parser = argparse.ArgumentParser(description="Prepare task-code Automation handoff")
    commands = parser.add_subparsers(dest="action", required=True)
    for action in ("resolve", "prepare"):
        sub = commands.add_parser(action)
        sub.add_argument("code", help="AUTO-R01 or llocphann/Alis#104")
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
        if args.action in ("resolve", "prepare"):
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
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
