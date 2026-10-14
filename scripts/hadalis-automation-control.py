#!/usr/bin/env python3
"""Narrow JSON control interface for the Quickshell Automation settings page."""
from __future__ import annotations

import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from automation.manager import control, credentials, diagnostics, store  # noqa: E402


def main(argv: list[str]) -> dict:
    if not argv or argv[0] == "status":
        if len(argv) > 1:
            raise ValueError("status takes no arguments")
        return control.status()
    operation, *args = argv
    if operation == "github-token-save" and len(args) == 1:
        # Secret input is private stdin, never argv, JSON config or Activity.
        return credentials.save(args[0], sys.stdin.read(513))
    if operation == "github-token-clear" and len(args) == 1:
        return credentials.clear(args[0])
    if operation == "service" and len(args) == 2:
        return control.control_service(args[0], args[1])
    if operation == "profile-action" and len(args) == 2:
        return control.profile_action(args[0], args[1])
    if operation == "job-cancel" and len(args) == 1:
        return control.cancel_job(args[0])
    if operation == "profile-create" and len(args) == 1:
        return control.create_profile(args[0])
    if operation == "profile-duplicate" and len(args) == 2:
        return control.create_profile(args[1], args[0])
    if operation == "profile-set" and len(args) in {3, 4}:
        if len(args) == 4 and args[3] != "confirm-delete":
            raise ValueError("invalid confirmation")
        return control.set_profile(args[0], args[1], args[2], len(args) == 4)
    if operation == "profile-reset-prompt" and len(args) == 2:
        return control.reset_prompt(args[0], args[1])
    if operation == "maintenance-set" and len(args) in {2, 3}:
        if len(args) == 3 and args[2] != "confirm-delete":
            raise ValueError("invalid confirmation")
        return control.set_maintenance(args[0], args[1], len(args) == 3)
    if operation == "profile-remove" and len(args) in {1, 2}:
        if len(args) == 2 and args[1] != "confirm-unresolved":
            raise ValueError("invalid removal confirmation")
        return control.remove_profile(args[0], len(args) == 2)
    if operation == "profile-park-unresolved" and len(args) == 1:
        return control.request_park_unresolved(args[0])
    if operation == "logs" and not args:
        return {"ok": True, "text": diagnostics.report()}
    if operation == "logs-export" and not args:
        return {"ok": True, "path": diagnostics.export_report()}
    raise ValueError("unknown or malformed automation control action")


if __name__ == "__main__":
    try:
        result = main(sys.argv[1:])
        print(json.dumps(result, ensure_ascii=False))
    except (ValueError, RuntimeError, OSError, json.JSONDecodeError) as exc:
        operation = sys.argv[1] if len(sys.argv) > 1 else "status"
        args = sys.argv[2:]
        profile_id = (args[1] if operation == "profile-action" and len(args) > 1
                      else args[0] if operation in {"profile-remove", "profile-set",
                                                    "profile-reset-prompt",
                                                    "profile-park-unresolved"} and args
                      else None)
        detail = f"{operation} failed: {type(exc).__name__}: {str(exc)[:1900]}"
        try:
            store.change_state(lambda _config, state: store.event(
                state, profile_id, "control_error", detail))
        except (ValueError, RuntimeError, OSError):
            pass  # Preserve the original failure if local state is unreadable.
        print(json.dumps({"ok": False, "error": str(exc)[:2000]}))
        raise SystemExit(1)
