#!/usr/bin/env python3
"""
apply-browser-themes.py — Non-privileged Material You auto-theming for web browsers.

Supported browsers (Native & Flatpak):
  - Zen Browser (~/.config/zen, ~/.zen, Flatpak app.zen_browser.zen)
  - Firefox / LibreWolf / Waterfox / Floorp (~/.mozilla/firefox, ~/.librewolf, ~/.waterfox, ~/.floorp, Flatpaks)
  - Vivaldi (~/.config/vivaldi, ~/.config/vivaldi-snapshot, Flatpak com.vivaldi.Vivaldi)
  - Brave (~/.config/BraveSoftware/Brave-Browser, Flatpak com.brave.Browser)
  - Google Chrome / Chromium / Ungoogled-Chromium / Microsoft Edge (Native & Flatpak)

Guarantees:
  - Never invokes sudo/pkexec automatically during wallpaper theming.
  - Writes managed policy JSON when /etc/<browser>/policies/managed is already writable.
  - Preserves all existing user themes (e.g. Vivaldi custom themes) and existing userChrome.css rules.
  - Supports clean rollback via --disable using saved state in browser_theme_state.json.
"""

from __future__ import annotations

import argparse
import configparser
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path
from typing import Any

ALIS_VIVALDI_THEME_ID = "alis-0000-4000-8000-000000000001"
ALIS_BRIDGE_PORT = 43821
ALIS_IMPORT_CHROME = '@import "alis-theme.css"; /* ALIS-AUTO-THEME */'
ALIS_IMPORT_CONTENT = '@import "alis-content.css"; /* ALIS-AUTO-THEME */'
USER_JS_BEGIN = "// >>> ALIS-AUTO-THEME BEGIN >>>"
USER_JS_END = "// <<< ALIS-AUTO-THEME END <<<"

HEX_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")


def normalize_hex(value: Any, fallback: str) -> str:
    if isinstance(value, str):
        s = value.strip()
        if HEX_RE.match(s):
            return s.lower()
    return fallback.lower()


def hex_to_skcolor_int(hex_color: str) -> int:
    """Convert #RRGGBB to Chromium's signed 32-bit ARGB SkColor integer."""
    rgb = int(hex_color.lstrip("#"), 16)
    argb = 0xFF000000 | rgb
    return struct.unpack("<i", struct.pack("<I", argb))[0]


def atomic_write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".alis-tmp", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(content)
        os.replace(tmp_name, path)
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


def atomic_write_json(path: Path, data: Any, indent: int | None = None) -> None:
    text = json.dumps(data, ensure_ascii=False, indent=indent) + "\n"
    atomic_write_text(path, text)


def load_json_safe(path: Path) -> dict[str, Any] | None:
    if not path.is_file():
        return None
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        return raw if isinstance(raw, dict) else None
    except Exception:
        return None


def load_palette(state_dir: Path, explicit_color: str = "", explicit_mode: str = "") -> dict[str, Any]:
    gen = state_dir / "user" / "generated"
    app_pal = load_json_safe(gen / "app-palette.json") or {}
    raw_pal = load_json_safe(gen / "palette.json") or {}
    colors_pal = load_json_safe(gen / "colors.json") or {}
    meta = load_json_safe(gen / "theme-meta.json") or {}

    merged: dict[str, Any] = {}
    merged.update(colors_pal)
    merged.update(raw_pal)
    merged.update(app_pal)

    mode = explicit_mode if explicit_mode in ("dark", "light") else str(meta.get("mode", "")).lower()
    if mode not in ("dark", "light"):
        scss = gen / "material_colors.scss"
        if scss.is_file():
            txt = scss.read_text(encoding="utf-8", errors="ignore")
            m = re.search(r"^\$darkmode:\s*(true|false)\s*;", txt, re.IGNORECASE | re.MULTILINE)
            if m:
                mode = "dark" if m.group(1).lower() == "true" else "light"
    if mode not in ("dark", "light"):
        mode = "dark"

    dark = mode == "dark"

    seed = ""
    if explicit_color and HEX_RE.match(explicit_color.strip()):
        seed = explicit_color.strip().lower()
    if not seed:
        seed_file = gen / "color.txt"
        if seed_file.is_file():
            c = seed_file.read_text(encoding="utf-8", errors="ignore").strip()
            if HEX_RE.match(c):
                seed = c.lower()

    bg = normalize_hex(merged.get("app_background") or merged.get("background"), "#141318" if dark else "#fdf8fd")
    surface = normalize_hex(merged.get("app_surface") or merged.get("surface_container_low") or merged.get("surface"), "#1d1b20" if dark else "#f7f2f7")
    surface_elev = normalize_hex(merged.get("app_surface_elevated") or merged.get("surface_container"), "#211f26" if dark else "#f1ecf1")
    surface_high = normalize_hex(merged.get("app_surface_popup") or merged.get("surface_container_high"), "#2b2930" if dark else "#ebe6eb")
    surface_hover = normalize_hex(merged.get("app_surface_hover") or merged.get("surface_container_highest"), "#36343b" if dark else "#e6e1e6")
    fg = normalize_hex(merged.get("app_foreground") or merged.get("on_background") or merged.get("on_surface"), "#e6e1e9" if dark else "#1d1b20")
    subtext = normalize_hex(merged.get("app_subtext") or merged.get("on_surface_variant"), "#cac4d0" if dark else "#49454f")
    primary = normalize_hex(merged.get("app_accent") or merged.get("primary") or seed, "#d0bcff" if dark else "#6750a4")
    on_primary = normalize_hex(merged.get("app_on_accent") or merged.get("on_primary"), "#381e72" if dark else "#ffffff")
    primary_container = normalize_hex(merged.get("app_accent_container") or merged.get("primary_container"), "#4f378b" if dark else "#eaddff")
    on_primary_container = normalize_hex(merged.get("on_primary_container") or fg, "#eaddff" if dark else "#21005d")
    secondary = normalize_hex(merged.get("secondary"), primary)
    tertiary = normalize_hex(merged.get("tertiary"), primary)
    border = normalize_hex(merged.get("app_border_subtle") or merged.get("outline_variant"), "#49454f" if dark else "#cac4d0")
    selection = normalize_hex(merged.get("app_selection") or primary_container, primary_container)

    chrome_seed = seed or primary

    return {
        "mode": mode,
        "dark": dark,
        "seed": chrome_seed,
        "bg": bg,
        "surface": surface,
        "surface_elev": surface_elev,
        "surface_high": surface_high,
        "surface_hover": surface_hover,
        "fg": fg,
        "subtext": subtext,
        "primary": primary,
        "on_primary": on_primary,
        "primary_container": primary_container,
        "on_primary_container": on_primary_container,
        "secondary": secondary,
        "tertiary": tertiary,
        "border": border,
        "selection": selection,
    }


def variant_to_chromium_int(variant_name: str) -> int:
    mapping = {
        "tonal_spot": 1,
        "neutral": 2,
        "vibrant": 3,
        "expressive": 4,
    }
    return mapping.get(variant_name, 1)


def iter_chromium_profiles(user_data_dir: Path) -> list[Path]:
    if not user_data_dir.is_dir():
        return []
    profiles: list[Path] = []
    default_prefs = user_data_dir / "Default" / "Preferences"
    if default_prefs.is_file():
        profiles.append(default_prefs)
    for child in sorted(user_data_dir.iterdir()):
        if child.is_dir() and child.name.startswith("Profile "):
            prefs = child / "Preferences"
            if prefs.is_file():
                profiles.append(prefs)
    return profiles


def apply_chromium_family(
    home_dir: Path,
    etc_dir: Path,
    pal: dict[str, Any],
    variant_name: str,
    disable: bool,
    refresh_live: bool,
    logs: list[str],
) -> None:
    config_home = home_dir / ".config"
    flatpak_apps = home_dir / ".var" / "app"

    targets = [
        ("google-chrome", ["google-chrome-stable", "google-chrome"], etc_dir / "opt/chrome/policies/managed", [
            config_home / "google-chrome",
            flatpak_apps / "com.google.Chrome/config/google-chrome",
        ]),
        ("chromium", ["chromium", "chromium-browser"], etc_dir / "chromium/policies/managed", [
            config_home / "chromium",
            flatpak_apps / "org.chromium.Chromium/config/chromium",
            flatpak_apps / "io.github.ungoogled_software.ungoogled_chromium/config/chromium",
        ]),
        ("brave", ["brave", "brave-browser"], etc_dir / "brave/policies/managed", [
            config_home / "BraveSoftware/Brave-Browser",
            flatpak_apps / "com.brave.Browser/config/BraveSoftware/Brave-Browser",
        ]),
        ("microsoft-edge", ["microsoft-edge-stable", "microsoft-edge"], etc_dir / "opt/edge/policies/managed", [
            config_home / "microsoft-edge",
            flatpak_apps / "com.microsoft.Edge/config/microsoft-edge",
        ]),
    ]

    cs_int = 2 if pal["dark"] else 1
    skcolor = hex_to_skcolor_int(pal["seed"])
    variant_int = variant_to_chromium_int(variant_name)

    for label, bins, policy_dir, data_dirs in targets:
        policy_file = policy_dir / "ii-theme.json"
        policy_writable = policy_dir.is_dir() and os.access(policy_dir, os.W_OK)

        if disable:
            if policy_writable and policy_file.exists():
                try:
                    policy_file.unlink()
                    logs.append(f"[{label}] removed policy {policy_file}")
                except OSError:
                    pass
            continue

        policy_written = False
        if policy_writable:
            try:
                atomic_write_json(policy_file, {
                    "BrowserThemeColor": pal["seed"],
                    "BackgroundModeEnabled": False,
                })
                policy_written = True
                logs.append(f"[{label}] wrote live policy {policy_file}")
            except Exception as exc:
                logs.append(f"[{label}] policy write skipped: {exc}")

        any_profile_updated = False
        for data_dir in data_dirs:
            is_flatpak = ".var/app/" in str(data_dir)
            use_policy_here = policy_written and not is_flatpak
            for prefs_path in iter_chromium_profiles(data_dir):
                prefs = load_json_safe(prefs_path)
                if prefs is None:
                    continue
                ext = prefs.setdefault("extensions", {}).setdefault("theme", {})
                ext["id"] = ""
                ext["use_system"] = False
                ext["use_custom"] = False

                bt = prefs.setdefault("browser", {}).setdefault("theme", {})
                bt["color_scheme"] = cs_int
                bt["color_scheme2"] = cs_int
                if use_policy_here:
                    bt.pop("user_color", None)
                    bt.pop("user_color2", None)
                else:
                    # Direct GM3 seed color in Preferences works without /etc root policy!
                    bt["user_color"] = skcolor
                    bt["user_color2"] = skcolor
                    bt["color_variant"] = variant_int
                    bt["color_variant2"] = variant_int
                    bt["follows_system_colors"] = False

                if label == "brave":
                    brave_obj = prefs.setdefault("brave", {})
                    brave_obj["dark_mode"] = 1 if pal["dark"] else 2

                try:
                    atomic_write_json(prefs_path, prefs)
                    any_profile_updated = True
                except Exception as exc:
                    logs.append(f"[{label}] failed updating {prefs_path}: {exc}")

        if any_profile_updated:
            logs.append(f"[{label}] updated Preferences (seed={pal['seed']}, mode={pal['mode']}, policy={policy_written})")

        if refresh_live and policy_written:
            for bin_name in bins:
                if shutil.which(bin_name):
                    running = subprocess.run(["pgrep", "-x", bin_name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
                    if running:
                        subprocess.Popen(
                            [bin_name, "--refresh-platform-policy", "--no-startup-window"],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                            start_new_session=True,
                        )
                        logs.append(f"[{label}] triggered live policy refresh on {bin_name}")
                    break


def apply_vivaldi(
    home_dir: Path,
    etc_dir: Path,
    state_file: Path,
    pal: dict[str, Any],
    disable: bool,
    logs: list[str],
) -> None:
    config_home = home_dir / ".config"
    flatpak_apps = home_dir / ".var" / "app"
    vivaldi_dirs = [
        config_home / "vivaldi",
        config_home / "vivaldi-snapshot",
        flatpak_apps / "com.vivaldi.Vivaldi/config/vivaldi",
    ]

    policy_dir = etc_dir / "vivaldi/policies/managed"
    policy_file = policy_dir / "ii-theme.json"
    if policy_dir.is_dir() and os.access(policy_dir, os.W_OK):
        if disable:
            if policy_file.exists():
                try:
                    policy_file.unlink()
                except OSError:
                    pass
        else:
            try:
                atomic_write_json(policy_file, {
                    "BrowserThemeColor": pal["seed"],
                    "BackgroundModeEnabled": False,
                })
            except Exception:
                pass

    saved_state = load_json_safe(state_file) or {}
    vivaldi_saved = saved_state.setdefault("vivaldi", {})

    alis_theme_obj = {
        "accentFromPage": False,
        "accentOnWindow": False,
        "accentSaturationLimit": 1,
        "alpha": 0.85,
        "backgroundImage": "",
        "backgroundPosition": "stretch",
        "backgroundSource": "",
        "blur": 10,
        "colorAccentBg": pal["surface_elev"],
        "colorBg": pal["bg"],
        "colorFg": pal["fg"],
        "colorHighlightBg": pal["primary"],
        "colorPosition": "unified",
        "colorWindowBg": pal["primary_container"],
        "contrast": 3,
        "dimBlurred": False,
        "engineVersion": 1,
        "id": ALIS_VIVALDI_THEME_ID,
        "name": "Alis Auto",
        "preferSystemAccent": False,
        "radius": 10,
        "simpleScrollbar": True,
        "transparencyTabBar": False,
        "transparencyTabs": False,
        "url": "",
        "version": 1,
    }

    state_dirty = False
    for data_dir in vivaldi_dirs:
        for prefs_path in iter_chromium_profiles(data_dir):
            prefs = load_json_safe(prefs_path)
            if prefs is None:
                continue
            key = str(prefs_path)
            vivaldi = prefs.setdefault("vivaldi", {})
            themes = vivaldi.setdefault("themes", {})
            user_themes = themes.get("user")
            if not isinstance(user_themes, list):
                user_themes = []
                themes["user"] = user_themes

            sched_os = vivaldi.setdefault("theme", {}).setdefault("schedule", {}).setdefault("o_s", {})

            if disable:
                prev = vivaldi_saved.get(key, {})
                if themes.get("current") == ALIS_VIVALDI_THEME_ID:
                    if prev.get("current"):
                        themes["current"] = prev["current"]
                    else:
                        themes.pop("current", None)
                if sched_os.get("dark") == ALIS_VIVALDI_THEME_ID and prev.get("dark"):
                    sched_os["dark"] = prev["dark"]
                if sched_os.get("light") == ALIS_VIVALDI_THEME_ID and prev.get("light"):
                    sched_os["light"] = prev["light"]
                themes["user"] = [t for t in user_themes if not (isinstance(t, dict) and t.get("id") == ALIS_VIVALDI_THEME_ID)]
                atomic_write_json(prefs_path, prefs)
                logs.append(f"[vivaldi] restored user theme in {prefs_path}")
                continue

            entry_backup = vivaldi_saved.setdefault(key, {})
            cur_id = themes.get("current")
            if cur_id and cur_id != ALIS_VIVALDI_THEME_ID:
                entry_backup["current"] = cur_id
                state_dirty = True
            dark_id = sched_os.get("dark")
            if dark_id and dark_id != ALIS_VIVALDI_THEME_ID:
                entry_backup["dark"] = dark_id
                state_dirty = True
            light_id = sched_os.get("light")
            if light_id and light_id != ALIS_VIVALDI_THEME_ID:
                entry_backup["light"] = light_id
                state_dirty = True

            replaced = False
            new_user_themes: list[Any] = []
            for item in user_themes:
                if isinstance(item, dict) and item.get("id") == ALIS_VIVALDI_THEME_ID:
                    new_user_themes.append(alis_theme_obj)
                    replaced = True
                else:
                    new_user_themes.append(item)
            if not replaced:
                new_user_themes.append(alis_theme_obj)
            themes["user"] = new_user_themes

            if cur_id is not None:
                themes["current"] = ALIS_VIVALDI_THEME_ID
            sched_os["dark"] = ALIS_VIVALDI_THEME_ID
            sched_os["light"] = ALIS_VIVALDI_THEME_ID

            bt = prefs.setdefault("browser", {}).setdefault("theme", {})
            bt["color_scheme"] = 2 if pal["dark"] else 1
            bt["color_scheme2"] = 2 if pal["dark"] else 1

            atomic_write_json(prefs_path, prefs)
            logs.append(f"[vivaldi] applied 'Alis Auto' theme in {prefs_path} (preserving {len(new_user_themes) - 1} user themes)")

    if state_dirty:
        atomic_write_json(state_file, saved_state, indent=2)


def build_gecko_live_theme_object(pal: dict[str, Any]) -> dict[str, Any]:
    scheme = "dark" if pal["dark"] else "light"
    return {
        "colors": {
            "frame": pal["bg"],
            "frame_inactive": pal["bg"],
            "tab_background_text": pal["fg"],
            "toolbar": pal["surface"],
            "toolbar_text": pal["fg"],
            "toolbar_field": pal["surface_elev"],
            "toolbar_field_text": pal["fg"],
            "toolbar_field_border": pal["border"],
            "toolbar_field_focus": pal["surface_high"],
            "toolbar_field_text_focus": pal["fg"],
            "toolbar_field_border_focus": pal["primary"],
            "toolbar_field_highlight": pal["selection"],
            "toolbar_field_highlight_text": pal["fg"],
            "tab_selected": pal["surface_elev"],
            "tab_text": pal["fg"],
            "tab_line": pal["primary"],
            "tab_loading": pal["primary"],
            "tab_background_separator": pal["surface_hover"],
            "toolbar_top_separator": pal["border"],
            "toolbar_bottom_separator": pal["border"],
            "toolbar_vertical_separator": pal["border"],
            "button_background_hover": pal["surface_hover"],
            "button_background_active": pal["primary_container"],
            "icons": pal["fg"],
            "icons_attention": pal["primary"],
            "popup": pal["surface_high"],
            "popup_text": pal["fg"],
            "popup_border": pal["border"],
            "popup_highlight": pal["primary_container"],
            "popup_highlight_text": pal["on_primary"],
            "sidebar": pal["bg"],
            "sidebar_text": pal["fg"],
            "sidebar_border": pal["border"],
            "sidebar_highlight": pal["primary_container"],
            "sidebar_highlight_text": pal["on_primary_container"],
            "ntp_background": pal["bg"],
            "ntp_card_background": pal["surface_elev"],
            "ntp_text": pal["fg"],
        },
        "properties": {
            "color_scheme": scheme,
            "content_color_scheme": scheme,
        },
    }


def build_gecko_chrome_css(pal: dict[str, Any], is_zen: bool) -> str:
    scheme = "dark" if pal["dark"] else "light"
    zen_static_block = ""
    zen_live_block = ""
    zen_backdrop_rules = ""
    if is_zen:
        zen_static_block = f"""
  /* Zen Browser Static Fallback (before live extension connects) */
  --zen-primary-color: {pal['primary']} !important;
  --zen-colors-primary: {pal['surface']} !important;
  --zen-colors-primary-foreground: {pal['fg']} !important;
  --zen-colors-secondary: {pal['surface_elev']} !important;
  --zen-colors-tertiary: {pal['bg']} !important;
  --zen-colors-hover-bg: {pal['surface_hover']} !important;
  --zen-colors-input-bg: {pal['surface_elev']} !important;
  --zen-colors-border: {pal['border']} !important;
  --zen-colors-border-contrast: {pal['border']} !important;
  --zen-dialog-background: {pal['surface_high']} !important;
  --zen-in-content-dialog-background: {pal['surface_high']} !important;
  --zen-urlbar-background: {pal['surface_elev']} !important;
  --zen-urlbar-background-base: {pal['surface_elev']} !important;
  --zen-main-browser-background: linear-gradient(135deg, {pal['bg']} 0%, {pal['surface']} 100%) !important;
  --zen-main-browser-background-old: {pal['bg']} !important;
  --zen-main-browser-background-toolbar: linear-gradient(135deg, {pal['bg']} 0%, {pal['surface']} 100%) !important;
  --zen-main-browser-background-toolbar-old: {pal['bg']} !important;
  --zen-navigator-toolbox-background: {pal['bg']} !important;
  --zen-themed-toolbar-bg: {pal['bg']} !important;
  --zen-themed-toolbar-bg-transparent: color-mix(in srgb, {pal['bg']} 86%, transparent) !important;
  --zen-toolbar-element-bg: {pal['surface_elev']} !important;
  --zen-toolbar-element-bg-hover: {pal['surface_hover']} !important;
  --zen-selected-bg: {pal['surface_elev']} !important;
  --zen-selected-color: {pal['fg']} !important;
  --zen-essential-tab-selected-bg: {pal['surface_elev']} !important;
  --zen-essential-tab-selected-bg-hover: {pal['surface_hover']} !important;
  --zen-active-split-outline-color: {pal['primary']} !important;
  --toolbox-textcolor: {pal['fg']} !important;
  --toolbar-text-color: {pal['fg']} !important;
"""
        # Uses strictly LWT CSS variables that have zero !important rules in Zen's omni.ja
        # (disjoint source -> target mapping prevents CSS custom property cycles).
        zen_live_block = """
  /* Zen Browser Live Bridge — dynamically tracks browser.theme.update() with 0ms restartless reload */
  --zen-primary-color: var(--lwt-tab-line-color) !important;
  --zen-colors-primary: var(--toolbar-background-color) !important;
  --zen-colors-primary-foreground: var(--lwt-text-color) !important;
  --zen-colors-secondary: var(--newtab-background-color-secondary) !important;
  --zen-colors-tertiary: var(--lwt-accent-color) !important;
  --zen-colors-hover-bg: var(--lwt-background-tab-separator-color) !important;
  --zen-colors-input-bg: var(--newtab-background-color-secondary) !important;
  --zen-colors-border: var(--toolbar-field-border-color) !important;
  --zen-colors-border-contrast: var(--toolbar-field-border-color) !important;
  --zen-dialog-background: var(--toolbar-field-background-color-focus) !important;
  --zen-in-content-dialog-background: var(--toolbar-field-background-color-focus) !important;
  --zen-urlbar-background: var(--newtab-background-color-secondary) !important;
  --zen-urlbar-background-base: var(--newtab-background-color-secondary) !important;
  --zen-main-browser-background: linear-gradient(135deg, var(--lwt-accent-color) 0%, var(--toolbar-background-color) 100%) !important;
  --zen-main-browser-background-old: var(--lwt-accent-color) !important;
  --zen-main-browser-background-toolbar: linear-gradient(135deg, var(--lwt-accent-color) 0%, var(--toolbar-background-color) 100%) !important;
  --zen-main-browser-background-toolbar-old: var(--lwt-accent-color) !important;
  --zen-navigator-toolbox-background: var(--lwt-accent-color) !important;
  --zen-themed-toolbar-bg: var(--lwt-accent-color) !important;
  --zen-themed-toolbar-bg-transparent: color-mix(in srgb, var(--lwt-accent-color) 86%, transparent) !important;
  --zen-toolbar-element-bg: var(--newtab-background-color-secondary) !important;
  --zen-toolbar-element-bg-hover: var(--lwt-background-tab-separator-color) !important;
  --zen-selected-bg: var(--newtab-background-color-secondary) !important;
  --zen-selected-color: var(--lwt-text-color) !important;
  --zen-essential-tab-selected-bg: var(--newtab-background-color-secondary) !important;
  --zen-essential-tab-selected-bg-hover: var(--lwt-background-tab-separator-color) !important;
  --zen-active-split-outline-color: var(--lwt-tab-line-color) !important;
  --toolbox-textcolor: var(--lwt-text-color) !important;
  --toolbar-text-color: var(--lwt-text-color) !important;
"""
        zen_backdrop_rules = f"""
/* Override ZenThemePicker inline gradient styles on workspace background layers */
:root:not([lwtheme]) .zen-browser-generic-background,
#main-window:not([lwtheme]) .zen-browser-generic-background {{
  --zen-main-browser-background: linear-gradient(135deg, {pal['bg']} 0%, {pal['surface']} 100%) !important;
  --zen-main-browser-background-old: {pal['bg']} !important;
  --zen-main-browser-background-toolbar: linear-gradient(135deg, {pal['bg']} 0%, {pal['surface']} 100%) !important;
  --zen-main-browser-background-toolbar-old: {pal['bg']} !important;
}}

:root[lwtheme] .zen-browser-generic-background,
#main-window[lwtheme] .zen-browser-generic-background {{
  --zen-main-browser-background: linear-gradient(135deg, var(--lwt-accent-color) 0%, var(--toolbar-background-color) 100%) !important;
  --zen-main-browser-background-old: var(--lwt-accent-color) !important;
  --zen-main-browser-background-toolbar: linear-gradient(135deg, var(--lwt-accent-color) 0%, var(--toolbar-background-color) 100%) !important;
  --zen-main-browser-background-toolbar-old: var(--lwt-accent-color) !important;
}}
"""
    return f"""/* Auto-generated by Alis Wallpaper Theming — Do not edit alis-theme.css directly. */

/* 1. Static startup fallback when live extension is not active (:not([lwtheme])) */
:root:not([lwtheme]),
#main-window:not([lwtheme]) {{
  color-scheme: {scheme} !important;{zen_static_block}
  --lwt-accent-color: {pal['bg']} !important;
  --lwt-text-color: {pal['fg']} !important;
  --toolbar-bgcolor: {pal['surface']} !important;
  --toolbar-color: {pal['fg']} !important;
  --toolbar-field-background-color: {pal['surface_elev']} !important;
  --toolbar-field-color: {pal['fg']} !important;
  --toolbar-field-border-color: {pal['border']} !important;
  --toolbar-field-focus-background-color: {pal['surface_high']} !important;
  --toolbar-field-focus-color: {pal['fg']} !important;
  --urlbar-box-bgcolor: {pal['surface_elev']} !important;
  --urlbar-box-hover-bgcolor: {pal['surface_hover']} !important;
  --urlbar-box-focus-bgcolor: {pal['surface_high']} !important;
  --tab-selected-bgcolor: {pal['surface_elev']} !important;
  --tab-selected-textcolor: {pal['fg']} !important;
  --tab-line-color: {pal['primary']} !important;
  --tabs-navbar-separator-color: {pal['border']} !important;
  --chrome-content-separator-color: {pal['border']} !important;
  --sidebar-background-color: {pal['bg']} !important;
  --sidebar-text-color: {pal['fg']} !important;
  --sidebar-border-color: {pal['border']} !important;
  --arrowpanel-background: {pal['surface_high']} !important;
  --arrowpanel-color: {pal['fg']} !important;
  --arrowpanel-border-color: {pal['border']} !important;
  --panel-separator-color: {pal['border']} !important;
  --button-bgcolor: {pal['surface_elev']} !important;
  --button-hover-bgcolor: {pal['surface_hover']} !important;
  --button-active-bgcolor: {pal['primary_container']} !important;
  --button-primary-bgcolor: {pal['primary']} !important;
  --button-primary-hover-bgcolor: {pal['primary']} !important;
  --button-primary-color: {pal['on_primary']} !important;
  --focus-outline-color: {pal['primary']} !important;
  --input-bgcolor: {pal['surface_elev']} !important;
  --input-color: {pal['fg']} !important;
  --input-border-color: {pal['border']} !important;
}}

/* 2. Live zero-restart variable bridge when Alis Live Theme extension is active ([lwtheme]) */
:root[lwtheme],
#main-window[lwtheme] {{{zen_live_block}
  --toolbar-bgcolor: var(--toolbar-background-color) !important;
  --toolbar-color: var(--lwt-text-color) !important;
  --toolbar-field-background-color: var(--newtab-background-color-secondary) !important;
  --toolbar-field-color: var(--lwt-text-color) !important;
  --toolbar-field-focus-background-color: var(--toolbar-field-background-color-focus) !important;
  --toolbar-field-focus-color: var(--lwt-text-color) !important;
  --urlbar-box-bgcolor: var(--newtab-background-color-secondary) !important;
  --urlbar-box-hover-bgcolor: var(--lwt-background-tab-separator-color) !important;
  --urlbar-box-focus-bgcolor: var(--toolbar-field-background-color-focus) !important;
  --tab-background-color-selected: var(--newtab-background-color-secondary) !important;
  --tab-text-color-selected: var(--lwt-text-color) !important;
  --tab-selected-bgcolor: var(--newtab-background-color-secondary) !important;
  --tab-selected-textcolor: var(--lwt-text-color) !important;
  --tab-line-color: var(--lwt-tab-line-color) !important;
  --toolbarbutton-background-color-hover: var(--lwt-background-tab-separator-color) !important;
  --toolbarbutton-background-color-active: var(--urlbarview-background-color-selected) !important;
  --arrowpanel-background: var(--toolbar-field-background-color-focus) !important;
  --arrowpanel-color: var(--lwt-text-color) !important;
  --arrowpanel-border-color: var(--toolbar-field-border-color) !important;
  --panel-background-color: var(--toolbar-field-background-color-focus) !important;
  --panel-border-color: var(--toolbar-field-border-color) !important;
  --panel-separator-color: var(--toolbar-field-border-color) !important;
  --button-bgcolor: var(--newtab-background-color-secondary) !important;
  --button-hover-bgcolor: var(--lwt-background-tab-separator-color) !important;
  --button-active-bgcolor: var(--urlbarview-background-color-selected) !important;
  --button-primary-bgcolor: var(--lwt-tab-line-color) !important;
  --button-primary-hover-bgcolor: var(--lwt-tab-line-color) !important;
  --button-primary-color: var(--urlbarview-text-color-selected) !important;
  --focus-outline-color: var(--lwt-tab-line-color) !important;
  --input-bgcolor: var(--newtab-background-color-secondary) !important;
  --input-color: var(--lwt-text-color) !important;
  --input-border-color: var(--toolbar-field-border-color) !important;
}}
{zen_backdrop_rules}
::selection {{
  background-color: var(--lwt-toolbar-field-highlight, {pal['selection']}) !important;
  color: var(--lwt-text-color, {pal['fg']}) !important;
}}
"""


def build_gecko_content_css(pal: dict[str, Any]) -> str:
    return f"""/* Auto-generated by Alis Wallpaper Theming — Internal browser pages */
@-moz-document url("about:newtab"), url("about:home"), url("about:blank"), url("about:privatebrowsing") {{
  :root, body {{
    --newtab-primary-action-background: {pal['primary']};
    --newtab-element-hover-color: {pal['surface_hover']};
    background-color: var(--newtab-background-color, {pal['bg']}) !important;
    color: var(--newtab-text-primary-color, {pal['fg']}) !important;
  }}
}}
"""


def ensure_import_at_top(css_file: Path, import_line: str, remove: bool = False) -> None:
    existing = css_file.read_text(encoding="utf-8", errors="ignore") if css_file.is_file() else ""
    lines = [ln for ln in existing.splitlines() if "ALIS-AUTO-THEME" not in ln and 'alis-theme.css' not in ln and 'alis-content.css' not in ln]
    cleaned = "\n".join(lines).strip()

    if remove:
        if css_file.is_file():
            atomic_write_text(css_file, (cleaned + "\n") if cleaned else "")
        return

    # CSS spec requires @charset first (if present), then @import rules before other selectors.
    if cleaned.startswith("@charset"):
        first_nl = cleaned.find("\n")
        if first_nl >= 0:
            head = cleaned[: first_nl + 1]
            tail = cleaned[first_nl + 1 :].lstrip("\n")
            merged = f"{head}{import_line}\n\n{tail}\n" if tail else f"{head}{import_line}\n"
        else:
            merged = f"{cleaned}\n{import_line}\n"
    else:
        merged = f"{import_line}\n\n{cleaned}\n" if cleaned else f"{import_line}\n"
    atomic_write_text(css_file, merged)


def update_gecko_user_js(profile_dir: Path, pal: dict[str, Any], is_zen: bool, remove: bool) -> None:
    user_js = profile_dir / "user.js"
    existing = user_js.read_text(encoding="utf-8", errors="ignore") if user_js.is_file() else ""
    pattern = re.compile(
        re.escape(USER_JS_BEGIN) + r".*?" + re.escape(USER_JS_END) + r"\n?",
        re.DOTALL,
    )
    stripped = pattern.sub("", existing).rstrip()

    if remove:
        if user_js.is_file():
            atomic_write_text(user_js, (stripped + "\n") if stripped else "")
        return

    # ui.systemUsesDarkTheme: 1 = dark, 0 = light
    # layout.css.prefers-color-scheme.content-override: 2 = follow live theme/system
    # zen.view.window.scheme: 2 = auto (tracks live prefersColorSchemeOverride from browser.theme.update)
    dark_int = 1 if pal["dark"] else 0
    lines = [
        USER_JS_BEGIN,
        'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);',
        'user_pref("xpinstall.signatures.required", false);',
        f'user_pref("ui.systemUsesDarkTheme", {dark_int});',
        'user_pref("layout.css.prefers-color-scheme.content-override", 2);',
    ]
    if is_zen:
        lines.append('user_pref("zen.theme.disable-lightweight", false);')
        lines.append('user_pref("zen.view.window.scheme", 2);')
        lines.append(f'user_pref("zen.theme.accent-color", "{pal["primary"]}");')
    lines.append(USER_JS_END)
    block = "\n".join(lines) + "\n"

    new_text = f"{stripped}\n\n{block}" if stripped else block
    atomic_write_text(user_js, new_text)


def iter_gecko_profiles(root_dir: Path) -> list[Path]:
    ini_path = root_dir / "profiles.ini"
    if not ini_path.is_file():
        return []
    cp = configparser.RawConfigParser()
    try:
        cp.read(ini_path, encoding="utf-8")
    except Exception:
        return []

    found: list[Path] = []
    seen: set[Path] = set()
    for section in cp.sections():
        if not (section.startswith("Profile") or section.startswith("Install")):
            continue
        for opt in ("Path", "Default"):
            if cp.has_option(section, opt):
                rel_val = cp.get(section, opt).strip()
                if not rel_val or rel_val in ("0", "1"):
                    continue
                is_rel = cp.get(section, "IsRelative", fallback="1").strip() != "0"
                p = (root_dir / rel_val) if is_rel else Path(rel_val)
                p = p.resolve()
                if p.is_dir() and p not in seen:
                    seen.add(p)
                    found.append(p)
    return found


def apply_gecko_family(
    home_dir: Path,
    pal: dict[str, Any],
    disable: bool,
    logs: list[str],
) -> None:
    config_home = home_dir / ".config"
    flatpak_apps = home_dir / ".var" / "app"

    gecko_roots = [
        # Zen Browser (XDG native, legacy ~/.zen, and Flatpak)
        ("zen", True, config_home / "zen"),
        ("zen", True, home_dir / ".zen"),
        ("zen-flatpak", True, flatpak_apps / "app.zen_browser.zen/.zen"),
        ("zen-flatpak", True, flatpak_apps / "app.zen_browser.zen/config/zen"),
        # Firefox & derivatives
        ("firefox", False, home_dir / ".mozilla/firefox"),
        ("firefox-flatpak", False, flatpak_apps / "org.mozilla.firefox/.mozilla/firefox"),
        ("librewolf", False, home_dir / ".librewolf"),
        ("librewolf-flatpak", False, flatpak_apps / "io.gitlab.librewolf-community/.librewolf"),
        ("waterfox", False, home_dir / ".waterfox"),
        ("floorp", False, home_dir / ".floorp"),
        ("floorp-flatpak", False, flatpak_apps / "one.ablaze.floorp/.floorp"),
    ]

    seen_profiles: set[Path] = set()
    for label, is_zen, root_dir in gecko_roots:
        for profile_dir in iter_gecko_profiles(root_dir):
            if profile_dir in seen_profiles:
                continue
            seen_profiles.add(profile_dir)

            chrome_dir = profile_dir / "chrome"
            theme_css = chrome_dir / "alis-theme.css"
            content_css = chrome_dir / "alis-content.css"
            user_chrome = chrome_dir / "userChrome.css"
            user_content = chrome_dir / "userContent.css"

            if disable:
                ensure_import_at_top(user_chrome, ALIS_IMPORT_CHROME, remove=True)
                ensure_import_at_top(user_content, ALIS_IMPORT_CONTENT, remove=True)
                update_gecko_user_js(profile_dir, pal, is_zen=is_zen, remove=True)
                for f in (theme_css, content_css):
                    if f.is_file():
                        try:
                            f.unlink()
                        except OSError:
                            pass
                logs.append(f"[{label}] removed Alis auto-theme from {profile_dir.name}")
                continue

            atomic_write_text(theme_css, build_gecko_chrome_css(pal, is_zen=is_zen))
            atomic_write_text(content_css, build_gecko_content_css(pal))
            ensure_import_at_top(user_chrome, ALIS_IMPORT_CHROME, remove=False)
            ensure_import_at_top(user_content, ALIS_IMPORT_CONTENT, remove=False)
            update_gecko_user_js(profile_dir, pal, is_zen=is_zen, remove=False)
            logs.append(f"[{label}] applied Alis auto-theme to profile '{profile_dir.name}'")


def package_live_extension_xpi(gen_dir: Path, logs: list[str]) -> Path | None:
    ext_src = Path(__file__).resolve().parent / "browser_extension"
    required = ("manifest.json", "background.js", "icon.svg")
    if not all((ext_src / name).is_file() for name in required):
        return None

    xpi_target = gen_dir / "alis-browser-theme.xpi"
    fd, tmp_name = tempfile.mkstemp(prefix=".alis-browser-theme.", suffix=".xpi", dir=str(gen_dir))
    os.close(fd)
    try:
        with zipfile.ZipFile(tmp_name, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            for name in required:
                info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o644 << 16
                zf.writestr(info, (ext_src / name).read_bytes())
        new_bytes = Path(tmp_name).read_bytes()
        if xpi_target.is_file() and xpi_target.read_bytes() == new_bytes:
            os.unlink(tmp_name)
        else:
            os.chmod(tmp_name, 0o644)
            os.replace(tmp_name, xpi_target)
            logs.append(f"[gecko-live] packaged extension {xpi_target}")
        return xpi_target
    except Exception as exc:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        logs.append(f"[gecko-live] failed packaging xpi: {exc}")
        return None


def _post_bridge_notify(port: int) -> dict[str, Any] | None:
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/notify",
        data=b"{}",
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=0.35) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception:
        return None


def publish_and_notify_live_bridge(
    state_dir: Path,
    gen_dir: Path,
    pal: dict[str, Any],
    disable: bool,
    refresh_live: bool,
    bridge_port: int,
    logs: list[str],
) -> None:
    package_live_extension_xpi(gen_dir, logs)
    live_payload = {
        "enabled": not disable,
        "version": 1,
        "updated_at": round(time.time(), 3),
        "mode": pal["mode"],
        "palette": pal,
        "gecko_theme": None if disable else build_gecko_live_theme_object(pal),
    }
    atomic_write_json(gen_dir / "browser-live-theme.json", live_payload, indent=2)

    if not refresh_live:
        return

    res = _post_bridge_notify(bridge_port)
    if res is not None:
        logs.append(f"[gecko-live] broadcasted live update (clients={res.get('clients', 0)})")
        return

    if disable:
        return

    bridge_script = Path(__file__).resolve().parent / "alis-browser-theme-bridge.py"
    if not bridge_script.is_file():
        return

    try:
        subprocess.Popen(
            [sys.executable, str(bridge_script), "--state-dir", str(state_dir), "--port", str(bridge_port)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
        for _ in range(10):
            time.sleep(0.05)
            res = _post_bridge_notify(bridge_port)
            if res is not None:
                logs.append(f"[gecko-live] started loopback bridge on 127.0.0.1:{bridge_port} (clients={res.get('clients', 0)})")
                break
    except Exception as exc:
        logs.append(f"[gecko-live] failed starting bridge: {exc}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply Material You auto-theming across web browsers")
    parser.add_argument("--color", default="", help="Explicit seed hex color (#RRGGBB)")
    parser.add_argument("--mode", default="", choices=["", "dark", "light"], help="Explicit color scheme")
    parser.add_argument("--variant", default="tonal_spot", help="GM3 scheme variant")
    parser.add_argument("--disable", action="store_true", help="Remove Alis browser theme overrides and restore prior state")
    parser.add_argument("--no-live-refresh", action="store_true", help="Skip spawning --refresh-platform-policy on running browsers")
    parser.add_argument("--bridge-port", type=int, default=ALIS_BRIDGE_PORT, help="Loopback SSE bridge port")
    parser.add_argument("--state-dir", default="", help="Override quickshell state directory")
    parser.add_argument("--home-dir", default="", help="Override HOME directory (for isolated tests)")
    parser.add_argument("--etc-dir", default="/etc", help="Override /etc policy root (for isolated tests)")
    args = parser.parse_args()

    home_dir = Path(args.home_dir).resolve() if args.home_dir else Path.home()
    xdg_state = os.environ.get("XDG_STATE_HOME") or str(home_dir / ".local/state")
    state_dir = Path(args.state_dir).resolve() if args.state_dir else (Path(xdg_state) / "quickshell")
    etc_dir = Path(args.etc_dir).resolve()

    gen_dir = state_dir / "user" / "generated"
    gen_dir.mkdir(parents=True, exist_ok=True)
    state_file = gen_dir / "browser_theme_state.json"
    log_file = gen_dir / "chrome_theme.log"

    pal = load_palette(state_dir, explicit_color=args.color, explicit_mode=args.mode)
    logs: list[str] = [
        f"[browsers] disable={args.disable} mode={pal['mode']} seed={pal['seed']} primary={pal['primary']} bg={pal['bg']}"
    ]

    apply_chromium_family(
        home_dir=home_dir,
        etc_dir=etc_dir,
        pal=pal,
        variant_name=args.variant,
        disable=args.disable,
        refresh_live=not args.no_live_refresh,
        logs=logs,
    )
    apply_vivaldi(
        home_dir=home_dir,
        etc_dir=etc_dir,
        state_file=state_file,
        pal=pal,
        disable=args.disable,
        logs=logs,
    )
    apply_gecko_family(
        home_dir=home_dir,
        pal=pal,
        disable=args.disable,
        logs=logs,
    )
    publish_and_notify_live_bridge(
        state_dir=state_dir,
        gen_dir=gen_dir,
        pal=pal,
        disable=args.disable,
        refresh_live=not args.no_live_refresh,
        bridge_port=args.bridge_port,
        logs=logs,
    )

    try:
        with log_file.open("a", encoding="utf-8") as fh:
            for line in logs:
                fh.write(line + "\n")
    except OSError:
        pass

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
