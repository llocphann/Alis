#!/usr/bin/env python3
"""Finite, read-only optional package discovery. Never starts a Companion or model."""
import json
import os
from pathlib import Path
import sys

API = 1
ENTRYPOINTS = {
    "session": "HadalisSession.qml",
    "output": "HadalisOutput.qml",
    "settings": "modules/settings/CompanionConfig.qml",
    "binary": "native/bin/alis-companiond",
}


def inspect(shell_root, data_home=None):
    package = Path(shell_root) / "optional/hadanion"
    if not package.exists():
        package = Path(data_home or os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "hadanion/current"
    manifest = package / "manifest.json"
    result = {"available": False, "version": "", "diagnostic": "not-installed"}
    try:
        if not manifest.is_file():
            return result
        if manifest.stat().st_size > 16384:
            raise ValueError("oversized manifest")
        data = json.loads(manifest.read_text())
        if not isinstance(data, dict):
            raise ValueError("manifest must be an object")
        if data.get("id") != "hadanion" or type(data.get("hostApi")) is not int or data["hostApi"] != API:
            return {**result, "diagnostic": "incompatible-package"}
        for key, name in ENTRYPOINTS.items():
            if data.get(key) != name or not (package / name).is_file():
                raise ValueError("incomplete package")
        if not os.access(package / ENTRYPOINTS["binary"], os.X_OK):
            raise ValueError("missing executable")
        version = data.get("version", "")
        if not isinstance(version, str) or not version or len(version) > 64:
            raise ValueError("invalid version")
        return {"available": True, "version": version, "diagnostic": "ready", "root": str(package.resolve()),
                "sourceSha": str(data.get("sourceSha", ""))[:64]}
    except (OSError, ValueError, TypeError):
        return {**result, "diagnostic": "invalid-package"}


if __name__ == "__main__":
    print(json.dumps(inspect(sys.argv[1] if len(sys.argv) == 2 else Path(__file__).resolve().parents[1])))
