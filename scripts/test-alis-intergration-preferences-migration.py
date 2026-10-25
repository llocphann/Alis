#!/usr/bin/env python3
"""Existing explicit choices survive; fresh and unchosen features stay off."""
import itertools
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
migration=ROOT/"sdata/migrations/060-hadalird-preferences.sh"
cases=0
for dirname in ("inir","illogical-impulse"):
    for selected in itertools.product((False,True),repeat=3):
        for explicit in (None,False,True):
            with tempfile.TemporaryDirectory(prefix="hadalird-intent-") as name:
                base=Path(name);path=base/dirname/"config.json";path.parent.mkdir()
                original={"battery":{"chargeLimit":{"enable":selected[0],"threshold":73}},
                          "powerProfiles":{"fanControl":{"enabled":selected[1],"balanced":2}},
                          "integrations":{"obsidian":{"autoTheme":selected[2],"configPath":".obsidian"}},
                          "todo":{"backend":"internal","obsidian":{"vaultPath":"/Vault có spaces"}},"custom":[0,False,"keep"]}
                if explicit is not None:original["integrations"]["hadalird"]={key:explicit for key in ("tlp","thinkfan","obsidian")}
                path.write_text(json.dumps(original));path.chmod(0o640)
                env=dict(os.environ,XDG_CONFIG_HOME=str(base))
                def run(action):return subprocess.run(["bash","-c",'source "$1"; "$2"',"fixture",str(migration),action],env=env,text=True,capture_output=True)
                result=run("migration_apply");assert result.returncode==0,result.stderr
                updated=json.loads(path.read_text())
                expected=dict(zip(("tlp","thinkfan","obsidian"),selected)) if explicit is None else {key:explicit for key in ("tlp","thinkfan","obsidian")}
                assert updated["integrations"]["hadalird"]==expected
                del updated["integrations"]["hadalird"]
                original["integrations"].pop("hadalird",None)
                assert updated==original and path.stat().st_mode&0o777==0o640
                before=path.read_bytes();assert run("migration_apply").returncode==0 and path.read_bytes()==before
                assert run("migration_check").returncode==1
                cases+=1
with tempfile.TemporaryDirectory(prefix="hadalird-todo-intent-") as name:
    base=Path(name);path=base/"inir/config.json";path.parent.mkdir();path.write_text(json.dumps({"todo":{"backend":"obsidian"}}))
    result=subprocess.run(["bash","-c",'source "$1"; migration_apply',"fixture",str(migration)],env=dict(os.environ,XDG_CONFIG_HOME=str(base)),capture_output=True,text=True)
    assert result.returncode==0 and json.loads(path.read_text())["integrations"]["hadalird"]=={"tlp":False,"thinkfan":False,"obsidian":True}
print("HADALIRD_PREFERENCES_PASS",cases+1,"selected/default-off/explicit override layouts; unrelated config, mode and byte idempotence")
