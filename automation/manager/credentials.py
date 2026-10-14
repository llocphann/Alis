"""Profile GitHub credentials live only in the system Secret Service keyring.

Metadata contains a saved flag, never the secret. No plaintext fallback, token
argv/environment, prompt injection, credential-store file or diagnostic output.
Git receives credentials through its helper pipe, scoped to the repository.
"""
from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
from urllib.parse import urlparse

from .store import _write, read_snapshot, state_dir

PROFILE_RE = re.compile(r"[a-z0-9-]{1,80}")
ROOT = Path(__file__).resolve().parents[2]


def _profile(profile_id: str, *, existing=False) -> None:
    if not isinstance(profile_id, str) or not PROFILE_RE.fullmatch(profile_id):
        raise ValueError("Invalid credential profile")
    if existing and not any(p["id"] == profile_id for p in read_snapshot()[0]["profiles"]):
        raise ValueError("Credential profile not found")


def _metadata() -> dict:
    path = state_dir() / "credentials/github.json"
    if not path.exists(): return {}
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError): return {}


def _mark(profile_id: str, saved: bool) -> None:
    folder = state_dir() / "credentials"
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (folder / "metadata.lock").open("a+") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        data = _metadata()
        if saved: data[profile_id] = True
        else: data.pop(profile_id, None)
        _write(folder / "github.json", data)


def status() -> dict:
    saved = _metadata()
    return {"available": bool(shutil.which("secret-tool")),
            "github": {pid: value is True for pid,value in saved.items() if PROFILE_RE.fullmatch(pid)}}


def has_token(profile_id: str | None) -> bool:
    return bool(profile_id and _metadata().get(profile_id) is True)


def _secret_tool(operation: str, profile_id: str, *, token: str | None = None) -> str:
    _profile(profile_id)
    executable = shutil.which("secret-tool")
    if not executable: raise RuntimeError("System keyring unavailable; token was not saved")
    argv = [executable, operation]
    if operation == "store": argv += ["--label=Hadalis Automation GitHub"]
    argv += ["application", "hadalis-automation", "profile", profile_id, "kind", "github"]
    try:
        result = subprocess.run(argv, input=token, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        raise RuntimeError("System keyring operation unavailable") from None
    if result.returncode:
        if operation == "lookup" and result.returncode == 1 and not result.stderr: return ""
        raise RuntimeError("Unlock the system keyring and retry")
    return result.stdout.rstrip("\n") if operation == "lookup" else ""


def save(profile_id: str, token: str) -> dict:
    _profile(profile_id, existing=True)
    if not isinstance(token,str) or not 1 <= len(token) <= 512 or any(ord(c) < 33 or ord(c) > 126 for c in token):
        raise ValueError("Token must be a nonempty single line of at most 512 characters")
    _secret_tool("store", profile_id, token=token)
    _mark(profile_id, True)
    return {"ok": True, "saved": True}


def clear(profile_id: str) -> dict:
    _profile(profile_id, existing=True)
    _secret_tool("clear", profile_id)
    _mark(profile_id, False)
    return {"ok": True, "saved": False}


def repository(remote: str) -> str | None:
    if remote.startswith("git@github.com:"):
        path = remote.removeprefix("git@github.com:")
    else:
        parsed = urlparse(remote)
        if parsed.scheme != "https" or parsed.hostname != "github.com" or parsed.username or parsed.password:
            return None
        path = parsed.path.lstrip("/")
    path = path.removesuffix(".git")
    return path if re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", path) else None


def git_options(profile_id: str | None, remote: str) -> list[str]:
    repo = repository(remote)
    if not has_token(profile_id) or not repo: return []
    _profile(profile_id)
    helper = "!" + shlex.join([sys.executable, str(ROOT / "scripts/hadalis-git-credential.py"), profile_id, repo])
    # Reset inherited helpers, including any plaintext credential-store helper.
    return ["-c", "credential.helper=", "-c", "credential.helper=" + helper,
            "-c", "credential.useHttpPath=true"]


def git_env() -> dict:
    env = dict(os.environ)
    for key in list(env):
        if key.startswith("GIT_TRACE") or key in {"GIT_CURL_VERBOSE", "GIT_ASKPASS", "SSH_ASKPASS"}:
            env.pop(key)
    env.update(GIT_TERMINAL_PROMPT="0", GIT_TRACE_REDACT="1")
    return env


def helper(profile_id: str, repo: str, operation: str, request: str) -> str:
    """Only Git's credential protocol may receive the secret, through stdout."""
    _profile(profile_id)
    if operation != "get" or len(request) > 8192: return ""
    fields = dict(line.split("=",1) for line in request.splitlines() if "=" in line)
    if fields.get("protocol") != "https" or fields.get("host") not in {"github.com", "github.com:443"}:
        return ""
    if fields.get("path", "").removesuffix(".git").casefold() != repo.casefold(): return ""
    try: token = _secret_tool("lookup", profile_id)
    except RuntimeError: return ""
    if not token or any(c in token for c in "\r\n"): return ""
    return "username=x-access-token\npassword=" + token + "\n\n"
