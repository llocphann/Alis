"""Bounded pipe draining and process-group cancellation, independent of QML."""
from __future__ import annotations
import hashlib
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import time


def session_env(keys):
    """Observe only allowlisted runtime sockets, including services started at boot."""
    env={k:v for k,v in os.environ.items() if k in keys}
    runtime=Path(os.environ.get("XDG_RUNTIME_DIR",f"/run/user/{os.getuid()}"))
    if runtime.is_dir():
        env["XDG_RUNTIME_DIR"]=str(runtime)
        for variable,pattern in (("WAYLAND_DISPLAY","wayland-*"),("NIRI_SOCKET","niri.*.sock")):
            if variable not in env:
                matches=[p for p in runtime.glob(pattern) if p.is_socket()][:2]
                if len(matches)==1:env[variable]=matches[0].name if variable=="WAYLAND_DISPLAY" else str(matches[0])
        if "DBUS_SESSION_BUS_ADDRESS" not in env and (runtime/"bus").is_socket():
            env["DBUS_SESSION_BUS_ADDRESS"]="unix:path="+str(runtime/"bus")
    return env


def process_identity(pid: int) -> dict | None:
    try:
        stat = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
        return {"pid":pid, "start_ticks":stat[19], "boot_id":Path("/proc/sys/kernel/random/boot_id").read_text().strip()}
    except (OSError, IndexError):
        return None


def is_same_process(identity: dict | None) -> bool:
    return bool(identity and process_identity(identity["pid"]) == identity)


def kill_group(pid: int) -> None:
    try: os.killpg(pid, signal.SIGTERM)
    except ProcessLookupError: return
    deadline=time.monotonic()+0.5
    while time.monotonic()<deadline:
        try: os.killpg(pid,0)
        except ProcessLookupError:return
        time.sleep(0.02)
    try:os.killpg(pid,signal.SIGKILL)
    except ProcessLookupError:pass


def bounded_run(argv: list[str], *, cwd: Path, timeout: float, env=None,
                capture: int = 65536, cancelled=lambda:False, on_spawn=lambda p:None,
                execution_receipt: Path | None = None) -> dict:
    if execution_receipt:
        argv=[sys.executable,str(Path(__file__).with_name("child.py")),str(os.getpid()),str(execution_receipt),*argv]
    process=subprocess.Popen(argv,cwd=cwd,env=env,stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
    buffers={"stdout":bytearray(),"stderr":bytearray()}
    hashes={name:hashlib.sha256() for name in buffers};counts={name:0 for name in buffers}
    timed_out=False;was_cancelled=False;ended_at=None
    deadline=time.monotonic()+timeout
    try:
        on_spawn(process_identity(process.pid))
        with selectors.DefaultSelector() as selector:
            for name, stream in (("stdout",process.stdout),("stderr",process.stderr)):
                os.set_blocking(stream.fileno(),False);selector.register(stream,selectors.EVENT_READ,name)
            while selector.get_map():
                now=time.monotonic()
                if not timed_out and not was_cancelled and (now>=deadline or cancelled()):
                    timed_out=now>=deadline;was_cancelled=not timed_out;kill_group(process.pid)
                if process.poll() is not None:
                    ended_at=ended_at or now
                    if now-ended_at>0.5: kill_group(process.pid)
                for key,_ in selector.select(0.1):
                    chunk=os.read(key.fileobj.fileno(),16384)
                    if not chunk:selector.unregister(key.fileobj);continue
                    name=key.data;hashes[name].update(chunk);counts[name]+=len(chunk)
                    room=max(0,capture-len(buffers[name]))
                    buffers[name].extend(chunk[:room])
                # A malicious inherited fd or detached descendant cannot keep
                # the observation alive past its hard deadline.
                if now>deadline+2 or (ended_at and now-ended_at>2):break
        process.wait(timeout=2)
    finally:
        kill_group(process.pid)
        if process.poll() is None:process.kill();process.wait(timeout=2)
        process.stdout.close();process.stderr.close()
    return {"exit_code":process.returncode,"timed_out":timed_out,"cancelled":was_cancelled,
        **{name:bytes(buf).decode("utf-8",errors="replace") for name,buf in buffers.items()},
        **{name+"_bytes":counts[name] for name in counts},
        **{name+"_sha256":hashes[name].hexdigest() for name in hashes},
        **{name+"_truncated":counts[name]>capture for name in counts}}
