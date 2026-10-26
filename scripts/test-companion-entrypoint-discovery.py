#!/usr/bin/env python3
"""Offline coverage for the exact Alis/Alis-Companion daemon ABI boundary.

No running Quickshell, Git checkout, binary build, network or user HOME touched.
"""
import importlib.util
import json
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


manager = load("companion_manager_fixture", ROOT / "scripts/companion-manager.py")
discovery = load("alis_companion_status_fixture", ROOT / "scripts/alis-companion-status.py")
CANONICAL = "native/bin/alis-companiond"
PINNED_LEGACY = "native/bin/inir-companiond"
assert manager.COMPATIBLE_BINARIES == discovery.COMPATIBLE_BINARIES == {
    CANONICAL, PINNED_LEGACY
}


def write_package(release, daemon):
    release.mkdir(parents=True, exist_ok=True)
    manifest = {
        "id": "alis-companion", "hostApi": 1, "version": "0.1.0",
        "session": "HadalisSession.qml",
        "output": "HadalisOutput.qml",
        "settings": "modules/settings/CompanionConfig.qml",
        "binary": daemon, "sourceSha": "a" * 40,
    }
    for name in ("session", "output", "settings"):
        path = release / manifest[name]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("fixture")
    binary = release / daemon
    binary.parent.mkdir(parents=True, exist_ok=True)
    binary.write_text("fixture")
    binary.chmod(0o755)
    (release / "manifest.json").write_text(json.dumps(manifest))
    return manifest, binary


with tempfile.TemporaryDirectory(prefix="alis-companion-entrypoint-") as temp:
    root = Path(temp)
    shell = root / "shell"
    shell.mkdir()
    data = root / "data"
    current = data / "alis-companion/current"
    for name in (PINNED_LEGACY, CANONICAL):
        release = data / "alis-companion/releases" / ("a" * 40)
        if release.exists():
            import shutil
            shutil.rmtree(release)
        info, binary = write_package(release, name)
        if current.is_symlink():
            current.unlink()
        current.symlink_to(Path("releases") / ("a" * 40))
        assert manager.installed_revision(data) == "a" * 40, name
        result = discovery.inspect(shell, data)
        assert result["available"] and result["diagnostic"] == "ready", result
        assert result["root"] == str(release.resolve())
        binary.chmod(0o644)
        assert manager.installed_revision(data) == "", "non-executable accepted"
        assert not discovery.inspect(shell, data)["available"], "non-executable discovered"
        binary.chmod(0o755)
        info["binary"] = "native/bin/untrusted-daemon"
        (release / "manifest.json").write_text(json.dumps(info))
        assert manager.installed_revision(data) == "", "foreign daemon accepted"
        assert not discovery.inspect(shell, data)["available"], "foreign daemon discovered"
        info["binary"] = "../../../tmp/foreign"
        (release / "manifest.json").write_text(json.dumps(info))
        assert manager.installed_revision(data) == "", "path escape accepted"
        assert not discovery.inspect(shell, data)["available"], "path escape discovered"
        info["binary"] = name
        info["hostApi"] = True
        (release / "manifest.json").write_text(json.dumps(info))
        assert manager.installed_revision(data) == "", "invalid host API accepted"
        assert not discovery.inspect(shell, data)["available"], "invalid host API discovered"

print("PASS: pinned iNiR and canonical Alis companion daemon discovery, executable gate, path and host API rejection")
