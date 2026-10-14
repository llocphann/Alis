#!/usr/bin/env python3
"""Migrate managed active Niri helper paths and Autostart delimiters only."""
import argparse, os, re, tempfile, shutil
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument('--apply',action='store_true')
parser.add_argument('--dry-run',action='store_true')
parser.add_argument('--owner-approved',action='store_true')
args=parser.parse_args()
if args.apply and not args.owner_approved:parser.error('apply requires --owner-approved')
root=Path(os.environ.get('XDG_CONFIG_HOME',str(Path.home()/'.config')))/'niri'
entry=root/'config.kdl'
files=[];pending=[entry];seen=set()
while pending:
 p=pending.pop(0)
 if p.is_symlink()or not p.is_file():raise SystemExit('Unsafe/missing Niri include: '+str(p))
 resolved=p.resolve()
 if not resolved.is_relative_to(root.resolve()):raise SystemExit('Niri include leaves root: '+str(p))
 if resolved in seen:continue
 seen.add(resolved);files.append(p)
 text=p.read_text()
 for line in text.splitlines():
  if not re.match(r'^\s*include\s+',line):continue
  m=re.match(r'^\s*include\s+"([^"]+)"\s*(?://.*)?$',line)
  if not m:raise SystemExit('Unrecognized Niri include: '+str(p))
  rel=Path(m[1])
  if rel.is_absolute()or any(x in ['.','..']for x in rel.parts):raise SystemExit('Unsafe include path')
  a=root/rel;b=p.parent/rel
  if a.is_file()and b.is_file()and a.resolve()!=b.resolve():raise SystemExit('Ambiguous Niri include')
  pending.append(a if a.is_file()else b)
changes=[]
has_canonical_venv=any(re.search(r'^\s*ALIS_VENV\s+',p.read_text(),re.M)for p in files)
legacy='in'+'ir'
for p in files:
 text=p.read_text();new=[]
 for line in text.splitlines(keepends=True):
  venv=re.match(r'^(\s*)INIR_VENV(\s+"[^"\n]+"[^\n]*)',line)
  if venv and not has_canonical_venv:
   new.append(venv[1]+'ALIS_VENV'+venv[2]+'\n')
   has_canonical_venv=True
  if re.match(r'^\s*spawn(?:-at-startup|-sh-at-startup)?\b',line):
   for helper in ['native-dispatch','clipboard-image-store.sh']:
    line=line.replace('/quickshell/'+legacy+'/scripts/'+helper,'/quickshell/alis/scripts/'+helper)
  if line.strip()in ['// >>> '+legacy+'-managed-autostart >>>','// <<< '+legacy+'-managed-autostart <<<']:
   line=line.replace(legacy+'-managed-autostart','alis-managed-autostart')
  new.append(line)
 result=''.join(new)
 if result!=text:
  if text.count('// >>> alis-managed-autostart >>>')and text.count('// >>> '+legacy+'-managed-autostart >>>'):
   raise SystemExit('Two managed Autostart blocks require review: '+str(p))
  changes.append((p,text,result))
for p,old,new in changes:
 print(('APPLY'if args.apply else'PLAN')+': '+str(p))
 if not args.apply:continue
 if p.is_symlink()or p.read_text()!=old:raise SystemExit('Niri file changed during planning')
 backup=p.with_name(p.name+'.brand-runtime.bak')
 if backup.is_symlink()or(backup.exists()and not backup.is_file()):raise SystemExit('Unsafe backup: '+str(backup))
 if not backup.exists():shutil.copy2(p,backup)
 fd,name=tempfile.mkstemp(prefix=p.name+'.alis-',dir=p.parent)
 try:
  with os.fdopen(fd,'w')as stream:stream.write(new)
  os.chmod(name,p.stat().st_mode&0o777);os.replace(name,p)
 finally:
  if Path(name).exists():Path(name).unlink()
print('Changed files: '+str(len(changes))+'; original helper arguments and Autostart entries preserved.')
