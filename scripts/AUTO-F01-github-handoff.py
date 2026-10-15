#!/usr/bin/env python3
"""Owner-visible, single-job GitHub handoff approval; never executes a job.

Existing worker polls origin/dev with its usual rate. No second daemon, no
secrets in GitHub, no approval through chat text, no git push from this CLI.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation import github_handoff
from automation.worker import daemon as worker


def inspect(job_id: str, *, fetch: bool = True) -> tuple[dict, dict, str]:
    if not worker.JOB_RE.fullmatch(job_id):
        raise ValueError("invalid job identity")
    if fetch:
        worker.fetch_dev()
    path = f"{worker.QUEUE}/{job_id}.json"
    if path not in worker.pending_paths():
        raise ValueError("job is not in the pinned worker queue")
    original = worker.remote_text(path, ref=worker.introducing_commit(path))
    if len(original.encode("utf-8")) > 65536:
        raise ValueError("job exceeds metadata bound")
    job = worker.validate_job(path, original)
    if not isinstance(job.get("handoff"), dict):
        raise ValueError("job is not using GitHub handoff")
    raw = worker.remote_text(github_handoff.PATH)
    signal = github_handoff.validate_signal(raw)
    github_handoff.match_job(signal, job, original)
    if signal["expires_unix"] < int(time.time()):
        raise ValueError("expired signal requires a new job ID and approval")
    return signal, job, original


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="AUTO-F01 single-file GitHub handoff")
    command = parser.add_subparsers(dest="command", required=True)
    for name in ("status", "approve"):
        p = command.add_parser(name)
        p.add_argument("job_id")
        if name == "approve":
            p.add_argument("--owner-approved", action="store_true")
            p.add_argument("--expected-sha256", required=True,
                           help="Exact pinned job digest displayed by status")
    args = parser.parse_args(argv)
    if args.command == "approve" and args.owner_approved is not True:
        raise ValueError("explicit owner approval required before any local job is eligible")
    signal, job, raw = inspect(args.job_id)
    digest = github_handoff.job_digest(raw)
    if args.command == "approve":
        # Owner must review the exact immutable job before granting execution.
        # The GitHub status file alone is not approval of executable actions.
        if args.expected_sha256 != digest:
            raise ValueError("approved job digest does not match")
    state = worker.state_root()
    approved = github_handoff.approval_matches(state, job, raw)
    if args.command == "approve" and not approved:
        receipt = github_handoff.approval_payload(job, raw)
        dest = github_handoff.approval_path(state, args.job_id)
        if dest.exists() or dest.is_symlink():
            raise ValueError("approval already exists but does not match; manual reconciliation required")
        dest.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        dest.parent.chmod(0o700)
        # Existing manager atomic writer preserves mode/ fsync, but only
        # after verifying that this new immutable identity has no old receipt.
        if worker.load_receipt(args.job_id):
            raise ValueError("job already has a worker receipt; approval refused")
        # Exclusive create avoids approval collision between concurrent local
        # operators, even if they both observed the empty approval directory.
        with dest.open("xb") as out:
            os.fchmod(out.fileno(), 0o600)
            data=json.dumps(receipt,sort_keys=True,separators=(",",":")).encode()+b"\n"
            out.write(data);out.flush();os.fsync(out.fileno())
        folder_fd=os.open(dest.parent,os.O_RDONLY)
        try:os.fsync(folder_fd)
        finally:os.close(folder_fd)
        approved=True
    print(json.dumps({
        "purpose":"auto-f01-github-handoff",
        "status":signal["status"],
        "task_code":signal["task_code"],
        "job_id":job["id"],
        "run_id":job["handoff"]["run_id"],
        "base_sha":job["base_sha"],
        "job_sha256":digest,
        "action_count":len(job["actions"]),
        "action_kinds":[next(iter(a)) for a in job["actions"]],
        "approved_for_exact_job":approved,
        "dispatch_ready":signal["status"]=="DONE" and approved,
        "server_chat_receipt_verified":False,
        "no_job_executed_by_this_command":True
    },sort_keys=True))
    return 0


if __name__=="__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (ValueError, RuntimeError, OSError, json.JSONDecodeError) as exc:
        # Local CLI stays categorical: never print job body, git stderr, or
        # potential credential/secret-containing remote API messages.
        print(json.dumps({"purpose":"auto-f01-github-handoff","status":"blocked",
                          "error_code":type(exc).__name__,
                          "job_executed":False}))
        raise SystemExit(1)
