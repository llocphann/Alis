#!/usr/bin/env python3
"""Check versioned Claude recovery using both source-built Rust and Python."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
for label, command in [
    ('python', [sys.executable, str(ROOT / 'scripts/colors/claude/theme_generator.py')]),
    ('rust', [str(ROOT / 'native/target/debug/alis-theme'), '--claude-theme']),
]:
    with tempfile.TemporaryDirectory() as directory:
        home = Path(directory)
        cli = home / '.claude/settings.json'
        desktop = home / '.config/Claude/config.json'
        state = home / '.local/state/quickshell/user/generated'
        for folder in [cli.parent, desktop.parent, state]:
            folder.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ, HOME=directory, XDG_CONFIG_HOME=str(home / '.config'),
                   XDG_STATE_HOME=str(home / '.local/state'), CLAUDE_CONFIG_DIR=str(cli.parent),
                   CLAUDE_DESKTOP_CONFIG_DIR=str(desktop.parent))
        colors = home / 'colors.json'
        colors.write_text(json.dumps({'background': '#101416', 'on_surface': '#dde4e6', 'primary': '#83d3e3'}))
        def run(strip=False, ok=True):
            result = subprocess.run(command + (['--strip'] if strip else ['--colors', str(colors)]),
                                    env=env, capture_output=True, text=True)
            assert (result.returncode == 0) == ok, result.stderr
        cli.write_text('{"theme":"light","permissions":{"keep":true}}')
        desktop.write_text('{"userThemeMode":"system","personal":"keep"}')
        run()
        journal = state / 'claude_desktop_prev_theme.json'
        saved = journal.read_bytes()
        desktop.write_text('{ invalid Owner data')
        run(strip=True, ok=False)
        assert desktop.read_text() == '{ invalid Owner data'
        assert journal.read_bytes() == saved, 'recovery metadata discarded after parse failure'
        desktop.write_text('{"userThemeMode":"dark","personal":"keep"}')
        run(strip=True)
        assert json.loads(desktop.read_text()) == {'userThemeMode':'system','personal':'keep'}
        assert json.loads(cli.read_text()) == {'theme':'light','permissions':{'keep':True}}
        run()
        desktop.write_text('{"userThemeMode":"light","personal":"keep"}')
        cli.write_text('{"theme":"Owner theme","permissions":{"keep":true}}')
        run(strip=True)
        assert json.loads(desktop.read_text())['userThemeMode'] == 'light'
        assert json.loads(cli.read_text())['theme'] == 'Owner theme'
        legacy = state / 'claude_desktop_prev_theme.txt'
        legacy.write_text('system\n')
        before = desktop.read_bytes()
        run(strip=True)
        assert desktop.read_bytes() == before and legacy.exists(), 'legacy ownership guessed'
        cli.write_text('{"permissions":{"keep":true}}')
        desktop.write_text('{"personal":"keep"}')
        run()
        run()
        run(strip=True)
        assert json.loads(cli.read_text()) == {'permissions':{'keep':True}}
        assert json.loads(desktop.read_text()) == {'personal':'keep'}
        print(f'PASS {label}: malformed metadata retention, later Owner edits, legacy unknown state, repeated apply and absent-value restore')
