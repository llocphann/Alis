#!/usr/bin/env python3
"""Owner-visible, single-job GitHub handoff approval; never executes a job.

Existing worker polls origin/dev with its usual rate. No second daemon, no
secrets in GitHub, no approval through chat text, no git push from this CLI.
"""
from __future__ import annotations

import argparse
import json
import os
import stat
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


# Receipt payloads may legitimately embed bounded command outcomes. The old
# 64 KiB ceiling covered metadata only and falsely blocked large real receipts.
# Limit both *individual* reads and aggregate doctor memory/IO; worker's
# historical evidence budget is 256 MiB, but doctor is deliberately smaller.
MAX_RECEIPT_INSPECT_BYTES=16*1024*1024
MAX_RECEIPT_TOTAL_BYTES=64*1024*1024


def pending_receipt_health() -> dict:
    """Bounded, read-only receipt phase inventory, without IDs or contents.

    An unreadable/legacy entry is diagnosed categorically and remains
    untouched. Do not infer a safe restart from partial inventory evidence.
    """
    root=worker.state_root() / "receipts"
    known={"published","preparing","executing","finished","publishing"}

    def blocked(reason: str) -> dict:
        return {
            "worker_receipt_inventory_complete":False,
            "worker_receipt_inventory_blocker":reason,
            "worker_unsettled_receipts_present":None,
            "worker_receipt_count_capped":None,
            "worker_receipt_phase_counts":None,
        }

    if root.is_symlink():return blocked("UNSAFE_RECEIPT_DIRECTORY_SYMLINK")
    if not root.exists():
        return {
            "worker_receipt_inventory_complete":True,
            "worker_receipt_inventory_blocker":None,
            "worker_unsettled_receipts_present":False,
            "worker_receipt_count_capped":0,
            "worker_receipt_phase_counts":{k:0 for k in sorted(known)},
        }
    if not root.is_dir():return blocked("RECEIPT_DIRECTORY_NOT_DIRECTORY")
    counts={k:0 for k in sorted(known)}
    total=0
    scanned_bytes=0
    try:
        for item in root.iterdir():
            total+=1
            if total>4096:return blocked("RECEIPT_DIRECTORY_LIMIT_EXCEEDED")
            if item.is_symlink():return blocked("RECEIPT_ENTRY_SYMLINK")
            if not item.is_file():return blocked("RECEIPT_ENTRY_NOT_REGULAR_FILE")
            if not item.name.endswith(".json"):
                return blocked("RECEIPT_ENTRY_UNEXPECTED_FILENAME")
            # Do not follow a swapped symlink. Never log or export content.
            flags=os.O_RDONLY | getattr(os,"O_CLOEXEC",0) | getattr(os,"O_NOFOLLOW",0)
            descriptor=os.open(item,flags)
            try:
                info=os.fstat(descriptor)
                if not stat.S_ISREG(info.st_mode):
                    return blocked("RECEIPT_ENTRY_NOT_REGULAR_FILE")
                if info.st_size>MAX_RECEIPT_INSPECT_BYTES:
                    return blocked("RECEIPT_ENTRY_SIZE_LIMIT_EXCEEDED")
                if scanned_bytes+info.st_size>MAX_RECEIPT_TOTAL_BYTES:
                    return blocked("RECEIPT_INVENTORY_TOTAL_SIZE_LIMIT_EXCEEDED")
                with os.fdopen(descriptor,"rb",closefd=False) as stream:
                    raw=stream.read(MAX_RECEIPT_INSPECT_BYTES+1)
                after=os.fstat(descriptor)
                if len(raw)>MAX_RECEIPT_INSPECT_BYTES:
                    return blocked("RECEIPT_ENTRY_SIZE_LIMIT_EXCEEDED")
                if (after.st_size!=info.st_size or len(raw)!=info.st_size
                        or after.st_mtime_ns!=info.st_mtime_ns):
                    return blocked("RECEIPT_ENTRY_CHANGED_DURING_SCAN")
                scanned_bytes+=len(raw)
            finally:
                os.close(descriptor)
            try:
                receipt=json.loads(raw)
            except (ValueError,UnicodeError):
                return blocked("RECEIPT_ENTRY_INVALID_JSON")
            if not isinstance(receipt,dict):
                return blocked("RECEIPT_ENTRY_NOT_OBJECT")
            phase=receipt.get("phase")
            if not isinstance(phase,str) or phase not in known:
                return blocked("RECEIPT_ENTRY_UNKNOWN_OR_LEGACY_PHASE")
            counts[phase]+=1
    except OSError:
        return blocked("RECEIPT_DIRECTORY_OR_ENTRY_IO_ERROR")
    return {
        "worker_receipt_inventory_complete":True,
        "worker_receipt_inventory_blocker":None,
        "worker_unsettled_receipts_present":total!=counts["published"],
        "worker_receipt_count_capped":total,
        "worker_receipt_phase_counts":counts,
    }


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
