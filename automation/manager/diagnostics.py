"""On-demand, bounded diagnostics for Hadalis Automation.

Never include profile prompts or the complete automation configuration. Systemd
journal excerpts may still contain sensitive local data; exports are explicit,
owned by the current user and mode 0600.
"""
from __future__ import annotations

from datetime import datetime
import os
from pathlib import Path
import subprocess
import tempfile
import time

from . import control
from .store import read_snapshot

JOURNAL_LINES = 120
JOURNAL_CHARS = 60000
ERROR_LIMIT = 6000


def _date(value: object) -> str:
    if type(value) is not int or value <= 0:
        return "never"
    try:
        return datetime.fromtimestamp(value).astimezone().isoformat(timespec="seconds")
    except (ValueError, OverflowError, OSError):
        return "invalid timestamp"


def _indent(value: object) -> str:
    return str(value or "—").replace("\r", "").replace("\n", "\n    ")


def _journal() -> str:
    try:
        result = subprocess.run(
            ["journalctl", "--user", "--no-pager", "-o", "short-iso",
             "-n", str(JOURNAL_LINES),
             *[part for unit in control.UNITS.values() for part in ("-u", unit)]],
            capture_output=True, text=True, timeout=8, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return f"Journal unavailable: {type(exc).__name__}: {exc}"
    if result.returncode:
        return ("Journal unavailable: " + (result.stderr or result.stdout).strip())[:ERROR_LIMIT]
    return result.stdout[-JOURNAL_CHARS:] or "No recent systemd journal entries."


def report() -> str:
    """Full local diagnostic report. Excludes prompts and other config fields."""
    config, state, issues = read_snapshot()
    services = control.service_states()
    now = int(time.time())
    lines = [
        "HADALIS AUTOMATION DIAGNOSTICS",
        f"Generated: {_date(now)}",
        "Scope: all local Automation profiles and services",
        "WARNING: systemd journal may contain private information; review before sharing.",
        "",
        "CONFIGURATION",
        "  " + ("; ".join(issues) if issues else "valid"),
        "",
        "SERVICES",
    ]
    for key, unit in control.UNITS.items():
        service = services[key]
        lines.append(
            f"  {unit}: state={service.get('state', 'unknown')}"
            f" substate={service.get('detail', '')}"
            f" result={service.get('result', '')}"
            f" exec_main_status={service.get('exec_main_status', '')}"
            f" working_dir={service.get('working_directory', '')}"
            f" exec_start={service.get('exec_start', '')}"
        )
    problem = control._scheduler_problem(services, state, now)
    lines.extend([
        "",
        "SCHEDULER",
        f"  health: {problem or 'heartbeat and services available'}",
        f"  owner_id: {state.get('owner_id') or 'none'}",
        f"  requested_profile_id: {state.get('requested_profile_id') or 'none'}",
        f"  command_seq: {state.get('command_seq', 0)}",
        f"  command_ack_seq: {state.get('command_ack_seq', 0)}",
        f"  last_heartbeat: {_date(state.get('manager_heartbeat_at_unix'))}",
        f"  heartbeat_age_seconds: "
        f"{max(0, now - state['manager_heartbeat_at_unix']) if type(state.get('manager_heartbeat_at_unix')) is int else 'unknown'}",
        "",
        "PROFILES",
    ])
    for profile in config["profiles"]:
        item = state["profiles"][profile["id"]]
        # Explicit allowlist: never dump the whole profile/config or raw pending
        # dictionary, which may gain sensitive fields in future releases.
        lines.extend([
            f"  {profile['name']} [{profile['id']}]:",
            f"    enabled={profile['enabled']} mode={profile['mode']} "
            f"desired={item['desired']} status={item['status']}",
            f"    loop={item['loop_state']} request={item['request']} "
            f"job={item['job_id']} pending={item['pending'] is not None} "
            f"park_requested={item.get('park_requested', False)} "
            f"parked_pending={item.get('parked_pending', False)}",
            f"    iterations={item['iterations']} prompts_sent={item['prompts_sent']} "
            f"failures={item['failures']} poll_errors={item['poll_errors']} "
            f"job_poll_errors={item['job_poll_errors']}",
            f"    last_activity={_date(item['last_activity_at_unix'])} "
            f"next_run={_date(item['next_run_at_unix'])}",
            f"    status_detail: {_indent(item.get('status_detail'))}",
            f"    last_error: {_indent(item.get('last_error'))}",
        ])
    lines.extend(["", "RECENT ACTIVITY (newest first)"])
    for entry in reversed(state["events"]):
        lines.append(
            f"  {_date(entry.get('at_unix'))} [{entry.get('profile_id') or 'system'}] "
            f"{entry.get('kind', 'unknown')}: {_indent(entry.get('detail'))}"
        )
    if not state["events"]:
        lines.append("  No recorded events.")
    lines.extend(["", "SYSTEMD JOURNAL (latest matching entries)", _journal(), ""])
    return "\n".join(lines)


def export_report() -> str:
    """Write an explicit, private snapshot into /tmp and return its actual path."""
    content = report()
    fd, name = tempfile.mkstemp(prefix="hadalis-automation-", suffix=".log", dir="/tmp")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        return str(Path(name))
    except BaseException:
        try:
            os.close(fd)
        except OSError:
            pass
        Path(name).unlink(missing_ok=True)
        raise
