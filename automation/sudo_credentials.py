"""Local Secret Service storage for optional Alis sudo authentication.

Separate from the GitHub token namespace. Never write passwords to disk,
argv, environment, GitHub, audit records or automation receipts. Status
reports only a boolean; reading the secret is broker-only and permitted
only for an already allowlisted, owner-authorized privileged action.
"""
from __future__ import annotations

import shutil
import subprocess

APP = "alis-automation"
KIND = "sudo-password"


class SudoKeyringError(ValueError):
    pass


def _valid(secret: str) -> bool:
    return (isinstance(secret, str) and 1 <= len(secret) <= 1024
            and not any(c in secret for c in ("\0", "\r", "\n")))


def _secret_tool(operation: str, secret: str | None = None) -> str:
    executable = shutil.which("secret-tool")
    if not executable:
        raise SudoKeyringError("System Secret Service keyring unavailable")
    if operation not in {"store", "lookup", "clear"}:
        raise SudoKeyringError("Invalid Alis sudo keyring operation")
    argv = [executable, operation]
    if operation == "store":
        argv.append("--label=Alis Automation sudo (local only)")
    argv += ["application", APP, "kind", KIND]
    try:
        result = subprocess.run(
            argv, input=secret if operation == "store" else None,
            capture_output=True, text=True, timeout=20, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise SudoKeyringError("Sudo keyring operation unavailable") from None
    if result.returncode:
        if operation == "lookup" and result.returncode == 1 and not result.stderr:
            return ""
        raise SudoKeyringError("Unlock system keyring and retry") from None
    return result.stdout.rstrip("\n") if operation == "lookup" else ""


def save(password: str) -> dict:
    if not _valid(password):
        raise SudoKeyringError("Sudo password must be a single line, max 1024 chars")
    _secret_tool("store", password)
    return {"ok": True, "saved": True, "keyring_available": True}


def clear() -> dict:
    _secret_tool("clear")
    return {"ok": True, "saved": False, "keyring_available": True}


def _lookup_for_broker() -> str:
    secret = _secret_tool("lookup")
    if secret and not _valid(secret):
        raise SudoKeyringError("Invalid sudo password in keyring")
    return secret


def status() -> dict:
    available = shutil.which("secret-tool") is not None
    if not available:
        return {"ok": True, "saved": False, "keyring_available": False}
    return {"ok": True, "saved": bool(_lookup_for_broker()),
            "keyring_available": True}
