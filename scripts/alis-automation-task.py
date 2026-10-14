#!/usr/bin/env python3
"""Alis Automation task-code intake (AUTO-R01), no implicit command execution."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation import taskflow


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
    args = parser.parse_args()
    try:
        if args.action in ("resolve", "prepare"):
            task = taskflow.resolve(args.code)
            result = {"ok": True, "task": task} if args.action == "resolve" else taskflow.intake(task)
            if args.action == "prepare":
                result["task"] = {"code": task["code"], "repository": task["repository"],
                                  "issue_number": task["issue_number"], "branch": task["branch"],
                                  "base_sha": task["base_sha"], "issue_url": task["issue_url"]}
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
    except (taskflow.TaskError, OSError, ValueError, json.JSONDecodeError) as error:
        result = {"ok": False, "error": str(error)}
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
