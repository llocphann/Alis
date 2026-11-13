#!/usr/bin/env python3
"""Runtime fixtures for independent desktop AI theme settings and recovery."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'scripts/colors/desktop_ai_themes.py'
spec = importlib.util.spec_from_file_location('desktop_ai_themes', HELPER)
themes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(themes)


def main():
    with tempfile.TemporaryDirectory() as directory:
        home = Path(directory)
        env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'),
                   XDG_STATE_HOME=str(home / '.local/state'), CODEX_HOME=str(home / '.codex'),
                   CLAUDE_CONFIG_DIR=str(home / '.claude'), CLAUDE_DESKTOP_CONFIG_DIR=str(home / '.config/Claude'))
        codex = home / '.codex/config.toml'
        anti = home / '.gemini/config/config.json'
        codex.parent.mkdir(parents=True)
        anti.parent.mkdir(parents=True)
        (home / '.config/Codex').mkdir(parents=True)
        original = '# Preserve Owner comments\nmodel = "owner-model"\n[desktop]\nusePointerCursors = true\nappearanceTheme = "system"\n[desktop.appearanceDarkChromeTheme]\naccent = "#123456"\ncontrast = 61\n[desktop.appearanceDarkChromeTheme.fonts]\nui = "Owner Font"\n'
        codex.write_text(original)
        anti_original = {'userSettings': {'themeMode': 'THEME_MODE_INHERIT', 'customThemeSeedsDark':
                         {'background': '#112233', 'ownerSetting': True}, 'privatePreference': 'keep'},
                         'projects': [{'id': 'owner-id'}]}
        anti.write_text(json.dumps(anti_original))
        palette = home / 'palette.json'
        palette.write_text(json.dumps({'background': '#101416', 'on_surface': '#dde4e6', 'primary': '#83d3e3'}))

        def run(codex_flag='true', anti_flag='true', ok=True):
            proc = subprocess.run([sys.executable, str(HELPER), '--colors', str(palette),
                                   '--codex', codex_flag, '--antigravity', anti_flag],
                                  env=env, capture_output=True, text=True)
            assert (proc.returncode == 0) == ok, proc.stderr
        codex_ino_before = codex.stat().st_ino
        anti_ino_before = anti.stat().st_ino
        run()
        assert codex.stat().st_ino == codex_ino_before, 'codex config.toml inode replaced (breaks live fs.watch)'
        assert anti.stat().st_ino == anti_ino_before, 'antigravity config.json inode replaced (breaks live fs.watch)'
        c = tomllib.loads(codex.read_text())
        assert c['model'] == 'owner-model' and '# Preserve Owner comments' in codex.read_text()
        assert c['desktop']['appearanceTheme'] == 'dark'
        assert c['desktop']['appearanceDarkChromeTheme']['surface'] == '#101416'
        assert c['desktop']['appearanceDarkChromeTheme']['fonts']['ui'] == 'Owner Font'
        assert c['desktop']['appearanceDarkChromeTheme']['contrast'] == 61
        a = json.loads(anti.read_text())
        assert a['userSettings']['themeMode'] == 'THEME_MODE_DARK'
        assert a['userSettings']['customThemeSeedsDark']['primary'] == '#83d3e3'
        assert a['projects'] == anti_original['projects']
        first = (codex.read_bytes(), anti.read_bytes())
        codex_ino_before = codex.stat().st_ino
        anti_ino_before = anti.stat().st_ino
        run()
        assert codex.stat().st_ino == codex_ino_before, 'codex config.toml inode replaced (breaks live fs.watch)'
        assert anti.stat().st_ino == anti_ino_before, 'antigravity config.json inode replaced (breaks live fs.watch)'
        assert first == (codex.read_bytes(), anti.read_bytes()), 'repeat apply changed settings'

        # Existing users switching light/dark keep recovery for both variants.
        palette.write_text(json.dumps({'background': '#fafafa', 'on_surface': '#171717', 'primary': '#334455'}))
        codex_ino_before = codex.stat().st_ino
        anti_ino_before = anti.stat().st_ino
        run()
        assert codex.stat().st_ino == codex_ino_before, 'codex config.toml inode replaced (breaks live fs.watch)'
        assert anti.stat().st_ino == anti_ino_before, 'antigravity config.json inode replaced (breaks live fs.watch)'
        assert tomllib.loads(codex.read_text())['desktop']['appearanceTheme'] == 'light'
        a = json.loads(anti.read_text())
        a['userSettings']['customThemeSeedsLight']['primary'] = '#abcdef'
        anti.write_text(json.dumps(a))
        valid_palette = palette.read_text()
        palette.write_text('{ interrupted palette publication')
        run('false', 'false')
        palette.write_text(valid_palette)
        restored = tomllib.loads(codex.read_text())
        assert restored['desktop']['appearanceTheme'] == 'system'
        dark = restored['desktop']['appearanceDarkChromeTheme']
        assert dark['accent'] == '#123456' and 'surface' not in dark
        assert dark['fonts']['ui'] == 'Owner Font'
        a = json.loads(anti.read_text())
        assert a['userSettings']['themeMode'] == 'THEME_MODE_INHERIT'
        assert a['userSettings']['customThemeSeedsLight']['primary'] == '#abcdef', 'Owner edit overwritten on disable'
        assert a['userSettings']['customThemeSeedsDark'] == anti_original['userSettings']['customThemeSeedsDark']
        first = (codex.read_bytes(), anti.read_bytes())
        run('false', 'false')
        assert first == (codex.read_bytes(), anti.read_bytes()), 'repeat strip changed settings'

        # Malformed settings and a conflicting inline table must remain byte exact.
        codex.write_text('desktop = { appearanceTheme = "system" }\n')
        anti.write_text('{ malformed owner settings')
        first = (codex.read_bytes(), anti.read_bytes())
        run(ok=False)
        assert first == (codex.read_bytes(), anti.read_bytes())

        # Interrupted config write leaves a durable journal; retry/strip recovers.
        codex.write_text(original)
        journal = home / 'recovery.json'
        desired = {('desktop', 'appearanceTheme'): 'dark'}
        real_write = themes.atomic_write
        def interrupted(path, text):
            if path == codex:
                raise OSError('simulated interruption')
            real_write(path, text)
        with patch.object(themes, 'atomic_write', interrupted):
            try:
                themes.manage(codex, journal, desired, True, 'toml')
            except OSError:
                pass
            else:
                raise AssertionError('interruption not raised')
        assert journal.exists() and codex.read_text() == original
        themes.manage(codex, journal, desired, True, 'toml')
        themes.manage(codex, journal, desired, False, 'toml')
        assert tomllib.loads(codex.read_text()) == tomllib.loads(original)

        # Codex CLI-only installs never gain desktop preferences.
        (home / '.config/Codex').rmdir()
        anti.unlink()
        codex.write_text('model = "owner-model"\n')
        before = codex.read_bytes()
        run()
        assert codex.read_bytes() == before

        # The orchestration module applies desktop settings and invalidates its
        # cache after the app settings change, even with an unchanged palette.
        (home / '.config/Codex').mkdir()
        anti.write_text(json.dumps(anti_original))
        generated = home / '.local/state/quickshell/user/generated'
        generated.mkdir(parents=True, exist_ok=True)
        (generated / 'palette.json').write_text(palette.read_text())
        (generated / 'material_colors.scss').write_text('$background: #fafafa;\n')
        config = home / '.config/alis/config.json'
        config.parent.mkdir()
        flags = {'enableVSCode': True, 'enableCodex': True, 'enableClaude': False}
        config.write_text(json.dumps({'appearance': {'wallpaperTheming': flags}}))
        module_env = dict(env, ALIS_NATIVE_BACKEND='python')
        def module(ok=True):
            result = subprocess.run(['bash', str(ROOT / 'scripts/colors/modules/30-editors.sh')],
                                    env=module_env, capture_output=True, text=True)
            assert (result.returncode == 0) == ok, result.stderr
        module()
        signature = generated / '.editors-themegen-input.sig'
        first_sig = signature.read_bytes()
        module()
        assert signature.read_bytes() == first_sig
        a = json.loads(anti.read_text())
        a['userSettings']['themeMode'] = 'THEME_MODE_INHERIT'
        anti.write_text(json.dumps(a))
        module()
        assert json.loads(anti.read_text())['userSettings']['themeMode'] == 'THEME_MODE_LIGHT'
        anti.write_text('{ malformed owner settings')
        first_sig = signature.read_bytes()
        module(ok=False)
        assert anti.read_text() == '{ malformed owner settings'
        assert signature.read_bytes() == first_sig, 'failed merge cached as success'

        # The Claude Python fallback must fail without resetting malformed data.
        claude = home / '.claude/settings.json'
        claude.parent.mkdir(parents=True, exist_ok=True)
        claude.write_text('{ malformed personal permissions')
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/colors/claude/theme_generator.py'),
                                 '--colors', str(palette)], env=env, capture_output=True, text=True)
        assert result.returncode != 0
        assert claude.read_text() == '{ malformed personal permissions'
    print('PASS: desktop AI theme merge, mode switch, opt-out, Owner edits, invalid settings, interruption and CLI-only fixtures')


if __name__ == '__main__':
    main()
