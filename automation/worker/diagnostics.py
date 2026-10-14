"""Bounded, read-only machine observations. Raw evidence never crosses Git."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import time

from automation.manager.store import _write
from automation.worker.process import bounded_run, session_env
from automation.worker.privacy import redact, scrub, SECRET_KEY

CHECKS = {"services", "processes", "journal", "git", "resources", "hardware",
          "config", "runtime", "screenshot", "crashes"}
UNITS = {"hadalis-chatgpt.service", "hadalis-worker.service", "hadalis-chat-bridge.service",
         "hadalis-privilege.service", "quickshell.service", "quickshell@inir.service"}
MAX_BYTES = 65536


def validate(spec):
    if set(spec) - {"checks", "config_paths", "units", "lines"}:
        raise ValueError("unknown diagnostic fields")
    checks = spec.get("checks", ["services", "processes", "git", "resources", "runtime"])
    if not isinstance(checks, list) or not 1 <= len(checks) <= len(CHECKS) or any(x not in CHECKS for x in checks):
        raise ValueError("diagnostic checks are not allowlisted")
    units = spec.get("units", sorted(UNITS))
    if not isinstance(units, list) or not units or any(x not in UNITS for x in units):
        raise ValueError("diagnostic units are not allowlisted")
    lines = spec.get("lines", 100)
    if type(lines) is not int or not 1 <= lines <= 200:
        raise ValueError("journal line limit must be 1..200")
    paths = spec.get("config_paths", [])
    if not isinstance(paths, list) or len(paths) > 8:
        raise ValueError("config path limit exceeded")
    for path in paths:
        config_path(path)


def config_path(relative):
    if not isinstance(relative, str) or len(relative) > 256 or SECRET_KEY.search(relative):
        raise ValueError("credential paths cannot be observed")
    root = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home()/".config"))).resolve()
    target = (root / relative).resolve()
    # Deliberately narrow: shell/compositor configuration, not arbitrary home files.
    if root not in target.parents or target.relative_to(root).parts[0] not in {"quickshell", "niri", "hadalis-automation"}:
        raise ValueError("config path outside diagnostic allowlist")
    return target


def error_codes(text):
    patterns = {"qml_syntax": r"SyntaxError|Expected token|Unexpected token",
                "qml_import": r'module .{0,100} is not installed|Type .{0,100} unavailable',
                "qml_reference": r"ReferenceError|Cannot assign|Unable to assign",
                "process_crash": r"segmentation fault|core dumped|SIGSEGV",
                "resource_pressure": r"out of memory|oom-kill|No space left",
                "permission": r"Permission denied|Access denied",
                "network": r"Connection refused|timed out|Could not resolve"}
    return [name for name, pattern in patterns.items() if re.search(pattern, text, re.I)]


def collect(spec, workspace: Path, evidence_dir: Path):
    validate(spec)
    evidence_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    checks = spec.get("checks", ["services", "processes", "git", "resources", "runtime"])
    observations = []; safe = []
    deadline = time.monotonic() + 45
    def command(check, argv, cwd=workspace):
        if time.monotonic() >= deadline:
            return {"exit_code": None, "stdout": "", "stderr": "diagnostic budget exhausted", "timed_out": True}
        try:
            result = bounded_run(argv, cwd=cwd, timeout=min(8, deadline-time.monotonic()), capture=MAX_BYTES,
                env=session_env({"PATH","HOME","USER","LANG","DISPLAY","WAYLAND_DISPLAY","XDG_RUNTIME_DIR","NIRI_SOCKET","DBUS_SESSION_BUS_ADDRESS"}))
        except OSError:
            result = {"exit_code": 127, "stdout": "", "stderr": "diagnostic command unavailable", "timed_out": False}
        result["stdout"] = redact(result["stdout"]); result["stderr"] = redact(result["stderr"])
        observations.append({"check": check, "argv": argv, "at_unix": int(time.time()), **result})
        safe.append({"check": check, "exit_code": result["exit_code"],
                     "error_codes": error_codes(result["stdout"]+result["stderr"])})
        return result
    for check in dict.fromkeys(checks):
        if check == "services":
            for unit in spec.get("units", sorted(UNITS)):
                r = command(check, ["systemctl", "--user", "show", unit, "--property=ActiveState,SubState,Result,ExecMainStatus"])
                fields = dict(line.split("=", 1) for line in r["stdout"].splitlines() if "=" in line)
                safe[-1]["unit"] = unit
                safe[-1]["active"] = fields.get("ActiveState") in {"active", "activating"}
        elif check == "journal":
            argv = ["journalctl", "--user", "--no-pager", "--output=short-monotonic", "--since=-15min", "-n", str(spec.get("lines",100))]
            for unit in spec.get("units", sorted(UNITS)): argv.extend(["-u", unit])
            command(check, argv)
        elif check == "git":
            # Observe both the pinned execution clone and the real maintainer worktree.
            from automation.worker.daemon import ROOT
            for cwd in dict.fromkeys([workspace, ROOT]):
                command(check, ["git", "rev-parse", "HEAD"], cwd)
                r = command(check, ["git", "status", "--porcelain=v1", "--untracked-files=no"], cwd)
                safe[-1]["dirty_count"] = len(r["stdout"].splitlines())
                command(check, ["git", "diff", "--stat", "--no-ext-diff"], cwd)
        elif check == "processes":
            # No argv/environment scan: these frequently contain credentials.
            command(check, ["ps", "-eo", "pid,ppid,pgid,stat,etimes,rss,pcpu,comm", "--sort=-rss"])
        elif check == "resources":
            value = {"load": list(os.getloadavg()), "disk_free_bytes": shutil.disk_usage(evidence_dir).free}
            mem = Path("/proc/meminfo").read_text()[:8192]
            observations.append({"check": check, "at_unix": int(time.time()), "meminfo": mem, **value})
            safe.append({"check": check, **value})
        elif check == "hardware":
            command(check, ["lscpu"])
            command(check, ["lspci", "-nn"])
        elif check == "config":
            for relative in spec.get("config_paths", []):
                path = config_path(relative)
                try:
                    if path.stat().st_size > MAX_BYTES: raise ValueError("config exceeds capture bound")
                    data = path.read_text()
                    try: data = json.dumps(scrub(json.loads(data)))
                    except json.JSONDecodeError: data = redact(data)
                    observations.append({"check": check, "path": relative, "at_unix": int(time.time()), "content": data})
                    safe.append({"check": check, "available": True})
                except (OSError, ValueError): safe.append({"check": check, "available": False})
        elif check == "runtime":
            command(check, ["qs", "list"])
            command(check, ["niri", "msg", "-j", "outputs"])
        elif check == "crashes":
            command(check, ["coredumpctl", "--no-pager", "--since=-1h", "list", "quickshell"])
        elif check == "screenshot":
            # One private frame. No screenshot pixels, paths or window titles in Git/chat.
            image = evidence_dir/"screen.png"
            r = command(check, ["grim", "-s", "0.5", str(image)])
            if image.exists():
                image.chmod(0o600)
                if image.stat().st_size > 8*1024**2: image.unlink(); safe[-1]["available"] = False
                else: safe[-1]["available"] = r["exit_code"] == 0
    _write(evidence_dir/"observations.json", {"observations": observations})
    digest = hashlib.sha256((evidence_dir/"observations.json").read_bytes()).hexdigest()
    return {"safe_observations": safe, "evidence_sha256": digest, "evidence_location": "private"}
