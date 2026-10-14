#!/usr/bin/env python3
"""No live Quickshell/systemd: reproduce indirect IPC/settings autostart refusal."""
from pathlib import Path
import os,tempfile,subprocess
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory()as tmp:
 home=Path(tmp);bin=home/'bin';bin.mkdir();(home/'config/alis').mkdir(parents=True)
 qs=bin/'qs';qs.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$CALLS"
if [[ "$*" == *list* ]]; then echo 'No running instances'; exit 0; fi
if [[ "$*" == *' -n '* || "$*" == '-n '* || "$*" == *' -d '* ]]; then touch "$LAUNCHED"; fi
exit 0
''');qs.chmod(0o755)
 ctl=bin/'systemctl';ctl.write_text('''#!/bin/bash
if [[ "$*" == *'is-active'* && "$*" == *'inir.service'* ]]; then exit 0; fi
if [[ "$*" == *start* || "$*" == *restart* || "$*" == *enable* ]]; then touch "$LAUNCHED"; fi
exit 3
''');ctl.chmod(0o755)
 cli=bin/'alis';s=(ROOT/'scripts/alis').read_text();assert 'qs_bin="/usr/bin/qs"'in s
 cli.write_text(s.replace('qs_bin="/usr/bin/qs"','qs_bin="'+str(qs)+'"',1));(bin/'lib').symlink_to(ROOT/'scripts/lib')
 env=dict(os.environ,HOME=str(home),XDG_CONFIG_HOME=str(home/'config'),XDG_STATE_HOME=str(home/'state'),XDG_CACHE_HOME=str(home/'cache'),ALIS_RUNTIME_DIR=str(ROOT),PATH=str(bin)+':'+os.environ['PATH'],CALLS=str(home/'calls'),LAUNCHED=str(home/'launched'))
 for args in [['run'],['start'],['restart'],['service','start'],['service','restart'],['service','enable'],['ipc','foo','echo'],['settings'],['overview','toggle']]:
  p=subprocess.run(['bash',str(cli),*args],env=env,capture_output=True,text=True,timeout=10)
  assert p.returncode!=0 and 'previous shell service is still active'in p.stderr,(args,p.returncode,p.stdout,p.stderr)
  assert not(home/'launched').exists(),args
 p=subprocess.run(['bash',str(cli),'ipc','foo','close'],env=env,capture_output=True,text=True,timeout=10)
 assert p.returncode==0 and not(home/'launched').exists(),p.stderr
 print('PASS: nine direct/indirect starts refused; absent-instance close remains non-starting; no live services touched')
