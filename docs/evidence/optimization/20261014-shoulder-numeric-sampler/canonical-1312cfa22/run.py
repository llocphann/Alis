from pathlib import Path
import json,tempfile,subprocess,sys,time,hashlib
r=Path.cwd();o=r/'.git/maintainer-validation/20261014-sampler-canonical';m=json.loads((o/'frozen-driver.json').read_text());sys.path.insert(0,str(Path(m['caller_checkout'])/'scripts'));from native_test_session import private_wayland
assert hashlib.sha256(Path(m['driver']).read_bytes()).hexdigest()==m['driver_sha256']
started=time.time()
with tempfile.TemporaryDirectory(prefix='alis-canonical-sampler-outer-') as name:
 with private_wayland(Path(name)) as env:
  env['ALIS_VALIDATION_LOG']=str(o/'canonical-raw.log')
  with (o/'terminal.log').open('w') as log:
   p=subprocess.Popen(['bash',m['driver'],'--current-repo'],cwd=m['caller_checkout'],env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
   (o/'running.json').write_text(json.dumps({'pid':p.pid,'process_group':p.pid,'started_unix':started,'source_sha':m['source_sha']},indent=2)+'\n')
   code=p.wait()
(o/'receipt.json').write_text(json.dumps({'source_sha':m['source_sha'],'frozen_driver':m,'exit_code':code,'started_unix':started,'ended_unix':time.time(),'scope':m['scope']},indent=2)+'\n');print('canonical exit',code);print((o/'terminal.log').read_text()[-4500:])
