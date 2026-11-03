#!/usr/bin/env python3
"""Finite, read-only optional package discovery. Never starts a Companion or model."""
import json
import os
from pathlib import Path
import sys

API = 1
ENTRYPOINTS = {
    "session": "AlisSession.qml",
    "output": "AlisOutput.qml",
    "settings": "modules/settings/CompanionConfig.qml",
    "binary": "native/bin/alis-companiond",
}
# The source-pinned external package still exports alis-companiond. Both
# values are fixed known paths; arbitrary manifest-provided paths remain
# rejected, including for the optional local package.
COMPATIBLE_BINARIES = frozenset((
    ENTRYPOINTS["binary"],
    "native/bin/alis-companiond",
))


def inspect(shell_root, data_home=None):
    package = Path(shell_root) / "optional/alis-companion"
    if not package.exists():
        package = Path(data_home or os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "alis-companion/current"
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
        if data.get("id") != "alis-companion" or type(data.get("hostApi")) is not int or data["hostApi"] != API:
            return {**result, "diagnostic": "incompatible-package"}
        for key, name in ENTRYPOINTS.items():
            if key == "binary":
                name = data.get("binary")
                if name not in COMPATIBLE_BINARIES:
                    raise ValueError("unexpected daemon name")
            elif data.get(key) != name:
                raise ValueError("incompatible entrypoint")
            if not (package / name).is_file():
                raise ValueError("incomplete package")
        if not os.access(package / data["binary"], os.X_OK):
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
