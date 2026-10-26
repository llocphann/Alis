#!/usr/bin/env bash
MIGRATION_ID="059-dashboard-local-music"
MIGRATION_TITLE="Move local Music to Dashboard"
MIGRATION_DESCRIPTION="Moves local Music navigation to Dashboard while retaining the existing MPD connection, library folder and enabled preference."
MIGRATION_REQUIRED=true
_dashboard_music_config_path() {
    if declare -F resolve_inir_config_dir >/dev/null 2>&1; then
        printf '%s/config.json' "$(resolve_inir_config_dir)"
    elif [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/inir/config.json" ]]; then
        printf '%s/inir/config.json' "${XDG_CONFIG_HOME:-$HOME/.config}"
    else
        printf '%s/illogical-impulse/config.json' "${XDG_CONFIG_HOME:-$HOME/.config}"
    fi
}
MIGRATION_TARGET_FILE="$(_dashboard_music_config_path)"
_dashboard_music_migrate() {
    local conf; conf="$(_dashboard_music_config_path)"
    [[ -f "$conf" ]] || return 1
    python3 - "$conf" "$1" <<'PYTHON'
from pathlib import Path
import json, os, stat, sys, tempfile
path=Path(sys.argv[1]); before=path.read_bytes(); data=json.loads(before)
if not isinstance(data,dict): raise ValueError("Config root must be an object")
def object_at(parent,key):
    value=parent.get(key)
    if not isinstance(value,dict): value={};parent[key]=value
    return value
dashboard=object_at(data,"dashboard"); music=object_at(dashboard,"music")
sidebar=data.get("sidebar",{}); sidebar=sidebar if isinstance(sidebar,dict) else {}
if not isinstance(music.get("enable"),bool):
    previous=sidebar.get("music",{})
    previous=previous.get("enable",True) if isinstance(previous,dict) else True
    music["enable"]=previous if isinstance(previous,bool) else True
left=sidebar.get("left",{})
if isinstance(left,dict) and isinstance(left.get("tabOrder"),list):
    left["tabOrder"]=[value for value in left["tabOrder"] if value not in ("music","ytmusic")]
if data==json.loads(before): sys.exit(1 if sys.argv[2]=="check" else 0)
if sys.argv[2]=="check": sys.exit(0)
mode=stat.S_IMODE(path.stat().st_mode)
with tempfile.NamedTemporaryFile(dir=path.parent,delete=False) as output:
    temporary=Path(output.name)
    output.write((json.dumps(data,indent=4,ensure_ascii=False)+"\n").encode())
try:
    temporary.chmod(mode)
    if path.read_bytes()!=before: raise RuntimeError("Config changed during migration; retry")
    os.replace(temporary,path)
finally:
    temporary.unlink(missing_ok=True)
PYTHON
}
migration_check() { _dashboard_music_migrate check; }
migration_preview() { printf '%s\n' '+ Local Music becomes a Dashboard page; existing MPD and library settings are retained.'; }
migration_apply() {
    [[ -f "$(_dashboard_music_config_path)" ]] || return 0
    _dashboard_music_migrate apply
}
