"""Least-privilege requests to a separate same-user authentication broker.

Workers retain NoNewPrivileges. Passwords can be fetched only inside broker from local Secret Service after
an allowlisted, approved service action. Jobs have no password field.
"""
from __future__ import annotations
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import struct
import subprocess
import time

from automation.manager.store import _write, state_dir
from automation.worker.process import bounded_run
from automation.worker.privacy import SECRET_KEY, redact

OPERATIONS = {"system-service-status", "system-service-restart"}
UNIT = re.compile(r"^[a-zA-Z0-9_.@-]{1,100}\.service$")


def validate(spec):
    if set(spec) != {"operation", "unit", "reason"} or spec["operation"] not in OPERATIONS:
        raise ValueError("privileged operation is not allowlisted")
    if not isinstance(spec["unit"],str) or not UNIT.fullmatch(spec["unit"]):
        raise ValueError("invalid administrator service")
    reason=spec["reason"]
    if not isinstance(reason,str) or not 8<=len(reason)<=300 or SECRET_KEY.search(reason):
        raise ValueError("a clear credential-free reason is required")


def socket_path():
    runtime=Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    return runtime/"hadalis-automation-privilege.sock"


def policy():
    path=Path(os.environ.get("XDG_CONFIG_HOME",str(Path.home()/".config")))/"hadalis/automation-privilege.json"
    if not path.exists():return {"units":[],"authentication":"sudo-cache"}
    data=json.loads(path.read_text())
    if set(data)-{"units","authentication"} or data.get("authentication","sudo-cache") not in {"sudo-cache","polkit"}:
        raise ValueError("invalid administrator policy")
    units=data.get("units",[])
    if not isinstance(units,list) or len(units)>16 or any(not isinstance(x,str) or not UNIT.fullmatch(x) for x in units):
        raise ValueError("invalid administrator service allowlist")
    return {"units":units,"authentication":data.get("authentication","sudo-cache")}


def request(spec, job_id, index):
    validate(spec)
    payload=json.dumps({"key":f"{job_id}:{index}","spec":spec}).encode()
    try:
        with socket.socket(socket.AF_UNIX) as s:
            s.settimeout(40);s.connect(str(socket_path()));s.sendall(payload);s.shutdown(socket.SHUT_WR)
            output=bytearray()
            while chunk:=s.recv(4096):
                output.extend(chunk)
                if len(output)>65536:raise ValueError("broker result exceeds bound")
        return json.loads(output)
    except (OSError,ValueError):
        # A request may have been delivered: never retry automatically.
        return {"status":"indeterminate","exit_code":None,"recovery_required":True,
                "error_code":"administrator_outcome_unknown","timed_out":False,"cancelled":False}


def _broker_control(payload: dict) -> dict:
    """One short same-user Unix socket request; never persist the secret."""
    try:
        with socket.socket(socket.AF_UNIX) as channel:
            channel.settimeout(16)
            channel.connect(str(socket_path()))
            channel.sendall(json.dumps(payload).encode("utf-8"))
            channel.shutdown(socket.SHUT_WR)
            data = channel.recv(2048)
            if not data or len(data) >= 2048:
                raise ValueError("Invalid administrator broker reply")
            response = json.loads(data)
            if not isinstance(response, dict):
                raise ValueError("Invalid administrator broker reply")
            return response
    except (OSError, ValueError, socket.timeout):
        return {"ok": False, "authenticated": False,
                "reason": "ADMINISTRATOR_BROKER_UNAVAILABLE"}


def authenticate(password: str) -> dict:
    """Send transient password to broker; never on argv, disk or GitHub."""
    if (not isinstance(password, str) or not 1 <= len(password) <= 1024
            or any(c in password for c in ("\0", "\r", "\n"))):
        return {"ok": False, "authenticated": False,
                "reason": "INVALID_PASSWORD_INPUT"}
    return _broker_control({"control": "sudo-authenticate", "password": password})


def auth_status() -> dict:
    return _broker_control({"control": "sudo-status"})


def _privilege_auth(payload: dict, *, runner=None) -> dict:
    """Called only by the existing UID-matched broker, never by worker jobs.

    sudo -v primes the broker's own timestamp context, which is also used by
    subsequent allowlisted sudo -n service actions. It does NOT expand the
    existing unit/operation allowlist, and does not store passwords or logs.
    """
    if payload.get("control") not in {"sudo-status", "sudo-authenticate"}:
        return {"ok": False, "authenticated": False,
                "reason": "INVALID_ADMINISTRATOR_CONTROL"}
    operation = payload["control"]
    if operation == "sudo-status":
        if set(payload) != {"control"}:
            return {"ok": False, "authenticated": False,
                    "reason": "INVALID_ADMINISTRATOR_CONTROL"}
    else:
        password = payload.get("password")
        if (set(payload) != {"control", "password"} or
                not isinstance(password, str) or
                not 1 <= len(password) <= 1024 or
                any(c in password for c in ("\0", "\r", "\n"))):
            return {"ok": False, "authenticated": False,
                    "reason": "INVALID_PASSWORD_INPUT"}
    try:
        rules = policy()
    except (OSError, ValueError, json.JSONDecodeError):
        return {"ok": False, "authenticated": False,
                "reason": "INVALID_ADMINISTRATOR_POLICY"}
    if rules["authentication"] != "sudo-cache":
        return {"ok": False, "authenticated": False,
                "reason": "SUDO_CACHE_MODE_NOT_SELECTED"}
    if not rules["units"]:
        return {"ok": False, "authenticated": False,
                "reason": "ADMINISTRATOR_ALLOWLIST_EMPTY"}
    argv = ["/usr/bin/sudo", "-n", "-v"] if operation == "sudo-status" else [
        "/usr/bin/sudo", "-S", "-p", "", "-v"]
    invoke = subprocess.run if runner is None else runner
    env = {k: v for k, v in os.environ.items() if k in (
        "PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL")}
    try:
        output = invoke(argv, input=None if operation == "sudo-status"
                        else password + "\n",
                        text=True, capture_output=True, timeout=12,
                        check=False, env=env)
        success = output.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return {"ok": False, "authenticated": False,
                "reason": "SUDO_AUTHENTICATION_UNAVAILABLE"}
    return {"ok": success, "authenticated": success,
            "reason": "SUDO_CACHE_READY" if success else
            "SUDO_AUTHENTICATION_FAILED"}


def _prime_saved_sudo_for_approved_action(*, runner=None) -> bool:
    """Only called AFTER allowlist and durable action intent.

    Most jobs never call this function and remain entirely unprivileged.
    sudo -n first preserves an existing cache without accessing keyring.
    A saved password is fetched on demand from local Secret Service, never
    from a GitHub job, argv, environment or task receipt.
    """
    execute = subprocess.run if runner is None else runner
    env = {k: v for k, v in os.environ.items() if k in
           {"PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL"}}
    try:
        cached = execute(["/usr/bin/sudo", "-n", "-v"], input=None,
                         text=True, capture_output=True, timeout=8,
                         check=False, env=env)
        if cached.returncode == 0:
            return True
    except (OSError, subprocess.TimeoutExpired):
        return False
    try:
        from automation import sudo_credentials
        secret = sudo_credentials._lookup_for_broker()
    except (ValueError, OSError):
        return False
    if not secret:
        return False
    try:
        authenticated = execute(
            ["/usr/bin/sudo", "-S", "-p", "", "-v"],
            input=secret + "\n", text=True, capture_output=True,
            timeout=12, check=False, env=env)
        return authenticated.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False
    finally:
        # No secret included in returned values or durable receipts.
        secret = None


def handle(payload, executor=bounded_run):
    if set(payload)!={"key","spec"} or not re.fullmatch(r"JOB-[A-Za-z0-9._-]+:[0-9]{1,2}",payload["key"]):
        raise ValueError("invalid administrator request identity")
    spec=payload["spec"];validate(spec)
    root=state_dir()/"privilege";root.mkdir(parents=True,exist_ok=True,mode=0o700);root.chmod(0o700)
    key=hashlib.sha256(payload["key"].encode()).hexdigest()
    path=root/(key+".json");digest=hashlib.sha256(json.dumps(spec,sort_keys=True).encode()).hexdigest()
    with (root/(key+".lock")).open("a+") as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        if path.exists():
            receipt=json.loads(path.read_text())
            if receipt["input_sha256"]!=digest:raise ValueError("administrator request identity reused")
            return receipt.get("result") or {"status":"indeterminate","exit_code":None,"recovery_required":True}
        rules=policy()
        if spec["unit"] not in rules["units"]:
            result={"status":"denied","exit_code":126,"error_code":"administrator_service_not_allowlisted"}
            _write(path,{"key":payload["key"],"input_sha256":digest,"phase":"finished","at_unix":int(time.time()),"reason":spec["reason"],"result":result})
            return result
        operation="restart" if spec["operation"]=="system-service-restart" else "show"
        argv=["/usr/bin/systemctl",operation,spec["unit"]]
        if operation=="show":argv.append("--property=ActiveState,SubState,Result,ExecMainStatus")
        else:argv.append("--no-block")
        # Timeout runs inside the elevated process: a user-process crash or
        # inability to signal a root child cannot leave it running indefinitely.
        argv=["/usr/bin/timeout","--signal=TERM","--kill-after=2s","20s",*argv]
        argv=(["/usr/bin/sudo","-n","--"] if rules["authentication"]=="sudo-cache"
              else ["/usr/bin/pkexec","--disable-internal-agent"]) + argv
        receipt={"key":payload["key"],"input_sha256":digest,"phase":"dispatching","at_unix":int(time.time()),
                 "operation":spec["operation"],"unit":spec["unit"],"reason":spec["reason"],"authentication":rules["authentication"]}
        _write(path,receipt) # Durable audit precedes any authentication or elevation.
        # Production-only on-demand broker privilege; injected test runners
        # must never accidentally invoke real sudo on the CI host.
        if rules["authentication"] == "sudo-cache" and executor is bounded_run:
            _prime_saved_sudo_for_approved_action()
        env={k:v for k,v in os.environ.items() if k in {"PATH","HOME","USER","LANG","DISPLAY","WAYLAND_DISPLAY","XDG_RUNTIME_DIR","DBUS_SESSION_BUS_ADDRESS"}}
        try:
            result=executor(argv,cwd=Path("/"),timeout=30,capture=16384,env=env,
                on_spawn=lambda identity:_write(path,{**receipt,"phase":"executing","process":identity}))
            result["stdout"]=redact(result["stdout"]);result["stderr"]=redact(result["stderr"])
            result["status"]="passed" if result["exit_code"]==0 else "failed"
            if result["status"]!="passed":
                result["error_code"]="administrator_authentication_required" if re.search(r"password is required|not authorized|authentication failed",result["stderr"],re.I) else "administrator_command_failed"
        except Exception:result={"status":"indeterminate","exit_code":None,"recovery_required":True}
        _write(path,{**receipt,"phase":"finished","result":result,"finished_at_unix":int(time.time())})
        return result


def serve():
    path=socket_path()
    with (state_dir()/"privilege-broker.lock").open("a+") as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        path.unlink(missing_ok=True)
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(str(path));path.chmod(0o600);server.listen(8)
            try:
                while True:
                    connection,_=server.accept()
                    with connection:
                        connection.settimeout(3)
                        _,uid,_=struct.unpack("3i",connection.getsockopt(socket.SOL_SOCKET,socket.SO_PEERCRED,12))
                        if uid!=os.getuid():continue
                        try:
                            raw=bytearray()
                            while chunk:=connection.recv(4096):
                                raw.extend(chunk)
                                if len(raw)>8192:raise ValueError("administrator request exceeds bound")
                            payload = json.loads(raw)
                            if isinstance(payload, dict) and "control" in payload:
                                result = _privilege_auth(payload)
                            else:
                                result = handle(payload)
                        except Exception:
                            result={"ok": False, "authenticated": False,
                                    "reason": "INVALID_ADMINISTRATOR_REQUEST"}
                        try:connection.sendall(json.dumps(result).encode())
                        except OSError:pass # Receipt stays usable even if client disappeared.
            finally:path.unlink(missing_ok=True)


if __name__=="__main__":
    state_dir().mkdir(parents=True,exist_ok=True,mode=0o700)
    serve()
