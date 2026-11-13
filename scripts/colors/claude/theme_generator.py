#!/usr/bin/env python3
"""
Alis Material Theme Generator for Claude Code CLI (~/.claude/themes/alis.json & settings.json)
and Claude Desktop (~/.config/Claude/config.json).
Python fallback for `alis-theme --claude-theme`.
"""

import argparse
import colorsys
import json
import os
import re
import tempfile
from pathlib import Path

CLAUDE_THEME_SLUG = "alis"
CLAUDE_THEME_REF = "custom:alis"
CLAUDE_THEME_FILE = "alis.json"
CLAUDE_PREV_THEME_STATE = "claude_prev_theme.txt"
CLAUDE_DESKTOP_PREV_THEME_STATE = "claude_desktop_prev_theme.txt"


def hex_to_rgb(hex_str: str) -> tuple[int, int, int]:
    h = hex_str.lstrip("#")
    if len(h) < 6:
        return (0, 0, 0)
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def rgb_to_hex(r: int, g: int, b: int) -> str:
    return f"#{max(0, min(255, r)):02x}{max(0, min(255, g)):02x}{max(0, min(255, b)):02x}"


def blend(c1: str, c2: str, factor: float) -> str:
    r1, g1, b1 = hex_to_rgb(c1)
    r2, g2, b2 = hex_to_rgb(c2)
    return rgb_to_hex(
        int(r1 + (r2 - r1) * factor),
        int(g1 + (g2 - g1) * factor),
        int(b1 + (b2 - b1) * factor),
    )


def is_dark_hex(hex_str: str) -> bool:
    r, g, b = [x / 255.0 for x in hex_to_rgb(hex_str)]
    _, l, _ = colorsys.rgb_to_hls(r, g, b)
    return l < 0.5


def parse_scss(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    pattern = re.compile(r"\$(\w+):\s*(#[A-Fa-f0-9]{6}|True|False);")
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        m = pattern.search(line.strip())
        if m:
            out[m.group(1)] = m.group(2)
    return out


def read_string_map_json(path: Path) -> dict[str, str]:
    if not path.is_file():
        return {}
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(raw, dict):
            return {k: v for k, v in raw.items() if isinstance(v, str)}
    except Exception:
        pass
    return {}


def write_if_changed(path: Path, content: str) -> bool:
    data = content.encode("utf-8")
    if path.is_file():
        try:
            if path.read_bytes() == data:
                return False
        except Exception:
            pass
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=f'.{path.name}.', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        if path.exists():
            os.chmod(temp, path.stat().st_mode & 0o777)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    return True


def build_claude_theme_json(colors: dict[str, str], term_colors: dict[str, str]) -> tuple[dict, bool]:
    def pick(key: str, fallback: str) -> str:
        val = colors.get(key, "")
        return val if val else fallback

    bg = pick("background", pick("surface", "#0f1417"))
    dark = is_dark_hex(bg)
    base = "dark" if dark else "light"

    primary = pick("primary", "#7aa2f7")
    secondary = pick("secondary", "#bb9af7")
    tertiary = pick("tertiary", "#9ece6a")
    on_surface = pick("on_surface", pick("onSurface", "#dfe3e7"))
    on_surface_variant = pick("on_surface_variant", pick("onSurfaceVariant", "#c1c7ce"))
    inverse_on_surface = pick("inverse_on_surface", pick("inverseOnSurface", "#1a1c1e"))
    surface_container = pick("surface_container", pick("surfaceContainer", "#1c2024"))
    surface_container_low = pick("surface_container_low", pick("surfaceContainerLow", "#181c1f"))
    surface_container_high = pick("surface_container_high", pick("surfaceContainerHigh", "#262b2e"))
    surface_container_highest = pick("surface_container_highest", pick("surfaceContainerHighest", "#313539"))
    outline = pick("outline", "#8b9298")
    outline_variant = pick("outline_variant", pick("outlineVariant", "#41484d"))
    error_col = pick("error", "#ffb4ab")

    def term_col(idx: int, fb: str) -> str:
        v = term_colors.get(f"term{idx}", "") or colors.get(f"term{idx}", "")
        return v if v else fb

    col_keyword = term_col(5, secondary)
    col_string = term_col(2, tertiary)
    col_function = term_col(4, primary)
    col_type = term_col(6, tertiary)
    col_constant = term_col(3, secondary)
    col_property = blend(col_function, col_type, 0.5)

    primary_shimmer = blend(primary, on_surface, 0.35)
    warning_shimmer = blend(col_type, on_surface, 0.30)
    fast_shimmer = blend(col_constant, on_surface, 0.35)
    diff_added = blend(surface_container, col_string, 0.22 if dark else 0.18)
    diff_removed = blend(surface_container, error_col, 0.22 if dark else 0.18)
    diff_added_dim = blend(surface_container, col_string, 0.12)
    diff_removed_dim = blend(surface_container, error_col, 0.12)
    diff_added_word = blend(surface_container, col_string, 0.42 if dark else 0.32)
    diff_removed_word = blend(surface_container, error_col, 0.42 if dark else 0.32)
    selection_bg = blend(bg, primary, 0.30 if dark else 0.22)

    payload = {
        "name": "Alis Material",
        "base": base,
        "overrides": {
            "background": bg,
            "text": on_surface,
            "inverseText": inverse_on_surface,
            "claude": primary,
            "claudeShimmer": primary_shimmer,
            "claudeBlue_FOR_SYSTEM_SPINNER": primary,
            "claudeBlueShimmer_FOR_SYSTEM_SPINNER": primary_shimmer,
            "autoAccept": tertiary,
            "skill": secondary,
            "bashBorder": primary,
            "permission": primary,
            "permissionShimmer": primary_shimmer,
            "planMode": secondary,
            "ide": tertiary,
            "promptBorder": outline_variant,
            "promptBorderShimmer": outline,
            "inactive": outline,
            "inactiveShimmer": on_surface_variant,
            "subtle": outline_variant,
            "suggestion": primary,
            "remember": tertiary,
            "success": col_string,
            "error": error_col,
            "warning": col_type,
            "warningShimmer": warning_shimmer,
            "merged": col_keyword,
            "diffAdded": diff_added,
            "diffRemoved": diff_removed,
            "diffAddedDimmed": diff_added_dim,
            "diffRemovedDimmed": diff_removed_dim,
            "diffAddedWord": diff_added_word,
            "diffRemovedWord": diff_removed_word,
            "userMessageBackground": surface_container_high,
            "userMessageBackgroundHover": surface_container_highest,
            "composerSidebarBackground": surface_container_low,
            "selectionBg": selection_bg,
            "bashMessageBackgroundColor": surface_container,
            "memoryBackgroundColor": surface_container_high,
            "rate_limit_fill": primary,
            "rate_limit_empty": surface_container_highest,
            "fastMode": col_constant,
            "fastModeShimmer": fast_shimmer,
            "effortUltra": col_keyword,
            "briefLabelYou": col_function,
            "briefLabelClaude": primary,
            "professionalBlue": col_function,
            "chromeYellow": col_type,
            "clawd_body": primary,
            "clawd_background": bg,
            "red_FOR_SUBAGENTS_ONLY": error_col,
            "blue_FOR_SUBAGENTS_ONLY": col_function,
            "green_FOR_SUBAGENTS_ONLY": col_string,
            "yellow_FOR_SUBAGENTS_ONLY": col_type,
            "purple_FOR_SUBAGENTS_ONLY": col_keyword,
            "orange_FOR_SUBAGENTS_ONLY": col_constant,
            "pink_FOR_SUBAGENTS_ONLY": secondary,
            "cyan_FOR_SUBAGENTS_ONLY": col_property,
            "rainbow_red": error_col,
            "rainbow_orange": col_constant,
            "rainbow_yellow": col_type,
            "rainbow_green": col_string,
            "rainbow_blue": col_function,
            "rainbow_indigo": primary,
            "rainbow_violet": col_keyword,
            "rainbow_red_shimmer": blend(error_col, on_surface, 0.35),
            "rainbow_orange_shimmer": blend(col_constant, on_surface, 0.35),
            "rainbow_yellow_shimmer": blend(col_type, on_surface, 0.35),
            "rainbow_green_shimmer": blend(col_string, on_surface, 0.35),
            "rainbow_blue_shimmer": blend(col_function, on_surface, 0.35),
            "rainbow_indigo_shimmer": primary_shimmer,
            "rainbow_violet_shimmer": blend(col_keyword, on_surface, 0.35),
        },
    }
    return payload, dark


def load_json_object(path: Path) -> dict:
    if not path.is_file():
        return {}
    text = path.read_text(encoding="utf-8")
    if not text.strip():
        return {}
    obj = json.loads(text)
    if not isinstance(obj, dict):
        raise ValueError(f"Expected settings object: {path}")
    return obj


def manage_theme_setting(path: Path, legacy: Path, key: str, desired: str | None) -> None:
    journal = legacy.with_suffix('.json')
    settings = load_json_object(path)
    current = {'present': key in settings, 'value': settings.get(key)}
    state = load_json_object(journal)
    if state and (state.get('version') != 1 or state.get('path') != str(path) or state.get('key') != key):
        raise ValueError(f'Unsupported theme recovery state: {journal}')
    if desired is not None:
        previous = state['previous'] if state and current == state['applied'] else current
        if not state and key == 'theme' and current['value'] == CLAUDE_THEME_REF and legacy.is_file():
            previous = {'present': True, 'value': legacy.read_text().strip()}
        applied = {'present': True, 'value': desired}
        write_if_changed(journal, json.dumps({'version': 1, 'path': str(path), 'key': key,
                                             'previous': previous, 'applied': applied}, indent=2) + '\n')
        settings[key] = desired
    elif state:
        if current != state['applied']:
            journal.unlink()  # Owner changed the value; retain it.
            return
        if state['previous']['present']:
            settings[key] = state['previous']['value']
        else:
            settings.pop(key, None)
    elif key == 'theme' and current['value'] == CLAUDE_THEME_REF:
        old = legacy.read_text().strip() if legacy.is_file() else ''
        if old:
            settings[key] = old
        else:
            settings.pop(key, None)
    else:
        # A legacy Desktop text file has no applied value. Keep both the Owner
        # setting and recovery metadata instead of guessing which mode we own.
        return
    write_if_changed(path, json.dumps(settings, indent=2) + '\n')
    if desired is None:
        journal.unlink(missing_ok=True)
        if key == 'theme':
            legacy.unlink(missing_ok=True)


def main() -> int:
    home = Path(os.environ.get("HOME", "/tmp"))
    state_dir = Path(os.environ.get("XDG_STATE_HOME") or (home / ".local/state")) / "quickshell/user/generated"
    xdg_config = Path(os.environ.get("XDG_CONFIG_HOME") or (home / ".config"))
    parser = argparse.ArgumentParser(description="Generate Alis theme for Claude Code & Claude Desktop")
    parser.add_argument("--colors", type=Path, default=state_dir / "palette.json")
    parser.add_argument("--terminal-json", type=Path, default=state_dir / "terminal.json")
    parser.add_argument("--scss", type=Path, default=state_dir / "material_colors.scss")
    parser.add_argument("--strip", action="store_true")
    args = parser.parse_args()

    claude_dir = Path(os.environ.get("CLAUDE_CONFIG_DIR") or (home / ".claude"))
    theme_path = claude_dir / "themes" / CLAUDE_THEME_FILE
    settings_path = claude_dir / "settings.json"
    prev_state_path = state_dir / CLAUDE_PREV_THEME_STATE

    desktop_dir = Path(os.environ.get("CLAUDE_DESKTOP_CONFIG_DIR") or (xdg_config / "Claude"))
    desktop_config_path = desktop_dir / "config.json"
    prev_desktop_state_path = state_dir / CLAUDE_DESKTOP_PREV_THEME_STATE

    if args.strip:
        manage_theme_setting(settings_path, prev_state_path, 'theme', None)
        manage_theme_setting(desktop_config_path, prev_desktop_state_path, 'userThemeMode', None)
        if theme_path.is_file():
            theme_path.unlink(missing_ok=True)
        print(f"[claude] Stripped Alis theme ({CLAUDE_THEME_SLUG})")
        return 0

    colors_path: Path = args.colors
    if not colors_path.is_file():
        fb = state_dir / "colors.json"
        if fb.is_file():
            colors_path = fb

    colors = parse_scss(args.scss)
    colors.update(read_string_map_json(colors_path))
    term_colors = parse_scss(args.scss)
    term_colors.update(read_string_map_json(args.terminal_json))

    payload, is_dark = build_claude_theme_json(colors, term_colors)
    write_if_changed(theme_path, json.dumps(payload, indent=2) + "\n")

    manage_theme_setting(settings_path, prev_state_path, 'theme', CLAUDE_THEME_REF)

    if desktop_dir.is_dir() or desktop_config_path.is_file():
        desired_mode = "dark" if is_dark else "light"
        manage_theme_setting(desktop_config_path, prev_desktop_state_path, 'userThemeMode', desired_mode)

    print(f"[claude] Theme generated: {theme_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
