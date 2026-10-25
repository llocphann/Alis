#!/usr/bin/env python3
"""Core install/update/remove must not mutate optional system integration state."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="hadalird-core-lifecycle-") as name:
    private = Path(name)
    marker = private / "system-mutation"
    env = dict(os.environ,MARKER=str(marker))
    forbidden = '''
pkg_sudo(){ printf '%s\\n' "$*" >> "$MARKER"; return 99; }
elevate(){ printf '%s\\n' "$*" >> "$MARKER"; return 99; }
systemctl(){ printf '%s\\n' "$*" >> "$MARKER"; return 99; }
tui_info(){ :; }
'''
    for filename in ("037-battery-charge-limit-helper.sh","038-tlp-profile-backend.sh","041-thinkfan-helper-bridge.sh"):
        script = ROOT / "sdata/migrations" / filename
        result = subprocess.run(["bash","-c",forbidden+'''
source "$1"
[[ "$MIGRATION_REQUIRED" == false ]] || exit 1
migration_check; [[ $? == 1 ]] || exit 1
migration_apply
''',"fixture",str(script)],env=env,text=True,capture_output=True)
        assert result.returncode==0,result.stderr
    result = subprocess.run(["bash","-c",forbidden+'''
source "$1"
uninstall_remove_battery_charge_limit
uninstall_remove_thinkfan_bridge
''',"fixture",str(ROOT/"sdata/lib/uninstall.sh")],env=env,text=True,capture_output=True)
    assert result.returncode==0,result.stderr
    assert not marker.exists(),"core lifecycle changed optional hardware state"
    # Inspect the complete default target expansion, including dependencies.
    for target in ("install","uninstall"):
        result = subprocess.run(["make","-n",target,"DESTDIR="+str(private/"stage")],cwd=ROOT,text=True,capture_output=True)
        assert result.returncode==0,result.stderr
        assert "assets/helpers/inir-thinkfan" not in result.stdout
        assert "assets/helpers/inir-battery-charge-limit" not in result.stdout
        assert "--config-reset" not in result.stdout and "--disable" not in result.stdout
print("HADALIRD_CORE_LIFECYCLE_PASS retired migrations/default make targets/removal preserve optional hardware state")
