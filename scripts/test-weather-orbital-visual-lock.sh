#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# First keep the semantic renderer/fallback contract green. The exact-content
# lock below is intentionally stricter and protects the maintainer-approved
# Orbital Weather appearance from cleanup/refactor/performance drift.
python3 "$repo_root/scripts/test-weather-liquid-orbital-contract.py"

python3 - "$repo_root" <<'PY'
from __future__ import annotations

import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile


root = Path(sys.argv[1])
approved_on = "2026-10-07"

# VISUAL FREEZE: the maintainer explicitly approved this exact Orbital Weather
# appearance on 2026-09-25. These are Git blob IDs, so even a tiny edit to the
# visual-defining source/QSB fails closed.
#
# The 2026-09-27 maintainer request explicitly redesigns Orbital Weather for
# Abyss. The 2026-09-28 hover defect fix changes only the shared tab motion
# to prevent the detail page painting over the orbit on first layout.
# The 2026-10-07 maintainer request explicitly approves changing the Material
# orbital foreground/accents so the stronger themed light palette uses dark,
# contrast-safe ink instead of pale light-mode text. The same approval covers
# forcing hourly time labels to black in light mode.
# WeatherPopupContent selects the Abyss view; the Material GPU
# membrane and all its visual-defining blobs remain unchanged.
# Do NOT refresh these hashes as part of refactors, cleanup, optimization,
# renderer work, or automated formatting. An intentional visual change requires
# explicit maintainer approval first, then a deliberate re-baseline of this map.
# The maintainer's strict-lossless optimization request permits one frozen
# arithmetic-only patch. Reverse that exact patch and check the ORIGINAL visual
# hash, then require the old/new arithmetic and real QV4 geometry oracle. This
# does not refresh a visual baseline or allow any other source/renderer drift.
# The owner's 2026-10-10 Detailed Weather theme request authorizes only the
# exact detail-palette patch. Reverse it to the ORIGINAL wrapper blob; the
# Orbital page, tab rail, renderer and QSB hashes stay frozen.
expected = {
    "modules/bar/weather/LiquidOrbitalField.qml":
        "1883b6877a02f6013fcacc7e30142e5f522b6165",
    "modules/bar/weather/LiquidOrbitalField.frag":
        "b14385e93e3690e18bfe10cbf123dc8525591b4e",
    "modules/bar/weather/LiquidOrbitalField.frag.qsb":
        "586f42291e050d432406e1ce9f1235ee63b91d34",
    "modules/bar/weather/OrbitalWeather.qml":
        "1a341d0102095971212f06903365cf572b7bad6b",
    "modules/bar/weather/WeatherPopupContent.qml":
        "d0342726a1b6337f7495d1099a1e7a4a38c21ca3",
    "modules/bar/weather/WeatherPopup.qml":
        "5c6e11509eaa5ad3eafdc755fcc7e593ba82e83e",
}


def git_blob_id(payload: bytes) -> str:
    header = f"blob {len(payload)}\0".encode("ascii")
    return hashlib.sha1(header + payload).hexdigest()


def approved_visual_after_exact_cache_patch(payload: bytes, approved_blob: str) -> bool:
    patch = (root / "scripts/fixtures/weather-orbit-exact-table-cache.patch").read_bytes()
    if hashlib.sha256(patch).hexdigest() != "26a2053ea5aa13519be94cf2e71082e572f5bd76231303b604c75e4cb84ccaea":
        return False
    with tempfile.TemporaryDirectory(prefix="hadalis-weather-visual-lock-") as name:
        private = Path(name)
        original = private / "modules/bar/weather/OrbitalWeather.qml"
        original.parent.mkdir(parents=True)
        original.write_bytes(payload)
        result = subprocess.run(["git", "apply", "--reverse", "-"], input=patch,
                                cwd=private, capture_output=True)
        return result.returncode == 0 and git_blob_id(original.read_bytes()) == approved_blob


def approved_visual_after_exact_detail_patch(payload: bytes, approved_blob: str) -> bool:
    patch = (root / "scripts/fixtures/weather-detail-theme.patch").read_bytes()
    if hashlib.sha256(patch).hexdigest() != "a214d0a52727066bffe8745e1f25aafcb129badb8a1274c2b7830e50d150503b":
        return False
    with tempfile.TemporaryDirectory(prefix="alis-weather-detail-lock-") as name:
        private = Path(name)
        original = private / "modules/bar/weather/WeatherPopupContent.qml"
        original.parent.mkdir(parents=True)
        original.write_bytes(payload)
        result = subprocess.run(["git", "apply", "--reverse", "-"], input=patch,
                                cwd=private, capture_output=True)
        return result.returncode == 0 and git_blob_id(original.read_bytes()) == approved_blob


drift = []
exact_cache_patch = False
for relative, approved_blob in expected.items():
    path = root / relative
    if not path.is_file():
        drift.append((relative, approved_blob, "<missing>"))
        continue
    payload = path.read_bytes()
    actual_blob = git_blob_id(payload)
    if actual_blob != approved_blob:
        if relative == "modules/bar/weather/OrbitalWeather.qml" and approved_visual_after_exact_cache_patch(payload, approved_blob):
            exact_cache_patch = True
            continue
        if relative == "modules/bar/weather/WeatherPopupContent.qml" and approved_visual_after_exact_detail_patch(payload, approved_blob):
            continue
        drift.append((relative, approved_blob, actual_blob))

if drift:
    print(
        f"Orbital Weather visual lock FAILED (approved {approved_on}).",
        file=sys.stderr,
    )
    for relative, approved_blob, actual_blob in drift:
        print(
            f"  {relative}: approved={approved_blob} current={actual_blob}",
            file=sys.stderr,
        )
    print(
        "This visual is frozen. Do not update the baseline for unrelated work. "
        "Only re-baseline after explicit maintainer approval of the new visual.",
        file=sys.stderr,
    )
    raise SystemExit(1)

if exact_cache_patch:
    subprocess.run([sys.executable, str(root / "scripts/test-weather-orbit-table-parity.py")], check=True)

print(f"Orbital Weather visual lock: PASS (original approved {approved_on} hashes preserved)")
PY
