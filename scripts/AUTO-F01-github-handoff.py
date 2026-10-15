#!/usr/bin/env python3
"""Owner-visible, single-job GitHub handoff approval; never executes a job.

Existing worker polls origin/dev with its usual rate. No second daemon, no
secrets in GitHub, no approval through chat text, no git push from this CLI.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
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


def installed_worker_info() -> dict:
    """Categorical service/source provenance, no PID, argv, paths or secrets exposed.

    Running services can keep the *old imported code* until a controlled
    restart; updating a repository checkout is not a process upgrade.
    """
    result = {
        "worker_service_active": False,
        "worker_unit_matches_checkout": False,
        "worker_process_matches_checkout": False,
    }
    try:
        observed=subprocess.run(
            ["systemctl","--user","show","hadalis-worker.service",
             "--no-pager","--property=ActiveState,MainPID,WorkingDirectory"],
            capture_output=True,text=True,timeout=5,check=False)
        if observed.returncode or len(observed.stdout)>8192:
            return result
        values=dict(line.split("=",1) for line in observed.stdout.splitlines()
                    if "=" in line)
        result["worker_service_active"]=values.get("ActiveState")=="active"
        root=Path(__file__).resolve().parents[1]
        working=values.get("WorkingDirectory","")
        result["worker_unit_matches_checkout"]=(
            bool(working) and Path(working).resolve()==root)
        raw_pid=values.get("MainPID","")
        if not raw_pid.isascii() or not raw_pid.isdecimal():
            return result
        pid=int(raw_pid)
        if not 1<=pid<=4194304:return result
        proc=Path("/proc")/str(pid)
        expected=root/"automation"/"worker"/"daemon.py"
        cmd=(proc/"cmdline").read_bytes()[:16384].split(bytes([0]))
        proc_cwd=Path(os.readlink(proc/"cwd")).resolve()
        args=[os.fsdecode(x) for x in cmd if x]
        result["worker_process_matches_checkout"]=(
            result["worker_service_active"] and proc_cwd==root and
            any(Path(x).is_absolute() and Path(x).resolve()==expected
                for x in args))
    except (OSError,ValueError,subprocess.TimeoutExpired):
        return result
    return result


def pending_receipt_health() -> dict:
    """Fail-closed receipt inventory, not a mutation or content export.

    A worker can have unpublished/uncertain durable receipts even when the
    heartbeat reports no running future and no active publisher. Do not
    restart until those have been reconciled.
    """
    root=worker.state_root() / "receipts"
    problem={"worker_receipt_inventory_complete":False,
             "worker_unsettled_receipts_present":None,
             "worker_receipt_count_capped":None}
    if root.is_symlink():return problem
    if not root.exists():
        # A worker with no jobs may never have created receipts/.
        return {"worker_receipt_inventory_complete":True,
                "worker_unsettled_receipts_present":False,
                "worker_receipt_count_capped":0}
    if not root.is_dir():return problem
    total=0
    unsettled=False
    try:
        for item in root.iterdir():
            total+=1
            if total>4096:return problem
            if (not item.name.endswith(".json") or item.is_symlink()
                    or not item.is_file() or item.stat().st_size>65536):
                return problem
            receipt=json.loads(item.read_text(encoding="utf-8"))
            if not isinstance(receipt,dict) or receipt.get("phase") not in (
                "published","preparing","executing","finished","publishing"):
                return problem
            if receipt["phase"]!="published":unsettled=True
    except (OSError,ValueError):
        return problem
    return {"worker_receipt_inventory_complete":True,
            "worker_unsettled_receipts_present":unsettled,
            "worker_receipt_count_capped":min(total,4096)}


def running_worker_status(*, now: int | None = None) -> dict:
    """Read-only heartbeat and installed unit/proc provenance; no GitHub IO."""
    at = int(time.time()) if now is None else now
    path = worker.state_root() / "pool.json"
    try:
        if path.is_symlink() or path.stat().st_size > 8192:
            raise ValueError("worker heartbeat unavailable")
        snapshot = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        snapshot = {}
    observed = snapshot.get("heartbeat_at_unix") if isinstance(snapshot,dict) else None
    fresh = (type(observed) is int and 0 <= at-observed <= 30)
    contract = (isinstance(snapshot,dict) and
                snapshot.get("github_handoff_contract") == github_handoff.SCHEMA)
    installed=installed_worker_info()
    if not fresh:
        diagnosis="WORKER_HEARTBEAT_MISSING_OR_STALE"
    elif contract and installed["worker_process_matches_checkout"] and installed["worker_unit_matches_checkout"]:
        diagnosis="RUNNING_WORKER_HANDOFF_CONTRACT_OBSERVED"
    elif contract:
        diagnosis="WORKER_HANDOFF_MARKER_SOURCE_UNVERIFIED"
    elif installed["worker_process_matches_checkout"]:
        diagnosis="RUNNING_WORKER_OLDER_CODE_MAY_REQUIRE_CONTROLLED_RESTART"
    elif installed["worker_unit_matches_checkout"]:
        diagnosis="WORKER_PROCESS_VERSION_UNVERIFIED"
    else:
        diagnosis="INSTALLED_WORKER_SOURCE_MISMATCH_OR_UNVERIFIED"
    active_tasks=(snapshot.get("running") if isinstance(snapshot,dict) else None)
    publishing=(snapshot.get("publishing") if isinstance(snapshot,dict) else None)
    receipt_health=pending_receipt_health()
    restart_preflight_ok=(
        fresh and installed["worker_service_active"] and
        installed["worker_unit_matches_checkout"] and
        installed["worker_process_matches_checkout"] and
        active_tasks==[] and publishing is False and
        receipt_health["worker_receipt_inventory_complete"] is True and
        receipt_health["worker_unsettled_receipts_present"] is False
    )
    return {
        "purpose": "auto-f01-github-handoff-doctor",
        "status": "read-only",
        "diagnosis":diagnosis,
        **installed,
        **receipt_health,
        "worker_restart_preflight_clear":restart_preflight_ok,
        "worker_heartbeat_fresh": fresh,
        "worker_supports_github_handoff": bool(fresh and contract and
                                               installed["worker_process_matches_checkout"] and
                                               installed["worker_unit_matches_checkout"]),
        "worker_has_active_work_observed": (
            bool(active_tasks) or publishing is True
            if isinstance(active_tasks,list) and isinstance(publishing,bool)
            else None),
        "worker_restart_authorized":False,
        "no_services_modified":True,
        "managed_chat_transport_ready": False,
        "scheduler_submission_authorized": False
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="AUTO-F01 single-file GitHub handoff")
    command = parser.add_subparsers(dest="command", required=True)
    command.add_parser("doctor",help="Read running worker capability without GitHub mutations")
    for name in ("status", "approve"):
        p = command.add_parser(name)
        p.add_argument("job_id")
        if name == "approve":
            p.add_argument("--owner-approved", action="store_true")
            p.add_argument("--expected-sha256", required=True,
                           help="Exact pinned job digest displayed by status")
    args = parser.parse_args(argv)
    if args.command == "doctor":
        print(json.dumps(running_worker_status(), sort_keys=True))
        return 0
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
