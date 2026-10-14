from pathlib import Path
import tempfile,sys,shutil,json,time
root=Path.cwd();out=root/'.git/maintainer-validation/20261014-async-frame-control';sys.path.insert(0,str(root/'scripts'))
from native_test_session import private_wayland,run_qs
with tempfile.TemporaryDirectory(prefix='alis-async-frame-control-') as name:
 folder=Path(name);shutil.copy2(out/'shell.qml',folder/'shell.qml')
 with private_wayland(folder) as env:result=run_qs(folder,env,timeout=15)
(out/'raw.log').write_text(result.stdout)
for l in result.stdout.splitlines():
 if 'ASYNC_FRAME_CONTROL ' in l:
  value=json.loads(l.split('ASYNC_FRAME_CONTROL ',1)[1]);(out/'result.json').write_text(json.dumps({'native_exit':result.returncode,'scope':'Minimal asynchronous Rectangle animation control, private no-focus Wayland; no production Dashboard or owner acceptance',**value},indent=2)+'\n');print({k:len(value[k]) for k in ['swaps','grabs','states']})
print('exit',result.returncode);print(result.stdout[-700:])
