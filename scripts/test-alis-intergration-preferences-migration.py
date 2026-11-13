#!/usr/bin/env python3
"""Existing explicit choices survive; fresh and unchosen features stay off."""
import itertools
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
migration=ROOT/"sdata/migrations/060-alis-intergration-preferences.sh"
cases=0
for dirname in ("alis","illogical-impulse"):
    for selected in itertools.product((False,True),repeat=3):
        for explicit in (None,False,True):
            with tempfile.TemporaryDirectory(prefix="alis-intergration-intent-") as name:
                base=Path(name);path=base/dirname/"config.json";path.parent.mkdir()
                original={"battery":{"chargeLimit":{"enable":selected[0],"threshold":73}},
                          "powerProfiles":{"fanControl":{"enabled":selected[1],"balanced":2}},
                          "integrations":{"nexus":{"autoTheme":selected[2],"configPath":".nexus"}},
                          "todo":{"backend":"internal","nexus":{"vaultPath":"/Vault có spaces"}},"custom":[0,False,"keep"]}
                if explicit is not None:original["integrations"]["alisIntergration"]={key:explicit for key in ("tlp","thinkfan","nexus")}
                path.write_text(json.dumps(original));path.chmod(0o640)
                env=dict(os.environ,XDG_CONFIG_HOME=str(base))
                def run(action):return subprocess.run(["bash","-c",'source "$1"; "$2"',"fixture",str(migration),action],env=env,text=True,capture_output=True)
                result=run("migration_apply");assert result.returncode==0,result.stderr
                updated=json.loads(path.read_text())
                expected=dict(zip(("tlp","thinkfan","nexus"),selected)) if explicit is None else {key:explicit for key in ("tlp","thinkfan","nexus")}
                assert updated["integrations"]["alisIntergration"]==expected
                del updated["integrations"]["alisIntergration"]
                original["integrations"].pop("alisIntergration",None)
                assert updated==original and path.stat().st_mode&0o777==0o640
                before=path.read_bytes();assert run("migration_apply").returncode==0 and path.read_bytes()==before
                assert run("migration_check").returncode==1
                cases+=1
with tempfile.TemporaryDirectory(prefix="alis-intergration-todo-intent-") as name:
    base=Path(name);path=base/"alis/config.json";path.parent.mkdir();path.write_text(json.dumps({"todo":{"backend":"nexus"}}))
    result=subprocess.run(["bash","-c",'source "$1"; migration_apply',"fixture",str(migration)],env=dict(os.environ,XDG_CONFIG_HOME=str(base)),capture_output=True,text=True)
    assert result.returncode==0 and json.loads(path.read_text())["integrations"]["alisIntergration"]=={"tlp":False,"thinkfan":False,"nexus":True}
legacy_k = "ob" + "sidian"
with tempfile.TemporaryDirectory(prefix="alis-intergration-legacy-intent-") as name:
    base=Path(name);path=base/"alis/config.json";path.parent.mkdir()
    path.write_text(json.dumps({"todo":{"backend":legacy_k},"integrations":{legacy_k:{"autoTheme":True,"configPath":"."+legacy_k},"alisIntergration":{"tlp":False,"thinkfan":False,legacy_k:True}}}))
    result=subprocess.run(["bash","-c",'source "$1"; migration_apply',"fixture",str(migration)],env=dict(os.environ,XDG_CONFIG_HOME=str(base)),capture_output=True,text=True)
    assert result.returncode==0 and json.loads(path.read_text())["integrations"]["alisIntergration"]=={"tlp":False,"thinkfan":False,"nexus":True}
policy_src = (ROOT / "modules/common/PanelFamilyPolicy.js").read_text(encoding="utf-8")
node_test = subprocess.run(
    ["node", "-e", policy_src + f"""
const k = "{legacy_k}";
const opts = {{
  abyss: {{ companionMind: {{ [k + "Enabled"]: true, nexusEnabled: true }} }},
  integrations: {{
    alisIntergration: {{ [k]: true, nexus: true }},
    [k]: {{ autoTheme: true, configPath: "." + k, applicationPath: k }},
    nexus: {{ autoTheme: true, configPath: "." + k, applicationPath: k }}
  }},
  todo: {{
    backend: k,
    [k]: {{ vaultPath: "~/Vault", dailyNote: {{ folder: "Journal" }} }},
    nexus: {{ vaultPath: "~/Vault", dailyNote: {{ folder: "Journal" }} }}
  }}
}};
const out = migrateNexusConfig(opts);
if (Object.keys(out).length === 0) process.exit(1);
if (out["integrations.nexus.configPath"] !== ".nexus") process.exit(2);
if (out["integrations.nexus.applicationPath"] !== "nexus") process.exit(3);
if (out["todo.backend"] !== "nexus") process.exit(4);
if (k in opts.integrations || k in opts.todo || (k + "Enabled") in opts.abyss.companionMind || k in opts.integrations.alisIntergration) process.exit(5);
"""],
    capture_output=True, text=True
)
assert node_test.returncode == 0, f"migrateNexusConfig failed ({node_test.returncode}): {node_test.stderr}"
print("ALIS_INTERGRATION_PREFERENCES_PASS",cases+3,"selected/default-off/explicit override layouts; legacy key migration, unrelated config, mode and byte idempotence")
