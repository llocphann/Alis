from pathlib import Path
import sys,json,time,tempfile,subprocess,os
root=Path.cwd();out=root/'.git/maintainer-validation/20261014-shoulder-cross-axis';clone=root/'.git/maintainer-validation/shoulder-cross-exact';sys.path.insert(0,str(clone/'scripts'))
from native_test_session import private_wayland
cases=[('sampler','test-abyss-shoulder-sampler-runtime.py','ALIS_SHOULDER_SAMPLER_LOG'),('regions','test-abyss-connection-region-runtime.py','ALIS_CONNECTION_REGION_LOG'),('hover','test-popup-anchor-hover-runtime.py','ALIS_POPUP_HOVER_LOG')]
results=[]
def run_scope(scope,env):
 for kind,fixture,key in cases:
  target=clone/'scripts'/fixture
  if not target.exists():raise RuntimeError('Missing exact fixture '+fixture)
  started=time.time();current=dict(env);current[key]=str(out/(kind+'-'+scope+'-raw.log'))
  with (out/(kind+'-'+scope+'-stdout.log')).open('w') as log:
   p=subprocess.run(['python3',str(target)],env=current,stdout=log,stderr=subprocess.STDOUT,timeout=130)
  receipt={'kind':kind,'scope':scope,'source_sha':'667a84d9cfd7c14e142a45ac4501c85c72dd576c','exit_code':p.returncode,'started':started,'ended':time.time(),'explicit_focus':False}
  (out/(kind+'-'+scope+'-receipt.json')).write_text(json.dumps(receipt,indent=2)+'\n');results.append(receipt);print(kind,scope,p.returncode,flush=True)
run_scope('direct',dict(os.environ))
with tempfile.TemporaryDirectory(prefix='alis-cross-axis-outer-') as name:
 with private_wayland(Path(name)) as env:run_scope('nested',env)
(out/'qualified-receipt.json').write_text(json.dumps(results,indent=2)+'\n')
