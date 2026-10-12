#!/usr/bin/env python3
"""Offline, no-home-touch lifecycle contract for Alis-managed Companion sync."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MANAGER = ROOT / "scripts/companion-manager.py"
STUB = r'''#!/usr/bin/env python3
import json, os
from pathlib import Path
import subprocess
import sys

if os.environ.get("COMPANION_FIXTURE_FAIL") == "1":
    sys.exit(23)
source = Path(__file__).resolve().parents[1]
sha = subprocess.check_output(["git","rev-parse","HEAD"],cwd=source,text=True).strip()
home = Path(os.environ["XDG_DATA_HOME"])
data = home / "hadanion"
release = data / "releases" / sha
release.mkdir(parents=True,exist_ok=True)
info = json.loads((source / "manifest.json").read_text())
info["sourceSha"] = sha
for rel in (info["session"],info["output"],info["settings"],info["binary"]):
    path = release / rel
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text("fixture")
    if rel == info["binary"]:
        path.chmod(0o755)
(release / "manifest.json").write_text(json.dumps(info))
current = data / "current"
if current.is_symlink():
    existing = current.resolve()
    if not existing.is_relative_to(data / "releases"):
        sys.exit(24)
elif current.exists():
    sys.exit(24)
temporary = data / ".current-fixture"
temporary.symlink_to(Path("releases") / sha)
os.replace(temporary,current)
'''

def cmd(*args, cwd=None, env=None, ok=True):
    p = subprocess.run(args, cwd=cwd, env=env, text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if ok and p.returncode:
        raise AssertionError(f"{args}: {p.returncode}\n{p.stdout}")
    return p

with tempfile.TemporaryDirectory(prefix="alis-companion-managed-") as td:
    root = Path(td)
    source = root / "source"
    source.mkdir()
    cmd("git", "init", "-q", "-b", "main", str(source))
    (source / "scripts").mkdir()
    (source / "scripts/stub_install.py").write_text(STUB)
    (source / "Makefile").write_text("install:\n\tpython3 scripts/stub_install.py\n")
    (source / "manifest.json").write_text(json.dumps({
        "id":"hadanion", "hostApi":1, "version":"fixture",
        "session":"HadalisSession.qml", "output":"HadalisOutput.qml",
        "settings":"modules/settings/CompanionConfig.qml",
        "binary":"native/bin/inir-companiond"
    }))
    cmd("git","add","-A",cwd=source)
    cmd("git","-c","user.name=Fixture","-c","user.email=fixture@example.invalid",
        "commit","-qm","first",cwd=source)
    first = cmd("git","rev-parse","HEAD",cwd=source).stdout.strip()
    remote = root / "remote.git"
    cmd("git","clone","--bare","-q",str(source),str(remote))
    cmd("git","remote","add","origin",str(remote),cwd=source)
    env = {**os.environ,"XDG_DATA_HOME":str(root/"data"),"XDG_CACHE_HOME":str(root/"cache")}
    base=[sys.executable,str(MANAGER),"sync","--repo-url",str(remote)]
    def sync(sha, extra=None, ok=True):
        return cmd(*base,"--revision",sha,env={**env,**(extra or {})},ok=ok)
    assert cmd(sys.executable,str(MANAGER),"status","--revision",first,env=env).returncode==0
    sync(first)
    current = root/"data/hadanion/current"
    assert current.is_symlink() and current.resolve().name==first
    # A healthy pinned installation is idempotent without contacting Git.
    checkout=root/"cache/alis/companion/source"
    cmd("git","remote","set-url","origin",str(root/"offline"),cwd=checkout)
    sync(first)
    assert current.resolve().name==first
    # A later revision must refuse a foreign remote and preserve the old release.
    (source/"extra.txt").write_text("next\n")
    cmd("git","add","extra.txt",cwd=source)
    cmd("git","-c","user.name=Fixture","-c","user.email=fixture@example.invalid",
        "commit","-qm","second",cwd=source)
    second=cmd("git","rev-parse","HEAD",cwd=source).stdout.strip()
    cmd("git","push","-q","origin","main",cwd=source)
    assert sync(second,ok=False).returncode != 0
    assert current.resolve().name==first
    cmd("git","remote","set-url","origin",str(remote),cwd=checkout)
    assert sync(second,{"COMPANION_FIXTURE_FAIL":"1"},ok=False).returncode != 0
    assert current.resolve().name==first, "failed build changed the active release"
    sync(second)
    assert current.resolve().name==second
    assert first != second
    # A local modification must not be overwritten on a repair.
    current.unlink()
    (checkout/"foreign.txt").write_text("local modification\n")
    assert sync(second,ok=False).returncode != 0
    assert not current.exists()
    (checkout/"foreign.txt").unlink()
    sync(second)
    assert current.resolve().name==second
    # Reject a non-release-current pointing outside owned releases.
    current.unlink()
    current.symlink_to(root/"source",target_is_directory=True)
    assert sync(second,ok=False).returncode != 0
    assert current.resolve()==source.resolve(), "foreign symlink must be preserved"
print("PASS: managed Companion pinned auto-install, offline no-op, remote isolation, failure rollback and safe repair")
