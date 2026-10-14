from pathlib import Path
import tempfile,subprocess,sys,json,shutil,statistics,time,os
root=Path.cwd();out=root/'.git/maintainer-validation/20261014-shoulder-cross-axis';clone=root/'.git/maintainer-validation/shoulder-cross-exact';bench=out/'benchmark-exact-serialized';bench.mkdir(exist_ok=True)
sha=subprocess.check_output(['git','-C',str(clone),'rev-parse','HEAD'],text=True).strip()
shutil.copy2(out/'baseline.js',bench/'baseline.js');shutil.copy2(clone/'modules/abyss/looks/AbyssGeometry.js',bench/'prototype.js');shutil.copy2(out/'shell.qml',bench/'shell.qml')
sys.path.insert(0,str(clone/'scripts'))
from native_test_session import private_wayland,run_qs
start=time.time()
with tempfile.TemporaryDirectory(prefix='alis-cross-exact-bench-') as name:
 folder=Path(name)
 for f in ['shell.qml','baseline.js','prototype.js']:shutil.copy2(bench/f,folder/f)
 with private_wayland(folder) as env:r=run_qs(folder,env,timeout=30)
(bench/'raw.log').write_text(r.stdout)
assert r.returncode==0 and 'SHOULDER_NUMERIC_RESEARCH_PASS' in r.stdout,r.stdout
v=json.loads(next(l.split('SHOULDER_NUMERIC_RESEARCH_PASS',1)[1] for l in r.stdout.splitlines() if 'SHOULDER_NUMERIC_RESEARCH_PASS' in l));a=statistics.median(x['ms'] for x in v['results'] if x['name']=='baseline');b=statistics.median(x['ms'] for x in v['results'] if x['name']=='prototype')
v.update(source_sha=sha,started=start,ended=time.time(),baseline_median_ms=a,prototype_median_ms=b,reduction_percent=(a-b)/a*100,scope='Serialized four alternating 400-call numeric shoulder sampler QV4 microbenchmark; no whole-desktop claim')
(bench/'result.json').write_text(json.dumps(v,indent=2)+'\n');print(json.dumps(v),flush=True)
neg=root/'.git/maintainer-validation/shoulder-cross-stale-mutant';subprocess.run(['git','clone','--quiet','--shared',str(clone),str(neg)],check=True)
f=neg/'modules/abyss/looks/AbyssGeometry.js';s=f.read_text();assert s.count('if (cross!==lastCross)')==1;f.write_text(s.replace('if (cross!==lastCross)','if (!Number.isFinite(lastCross))'))
env=dict(os.environ,ALIS_SHOULDER_SAMPLER_LOG=str(out/'stale-mutant-raw.log'));start=time.time()
with (out/'stale-mutant-stdout.log').open('w') as log:p=subprocess.run(['python3',str(neg/'scripts/test-abyss-shoulder-sampler-runtime.py')],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=90)
(out/'stale-mutant-receipt.json').write_text(json.dumps({'base_sha':sha,'exit_code':p.returncode,'started':start,'ended':time.time(),'mutation':'Retain first cross-axis values for subsequent rows'},indent=2)+'\n');assert p.returncode!=0,'Oracle accepted stale rows';print('negative control rejected',flush=True)
with tempfile.TemporaryDirectory(prefix='alis-cross-serial-hover-') as name:
 with private_wayland(Path(name)) as env:
  env['ALIS_POPUP_HOVER_LOG']=str(out/'hover-nested-serialized-raw.log');start=time.time()
  with (out/'hover-nested-serialized-stdout.log').open('w') as log:p=subprocess.run(['python3',str(clone/'scripts/test-popup-anchor-hover-runtime.py')],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=100)
(out/'hover-nested-serialized-receipt.json').write_text(json.dumps({'source_sha':sha,'exit_code':p.returncode,'started':start,'ended':time.time(),'explicit_focus':False},indent=2)+'\n');print('serialized nested hover',p.returncode,flush=True)
