#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

doctor="sdata/lib/doctor.sh"
arch_installer="sdata/dist-arch/install-deps.sh"
generic_installer="sdata/dist-generic/install-deps.sh"
arch_core="sdata/dist-arch/alis-core/PKGBUILD"
arch_tracker="sdata/dist-arch/alis-deps/PKGBUILD"
default_config="defaults/config.json"

python3 - "$doctor" "$arch_installer" "$generic_installer" "$arch_core" "$arch_tracker" "$default_config" <<'PY'
from pathlib import Path
import json
import re
import sys

doctor_path = Path(sys.argv[1])
installer_path = Path(sys.argv[2])
generic_installer_path = Path(sys.argv[3])
core_path = Path(sys.argv[4])
tracker_path = Path(sys.argv[5])
default_config_path = Path(sys.argv[6])
doctor = doctor_path.read_text(encoding="utf-8")
installer = installer_path.read_text(encoding="utf-8")
generic_installer = generic_installer_path.read_text(encoding="utf-8")
core = core_path.read_text(encoding="utf-8")
tracker = tracker_path.read_text(encoding="utf-8")
default_config = json.loads(default_config_path.read_text(encoding="utf-8"))

cmd_block = re.search(r"local cmds=\(\n(?P<body>.*?)\n\s*\)", doctor, re.S)
if not cmd_block:
    raise SystemExit("FAIL: could not find doctor command dependency list")

doctor_cmds = []
for command, _friendly in re.findall(r'^\s*"([^":]+):([^"\n]+)"\s*$', cmd_block.group("body"), re.M):
    doctor_cmds.append(command)

if not doctor_cmds:
    raise SystemExit("FAIL: doctor dependency command list is empty")

optional_equalizer_cmds = {"easyeffects", "socat"}
leaked_optional = sorted(optional_equalizer_cmds & set(doctor_cmds))
if leaked_optional:
    raise SystemExit(
        "FAIL: doctor hard-requires optional Equalizer backend commands: "
        + ", ".join(leaked_optional)
    )

# CAVA is the live Media visualizer process. Generic/manual source-install
# guidance must expose the same required capability as doctor and the distro
# installers, without making the entire shell pre-flight fail when omitted.
if "cava" not in doctor_cmds:
    raise SystemExit("FAIL: doctor no longer checks the CAVA runtime")
for token in (
    'check_cmd "cava" "CAVA audio visualizer"',
    'pipewire, pipewire-pulse, wireplumber, playerctl, pavucontrol, cava',
):
    if token not in generic_installer:
        raise SystemExit(
            f"FAIL: generic source-install guidance is missing CAVA dependency token: {token}"
        )

mapping_block = re.search(r"declare -A cmd_to_pkg=\(\n(?P<body>.*?)\n\s*\)", installer, re.S)
if not mapping_block:
    raise SystemExit("FAIL: could not find Arch doctor command mapping")

mapping = dict(re.findall(r'^\s*\[([^\]]+)\]="([^"]+)"\s*$', mapping_block.group("body"), re.M))
missing = sorted(set(doctor_cmds) - mapping.keys())
if missing:
    raise SystemExit(
        "FAIL: doctor commands lack explicit Arch package mappings: " + ", ".join(missing)
    )

# These aliases are deliberately non-identity mappings. Lock them separately so
# a future cleanup cannot leave a syntactically present but invalid package name.
required_aliases = {
    "qs": "quickshell",
    "nmcli": "networkmanager",
    "wpctl": "wireplumber",
    "python3": "python",
    "magick": "imagemagick",
    "wl-copy": "wl-clipboard",
    "wl-paste": "wl-clipboard",
    "awww-daemon": "awww",
    "notify-send": "libnotify",
    "flock": "util-linux",
    "qalc": "libqalculate",
    "blueman-manager": "blueman",
    "gowall": "gowall-bin",
    "kwriteconfig6": "kconfig",
    "checkupdates": "pacman-contrib",
    "missioncenter": "mission-center",
    "xdg-settings": "xdg-utils",
    "trans": "translate-shell",
}
wrong = [
    f"{cmd}->{mapping.get(cmd)!r} (expected {package!r})"
    for cmd, package in required_aliases.items()
    if mapping.get(cmd) != package
]
if wrong:
    raise SystemExit("FAIL: invalid Arch doctor aliases: " + "; ".join(wrong))

# The fresh default config launches nm-connection-editor directly. Keep its
# doctor route, always-installed source bundle, and orphan-protection tracker in
# lockstep so a clean Arch install cannot pass dependency setup without it.
network_editor = "nm-connection-editor"
if mapping.get(network_editor) != network_editor:
    raise SystemExit(
        f"FAIL: {network_editor} doctor route resolves to {mapping.get(network_editor)!r}"
    )
for package_path, package_text in ((core_path, core), (tracker_path, tracker)):
    if not re.search(rf"^\s+{re.escape(network_editor)}\s*$", package_text, re.M):
        raise SystemExit(f"FAIL: {package_path} is missing required dependency: {network_editor}")

# The default task manager must be installed by the normal source Arch path and
# retained by the staged dependency tracker. The tracker later filters missing
# AUR packages, so this preserves orphan protection without making install fail
# when mission-center itself is unavailable.
task_manager = default_config.get("apps", {}).get("taskManager")
if task_manager != "missioncenter":
    raise SystemExit(f"FAIL: unexpected default task manager command: {task_manager!r}")
if task_manager not in doctor_cmds:
    raise SystemExit(f"FAIL: default task manager is absent from doctor dependencies: {task_manager}")
task_manager_package = mapping.get(task_manager)
if task_manager_package != "mission-center":
    raise SystemExit(
        f"FAIL: default task manager route is {task_manager_package!r}, expected 'mission-center'"
    )
aur_block = re.search(r"^AUR_PACKAGES=\(\n(?P<body>.*?)\n\)", installer, re.S | re.M)
if not aur_block or not re.search(
    rf"^\s*{re.escape(task_manager_package)}\s*$", aur_block.group("body"), re.M
):
    raise SystemExit(f"FAIL: normal Arch install does not install {task_manager_package}")
if not re.search(rf"^\s+{re.escape(task_manager_package)}\s*$", tracker, re.M):
    raise SystemExit(f"FAIL: dependency tracker does not retain {task_manager_package}")

print(f"ok - {len(doctor_cmds)} doctor command dependencies have explicit Arch package routing")
PY
