#!/usr/bin/env python3
"""Silent, zero-focus virtual Wayland compositor harness for Qt / Quickshell tests.

Always isolates execution off the user's live desktop using `kwin_wayland --virtual`
(with an optional nested `niri` inside the virtual KWin display when a test requires
`NIRI_SOCKET`, `wlr-screencopy`, or `wlr-virtual-pointer`). Never maps visible windows
onto the host `WAYLAND_DISPLAY` and never steals host window focus.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time


def _terminate_pg(process: subprocess.Popen | None, grace: float = 3.0) -> None:
    if process is None or process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=grace)
    except Exception:
        try:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=2.0)
        except Exception:
            pass


def run_qs(folder: Path, env: dict, timeout: int = 25):
    """Bound and clean up the test's whole process group in silent mode."""
    env = dict(env)
    real_home = Path.home().resolve()
    real_xdg_defaults = {
        "config": real_home / ".config",
        "state": real_home / ".local" / "state",
        "cache": real_home / ".cache",
        "data": real_home / ".local" / "share",
    }
    for kind, real_dir in real_xdg_defaults.items():
        var_name = f"XDG_{kind.upper()}_HOME"
        cur = env.get(var_name, "")
        if not cur or Path(cur).resolve() == real_dir:
            isolated = folder / kind
            isolated.mkdir(parents=True, exist_ok=True)
            env[var_name] = str(isolated)

    # Never inherit the live desktop WAYLAND_DISPLAY if caller requested offscreen or forgot private_wayland.
    host_wayland = os.environ.get("WAYLAND_DISPLAY", "")
    preset_socket = env.get("ALIS_TEST_WAYLAND_SOCKET") or os.environ.get("ALIS_TEST_WAYLAND_SOCKET")
    if preset_socket and Path(preset_socket).exists() and env.get("QT_QPA_PLATFORM") == "offscreen":
        sock_path = Path(preset_socket)
        env = dict(
            env,
            XDG_RUNTIME_DIR=str(sock_path.parent),
            WAYLAND_DISPLAY=sock_path.name,
            QT_QPA_PLATFORM="wayland",
        )
    elif env.get("QT_QPA_PLATFORM") != "wayland" or (
        host_wayland
        and env.get("WAYLAND_DISPLAY") == host_wayland
        and env.get("XDG_RUNTIME_DIR") == os.environ.get("XDG_RUNTIME_DIR")
    ):
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("NIRI_SOCKET", None)
        env.pop("DISPLAY", None)
        env["QT_QPA_PLATFORM"] = "offscreen"

    command = ["dbus-run-session", "--", "qs", "-p", str(folder), "--no-color"]
    log = folder / "native-test-qs.log"
    with log.open("wb") as stream:
        process = subprocess.Popen(
            command,
            env=dict(env, LC_ALL="C.UTF-8", QT_NO_XDG_DESKTOP_PORTAL="1"),
            stdout=stream,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    try:
        code = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        _terminate_pg(process, grace=3.0)
        code = 124
    return subprocess.CompletedProcess(command, code, log.read_text(errors="replace"), "")


@contextmanager
def private_wayland(
    folder: Path,
    *,
    capture_focus: bool = False,
    need_niri: bool = False,
    isolate_xdg: bool = True,
):
    """Yield an invisible, zero-focus Wayland environment backed by `kwin_wayland --virtual`."""
    test_bin = folder / ".test-bin"
    test_bin.mkdir(parents=True, exist_ok=True)
    for mock_cmd, mock_out in (
        ("wpctl", 'if [ "${1:-}" = "get-volume" ]; then echo "Volume: 0.50"; fi'),
        (
            "brightnessctl",
            'if [ "${1:-}" = "info" ] || [ "${1:-}" = "-m" ] || [ "${1:-}" = "-l" ]; then echo "backlight,backlight,100,50%,200"; '
            'elif [ "${1:-}" = "g" ]; then echo "100"; elif [ "${1:-}" = "m" ]; then echo "200"; fi',
        ),
        ("playerctl", 'if [ "${1:-}" = "status" ]; then echo "Stopped"; fi'),
    ):
        mock_path = test_bin / mock_cmd
        mock_path.write_text(f"#!/bin/sh\n{mock_out}\nexit 0\n", encoding="utf-8")
        mock_path.chmod(0o755)

    fake_sysfs = folder / ".fake-backlight"
    if not os.environ.get("ALIS_BACKLIGHT_SYSFS_DIR"):
        dev = fake_sysfs / "test_bl0"
        dev.mkdir(parents=True, exist_ok=True)
        (dev / "brightness").write_text("100\n", encoding="utf-8")
        (dev / "max_brightness").write_text("200\n", encoding="utf-8")

    env = dict(
        os.environ,
        LC_ALL="C.UTF-8",
        PATH=f"{test_bin}{os.pathsep}{os.environ.get('PATH', '')}",
        ALIS_SILENT_TEST_MODE="1",
    )
    if not os.environ.get("ALIS_BACKLIGHT_SYSFS_DIR"):
        env["ALIS_BACKLIGHT_SYSFS_DIR"] = str(fake_sysfs)

    for key in (
        "WAYLAND_DISPLAY",
        "NIRI_SOCKET",
        "HYPRLAND_INSTANCE_SIGNATURE",
        "DISPLAY",
        "QS_CONFIG_NAME",
        "QS_CONFIG_PATH",
        "QS_MANIFEST",
    ):
        env.pop(key, None)

    if isolate_xdg:
        for kind in ("config", "state", "cache", "data"):
            target_dir = folder / kind
            target_dir.mkdir(parents=True, exist_ok=True)
            env[f"XDG_{kind.upper()}_HOME"] = str(target_dir)

    preset_socket = os.environ.get("ALIS_TEST_WAYLAND_SOCKET", "")
    if preset_socket and Path(preset_socket).exists() and not need_niri:
        sock_path = Path(preset_socket)
        env.update(
            XDG_RUNTIME_DIR=str(sock_path.parent),
            WAYLAND_DISPLAY=sock_path.name,
            QT_QPA_PLATFORM="wayland",
        )
        if capture_focus:
            (folder / "native-test-capture-focus.json").write_text(
                json.dumps({"private_pid": 0, "previous": None, "owned": None, "silent_mode": True}, indent=2) + "\n",
                encoding="utf-8",
            )
        yield env
        return

    kwin = shutil.which("kwin_wayland")
    if not kwin:
        # Never fall back to a visible window on the user's live compositor.
        if need_niri:
            yield None
            return
        env["QT_QPA_PLATFORM"] = "offscreen"
        if capture_focus:
            (folder / "native-test-capture-focus.json").write_text(
                json.dumps({"private_pid": 0, "previous": None, "owned": None, "silent_mode": True}, indent=2) + "\n",
                encoding="utf-8",
            )
        yield env
        return

    kwin_runtime = folder / ".kwin-runtime"
    kwin_runtime.mkdir(mode=0o700, exist_ok=True)
    kwin_sock_name = "wayland-headless-0"
    kwin_sock_path = kwin_runtime / kwin_sock_name
    kwin_env = dict(env, XDG_RUNTIME_DIR=str(kwin_runtime), QT_QPA_PLATFORM="wayland")
    kwin_log = folder / "native-test-kwin.log"
    kwin_process: subprocess.Popen | None = None
    niri_process: subprocess.Popen | None = None
    niri_runtime: Path | None = None
    reserved_locks: list = []

    try:
        with kwin_log.open("wb") as stream:
            kwin_process = subprocess.Popen(
                [
                    kwin,
                    "--virtual",
                    "--no-lockscreen",
                    "--no-global-shortcuts",
                    "--width",
                    "1920",
                    "--height",
                    "1080",
                    "--socket",
                    kwin_sock_name,
                ],
                env=kwin_env,
                stdout=stream,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )

        deadline = time.monotonic() + 10.0
        while time.monotonic() < deadline:
            if kwin_process.poll() is not None:
                raise RuntimeError("Headless kwin_wayland exited: " + kwin_log.read_text(errors="replace")[-2000:])
            if kwin_sock_path.exists():
                break
            time.sleep(0.05)
        else:
            raise RuntimeError("Headless kwin_wayland did not publish socket")

        if not need_niri:
            kwin_env.update(
                WAYLAND_DISPLAY=kwin_sock_name,
                ALIS_TEST_WAYLAND_SOCKET=str(kwin_sock_path),
            )
            if capture_focus:
                (folder / "native-test-capture-focus.json").write_text(
                    json.dumps(
                        {"private_pid": kwin_process.pid, "previous": None, "owned": None, "silent_mode": True},
                        indent=2,
                    )
                    + "\n",
                    encoding="utf-8",
                )
            yield kwin_env
            return

        niri = shutil.which("niri")
        if not niri:
            yield None
            return

        niri_runtime = folder / ".niri-runtime"
        niri_runtime.mkdir(mode=0o700, exist_ok=True)
        host_wl_name = os.environ.get("WAYLAND_DISPLAY", "")
        for reserved_name in {"wayland-0", host_wl_name}:
            if reserved_name and "/" not in reserved_name:
                lock_fp = (niri_runtime / f"{reserved_name}.lock").open("w")
                fcntl.flock(lock_fp.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                reserved_locks.append(lock_fp)
        config = folder / "native-test.kdl"
        config.write_text(
            'prefer-no-csd\n'
            'hotkey-overlay {\n skip-at-startup\n}\n'
            'layout {\n background-color "#111820"\n'
            ' default-column-width { proportion 1.0; }\n}\n'
            'overview {\n backdrop-color "#111820"\n}\n',
            encoding="utf-8",
        )
        niri_env = dict(
            env,
            XDG_RUNTIME_DIR=str(niri_runtime),
            WAYLAND_DISPLAY=str(kwin_sock_path),
            NIRI_CONFIG=str(config),
            RUST_LOG="niri=info",
        )
        niri_log = folder / "native-test-niri.log"
        with niri_log.open("wb") as nstream:
            niri_process = subprocess.Popen(
                [niri],
                env=niri_env,
                stdout=nstream,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )

        ndeadline = time.monotonic() + 12.0
        while time.monotonic() < ndeadline:
            if niri_process.poll() is not None:
                raise RuntimeError("Headless nested Niri exited: " + niri_log.read_text(errors="replace")[-2000:])
            text = niri_log.read_text(errors="replace")
            displays = re.findall(r"listening on Wayland socket:\s*(wayland-[0-9]+)", text)
            sockets = re.findall(r"IPC listening on:\s*(/\S+?\.sock)(?:\s|$)", text)
            if displays and sockets and (niri_runtime / displays[-1]).exists():
                sock = Path(sockets[-1])
                if sock.is_socket():
                    client_env = dict(
                        env,
                        XDG_RUNTIME_DIR=str(niri_runtime),
                        WAYLAND_DISPLAY=displays[-1],
                        NIRI_SOCKET=str(sock),
                        QT_QPA_PLATFORM="wayland",
                        ALIS_TEST_WAYLAND_SOCKET=str(niri_runtime / displays[-1]),
                    )
                    if capture_focus:
                        (folder / "native-test-capture-focus.json").write_text(
                            json.dumps(
                                {"private_pid": niri_process.pid, "previous": None, "owned": None, "silent_mode": True},
                                indent=2,
                            )
                            + "\n",
                            encoding="utf-8",
                        )
                    yield client_env
                    return
            time.sleep(0.05)

        raise RuntimeError("Headless nested Niri did not publish socket: " + niri_log.read_text(errors="replace")[-2000:])
    finally:
        _terminate_pg(niri_process, grace=3.0)
        _terminate_pg(kwin_process, grace=3.0)
        for lock_fp in reserved_locks:
            try:
                lock_fp.close()
            except Exception:
                pass
        if niri_runtime is not None:
            shutil.rmtree(niri_runtime, ignore_errors=True)
        shutil.rmtree(kwin_runtime, ignore_errors=True)


def _cli_main() -> int:
    parser = argparse.ArgumentParser(description="Run a command inside a silent, zero-focus virtual Wayland session.")
    parser.add_argument("--need-niri", action="store_true", help="Spawn nested Niri inside virtual KWin (for grim/IPC)")
    parser.add_argument("--keep-xdg", action="store_true", help="Preserve caller XDG_*_HOME directories")
    parser.add_argument("cmd", nargs=argparse.REMAINDER, help="Command to execute (after --)")
    args = parser.parse_args()
    cmd = list(args.cmd)
    if cmd and cmd[0] == "--":
        cmd = cmd[1:]
    if not cmd:
        parser.error("missing command after --")
    if cmd[0].endswith(".sh") and not os.access(cmd[0], os.X_OK):
        cmd = ["bash", *cmd]

    with tempfile.TemporaryDirectory(prefix="alis-silent-wl-") as tmp:
        with private_wayland(Path(tmp), need_niri=args.need_niri, isolate_xdg=not args.keep_xdg) as wl_env:
            if wl_env is None:
                print("SKIP: silent virtual Wayland compositor unavailable")
                return 0
            # Preserve explicit caller env overrides like XDG_CONFIG_HOME or ANTI_TEST_*
            for key in ("XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "PATH"):
                if key in os.environ and args.keep_xdg:
                    wl_env[key] = os.environ[key]
            proc = subprocess.run(cmd, env=wl_env)
            return proc.returncode


if __name__ == "__main__":
    raise SystemExit(_cli_main())
