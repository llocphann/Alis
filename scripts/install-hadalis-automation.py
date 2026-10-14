#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]


def require_command(name: str) -> str:
    path = shutil.which(name)
    if path is None:
        raise SystemExit(f"required command not found: {name}")
    return path


def quote(value: str | Path) -> str:
    text = str(value)
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def environment(name: str, value: str | Path) -> str:
    # systemd Environment= parses shell-like words, not shell assignments.
    # Quote the complete NAME=VALUE token; quoting only the RHS can be
    # rejected as an invalid environment assignment on current systemd.
    return f"Environment={quote(f'{name}={value}')}"


def write_unit(path: Path, content: str) -> None:
    path.write_text(content.rstrip() + "\n", encoding="utf-8")
    print(f"wrote {path}")


def install_control_endpoint():
    """Old repo-copy frontends delegate before they can normalize v2 state."""
    from automation.manager.store import _write
    data=Path(os.environ.get("XDG_DATA_HOME",str(Path.home()/".local/share")))/"hadalis-automation"
    data.mkdir(parents=True,exist_ok=True)
    _write(data/"backend.json",{"version":2,"source":str(ROOT)})
    launcher=("#!/usr/bin/env python3\nimport runpy\n"
              f"runpy.run_path({str(ROOT/'scripts/hadalis-automation-control.py')!r},run_name='__main__')\n")
    from automation.worker.deployment import atomic_file
    atomic_file(data/"control.py",launcher.encode())
    shells=Path(os.environ.get("XDG_CONFIG_HOME",str(Path.home()/".config")))/"quickshell"
    for path in shells.glob("*/scripts/hadalis-automation-control.py"):
        if path.resolve()==(ROOT/"scripts/hadalis-automation-control.py").resolve():continue
        # Save the old frontend privately before replacing its control interface.
        import hashlib
        from automation.manager.store import state_dir
        _write(state_dir()/"frontend-migration"/(hashlib.sha256(str(path).encode()).hexdigest()+".json"),
               {"path":str(path),"previous_control":path.read_text(),"backend_source":str(ROOT)})
        atomic_file(path,launcher.encode())


def install_desktop_launcher(chatgpt: str) -> Path | None:
    """Make ordinary menu/autostart launches compatible with the CDP host.

    Electron's single-instance launcher cannot add debugging flags to an
    already-running app. Preserve the existing desktop entry's metadata and
    actions; only its main Exec command changes in a user-local override.
    """
    data_home = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share")))
    data_dirs = [data_home] + [Path(p) for p in os.environ.get(
        "XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":") if p]
    source = next((p / "applications/chatgpt.desktop" for p in data_dirs
                   if (p / "applications/chatgpt.desktop").is_file()), None)
    if source is None:
        print("ChatGPT desktop entry unavailable; use hadalis-chatgpt.service to launch")
        return None
    executable = chatgpt.replace("%", "%%")
    for char in ("\\", '"', "`", "$"):
        executable = executable.replace(char, "\\" + char)
    # Exec is parsed once as a desktop-entry string and once as argv.
    executable = executable.replace("\\", "\\\\")
    command = (f'Exec="{executable}" --remote-debugging-address=127.0.0.1 '
               '--remote-debugging-port=9222 %U')
    lines = source.read_text(encoding="utf-8").splitlines()
    in_main = False
    replaced = False
    for i, line in enumerate(lines):
        if line.startswith("["):
            in_main = line == "[Desktop Entry]"
        elif in_main and line.startswith("Exec="):
            lines[i] = command
            replaced = True
    if not replaced:
        raise RuntimeError(f"ChatGPT desktop entry has no main Exec command: {source}")
    target = data_home / "applications/chatgpt.desktop"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {target}")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Install Hadalis autonomous user services"
    )
    parser.add_argument(
        "--enable-now",
        action="store_true",
        help="also enable and start the installed services",
    )
    parser.add_argument(
        "--reset-session-state",
        action="store_true",
        help=(
            "safely clear persisted bridge session state before service startup; "
            "fails if another bridge instance currently holds the lock"
        ),
    )
    parser.add_argument("--push-remote",default=os.environ.get("HADALIS_WORKER_PUSH_REMOTE"),
                        help="optional credential-free worker publication remote (for example an SSH Git URL)")
    args = parser.parse_args()
    if args.push_remote and (urlparse(args.push_remote).password or any(ch.isspace() for ch in args.push_remote)):
        raise ValueError("worker push remote cannot contain credentials or whitespace")

    import sys
    sys.path.insert(0,str(ROOT))
    install_control_endpoint()

    python = require_command("python3")
    chatgpt = require_command("chatgpt")
    require_command("git")
    require_command("node")
    systemctl = require_command("systemctl")

    units = Path.home() / ".config" / "systemd" / "user"
    units.mkdir(parents=True, exist_ok=True)

    write_unit(
        units / "hadalis-chatgpt.service",
        f"""[Unit]
Description=ChatGPT Desktop for Hadalis automation
PartOf=graphical-session.target

[Service]
Type=simple
WorkingDirectory={ROOT}
ExecStart={quote(python)} -m automation.chat_bridge.desktop_host
{environment("PYTHONUNBUFFERED", "1")}
{environment("HADALIS_CHATGPT_BIN", chatgpt)}
{environment("HADALIS_CHATGPT_CDP_URL", "http://127.0.0.1:9222")}
Restart=on-failure
RestartPreventExitStatus=76
RestartSec=3

[Install]
WantedBy=graphical-session.target
""",
    )

    write_unit(
        units / "hadalis-worker.service",
        f"""[Unit]
Description=Hadalis deterministic local worker

[Service]
Type=simple
WorkingDirectory={ROOT}
ExecStart={quote(python)} {quote(ROOT / "automation" / "worker" / "daemon.py")}
{environment("PYTHONUNBUFFERED", "1")}
{environment("HADALIS_WORKER_PUSH_REMOTE", args.push_remote) if args.push_remote else ""}
Restart=on-failure
RestartSec=3
KillMode=control-group
TimeoutStopSec=10
TasksMax=256
MemoryMax=2G
CPUQuota=200%
NoNewPrivileges=yes

[Install]
WantedBy=default.target
""",
    )

    write_unit(
        units / "hadalis-chat-bridge.service",
        f"""[Unit]
Description=Hadalis deterministic ChatGPT bridge

[Service]
Type=simple
WorkingDirectory={ROOT}
ExecStart={quote(python)} -m automation.manager.daemon
{environment("PYTHONUNBUFFERED", "1")}
{environment("HADALIS_CHATGPT_CDP_URL", "http://127.0.0.1:9222")}
Restart=on-failure
RestartPreventExitStatus=75
RestartSec=3
KillMode=control-group
TimeoutStopSec=10
TasksMax=128
MemoryMax=512M
NoNewPrivileges=yes

[Install]
WantedBy=default.target
""",
    )

    write_unit(units/"hadalis-privilege.service",f"""[Unit]
Description=Hadalis allowlisted administrator broker

[Service]
Type=simple
WorkingDirectory={ROOT}
ExecStart={quote(python)} -m automation.worker.privilege
{environment("PYTHONUNBUFFERED", "1")}
Restart=on-failure
RestartSec=3
KillMode=control-group
TimeoutStopSec=10
TasksMax=32
MemoryMax=128M

[Install]
WantedBy=default.target
""")

    install_desktop_launcher(chatgpt)
    subprocess.run([systemctl, "--user", "daemon-reload"], check=True)

    systemd_analyze = shutil.which("systemd-analyze")
    if systemd_analyze is not None:
        subprocess.run(
            [
                systemd_analyze,
                "--user",
                "verify",
                str(units / "hadalis-chatgpt.service"),
                str(units / "hadalis-worker.service"),
                str(units / "hadalis-chat-bridge.service"),
                str(units / "hadalis-privilege.service"),
            ],
            check=True,
        )

    if args.reset_session_state:
        subprocess.run(
            [
                python,
                "-m",
                "automation.manager.daemon",
                "--reset-state",
            ],
            cwd=ROOT,
            check=True,
        )

    if args.enable_now:
        subprocess.run(
            [
                systemctl,
                "--user",
                "enable",
                "--now",
                "hadalis-chatgpt.service",
                "hadalis-worker.service",
                "hadalis-chat-bridge.service",
                "hadalis-privilege.service",
            ],
            check=True,
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
