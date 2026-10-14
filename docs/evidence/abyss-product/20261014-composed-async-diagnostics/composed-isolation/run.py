from pathlib import Path
import tempfile,shutil,sys,json,subprocess,time,os,signal,threading,hashlib
root=Path.cwd();out=root/'.git/maintainer-validation/20261014-composed-isolation';source=root/'.git/maintainer-validation/composed-motion-source';sys.path.insert(0,str(source/'scripts'))
from native_test_session import private_wayland
sha=subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()
def descendants(pid):
 try:children=Path(f'/proc/{pid}/task/{pid}/children').read_text().split()
 except OSError:return []
 result=[]
 for child in children:result.append(int(child));result.extend(descendants(int(child)))
 return result
def stats(pid):
 values=[]
 for task in Path(f'/proc/{pid}/task').glob('*'):
  try:
   s=(task/'stat').read_text();a=s.index('(');b=s.rindex(')');fields=s[b+2:].split()
   values.append({'tid':int(task.name),'name':s[a+1:b],'cpu_ticks':int(fields[11])+int(fields[12]),'state':fields[0]})
  except (OSError,ValueError):pass
 return values
for mode in ['long','short','none','long-source']:
 target=out/mode
 with tempfile.TemporaryDirectory(prefix='alis-composed-isolate-'+mode+'-') as name:
  folder=Path(name)
  for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(source/entry)
  shutil.copy2(target/'shell.qml',folder/'shell.qml')
  with private_wayland(folder) as env:
   assert env
   config=folder/'config/illogical-impulse';config.mkdir(parents=True);v=json.loads((source/'defaults/config.json').read_text());v['panelFamily']='abyss';v['abyss']['companion']['enabled']=False
   (config/'config.json').write_text(json.dumps(v));(target/'frames').mkdir(exist_ok=True);env.update(COMPOSED_CAPTURE=str(target/'frames'),QSG_RHI_BACKEND='opengl',QT_NO_XDG_DESKTOP_PORTAL='1')
   started=time.time();samples=[];qs_pid=None
   with (target/'raw.log').open('wb') as log:p=subprocess.Popen(['dbus-run-session','--','qs','-p',str(folder),'--no-color'],env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
   while p.poll() is None and time.time()-started<20:
    if qs_pid is None:
     for child in descendants(p.pid):
      try:
       if Path(f'/proc/{child}/comm').read_text().strip()=='qs':qs_pid=child;break
      except OSError:pass
    if qs_pid is not None:samples.append({'ms':(time.time()-started)*1000,'tasks':stats(qs_pid)})
    time.sleep(.05)
   code=p.poll()
   if code is None:os.killpg(p.pid,signal.SIGTERM);p.wait(timeout=3);code=124
  (target/'tasks.json').write_text(json.dumps({'ticks_per_second':os.sysconf('SC_CLK_TCK'),'qs_pid':qs_pid,'samples':samples},indent=2)+'\n')
  raw=(target/'raw.log').read_text(errors='replace');data=None
  for line in raw.splitlines():
   if 'COMPOSED_MOTION_RESULT ' in line:data=json.loads(line.split('COMPOSED_MOTION_RESULT ',1)[1])
  if data:(target/'result.json').write_text(json.dumps(data,indent=2)+'\n')
  (target/'receipt.json').write_text(json.dumps({'source_sha':sha,'native_exit':code,'started':started,'ended':time.time(),'qml_sha256':hashlib.sha256((target/'shell.qml').read_bytes()).hexdigest(),'explicit_focus':False},indent=2)+'\n')
  print(mode,code,data['error'] if data else 'NO_RESULT',data['completed'] if data else None,flush=True)
