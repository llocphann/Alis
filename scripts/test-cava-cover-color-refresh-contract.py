#!/usr/bin/env python3
"""Guard against extracting the same CAVA cover palette twice per theme apply."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "scripts/colors/modules/90-cava.sh").read_text()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


cover_builder = source.split("build_gradient_cover() {", 1)[1].split("\n}", 1)[0]
generator = source.split("generate_managed_block() {", 1)[1].split("\n}", 1)[0]
require('refresh_cover_colors "$count" || true' in cover_builder,
        "cover gradient must still refresh colors before reading the cover palette")
require('refresh_cover_colors "$gradient_count"' not in generator,
        "generate_managed_block must not extract cover colors before build_gradient_cover extracts them")
require('cover)   while IFS= read -r c; do gradient+=("$c"); done < <(build_gradient_cover "$gradient_count")' in generator,
        "cover source must continue to use build_gradient_cover")
print("CAVA_COVER_REFRESH_PASS exactly one cover extraction per cover-source generation")
