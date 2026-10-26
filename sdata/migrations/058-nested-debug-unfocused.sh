#!/usr/bin/env bash
MIGRATION_ID="058-nested-debug-unfocused"
MIGRATION_TITLE="Keep nested debug windows unfocused"
MIGRATION_DESCRIPTION="Keeps Niri test windows from interrupting the focused application; capture tools can focus explicitly."
MIGRATION_REQUIRED=true
MIGRATION_TARGET_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.d/90-user-extra.kdl"
migration_check() {
    [[ -f "$MIGRATION_TARGET_FILE" ]] || return 1
    ! grep -Fq '// Hadalis nested debug focus policy' "$MIGRATION_TARGET_FILE"
}
migration_preview() { printf '%s\n' '+ Nested Niri windows open without taking focus'; }
migration_apply() {
    migration_check || return 0
    python3 - "$MIGRATION_TARGET_FILE" <<'PYTHON'
from pathlib import Path
import os, stat, sys, tempfile
path=Path(sys.argv[1]); before=path.read_bytes(); mode=stat.S_IMODE(path.stat().st_mode)
block=b'\n// Hadalis nested debug focus policy\nwindow-rule {\n    match app-id=r#"^niri$"#\n    open-focused false\n}\n'
with tempfile.NamedTemporaryFile(dir=path.parent,delete=False) as output:
    temporary=Path(output.name); output.write(before+block)
try:
    temporary.chmod(mode)
    if path.read_bytes()!=before: raise RuntimeError("Niri overrides changed during migration; retry")
    os.replace(temporary,path)
finally:
    temporary.unlink(missing_ok=True)
PYTHON
}
