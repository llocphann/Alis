"""Scoped GitHub credentials for AUTO-R01. Never persist or log token content.

Adapted from the historical Automation Secret Service integration. Tokens are
passed only via stdin to secret-tool and supplied to Git only through a narrowly
scoped credential-helper pipe. No plaintext or environment fallback is written.
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

from . import taskflow

REPOS = taskflow.REPOSITORIES
APP = "hadalis-automation"  # Preserve existing keyring namespace.
KIND = "github"
GITHUB = "github.com"


class CredentialError(ValueError):
    pass


def _require_repo(repo: str) -> str:
    if repo not in REPOS:
        raise CredentialError("Repository is not an authorized Automation owner")
    return repo


def _metadata_path() -> Path:
    folder = taskflow.state_dir() / "credentials"
    if folder.is_symlink():
        raise CredentialError("Unsafe credential metadata directory")
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    return folder / "github-status.json"


def _metadata() -> dict:
    path = _metadata_path()
    if not path.exists():
        return {}
    if path.is_symlink():
        raise CredentialError("Unsafe credential metadata file")
    try:
        with path.open(encoding="utf-8") as stream:
            result = json.load(stream)
    except (OSError, ValueError):
        return {}
    return result if isinstance(result, dict) else {}


def _mark(repo: str, saved: bool) -> None:
    path = _metadata_path()
    lock = path.parent / ".status.lock"
    if lock.is_symlink():
        raise CredentialError("Unsafe credential metadata lock")
    with lock.open("a+", encoding="utf-8") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        metadata = _metadata()
        if saved:
            metadata[repo] = True
        else:
            metadata.pop(repo, None)
        taskflow._atomic_json(path, metadata)


def _secret_tool(operation: str, repo: str, *, token: str | None = None) -> str:
    _require_repo(repo)
    executable = shutil.which("secret-tool")
    if not executable:
        raise CredentialError("System Secret Service keyring is unavailable")
    if operation not in {"store", "lookup", "clear"}:
        raise CredentialError("Unsupported keyring operation")
    args = [executable, operation]
    if operation == "store":
        args.append("--label=Alis Automation GitHub")
    args += ["application", APP, "repository", repo, "kind", KIND]
    try:
        result = subprocess.run(args, input=token, capture_output=True,
                                text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        raise CredentialError("System keyring operation unavailable") from None
    if result.returncode:
        if operation == "lookup" and result.returncode == 1 and not result.stderr:
            return ""
        raise CredentialError("Unlock the system keyring and retry")
    return result.stdout.rstrip("\n") if operation == "lookup" else ""


def save(repo: str, token: str) -> dict:
    _require_repo(repo)
    if (not isinstance(token, str) or not 1 <= len(token) <= 512
            or any(ord(c) < 33 or ord(c) > 126 for c in token)):
        raise CredentialError("Token must be one nonempty printable line, max 512 characters")
    _secret_tool("store", repo, token=token)
    _mark(repo, True)
    return {"ok": True, "repository": repo, "saved": True}


def clear(repo: str) -> dict:
    _secret_tool("clear", repo)
    _mark(repo, False)
    return {"ok": True, "repository": repo, "saved": False}


def status(repo: str) -> dict:
    _require_repo(repo)
    return {"ok": True, "repository": repo,
            "keyring_available": shutil.which("secret-tool") is not None,
            "saved": _metadata().get(repo) is True}


def _lookup(repo: str) -> str:
    # Read only for local authorized Git/GitHub API operations. Never display.
    token = _secret_tool("lookup", repo)
    if token and (len(token) > 512 or any(c in token for c in "\r\n")):
        raise CredentialError("Invalid keyring secret")
    return token


def git_helper(repo: str, operation: str, request: str) -> str:
    """Return the Git credential protocol response to Git only, not the UI."""
    _require_repo(repo)
    if operation != "get" or len(request) > 8192:
        return ""
    parts = dict(line.split("=", 1) for line in request.splitlines() if "=" in line)
    if (parts.get("protocol") != "https" or parts.get("host") not in
            {"github.com", "github.com:443"}):
        return ""
    if parts.get("path", "").removesuffix(".git").casefold() != repo.casefold():
        return ""
    try:
        token = _lookup(repo)
    except CredentialError:
        return ""
    return "username=x-access-token\npassword=" + token + "\n\n" if token else ""


def git_options(repo: str) -> list[str]:
    """Strictly scoped credential pipe: no token in argv, env or stored config."""
    _require_repo(repo)
    root = Path(__file__).resolve().parents[1]
    helper = "!" + shlex.join([sys.executable,
                               str(root / "scripts/alis-automation-task.py"),
                               "git-credential", repo])
    return ["-c", "credential.helper=", "-c", "credential.helper=" + helper,
            "-c", "credential.useHttpPath=true"]


def git_env() -> dict:
    env = dict(os.environ)
    for name in list(env):
        if (name.startswith("GIT_TRACE") or name in
                {"GIT_CURL_VERBOSE", "GIT_ASKPASS", "SSH_ASKPASS", "GH_TOKEN", "GITHUB_TOKEN"}):
            env.pop(name)
    env.update(GIT_TERMINAL_PROMPT="0", GIT_TRACE_REDACT="1")
    return env
