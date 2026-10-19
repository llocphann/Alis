#!/usr/bin/env python3
"""THEME-PERF-10: ordered app palette batch must equal legacy per-field jq reads.

Only parses disposable JSON fixtures; does not touch ~/.config or applications.
"""
from __future__ import annotations

import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/colors/apply-gtk-theme.sh"
BATCH = ROOT / "scripts/colors/lib/app-palette-fields.jq"
SOURCE = SCRIPT.read_text()
FIELDS = [
    [
        "BG",
        ".app_background // .background // empty"
    ],
    [
        "FG",
        ".app_foreground // .on_background // empty"
    ],
    [
        "PRIMARY",
        ".app_accent // .primary // empty"
    ],
    [
        "ON_PRIMARY",
        ".app_on_accent // .on_primary // empty"
    ],
    [
        "PRIMARY_CONTAINER",
        ".primary_container // empty"
    ],
    [
        "ON_PRIMARY_CONTAINER",
        ".on_primary_container // empty"
    ],
    [
        "SURFACE",
        ".app_view_bg // .surface // empty"
    ],
    [
        "ON_SURFACE",
        ".app_foreground // .on_surface // empty"
    ],
    [
        "SURFACE_CONTAINER",
        ".app_surface_elevated // .surface_container // empty"
    ],
    [
        "SURFACE_CONTAINER_HIGH",
        ".app_surface_popup // .surface_container_high // empty"
    ],
    [
        "SURFACE_CONTAINER_LOW",
        ".app_surface // .surface_container_low // empty"
    ],
    [
        "SURFACE_DIM",
        ".app_window_bg // .surface_dim // empty"
    ],
    [
        "OUTLINE_VARIANT",
        ".app_border_subtle // .outline_variant // empty"
    ],
    [
        "SURFACE_CONTAINER_HIGHEST",
        ".app_thumbnail_bg // .surface_container_highest // empty"
    ],
    [
        "APP_HEADERBAR_BG",
        ".app_headerbar_bg // empty"
    ],
    [
        "APP_SIDEBAR_BG",
        ".app_sidebar_bg // empty"
    ],
    [
        "APP_CARD_BG",
        ".app_card_bg // empty"
    ],
    [
        "APP_POPOVER_BG",
        ".app_popover_bg // empty"
    ],
    [
        "APP_DIALOG_BG",
        ".app_dialog_bg // empty"
    ],
    [
        "APP_SELECTION",
        ".app_selection // empty"
    ],
    [
        "APP_SELECTION_HOVER",
        ".app_selection_hover // empty"
    ],
    [
        "APP_ON_SELECTION",
        ".app_on_selection // empty"
    ],
    [
        "APP_SUCCESS",
        ".app_success // empty"
    ],
    [
        "APP_WARNING",
        ".app_warning // empty"
    ],
    [
        "APP_ERROR",
        ".app_error // empty"
    ],
    [
        "ERROR_COLOR",
        ".error // empty"
    ],
    [
        "TERTIARY",
        ".tertiary // empty"
    ],
    [
        "SECONDARY",
        ".secondary // empty"
    ],
    [
        "SECONDARY_CONTAINER",
        ".secondary_container // empty"
    ]
]

assert "mapfile -t COLOR_VALUES" in SOURCE
assert 'jq -r -f "$SCRIPT_DIR/lib/app-palette-fields.jq"' in SOURCE
assert SOURCE.count("COLOR_VALUES[") == len(FIELDS), "Fields must only map once"

check = subprocess.run(["bash", "-n", str(SCRIPT)], capture_output=True, text=True)
assert check.returncode == 0, check.stderr

# Explicitly test preferred app_* contract, legacy Material fallbacks, nulls,
# and populated trailing field. Do not require the user palette to exist.
fixtures = [
    {},
    {"background": "#010203", "on_background": "#111111",
     "primary": "#334455", "on_primary": "#ffffff",
     "surface": "#454545", "on_surface": "#aaaaaa",
     "surface_container": "#454647", "secondary_container": "#123456"},
    {"app_background": "#112233", "background": "#ffff00",
     "app_foreground": "#445566", "on_background": "#abcdef",
     "app_accent": "#778899", "primary": "#000000",
     "app_view_bg": "#010101", "surface": "#222222",
     "app_selection": "#aa4422", "app_on_selection": "#eeeeee",
     "app_success": "#00ff00", "app_warning": "#ffbb00",
     "app_error": "#cc0011", "secondary_container": "#aabbcc"},
    {"app_background": "", "app_foreground": None, "on_background": "#eeeeee",
     "app_card_bg": "", "error": None, "secondary": "#123abc"},
]
with tempfile.TemporaryDirectory(prefix="alis-theme-palette-batch-") as td:
    palette = Path(td) / "palette.json"
    for case in fixtures:
        palette.write_text(json.dumps(case))
        batched = subprocess.run(
            ["jq", "-r", "-f", str(BATCH), str(palette)],
            capture_output=True, text=True, check=True,
        ).stdout.splitlines()
        if len(batched) != len(FIELDS):
            raise AssertionError(f"Batch length {len(batched)} != {len(FIELDS)}")
        expected = []
        for name, expression in FIELDS:
            actual = subprocess.run(
                ["jq", "-r", expression, str(palette)],
                capture_output=True, text=True, check=True,
            ).stdout.rstrip("\n")
            expected.append(actual)
        assert batched == expected, (case, list(zip(FIELDS, batched, expected)))
        for index, (name, _) in enumerate(FIELDS):
            mapping = f'{name}="${{COLOR_VALUES[{index}]:-}}"'
            assert mapping in SOURCE, f"Missing field index {index} for {name}"

print("THEME_PERF_10_PASS 29 jq fields equivalent across 4 fixtures; shell syntax valid")
