#!/usr/bin/env python3
"""Isolated parity for IconThemeService Python fallback vs Rust desktop sync.

The fixture extracts the real embedded Python updater scripts from
services/IconThemeService.qml, runs them under a temporary HOME, runs
alis-native desktop sync-icon-theme under a separate temporary XDG_CONFIG_HOME,
and compares the resulting KDE/Qt/GTK INI semantics. No real desktop config,
gsettings database, or icon cache is touched.
"""

from __future__ import annotations

import configparser
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[2]
QML = REPO / "services" / "IconThemeService.qml"
THEME = "Alis-Native-Fixture"

FILES = {
    "kdeglobals": ("Icons", "Theme"),
    "qt5ct/qt5ct.conf": ("Appearance", "icon_theme"),
    "qt6ct/qt6ct.conf": ("Appearance", "icon_theme"),
    "gtk-3.0/settings.ini": ("Settings", "gtk-icon-theme-name"),
    "gtk-4.0/settings.ini": ("Settings", "gtk-icon-theme-name"),
}

INITIAL = {
    "kdeglobals": "[Icons]\nTheme=Old\nKeep=1\n\n[Other]\nX=1\n",
    "qt5ct/qt5ct.conf": "[Appearance]\nstyle=Fusion\nicon_theme=Old\n\n[Other]\nX=1\n",
    # Leave qt6ct missing to cover first-write behavior.
    "gtk-3.0/settings.ini": (
        "[Settings]\ngtk-theme-name=Adwaita\ngtk-icon-theme-name=Old\n"
        "\n[Other]\nX=1\n"
    ),
    # Existing non-empty GTK file without [Settings] must be backed up/reset.
    "gtk-4.0/settings.ini": "[Broken]\nX=1\n",
}

PROCESS_IDS = (
    "kdeGlobalsUpdateProc",
    "qt5ctProc",
    "qt6ctProc",
    "gtkSettingsProc",
)


def prepare_home(home: Path) -> None:
    for relative, content in INITIAL.items():
        path = home / ".config" / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)


def embedded_script(source: str, process_id: str) -> str:
    marker = f"id: {process_id}"
    start = source.index(marker)
    command = source.index("command:", start)
    opening = source.index("`", command)
    closing = source.index("`", opening + 1)
    script = source[opening + 1 : closing]
    script = script.replace("${" + process_id + ".themeName}", THEME)
    # QML template literals escape backslashes that Python must see literally.
    return script.replace("\\\\", "\\")


def run_python_fallback(home: Path, source: str) -> None:
    env = os.environ.copy()
    env["HOME"] = str(home)
    for process_id in PROCESS_IDS:
        script = embedded_script(source, process_id)
        result = subprocess.run(
            [sys.executable, "-c", script],
            env=env,
            text=True,
            capture_output=True,
        )
        if result.returncode:
            raise AssertionError(
                f"embedded Python icon updater failed: {process_id} rc={result.returncode}\n"
                f"stdout={result.stdout!r}\nstderr={result.stderr!r}"
            )


def run_rust(home: Path, rust: Path) -> None:
    env = os.environ.copy()
    env.update(
        {
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(home / ".config"),
        }
    )
    result = subprocess.run(
        [str(rust), "desktop", "sync-icon-theme", THEME],
        env=env,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        raise AssertionError(
            f"Rust desktop icon sync failed rc={result.returncode}\n"
            f"stdout={result.stdout!r}\nstderr={result.stderr!r}"
        )
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise AssertionError(f"Rust desktop icon sync returned non-JSON: {result.stdout!r}") from error
    if payload.get("ok") is not True or payload.get("theme") != THEME:
        raise AssertionError(f"unexpected Rust desktop icon response: {payload!r}")


def ini_semantics(path: Path) -> dict[str, dict[str, str]]:
    config = configparser.ConfigParser(interpolation=None)
    config.optionxform = str
    with path.open() as handle:
        config.read_file(handle)
    return {section: dict(config[section]) for section in config.sections()}


def compare_configs(py_home: Path, rs_home: Path) -> None:
    for relative, (section, key) in FILES.items():
        py_path = py_home / ".config" / relative
        rs_path = rs_home / ".config" / relative
        if not py_path.is_file() or not rs_path.is_file():
            raise AssertionError(f"missing generated icon config: {relative}")
        py = ini_semantics(py_path)
        rs = ini_semantics(rs_path)
        if py != rs:
            raise AssertionError(
                f"desktop icon config mismatch for {relative}\n"
                f"python={py!r}\nrust={rs!r}"
            )
        if rs.get(section, {}).get(key) != THEME:
            raise AssertionError(f"{relative} did not receive expected theme {THEME!r}")
        print(f"PASS desktop icon config: {relative}")


def compare_corrupt_backups(py_home: Path, rs_home: Path) -> None:
    relative = Path(".config/gtk-4.0")
    expected = INITIAL["gtk-4.0/settings.ini"]
    for label, home in (("python", py_home), ("rust", rs_home)):
        backups = sorted((home / relative).glob("settings.ini.corrupt-*.bak"))
        if len(backups) != 1:
            raise AssertionError(f"{label} expected one GTK4 corrupt backup, got {backups!r}")
        if backups[0].read_text() != expected:
            raise AssertionError(f"{label} GTK4 corrupt backup content changed")
    print("PASS desktop icon config: GTK4 corrupt backup lifecycle")


def assert_consumer_order(source: str) -> None:
    gsettings = source.index("id: gsettingsSetProc")
    native = source.index("id: nativeIconSyncProc")
    if gsettings >= native:
        raise AssertionError("IconThemeService native sync no longer follows gsettings stage")
    required = [
        'root._startKdeGlobalsSync(gsettingsSetProc.themeName',
        'command: [root.nativeDispatchPath, "desktop-icons", nativeIconSyncProc.themeName]',
        "native icon sync failed; falling back to legacy path",
    ]
    missing = [token for token in required if token not in source]
    if missing:
        raise AssertionError(f"IconThemeService native/fallback consumer contract missing: {missing!r}")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check-desktop-icon-parity.py /path/to/alis-native", file=sys.stderr)
        return 64
    rust = Path(sys.argv[1]).resolve()
    if not rust.is_file():
        print(f"Rust binary not found: {rust}", file=sys.stderr)
        return 2

    source = QML.read_text()
    assert_consumer_order(source)

    with tempfile.TemporaryDirectory(prefix="alis-icon-parity.") as temp_raw:
        temp = Path(temp_raw)
        py_home = temp / "python"
        rs_home = temp / "rust"
        prepare_home(py_home)
        prepare_home(rs_home)

        run_python_fallback(py_home, source)
        run_rust(rs_home, rust)
        compare_configs(py_home, rs_home)
        compare_corrupt_backups(py_home, rs_home)

    print("PASS: desktop icon parity is isolated and consumer fallback remains intact")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
