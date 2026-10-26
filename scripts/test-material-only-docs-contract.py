#!/usr/bin/env python3
"""Regression contract for Material-only public documentation."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

docs = {
    "ARCHITECTURE.md": ROOT / "ARCHITECTURE.md",
    "ARCHITECTURE_OVERVIEW.md": ROOT / "docs" / "ARCHITECTURE_OVERVIEW.md",
    "PANEL_FAMILIES.md": ROOT / "docs" / "PANEL_FAMILIES.md",
    "OPTIMIZATION.md": ROOT / "to-do" / "cloud-bot" / "OPTIMIZATION.md",
    "WALLPAPER.md": ROOT / "docs" / "WALLPAPER.md",
    "SHELL_SURFACE_CONTRACTS.md": ROOT / "docs" / "SHELL_SURFACE_CONTRACTS.md",
    "PROJECT_MAP.md": ROOT / "docs" / "PROJECT_MAP.md",
}

forbidden = {
    "ARCHITECTURE.md": (
        "| Global styles | material, cards, aurora, inir, angel, zzz, cookie |",
        "Style dispatch priority is **cookie > zzz > angel > inir > aurora > material**",
    ),
    "ARCHITECTURE_OVERVIEW.md": ("active material, cards, aurora",),
    "PANEL_FAMILIES.md": ("six style variants", "Style dispatch priority"),
    "OPTIMIZATION.md": (
        "each global style's intended material",
        "selected global style",
        "global ZZZ, Aurora, Angel or iNiR chrome",
    ),
    "WALLPAPER.md": ("Aurora and Angel styles use frosted glass effects",),
    "SHELL_SURFACE_CONTRACTS.md": (
        "Global visual themes may still change",
        "If a full `iiPerimeter` composition is tested separately",
    ),
    "PROJECT_MAP.md": ("six supported styles",),
}

for name, path in docs.items():
    text = path.read_text(encoding="utf-8")
    for token in forbidden[name]:
        if token in text:
            raise AssertionError(
                f"{name} still advertises retired Global Theme/runtime behavior: {token!r}"
            )

panel = docs["PANEL_FAMILIES.md"].read_text(encoding="utf-8")
for token in (
    "Material as the only shell-wide Global Theme",
    "`Appearance.globalStyle` is runtime-clamped to `material`",
):
    if token not in panel:
        raise AssertionError(f"PANEL_FAMILIES.md missing Material-only contract: {token!r}")

legacy_sequence = re.compile(
    r"material.{0,16}cards.{0,16}aurora.{0,16}inir.{0,16}angel",
    re.IGNORECASE,
)
for path in sorted((ROOT / "docs" / "readme").glob("README.*.md")):
    text = path.read_text(encoding="utf-8")
    if legacy_sequence.search(text):
        raise AssertionError(
            f"{path.relative_to(ROOT)} still advertises multiple shell-wide Global Themes"
        )

print("Material-only documentation contract: PASS")
