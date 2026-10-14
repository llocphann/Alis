#!/usr/bin/env python3
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
import hashlib
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import sys
from urllib.parse import urlparse

sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from automation.manager.store import _write
from automation.worker.process import bounded_run, process_identity, is_same_process, kill_group
from automation.worker.privacy import public_result
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
QUEUE = "automation/queue/pending"
RESULTS = "automation/results"
JOB_RE = re.compile(r"^JOB-[A-Za-z0-9._-]+$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
POLL = float(os.environ.get("HADALIS_WORKER_POLL_SECONDS", "10"))
MAX_CAPTURE = max(4096,min(262144,int(os.environ.get("HADALIS_WORKER_MAX_CAPTURE_BYTES", "131072"))))
MAX_WORKERS = max(1,min(4,int(os.environ.get("HADALIS_WORKER_CONCURRENCY", "2"))))
MAX_EVIDENCE_BYTES = 256 * 1024**2
MAX_TIMEOUT = int(os.environ.get("HADALIS_WORKER_MAX_TIMEOUT_SECONDS", "3600"))
ENV_KEYS = {
    "PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL",
    "DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "NIRI_SOCKET",
    "DBUS_SESSION_BUS_ADDRESS",
}


def run(argv: list[str], *, cwd: Path = ROOT, timeout: float | None = None,
        env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    result=bounded_run(argv,cwd=cwd,env=env,timeout=timeout or 120,capture=262144)
    return subprocess.CompletedProcess(argv,result["exit_code"],result["stdout"],result["stderr"])



def git(*args: str, timeout: int = 30) -> subprocess.CompletedProcess[str]:
    return run(["git", *args], timeout=timeout)


def state_root() -> Path:
    base = Path(os.environ.get(
        "XDG_STATE_HOME", str(Path.home() / ".local" / "state")
    ))
    path = base / "hadalis-automation" / "worker"
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.chmod(0o700)
    return path


def fetch_dev(profile_id=None) -> None:
    from automation.manager.credentials import git_options, git_env, status
    if profile_id is None:
        # Discovery reads the common authoritative repository; job publication
        # always uses its explicit owning profile's credential.
        profile_id=next((pid for pid,saved in status()["github"].items() if saved),None)
    options=git_options(profile_id,remote_url()) if profile_id else []
    result = run(["git",*options,"fetch","origin","dev"],env=git_env()) if options else git("fetch", "origin", "dev")
    if result.returncode != 0:
        raise RuntimeError(f"git fetch failed: {result.stderr.strip()}")


def remote_url() -> str:
    result = git("remote", "get-url", "origin")
    if result.returncode != 0:
        raise RuntimeError(f"origin unavailable: {result.stderr.strip()}")
    return result.stdout.strip()


def pending_paths() -> list[str]:
    result = git("ls-tree", "-r", "--name-only", "origin/dev", QUEUE)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())
    return sorted(
        line.strip() for line in result.stdout.splitlines()
        if line.strip().endswith(".json")
    )


def result_exists(job_id: str) -> bool:
    result = git(
        "cat-file", "-e", f"origin/dev:{RESULTS}/{job_id}.json",
        timeout=30,
    )
    return result.returncode == 0


def remote_text(path: str, *, ref="origin/dev") -> str:
    result = git("show", f"{ref}:{path}", timeout=30)
    if result.returncode != 0:
        raise RuntimeError(f"cannot read {path}: {result.stderr.strip()}")
    return result.stdout


def introducing_commit(path: str) -> str:
    result = git("log", "-1", "--format=%H", "origin/dev", "--", path, timeout=30)
    value = result.stdout.strip()
    if result.returncode != 0 or SHA_RE.fullmatch(value) is None:
        raise RuntimeError(f"cannot resolve job commit for {path}")
    return value


def first_parent(commit: str) -> str:
    result = git("rev-parse", f"{commit}^", timeout=30)
    value = result.stdout.strip()
    if result.returncode != 0 or SHA_RE.fullmatch(value) is None:
        raise RuntimeError(f"cannot resolve parent for {commit}")
    return value


def validate_job(path: str, raw: str) -> dict[str, Any]:
    job_id = Path(path).stem
    if JOB_RE.fullmatch(job_id) is None:
        raise ValueError("unsafe job filename")
    data = json.loads(raw)
    if not isinstance(data, dict) or data.get("id") != job_id:
        raise ValueError("job id must match filename")
    base_sha = data.get("base_sha")
    if not isinstance(base_sha, str) or SHA_RE.fullmatch(base_sha) is None:
        raise ValueError("base_sha must be a full SHA")
    if set(data)-{"id","base_sha","actions","profile_id","resources"}: raise ValueError("unknown job fields")
    owner=data.get("profile_id")
    if owner is not None and (not isinstance(owner,str) or not re.fullmatch(r"[a-z0-9-]{1,80}",owner)):
        raise ValueError("invalid profile ownership")
    resources=data.get("resources",[])
    if not isinstance(resources,list) or len(resources)>8 or any(not isinstance(x,str) or not re.fullmatch(r"[a-zA-Z0-9:_.-]{1,100}",x) for x in resources):
        raise ValueError("invalid resource leases")
    actions=data.get("actions")
    if not isinstance(actions,list) or not 1<=len(actions)<=32:raise ValueError("actions must contain 1..32 steps")
    for action in actions:
        if not isinstance(action,dict) or len(action)!=1:raise ValueError("action must contain exactly one typed step")
        kind=next(iter(action));spec=action[kind]
        if not isinstance(spec,dict):raise ValueError("action spec must be an object")
        if kind=="exec":
            if set(spec)-{"argv","cwd","timeout_seconds"}:raise ValueError("unknown exec fields")
            argv=spec.get("argv")
            if not isinstance(argv,list) or not 1<=len(argv)<=128 or any(not isinstance(x,str) or not x or len(x)>4096 for x in argv) or sum(map(len,argv))>16384:
                raise ValueError("exec.argv exceeds bound")
            if any(re.search(r"(?i)^--?(?:password|passwd|token|api-key|secret)(?:=|$)",x) for x in argv):
                raise ValueError("credentials cannot be passed in argv")
            if not isinstance(spec.get("cwd","."),str):raise ValueError("exec.cwd must be a string")
            timeout=spec.get("timeout_seconds",600)
            if type(timeout) is not int or not 0<timeout<=MAX_TIMEOUT:raise ValueError("timeout exceeds bound")
        elif kind=="diagnostics":
            from automation.worker.diagnostics import validate
            validate(spec)
        elif kind=="privileged":
            from automation.worker.privilege import validate
            validate(spec)
        elif kind=="shell_deploy":
            from automation.worker.deployment import validate
            validate(spec)
        else:raise ValueError("action kind not allowlisted")
    return data


def safe_cwd(workspace: Path, relative: str) -> Path:
    root = workspace.resolve()
    target = (workspace / relative).resolve()
    if target != root and root not in target.parents:
        raise ValueError("exec.cwd escapes workspace")
    if not target.is_dir():
        raise ValueError(f"exec.cwd does not exist: {relative}")
    return target


def clipped(text: str | bytes | None) -> tuple[str, bool]:
    if text is None:
        return "", False
    if isinstance(text, bytes):
        raw = text
    else:
        raw = text.encode("utf-8", errors="replace")
    if len(raw) <= MAX_CAPTURE:
        return raw.decode("utf-8", errors="replace"), False
    return raw[:MAX_CAPTURE].decode("utf-8", errors="replace"), True


def exec_env() -> dict[str, str]:
    return {key: value for key, value in os.environ.items() if key in ENV_KEYS}


def workspace_for(commit: str, job_id: str) -> Path:
    runs=state_root()/"runs";runs.mkdir(exist_ok=True,mode=0o700)
    if shutil.disk_usage(runs).free<256*1024**2:raise RuntimeError("workspace disk pressure")
    path=Path(tempfile.mkdtemp(prefix=f"{job_id}-",dir=runs));shutil.rmtree(path)
    try:
        clone=run(["git","clone","--shared","--no-checkout",str(ROOT),str(path)],timeout=120)
        if clone.returncode:raise RuntimeError("workspace clone failed")
        checkout=run(["git","checkout","--detach",commit],cwd=path,timeout=60)
        if checkout.returncode:raise RuntimeError("workspace checkout failed")
        return path
    except BaseException:
        shutil.rmtree(path,ignore_errors=True);raise


def receipt_path(job_id):return state_root()/"receipts"/(job_id+".json")


def load_receipt(job_id):
    path=receipt_path(job_id)
    return json.loads(path.read_text()) if path.exists() else None


def save_receipt(job_id,receipt):_write(receipt_path(job_id),receipt)


@contextmanager
def job_lock(job_id):
    path=state_root()/"locks"/(job_id+".lock");path.parent.mkdir(exist_ok=True,mode=0o700)
    with path.open("a+") as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        yield


@contextmanager
def resource_leases(names):
    handles=[]
    try:
        for name in sorted(set(names)):
            root=state_root()/"resources";root.mkdir(exist_ok=True,mode=0o700)
            handle=(root/(hashlib.sha256(name.encode()).hexdigest()+".lock")).open("a+")
            try:fcntl.flock(handle,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError:
                handle.close();raise RuntimeError("shared resource busy")
            handles.append(handle)
        yield
    finally:
        for handle in handles:handle.close()


def execute(data: dict[str, Any], commit: str) -> dict[str, Any]:
    job_id=data["id"];receipt=load_receipt(job_id)
    if (state_root()/"cancellations"/job_id).exists():
        return {"job":job_id,"base_sha":data["base_sha"],"job_commit":commit,"profile_id":data.get("profile_id"),
                "input_sha256":receipt["input_sha256"],"status":"cancelled","actions":[],"finished_at_unix":int(time.time())}
    workspace=workspace_for(commit,job_id)
    action_root=state_root()/"actions"/job_id;action_root.mkdir(parents=True,exist_ok=True,mode=0o700)
    spec={"job":data,"workspace":str(workspace),"commit":commit,"receipt_dir":str(action_root),
          "started_at_unix":int(time.time()),"capture":MAX_CAPTURE,"input_sha256":receipt["input_sha256"]}
    _write(action_root/"spec.json",spec)
    receipt.update(phase="executing",workspace=str(workspace),runner=None);save_receipt(job_id,receipt)
    try:
        def spawned(identity):
            receipt["runner"]=identity;save_receipt(job_id,receipt)
        result=bounded_run([sys.executable,str(Path(__file__).with_name("runner.py")),str(action_root/"spec.json")],
            cwd=ROOT,timeout=min(32*MAX_TIMEOUT,sum(a.get("exec",{}).get("timeout_seconds",1860 if "shell_deploy" in a else 60) for a in data["actions"])+60),
            capture=4096,on_spawn=spawned,
            cancelled=lambda:(state_root()/"cancellations"/job_id).exists())
        output=action_root/"result.json"
        if output.exists():return json.loads(output.read_text())
        partial=[json.loads(p.read_text())["result"] for p in sorted(action_root.glob("action-*.json")) if json.loads(p.read_text()).get("phase")=="finished"]
        return {"job":job_id,"base_sha":data["base_sha"],"job_commit":commit,"profile_id":data.get("profile_id"),
            "status":"indeterminate","recovery_required":True,"actions":partial,
            "input_sha256":receipt["input_sha256"],"finished_at_unix":int(time.time())}
    finally:
        shutil.rmtree(workspace,ignore_errors=True)
        receipt["workspace"]=None;save_receipt(job_id,receipt)


def publish(job_id: str, payload: dict[str, Any]) -> None:
    """One publication attempt. Retry this receipt, never its external actions."""
    target=f"{RESULTS}/{job_id}.json";remote=remote_url()
    if urlparse(remote).password:raise ValueError("credential-bearing remote URL is unsupported")
    publish_dir=state_root()/"publish";publish_dir.mkdir(exist_ok=True,mode=0o700)
    with (state_root()/"publish.lock").open("a+") as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        fetch_dev(payload.get("profile_id"))
        if result_exists(job_id):return
        head=git("rev-parse","origin/dev").stdout.strip()
        if not SHA_RE.fullmatch(head):raise RuntimeError("publication HEAD unavailable")
        checkout=Path(tempfile.mkdtemp(prefix=job_id+"-",dir=publish_dir));shutil.rmtree(checkout)
        try:
            clone=run(["git","clone","--shared","--branch","dev","--no-checkout",str(ROOT),str(checkout)],timeout=60)
            if clone.returncode:raise RuntimeError("publication clone failed")
            checked=run(["git","checkout","--detach",head],cwd=checkout,timeout=60)
            if checked.returncode:raise RuntimeError("publication checkout failed")
            output=checkout/target;output.parent.mkdir(parents=True,exist_ok=True)
            output.write_text(json.dumps(public_result(payload),indent=2,sort_keys=True)+"\n")
            for argv in (["git","add",target],["git","commit","-m",f"automation: record {job_id} result"]):
                result=run(argv,cwd=checkout,timeout=60)
                if result.returncode:raise RuntimeError("publication commit failed")
            # Refetch immediately before the remote ref update. A race is a
            # publication retry on fresh dev, never a reset or execution retry.
            fetch_dev(payload.get("profile_id"))
            push_remote=os.environ.get("HADALIS_WORKER_PUSH_REMOTE") or remote
            if urlparse(push_remote).password:raise ValueError("credentials cannot appear in push argv")
            from automation.manager.credentials import git_options,git_env,repository,has_token
            owner=payload.get("profile_id")
            if has_token(owner) and repository(remote):
                push_remote="https://github.com/"+repository(remote)+".git"
            pushed=run(["git",*git_options(owner,push_remote),"push",push_remote,"HEAD:dev"],cwd=checkout,timeout=45,env=git_env())
            if pushed.returncode:raise RuntimeError("result publication failed; private receipt retained")
        finally:shutil.rmtree(checkout,ignore_errors=True)


def publish_receipt(job_id):
    with job_lock(job_id):
        receipt=load_receipt(job_id)
        if not receipt or not receipt.get("result") or receipt["phase"]=="published":return
        if int(time.time())<receipt.get("publish_after_unix",0):return
        receipt["phase"]="publishing";save_receipt(job_id,receipt)
        try:publish(job_id,receipt["result"])
        except Exception:
            receipt.update(phase="finished",publish_attempts=receipt.get("publish_attempts",0)+1)
            receipt["publish_error"]="Publication failed; execution receipt retained"
            receipt["publish_after_unix"]=int(time.time())+min(300,5*2**min(receipt["publish_attempts"],6))
            save_receipt(job_id,receipt)
            return
        receipt.update(phase="published",published_at_unix=int(time.time()),publish_after_unix=0)
        save_receipt(job_id,receipt)


def process_job(path: str, *, publish_now=True):
    job_id=Path(path).stem
    if not JOB_RE.fullmatch(job_id):return None
    with job_lock(job_id):
        prior=load_receipt(job_id)
        if prior and prior["phase"]=="published":return None
        if prior and prior.get("result"):
            payload=prior["result"]
        else:
            commit=introducing_commit(path)
            raw=remote_text(path,ref=commit);digest=hashlib.sha256(raw.encode()).hexdigest()
            if prior and prior.get("input_sha256")!=digest:
                raise ValueError("job ID reused with different content; original receipt retained")
            if prior and prior["phase"]=="executing":
                result_path=state_root()/"actions"/job_id/"result.json"
                payload=json.loads(result_path.read_text()) if result_path.exists() else {
                    "job":job_id,"job_commit":commit,"input_sha256":digest,"status":"indeterminate","recovery_required":True,"actions":[]}
            else:
                prior=prior or {"job":job_id,"phase":"preparing","input_sha256":digest,"job_commit":commit}
                save_receipt(job_id,prior)
                try:
                    data=validate_job(path,raw)
                    if first_parent(commit)!=data["base_sha"]:raise ValueError("job parent does not match base_sha")
                    prior["profile_id"]=data.get("profile_id");save_receipt(job_id,prior)
                    if sum(p.stat().st_size for folder in ("actions","receipts") for p in (state_root()/folder).rglob("*") if p.is_file())>MAX_EVIDENCE_BYTES:
                        raise RuntimeError("private evidence storage pressure")
                    with resource_leases(data.get("resources",[])):
                        payload=execute(data,commit)
                except RuntimeError as exc:
                    if str(exc) in {"shared resource busy","private evidence storage pressure","workspace disk pressure"}:
                        prior.update(phase="preparing",retry_after_unix=int(time.time())+10)
                        save_receipt(job_id,prior);return None
                    latest=load_receipt(job_id)
                    payload={"job":job_id,"status":"indeterminate" if latest.get("phase")=="executing" else "invalid", "actions":[],
                        "job_commit":commit,"input_sha256":digest,"finished_at_unix":int(time.time()),"recovery_required":latest.get("phase")=="executing"}
                except Exception:
                    latest=load_receipt(job_id)
                    payload={"job":job_id,"status":"indeterminate" if latest.get("phase")=="executing" else "invalid","actions":[],
                        "job_commit":commit,"input_sha256":digest,"finished_at_unix":int(time.time()),"recovery_required":latest.get("phase")=="executing"}
            latest=load_receipt(job_id) or prior
            latest.update(phase="finished",result=payload,workspace=None);save_receipt(job_id,latest)
    if publish_now:publish_receipt(job_id)
    return job_id,payload["status"]


def process_one() -> tuple[str,str] | None:
    fetch_dev()
    for path in pending_paths():
        job_id=Path(path).stem
        if not result_exists(job_id):return process_job(path)
    return None


def cleanup(*, startup=True) -> None:
    """Recover orphans on startup; prune only completed evidence while running."""
    root=state_root();protected=set()
    for path in (root/"receipts").glob("*.json"):
        receipt=json.loads(path.read_text())
        if receipt.get("workspace"):protected.add(receipt["workspace"])
        if startup and receipt.get("phase")=="executing":
            # Supervisor restart: any surviving old runner/action is an orphan.
            action_root=root/"actions"/receipt["job"]
            for action in action_root.glob("action-*.json"):
                ident=json.loads(action.read_text()).get("process")
                if ident and (is_same_process(ident) or process_identity(ident["pid"]) is None) and ident.get("boot_id")==Path("/proc/sys/kernel/random/boot_id").read_text().strip():
                    kill_group(ident["pid"])
            ident=receipt.get("runner")
            if is_same_process(ident):kill_group(ident["pid"])
            if receipt.get("workspace"):
                shutil.rmtree(receipt["workspace"],ignore_errors=True);protected.discard(receipt["workspace"])
            result=action_root/"result.json"
            payload=json.loads(result.read_text()) if result.exists() else {"job":receipt["job"],"status":"indeterminate", "recovery_required":True,"actions":[],"job_commit":receipt.get("job_commit"),"input_sha256":receipt.get("input_sha256")}
            receipt.update(phase="finished",result=payload,workspace=None);save_receipt(receipt["job"],receipt)
        if receipt.get("phase")=="published" and int(time.time())-receipt.get("published_at_unix",0)>14*86400:
            # Keep the exactly-once tombstone indefinitely; prune raw artifacts.
            shutil.rmtree(root/"actions"/receipt["job"],ignore_errors=True)
            receipt["result"]=public_result(receipt["result"]);save_receipt(receipt["job"],receipt)
    if startup:
        for directory in (root/"runs",root/"publish"):
            for path in directory.glob("*"):
                if str(path) not in protected and path.is_dir():shutil.rmtree(path,ignore_errors=True)


def main() -> int:
    parser=argparse.ArgumentParser(description="Bounded durable Hadalis worker pool")
    parser.add_argument("--once",action="store_true");args=parser.parse_args()
    root=state_root();lock_path=root/"worker.lock"
    legacy=lock_path.exists() and not (root/"pool-v2.json").exists()
    with lock_path.open("a+") as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        cleanup()
        if legacy:
            fetch_dev()
            for path in pending_paths():
                job_id=Path(path).stem
                if not result_exists(job_id) and not load_receipt(job_id):
                    save_receipt(job_id,{"job":job_id,"phase":"finished","result":{"job":job_id,"status":"indeterminate","actions":[],"recovery_required":True}})
        _write(root/"pool-v2.json",{"version":2,"started_at_unix":int(time.time())})
        if args.once:
            result=process_one();print(json.dumps({"outcome":result}));return 0
        running={};publisher=None;last_fetch=0;last_cleanup=0;last_error=None
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as execution, ThreadPoolExecutor(max_workers=1) as publication:
            while True:
                now=int(time.time())
                for job_id,future in list(running.items()):
                    if future.done():
                        try:future.result()
                        except Exception:last_error="Job metadata processing failed; private receipts preserved"
                        del running[job_id]
                _write(root/"pool.json",{"heartbeat_at_unix":now,"running":list(running),"limit":MAX_WORKERS,"publishing":publisher is not None and not publisher.done(),"last_error":last_error})
                if now-last_cleanup>=300:
                    cleanup(startup=False);last_cleanup=now
                if publisher is None or publisher.done():
                    ready=[p.stem for p in (root/"receipts").glob("*.json") if (lambda r:r.get("result") and r["phase"]!="published" and now>=r.get("publish_after_unix",0))(json.loads(p.read_text()))]
                    publisher=publication.submit(publish_receipt,ready[0]) if ready else None
                if now-last_fetch>=POLL and len(running)<MAX_WORKERS:
                    last_fetch=now
                    try:
                        fetch_dev()
                        for path in pending_paths()[:512]:
                            if len(running)>=MAX_WORKERS:break
                            job_id=Path(path).stem
                            if job_id in running:continue
                            r=load_receipt(job_id)
                            if r and (r.get("result") or now<r.get("retry_after_unix",0)):continue
                            if result_exists(job_id):continue
                            running[job_id]=execution.submit(process_job,path,publish_now=False)
                    except Exception:last_error="Git discovery unavailable; owned jobs and publication recovery continue"
                time.sleep(1)


if __name__=="__main__":raise SystemExit(main())
