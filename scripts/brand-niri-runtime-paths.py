#!/usr/bin/env python3
"""Migrate managed active Niri helper paths and Autostart delimiters only."""
import argparse, os, re, tempfile, shutil
from pathlib import Path
def read_exact(path):
 return path.read_bytes().decode('utf-8')

def apply_changes(changes):
 # Validate every destination before creating backups or modifying any file.
 for p,old,new in changes:
  if p.is_symlink()or read_exact(p)!=old:raise SystemExit('Niri file changed during planning: '+str(p))
  backup=p.with_name(p.name+'.brand-runtime.bak')
  if backup.is_symlink()or(backup.exists()and not backup.is_file()):raise SystemExit('Unsafe backup: '+str(backup))
 staged=[];applied=[]
 try:
  for p,old,new in changes:
   copies=[];staged.append((p,old,new,copies))
   # Historical backup may predate this transaction: keep a separate snapshot
   # so a failed multi-file repair restores the exact pre-apply bytes.
   for data in [old,new]:
    fd,name=tempfile.mkstemp(prefix=p.name+'.alis-',dir=p.parent);copies.append(Path(name))
    with os.fdopen(fd,'wb')as stream:stream.write(data.encode('utf-8'))
    shutil.copystat(p,name)
   backup=p.with_name(p.name+'.brand-runtime.bak')
   if not backup.exists():
    with backup.open('xb')as stream:stream.write(old.encode('utf-8'))
    shutil.copystat(p,backup)
    if read_exact(backup)!=old:raise OSError('Niri backup verification failed: '+str(backup))
  for p,old,new,copies in staged:
   if p.is_symlink()or read_exact(p)!=old:raise SystemExit('Niri file changed before apply: '+str(p))
   os.replace(copies[1],p);applied.append((p,new,copies[0]))
 except BaseException:
  for p,new,original in reversed(applied):
   try:
    if p.is_symlink()or read_exact(p)!=new:raise OSError('Concurrent edit preserved; owner recovery required')
    os.replace(original,p)
   except OSError as error:print('BLOCKER: cannot restore '+str(p)+': '+str(error),file=__import__('sys').stderr)
  raise
 finally:
  for p,old,new,copies in staged:
   for copy in copies:copy.unlink(missing_ok=True)

parser=argparse.ArgumentParser()
mode=parser.add_mutually_exclusive_group()
mode.add_argument('--apply',action='store_true')
mode.add_argument('--dry-run',action='store_true')
parser.add_argument('--owner-approved',action='store_true')
args=parser.parse_args()
if args.apply and not args.owner_approved:parser.error('apply requires --owner-approved')
root=Path(os.environ.get('XDG_CONFIG_HOME',str(Path.home()/'.config')))/'niri'
entry=root/'config.kdl'
files=[];pending=[entry];seen=set()
while pending:
 p=pending.pop(0)
 if any(x.is_symlink()for x in [p,*p.parents]if x==root or root in x.parents)or not p.is_file():raise SystemExit('Unsafe/missing Niri include: '+str(p))
 resolved=p.resolve()
 if not resolved.is_relative_to(root.resolve()):raise SystemExit('Niri include leaves root: '+str(p))
 if resolved in seen:continue
 seen.add(resolved);files.append(p)
 text=read_exact(p)
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
has_canonical_venv=any(re.search(r'^\s*ALIS_VENV\s+',read_exact(p),re.M)for p in files)
legacy='in'+'ir'
for p in files:
 text=read_exact(p);new=[]
 for line in text.splitlines(keepends=True):
  venv=re.match(r'^(\s*)INIR_VENV(\s+"[^"\r\n]+"[^\r\n]*)',line)
  if venv and not has_canonical_venv:
   new.append(venv[1]+'ALIS_VENV'+venv[2]+('\r\n'if line.endswith('\r\n')else'\n'))
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
if args.apply:apply_changes(changes)
print('Changed files: '+str(len(changes))+'; original helper arguments and Autostart entries preserved.')
