from pathlib import Path
import sys,json,time,tempfile,shutil
root=Path.cwd();out=root/'.git/maintainer-validation/20261014-shoulder-cross-axis';sys.path.insert(0,str(root/'scripts'))
from native_test_session import private_wayland,run_qs
with tempfile.TemporaryDirectory(prefix='alis-shoulder-cross-') as name:
 folder=Path(name)
 for f in ['shell.qml','baseline.js','prototype.js']:shutil.copy2(out/f,folder/f)
 with private_wayland(folder) as env:
  result=run_qs(folder,env,timeout=30)
(out/'raw.log').write_text(result.stdout)
print(result.returncode);print(result.stdout[-2000:])
