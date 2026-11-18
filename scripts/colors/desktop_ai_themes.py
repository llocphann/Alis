#!/usr/bin/env python3
"""Merge supported Codex desktop and Antigravity App theme settings.

These are different products from their CLIs and the legacy Antigravity IDE.
Only managed color leaves are changed; the journal supports retry and opt-out.
"""
from __future__ import annotations

import argparse
import copy
import fcntl
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
import tomllib


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text()) if path.exists() else {}
    if not isinstance(value, dict):
        raise ValueError(f"Expected an object: {path}")
    return value


def atomic_write(path: Path, content: str) -> None:
    data = content.encode()
    if path.exists() and not path.is_symlink():
        if path.read_bytes() == data:
            return
        # Write in-place so open Electron/Node fs.watch (inotify) descriptors
        # in Codex Desktop and Antigravity keep watching the same inode.
        with path.open("r+b") as stream:
            stream.seek(0)
            stream.write(data)
            stream.truncate()
            stream.flush()
            os.fsync(stream.fileno())
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def get_leaf(obj: dict, keys: tuple[str, ...]) -> dict:
    for key in keys:
        if not isinstance(obj, dict) or key not in obj:
            return {"present": False}
        obj = obj[key]
    return {"present": True, "value": obj}


def set_leaf(obj: dict, keys: tuple[str, ...], record: dict) -> None:
    for key in keys[:-1]:
        if key not in obj:
            if not record["present"]:
                return
            obj[key] = {}
        if not isinstance(obj[key], dict):
            raise ValueError(f"Expected object at {'.'.join(keys)}")
        obj = obj[key]
    if record["present"]:
        obj[keys[-1]] = record["value"]
    else:
        obj.pop(keys[-1], None)


import stat


CHROME_THEME_DEFAULTS = {
    'Dark': {
        'contrast': 60,
        'semanticColors': {'diffAdded': '#40c977', 'diffRemoved': '#fa423e', 'skill': '#ad7bf9'},
    },
    'Light': {
        'contrast': 45,
        'semanticColors': {'diffAdded': '#00a240', 'diffRemoved': '#ba2623', 'skill': '#924ff7'},
    },
}


def _format_toml_value(value: object) -> str:
    """Serialize a TOML leaf (str, int, bool, float, list, or inline table) cleanly."""
    if isinstance(value, dict):
        parts = []
        for k, v in value.items():
            ks = str(k)
            key_repr = ks if re.fullmatch(r'[A-Za-z0-9_-]+', ks) else json.dumps(ks, ensure_ascii=False)
            parts.append(f'{key_repr} = {_format_toml_value(v)}')
        return '{' + ', '.join(parts) + '}'
    if isinstance(value, list):
        return '[' + ', '.join(_format_toml_value(v) for v in value) + ']'
    if isinstance(value, (bool, int, float, str)):
        return json.dumps(value, ensure_ascii=False)
    raise ValueError(f'Unsupported TOML value type: {type(value).__name__}')


def _find_toml_section(lines: list[str], section: str) -> tuple[int | None, int]:
    start = None
    for index, line in enumerate(lines):
        match = re.match(r'^\s*\[([^\[\]]+)\]\s*(?:#.*)?$', line.strip())
        if match:
            if start is not None:
                return start, index
            if match[1].strip() == section:
                start = index
    return start, len(lines)


def patch_toml(text: str, changes: dict[tuple[str, ...], dict]) -> str:
    """Edit individual standard table assignments, retaining unrelated bytes."""
    lines = text.splitlines(keepends=True)
    touched_sections: set[str] = set()
    for keys, record in changes.items():
        section, key = '.'.join(keys[:-1]), keys[-1]
        sub_section = f'{section}.{key}' if section else key
        sub_start, _ = _find_toml_section(lines, sub_section)
        # Do not emit `fonts = {}` into [section] if `[section.fonts]` already exists cleanly.
        if sub_start is not None:
            current_parsed = tomllib.loads(''.join(lines))
            if get_leaf(current_parsed, keys) == record:
                continue
            if not record['present']:
                touched_sections.add(sub_section)
                continue
        start, end = _find_toml_section(lines, section)
        value_line = f'{key} = {_format_toml_value(record.get("value"))}\n' if record['present'] else ''
        if start is None:
            if record['present']:
                if lines:
                    if not lines[-1].endswith('\n'):
                        lines[-1] += '\n'
                    lines += [f'\n[{section}]\n', value_line]
                else:
                    lines += [f'[{section}]\n', value_line]
            continue
        assignment = re.compile(r'^\s*' + re.escape(key) + r'\s*=')
        found = next((i for i in range(start + 1, end) if assignment.match(lines[i])), None)
        if found is not None:
            if record['present']:
                lines[found] = value_line
            else:
                del lines[found]
                touched_sections.add(section)
        elif record['present']:
            lines.insert(start + 1, value_line)
    # Remove any sections we emptied during restoration/strip (never touching pre-existing comments/subtables).
    if touched_sections:
        headers: list[tuple[int, str]] = []
        for idx, line in enumerate(lines):
            match = re.match(r'^\s*\[([^\[\]]+)\]\s*(?:#.*)?$', line.strip())
            if match:
                headers.append((idx, match[1].strip()))
        for pos in range(len(headers) - 1, -1, -1):
            hdr_idx, sec_name = headers[pos]
            if sec_name not in touched_sections:
                continue
            body_end = headers[pos + 1][0] if pos + 1 < len(headers) else len(lines)
            if all(not ln.strip() for ln in lines[hdr_idx + 1 : body_end]):
                del lines[hdr_idx:body_end]
                if hdr_idx > 0 and not lines[hdr_idx - 1].strip() and (hdr_idx == len(lines) or not lines[hdr_idx].strip()):
                    del lines[hdr_idx - 1]
    updated = ''.join(lines)
    parsed = tomllib.loads(updated)
    for keys, record in changes.items():
        if get_leaf(parsed, keys) != record:
            raise ValueError(f"Unsupported TOML layout at {'.'.join(keys)}; settings unchanged")
    return updated


def manage(path: Path, journal_path: Path, desired: dict[tuple[str, ...], object], enabled: bool, kind: str) -> bool:
    journal_path.parent.mkdir(parents=True, exist_ok=True)
    with journal_path.with_suffix('.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return _manage(path, journal_path, desired, enabled, kind)


def _manage(path: Path, journal_path: Path, desired: dict[tuple[str, ...], object], enabled: bool, kind: str) -> bool:
    if not path.exists() and not journal_path.exists():
        return False
    original = path.read_text() if path.exists() else ''
    obj = tomllib.loads(original) if kind == 'toml' else read_json(path)
    journal = read_json(journal_path)
    if journal and (journal.get('version') != 1 or journal.get('path') != str(path)):
        raise ValueError(f"Unsupported theme journal: {journal_path}")
    journal = journal or {"version": 1, "path": str(path), "leaves": {}}
    changes = {}
    if enabled:
        for keys, value in desired.items():
            name = '.'.join(keys)
            applied = {"present": True, "value": value}
            old = journal['leaves'].get(name)
            current = get_leaf(obj, keys)
            # An Owner edit made since the last apply becomes the new restore value.
            previous = old['previous'] if old and current == old['applied'] else current
            journal['leaves'][name] = {"keys": list(keys), "previous": previous, "applied": applied}
            changes[keys] = applied
    else:
        for entry in journal['leaves'].values():
            keys = tuple(entry['keys'])
            if get_leaf(obj, keys) == entry['applied']:
                changes[keys] = entry['previous']
    if kind == 'toml':
        updated = patch_toml(original, changes)
    else:
        merged = copy.deepcopy(obj)
        for keys, record in changes.items():
            set_leaf(merged, keys, record)
        updated = json.dumps(merged, indent=2, ensure_ascii=False) + '\n'
    if enabled:
        # Persist recovery metadata before changing user settings.
        atomic_write(journal_path, json.dumps(journal, indent=2) + '\n')
    changed = bool(changes and updated != original)
    if changed:
        if (path.read_text() if path.exists() else '') != original:
            raise ValueError(f"Settings changed during theme merge; retry required: {path}")
        atomic_write(path, updated)
    if not enabled and journal_path.exists():
        journal_path.unlink()
    return changed


def _codex_desired(
    codex_path: Path,
    codex_journal: Path,
    variant: str,
    mode: str,
    bg: str,
    primary: str,
    ink: str,
) -> dict[tuple[str, ...], object]:
    """Build complete ChatGPT/Codex Zod Chrome theme fields while preserving valid Owner defaults."""
    prefix = ('desktop', f'appearance{variant}ChromeTheme')
    desired: dict[tuple[str, ...], object] = {
        ('desktop', 'appearanceTheme'): mode,
        prefix + ('accent',): primary,
        prefix + ('accentSource',): 'custom',
        prefix + ('ink',): ink,
        prefix + ('opaqueWindows',): True,
        prefix + ('surface',): bg,
    }
    existing = tomllib.loads(codex_path.read_text()) if codex_path.is_file() else {}
    journal = read_json(codex_journal)
    leaves = journal.get('leaves', {}) if isinstance(journal, dict) else {}

    def keep_or_default(keys: tuple[str, ...], default: object, validator) -> None:
        old = leaves.get('.'.join(keys))
        current = get_leaf(existing, keys)
        if isinstance(old, dict) and current == old.get('applied'):
            desired[keys] = old['applied']['value']
        elif current['present'] and validator(current['value']):
            return
        else:
            desired[keys] = default

    defaults = CHROME_THEME_DEFAULTS[variant]
    is_hex = lambda v: isinstance(v, str) and bool(re.fullmatch(r'#[0-9a-fA-F]{6}', v))
    is_contrast = lambda v: isinstance(v, int) and not isinstance(v, bool) and 0 <= v <= 100
    is_fonts = lambda v: isinstance(v, dict)
    keep_or_default(prefix + ('contrast',), defaults['contrast'], is_contrast)
    keep_or_default(prefix + ('fonts',), {}, is_fonts)
    for sem_key, sem_default in defaults['semanticColors'].items():
        keep_or_default(prefix + ('semanticColors', sem_key), sem_default, is_hex)
    return desired


def _codex_ipc_active(codex_dir: Path) -> bool:
    """Return True if a running ChatGPT/Codex IPC socket is present (passive lstat, offline-safe)."""
    try:
        st = (codex_dir / 'ipc' / 'ipc.sock').lstat()
        return stat.S_ISSOCK(st.st_mode)
    except OSError:
        return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--colors', required=True, type=Path)
    parser.add_argument('--codex', choices=['true', 'false'], required=True)
    parser.add_argument('--antigravity', choices=['true', 'false'], required=True)
    args = parser.parse_args()
    home = Path.home()
    state = Path(os.environ.get('XDG_STATE_HOME', home / '.local/state')) / 'quickshell/user/generated'
    xdg = Path(os.environ.get('XDG_CONFIG_HOME', home / '.config'))
    codex = Path(os.environ.get('CODEX_HOME', home / '.codex'))
    codex_path = codex / 'config.toml'
    codex_journal = state / 'codex_desktop_theme_state.json'
    codex_target = codex_path.is_file() and (any((xdg / n).is_dir() for n in ['Codex', 'ChatGPT']) or codex_journal.is_file())
    anti_path = home / '.gemini/config/config.json'
    anti_journal = state / 'antigravity_app_theme_state.json'
    anti_target = anti_path.is_file() or anti_journal.is_file()
    needs_palette = (codex_target and args.codex == 'true') or (anti_target and args.antigravity == 'true')
    # Restoration and absent optional apps must work without a generated palette.
    colors = read_json(args.colors) if needs_palette else {
        'background': '#000000', 'primary': '#ffffff', 'on_surface': '#ffffff'}
    def color(*names: str) -> str:
        value = next((colors[n] for n in names if n in colors), '')
        if not isinstance(value, str) or not re.fullmatch(r'#[0-9a-fA-F]{6}', value):
            raise ValueError(f"Missing or invalid color: {names[0]}")
        return value
    bg = color('background', 'surface')
    rgb = [int(bg[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    dark = (max(rgb) + min(rgb)) / 2 < .5
    variant, mode = ('Dark', 'dark') if dark else ('Light', 'light')
    primary = color('primary')
    ink = color('on_surface', 'onSurface')
    failed = False
    if codex_target:
        try:
            desired = (
                _codex_desired(codex_path, codex_journal, variant, mode, bg, primary, ink)
                if args.codex == 'true'
                else {}
            )
            changed = manage(codex_path, codex_journal, desired, args.codex == 'true', 'toml')
            if changed and _codex_ipc_active(codex):
                # ChatGPT Desktop SettingsStore loads config.toml at startup only (no fs.watch;
                # ipc.sock only handles thread/worker messages & non-settings query-cache-invalidate).
                print(
                    '[codex-desktop] Updated config.toml; restart ChatGPT/Codex desktop for outer shell chrome changes to apply.',
                    file=sys.stderr,
                )
        except (OSError, ValueError) as error:
            print(f'[codex-desktop] {error}', file=sys.stderr)
            failed = True
    if anti_target:
        prefix = ('userSettings', f'customThemeSeeds{variant}')
        desired = {
            ('userSettings', 'themeMode'): f'THEME_MODE_{mode.upper()}',
            prefix + ('background',): bg,
            prefix + ('foregroundOverride',): ink,
            prefix + ('primary',): primary,
        }
        try:
            manage(anti_path, anti_journal, desired, args.antigravity == 'true', 'json')
        except (OSError, ValueError) as error:
            print(f'[antigravity-app] {error}', file=sys.stderr)
            failed = True
    return int(failed)


if __name__ == '__main__':
    raise SystemExit(main())
