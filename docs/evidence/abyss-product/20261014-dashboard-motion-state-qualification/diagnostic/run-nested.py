from pathlib import Path
import tempfile,subprocess,os,sys,json,time
root=Path.cwd();out=root/'.git/maintainer-validation/20261014-dashboard-field-diagnostic';sys.path.insert(0,str(root/'scripts'))
from native_test_session import private_wayland
started=time.time()
with tempfile.TemporaryDirectory(prefix='alis-dashboard-field-outer-') as name:
 with private_wayland(Path(name)) as env:
  env.update(HADALIS_DASHBOARD_TEST_ROOT=str(root),PYTHONPATH=str(root/'scripts'))
  with (out/'candidate-nested.log').open('w') as log:
   result=subprocess.run(['python3',str(out/'candidate.py')],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=100)
(out/'candidate-nested-receipt.json').write_text(json.dumps({'exit_code':result.returncode,'started':started,'ended':time.time(),'explicit_focus':False},indent=2)+'\n')
print('exit',result.returncode);print((out/'candidate-nested.log').read_text()[-2000:])
