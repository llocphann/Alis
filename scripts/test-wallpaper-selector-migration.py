#!/usr/bin/env python3
"""Selection migration preserves targets, formats, permission and unrelated data."""
import json,os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-wallpaper-migration-") as name:
 base=Path(name);conf=base/"illogical-impulse/config.json";conf.parent.mkdir()
 initial={"wallpaperSelector":{"style":"coverflow","selectionTarget":"waffle","targetMonitor":"DP-1","useSystemFileDialog":True},"background":{"wallpaperPath":"/images/owned.png","transition":{"enable":False,"type":"random","duration":900}},"enabledPanels":["iiCoverflowSelector","iiWallpaperLauncher","dock"],"future":{"retained":True}}
 conf.write_text(json.dumps(initial));conf.chmod(0o600)
 script=ROOT/"sdata/migrations/057-unified-wallpaper-selector.sh"
 env={**os.environ,"XDG_CONFIG_HOME":name}
 def invoke(command):return subprocess.run(["bash","-c",'source "$1"; '+command,"migration",str(script)],env=env,check=True)
 invoke("migration_check && migration_apply")
 value=json.loads(conf.read_text())
 assert value["wallpaperSelector"]=={**initial["wallpaperSelector"],"style":"caelestia","useSystemFileDialog":False}
 assert value["background"]=={**initial["background"],"transition":{**initial["background"]["transition"],"type":"alisMelt"}}
 assert value["enabledPanels"]==["dock","iiWallpaperSelector"] and value["future"]==initial["future"]
 assert conf.stat().st_mode&0o777==0o600
 invoke("! migration_check")
 before=conf.read_bytes();invoke("migration_apply");assert conf.read_bytes()==before
 print("WALLPAPER_MIGRATION_PASS target format disabled-motion panel-alias permissions idempotence")
