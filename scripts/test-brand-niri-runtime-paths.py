#!/usr/bin/env python3
import tempfile,os,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1];helper=root/'scripts/brand-niri-runtime-paths.py'
with tempfile.TemporaryDirectory()as tmp:
 home=Path(tmp);cfg=home/'config/niri';cfg.mkdir(parents=True);(cfg/'parts').mkdir()
 (cfg/'config.kdl').write_text('include "parts/startup.kdl"\n')
 p=cfg/'parts/startup.kdl'
 original='// bookmark /quickshell/inir/scripts/native-dispatch\nspawn-at-startup "bash" "-c" "exec wl-paste --type text --watch ~/.config/quickshell/inir/scripts/native-dispatch clipboard-store"\nspawn-at-startup "bash" "-c" "exec wl-paste --type image --watch ~/.config/quickshell/inir/scripts/clipboard-image-store.sh"\n// >>> inir-managed-autostart >>>\nspawn-at-startup "gtk-launch" "my-app"\n// <<< inir-managed-autostart <<<\n'
 original+='environment {\n    INIR_VENV \"/custom/venv\"\n}\n'
 p.write_text(original);env=dict(os.environ,XDG_CONFIG_HOME=str(home/'config'))
 def run(*args):return subprocess.run(['python3',str(helper),*args],env=env,capture_output=True,text=True)
 assert run('--dry-run').returncode==0 and p.read_text()==original
 assert run('--apply').returncode!=0 and p.read_text()==original
 assert run('--apply','--owner-approved').returncode==0
 actual=p.read_text();assert 'ALIS_VENV \"/custom/venv\"'in actual and 'INIR_VENV \"/custom/venv\"'in actual
 assert '/quickshell/alis/scripts/native-dispatch clipboard-store' in actual
 assert '/quickshell/alis/scripts/clipboard-image-store.sh' in actual
 assert 'bookmark /quickshell/inir/scripts/native-dispatch' in actual
 assert 'spawn-at-startup "gtk-launch" "my-app"'in actual and 'alis-managed-autostart'in actual
 assert p.with_name(p.name+'.brand-runtime.bak').read_text()==original
 assert run('--apply','--owner-approved').returncode==0 and p.read_text()==actual
 p.unlink();p.symlink_to(p.with_name(p.name+'.brand-runtime.bak'))
 assert run('--apply','--owner-approved').returncode!=0
print('PASS: scoped Niri helpers/markers, retained entries/comments/backup, consent, idempotency, symlink refusal')
