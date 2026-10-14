"""One bounded deterministic job; durable action receipts precede every spawn."""
from __future__ import annotations
import ctypes
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import sys
import time

sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from automation.manager.store import _write
from automation.worker.process import bounded_run, process_identity, session_env
from automation.worker.privacy import redact

ENV_KEYS={"PATH","HOME","USER","LOGNAME","LANG","LC_ALL","DISPLAY","WAYLAND_DISPLAY",
    "XDG_RUNTIME_DIR","NIRI_SOCKET","DBUS_SESSION_BUS_ADDRESS","XDG_STATE_HOME"}
_CANCELLED=False


def restrict() -> None:
    # Applies to this runner and descendants, including manual --once runs.
    if sys.platform.startswith("linux"):
        libc=ctypes.CDLL(None,use_errno=True)
        if libc.prctl(38,1,0,0,0)!=0:raise OSError("cannot enforce no-new-privileges")
        # Parent-death signal plus process-group cleanup covers daemon crashes.
        parent=os.getppid()
        libc.prctl(1,signal.SIGTERM,0,0,0)
        if os.getppid()!=parent:os.kill(os.getpid(),signal.SIGTERM)
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    resource.setrlimit(resource.RLIMIT_NOFILE,(512,512))
    resource.setrlimit(resource.RLIMIT_AS,(8*1024**3,8*1024**3))
    resource.setrlimit(resource.RLIMIT_CPU,(3600,3605))


def cancelled(signum=None, frame=None):
    global _CANCELLED
    if signum is not None:_CANCELLED=True
    return _CANCELLED


def execute_spec(spec: dict) -> dict:
    root=Path(spec["receipt_dir"]);root.mkdir(parents=True,exist_ok=True,mode=0o700)
    job=spec["job"];workspace=Path(spec["workspace"]).resolve()
    output=[];status="passed"
    for index,action in enumerate(job["actions"]):
        path=root/f"action-{index}.json"
        if path.exists():
            prior=json.loads(path.read_text())
            if prior.get("phase")!="finished":
                status="indeterminate";break # Never repeat an ambiguous external action.
            result=prior["result"];output.append(result)
            if result.get("exit_code")!=0:
                status="cancelled" if result.get("cancelled") else "failed";break
            continue
        kind=next(iter(action));body=action[kind]
        intent={"phase":"dispatching","index":index,"kind":kind,"at_unix":int(time.time()),
                "runner":process_identity(os.getpid())}
        _write(path,intent)
        if cancelled() or (root.parent.parent/"cancellations"/job["id"]).exists():
            result={"index":index,"kind":kind,"exit_code":None,"cancelled":True,"timed_out":False}
            status="cancelled"
        elif kind=="exec":
            cwd=(workspace/body.get("cwd",".")).resolve()
            if cwd!=workspace and workspace not in cwd.parents:raise ValueError("cwd escapes workspace")
            argv=body["argv"]
            def spawned(identity):
                intent.update(phase="executing",process=identity);_write(path,intent)
            result=bounded_run(argv,cwd=cwd,timeout=body.get("timeout_seconds",600),
                env=session_env(ENV_KEYS),capture=spec["capture"],
                cancelled=lambda:cancelled() or (root.parent.parent/"cancellations"/job["id"]).exists(),
                on_spawn=spawned,execution_receipt=path)
            result.update(index=index,kind=kind,command_sha256=hashlib.sha256(json.dumps(argv).encode()).hexdigest())
            # Even private evidence must not become a credential store.
            result["stdout"]=redact(result["stdout"]);result["stderr"]=redact(result["stderr"])
            status="cancelled" if result["cancelled"] else "failed" if result["timed_out"] or result["exit_code"] else "passed"
        elif kind=="diagnostics":
            from automation.worker.diagnostics import collect
            result=collect(body,workspace,root/index.__str__())
            result.update(index=index,kind=kind,exit_code=0,timed_out=False,cancelled=False)
        elif kind=="privileged":
            from automation.worker.privilege import request
            result=request(body,job["id"],index)
            result.update(index=index,kind=kind)
            status=result.get("status","failed")
        elif kind=="shell_deploy":
            from automation.worker.deployment import deploy
            result=deploy(body,workspace,f"{job['id']}-{index}")
            result.update(index=index,kind=kind)
            status=result.get("status","failed")
        else:raise ValueError("unknown action kind")
        result["evidence_id"]=f"{job['id']}:{index}"
        result["source_sha"]=spec["commit"]
        result["observed_at_unix"]=int(time.time())
        _write(path,{**intent,"phase":"finished","result":result})
        output.append(result)
        if status!="passed":break
    return {"job":job["id"],"base_sha":job["base_sha"],"job_commit":spec["commit"],
        "profile_id":job.get("profile_id"),"input_sha256":spec["input_sha256"],
        "status":status,"started_at_unix":spec["started_at_unix"],"finished_at_unix":int(time.time()),
        "actions":output,**({"recovery_required":True} if status=="indeterminate" else {})}


def main():
    signal.signal(signal.SIGTERM,cancelled);signal.signal(signal.SIGINT,cancelled)
    restrict()
    path=Path(sys.argv[1]);spec=json.loads(path.read_text())
    result=execute_spec(spec)
    _write(path.with_name("result.json"),result)
    return 0


if __name__=="__main__":raise SystemExit(main())
