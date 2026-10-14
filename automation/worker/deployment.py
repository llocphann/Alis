"""Validated file deployment with durable rollback outside the shell process."""
from __future__ import annotations
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
import time

from automation.manager.store import _write, _sync_directory, state_dir
from automation.worker.process import bounded_run, process_identity, is_same_process


def validate(spec):
    if set(spec)-{"family","files","reason"} or spec.get("family") not in {"inir","waffle"}:
        raise ValueError("deployment family is not allowlisted")
    files=spec.get("files")
    if not isinstance(files,list) or not 1<=len(files)<=64 or len(set(files))!=len(files):
        raise ValueError("deployment requires 1..64 unique files")
    for name in files:
        if not isinstance(name,str) or len(name)>256 or Path(name).is_absolute() or ".." in Path(name).parts or Path(name).suffix not in {".qml",".js",".json"}:
            raise ValueError("only relative shell source files can be deployed")
    if not isinstance(spec.get("reason"),str) or not 8<=len(spec["reason"])<=300:
        raise ValueError("deployment reason is required")


def target_for(family):
    return Path(os.environ.get("XDG_CONFIG_HOME",str(Path.home()/".config")))/"quickshell"/family


def atomic_file(path, data):
    path.parent.mkdir(parents=True,exist_ok=True)
    fd,name=tempfile.mkstemp(prefix=".hadalis-deploy-",dir=path.parent)
    try:
        with os.fdopen(fd,"wb") as output:
            output.write(data);output.flush();os.fsync(output.fileno())
        os.replace(name,path);_sync_directory(path.parent)
    finally:
        if Path(name).exists():Path(name).unlink()


def shell_identity(target):
    try:
        result=bounded_run(["qs","list","-a","-j"],cwd=target,timeout=5,capture=32768)
        for item in json.loads(result["stdout"]):
            if Path(item["config_path"]).resolve()==(target/"shell.qml").resolve():
                return process_identity(item["pid"])
    except (OSError,ValueError,KeyError):pass
    return None


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def rollback(path, receipt):
    target=Path(receipt["target"]);root=path.parent
    conflicts=[]
    for item in receipt["files"]:
        dest=target/item["name"]
        current=digest(dest)
        if current not in {item["original_sha256"],item["applied_sha256"]}:
            conflicts.append(item["name"]);continue # Preserve concurrent valid deployment.
        if item["original_sha256"] is None:
            dest.unlink(missing_ok=True);_sync_directory(dest.parent)
        else:atomic_file(dest,(root/"backup"/item["name"]).read_bytes())
    receipt.update(phase="conflict" if conflicts else "rolled_back",conflicts=conflicts,finished_at_unix=int(time.time()))
    _write(path,receipt)
    if not conflicts and shell_identity(target) is None:
        # One named user service per family; independent of the crashed QML.
        bounded_run(["systemd-run","--user","--collect",f"--unit=hadalis-shell-recovery-{receipt['family']}",
                     "--property=Restart=on-failure","--property=RestartSec=3","--property=StartLimitBurst=3",
                     "qs","-p",str(target)],cwd=target,timeout=8,capture=4096)
    return {"status":"failed","exit_code":1,"rolled_back":not conflicts,"recovery_required":bool(conflicts)}


def deploy(spec, workspace, job_id):
    validate(spec)
    target=target_for(spec["family"]).resolve();workspace=workspace.resolve()
    root=state_dir()/"deployments"/job_id;root.mkdir(parents=True,exist_ok=True,mode=0o700);root.chmod(0o700)
    lockpath=state_dir()/f"deployment-{spec['family']}.lock"
    with lockpath.open("a+") as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        path=root/"receipt.json"
        if path.exists():
            old=json.loads(path.read_text())
            if old["phase"]=="accepted":return {"status":"passed","exit_code":0}
            if old["phase"] in {"applying","watching"}:return rollback(path,old)
            return {"status":"failed","exit_code":1,"recovery_required":old["phase"]=="conflict"}
        baseline=shell_identity(target)
        if not baseline:return {"status":"failed","exit_code":1,"error_code":"no_known_good_running_shell"}
        stage=root/"stage"
        _write(path,{"phase":"staging","runner":process_identity(os.getpid()),"target":str(target),"family":spec["family"]})
        count=0;total=0
        for p in target.rglob("*"):
            if p.is_file():count+=1;total+=p.stat().st_size
            if count>12000 or total>256*1024**2:raise ValueError("shell staging exceeds bound")
        shutil.copytree(target,stage,symlinks=False)
        entries=[]
        for name in spec["files"]:
            src=(workspace/name).resolve();dest=(target/name).resolve()
            if workspace not in src.parents or target not in dest.parents or not src.is_file() or src.stat().st_size>2*1024**2:
                raise ValueError("unsafe shell deployment path")
            if dest.exists():atomic_file(root/"backup"/name,dest.read_bytes())
            atomic_file(stage/name,src.read_bytes())
            entries.append({"name":name,"original_sha256":digest(dest),"applied_sha256":digest(src)})
        receipt={"phase":"prepared","target":str(target),"family":spec["family"],"files":entries,
                 "reason":spec["reason"],"runner":process_identity(os.getpid()),"baseline":baseline,"at_unix":int(time.time())}
        _write(path,receipt)
        try:
            # Acceptance is required on the exact pinned workspace before touching the shell.
            result=bounded_run(["bash","scripts/validate-maintainer-local.sh","--current-repo"],cwd=workspace,timeout=1800,capture=32768)
            qml=[str(stage/name) for name in spec["files"] if Path(name).suffix in {".qml",".js"}]
            parser=next((p for p in ("/usr/lib/qt6/bin/qmlformat","/usr/lib/x86_64-linux-gnu/qt6/bin/qmlformat") if Path(p).exists()),shutil.which("qmlformat"))
            syntax={"exit_code":0}
            if qml and not parser:syntax={"exit_code":127}
            elif parser:
                for file in qml:
                    syntax=bounded_run([parser,file],cwd=stage,timeout=20,capture=32768)
                    if syntax["exit_code"]:break
            if result["exit_code"] or syntax["exit_code"]:
                receipt.update(phase="validation_failed",validation_exit=result["exit_code"],syntax_exit=syntax["exit_code"]);_write(path,receipt)
                return {"status":"failed","exit_code":1,"error_code":"shell_validation_failed"}
            if any(digest(target/e["name"])!=e["original_sha256"] for e in entries):
                receipt["phase"]="conflict";_write(path,receipt)
                return {"status":"failed","exit_code":1,"recovery_required":True}
            receipt["phase"]="applying";_write(path,receipt)
            for e in entries:atomic_file(target/e["name"],(stage/e["name"]).read_bytes())
            receipt["phase"]="watching";_write(path,receipt)
            deadline=time.monotonic()+30
            while time.monotonic()<deadline:
                if not is_same_process(baseline) and shell_identity(target) is None:return rollback(path,receipt)
                time.sleep(.5)
            receipt.update(phase="accepted",finished_at_unix=int(time.time()));_write(path,receipt)
            return {"status":"passed","exit_code":0}
        finally:shutil.rmtree(stage,ignore_errors=True)


def recover():
    # A runner killed during apply/reboot never leaves an unvalidated shell active.
    for path in (state_dir()/"deployments").glob("*/receipt.json"):
        receipt=json.loads(path.read_text())
        if is_same_process(receipt.get("runner")):continue
        if receipt["phase"] in {"staging","prepared","validation_failed","accepted","rolled_back"}:
            shutil.rmtree(path.parent/"stage",ignore_errors=True)
            if receipt["phase"] in {"accepted","rolled_back"} and int(time.time())-receipt.get("finished_at_unix",0)>14*86400:
                shutil.rmtree(path.parent/"backup",ignore_errors=True)
            continue
        if receipt["phase"] not in {"applying","watching"}:continue
        with (state_dir()/f"deployment-{receipt['family']}.lock").open("a+") as lock:
            try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError:continue
            rollback(path,receipt)
