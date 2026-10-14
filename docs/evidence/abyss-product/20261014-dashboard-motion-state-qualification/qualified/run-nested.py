from pathlib import Path
import tempfile,subprocess,sys,json,time,os
root=Path.cwd();out=root/'.git/maintainer-validation/20261014-dashboard-motion-qualified';clone=root/'.git/maintainer-validation/dashboard-motion-exact';sys.path.insert(0,str(clone/'scripts'))
from native_test_session import private_wayland
start=time.time()
with tempfile.TemporaryDirectory(prefix='alis-motion-qualified-outer-') as name:
 with private_wayland(Path(name)) as env:
  env['ALIS_DASHBOARD_FIELD_LOG']=str(out/'nested-raw.log')
  with (out/'nested-stdout.log').open('w') as log:
   p=subprocess.run(['python3',str(clone/'scripts/test-dashboard-editor-field-runtime.py')],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=100)
(out/'nested-receipt.json').write_text(json.dumps({'exit_code':p.returncode,'source_sha':"c3143be527b4aaec7372e1037742a3c9908c5ff2",'started':start,'ended':time.time(),'explicit_focus':False},indent=2)+'\n')
print('exit',p.returncode);print((out/'nested-stdout.log').read_text()[-2000:])
