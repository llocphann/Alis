#!/usr/bin/env python3
"""Preserve enabled/disabled MPD intent and unrelated config across the move."""
import json, os, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MIGRATION=ROOT/"sdata/migrations/059-dashboard-local-music.sh"
for dirname in ["alis","illogical-impulse"]:
 for enabled in [False,True]:
  for explicit in [None,False,True]:
   with tempfile.TemporaryDirectory(prefix="alis-music-move-") as name:
    base=Path(name); path=base/dirname/"config.json"; path.parent.mkdir()
    original={"sidebar":{"music":{"enable":enabled,"mpdHost":"/tmp/private mpd.sock","mpdPort":6610,"libraryFolder":"/Music/四"},"left":{"tabOrder":["news","music","ai","ytmusic","tools"]}},"custom":{"keep":[0,False,"四"]}}
    if explicit is not None: original["dashboard"]={"music":{"enable":explicit},"showHeader":False}
    path.write_text(json.dumps(original));path.chmod(0o640)
    env=dict(os.environ,XDG_CONFIG_HOME=str(base))
    run=lambda action:subprocess.run(["bash","-c",'source "$1"; "$2"',"migration",str(MIGRATION),action],env=env,text=True,capture_output=True)
    result=run("migration_apply")
    assert result.returncode==0,result.stderr
    updated=json.loads(path.read_text())
    assert updated["dashboard"]["music"]["enable"]==(enabled if explicit is None else explicit)
    assert updated["sidebar"]["music"]==original["sidebar"]["music"]
    assert updated["sidebar"]["left"]["tabOrder"]==["news","ai","tools"]
    assert updated["custom"]==original["custom"]
    assert path.stat().st_mode & 0o777==0o640
    before=path.read_bytes();assert run("migration_apply").returncode==0
    assert path.read_bytes()==before and run("migration_check").returncode==1
subprocess.run(["node",str(ROOT/"scripts/test-dashboard-music-model.cjs")],cwd=ROOT,check=True)
print("DASHBOARD_MUSIC_MIGRATION_PASS 12 layouts/preferences, MPD endpoint/library, retained order, mode, idempotence; model behavior")
