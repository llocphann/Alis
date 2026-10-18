#!/usr/bin/env python3
"""Explicit setup lifecycle for the optional package and its system helpers."""
import argparse
import datetime
import fcntl
import importlib.util
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("integration_manager", ROOT / "scripts/hadalird-manager.py")
manager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manager)
PLANS = {
    "install": ("install", "helpers-ensure"),
    "reinstall": ("install", "helpers-ensure"),
    "update": ("install", "helpers-ensure"),
    "rollback": ("rollback", "helpers-ensure"),
    "remove": ("helpers-remove", "gateway-remove", "remove"),
}


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def publish(path, doc):
    if path.is_symlink():
        raise ValueError("Preserving linked setup receipt")
    fd, temporary = tempfile.mkstemp(prefix=".receipt-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(doc, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def execute(action, shell_root, data_home, state_home, *, call=None, acknowledge=False):
    """Injected call keeps tests away from live system/package operations."""
    call = call or (lambda stage: manager.operate(stage, data_home / "hadalird", shell_root))
    state = state_home / "alis/integrations"
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    receipt_path = state / "last-operation.json"
    lock_path = state / ".setup.lock"
    if lock_path.is_symlink() or receipt_path.is_symlink():
        raise ValueError("Preserving unowned setup state")
    with lock_path.open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError("Another Integration setup operation is running") from error
        previous = json.loads(receipt_path.read_text()) if receipt_path.exists() else {}
        if not isinstance(previous, dict):
            raise ValueError("Invalid prior setup receipt; preserve it for inspection")
        if action == "status":
            package, system = call("status"), call("system-status")
            if not all(isinstance(report, dict) and report.get("ok") is True for report in (package, system)):
                raise ValueError("Could not reconcile package and system status")
            if acknowledge and previous.get("status") in ("running", "uncertain"):
                previous.update(status="acknowledged", reconciledAt=now(), reconciliation={"package": package, "system": system})
                publish(receipt_path, previous)
            return {"ok": True, "package": package, "system": system, "receipt": previous,
                    "receiptPath": str(receipt_path)}
        if action not in PLANS:
            raise ValueError("Unsupported setup action")
        if previous.get("status") in ("running", "uncertain"):
            raise ValueError("Previous operation may have changed system state. Run ./setup integrations status; inspect it before status --acknowledge-uncertain and retry")
        if previous and not re.fullmatch(r"[0-9a-f]{32}", str(previous.get("id", ""))):
            raise ValueError("Invalid prior setup receipt identity; preserve it for inspection")
        if previous:
            # Keep the last real transaction, including acknowledged uncertainty.
            publish(state / (str(previous.get("id", uuid.uuid4().hex)) + ".json"), previous)
        head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=shell_root,
                              text=True, capture_output=True, check=True).stdout.strip()
        receipt = {"schema": 1, "id": uuid.uuid4().hex, "action": action, "hostSha": head,
                   "startedAt": now(), "status": "running", "stages": []}
        publish(receipt_path, receipt)
        for stage in PLANS[action]:
            entry = {"action": stage, "startedAt": now(), "status": "running"}
            receipt["stages"].append(entry)
            publish(receipt_path, receipt)
            try:
                report = call(stage)
                if not isinstance(report, dict) or report.get("ok") is not True:
                    raise ValueError("Operation returned no successful typed receipt")
                if stage == "helpers-ensure" and report.get("systemHelpersInstalled") is not True:
                    raise ValueError("Helper installation was not verified")
                entry.update(status="passed", finishedAt=now(), result=report)
                publish(receipt_path, receipt)
            except (OSError, ValueError, TypeError, subprocess.SubprocessError) as error:
                entry.update(status="uncertain", finishedAt=now(), error=str(error))
                receipt.update(status="uncertain", finishedAt=now())
                publish(receipt_path, receipt)
                return {"ok": False, "error": str(error), "receipt": receipt, "receiptPath": str(receipt_path)}
        receipt.update(status="passed", finishedAt=now())
        publish(receipt_path, receipt)
        return {"ok": True, "receipt": receipt, "receiptPath": str(receipt_path)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("status", *PLANS))
    parser.add_argument("--confirm", action="store_true", help="Approve this explicit setup transaction; Polkit still authorizes system changes")
    parser.add_argument("--dry-run", action="store_true", help="Show the plan without network, state writes or authorization")
    parser.add_argument("--acknowledge-uncertain", action="store_true", help="With status only, acknowledge an inspected uncertain operation without replaying it")
    args = parser.parse_args()
    if args.acknowledge_uncertain and args.action != "status":
        parser.error("--acknowledge-uncertain requires status")
    if args.dry_run:
        print(json.dumps({"action": args.action, "stages": PLANS.get(args.action, ("status", "system-status")),
                          "privilegedConsent": args.action != "status", "workersEnabled": False}))
        return
    if os.geteuid() == 0:
        parser.error("Run setup as your regular user; Polkit authorizes only the audited system stages")
    if args.action != "status" and not args.confirm:
        if not sys.stdin.isatty():
            parser.error("Review --dry-run first, then use --confirm for this explicit transaction")
        print("Stages: " + " → ".join(PLANS[args.action]))
        if input("Manage optional Integration package and system helper files? [y/N] ").strip().lower() != "y":
            raise SystemExit(2)
    os.umask(0o077)
    try:
        result = execute(args.action, ROOT,
                         Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")),
                         Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")),
                         acknowledge=args.acknowledge_uncertain)
        print(json.dumps(result))
        if result.get("ok") is not True:
            raise SystemExit(1)
    except (OSError, ValueError, TypeError, subprocess.SubprocessError) as error:
        print(json.dumps({"ok": False, "error": str(error)}))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
