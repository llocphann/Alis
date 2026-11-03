#!/usr/bin/env python3
"""Helper for Autostart Services in Settings -> Apps & AI -> Autostart.

Lists and manages systemd --user services (enable/disable at login, start/stop/restart).
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys

IGNORED_UNIT_PREFIXES = (
    "app-",
    "vte-spawn-",
    "dbus-:",
    "flatpak-session-helper",
    "xdg-document-portal",
    "xdg-permission-store",
    "systemd-exit",
    "systemd-tmpfiles",
)


def _run_systemctl(args: list[str], timeout: float = 4.0) -> tuple[int, str, str]:
    systemctl = shutil.which("systemctl")
    if not systemctl:
        return 127, "", "systemctl not found"
    try:
        proc = subprocess.run(
            [systemctl, "--user", "--no-pager", "--no-legend", *args],
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        return proc.returncode, proc.stdout, proc.stderr.strip()
    except Exception as exc:
        return 1, "", str(exc)


def list_user_services() -> dict:
    rc_files, out_files, err_files = _run_systemctl(["list-unit-files", "--type=service"])
    rc_units, out_units, _ = _run_systemctl(["list-units", "--type=service", "--all"])

    if rc_files == 127:
        return {"ok": False, "error": err_files or "systemctl not available", "services": []}

    runtime_map: dict[str, dict] = {}
    for raw_line in out_units.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        # Strip leading bullet (● or *) if present
        line = re.sub(r"^[●*○×]\s+", "", line)
        parts = line.split(None, 4)
        if len(parts) < 4:
            continue
        unit, load_state, active_state, sub_state = parts[0], parts[1], parts[2], parts[3]
        desc = parts[4].strip() if len(parts) > 4 else ""
        runtime_map[unit] = {
            "loadState": load_state,
            "activeState": active_state,
            "subState": sub_state,
            "description": desc,
        }

    services_by_unit: dict[str, dict] = {}
    for raw_line in out_files.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        unit = parts[0].strip()
        file_state = parts[1].strip()
        preset = parts[2].strip() if len(parts) > 2 else ""

        if not unit.endswith(".service"):
            continue
        # Skip uninstantiated template unit files like foo@.service
        if "@.service" in unit:
            continue
        stem = unit[:-8]
        if any(stem.startswith(p) for p in IGNORED_UNIT_PREFIXES):
            continue
        if file_state in ("masked", "masked-runtime", "alias"):
            continue

        rt = runtime_map.get(unit, {})
        active_state = rt.get("activeState", "inactive")
        sub_state = rt.get("subState", "dead")
        desc = rt.get("description", "")

        can_toggle = file_state in (
            "enabled",
            "enabled-runtime",
            "disabled",
            "indirect",
            "generated",
            " bad",
        )
        enabled = file_state in ("enabled", "enabled-runtime")

        services_by_unit[unit] = {
            "unit": unit,
            "name": stem,
            "description": desc or f"User service ({stem})",
            "unitFileState": file_state,
            "preset": preset,
            "enabled": enabled,
            "activeState": active_state,
            "subState": sub_state,
            "running": active_state == "active" and sub_state in ("running", "listening", "exited"),
            "canToggle": can_toggle,
        }

    # Include active instantiated services not listed in unit-files (if non-transient)
    for unit, rt in runtime_map.items():
        if unit in services_by_unit or not unit.endswith(".service"):
            continue
        stem = unit[:-8]
        if any(stem.startswith(p) for p in IGNORED_UNIT_PREFIXES):
            continue
        active_state = rt.get("activeState", "inactive")
        sub_state = rt.get("subState", "dead")
        if active_state != "active" and active_state != "failed":
            continue
        services_by_unit[unit] = {
            "unit": unit,
            "name": stem,
            "description": rt.get("description") or f"User service ({stem})",
            "unitFileState": "runtime",
            "preset": "",
            "enabled": False,
            "activeState": active_state,
            "subState": sub_state,
            "running": active_state == "active",
            "canToggle": True,
        }

    def _sort_key(item: dict) -> tuple:
        # 0: enabled & running, 1: enabled, 2: running (canToggle), 3: disabled (canToggle), 4: static/other
        if item["enabled"] and item["running"]:
            rank = 0
        elif item["enabled"]:
            rank = 1
        elif item["running"] and item["canToggle"]:
            rank = 2
        elif item["canToggle"]:
            rank = 3
        elif item["running"]:
            rank = 4
        else:
            rank = 5
        return (rank, item["name"].lower())

    items = sorted(services_by_unit.values(), key=_sort_key)
    return {
        "ok": True,
        "services": items,
        "enabledCount": sum(1 for s in items if s["enabled"]),
        "runningCount": sum(1 for s in items if s["running"]),
    }


def _normalize_unit(unit: str) -> str:
    u = (unit or "").strip()
    if not u:
        return ""
    if not u.endswith(".service"):
        u = f"{u}.service"
    if not re.match(r"^[A-Za-z0-9_.@:\-]+\.service$", u):
        return ""
    return u


def set_service_enabled(unit_raw: str, enable: bool) -> dict:
    unit = _normalize_unit(unit_raw)
    if not unit:
        return {"ok": False, "error": f"Invalid service unit name: {unit_raw!r}"}
    action = "enable" if enable else "disable"
    rc, _, err = _run_systemctl([action, "--now", unit], timeout=8.0)
    if rc != 0:
        # Try without --now if the unit cannot be started/stopped immediately
        rc2, _, err2 = _run_systemctl([action, unit], timeout=6.0)
        if rc2 != 0:
            return {"ok": False, "unit": unit, "error": err or err2 or f"systemctl {action} failed"}
    res = list_user_services()
    res["updatedUnit"] = unit
    res["message"] = f"{unit} {'enabled' if enable else 'disabled'}"
    return res


def control_service(unit_raw: str, action: str) -> dict:
    unit = _normalize_unit(unit_raw)
    if not unit:
        return {"ok": False, "error": f"Invalid service unit name: {unit_raw!r}"}
    if action not in ("start", "stop", "restart"):
        return {"ok": False, "error": f"Unsupported action: {action!r}"}
    rc, _, err = _run_systemctl([action, unit], timeout=8.0)
    if rc != 0:
        return {"ok": False, "unit": unit, "error": err or f"systemctl {action} {unit} failed"}
    res = list_user_services()
    res["updatedUnit"] = unit
    res["message"] = f"{unit} {action}ed"
    return res


def main() -> int:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    if cmd == "list":
        res = list_user_services()
        print(json.dumps(res))
        return 0 if res.get("ok") else 1
    if cmd == "set-enabled":
        unit = sys.argv[2] if len(sys.argv) > 2 else ""
        flag = (sys.argv[3] if len(sys.argv) > 3 else "true").lower() in ("1", "true", "yes", "enable", "enabled")
        res = set_service_enabled(unit, flag)
        print(json.dumps(res))
        return 0 if res.get("ok") else 1
    if cmd == "action":
        unit = sys.argv[2] if len(sys.argv) > 2 else ""
        act = sys.argv[3] if len(sys.argv) > 3 else "restart"
        res = control_service(unit, act)
        print(json.dumps(res))
        return 0 if res.get("ok") else 1
    print(json.dumps({"ok": False, "error": f"Unknown subcommand: {cmd}"}))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
