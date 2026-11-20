#!/usr/bin/env python3
"""Regression contract for Material-only public documentation."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

assert not (ROOT / "to-do").exists(), "Retired to-do/ directory must remain absent"
assert not (ROOT / "docs").exists(), "Retired docs/ directory must remain absent"

docs = {
    "ARCHITECTURE.md": ROOT / "ARCHITECTURE.md",
    "README.md": ROOT / "README.md",
}

forbidden = {
    "ARCHITECTURE.md": (
        "| Global styles | material, cards, aurora, alis, angel, zzz, cookie |",
        "Style dispatch priority is **cookie > zzz > angel > alis > aurora > material**",
        "six style variants",
        "six supported styles",
    ),
    "README.md": (
        "active material, cards, aurora",
        "six style variants",
        "Style dispatch priority",
        "global ZZZ, Aurora, Angel or Alis chrome",
        "Aurora and Angel styles use frosted glass effects",
        "six supported styles",
    ),
}

for name, path in docs.items():
    text = path.read_text(encoding="utf-8")
    for token in forbidden[name]:
        if token in text:
            raise AssertionError(
                f"{name} still advertises retired Global Theme/runtime behavior: {token!r}"
            )

arch = docs["ARCHITECTURE.md"].read_text(encoding="utf-8")
if "`Appearance.globalStyle` is runtime-clamped to `material`" not in arch:
    raise AssertionError("ARCHITECTURE.md missing Material-only runtime clamp contract")

legacy_sequence = re.compile(
    r"material.{0,16}cards.{0,16}aurora.{0,16}alis.{0,16}angel",
    re.IGNORECASE,
)
for name, path in docs.items():
    if legacy_sequence.search(path.read_text(encoding="utf-8")):
        raise AssertionError(f"{name} still advertises multiple shell-wide Global Themes")

print("Material-only documentation contract: PASS")
