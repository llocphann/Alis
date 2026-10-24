#!/usr/bin/env python3
"""OFFICE-I01: optional user-scoped ONLYOFFICE 9.4 / LibreOffice 26.8 themes.

Never launches an office application. Private write-ahead receipts protect
interrupted writes; selector restore merges with current unrelated preferences.
"""
import argparse
import base64
import configparser
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import xml.etree.ElementTree as ET

import office_registry as registry


THEME_NAME = "alis-auto.json"
MAX_SIZE = 4 * 1024 * 1024


class UnsafeConfig(ValueError):
    pass


def safe_path(path):
    if not path.is_absolute():
        raise UnsafeConfig("configuration paths must be absolute")
    for part in [path, *path.parents]:
        if part.is_symlink():
            raise UnsafeConfig("symlink path; no changes made")


def read_file(path):
    safe_path(path)
    try:
        info = path.stat()
    except FileNotFoundError:
        return None
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
        raise UnsafeConfig("configuration must be a single user-owned regular file")
    if info.st_size > MAX_SIZE:
        raise UnsafeConfig("configuration exceeds the safe size limit")
    return path.read_bytes()


def read_input(path):
    # Palette and Alis config are read-only inputs, including the legacy
    # config-directory aliases. No target/journal write follows a symlink.
    return read_file(path.resolve())


def write_file(path, content, expected):
    """Bounded, durable replace with a last comparison against concurrent edits."""
    if read_file(path) != expected:
        raise UnsafeConfig("configuration changed concurrently; preserving it")
    if content == expected:
        return
    if content is None:
        path.unlink()
    else:
        safe_path(path)
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        mode = stat.S_IMODE(path.stat().st_mode) if expected is not None else 0o600
        fd, name = tempfile.mkstemp(prefix=".alis-office-", dir=path.parent)
        try:
            with os.fdopen(fd, "wb") as stream:
                os.fchmod(stream.fileno(), mode)
                stream.write(content)
                stream.flush()
                os.fsync(stream.fileno())
            if read_file(path) != expected:
                raise UnsafeConfig("configuration changed concurrently; preserving it")
            os.replace(name, path)
        finally:
            if os.path.exists(name):
                os.unlink(name)
    directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def packed(value):
    return None if value is None else base64.b64encode(value).decode("ascii")


def unpacked(value):
    return None if value is None else base64.b64decode(value, validate=True)


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def save_journal(path, value):
    write_file(path, json_bytes(value), read_file(path))


def finish_pending(journal_path, journal, paths):
    """Recovery accepts only exact old/new bytes, never an ambiguous side effect."""
    pending = journal.get("pending")
    if pending is None:
        return journal
    for key, change in pending.items():
        if key not in paths or read_file(paths[key]) not in (
            unpacked(change["old"]), unpacked(change["new"])
        ):
            raise UnsafeConfig("interrupted update conflicts with current files; receipt retained")
    order = journal.get("pending_order", list(pending))
    if set(order) != set(pending) or len(order) != len(pending):
        raise UnsafeConfig("invalid interrupted update order; receipt retained")
    for key in order:
        change = pending[key]
        current = read_file(paths[key])
        if current not in (unpacked(change["old"]), unpacked(change["new"])):
            raise UnsafeConfig("configuration changed during recovery; receipt retained")
        write_file(paths[key], unpacked(change["new"]), current)
    journal.pop("pending")
    journal.pop("pending_order", None)
    save_journal(journal_path, journal)
    return journal


def commit_changes(journal_path, journal, changes, paths):
    journal["pending"] = {
        key: {"old": packed(old), "new": packed(new)}
        for key, (old, new) in changes.items() if old != new
    }
    if journal["pending"]:
        journal["pending_order"] = list(journal["pending"])
        save_journal(journal_path, journal)
        finish_pending(journal_path, journal, paths)
    else:
        journal.pop("pending")
        journal.pop("pending_order", None)
        save_journal(journal_path, journal)


def ini_selector(data):
    text = (data or b"").decode("utf-8")
    if "\0" in text or text.startswith("\ufeff"):
        raise UnsafeConfig("unsupported ONLYOFFICE configuration encoding")
    parser = configparser.ConfigParser(interpolation=None, strict=True)
    parser.optionxform = str
    try:
        parser.read_string(text)
    except configparser.Error as error:
        raise UnsafeConfig("malformed ONLYOFFICE settings; preserving configuration") from error
    sections = list(re.finditer(r"(?m)^[ \t]*\[([^\]\r\n]+)\][^\r\n]*(?:\r?\n|$)", text))
    general = [section for section in sections if section[1] == "General"]
    if len(general) > 1:
        raise UnsafeConfig("duplicate General settings section")
    if not general:
        if any(name.strip() == "General" for name in parser.sections()):
            raise UnsafeConfig("noncanonical General settings section")
        return text, None, None
    start = general[0].end()
    end = next((s.start() for s in sections if s.start() > start), len(text))
    matches = list(re.finditer(r"(?m)^[ \t]*UITheme[ \t]*=([^\r\n]*)(?:\r?\n|$)", text[start:end]))
    if len(matches) > 1:
        raise UnsafeConfig("duplicate UITheme settings")
    if not matches:
        if parser.has_option("General", "UITheme"):
            raise UnsafeConfig("unsupported UITheme setting syntax")
        return text, None, start
    match = matches[0]
    if match[1].endswith("\\"):
        raise UnsafeConfig("multiline UITheme setting is unsupported")
    return text, (start + match.start(), start + match.end()), end


def replace_selector(data, replacement, remove_section=False):
    text, span, end = ini_selector(data)
    if span:
        text = text[:span[0]] + (replacement or "") + text[span[1]:]
    elif replacement is not None:
        if end is None:
            text = "[General]\n" + replacement + text
        else:
            prefix = text[:end]
            text = prefix + ("" if prefix.endswith("\n") else "\n") + replacement + text[end:]
    if remove_section:
        text = re.sub(r"(?m)^\[General\]\r?\n(?=\[|\Z)", "", text)
    return text.encode()


def _rgb(hex_color):
    return tuple(int(hex_color[i:i + 2], 16) for i in (1, 3, 5))


def _mix(first, second, amount):
    a, b = _rgb(first), _rgb(second)
    return "#" + "".join(f"{round(x * (1 - amount) + y * amount):02x}" for x, y in zip(a, b))


def _luminance(color):
    channels = [c / 255 for c in _rgb(color)]
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
              for c in channels]
    return sum(c * w for c, w in zip(linear, (0.2126, 0.7152, 0.0722)))


def contrast_ratio(first, second):
    """WCAG contrast for opaque sRGB colors used by both Office adapters."""
    hi, lo = sorted((_luminance(first), _luminance(second)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def _readable(preferred, backgrounds, minimum=4.5):
    """Keep the Alis hue where possible, otherwise correct toward legible ink."""
    if all(contrast_ratio(preferred, bg) >= minimum for bg in backgrounds):
        return preferred
    # Each Office role has one text color, so both covered surfaces must
    # share a light/dark family; never choose a hue that fails either surface.
    for endpoint in ("#ffffff", "#000000"):
        if all(contrast_ratio(endpoint, bg) >= minimum for bg in backgrounds):
            choices = []
            for step in range(1, 101):
                candidate = _mix(preferred, endpoint, step / 100)
                if all(contrast_ratio(candidate, bg) >= minimum for bg in backgrounds):
                    choices.append((step, candidate))
                    break
            if choices:
                return choices[0][1]
    raise UnsafeConfig("Office text/background colors have incompatible luminance")


def generate_theme(palette):
    def color(*keys):
        for key in keys:
            value = palette.get(key)
            if value is not None:
                if not isinstance(value, str) or not re.fullmatch(r"#[\da-fA-F]{6}", value):
                    raise UnsafeConfig("invalid palette color: " + key)
                return value.lower()
        raise UnsafeConfig("missing palette color: " + keys[0])

    bg = color("app_background", "background", "surface")
    proposed_surface = color("app_surface_elevated", "surface_container", "surface")
    # NEVER mix a light panel with dark ink (or vice versa). The desktop
    # login/settings screen uses background-action-panel, not background-normal.
    dark = contrast_ratio("#ffffff", bg) > contrast_ratio("#000000", bg)
    surface_dark = contrast_ratio("#ffffff", proposed_surface) > contrast_ratio("#000000", proposed_surface)
    surface = proposed_surface if surface_dark == dark else _mix(
        bg, "#ffffff" if dark else "#000000", 0.08)
    # Near the light/dark crossover, an elevated surface must not create a
    # pair that neither black nor white ink can read. Keep the base surface
    # rather than emitting an impossible or unreadable theme.
    if not any(all(contrast_ratio(ink, ground) >= 4.5 for ground in (bg, surface))
               for ink in ("#ffffff", "#000000")):
        surface = bg
    backgrounds = (bg, surface)
    primary_minimum = 7.0 if any(
        all(contrast_ratio(ink, ground) >= 7.0 for ground in backgrounds)
        for ink in ("#ffffff", "#000000")) else 4.5
    fg = _readable(color("app_foreground", "on_surface", "on_background"),
                   backgrounds, primary_minimum)
    muted = _readable(color("app_subtext", "on_surface_variant", "on_surface"), backgrounds)
    border = _readable(color("app_border", "outline"), backgrounds, 3.0)
    accent = _readable(color("app_accent", "primary"), backgrounds, 3.0)
    on_accent = _readable(color("app_on_accent", "on_primary"), (accent,))
    link = _readable(accent, backgrounds)
    def interactive(base, amount):
        candidate = _mix(base, fg, amount)
        return candidate if contrast_ratio(candidate, fg) >= 4.5 else base
    def accent_state(amount):
        candidate = _mix(accent, on_accent, amount)
        return candidate if contrast_ratio(candidate, on_accent) >= 4.5 else accent
    hover, pressed = interactive(surface, 0.05), interactive(surface, 0.10)
    accent_hover, accent_pressed = accent_state(0.05), accent_state(0.10)

    # The desktop home/settings shell has its OWN CSS variable names.
    # Source: ONLYOFFICE/desktop-apps 9.4 loginpage/src/css/colors*.less.
    # Editor-only tokens cannot paint the home screen's action panel, sidebar,
    # buttons or checkboxes; omitting them caused white-on-white/near-white.
    colors = {
        "background-normal": bg,
        "background-action-panel": surface,
        "background-normal-element": surface,
        "background-normal-element-light": surface,
        "background-tabbar": bg,
        "background-button": surface,
        "background-primary-button": accent,
        "background-primary-dialog-button": accent,
        "background-scroll-thumb": border,
        "background-icon-normal": bg,
        "background-toolbar": surface,
        "background-toolbar-additional": surface,
        "background-toolbar-tab": surface,
        "background-primary-dialog": surface,
        "background-notification-popover": surface,
        "background-normal-input": bg,
        "background-normal-button": surface,
        "background-accent-button": accent,
        "highlight-button-hover": hover,
        "highlight-button-pressed": pressed,
        "highlight-button-pressed-hover": pressed,
        "highlight-sidebar-item-pressed": surface,
        "highlight-scroll-thumb-hover": border,
        "highlight-primary-button-hover": accent_hover,
        "highlight-primary-button-pressed": accent_pressed,
        "highlight-primary-dialog-button-hover": accent_hover,
        "highlight-accent-button-hover": accent_hover,
        "highlight-accent-button-pressed": accent_pressed,
        "highlight-toolbar-tab-underline": accent,
        "border-divider": border,
        "border-tabbar": border,
        "border-sidebar": border,
        "border-sidebar-item": border,
        "border-sidebar-icon": border,
        "border-regular-control": border,
        "border-toolbar": border,
        "border-preview-hover": accent,
        "border-control-focus": accent,
        "text-normal": fg,
        "text-normal-pressed": fg,
        "text-secondary": muted,
        "text-tertiary": muted,
        "text-link": link,
        "text-link-hover": link,
        "text-link-active": link,
        "text-link-visited": link,
        "text-alt-key-hint": fg,
        "text-inverse": on_accent,
        "text-accent-button": on_accent,
        "text-toolbar-header": on_accent,
        "text-negative": _readable("#ff7777" if dark else "#ba1a1a", backgrounds),
        "icon-normal": fg,
        "icon-normal-pressed": fg,
        "icon-inverse": on_accent,
        "icon-toolbar-header": on_accent,
        "chb-check-mark-background": on_accent,
        "chb-background-normal": bg,
        "chb-background-checked": accent,
        "chb-border-normal": border,
        "chb-border-checked": accent,
        # Disabled elements remain visibly differentiated but not washed out.
        "disabled-element-opacity": 0.85,
        "toolbar-header-document": accent,
        "toolbar-header-presentation": accent,
        "toolbar-header-spreadsheet": accent,
        "toolbar-header-pdf": accent,
        "toolbar-header-draw": accent,
        # The editor workspace is separate from the login/settings panel.
        # ONLYOFFICE's documented canvas-background paints the gray region
        # around the page in Writer/Calc/Impress, independently of the document
        # surface. Do not set canvas-content-background: that belongs to the
        # document/night-page rendering and must retain suite/user semantics.
        "canvas-background": bg,
        "canvas-page-border": border,
        "canvas-ruler-background": bg,
        "canvas-ruler-border": border,
        "canvas-ruler-margins-background": surface,
        "canvas-ruler-mark": fg,
        "canvas-ruler-handle-border": border,
        "canvas-ruler-handle-border-disabled": muted,
        "canvas-high-contrast": fg,
        "canvas-high-contrast-disabled": muted,
        "canvas-cell-title-background": surface,
        "canvas-cell-title-text": fg,
        "canvas-cell-title-border": border,
        "canvas-scroll-thumb": border,
        "canvas-scroll-thumb-border": border,
        "canvas-scroll-thumb-hover": accent,
        "canvas-scroll-thumb-border-hover": accent,
        "window-border": border,
    }
    return json_bytes({"id": "theme-alis-auto", "name": "Alis Auto",
                       "type": "dark" if dark else "light", "colors": colors})


def app_busy(app="onlyoffice"):
    for entry in Path("/proc").iterdir():
        if not entry.name.isdecimal():
            continue
        try:
            if entry.stat().st_uid == os.getuid():
                name = (entry / "comm").read_text().strip()
                if ((app == "onlyoffice" and (name in {"DesktopEditors", "editors_helper"} or name.startswith("onlyoffice")))
                        or (app == "libreoffice" and name in {"soffice.bin", "soffice", "oosplash"})):
                    return True
        except (FileNotFoundError, ProcessLookupError):
            continue
        except PermissionError as error:
            raise UnsafeConfig("cannot verify office process state") from error
    return False


def installed_version(app="onlyoffice"):
    # Read package metadata, never execute DesktopEditors (even --version can
    # open the application). Unknown/AppImage/Flatpak profiles are not guessed.
    if shutil.which("pacman"):
        packages = ("onlyoffice-bin",) if app == "onlyoffice" else ("libreoffice-fresh", "libreoffice-still")
        for package in packages:
            result = subprocess.run(["pacman", "-Q", package], capture_output=True,
                                    text=True, timeout=5, check=False)
            if result.returncode == 0:
                return result.stdout.split()[1]
    if shutil.which("dpkg-query"):
        result = subprocess.run(["dpkg-query", "-W", "-f=${Version}",
                                 "onlyoffice-desktopeditors" if app == "onlyoffice" else "libreoffice-core"], capture_output=True,
                                text=True, timeout=5, check=False)
        if result.returncode == 0:
            return result.stdout.strip()
    return None


def update_onlyoffice(config_home, data_home, state_home, enabled, palette, version):
    paths = {
        "config": config_home / "onlyoffice/DesktopEditors.conf",
        "theme": data_home / "onlyoffice/desktopeditors/uithemes" / THEME_NAME,
    }
    journal_path = state_home / "quickshell/user/generated/office/onlyoffice.json"
    old_journal = read_file(journal_path)
    journal = json.loads(old_journal) if old_journal else None
    if journal and (journal.get("schema") != 1 or journal.get("paths") !=
                    {key: str(path) for key, path in paths.items()}):
        raise UnsafeConfig("ownership receipt does not match this profile")
    if not enabled and journal is None:
        return "disabled"
    if enabled and version is None:
        return "not installed or unsupported package layout"
    if enabled and not re.match(r"^(?:\d+:)?9\.4\.", version):
        return "unsupported version: " + version
    if app_busy():
        return "deferred: close ONLYOFFICE, then refresh Alis colors"
    if journal:
        journal = finish_pending(journal_path, journal, paths)
    config, theme = (read_file(paths[key]) for key in ("config", "theme"))
    text, span, section = ini_selector(config)
    current = text[span[0]:span[1]] if span else None
    if enabled:
        generated = generate_theme(palette)
        if journal is None:
            if theme is not None or (current and current.strip() == "UITheme=" + THEME_NAME):
                raise UnsafeConfig("unowned Alis theme/selector already exists; preserving it")
            journal = {"schema": 1, "paths": {key: str(path) for key, path in paths.items()},
                       "original_selector": current, "original_config_absent": config is None,
                       "original_general_absent": section is None}
        elif current != journal["selector"] or theme != unpacked(journal["theme"]):
            raise UnsafeConfig("user changed managed theme/selector; disable to release ownership")
        journal.update(selector="UITheme=" + THEME_NAME + "\n", theme=packed(generated))
        commit_changes(journal_path, journal, {
            # Generate before selecting; recovery verifies both old/new states.
            "theme": (theme, generated),
            "config": (config, replace_selector(config, journal["selector"]))}, paths)
        return "applied for next ONLYOFFICE launch"
    restored = config
    conflicts = []
    if current == journal["selector"]:
        restored = replace_selector(config, journal["original_selector"],
                                    journal["original_general_absent"])
        if journal["original_config_absent"] and not restored:
            restored = None
    else:
        conflicts.append("selector")
    restored_theme = theme
    if theme == unpacked(journal["theme"]):
        restored_theme = None
    else:
        conflicts.append("theme")
    commit_changes(journal_path, journal, {
        "config": (config, restored), "theme": (theme, restored_theme)}, paths)
    write_file(journal_path, None, read_file(journal_path))
    return "disabled; user edits preserved: " + ", ".join(conflicts) if conflicts else "restored"


LO_SCHEME = "AlisAuto"
LO_BASE = ("org.openoffice.Office.UI", "ColorScheme")
LO_COLORS = LO_BASE + ("ColorSchemes", LO_SCHEME)
LO_APPEARANCE = ("org.openoffice.Office.Common", "Appearance")


def libreoffice_values(palette):
    theme = json.loads(generate_theme(palette))
    colors = theme["colors"]
    bg, fg, surface = (colors[k] for k in ("background-normal", "text-normal", "background-toolbar"))
    # AccentColor is a filled UI role; text-link is independently contrast-
    # corrected for a surface and may not have a legible on-accent partner.
    accent, on_accent, muted, border = (colors[k] for k in ("background-accent-button", "text-accent-button", "text-secondary", "border-regular-control"))
    # LibreOffice's AppBackground is the Writer/Calc workspace outside the
    # document; keep it in sync with ONLYOFFICE canvas-background. Document
    # paper, font, print and visibility entries remain user-owned.
    workspace = colors["canvas-background"]
    role_colors = {
        "AppBackground": workspace, "WindowColor": surface, "WindowTextColor": fg,
        "BaseColor": bg, "ButtonColor": surface, "ButtonTextColor": fg,
        "AccentColor": accent, "DisabledColor": surface, "DisabledTextColor": muted,
        "ShadowColor": border, "SeparatorColor": border, "FaceColor": surface,
        "ActiveColor": accent, "ActiveTextColor": on_accent, "ActiveBorderColor": accent,
        "FieldColor": bg, "MenuBarColor": surface, "MenuBarTextColor": fg,
        "MenuBarHighlightColor": accent, "MenuBarHighlightTextColor": on_accent,
        "MenuColor": surface, "MenuTextColor": fg, "MenuHighlightColor": accent,
        "MenuHighlightTextColor": on_accent, "MenuBorderColor": border,
        "InactiveColor": surface, "InactiveTextColor": muted, "InactiveBorderColor": border,
    }
    values = {LO_COLORS + (role, "Color"): str(int(color[1:], 16))
              for role, color in role_colors.items()}
    values[LO_BASE + ("CurrentColorScheme",)] = LO_SCHEME
    values[LO_APPEARANCE + ("LibreOfficeTheme",)] = "1"
    values[LO_APPEARANCE + ("ApplicationAppearance",)] = "2" if theme["type"] == "dark" else "1"
    return values


def check_libreoffice_schema(values, schema_path=Path("/usr/lib/libreoffice/share/registry/main.xcd")):
    # Installed schema is shipped package data, not a user preference file.
    if not schema_path.is_file() or schema_path.stat().st_size > 32 * 1024 * 1024:
        raise UnsafeConfig("LibreOffice appearance schema is unavailable")
    root = ET.parse(schema_path).getroot()
    name = "{" + registry.OOR + "}name"
    groups = [e for e in root.iter() if e.tag == "group" and e.get(name) == "ColorScheme"]
    roles = {e.get(name) for group in groups for e in group
             if any(child.get(name) == "Color" for child in e)}
    required = {key[-2] for key in values if key[:len(LO_COLORS)] == LO_COLORS}
    props = {e.get(name) for e in root.iter() if e.tag == "prop"}
    if not required <= roles or not {"ApplicationAppearance", "LibreOfficeTheme", "CurrentColorScheme"} <= props:
        raise UnsafeConfig("LibreOffice version lacks required appearance properties")


def update_libreoffice(config_home, state_home, enabled, palette, version):
    path = config_home / "libreoffice/4/user/registrymodifications.xcu"
    paths = {"config": path}
    journal_path = state_home / "quickshell/user/generated/office/libreoffice.json"
    raw_journal = read_file(journal_path)
    journal = json.loads(raw_journal) if raw_journal else None
    if journal and (journal.get("schema") != 1 or journal.get("paths") != {"config": str(path)}):
        raise UnsafeConfig("ownership receipt does not match this LibreOffice profile")
    if not enabled and journal is None:
        return "disabled"
    if enabled and version is None:
        return "not installed or unsupported package layout"
    if enabled and not re.match(r"^(?:\d+:)?26\.8\.", version):
        return "unsupported version: " + version
    if app_busy("libreoffice") or (path.parent.parent / ".lock").exists():
        return "deferred: close LibreOffice, then refresh Alis colors"
    if journal:
        finish_pending(journal_path, journal, paths)
    old = read_file(path)
    tree = registry.Registry(old)
    if enabled:
        values = libreoffice_values(palette)
        check_libreoffice_schema(values)
        updates = {key: registry.property_xml(key[-1], value) for key, value in values.items()}
        if journal is None:
            if any(key[:len(LO_COLORS)] == LO_COLORS for key in tree.locations):
                raise UnsafeConfig("unowned AlisAuto LibreOffice scheme exists; preserving it")
            previous_scheme = tree.value(LO_BASE + ("CurrentColorScheme",)) or "COLOR_SCHEME_LIBREOFFICE_AUTOMATIC"
            previous_prefix = LO_BASE + ("ColorSchemes", previous_scheme)
            # Keep the selected scheme's explicit document/font/visibility
            # overrides in the managed scheme. Palette updates never rewrite
            # these inherited fields or a later user edit to them.
            inherited = {}
            for key in tree.fields:
                if key[:len(previous_prefix)] == previous_prefix:
                    target = LO_COLORS + key[len(previous_prefix):]
                    if target not in values:
                        if any("/" in part for part in target):
                            raise UnsafeConfig("unsupported custom color property path; preserving the profile")
                        inherited[target] = tree.raw(key)
                        tree.value(key)  # Reject ambiguous/localized values.
            updates.update(inherited)
            journal = {"schema": 1, "paths": {"config": str(path)},
                       "original_config_absent": old is None, "fields": {}}
            for key in updates:
                source = previous_prefix + key[len(LO_COLORS):] if key in inherited else key
                journal["fields"]["/".join(key)] = {
                    "before": packed(tree.raw(key)),
                    "last": tree.value(source) if key in inherited else values[key],
                    "inherited": key in inherited,
                }
        else:
            for field, record in journal["fields"].items():
                key = tuple(field.split("/"))
                if not record["inherited"] and tree.value(key) != record["last"]:
                    raise UnsafeConfig("user changed LibreOffice managed colors/selector; disable to release ownership")
            for key, value in values.items():
                journal["fields"]["/".join(key)]["last"] = value
        new = tree.changed(updates)
        commit_changes(journal_path, journal, {"config": (old, new)}, paths)
        return "applied for next LibreOffice launch"
    updates, conflicts = {}, 0
    for field, record in journal["fields"].items():
        key = tuple(field.split("/"))
        if tree.value(key) == record["last"]:
            updates[key] = unpacked(record["before"])
        else:
            conflicts += 1
    new = tree.changed(updates)
    if journal["original_config_absent"] and new == registry.EMPTY_REGISTRY:
        new = None
    commit_changes(journal_path, journal, {"config": (old, new)}, paths)
    write_file(journal_path, None, read_file(journal_path))
    return f"disabled; preserved {conflicts} user-edited properties" if conflicts else "restored"


def load_palette(state_home):
    palette = {}
    base = state_home / "quickshell/user/generated"
    for name in ("app-palette.json", "palette.json", "colors.json"):
        raw = read_input(base / name)
        if raw is not None:
            palette = json.loads(raw)
            break
    if not isinstance(palette, dict):
        raise UnsafeConfig("palette must be a JSON object")
    return palette


def run_locked(app, config_home, data_home, state_home, enabled):
    lock_path = state_home / f"quickshell/user/generated/office/{app}.lock"
    safe_path(lock_path)
    lock_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "r+") as lock:
        info = os.fstat(lock.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
            raise UnsafeConfig("invalid office update lock")
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return "another office theme update is running"
        version = installed_version(app) if enabled else None
        supported = version is not None and re.match(r"^(?:\d+:)?" + (r"9\.4\." if app == "onlyoffice" else r"26\.8\."), version)
        palette = load_palette(state_home) if enabled and supported else {}
        if app == "onlyoffice":
            return update_onlyoffice(config_home, data_home, state_home, enabled, palette, version)
        return update_libreoffice(config_home, state_home, enabled, palette, version)


def run(config_path, config_home, data_home, state_home):
    config = json.loads(read_input(config_path) or b"{}")
    flags = config.get("appearance", {}).get("wallpaperTheming", {})
    statuses, failed = [], False
    for app, flag, label in (("onlyoffice", "enableOnlyOffice", "ONLYOFFICE"),
                             ("libreoffice", "enableLibreOffice", "LibreOffice")):
        try:
            enabled = flags.get(flag, False)
            if not isinstance(enabled, bool):
                raise UnsafeConfig(flag + " must be a boolean")
            status = run_locked(app, config_home, data_home, state_home, enabled)
        except (UnsafeConfig, registry.RegistryError) as error:
            status, failed = str(error), True
        except (OSError, ValueError, KeyError, TypeError, ET.ParseError, subprocess.SubprocessError):
            status, failed = "not applied: invalid configuration, access error or unknown capability", True
        statuses.append(label + ": " + status)
    return "\n".join(statuses), int(failed)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    try:
        home = Path.home()
        status, result = run(args.config, Path(os.environ.get("XDG_CONFIG_HOME", home / ".config")),
                     Path(os.environ.get("XDG_DATA_HOME", home / ".local/share")),
                     Path(os.environ.get("XDG_STATE_HOME", home / ".local/state")))
        print(status)
        return result
    except UnsafeConfig as error:
        print("Office theming: " + str(error))
        return 1
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        # Config values/paths and private recovery payloads must not enter logs.
        print("Office theming: update not applied; invalid configuration or access error")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
