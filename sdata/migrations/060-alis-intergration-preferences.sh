#!/usr/bin/env bash
# Preserve explicitly chosen integration behavior without installing a package
# or touching hardware/services/vaults. Fresh installs remain default-off.
MIGRATION_ID="060-alis-intergration-preferences"
MIGRATION_TITLE="Retain optional integration preferences"
MIGRATION_DESCRIPTION="Keeps previously selected TLP, Thinkfan and Obsidian features when moving their workers to optional AlisIntergration."
MIGRATION_REQUIRED=true
_alis_intergration_config() {
    if declare -F resolve_alis_config_dir >/dev/null 2>&1; then
        printf '%s/config.json' "$(resolve_alis_config_dir)"
    elif [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/alis/config.json" ]]; then
        printf '%s/alis/config.json' "${XDG_CONFIG_HOME:-$HOME/.config}"
    else
        printf '%s/illogical-impulse/config.json' "${XDG_CONFIG_HOME:-$HOME/.config}"
    fi
}
MIGRATION_TARGET_FILE="$(_alis_intergration_config)"
_alis_intergration_preferences() {
    local conf; conf="$(_alis_intergration_config)"
    [[ -f "$conf" ]] || return 1
    python3 - "$conf" "$1" <<'PYTHON'
import json,os,stat,sys,tempfile
from pathlib import Path
path=Path(sys.argv[1]);before=path.read_bytes();data=json.loads(before)
if not isinstance(data,dict):raise ValueError("Config root must be an object")
def get(*keys):
    value=data
    for key in keys:
        if not isinstance(value,dict):return None
        value=value.get(key)
    return value
selected={
    "tlp":get("battery","chargeLimit","enable") is True,
    "thinkfan":get("powerProfiles","fanControl","enabled") is True,
    "obsidian":get("integrations","obsidian","autoTheme") is True or get("todo","backend")=="obsidian",
}
integrations=data.get("integrations")
if not isinstance(integrations,dict):integrations={};data["integrations"]=integrations
options=integrations.get("alisIntergration")
if not isinstance(options,dict):options={};integrations["alisIntergration"]=options
for key,value in selected.items():
    if not isinstance(options.get(key),bool):options[key]=value
if data==json.loads(before):sys.exit(1 if sys.argv[2]=="check" else 0)
if sys.argv[2]=="check":sys.exit(0)
mode=stat.S_IMODE(path.stat().st_mode)
with tempfile.NamedTemporaryFile(dir=path.parent,delete=False) as output:
    temporary=Path(output.name);output.write((json.dumps(data,indent=4,ensure_ascii=False)+"\n").encode())
try:
    temporary.chmod(mode)
    if path.read_bytes()!=before:raise RuntimeError("Config changed during migration; retry")
    os.replace(temporary,path)
finally:
    temporary.unlink(missing_ok=True)
PYTHON
}
migration_check() { _alis_intergration_preferences check; }
migration_preview() { printf '%s\n' 'Retain selected integration preferences; install no package and change no system state.'; }
migration_apply() {
    [[ -f "$(_alis_intergration_config)" ]] || return 0
    _alis_intergration_preferences apply
}
