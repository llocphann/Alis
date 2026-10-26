#!/usr/bin/env python3
"""The audit catches active quoted legacy commands while allowing inputs."""
from pathlib import Path
import contextlib
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('brand_audit', ROOT / 'scripts/brand-canonical-audit.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    subprocess.run(['git', 'init', '-q', tmp], check=True)
    (root / 'scripts/lib').mkdir(parents=True)
    fixture = root / 'scripts/lib/ipc-registry.sh'
    fixture.write_text('spawn "inir" "settings"\nexec inir help\n')
    subprocess.run(['git', '-C', tmp, 'add', '.'], check=True)
    def run():
        out = io.StringIO()
        with patch.object(audit, 'ROOT', root), patch.object(sys, 'argv', ['audit', '--strict']), contextlib.redirect_stdout(out):
            rc = audit.main()
        return rc, json.loads(out.getvalue())
    rc, result = run()
    assert rc == 2 and result['by_kind']['launcher'] == 2, result
    fixture.write_text('spawn "alis" "settings"\nexec alis help\n')
    (root / 'nix').mkdir()
    (root / 'nix/home-module.nix').write_text('imports = [ common.optionsModule (lib.mkAliasOptionModule [ "programs" "inir" ] [ "programs" "alis" ]) ];\n')
    (root / 'setup').write_text('local retired_path="${XDG_STATE_HOME:-$HOME/.local/state}/alis-cutover-backups/retired-inir.service"\n')
    subprocess.run(['git', '-C', tmp, 'add', '.'], check=True)
    rc, result = run()
    assert rc == 0 and result['remaining_active_references'] == 0, result
    with (root / 'setup').open('a') as stream:
        stream.write('systemctl --user start inir.service\n')
    rc, result = run()
    assert rc == 2 and result['by_kind']['service'] == 1, result
print('PASS: quoted retired commands and active unit operations refused; exact recovery/config aliases accepted')
