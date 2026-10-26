#!/usr/bin/env python3
"""Isolated Python/Rust parity for Niri write commands.

All filesystem mutations live under temporary HOME/XDG_CONFIG_HOME roots.
niri, gsettings and systemctl are mocked, so this never touches the user's
real compositor configuration or running session.
"""

from __future__ import annotations

import difflib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from typing import Any

REPO = Path(__file__).resolve().parents[2]
PYTHON_HELPER = REPO / "scripts" / "niri-config.py"

CONFIG_FILES = {
    "config.kdl": """include "config.d/10-input-and-cursor.kdl"
include "config.d/15-outputs.kdl"
include "config.d/20-layout-and-overview.kdl"
include "config.d/30-window-rules.kdl"
include "config.d/60-animations.kdl"
include "config.d/70-binds.kdl"
include "config.d/90-user-extra.kdl"
""",
    "config.d/10-input-and-cursor.kdl": """input {
    keyboard {
        xkb {
            layout "us"
        }
        repeat-delay 250
        repeat-rate 50
    }
    touchpad {
        tap
    }
    mouse {
        accel-profile "flat"
    }
    mod-key "Super"
}
cursor {
    xcursor-theme "FixtureCursor"
    xcursor-size 24
    hide-when-typing
}
""",
    "config.d/15-outputs.kdl": """output "eDP-1" {
    mode "1920x1080@60.000"
    scale 1
    position x=0 y=0
}

output "HDMI-A-1" {
    mode "1920x1080@60.000"
    scale 1
    position x=1920 y=0
}
""",
    "config.d/20-layout-and-overview.kdl": """layout {
    gaps 10
    border {
        width 2
        active-color "#ffffff"
    }
    shadow {
        softness 30
        spread 5
        offset x=0 y=5
    }
}
overview {
    zoom 0.5
}
""",
    "config.d/30-window-rules.kdl": """window-rule {
    match app-id=".*"
    geometry-corner-radius 12
    clip-to-geometry true
}
""",
    "config.d/60-animations.kdl": """animations {
    slowdown 1.0
    window-open {
        spring damping-ratio=0.8 stiffness=1000 epsilon=0.0001
    }
}
""",
    "config.d/70-binds.kdl": """binds {
    Mod+Q { close-window; }
}
""",
    "config.d/90-user-extra.kdl": """// user fixture survives managed edits
""",
}

COMMANDS = [
    ["validate"],
    [
        "apply-output",
        "eDP-1",
        "mode=2560x1440@120.000",
        "scale=1.25",
        "transform=normal",
        "vrr=on-demand",
        "position=100,200",
        "dpms=off",
    ],
    [
        "persist-output",
        "eDP-1",
        "mode=2560x1440@120.000",
        "scale=1.25",
        "transform=normal",
        "vrr=on-demand",
        "position=100,200",
    ],
    [
        "persist-layout",
        '{"eDP-1":{"x":0,"y":0},"HDMI-A-1":{"x":2560,"y":0}}',
    ],
    ["set", "layout", "gaps", "18"],
    ["set-bind", "Mod+Q", "close-window", "--options", "repeat=false"],
    ["set-bind", "Mod+T", 'spawn "foot"'],
    ["remove-bind", "Mod+T"],
    ["sync-backdrop-overview-shadow", "on"],
    ["sync-backdrop-overview-shadow", "off"],
    ["sync-cursor"],
]


def write_executable(path: Path, content: str) -> None:
    path.write_text(content)
    path.chmod(0o755)


def prepare_home(root: Path) -> None:
    config = root / ".config" / "niri"
    for relative, content in CONFIG_FILES.items():
        path = config / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)


def normalize_json(value: Any, home: Path) -> Any:
    if isinstance(value, dict):
        return {key: normalize_json(item, home) for key, item in value.items()}
    if isinstance(value, list):
        return [normalize_json(item, home) for item in value]
    if isinstance(value, str):
        return value.replace(str(home), "<HOME>")
    return value


def run_one(kind: str, home: Path, mock_bin: Path, rust_binary: Path, command: list[str]):
    niri_log = home.parent / f"{kind}-niri.log"
    side_log = home.parent / f"{kind}-side.log"
    env = os.environ.copy()
    env.update(
        {
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(home / ".config"),
            "PATH": str(mock_bin) + os.pathsep + env.get("PATH", ""),
            "MOCK_NIRI_LOG": str(niri_log),
            "MOCK_SIDE_EFFECT_LOG": str(side_log),
        }
    )
    argv = (
        [sys.executable, str(PYTHON_HELPER), *command]
        if kind == "python"
        else [str(rust_binary), "niri", *command]
    )
    result = subprocess.run(argv, env=env, text=True, capture_output=True)
    stdout = result.stdout.strip()
    try:
        payload = json.loads(stdout) if stdout else None
    except json.JSONDecodeError as error:
        raise AssertionError(
            f"{kind} {' '.join(command)} returned non-JSON stdout: {stdout!r}\n"
            f"stderr: {result.stderr}"
        ) from error
    return result.returncode, normalize_json(payload, home), result.stderr


def snapshot(home: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for base in (home / ".config", home / ".local"):
        if not base.exists():
            continue
        for path in sorted(item for item in base.rglob("*") if item.is_file()):
            result[str(path.relative_to(home))] = path.read_text()
    return result


def normalized_log(path: Path, home: Path) -> list[str]:
    if not path.exists():
        return []
    return [line.replace(str(home), "<HOME>") for line in path.read_text().splitlines()]


def assert_equal(label: str, left: Any, right: Any) -> None:
    if left == right:
        return
    left_text = json.dumps(left, indent=2, ensure_ascii=False, sort_keys=True).splitlines()
    right_text = json.dumps(right, indent=2, ensure_ascii=False, sort_keys=True).splitlines()
    diff = "\n".join(
        difflib.unified_diff(left_text, right_text, fromfile="python", tofile="rust")
    )
    raise AssertionError(f"{label} parity mismatch:\n{diff}")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check-niri-write-parity.py /path/to/alis-native", file=sys.stderr)
        return 64
    rust_binary = Path(sys.argv[1]).resolve()
    if not rust_binary.is_file():
        print(f"Rust binary not found: {rust_binary}", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory(prefix="alis-niri-write-parity.") as temporary:
        temp = Path(temporary)
        mock_bin = temp / "mock-bin"
        mock_bin.mkdir()
        write_executable(
            mock_bin / "niri",
            """#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "$MOCK_NIRI_LOG"
case "${1:-}" in
    validate)
        printf '%s\\n' 'fixture config valid'
        printf '%s\\n' 'fixture validator note' >&2
        exit 0
        ;;
    msg) printf '%s\\n' 'mock-ok'; exit 0 ;;
    *) printf '%s\\n' 'unexpected niri invocation' >&2; exit 2 ;;
esac
""",
        )
        for name in ("gsettings", "systemctl"):
            write_executable(
                mock_bin / name,
                f"""#!/usr/bin/env bash
set -eu
printf '%s %s\\n' '{name}' "$*" >> "$MOCK_SIDE_EFFECT_LOG"
exit 0
""",
            )

        py_home = temp / "python-home"
        rs_home = temp / "rust-home"
        prepare_home(py_home)
        prepare_home(rs_home)

        for command in COMMANDS:
            py_rc, py_json, py_err = run_one("python", py_home, mock_bin, rust_binary, command)
            rs_rc, rs_json, rs_err = run_one("rust", rs_home, mock_bin, rust_binary, command)
            if py_rc != rs_rc:
                raise AssertionError(
                    f"{' '.join(command)} exit mismatch: python={py_rc} rust={rs_rc}\n"
                    f"python stderr={py_err!r}\nrust stderr={rs_err!r}"
                )
            assert_equal(" ".join(command) + " JSON", py_json, rs_json)
            print(f"PASS niri write: {' '.join(command[:2])}")

        assert_equal("Niri temp HOME tree", snapshot(py_home), snapshot(rs_home))
        assert_equal(
            "Niri mocked IPC sequence",
            normalized_log(temp / "python-niri.log", py_home),
            normalized_log(temp / "rust-niri.log", rs_home),
        )
        assert_equal(
            "Niri mocked side effects",
            normalized_log(temp / "python-side.log", py_home),
            normalized_log(temp / "rust-side.log", rs_home),
        )

    print("PASS: isolated Niri validate/write commands match Python without touching live config")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
