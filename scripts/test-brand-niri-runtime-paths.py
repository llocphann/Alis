#!/usr/bin/env python3
import tempfile,os,subprocess,runpy,sys
from unittest.mock import patch
from pathlib import Path
root=Path(__file__).resolve().parents[1];helper=root/'scripts/brand-niri-runtime-paths.py'
with tempfile.TemporaryDirectory()as tmp:
 home=Path(tmp);cfg=home/'config/niri';cfg.mkdir(parents=True);(cfg/'parts').mkdir()
 (cfg/'config.kdl').write_text('include "parts/startup.kdl"\n')
 p=cfg/'parts/startup.kdl'
 original='// bookmark /quickshell/alis/scripts/native-dispatch\nspawn-at-startup "bash" "-c" "exec wl-paste --type text --watch ~/.config/quickshell/alis/scripts/native-dispatch clipboard-store"\nspawn-at-startup "bash" "-c" "exec wl-paste --type image --watch ~/.config/quickshell/alis/scripts/clipboard-image-store.sh"\n// >>> alis-managed-autostart >>>\nspawn-at-startup "gtk-launch" "my-app"\n// <<< alis-managed-autostart <<<\n'
 original+='environment {\n    ALIS_VENV \"/custom/venv\"\n}\n'
 p.write_text(original);env=dict(os.environ,XDG_CONFIG_HOME=str(home/'config'))
 def run(*args):return subprocess.run(['python3',str(helper),*args],env=env,capture_output=True,text=True)
 assert run('--dry-run').returncode==0 and p.read_text()==original
 assert run('--apply').returncode!=0 and p.read_text()==original
 assert run('--apply','--owner-approved').returncode==0
 actual=p.read_text();assert 'ALIS_VENV \"/custom/venv\"'in actual and 'ALIS_VENV \"/custom/venv\"'in actual
 assert '/quickshell/alis/scripts/native-dispatch clipboard-store' in actual
 assert '/quickshell/alis/scripts/clipboard-image-store.sh' in actual
 assert 'bookmark /quickshell/alis/scripts/native-dispatch' in actual
 assert 'spawn-at-startup "gtk-launch" "my-app"'in actual and 'alis-managed-autostart'in actual
 assert p.with_name(p.name+'.brand-runtime.bak').read_text()==original
 assert run('--apply','--owner-approved').returncode==0 and p.read_text()==actual
 p.unlink();p.symlink_to(p.with_name(p.name+'.brand-runtime.bak'))
 assert run('--apply','--owner-approved').returncode!=0
with tempfile.TemporaryDirectory()as tmp:
 cfg=Path(tmp)/'niri';cfg.mkdir();parts=cfg/'parts';parts.mkdir()
 (cfg/'config.kdl').write_text('include "parts/first.kdl"\ninclude "parts/second.kdl"\n')
 first=parts/'first.kdl';second=parts/'second.kdl'
 original=b'environment {\r\n    ALIS_VENV "/custom/venv"\r\n}\r\n'
 first.write_bytes(original);first.chmod(0o640)
 second.write_bytes(b'spawn-at-startup "~/.config/quickshell/alis/scripts/native-dispatch" "clipboard-store"\r\n')
 old_second=second.read_bytes()
 backup=second.with_name(second.name+'.brand-runtime.bak');backup.mkdir()
 env=dict(os.environ,XDG_CONFIG_HOME=tmp)
 rejected=subprocess.run(['python3',str(helper),'--apply','--owner-approved'],env=env,capture_output=True,text=True)
 assert rejected.returncode!=0 and 'Unsafe backup' in rejected.stderr
 assert first.read_bytes()==original and second.read_bytes()==old_second
 assert not first.with_name(first.name+'.brand-runtime.bak').exists()
 backup.rmdir()
 with patch.dict(os.environ,env),patch.object(sys,'argv',[str(helper),'--dry-run']):
  module=runpy.run_path(str(helper))
 replace=os.replace
 def fail_second(src,dst):
  if dst==second:raise OSError('injected second-file replacement failure')
  replace(src,dst)
 with patch.object(os,'replace',side_effect=fail_second):
  try:module['apply_changes'](module['changes'])
  except OSError as error:assert 'injected' in str(error)
  else:raise AssertionError('expected replacement failure')
 assert first.read_bytes()==original and second.read_bytes()==old_second
 assert first.stat().st_mode&0o777==0o640 and not list(parts.glob('*.alis-*'))
 accepted=subprocess.run(['python3',str(helper),'--apply','--owner-approved'],env=env,capture_output=True,text=True)
 assert accepted.returncode==0,accepted.stderr
 assert b'ALIS_VENV "/custom/venv"\r\n' in first.read_bytes()
 assert first.read_bytes().replace(b'\r\n',b'').count(b'\n')==0
 assert first.with_name(first.name+'.brand-runtime.bak').read_bytes()==original
 # Includes through a symlinked parent must be rejected, too.
 parts.rename(cfg/'retained-parts');parts.symlink_to(cfg/'retained-parts',target_is_directory=True)
 assert subprocess.run(['python3',str(helper),'--dry-run'],env=env,capture_output=True).returncode!=0
print('PASS: scoped Niri helpers/markers, retained entries/comments/backup, consent, idempotency, symlink refusal')
print('PASS: whole-plan preflight, failed multi-file repair rollback, original CRLF/modes and parent-link refusal')
