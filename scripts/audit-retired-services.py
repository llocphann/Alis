#!/usr/bin/env python3
"""Read-only local evidence for retiring the old Alis Automation user services.

No service calls that mutate state, no keyring access, and no job dispatch.
Output includes unit identity and aggregate statuses, never receipt bodies.
"""

from __future__ import annotations

from collections import Counter
import json
import os
from pathlib import Path
import subprocess

UNITS = (
    "hadalis-worker.service",
    "hadalis-chat-bridge.service",
    "hadalis-privilege.service",
    "hadalis-chatgpt.service",
)
AUTOMATION_PROCESSES = (
    "automation/worker/daemon.py",
    "automation.manager.daemon",
    "automation.worker.privilege",
    "automation.chat_bridge.desktop_host",
)
MAX_JSON_BYTES = 8 * 1024 * 1024


def read_json(path: Path, blockers: list[str]) -> dict | None:
    if not path.exists():
        return None
    try:
        if not path.is_file() or path.stat().st_size > MAX_JSON_BYTES:
            raise ValueError("unsupported file")
        value = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(value, dict):
            raise ValueError("expected object")
        return value
    except (OSError, ValueError, UnicodeDecodeError):
        blockers.append(f"Unreadable/invalid state: {path.name}")
        return None


def unit_snapshot(unit: str, blockers: list[str]) -> dict:
    try:
        result = subprocess.run(
            ["systemctl", "--user", "show", unit, "--no-pager",
             "--property=LoadState,ActiveState,UnitFileState,MainPID,FragmentPath"],
            capture_output=True, text=True, timeout=8, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        blockers.append("User systemd unavailable")
        return {"unit": unit, "error": "systemd-unavailable"}
    if result.returncode:
        blockers.append(f"Could not inspect {unit}")
        return {"unit": unit, "error": "inspection-failed"}
    record = dict(line.split("=", 1) for line in result.stdout.splitlines()
                  if "=" in line)
    if not record.get("LoadState"):
        blockers.append(f"Missing unit status: {unit}")
    return {
        "unit": unit,
        "loaded": record.get("LoadState", "unknown"),
        "active": record.get("ActiveState", "unknown"),
        "enabled": record.get("UnitFileState", "unknown"),
        "main_pid": record.get("MainPID", ""),
        "fragment_path": record.get("FragmentPath", ""),
    }


def process_snapshot(blockers: list[str]) -> list[dict]:
    proc = Path("/proc")
    if not proc.is_dir():
        blockers.append("Cannot inspect /proc for unmanaged Automation processes")
        return []
    found = []
    try:
        for path in proc.iterdir():
            if not path.name.isdigit():
                continue
            try:
                argv = (path / "cmdline").read_bytes().replace(b"\0", b" ").decode(
                    "utf-8", errors="replace"
                )
            except (OSError, PermissionError):
                continue
            matched = next((name for name in AUTOMATION_PROCESSES if name in argv), None)
            if matched:
                found.append({"pid": int(path.name), "component": matched})
    except OSError:
        blockers.append("Cannot fully inspect /proc")
    return found


def worker_snapshot(state: Path, blockers: list[str]) -> dict:
    worker = state / "worker"
    pool_path = worker / "pool.json"
    pool = read_json(pool_path, blockers)
    receipts_dir = worker / "receipts"
    phases = Counter()
    if receipts_dir.exists():
        try:
            for file in sorted(receipts_dir.glob("*.json")):
                receipt = read_json(file, blockers)
                if receipt is None:
                    continue
                phase = receipt.get("phase", "unknown")
                phases[str(phase)] += 1
                if phase != "published":
                    blockers.append(f"Unsettled worker receipt: {file.name}")
        except OSError:
            blockers.append("Cannot enumerate worker receipts")
    if pool:
        if pool.get("running"):
            blockers.append("Worker still reports running jobs")
        if pool.get("publishing"):
            blockers.append("Worker still reports active publication")
    return {
        "pool_file_present": pool_path.exists(),
        "running_jobs": len(pool.get("running") or []) if pool else None,
        "publishing": bool(pool.get("publishing")) if pool else None,
        "receipt_phases": dict(phases),
        "receipt_count": sum(phases.values()),
    }


def manager_snapshot(state: Path, blockers: list[str]) -> dict:
    file = state / "manager.json"
    manager = read_json(file, blockers)
    profiles = manager.get("profiles") if manager else None
    if profiles is not None and not isinstance(profiles, dict):
        blockers.append("Unknown manager profile structure")
        profiles = None
    active = []
    if isinstance(profiles, dict):
        for key, profile in profiles.items():
            if not isinstance(profile, dict):
                blockers.append("Unknown manager profile record")
                continue
            if profile.get("pending") or profile.get("request") or (
                profile.get("desired", "stopped") != "stopped"
            ):
                active.append(str(key))
                blockers.append("Manager profile still active/pending")
    if (state / "transaction.json").exists():
        blockers.append("Unreconciled manager transaction journal exists")
    return {
        "manager_file_present": file.exists(),
        "profile_count": len(profiles) if isinstance(profiles, dict) else None,
        "active_or_pending_profile_count": len(active),
        "transaction_journal_present": (state / "transaction.json").exists(),
    }


def desktop_launcher_snapshot(blockers: list[str]) -> dict:
    data_home = Path(os.environ.get(
        "XDG_DATA_HOME", str(Path.home() / ".local/share")
    ))
    local = data_home / "applications" / "chatgpt.desktop"
    upstream = [Path(root) / "applications" / "chatgpt.desktop"
                for root in os.environ.get(
                    "XDG_DATA_DIRS", "/usr/local/share:/usr/share"
                ).split(":") if root]
    marker = False
    if local.exists():
        try:
            # Never print contents or overwrite this potentially customized file.
            if local.stat().st_size > 1024 * 1024:
                raise ValueError("unexpected Desktop entry size")
            lines = local.read_text(encoding="utf-8").splitlines()
            marker = any(
                line.startswith("Exec=")
                and "--remote-debugging-address=127.0.0.1" in line
                and "--remote-debugging-port=9222" in line
                for line in lines
            )
        except (OSError, ValueError, UnicodeDecodeError):
            blockers.append("Cannot safely inspect the user ChatGPT Desktop entry")
    if marker:
        blockers.append(
            "Possible Automation-generated ChatGPT desktop override: review"
            " the original launcher and user customizations before restoring"
        )
    return {
        "user_local_override_present": local.exists(),
        "suspected_automation_generated_exec": marker,
        "system_desktop_entry_present": any(p.is_file() for p in upstream),
        "restore_requires_separate_owner_review": True,
    }


def main() -> int:
    blockers: list[str] = []
    state = Path(os.environ.get(
        "XDG_STATE_HOME", str(Path.home() / ".local/state")
    )) / "hadalis-automation"
    config = Path(os.environ.get(
        "XDG_CONFIG_HOME", str(Path.home() / ".config")
    )) / "hadalis" / "automation.json"
    units = [unit_snapshot(unit, blockers) for unit in UNITS]
    active_units = [u["unit"] for u in units[:3] if u.get("active") == "active"]
    processes = process_snapshot(blockers)
    worker = worker_snapshot(state, blockers)
    manager = manager_snapshot(state, blockers)
    desktop_launcher = desktop_launcher_snapshot(blockers)
    if active_units:
        blockers.append("Automation-owned services still running; require independent idle review")
    if processes:
        blockers.append("Automation-related processes exist; establish ownership before stopping")
    if state.exists() and worker["pool_file_present"] is False and active_units:
        blockers.append("Worker pool status unavailable while service may be running")
    if state.exists() and manager["manager_file_present"] is False and active_units:
        blockers.append("Manager status unavailable while service may be running")
    output = {
        "read_only": True,
        "safe_to_delete_state": False,
        "candidate_for_owner_supervised_stop": not blockers,
        "systemd_units": units,
        "automation_processes": processes,
        "worker": worker,
        "manager": manager,
        "chatgpt_desktop_launcher": desktop_launcher,
        "historical_config_present": config.exists(),
        "historical_state_present": state.exists(),
        "blockers": sorted(set(blockers)),
        "note": (
            "This is local evidence only. Review GitHub queue/receipt and "
            "Desktop launcher ownership separately; never auto-delete secrets or state."
        ),
    }
    print(json.dumps(output, indent=2, ensure_ascii=False))
    return 0 if not blockers else 2


if __name__ == "__main__":
    raise SystemExit(main())
