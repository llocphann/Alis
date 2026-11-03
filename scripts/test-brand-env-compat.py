#!/usr/bin/env python3
"""Legacy user overrides remain inputs; no services or user files are changed."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'scripts/lib/brand-env-compat.sh'
SUFFIXES = '''RUNTIME_DIR SYSTEM_RUNTIME_DIR FALLBACK_SYSTEM_RUNTIME_DIR
SYSTEM_RUNTIME_DIR_LOCAL LEGACY_SYSTEM_RUNTIME_DIR_LOCAL LEGACY_SYSTEM_RUNTIME_DIR
RESTART_POLL_DELAY RESTART_MAX_POLLS MAX_RAPID_RESTARTS RESTART_WINDOW
DISABLE_HOT_RELOAD GPU_FORCE_DEFAULT QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE
LAUNCHER_PATH VENV NATIVE_BACKEND NATIVE_BIN_DIR NATIVE_STRICT MPD_SOCKET
SHELL_ROOT THEME_SKIP_SDDM_SYNC INSTALL_MODE UPDATE_STRATEGY REPO_PATH
PACKAGE_MANAGER PACKAGE_NAME PACKAGE_UPDATE_HINT'''.split()
base = {k: v for k, v in os.environ.items() if not k.startswith(('ALIS_', 'ALIS_'))}
for suffix in SUFFIXES:
    key = 'ALIS_' + suffix
    legacy = 'ALIS_' + suffix
    for canonical in (None, '', 'canonical value with spaces'):
        env = dict(base, **{legacy: 'retained value with spaces'})
        if canonical is not None:
            env[key] = canonical
        run = subprocess.run(['bash', '-eu', '-c',
                              'source "$1"; printenv "$2"', '_', str(HELPER), key],
                             env=env, capture_output=True, text=True, check=True)
        assert run.stdout.rstrip('\n') == (canonical if canonical is not None else env[legacy])

with tempfile.TemporaryDirectory() as tmp:
    home = Path(tmp)
    cfg = home / 'config'
    (cfg / 'alis').mkdir(parents=True)
    (cfg / 'alis/config.json').write_bytes(b'original preferences\n')
    env = dict(base, HOME=tmp, XDG_CONFIG_HOME=str(cfg))
    snippets = [
        (ROOT / 'scripts/lib/config-path.sh', 'alis_config_dir'),
        (ROOT / 'sdata/lib/environment-variables.sh', 'resolve_alis_config_dir'),
        (ROOT / 'sdata/lib/versioning.sh', 'printf "%s" "$CONFIG_DIR"'),
    ]
    for available, expected in ((None, 'alis'), ('illogical-impulse', 'illogical-impulse'), ('alis', 'alis')):
        if available:
            (cfg / available).mkdir()
        for script, command in snippets:
            run = subprocess.run(['bash', '-eu', '-c', 'REPO_ROOT="$3"; source "$1"; ' + command,
                                  '_', str(script), '', str(ROOT)], env=env,
                                 capture_output=True, text=True, check=True)
            assert run.stdout.rstrip('\n') == str(cfg / expected), (script, run.stdout)
    assert (cfg / 'alis/config.json').read_bytes() == b'original preferences\n'
    native_env = dict(env, ALIS_NATIVE_BACKEND='python', ALIS_NATIVE_BIN_DIR=str(home / 'custom bin'))
    run = subprocess.run(['bash', str(ROOT / 'scripts/native-dispatch'), 'backend-info'],
                         env=native_env, capture_output=True, text=True, check=True)
    assert 'mode=python\n' in run.stdout and 'bin_dir=' + str(home / 'custom bin') + '\n' in run.stdout
    run = subprocess.run(['bash', str(ROOT / 'scripts/alis'), 'help'],
                         env=dict(env, ALIS_RUNTIME_DIR=str(ROOT)), capture_output=True, text=True, check=True)
    assert 'Alis' in run.stdout
print(f'PASS: {len(SUFFIXES)} legacy overrides, canonical/empty precedence, exported child values, native dispatch and three config resolvers')
