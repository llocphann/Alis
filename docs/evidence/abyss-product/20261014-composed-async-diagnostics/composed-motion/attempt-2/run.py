from pathlib import Path
import tempfile,shutil,sys,json,subprocess,time,hashlib
root=Path.cwd();out=root/'.git/maintainer-validation/20261014-composed-motion';source=root/'.git/maintainer-validation/composed-motion-source';sys.path.insert(0,str(source/'scripts'))
from native_test_session import private_wayland,run_qs
started=time.time()
with tempfile.TemporaryDirectory(prefix='alis-composed-async-') as name:
 folder=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(source/entry)
 shutil.copy2(out/'shell.qml',folder/'shell.qml')
 with private_wayland(folder) as env:
  assert env
  config=folder/'config/illogical-impulse';config.mkdir(parents=True)
  value=json.loads((source/'defaults/config.json').read_text());value['panelFamily']='abyss';value['abyss']['companion']['enabled']=False
  (config/'config.json').write_text(json.dumps(value));(out/'frames').mkdir(exist_ok=True);env['COMPOSED_CAPTURE']=str(out/'frames');env['QSG_RHI_BACKEND']='opengl'
  result=run_qs(folder,env,timeout=180)
(out/'raw.log').write_text(result.stdout)
for line in result.stdout.splitlines():
 if 'COMPOSED_MOTION_RESULT ' in line:
  data=json.loads(line.split('COMPOSED_MOTION_RESULT ',1)[1]);(out/'result.json').write_text(json.dumps(data,indent=2)+'\n');print({k:data[k] for k in ['error','phase','completed','checks']});print({k:len(data[k]) for k in ['results']})
(out/'receipt.json').write_text(json.dumps({'source_sha':subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip(),'native_exit':result.returncode,'started':started,'ended':time.time(),'explicit_focus':False,'scope':'Actual composed BodyHost/Field/Dashboard Notes/editor in asynchronous normal event loop; diagnostic, not owner acceptance'},indent=2)+'\n');print('native exit',result.returncode)
if result.returncode:print(result.stdout[-3000:])
