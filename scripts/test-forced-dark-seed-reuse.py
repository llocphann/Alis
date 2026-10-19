#!/usr/bin/env python3
"""Guard the forced-dark pass against re-decoding an unchanged source image."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "scripts/colors/switchwall.sh").read_text()
block = source.split('if [[ "$force_dark_terminal" == "true" ]]; then', 1)[1].split(
    '\n    else\n        rm -f "$_scss_tmp"', 1
)[0]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


require('local theme_generation_succeeded=false' in source
        and 'theme_generation_succeeded=true' in source,
        "cached seed reuse must be gated on a successful primary generation")
require("meta_source=" in block and ".source_path // empty" in block,
        "the cache must be tied to source_path from the successful generation")
require('"$meta_source" == "$source_image_path"' in block
        and '"$cached_seed" =~ ^#?[[:xdigit:]]{6}$' in block,
        "stale or malformed seed metadata must fall back to the original image path")
require('cached_args+=(--color "$cached_seed")' in block
        and 'cached_args+=(--scheme "$cached_scheme")' in block,
        "the second pass must reuse the exact seed and resolved scheme")
require('scss_generate_args=("${generate_colors_material_args[@]}")' in block,
        "the original image-generation command must remain the safe fallback")
print("FORCED_DARK_SEED_REUSE_PASS source-bound seed and resolved scheme reuse with safe fallback")
