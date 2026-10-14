#!/usr/bin/env python3
"""Small, user-scoped Fcitx5/Unikey bridge for Hadalis Keyboard Settings.

Only whitelisted operations and values are accepted. Existing Fcitx profiles
and unrelated Unikey options are preserved, and a running daemon is never
restarted to apply a preference.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
FCITX_HOME = CONFIG_HOME / "fcitx5"
PROFILE = FCITX_HOME / "profile"
UNIKEY = FCITX_HOME / "conf" / "unikey.conf"
ENGINE = Path(os.environ.get("ALIS_FCITX5_DATA_DIR", "/usr/share/fcitx5/inputmethod")) / "unikey.conf"
BUS_NAME = "org.fcitx.Fcitx5"
BUS_PATH = "/controller"
BUS_INTERFACE = "org.fcitx.Fcitx.Controller1"
SECTION_RE = re.compile(r"^\s*\[([^\]]+)\]\s*$")
ENTRY_RE = re.compile(r"^\s*Name\s*=\s*unikey\s*$", re.IGNORECASE)


class InputMethodError(RuntimeError):
    pass


def command(*argv: str) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=8 if argv[0] == "bash" else 3, check=False)
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        raise InputMethodError(f"{argv[0]} is unavailable or timed out.") from exc


def remote(*args: str) -> subprocess.CompletedProcess[str] | None:
    if not shutil.which("fcitx5-remote"):
        return None
    return command("fcitx5-remote", *args)


def state() -> int:
    result = remote()
    if result and result.returncode == 0:
        try:
            value = int(result.stdout.strip())
            return value if value in (0, 1, 2) else 0
        except ValueError:
            pass
    return 0


def read_setting(key: str, default: str) -> str:
    if not UNIKEY.is_file():
        return default
    section = ""
    for line in UNIKEY.read_text(encoding="utf-8").splitlines():
        match = SECTION_RE.match(line)
        if match:
            section = match.group(1).strip().lower()
            continue
        if section == "config":
            match = re.match(r"^\s*" + re.escape(key) + r"\s*=\s*([^#;\r\n]*)", line)
            if match:
                return match.group(1).strip()
    return default


def configured() -> bool:
    return PROFILE.is_file() and any(ENTRY_RE.match(s) for s in PROFILE.read_text(encoding="utf-8").splitlines())


def snapshot() -> dict[str, object]:
    installed = shutil.which("fcitx5") is not None
    running_state = state() if installed else 0
    name = ""
    if running_state:
        result = remote("-n")
        if result and result.returncode == 0:
            name = result.stdout.strip()
    return {
        "installed": installed,
        "engineInstalled": ENGINE.is_file(),
        "configtoolInstalled": shutil.which("fcitx5-configtool") is not None,
        "running": running_state != 0,
        "state": running_state,
        "current": name,
        "unikeyConfigured": configured(),
        "method": read_setting("InputMethod", "0"),
        "charset": read_setting("OutputCharset", "0"),
    }


def atomic_write(path: Path, text: str) -> None:
    if path.is_symlink():
        raise InputMethodError("Refusing to overwrite a symbolic-link configuration.")
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    descriptor, temporary = tempfile.mkstemp(prefix=".hadalis-fcitx-", dir=path.parent)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def update_unikey_option(key: str, value: str) -> None:
    if not ENGINE.is_file():
        raise InputMethodError("Unikey is not installed. Install fcitx5-unikey.")
    previous = UNIKEY.read_text(encoding="utf-8") if UNIKEY.exists() else ""
    lines = previous.splitlines(keepends=True)
    section_start = -1
    section_end = len(lines)
    for index, line in enumerate(lines):
        match = SECTION_RE.match(line.rstrip("\r\n"))
        if match:
            if section_start >= 0:
                section_end = index
                break
            if match.group(1).strip().lower() == "config":
                section_start = index
    if section_start < 0:
        if previous and not previous.endswith("\n"):
            lines.append("\n")
        lines.extend(["[Config]\n", f"{key}={value}\n"])
    else:
        found = False
        index = section_start + 1
        while index < section_end:
            if re.match(r"^\s*" + re.escape(key) + r"\s*=", lines[index]):
                if not found:
                    lines[index] = f"{key}={value}\n"
                    found = True
                    index += 1
                else:
                    del lines[index]
                    section_end -= 1
            else:
                index += 1
        if not found:
            lines.insert(section_start + 1, f"{key}={value}\n")
    atomic_write(UNIKEY, "".join(lines))


def reload_config(addon: str | None = None) -> str:
    if state() == 0:
        return "Saved. Start Fcitx5 to use the new setting."
    if not shutil.which("busctl"):
        return "Saved. Restart Fcitx5 later to load the change."
    args = ("ReloadAddonConfig", "s", addon) if addon else ("ReloadConfig",)
    result = command("busctl", "--user", "call", BUS_NAME, BUS_PATH, BUS_INTERFACE, *args)
    return "" if result.returncode == 0 else "Saved. Reopen the input method to apply the change."


def add_unikey() -> str:
    if not ENGINE.is_file():
        raise InputMethodError("Unikey is not installed. Install fcitx5-unikey.")
    if configured():
        return "Unikey is already in the input method list."
    if not PROFILE.exists():
        raise InputMethodError("Start Fcitx5 first to create a starter profile.")
    original = PROFILE.read_text(encoding="utf-8")
    match = re.search(r"(?m)^\[Groups/(\d+)\]\s*$", original)
    if not match:
        raise InputMethodError("Custom Fcitx profile: add Unikey using Advanced Settings.")
    group = match.group(1)
    used = [int(n) for n in re.findall(r"(?m)^\[Groups/" + group + r"/Items/(\d+)\]\s*$", original)]
    number = max(used, default=-1) + 1
    atomic_write(PROFILE, original.rstrip("\n") + f"\n\n[Groups/{group}/Items/{number}]\nName=unikey\nLayout=\n")
    return reload_config()


def choose(language: str) -> str:
    if state() == 0:
        raise InputMethodError("Fcitx5 is not running. Start it first.")
    if language == "vi":
        if not configured():
            raise InputMethodError("Add Unikey to the input method list first.")
        result = remote("-s", "unikey")
        if not result or result.returncode != 0:
            raise InputMethodError("Cannot select Unikey. Open Advanced Settings to check the profile.")
        result = remote("-o")
    else:
        result = remote("-c")
    if not result or result.returncode != 0:
        raise InputMethodError("Fcitx5 did not accept the input method change.")
    return ""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("status", "start", "add-unikey", "set-method", "set-charset", "set-language"))
    parser.add_argument("value", nargs="?")
    args = parser.parse_args()
    notice = ""
    try:
        if args.action == "start":
            if not shutil.which("fcitx5"):
                raise InputMethodError("Fcitx5 is not installed.")
            helper = Path(__file__).with_name("fcitx5-session.sh")
            result = command("bash", str(helper))
            if result.returncode != 0:
                raise InputMethodError(result.stderr.strip() or "Could not start Fcitx5.")
        elif args.action == "add-unikey":
            notice = add_unikey()
        elif args.action == "set-method":
            if args.value not in ("0", "1"):
                raise InputMethodError("Supported methods: Telex and VNI.")
            update_unikey_option("InputMethod", args.value)
            notice = reload_config("unikey")
        elif args.action == "set-charset":
            if args.value != "0":
                raise InputMethodError("Only Unicode output is supported here.")
            update_unikey_option("OutputCharset", "0")
            notice = reload_config("unikey")
        elif args.action == "set-language":
            if args.value not in ("en", "vi"):
                raise InputMethodError("Supported languages: en and vi.")
            notice = choose(args.value)
        print(json.dumps({"ok": True, "notice": notice, **snapshot()}))
        return 0
    except (InputMethodError, OSError, UnicodeError) as exc:
        print(json.dumps({"ok": False, "error": str(exc), **snapshot()}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
