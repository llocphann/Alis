"""Private, dark Niri window for Qt tests that require a layer-shell backend."""
from contextlib import contextmanager
from pathlib import Path
import json, os, re, shutil, signal, subprocess, time


def run_qs(folder: Path, env: dict, timeout: int = 25):
    """Bound and clean up the test's whole process group, retaining diagnostics."""
    command = ["dbus-run-session", "--", "qs", "-p", str(folder), "--no-color"]
    log = folder / "native-test-qs.log"
    with log.open("wb") as stream:
        process = subprocess.Popen(command, env=dict(env,QT_NO_XDG_DESKTOP_PORTAL="1"), stdout=stream,
                                   stderr=subprocess.STDOUT, start_new_session=True)
    try:
        code = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try: process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=3)
        code = 124
    return subprocess.CompletedProcess(command, code, log.read_text(errors="replace"), "")


def _host_query(niri: str, env: dict, topic: str):
    result = subprocess.run([niri, "msg", "--json", topic], env=env,
                            capture_output=True, text=True, timeout=3)
    if result.returncode:
        raise RuntimeError("Capture focus query failed: " + result.stderr[-400:])
    return json.loads(result.stdout)


def _focus_for_capture(niri: str, pid: int, host_env: dict):
    """Focus only this private compositor, preserving a known previous target."""
    before = _host_query(niri, host_env, "focused-window")
    if not before:
        raise RuntimeError("Capture focus requires a restorable parent window")
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        windows = _host_query(niri, host_env, "windows")
        owned = [window for window in windows if window.get("pid") == pid]
        if len(owned) == 1:
            target = owned[0]["id"]
            subprocess.run([niri, "msg", "action", "focus-window", "--id", str(target)],
                           env=host_env, capture_output=True, text=True,
                           timeout=3, check=True)
            return before["id"], target
        time.sleep(.1)
    raise RuntimeError("Capture focus could not identify the private Niri window")


def _restore_capture_focus(niri: str, targets: tuple, host_env: dict):
    previous, owned = targets
    current = _host_query(niri, host_env, "focused-window")
    # A user changing focus during the capture owns that choice.
    if current and current["id"] == owned and any(
            window["id"] == previous for window in _host_query(niri, host_env, "windows")):
        subprocess.run([niri, "msg", "action", "focus-window", "--id", str(previous)],
                       env=host_env, capture_output=True, text=True, timeout=3, check=True)


@contextmanager
def private_wayland(folder: Path, *, capture_focus: bool = False):
    niri = shutil.which("niri")
    host_display = os.environ.get("WAYLAND_DISPLAY", "")
    if not niri or not host_display:
        yield None
        return
    config = folder / "native-test.kdl"
    # Qt client decorations otherwise clear white even with a dark canvas.
    config.write_text('prefer-no-csd\n'
                      'hotkey-overlay {\n skip-at-startup\n}\n'
                      'layout {\n background-color "#111820"\n'
                      ' default-column-width { proportion 1.0; }\n}\n'
                      'overview {\n backdrop-color "#111820"\n}\n')
    env = dict(os.environ, NIRI_CONFIG=str(config), RUST_LOG="niri=info")
    env.pop("NIRI_SOCKET", None)
    for kind in ["config", "state", "cache", "data"]:
        env[f"XDG_{kind.upper()}_HOME"] = str(folder / kind)
        (folder / kind).mkdir(exist_ok=True)
    log = folder / "native-test-niri.log"
    process = None
    capture_targets = None
    host_env = dict(os.environ)
    try:
        with log.open("wb") as stream:
            process = subprocess.Popen([niri], env=env, stdout=stream,
                                       stderr=subprocess.STDOUT, start_new_session=True)
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError("Private Niri exited: " + log.read_text()[-2000:])
            text = log.read_text(errors="replace")
            displays = re.findall(r"listening on Wayland socket:\s*(wayland-[0-9]+)", text)
            sockets = re.findall(r"IPC listening on:\s*(/\S+?\.sock)(?:\s|$)", text)
            if displays and sockets and displays[-1] != host_display:
                socket = Path(sockets[-1])
                if socket.is_socket() and str(socket) != os.environ.get("NIRI_SOCKET"):
                    env.update(WAYLAND_DISPLAY=displays[-1], NIRI_SOCKET=str(socket),
                               QT_QPA_PLATFORM="wayland")
                    for key in ["QS_CONFIG_NAME", "QS_CONFIG_PATH", "QS_MANIFEST"]:
                        env.pop(key, None)
                    if capture_focus:
                        capture_targets = _focus_for_capture(niri, process.pid, host_env)
                        (folder / "native-test-capture-focus.json").write_text(json.dumps({
                            "private_pid": process.pid, "previous": capture_targets[0],
                            "owned": capture_targets[1]}, indent=2) + "\n")
                    yield env
                    return
            time.sleep(.1)
        raise RuntimeError("Private Niri did not publish a distinct socket: "
                           + log.read_text(errors="replace")[-2400:])
    finally:
        if capture_targets is not None:
            try:
                _restore_capture_focus(niri, capture_targets, host_env)
            except (RuntimeError, subprocess.SubprocessError):
                # The host/previous window may have closed; private cleanup
                # still must run, and no unrelated target is substituted.
                pass
        if process is not None and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=4)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=3)
            except ProcessLookupError:
                pass
