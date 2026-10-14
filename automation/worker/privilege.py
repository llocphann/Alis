"""Least-privilege requests to a separate same-user authentication broker.

Workers retain NoNewPrivileges. Passwords are handled only by the OS agent or
sudo's existing cache; this protocol has no credential field.
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
        _write(path,receipt) # Durable audit precedes the only elevation point.
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
                            result=handle(json.loads(raw))
                        except Exception:result={"status":"denied","exit_code":126,"error_code":"invalid_administrator_request"}
                        try:connection.sendall(json.dumps(result).encode())
                        except OSError:pass # Receipt stays usable even if client disappeared.
            finally:path.unlink(missing_ok=True)


if __name__=="__main__":
    state_dir().mkdir(parents=True,exist_ok=True,mode=0o700)
    serve()
