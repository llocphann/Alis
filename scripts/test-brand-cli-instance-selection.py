#!/usr/bin/env python3
"""CLI logs must not discover private test shells or another Wayland display."""
from pathlib import Path
import json
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-cli-instance-selection-") as name:
    base = Path(name)
    bindir = base / "bin"; bindir.mkdir()
    current = base / "config/quickshell/alis"; current.mkdir(parents=True)
    other_display = base / "private full Alis"; other_display.mkdir()
    foreign = base / "hadalis-recording-field-fixture"; foreign.mkdir()
    for folder in [current, other_display]:
        (folder / "shell.qml").write_text("//@ pragma ShellId alis\n// fixture only\n")
    (foreign / "shell.qml").write_text("// a Recording test is not the Alis shell\n")
    inventory = base / "inventory.json"
    inventory.write_text(json.dumps([{"config_path":str(p/"shell.qml")} for p in [foreign, other_display, current]]))
    calls = base / "calls.jsonl"
    qs = bindir / "qs"
    qs.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
a=sys.argv[1:]
with open(os.environ['CALLS'],'a') as f:f.write(json.dumps(a)+'\\n')
rows=json.loads(Path(os.environ['INVENTORY']).read_text())
if a==['list','--all','--json']:
 if os.environ.get('TEXT_ONLY')=='1':sys.exit(2)
 print(json.dumps(rows))
elif a==['list','--all']:
 for row in rows:print('  Config path: '+row['config_path'])
elif len(a)>=3 and a[0]=='-p' and a[2]=='list':
 if a[1] in json.loads(os.environ['CURRENT_CONFIGS']):print('Instance own-fixture:\\n  Config path: '+a[1]+'/shell.qml')
 else:print('No running instances for "'+a[1]+'/shell.qml"')
elif len(a)>=3 and a[0]=='-p' and a[2]=='log':
 print(json.dumps({'log_config':a[1]}))
else:sys.exit(83)
''')
    qs.chmod(0o755)
    cli = bindir / "alis"
    source = (ROOT / "scripts/alis").read_text()
    assert source.count('qs_bin="/usr/bin/qs"') == 1
    cli.write_text(source.replace('qs_bin="/usr/bin/qs"', 'qs_bin="'+str(qs)+'"'))
    (bindir / "lib").symlink_to(ROOT / "scripts/lib")
    env = dict(os.environ, HOME=str(base), XDG_CONFIG_HOME=str(base/"config"),
               XDG_STATE_HOME=str(base/"state"), XDG_CACHE_HOME=str(base/"cache"),
               CALLS=str(calls), INVENTORY=str(inventory), CURRENT_CONFIGS=json.dumps([str(current),str(foreign)]),
               ALIS_SYSTEM_RUNTIME_DIR=str(base/"absent-system"),
               ALIS_FALLBACK_SYSTEM_RUNTIME_DIR=str(base/"absent-fallback"))
    for key in ["ALIS_RUNTIME_DIR","INIR_RUNTIME_DIR","HADALIS_RUNTIME_DIR","QS_CONFIG_NAME","QS_CONFIG_PATH","QS_MANIFEST"]:
        env.pop(key,None)
    for text_only in [False, True]:
        p = subprocess.run(["bash",str(cli),"logs","--full"],env={**env,"TEXT_ONLY":str(int(text_only))},
                           text=True,capture_output=True,timeout=5)
        assert p.returncode == 0 and json.loads(p.stdout)["log_config"] == str(current), (p.stdout,p.stderr)
    observed = [json.loads(line) for line in calls.read_text().splitlines()]
    assert ["-p",str(other_display),"list"] in observed, "other-display Alis was not checked"
    assert ["-p",str(foreign),"list"] not in observed, "foreign fixture was treated as Alis"
    assert not any("--any-display" in args for args in observed), "default discovery crossed display boundary"
    # Explicit owner override must remain explicit, even for a test config.
    p = subprocess.run(["bash",str(cli),"logs","--full"],env={**env,"ALIS_RUNTIME_DIR":str(foreign)},
                       text=True,capture_output=True,timeout=5)
    assert p.returncode == 0 and json.loads(p.stdout)["log_config"] == str(foreign)
    print("PASS: JSON/text discovery ignores private fixtures and other displays; explicit runtime override preserved")
