#!/usr/bin/env python3
"""
Alis Material Theme Generator for OpenAI Codex CLI ($CODEX_HOME/themes/alis.tmTheme & config.toml).
Python fallback for `alis-theme --codex-theme`.
"""

import argparse
import colorsys
import json
import os
import re
from pathlib import Path

CODEX_THEME_SLUG = "alis"
CODEX_THEME_FILE = "alis.tmTheme"
CODEX_PREV_THEME_STATE = "codex_prev_theme.txt"


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
    path.write_bytes(data)
    return True


def xml_escape(s: str) -> str:
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def build_codex_tmtheme(colors: dict[str, str], term_colors: dict[str, str]) -> str:
    def pick(key: str, fallback: str) -> str:
        val = colors.get(key, "")
        return val if val else fallback

    bg = pick("background", pick("surface", "#0f1417"))
    dark = is_dark_hex(bg)
    primary = pick("primary", "#7aa2f7")
    secondary = pick("secondary", "#bb9af7")
    tertiary = pick("tertiary", "#9ece6a")
    on_surface = pick("on_surface", pick("onSurface", "#dfe3e7"))
    on_surface_variant = pick("on_surface_variant", pick("onSurfaceVariant", "#c1c7ce"))
    surface_container = pick("surface_container", pick("surfaceContainer", "#1c2024"))
    surface_container_low = pick("surface_container_low", pick("surfaceContainerLow", "#181c1f"))
    outline = pick("outline", "#8b9298")
    outline_variant = pick("outline_variant", pick("outlineVariant", "#41484d"))
    tertiary_container = pick("tertiary_container", pick("tertiaryContainer", tertiary))
    on_tertiary_container = pick("on_tertiary_container", pick("onTertiaryContainer", on_surface))
    error_col = pick("error", "#ffb4ab")

    def term_col(idx: int, fb: str) -> str:
        v = term_colors.get(f"term{idx}", "") or colors.get(f"term{idx}", "")
        return v if v else fb

    col_keyword = term_col(5, secondary)
    col_string = term_col(2, tertiary)
    col_function = term_col(4, primary)
    col_type = term_col(6, tertiary)
    col_constant = term_col(3, secondary)
    col_tag = term_col(1, error_col)
    col_property = blend(col_function, col_type, 0.5)
    comment_aa = blend(bg, on_surface_variant, 0.72)
    selection = blend(bg, primary, 0.28 if dark else 0.22)

    scopes = [
        ("Comment", "comment, punctuation.definition.comment", comment_aa, "italic"),
        ("Keyword", "keyword, storage, storage.type, storage.modifier, keyword.control, keyword.operator", col_keyword, None),
        ("Constant", "constant, constant.numeric, constant.language, constant.character, keyword.other.unit", col_constant, None),
        ("String", "string, string.quoted, string.template, punctuation.definition.string", col_string, None),
        ("Escape & Regexp", "string.regexp, constant.character.escape, string.escape", col_tag, None),
        ("Function", "entity.name.function, support.function, meta.function-call, entity.name.function.call", col_function, None),
        ("Type & Class", "entity.name.type, entity.name.class, support.type, support.class, entity.other.inherited-class", col_type, None),
        ("Variable", "variable, variable.other, variable.parameter", on_surface, None),
        ("Language Variable", "variable.language", col_tag, "italic"),
        ("Property & Attribute", "variable.other.property, support.variable.property, entity.other.attribute-name, meta.object-literal.key, support.type.property-name", col_property, None),
        ("Tag", "entity.name.tag, punctuation.definition.tag", col_tag, None),
        ("Punctuation", "punctuation, punctuation.separator, punctuation.terminator", on_surface_variant, None),
        ("Markdown Heading", "markup.heading, entity.name.section", col_function, "bold"),
        ("Markdown Bold", "markup.bold", on_surface, "bold"),
        ("Markdown Italic", "markup.italic", on_surface, "italic"),
        ("Markdown Link", "markup.underline.link, string.other.link", col_function, "underline"),
        ("Markdown Code", "markup.inline.raw, markup.fenced_code, markup.raw", col_string, None),
        ("Markdown Quote", "markup.quote", on_surface_variant, "italic"),
        ("Markdown List", "markup.list", col_keyword, None),
        ("Diff Inserted", "markup.inserted, diff.inserted", col_string, None),
        ("Diff Deleted", "markup.deleted, diff.deleted", error_col, None),
        ("Diff Changed", "markup.changed, diff.changed", col_constant, None),
        ("Diff Header", "meta.diff, meta.diff.header", secondary, None),
        ("Invalid", "invalid, invalid.deprecated", error_col, None),
    ]

    rules_xml = []
    for name, scope, fg, style in scopes:
        style_xml = (
            f"        <key>fontStyle</key>\n        <string>{xml_escape(style)}</string>\n"
            if style
            else ""
        )
        rules_xml.append(
            f"    <dict>\n"
            f"      <key>name</key>\n      <string>{xml_escape(name)}</string>\n"
            f"      <key>scope</key>\n      <string>{xml_escape(scope)}</string>\n"
            f"      <key>settings</key>\n      <dict>\n"
            f"        <key>foreground</key>\n        <string>{xml_escape(fg)}</string>\n"
            f"{style_xml}"
            f"      </dict>\n    </dict>\n"
        )

    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        '<plist version="1.0">\n'
        "<dict>\n"
        "  <key>name</key>\n"
        "  <string>Alis Material</string>\n"
        "  <key>settings</key>\n"
        "  <array>\n"
        "    <dict>\n"
        "      <key>settings</key>\n"
        "      <dict>\n"
        f"        <key>background</key>\n        <string>{bg}</string>\n"
        f"        <key>foreground</key>\n        <string>{on_surface}</string>\n"
        f"        <key>caret</key>\n        <string>{primary}</string>\n"
        f"        <key>selection</key>\n        <string>{selection}</string>\n"
        f"        <key>selectionForeground</key>\n        <string>{on_surface}</string>\n"
        f"        <key>lineHighlight</key>\n        <string>{surface_container}</string>\n"
        f"        <key>findHighlight</key>\n        <string>{tertiary_container}</string>\n"
        f"        <key>findHighlightForeground</key>\n        <string>{on_tertiary_container}</string>\n"
        f"        <key>gutter</key>\n        <string>{surface_container_low}</string>\n"
        f"        <key>gutterForeground</key>\n        <string>{outline}</string>\n"
        f"        <key>activeGuide</key>\n        <string>{primary}</string>\n"
        f"        <key>guide</key>\n        <string>{outline_variant}</string>\n"
        "      </dict>\n"
        "    </dict>\n"
        + "".join(rules_xml)
        + "  </array>\n</dict>\n</plist>\n"
    )


def _parse_toml_str(raw: str) -> str | None:
    t = raw.split("#", 1)[0].strip()
    if len(t) >= 2 and ((t[0] == '"' and t[-1] == '"') or (t[0] == "'" and t[-1] == "'")):
        return t[1:-1]
    return None


def _toml_section(line: str) -> str | None:
    t = line.split("#", 1)[0].strip()
    if t.startswith("[") and t.endswith("]") and not t.startswith("[["):
        return t[1:-1].strip()
    return None


def update_codex_config_toml(existing: str, theme_slug: str = CODEX_THEME_SLUG) -> tuple[str, str | None]:
    if not existing.strip():
        return f'[tui]\ntheme = "{theme_slug}"\n', None

    lines = existing.splitlines()
    out_lines: list[str] = []
    prev_theme: str | None = None

    tui_start: int | None = None
    tui_end = len(lines)
    for idx, line in enumerate(lines):
        sec = _toml_section(line)
        if sec is not None:
            if tui_start is not None:
                tui_end = idx
                break
            if sec == "tui":
                tui_start = idx

    if tui_start is not None:
        found = False
        has_later = any(
            line.split("#", 1)[0].split("=", 1)[0].strip() == "theme"
            for line in lines[tui_start + 1 : tui_end]
            if "=" in line.split("#", 1)[0]
        )
        for idx, line in enumerate(lines):
            if tui_start < idx < tui_end and not found:
                code = line.split("#", 1)[0]
                if "=" in code:
                    k, v = code.split("=", 1)
                    if k.strip() == "theme":
                        old = _parse_toml_str(v)
                        if old and old != theme_slug:
                            prev_theme = old
                        indent = line[: len(line) - len(line.lstrip())]
                        out_lines.append(f'{indent}theme = "{theme_slug}"')
                        found = True
                        continue
            out_lines.append(line)
            if idx == tui_start and not has_later:
                out_lines.append(f'theme = "{theme_slug}"')
                found = True
    else:
        out_lines.extend(lines)
        if out_lines and out_lines[-1].strip():
            out_lines.append("")
        out_lines.append("[tui]")
        out_lines.append(f'theme = "{theme_slug}"')

    return "\n".join(out_lines) + "\n", prev_theme


def strip_codex_config_toml(existing: str, theme_slug: str, restore_theme: str | None) -> str:
    if not existing.strip():
        return existing
    lines = existing.splitlines()
    out_lines: list[str] = []
    in_tui = False
    for line in lines:
        sec = _toml_section(line)
        if sec is not None:
            in_tui = sec == "tui"
            out_lines.append(line)
            continue
        code = line.split("#", 1)[0]
        if "=" in code:
            k, v = code.split("=", 1)
            key = k.strip()
            if (in_tui and key == "theme") or (not in_tui and key == "tui.theme"):
                if _parse_toml_str(v) == theme_slug:
                    if restore_theme:
                        indent = line[: len(line) - len(line.lstrip())]
                        out_lines.append(f'{indent}{key} = "{restore_theme}"')
                    continue
        out_lines.append(line)
    return ("\n".join(out_lines) + "\n") if out_lines else ""


def main() -> int:
    home = Path(os.environ.get("HOME", "/tmp"))
    state_dir = Path(os.environ.get("XDG_STATE_HOME") or (home / ".local/state")) / "quickshell/user/generated"
    parser = argparse.ArgumentParser(description="Generate Alis theme for Codex CLI")
    parser.add_argument("--colors", type=Path, default=state_dir / "palette.json")
    parser.add_argument("--terminal-json", type=Path, default=state_dir / "terminal.json")
    parser.add_argument("--scss", type=Path, default=state_dir / "material_colors.scss")
    parser.add_argument("--strip", action="store_true")
    args = parser.parse_args()

    codex_env = os.environ.get("CODEX_HOME")
    if codex_env:
        codex_dir = Path(codex_env)
    else:
        p1 = home / ".codex"
        p2 = Path(os.environ.get("XDG_CONFIG_HOME") or (home / ".config")) / "codex"
        codex_dir = p2 if (not p1.exists() and p2.is_dir()) else p1
    theme_path = codex_dir / "themes" / CODEX_THEME_FILE
    config_path = codex_dir / "config.toml"
    prev_state_path = state_dir / CODEX_PREV_THEME_STATE

    if args.strip:
        if theme_path.is_file():
            theme_path.unlink(missing_ok=True)
        restore_theme = None
        if prev_state_path.is_file():
            restore_theme = prev_state_path.read_text(encoding="utf-8", errors="ignore").strip() or None
            prev_state_path.unlink(missing_ok=True)
        if config_path.is_file():
            existing = config_path.read_text(encoding="utf-8", errors="ignore")
            updated = strip_codex_config_toml(existing, CODEX_THEME_SLUG, restore_theme)
            write_if_changed(config_path, updated)
        print("[codex] Stripped Alis theme")
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

    tmtheme = build_codex_tmtheme(colors, term_colors)
    write_if_changed(theme_path, tmtheme)

    existing_toml = config_path.read_text(encoding="utf-8", errors="ignore") if config_path.is_file() else ""
    updated_toml, prev_theme = update_codex_config_toml(existing_toml, CODEX_THEME_SLUG)
    if prev_theme:
        write_if_changed(prev_state_path, f"{prev_theme}\n")
    write_if_changed(config_path, updated_toml)
    print(f"[codex] Theme generated: {theme_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
