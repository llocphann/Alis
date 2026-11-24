#!/usr/bin/env python3
"""Modern, structured terminal log viewer and formatter for Alis."""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
from typing import Iterable


LEVEL_RANK = {
    "DEBUG": 10,
    "INFO": 20,
    "NOTICE": 25,
    "WARN": 30,
    "WARNING": 30,
    "ERROR": 40,
    "CRIT": 50,
    "CRITICAL": 50,
    "FATAL": 50,
}

CANONICAL_LEVEL = {
    "DEBUG": "DEBUG",
    "DBG": "DEBUG",
    "INFO": "INFO",
    "NOTICE": "INFO",
    "WARN": "WARN",
    "WARNING": "WARN",
    "ERROR": "ERROR",
    "ERR": "ERROR",
    "CRITICAL": "CRIT",
    "FATAL": "CRIT",
    "CRIT": "CRIT",
}

LEVEL_FILTER_RANK = {
    "debug": 10,
    "info": 20,
    "warn": 30,
    "warning": 30,
    "error": 40,
    "err": 40,
    "crit": 50,
}

# Journalctl short-iso: 2026-11-23T20:46:51+07:00 host unit[pid]: body
JOURNAL_ISO_RE = re.compile(
    r"^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(?:\.\d+)?(?:[+-]\d{2}:?\d{2}|Z)?\s+\S+\s+([^\s\[:]+)(?:\[(\d+)\])?:\s?(.*)$"
)
# Journalctl traditional: Nov 23 20:46:51 host unit[pid]: body
JOURNAL_BSD_RE = re.compile(
    r"^([A-Z][a-z]{2}\s+\d{1,2})\s+(\d{2}:\d{2}:\d{2})\s+\S+\s+([^\s\[:]+)(?:\[(\d+)\])?:\s?(.*)$"
)
# Some subprocesses (e.g. xwayland-satellite) log a duplicate "host unit[pid]:" inside the body
JOURNAL_DUP_PREFIX_RE = re.compile(
    r"^[A-Za-z0-9_.-]+\s+([^\s\[:]+)\[(\d+)\]:\s?(.*)$"
)
# Rust tracing format (e.g. niri): 2026-11-24T00:54:41.891605Z  INFO niri::niri: body
RUST_TRACING_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z\s+(TRACE|DEBUG|INFO|WARN|ERROR)\s+([A-Za-z0-9_:-]+):\s*(.*)$"
)
# Quickshell / Alis line prefix: "  DEBUG qml: ..." or "   INFO scene: ..."
QS_PREFIX_RE = re.compile(
    r"^\s*(DEBUG|INFO|WARN|WARNING|ERROR|CRITICAL|FATAL)(?:\s+([A-Za-z0-9_.*-]+))?:\s*(.*)$"
)
ANSI_STRIP_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
# Simple timestamped update.log prefix: "[2026-11-23 18:13:02] ..." or "2026-11-23 18:13:02 ..."
ALT_TS_RE = re.compile(
    r"^\[?(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})\]?\s*(.*)$"
)
# Component tag: "[Weather] ..." or "Weather: ..."
COMPONENT_RE = re.compile(r"^\[([A-Za-z0-9_.:/ +-]{1,36})\]\s*(.*)$")
QML_LOC_RE = re.compile(r"(@?[A-Za-z0-9_./-]+\.(?:qml|js|py|sh|rs)\[[^\]]+\]|@[A-Za-z0-9_./-]+\.qml:\d+(?::\d+)?)")
ERR_TOKEN_RE = re.compile(
    r"\b(ReferenceError|TypeError|SyntaxError|RangeError|Binding loop|Unable to assign|Cannot assign|Cannot read|Failed to load|Error loading|ERROR|CRITICAL|FATAL)\b"
)
CONTINUATION_RE = re.compile(
    r"^(\s{2,}(?:at\s|\w+@|expression for\b|Caused by:|Traceback|File \")|\s*\^\~*|\t+)"
)


@dataclass
class LogEntry:
    raw: str
    level: str = "INFO"
    category: str = ""
    component: str = ""
    unit: str = ""
    pid: str = ""
    date_str: str = ""
    time_str: str = ""
    message: str = ""
    extras: list[str] = field(default_factory=list)
    count: int = 1

    def to_dict(self) -> dict[str, object]:
        return {
            "date": self.date_str,
            "time": self.time_str,
            "level": self.level,
            "category": self.category,
            "component": self.component,
            "unit": self.unit,
            "pid": self.pid,
            "message": self.message if not self.extras else self.message + "\n" + "\n".join(self.extras),
            "count": self.count,
            "raw": self.raw,
        }


def _hex_to_rgb(hex_color: str) -> tuple[int, int, int] | None:
    s = hex_color.strip()
    if s.startswith("#") and len(s) == 7:
        try:
            return int(s[1:3], 16), int(s[3:5], 16), int(s[5:7], 16)
        except ValueError:
            return None
    return None


class Theme:
    def __init__(self, use_color: bool) -> None:
        self.enabled = use_color
        self.palette = {
            "primary": (131, 211, 227),
            "secondary": (177, 203, 209),
            "tertiary": (185, 205, 255),
            "success": (137, 254, 185),
            "warning": (255, 243, 155),
            "error": (250, 116, 111),
            "on_surface": (221, 231, 234),
            "muted": (140, 146, 148),
            "dim": (102, 112, 116),
            "surface": (24, 34, 37),
            "surface_hi": (35, 48, 52),
            "accent_alt": (204, 158, 252),
            "teal": (93, 219, 221),
        }
        if self.enabled:
            self._load_alis_palette()

    def _load_alis_palette(self) -> None:
        state_home = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
        gen_dir = state_home / "quickshell/user/generated"
        colors_file = gen_dir / "colors.json"
        term_file = gen_dir / "terminal.json"
        colors = {}
        term = {}
        try:
            if colors_file.is_file():
                colors = json.loads(colors_file.read_text(encoding="utf-8"))
        except Exception:
            colors = {}
        try:
            if term_file.is_file():
                term = json.loads(term_file.read_text(encoding="utf-8"))
        except Exception:
            term = {}

        mapping = {
            "primary": colors.get("primary") or term.get("term12"),
            "secondary": colors.get("secondary") or term.get("term7"),
            "tertiary": colors.get("tertiary") or term.get("term13"),
            "success": colors.get("success") or term.get("term10"),
            "warning": term.get("term11") or term.get("term3"),
            "error": colors.get("error") or term.get("term1"),
            "on_surface": colors.get("on_surface") or term.get("term15"),
            "muted": colors.get("on_surface_variant") or term.get("term8"),
            "dim": colors.get("outline") or term.get("term8"),
            "surface": colors.get("surface_container"),
            "surface_hi": colors.get("surface_container_high"),
            "accent_alt": term.get("term5"),
            "teal": term.get("term6"),
        }
        for key, value in mapping.items():
            if isinstance(value, str):
                rgb = _hex_to_rgb(value)
                if rgb:
                    self.palette[key] = rgb

    def fg(self, key: str | tuple[int, int, int], text: str, *, bold: bool = False, underline: bool = False) -> str:
        if not self.enabled:
            return text
        rgb = self.palette[key] if isinstance(key, str) else key
        mods = ["1"] if bold else []
        if underline:
            mods.append("4")
        mods.append(f"38;2;{rgb[0]};{rgb[1]};{rgb[2]}")
        return f"\x1b[{';'.join(mods)}m{text}\x1b[0m"

    def pill(self, fg_key: str | tuple[int, int, int], bg_key: str | tuple[int, int, int], text: str, *, bold: bool = True) -> str:
        if not self.enabled:
            return text
        fg = self.palette[fg_key] if isinstance(fg_key, str) else fg_key
        bg = self.palette[bg_key] if isinstance(bg_key, str) else bg_key
        prefix = "1;" if bold else ""
        return (
            f"\x1b[{prefix}38;2;{fg[0]};{fg[1]};{fg[2]};"
            f"48;2;{bg[0]};{bg[1]};{bg[2]}m{text}\x1b[0m"
        )


def _infer_level(msg: str, default: str = "INFO", *, explicit_level: bool = False) -> str:
    lowered = msg.lower()
    if re.search(r"(?<!not\s)(?<!non-)\b(fatal|critical|panic|segfault)\b", lowered):
        return "CRIT"
    err_tokens = (
        ("ReferenceError", "TypeError", "SyntaxError", "RangeError", "Failed to load configuration", "Cannot load")
        if explicit_level
        else (
            "ReferenceError",
            "TypeError",
            "SyntaxError",
            "RangeError",
            "Failed to",
            "failed with",
            "ERROR",
            "Error:",
            "[ERROR]",
            "Cannot open",
            "Cannot load",
            "Could not",
        )
    )
    if any(tok in msg for tok in err_tokens):
        return "ERROR"
    if not explicit_level and any(
        tok in msg
        for tok in (
            "Binding loop",
            "Unable to assign",
            "Cannot assign",
            "WARN",
            "Warning",
            "warning:",
            "[WARN]",
            "deprecated",
            "Timed out",
        )
    ):
        return "WARN"
    if not explicit_level and any(tok in lowered for tok in ("debug", "[dbg]", "trace:")):
        return "DEBUG"
    return default


def parse_line(raw: str) -> LogEntry:
    line = ANSI_STRIP_RE.sub("", raw.rstrip("\r\n"))
    entry = LogEntry(raw=line)
    rest = line

    m = JOURNAL_ISO_RE.match(line)
    if m:
        entry.date_str, entry.time_str, entry.unit, entry.pid, rest = m.groups()
        entry.pid = entry.pid or ""
    else:
        m = JOURNAL_BSD_RE.match(line)
        if m:
            month_day, entry.time_str, entry.unit, entry.pid, rest = m.groups()
            entry.date_str = month_day.strip()
            entry.pid = entry.pid or ""
        else:
            m = ALT_TS_RE.match(line)
            if m:
                entry.date_str, entry.time_str, rest = m.groups()

    if entry.unit:
        dup_m = JOURNAL_DUP_PREFIX_RE.match(rest)
        if dup_m:
            dup_unit, dup_pid, dup_body = dup_m.groups()
            entry.unit = dup_unit
            entry.pid = dup_pid
            rest = dup_body

    explicit_level = False
    qs_m = QS_PREFIX_RE.match(rest)
    if qs_m:
        lvl_raw, cat, body = qs_m.groups()
        entry.level = CANONICAL_LEVEL.get(lvl_raw.upper(), "INFO")
        entry.category = (cat or "").strip()
        rest = body.strip()
        explicit_level = True
    else:
        rust_m = RUST_TRACING_RE.match(rest)
        if rust_m:
            lvl_raw, module_name, body = rust_m.groups()
            lvl_norm = "DEBUG" if lvl_raw.upper() == "TRACE" else CANONICAL_LEVEL.get(lvl_raw.upper(), "INFO")
            entry.level = lvl_norm
            entry.component = module_name.strip()
            rest = body.strip()
            explicit_level = True
        else:
            # Handle systemd unit status or plain update.log lines
            bracket_lvl = re.match(r"^\[(INFO|WARN|WARNING|ERROR|ERR|DEBUG|OK|SUCCESS|FAIL)\]\s*(.*)$", rest, re.I)
            if bracket_lvl:
                tag, rest = bracket_lvl.groups()
                u = tag.upper()
                if u in ("OK", "SUCCESS"):
                    entry.level = "INFO"
                elif u == "FAIL":
                    entry.level = "ERROR"
                else:
                    entry.level = CANONICAL_LEVEL.get(u, "INFO")
                explicit_level = True
            else:
                colon_lvl = re.match(r"^(INFO|WARN|WARNING|ERROR|ERR|DEBUG|CRITICAL|FATAL):\s+(.*)$", rest)
                if colon_lvl:
                    tag, rest = colon_lvl.groups()
                    entry.level = CANONICAL_LEVEL.get(tag.upper(), "INFO")
                    explicit_level = True
                else:
                    entry.level = _infer_level(rest, "INFO", explicit_level=False)

    comp_m = COMPONENT_RE.match(rest)
    if comp_m:
        tag = comp_m.group(1).strip()
        # Avoid treating timestamps like [12:34:56] as components
        if not re.match(r"^\d{2}:\d{2}(?::\d{2})?$", tag):
            entry.component = tag
            rest = comp_m.group(2).strip()

    # If a unit is systemd and no component tag was present, derive subtle component from unit
    if not entry.component and entry.unit:
        if entry.unit == "systemd":
            entry.component = "systemd"
            if not entry.category:
                entry.category = "unit"
        elif entry.unit in ("xembedsniproxy", "xwayland-satellite"):
            entry.component = entry.unit

    # Upgrade INFO/WARN -> WARN/ERROR/CRIT safely without turning non-fatal/external Qt warnings into errors
    inferred = _infer_level(rest, entry.level, explicit_level=explicit_level)
    if LEVEL_RANK.get(inferred, 20) > LEVEL_RANK.get(entry.level, 20):
        entry.level = inferred

    entry.message = rest
    return entry


def parse_lines(lines: Iterable[str]) -> list[LogEntry]:
    entries: list[LogEntry] = []
    for raw in lines:
        stripped = raw.rstrip("\r\n")
        if not stripped.strip():
            continue
        if entries and CONTINUATION_RE.match(stripped) and not QS_PREFIX_RE.match(stripped) and not JOURNAL_ISO_RE.match(stripped):
            entries[-1].extras.append(stripped)
            if LEVEL_RANK.get(_infer_level(stripped, "DEBUG"), 10) > LEVEL_RANK.get(entries[-1].level, 10):
                entries[-1].level = _infer_level(stripped, entries[-1].level)
            continue
        entries.append(parse_line(stripped))
    return entries


def _level_matches(entry: LogEntry, min_rank: int) -> bool:
    return LEVEL_RANK.get(entry.level, 20) >= min_rank


def filter_entries(
    entries: list[LogEntry],
    *,
    min_level_rank: int = 0,
    component: str = "",
    category: str = "",
    grep_re: re.Pattern[str] | None = None,
) -> list[LogEntry]:
    comp_l = component.lower().strip()
    cat_l = category.lower().strip()
    out: list[LogEntry] = []
    for e in entries:
        if min_level_rank and not _level_matches(e, min_level_rank):
            continue
        if comp_l and comp_l not in e.component.lower() and comp_l not in e.unit.lower():
            continue
        if cat_l and cat_l not in e.category.lower():
            continue
        if grep_re:
            haystack = " ".join([e.level, e.category, e.component, e.unit, e.message, *e.extras])
            if not grep_re.search(haystack):
                continue
        out.append(e)
    return out


def collapse_repeats(entries: list[LogEntry]) -> list[LogEntry]:
    if not entries:
        return []
    collapsed: list[LogEntry] = []
    for e in entries:
        if (
            collapsed
            and not e.extras
            and not collapsed[-1].extras
            and collapsed[-1].level == e.level
            and collapsed[-1].component == e.component
            and collapsed[-1].category == e.category
            and collapsed[-1].message == e.message
        ):
            collapsed[-1].count += e.count
            if e.time_str:
                collapsed[-1].time_str = e.time_str
            if e.date_str:
                collapsed[-1].date_str = e.date_str
        else:
            collapsed.append(e)
    return collapsed


def _component_color(theme: Theme, component: str) -> tuple[int, int, int]:
    pool = [
        theme.palette["primary"],
        theme.palette["teal"],
        theme.palette["tertiary"],
        theme.palette["accent_alt"],
        theme.palette["success"],
        theme.palette["secondary"],
    ]
    h = sum((idx + 1) * ord(ch) for idx, ch in enumerate(component))
    return pool[h % len(pool)]


def _highlight_message(
    text: str,
    level: str,
    theme: Theme,
    grep_re: re.Pattern[str] | None = None,
) -> str:
    if not theme.enabled:
        return text

    # Build spans carefully by tokenizing known rich segments in a single pass
    patterns = [
        ("ERR", ERR_TOKEN_RE),
        ("LOC", QML_LOC_RE),
    ]
    if grep_re:
        patterns.insert(0, ("GREP", grep_re))

    # Apply non-overlapping replacements greedily left-to-right
    spans: list[tuple[int, int, str, str]] = []
    for kind, pat in patterns:
        for m in pat.finditer(text):
            if m.start() == m.end():
                continue
            s, e = m.start(), m.end()
            if any(not (e <= os_ or s >= oe_) for os_, oe_, _, _ in spans):
                continue
            spans.append((s, e, kind, m.group(0)))
    spans.sort(key=lambda item: item[0])

    base_color = (
        "error"
        if level in ("ERROR", "CRIT")
        else ("warning" if level == "WARN" else ("muted" if level == "DEBUG" else "on_surface"))
    )

    chunks: list[str] = []
    pos = 0
    for s, e, kind, tok in spans:
        if s > pos:
            chunks.append(theme.fg(base_color, text[pos:s]))
        if kind == "GREP":
            chunks.append(theme.pill("surface", "warning", tok, bold=True))
        elif kind == "ERR":
            chunks.append(theme.fg("error", tok, bold=True))
        else:
            chunks.append(theme.fg("teal", tok, underline=True))
        pos = e
    if pos < len(text):
        chunks.append(theme.fg(base_color, text[pos:]))
    return "".join(chunks)


def _badge_for_level(theme: Theme, level: str) -> str:
    if level == "CRIT":
        return theme.pill("surface", "error", " CRIT ", bold=True) if theme.enabled else "[CRIT]"
    if level == "ERROR":
        return theme.fg("error", "✖ ERR ", bold=True) if theme.enabled else "[ERR ]"
    if level == "WARN":
        return theme.fg("warning", "▲ WARN", bold=True) if theme.enabled else "[WARN]"
    if level == "DEBUG":
        return theme.fg("dim", "· DBG ") if theme.enabled else "[DBG ]"
    return theme.fg("primary", "● INFO", bold=True) if theme.enabled else "[INFO]"


def _term_width() -> int:
    cols = shutil.get_terminal_size((100, 24)).columns
    return max(72, min(132, cols))


def _visible_len(s: str) -> int:
    return len(re.sub(r"\x1b\[[0-9;]*m", "", s))


def render_header(
    theme: Theme,
    *,
    source_label: str,
    entries: list[LogEntry],
    raw_count: int,
    filters_desc: list[str],
) -> str:
    width = _term_width()
    counts = Counter(e.level for e in entries)
    err_n = counts.get("ERROR", 0) + counts.get("CRIT", 0)
    warn_n = counts.get("WARN", 0)
    info_n = counts.get("INFO", 0)
    dbg_n = counts.get("DEBUG", 0)

    title = theme.fg("primary", "ALIS LOGS", bold=True)
    src_badge = theme.pill("on_surface", "surface_hi", f" {source_label} ", bold=False)
    filter_str = " ".join(
        theme.fg("tertiary", f"[{f}]") for f in filters_desc
    ) if filters_desc else theme.fg("dim", "all levels")

    stats = "  ".join([
        theme.fg("error" if err_n else "dim", f"✖ {err_n} ERR", bold=bool(err_n)),
        theme.fg("warning" if warn_n else "dim", f"▲ {warn_n} WARN", bold=bool(warn_n)),
        theme.fg("primary" if info_n else "dim", f"● {info_n} INFO"),
        theme.fg("dim", f"· {dbg_n} DBG"),
        theme.fg("dim", f"({len(entries)} shown / {raw_count} read)"),
    ])

    inner = width - 4
    line1 = f"{title}  {src_badge}  {filter_str}"
    line2 = stats
    pad1 = max(0, inner - _visible_len(line1))
    pad2 = max(0, inner - _visible_len(line2))

    b = lambda ch: theme.fg("dim", ch)
    top = b("╭" + "─" * (width - 2) + "╮")
    row1 = f"{b('│')} {line1}{' ' * pad1} {b('│')}"
    row2 = f"{b('│')} {line2}{' ' * pad2} {b('│')}"
    bot = b("╰" + "─" * (width - 2) + "╯")
    return "\n".join([top, row1, row2, bot])


def format_entry(
    entry: LogEntry,
    theme: Theme,
    *,
    grep_re: re.Pattern[str] | None = None,
    show_category: bool = True,
) -> list[str]:
    ts = entry.time_str or "──:──:──"
    ts_col = theme.fg("dim", ts)
    lvl_col = _badge_for_level(theme, entry.level)

    meta_parts: list[str] = []
    if entry.component:
        comp_rgb = _component_color(theme, entry.component)
        meta_parts.append(theme.fg(comp_rgb, f"[{entry.component}]", bold=True))
    if show_category and entry.category and entry.category not in ("qml",):
        meta_parts.append(theme.fg("dim", f"({entry.category})"))

    meta_str = " ".join(meta_parts)
    msg_str = _highlight_message(entry.message, entry.level, theme, grep_re)
    if meta_str:
        body = f"{meta_str} {msg_str}"
    else:
        body = msg_str

    if entry.count > 1:
        body += " " + theme.pill("surface", "secondary", f" ×{entry.count} ", bold=True)

    lines = [f" {ts_col}  {lvl_col}  {body}"]
    rail = theme.fg("dim", "│")
    for extra in entry.extras:
        lines.append(f" {' ' * len(ts)}  {rail}       {_highlight_message(extra.strip(), entry.level, theme, grep_re)}")
    return lines


def render_summary(entries: list[LogEntry], theme: Theme, *, source_label: str) -> str:
    width = _term_width()
    counts = Counter(e.level for e in entries)
    total = max(1, len(entries))
    comp_counts = Counter(e.component or e.category or "core" for e in entries)
    issues: list[LogEntry] = []
    seen_issue: set[tuple[str, str, str]] = set()
    for e in reversed(entries):
        if e.level not in ("WARN", "ERROR", "CRIT"):
            continue
        key = (e.level, e.component, e.message)
        if key in seen_issue:
            continue
        seen_issue.add(key)
        issues.append(e)
        if len(issues) >= 8:
            break
    issues.reverse()

    out = [
        render_header(
            theme,
            source_label=f"{source_label} · Summary",
            entries=entries,
            raw_count=len(entries),
            filters_desc=["stats"],
        ),
        "",
        " " + theme.fg("primary", "Severity Breakdown", bold=True),
    ]
    bar_w = max(16, min(36, width - 38))
    for lvl, key in (("CRIT", "error"), ("ERROR", "error"), ("WARN", "warning"), ("INFO", "primary"), ("DEBUG", "dim")):
        c = counts.get(lvl, 0)
        if c == 0 and lvl == "CRIT":
            continue
        pct = (c * 100.0) / total
        filled = int(round((c / total) * bar_w)) if c else 0
        bar = theme.fg(key, "█" * max(1 if c else 0, filled)) + theme.fg("dim", "░" * (bar_w - max(1 if c else 0, filled)))
        out.append(f"   {theme.fg(key, f'{lvl:<5}', bold=True)}  {bar}  {c:>5} ({pct:5.1f}%)")

    out.extend(["", " " + theme.fg("primary", "Top Components", bold=True)])
    for comp, c in comp_counts.most_common(10):
        rgb = _component_color(theme, comp)
        label_plain = f"[{comp}]"
        pad = " " * max(2, 32 - len(label_plain))
        out.append(f"   {theme.fg(rgb, label_plain, bold=True)}{pad}{c:>5}")

    out.extend(["", " " + theme.fg("primary", "Recent Warnings & Errors", bold=True)])
    if not issues:
        out.append("   " + theme.fg("success", "✓ No warnings or errors in scanned window"))
    else:
        for e in issues:
            out.extend(format_entry(e, theme))
    return "\n".join(out)


def classify_issue(entry: LogEntry) -> tuple[bool, str, str]:
    """Return (is_noise, category_or_label, fix_hint) for WARN/ERROR/CRIT entries."""
    msg = entry.message
    cat = (entry.category or "").lower()
    comp = (entry.component or "").lower()
    unit = (entry.unit or "").lower()

    # Known environmental noise (non-actionable in normal Niri + Quickshell sessions)
    if (
        cat == "qt.accessibility.atspi"
        or comp == "qt.accessibility.atspi"
        or "AtSpiAdaptor" in msg
        or 'Subscription string not handled: "Window:Destroy:"' in msg
    ):
        return (
            True,
            "qt.accessibility.atspi",
            "Qt AT-SPI bridge noise under Niri; silence via QT_LOGGING_RULES+=qt.accessibility.atspi.warning=false",
        )
    if "$HYPRLAND_INSTANCE_SIGNATURE is unset" in msg or "Cannot connect to hyprland" in msg:
        return (True, "hyprland-probe", "Expected when running Alis under Niri instead of Hyprland")
    if cat == "qt.qpa.services" or comp == "qt.qpa.services" or "Connection already associated with an application ID" in msg:
        return (
            True,
            "qt.qpa.services",
            "Host portal app ID already registered on session; silence via qt.qpa.services.warning=false",
        )
    if (
        "xkbcomp" in msg.lower()
        or "Unsupported maximum keycode" in msg
        or "Virtual modifier" in msg
        or ("xwayland-satellite" in unit and ("X11 cannot support keycodes" in msg or "Using 0, ignoring 0" in msg))
    ):
        return (True, "xwayland-xkbcomp", "Non-fatal Xwayland XKB keymap compatibility notice")
    if cat == "qt.svg" and "Could not resolve property:" in msg:
        return (True, "qt.svg", "External icon theme SVG uses an unsupported property/reference")
    if cat == "quickshell.service.sni.item" and "Failed to load tray item" in msg:
        return (
            True,
            "quickshell.sni-transient",
            "Transient external StatusNotifierItem D-Bus client vanished or re-registered during tray handshake",
        )

    # Actionable hint derivation
    if "File does not exist" in msg or "FileView" in msg:
        hint = "Add printErrors: false on optional FileView or guard existence before reading"
    elif "Binding loop" in msg:
        hint = "Break circular QML property dependency (use an intermediate state trigger or onChanged handler)"
    elif any(tok in msg for tok in ("ReferenceError", "TypeError", "SyntaxError", "RangeError")):
        hint = "Fix undefined/null property access or invalid import at the reported QML/JS source"
    elif "Window.window only supports types derived from Item" in msg:
        hint = "Use root.Window.activeFocusItem / root.Window.window instead of bare Window.* inside Shortcut/TapHandler/non-Item QObject"
    elif "Unable to assign" in msg or "Cannot assign" in msg:
        hint = "Coerce nullable/undefined value with an explicit typed fallback before assignment"
    elif "capture process failed" in msg:
        hint = "Defer window preview capture while screenLocked or guard closed window IDs before spawning helper"
    elif "Failed to create graphics context" in msg or "OpenGL" in msg:
        hint = "Check RHI/OpenGL backend; tests rendering shaders/grabToImage must not force software GL"
    elif "timed out" in msg.lower() or "timeout" in msg.lower():
        hint = "Inspect hanging helper/subprocess or network timeout handling"
    else:
        hint = "Inspect the cited component and stack trace to add an explicit guard or fix the failing handler"

    return (False, entry.component or entry.category or entry.unit or "core", hint)


def _normalize_issue_sig(entry: LogEntry, source_loc: str) -> tuple[str, str, str, str]:
    text = entry.message
    text = re.sub(r"\b\d{4}-\d{2}-\d{2}\b", "<date>", text)
    text = re.sub(r"/tmp/[^\s\"')]+", "/tmp/<path>", text)
    text = re.sub(r"0x[0-9a-fA-F]+", "0x<addr>", text)
    text = re.sub(r":1\.\d+/", ":1.<id>/", text)
    text = re.sub(r"\b\d{4,}\b", "<n>", text)
    owner = entry.component or entry.category or entry.unit or "core"
    return (entry.level, owner, source_loc, text)


def analyze_entries(
    entries: list[LogEntry],
    *,
    source_label: str = "",
    meta: dict[str, str] | None = None,
) -> dict[str, object]:
    meta = meta or {}
    act_groups: dict[tuple[str, str, str, str], dict[str, object]] = {}
    noise_groups: dict[str, dict[str, object]] = {}
    total_read = 0

    for e in entries:
        total_read += max(1, e.count)
        if e.level not in ("WARN", "ERROR", "CRIT"):
            continue
        is_noise, label, hint = classify_issue(e)
        if is_noise:
            bucket = noise_groups.get(label)
            if bucket is None:
                bucket = {"label": label, "level": e.level, "count": 0, "sample": e.message}
                noise_groups[label] = bucket
            bucket["count"] = int(bucket["count"]) + max(1, e.count)
            continue

        loc_m = QML_LOC_RE.search(e.message + ("\n" + "\n".join(e.extras) if e.extras else ""))
        source_loc = loc_m.group(0) if loc_m else ""
        sig = _normalize_issue_sig(e, source_loc)
        ts = f"{e.date_str} {e.time_str}".strip() or e.time_str or ""
        g = act_groups.get(sig)
        if g is None:
            g = {
                "level": e.level,
                "component": e.component or e.category or e.unit or "core",
                "category": e.category,
                "sourceLoc": source_loc,
                "count": 0,
                "firstSeen": ts,
                "lastSeen": ts,
                "message": e.message if not e.extras else e.message + " | " + " ".join(x.strip() for x in e.extras[:2]),
                "hint": hint,
            }
            act_groups[sig] = g
        g["count"] = int(g["count"]) + max(1, e.count)
        if ts:
            if not g["firstSeen"]:
                g["firstSeen"] = ts
            g["lastSeen"] = ts

    actionable = sorted(
        act_groups.values(),
        key=lambda row: (-LEVEL_RANK.get(str(row["level"]), 20), -int(row["count"]), str(row["component"])),
    )
    noise = sorted(noise_groups.values(), key=lambda row: -int(row["count"]))
    actionable_count = sum(int(r["count"]) for r in actionable)
    noise_count = sum(int(r["count"]) for r in noise)

    return {
        "source": source_label,
        "invocationId": meta.get("invocation_id", ""),
        "activeSince": meta.get("active_since", ""),
        "activeState": meta.get("active_state", ""),
        "mainPid": meta.get("main_pid", ""),
        "totalRead": total_read,
        "actionableCount": actionable_count,
        "actionableGroups": len(actionable),
        "noiseCount": noise_count,
        "healthy": actionable_count == 0,
        "actionable": actionable,
        "noise": noise,
    }


def render_diagnose(report: dict[str, object], theme: Theme) -> str:
    width = _term_width()
    inner = width - 4
    inv = str(report.get("invocationId") or "")
    since = str(report.get("activeSince") or "")
    src = str(report.get("source") or "logs")
    actionable: list[dict[str, object]] = list(report.get("actionable") or [])  # type: ignore[arg-type]
    noise: list[dict[str, object]] = list(report.get("noise") or [])  # type: ignore[arg-type]
    act_count = int(report.get("actionableCount") or 0)
    noise_count = int(report.get("noiseCount") or 0)
    total_read = int(report.get("totalRead") or 0)

    err_groups = sum(1 for r in actionable if r["level"] in ("ERROR", "CRIT"))
    warn_groups = sum(1 for r in actionable if r["level"] == "WARN")

    title = theme.fg("primary", "ALIS DIAGNOSE", bold=True)
    src_badge = theme.pill("on_surface", "surface_hi", f" {src} ", bold=False)
    verdict = (
        theme.pill("surface", "success", " ✓ HEALTHY ", bold=True)
        if act_count == 0
        else theme.pill("surface", "error", f" ! {len(actionable)} ACTIONABLE ", bold=True)
    )
    meta_parts = []
    if inv:
        meta_parts.append(f"inv={inv[:8]}")
    if since:
        meta_parts.append(f"since={since}")
    meta_str = theme.fg("dim", " ".join(meta_parts)) if meta_parts else ""

    line1 = f"{title}  {src_badge}  {verdict}" + (f"  {meta_str}" if meta_str else "")
    line2 = "  ".join([
        theme.fg("error" if err_groups else "dim", f"✖ {err_groups} ERR groups", bold=bool(err_groups)),
        theme.fg("warning" if warn_groups else "dim", f"▲ {warn_groups} WARN groups", bold=bool(warn_groups)),
        theme.fg("dim", f"~ {noise_count} noise suppressed"),
        theme.fg("dim", f"({total_read} entries scanned)"),
    ])
    width = max(width, _visible_len(line1) + 4, _visible_len(line2) + 4)
    inner = width - 4
    pad1 = max(0, inner - _visible_len(line1))
    pad2 = max(0, inner - _visible_len(line2))
    b = lambda ch: theme.fg("dim", ch)
    out = [
        b("╭" + "─" * (width - 2) + "╮"),
        f"{b('│')} {line1}{' ' * pad1} {b('│')}",
        f"{b('│')} {line2}{' ' * pad2} {b('│')}",
        b("╰" + "─" * (width - 2) + "╯"),
        "",
        " " + theme.fg("primary", "Actionable Issues", bold=True),
    ]

    if not actionable:
        out.append("   " + theme.fg("success", "✓ No actionable warnings or errors found."))
    else:
        for idx, item in enumerate(actionable, 1):
            lvl = str(item["level"])
            badge = _badge_for_level(theme, lvl)
            comp = str(item["component"])
            cnt = int(item["count"])
            loc = str(item["sourceLoc"] or "")
            comp_str = theme.fg(_component_color(theme, comp), f"[{comp}]", bold=True)
            cnt_str = theme.pill("surface", "secondary", f" ×{cnt} ", bold=True) if cnt > 1 else ""
            loc_str = (" " + theme.fg("teal", loc, underline=True)) if loc else ""
            when = str(item["lastSeen"] or item["firstSeen"] or "")
            when_str = ("  " + theme.fg("dim", when)) if when else ""
            msg_str = _highlight_message(str(item["message"]), lvl, theme)
            hint_str = theme.fg("primary", "Hint:") + " " + theme.fg("on_surface", str(item["hint"]))
            out.append(f"   {theme.fg('dim', f'{idx}.')} {badge} {comp_str}{loc_str} {cnt_str}{when_str}".rstrip())
            out.append(f"      {msg_str}")
            out.append(f"      {hint_str}")

    if noise:
        out.extend(["", " " + theme.fg("dim", f"Suppressed Environmental Noise ({noise_count} events)")])
        for n in noise:
            lbl = str(n["label"])
            cnt = int(n["count"])
            sample = str(n["sample"])[:72]
            out.append("   " + theme.fg("dim", f"· {cnt:>4}×  {lbl:<24s}  ({sample})"))

    return "\n".join(out)


def _find_qs() -> str:
    env_bin = os.environ.get("ALIS_QS_BIN", "")
    if env_bin and os.access(env_bin, os.X_OK):
        return env_bin
    for cand in ("/usr/bin/qs", shutil.which("qs") or ""):
        if cand and os.access(cand, os.X_OK):
            return cand
    return ""


def _resolve_config_dir(explicit: str = "") -> str:
    if explicit and Path(explicit, "shell.qml").is_file():
        return explicit
    xdg = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
    for cand in (
        os.environ.get("ALIS_RUNTIME_DIR", ""),
        str(xdg / "quickshell/alis"),
        os.environ.get("ALIS_SYSTEM_RUNTIME_DIR", "/usr/local/share/quickshell/alis"),
        os.environ.get("ALIS_FALLBACK_SYSTEM_RUNTIME_DIR", "/usr/share/quickshell/alis"),
    ):
        if cand and Path(cand, "shell.qml").is_file():
            return cand
    return str(xdg / "quickshell/alis")


def _systemd_service_active(unit: str) -> bool:
    if not shutil.which("systemctl"):
        return False
    r = subprocess.run(
        ["systemctl", "--user", "is-active", "--quiet", unit],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return r.returncode == 0


def _service_invocation_info(unit: str = "alis.service") -> dict[str, str]:
    if not shutil.which("systemctl"):
        return {}
    r = subprocess.run(
        [
            "systemctl",
            "--user",
            "show",
            unit,
            "--property=InvocationID,ActiveEnterTimestamp,ActiveState,MainPID",
        ],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        return {}
    info: dict[str, str] = {}
    for line in r.stdout.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            info[k.strip()] = v.strip()
    return {
        "invocation_id": info.get("InvocationID", ""),
        "active_since": info.get("ActiveEnterTimestamp", ""),
        "active_state": info.get("ActiveState", ""),
        "main_pid": info.get("MainPID", ""),
    }


def _update_log_path() -> Path | None:
    state_home = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
    cache_home = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
    for cand in (
        state_home / "quickshell/user/update.log",
        cache_home / "alis/update.log",
    ):
        if cand.is_file():
            return cand
    return None


def _read_source_lines(
    args: argparse.Namespace,
    meta_out: dict[str, str] | None = None,
) -> tuple[str, list[str], list[str] | None]:
    """Return (source_label, static_lines, follow_cmd_or_None)."""
    if args.stdin:
        lines = sys.stdin.read().splitlines()
        label = args.source_label if args.source_label != "Alis" else "stdin"
        return label, lines, None
    source = args.source
    fetch_lines = args.lines
    use_since_restart = bool(args.since_restart or (args.diagnose and not args.since))
    has_filters = any([
        args.level,
        args.errors,
        args.component,
        args.category,
        args.grep,
        args.summary,
        args.diagnose,
        args.hide_noise,
    ])
    if use_since_restart:
        fetch_lines = max(fetch_lines, 2000)
    elif has_filters and not args.explicit_lines and not args.since:
        fetch_lines = max(args.lines * 25, 1500)

    if source == "auto":
        if args.full and _find_qs():
            source = "qs"
        elif shutil.which("journalctl") and _systemd_service_active("alis.service"):
            source = "service"
        elif _find_qs():
            source = "qs"
        elif shutil.which("journalctl"):
            source = "service"
        else:
            source = "update"

    if source in ("service", "tray", "niri", "all"):
        if not shutil.which("journalctl"):
            raise RuntimeError("journalctl is required for systemd journal logs")
        units = {
            "service": ["-u", "alis.service"],
            "tray": ["-u", "alis-xembedsniproxy.service"],
            "niri": ["-u", "niri.service"],
            "all": ["-u", "alis.service", "-u", "alis-xembedsniproxy.service"],
        }[source]
        labels = {
            "service": "alis.service",
            "tray": "alis-xembedsniproxy.service",
            "niri": "niri.service",
            "all": "alis.service + tray",
        }
        cmd = ["journalctl", "--user", *units, "--output=short-iso", "--no-pager"]
        meta_unit = {
            "service": "alis.service",
            "tray": "alis-xembedsniproxy.service",
            "niri": "niri.service",
        }.get(source, "alis.service")
        svc_meta = _service_invocation_info(meta_unit) if (use_since_restart or args.diagnose) else {}
        if meta_out is not None and svc_meta:
            meta_out.update(svc_meta)
        if args.since:
            cmd.extend(["--since", args.since])
        elif use_since_restart and svc_meta:
            inv_id = svc_meta.get("invocation_id", "")
            active_ts = svc_meta.get("active_since", "")
            if source in ("service", "tray", "niri") and inv_id and inv_id != "00000000000000000000000000000000":
                cmd.append(f"_SYSTEMD_INVOCATION_ID={inv_id}")
            elif active_ts and active_ts not in ("n/a", ""):
                cmd.extend(["--since", active_ts])
        if args.follow:
            cmd.extend(["-n", str(args.lines), "-f"])
            return labels[source], [], cmd
        cmd.extend(["-n", str(fetch_lines)])
        res = subprocess.run(cmd, capture_output=True, text=True)
        lines = res.stdout.splitlines()
        if source in ("service", "tray", "niri") and use_since_restart and not lines and svc_meta.get("active_since"):
            # Fallback if journald did not index _SYSTEMD_INVOCATION_ID for older units
            fb_cmd = ["journalctl", "--user", "-u", meta_unit, "--output=short-iso", "--no-pager", "--since", svc_meta["active_since"], "-n", str(fetch_lines)]
            lines = subprocess.run(fb_cmd, capture_output=True, text=True).stdout.splitlines()
        if source == "niri" and not lines:
            fallback = ["journalctl", "--user", "_COMM=niri", "--output=short-iso", "--no-pager", "-n", str(fetch_lines)]
            if args.since:
                fallback.extend(["--since", args.since])
            res2 = subprocess.run(fallback, capture_output=True, text=True)
            lines = res2.stdout.splitlines()
            return "niri", lines, None
        return labels[source], lines, None

    if source == "qs":
        qs = _find_qs()
        if not qs:
            raise RuntimeError("Quickshell ('qs') binary not found")
        cfg = _resolve_config_dir(args.config)
        cmd = [qs, "-p", cfg, "log"]
        if args.full:
            cmd.extend(["--rules", "*=true"])
        if args.follow:
            cmd.append("-f")
            return f"qs log ({Path(cfg).name})", [], cmd
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0 and not res.stdout.strip():
            err = res.stderr.strip() or f"qs log exited with {res.returncode}"
            raise RuntimeError(err)
        lines = res.stdout.splitlines()
        if not has_filters and len(lines) > fetch_lines:
            lines = lines[-fetch_lines:]
        return f"qs log{' --full' if args.full else ''}", lines, None

    if source == "update":
        path = _update_log_path()
        if not path:
            raise RuntimeError("No update.log found under ~/.local/state/quickshell/user/")
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        if args.follow:
            return f"update.log ({path.name})", [], ["tail", "-n", str(args.lines), "-f", str(path)]
        return str(path), lines[-fetch_lines:], None

    raise RuntimeError(f"Unknown log source: {source}")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="alis logs",
        description="Modern structured log viewer for Alis (journal, Quickshell, tray proxy, update logs).",
    )
    p.add_argument("-c", "--config", default="", help="Alis shell config/runtime directory")
    p.add_argument("-n", "--lines", type=int, default=60, help="Number of matching log entries to show (default: 60)")
    p.add_argument("-f", "--follow", action="store_true", help="Follow new log entries live")
    p.add_argument("-l", "--level", default="", help="Minimum severity: debug, info, warn, error, crit")
    p.add_argument("-e", "--errors", action="store_true", help="Show warnings and errors only (alias for --level warn)")
    p.add_argument("-m", "--component", default="", help="Filter by component tag (e.g. Weather, Tray, ShellUpdates)")
    p.add_argument("--category", default="", help="Filter by log category (e.g. qml, scene, unit)")
    p.add_argument("-g", "--grep", default="", help="Case-insensitive regex search on message")
    p.add_argument("-s", "--since", default="", help="Journalctl --since time filter (e.g. '10 min ago', 'today')")
    p.add_argument("--since-restart", action="store_true", help="Filter journal logs to current alis.service InvocationID")
    p.add_argument(
        "--source",
        default="auto",
        choices=["auto", "service", "qs", "tray", "update", "niri", "all"],
        help="Log source (default: auto)",
    )
    p.add_argument("--full", action="store_true", help="Include all Qt logging categories (with qs) and debug entries")
    p.add_argument("--summary", "--stats", dest="summary", action="store_true", help="Show severity counts, top components, and recent issues")
    p.add_argument("--diagnose", "--check", dest="diagnose", action="store_true", help="Separate actionable warnings/errors (with source/hints) from known noise")
    p.add_argument("--fail-on-error", action="store_true", help="Exit 1 when actionable warnings/errors are present")
    p.add_argument("--hide-noise", action="store_true", help="Hide known environmental noise (AT-SPI, Hyprland probe, portal duplicate)")
    p.add_argument("--json", action="store_true", help="Output parsed entries (or diagnose report) as JSON")
    p.add_argument("--ndjson", action="store_true", help="Output one parsed JSON object per line")
    p.add_argument("--raw", action="store_true", help="Pass through raw unformatted log lines")
    p.add_argument("--no-collapse", action="store_true", help="Do not collapse consecutive duplicate entries")
    p.add_argument("--stdin", action="store_true", help="Read and format log lines from stdin")
    p.add_argument("--source-label", default="Alis", help=argparse.SUPPRESS)
    color_grp = p.add_mutually_exclusive_group()
    color_grp.add_argument("--color", action="store_true", help="Force colored ANSI output even when piped")
    color_grp.add_argument("--no-color", action="store_true", help="Disable ANSI color sequences")
    return p


def main(argv: list[str] | None = None) -> int:
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    raw_argv = list(sys.argv[1:] if argv is None else argv)
    parser = build_parser()
    args = parser.parse_args(raw_argv)
    args.explicit_lines = any(a in ("-n", "--lines") or a.startswith("--lines=") for a in raw_argv)

    use_color = False
    if args.color:
        use_color = True
    elif args.no_color or os.environ.get("NO_COLOR"):
        use_color = False
    else:
        use_color = sys.stdout.isatty()
    theme = Theme(use_color=use_color)

    min_rank = 0
    if args.errors:
        min_rank = LEVEL_FILTER_RANK["warn"]
    if args.level:
        key = args.level.strip().lower()
        if key not in LEVEL_FILTER_RANK:
            print(f"Invalid level '{args.level}'. Expected: debug, info, warn, error, crit", file=sys.stderr)
            return 2
        min_rank = LEVEL_FILTER_RANK[key]
    elif args.full:
        min_rank = 0

    grep_re = None
    if args.grep:
        try:
            grep_re = re.compile(args.grep, re.IGNORECASE)
        except re.error as exc:
            print(f"Invalid --grep regex: {exc}", file=sys.stderr)
            return 2

    filters_desc: list[str] = []
    if min_rank >= 40:
        filters_desc.append("level>=error")
    elif min_rank >= 30:
        filters_desc.append("level>=warn")
    elif args.level:
        filters_desc.append(f"level>={args.level.lower()}")
    if args.component:
        filters_desc.append(f"component:{args.component}")
    if args.category:
        filters_desc.append(f"category:{args.category}")
    if args.grep:
        filters_desc.append(f"grep:{args.grep}")
    if args.since:
        filters_desc.append(f"since:{args.since}")

    # Streaming follow mode
    if args.follow:
        source_label = args.source_label if args.stdin else args.source
        proc: subprocess.Popen[str] | None = None
        if args.stdin:
            stream = sys.stdin
        else:
            try:
                source_label, _, cmd = _read_source_lines(args)
            except RuntimeError as exc:
                print(f"alis logs: {exc}", file=sys.stderr)
                return 1
            if cmd is None:
                return 0
            if args.raw:
                return subprocess.call(cmd)
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
            assert proc.stdout is not None
            stream = proc.stdout

        if not args.raw and not args.json and not args.ndjson:
            print(render_header(theme, source_label=f"{source_label} · live", entries=[], raw_count=0, filters_desc=filters_desc), flush=True)
        last_date = ""
        try:
            for raw in stream:
                raw_s = raw.rstrip("\r\n")
                if not raw_s.strip():
                    continue
                if args.raw:
                    print(raw_s, flush=True)
                    continue
                entry = parse_line(raw_s)
                if not filter_entries([entry], min_level_rank=min_rank, component=args.component, category=args.category, grep_re=grep_re):
                    continue
                if args.hide_noise and entry.level in ("WARN", "ERROR", "CRIT") and classify_issue(entry)[0]:
                    continue
                if args.ndjson or args.json:
                    print(json.dumps(entry.to_dict(), ensure_ascii=False), flush=True)
                    continue
                if entry.date_str and entry.date_str != last_date:
                    last_date = entry.date_str
                    divider = f" ── {entry.date_str} " + "─" * max(12, _term_width() - len(entry.date_str) - 6)
                    print(theme.fg("dim", divider), flush=True)
                for line in format_entry(entry, theme, grep_re=grep_re):
                    print(line, flush=True)
        except KeyboardInterrupt:
            pass
        finally:
            if proc and proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    proc.kill()
        return 0

    service_meta: dict[str, str] = {}
    try:
        source_label, raw_lines, _ = _read_source_lines(args, service_meta)
    except RuntimeError as exc:
        print(f"alis logs: {exc}", file=sys.stderr)
        return 1

    if args.raw:
        for line in raw_lines[-args.lines:]:
            print(line)
        return 0

    all_entries = parse_lines(raw_lines)
    filtered = filter_entries(
        all_entries,
        min_level_rank=min_rank,
        component=args.component,
        category=args.category,
        grep_re=grep_re,
    )
    if args.hide_noise and not args.diagnose:
        filtered = [e for e in filtered if not (e.level in ("WARN", "ERROR", "CRIT") and classify_issue(e)[0])]

    if args.diagnose:
        report = analyze_entries(filtered, source_label=source_label, meta=service_meta)
        if args.json:
            print(json.dumps(report, indent=2, ensure_ascii=False))
        else:
            print(render_diagnose(report, theme))
        if args.fail_on_error and int(report["actionableCount"]) > 0:
            return 1
        return 0

    exit_code = 0
    if args.fail_on_error:
        report_check = analyze_entries(filtered, source_label=source_label, meta=service_meta)
        if int(report_check["actionableCount"]) > 0:
            exit_code = 1

    if not args.no_collapse and not args.summary and not args.json and not args.ndjson:
        filtered = collapse_repeats(filtered)
    window = filtered if args.summary else filtered[-args.lines:]

    if args.json:
        print(json.dumps([e.to_dict() for e in window], indent=2, ensure_ascii=False))
        return exit_code
    if args.ndjson:
        for e in window:
            print(json.dumps(e.to_dict(), ensure_ascii=False))
        return exit_code
    if args.summary:
        print(render_summary(filtered, theme, source_label=source_label))
        return exit_code

    print(render_header(theme, source_label=source_label, entries=window, raw_count=len(all_entries), filters_desc=filters_desc))
    if not window:
        print(" " + theme.fg("muted", "No matching log entries."))
        return exit_code

    last_date = ""
    for entry in window:
        if entry.date_str and entry.date_str != last_date:
            last_date = entry.date_str
            divider = f" ── {entry.date_str} " + "─" * max(12, _term_width() - len(entry.date_str) - 6)
            print(theme.fg("dim", divider))
        for line in format_entry(entry, theme, grep_re=grep_re):
            print(line)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
