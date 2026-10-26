#!/usr/bin/env bash
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
out_dir="${ALIS_ABYSS_POC_CAPTURE_DIR:-$here/captures}"
warmup="${ALIS_ABYSS_POC_CAPTURE_WARMUP:-0.35}"
mode="${ALIS_ABYSS_POC_MODE:-card-owner}"
profile="${ALIS_ABYSS_POC_PROFILE:-diagnostic}"
output="${ALIS_ABYSS_POC_OUTPUT:-}"

case "$mode" in
    card-owner|edge-reach) ;;
    *)
        printf 'Invalid ALIS_ABYSS_POC_MODE=%s (expected card-owner or edge-reach).\n' "$mode" >&2
        exit 2
        ;;
esac
case "$profile" in
    diagnostic|upstream-relative) ;;
    *)
        printf 'Invalid ALIS_ABYSS_POC_PROFILE=%s (expected diagnostic or upstream-relative).\n' "$profile" >&2
        exit 2
        ;;
esac

if [[ -z "${WAYLAND_DISPLAY:-}" || -z "${XDG_RUNTIME_DIR:-}" ]]; then
    printf 'capture-matrix.sh requires an existing Wayland session.\n' >&2
    exit 2
fi
if ! command -v grim >/dev/null 2>&1; then
    printf 'Missing grim; install it before capturing the visual matrix.\n' >&2
    exit 127
fi
if ! command -v python3 >/dev/null 2>&1; then
    printf 'Missing python3; it is required to preserve capture geometry metadata.\n' >&2
    exit 127
fi

if [[ -n "${QS:-}" ]]; then
    qs_bin="$QS"
elif command -v qs >/dev/null 2>&1; then
    qs_bin="$(command -v qs)"
elif command -v quickshell >/dev/null 2>&1; then
    qs_bin="$(command -v quickshell)"
else
    printf 'Missing Quickshell executable (qs/quickshell).\n' >&2
    exit 127
fi

mkdir -p "$out_dir"
out_dir="$(cd -- "$out_dir" && pwd)"
manifest="$out_dir/manifest-${mode}-${profile}.tsv"
session_metadata="$out_dir/session-${mode}-${profile}.json"
printf 'edge\tsource_t\tmode\tprofile\tpng\tdetail_png\tmetadata_json\tlog\n' > "$manifest"

python3 - "$session_metadata" "$mode" "$profile" "$output" "$warmup" "$qs_bin" "$(command -v grim)" <<'PY'
import datetime
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
mode, profile, requested_output, warmup, qs_bin, grim_bin = sys.argv[2:]
payload = {
    "capturedAtUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "mode": mode,
    "profile": profile,
    "requestedOutput": requested_output,
    "warmupSeconds": float(warmup),
    "quickshellExecutable": qs_bin,
    "grimExecutable": grim_bin,
    "waylandDisplay": __import__("os").environ.get("WAYLAND_DISPLAY", ""),
    "detailCropCoordinates": "compositor-layout-logical",
    "devicePixelRatioAppliedToCrop": False,
}
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

current_pid=""
cleanup() {
    if [[ -n "$current_pid" ]] && kill -0 "$current_pid" 2>/dev/null; then
        kill "$current_pid" 2>/dev/null || true
        wait "$current_pid" 2>/dev/null || true
    fi
    current_pid=""
}
trap cleanup EXIT INT TERM

capture_case() {
    local edge="$1"
    local source_t="$2"
    local safe_t="${source_t/./p}"
    local stem="${edge}-${safe_t}-${mode}-${profile}"
    local png="$out_dir/$stem.png"
    local detail="$out_dir/$stem-detail.png"
    local metadata="$out_dir/$stem.json"
    local log="$out_dir/$stem.log"

    printf 'capture %-6s source=%s mode=%s profile=%s\n' "$edge" "$source_t" "$mode" "$profile"

    ALIS_ABYSS_POC_EDGE="$edge" \
    ALIS_ABYSS_POC_SOURCE_T="$source_t" \
    ALIS_ABYSS_POC_MODE="$mode" \
    ALIS_ABYSS_POC_PROFILE="$profile" \
    ALIS_ABYSS_POC_OUTPUT="$output" \
    ALIS_ABYSS_POC_GUIDES=1 \
        "$qs_bin" -n -p "$here" >"$log" 2>&1 &
    current_pid=$!

    local ready=0
    for _ in $(seq 1 80); do
        if grep -Fq 'ALIS_ABYSS_POC' "$log" 2>/dev/null; then
            ready=1
            break
        fi
        if ! kill -0 "$current_pid" 2>/dev/null; then
            printf 'PoC exited before readiness marker for %s/%s.\n' "$edge" "$source_t" >&2
            cat "$log" >&2 || true
            return 1
        fi
        sleep 0.05
    done
    if [[ "$ready" -ne 1 ]]; then
        printf 'Timed out waiting for PoC readiness marker for %s/%s.\n' "$edge" "$source_t" >&2
        cat "$log" >&2 || true
        return 1
    fi

    sleep "$warmup"

    python3 - "$log" "$metadata" <<'PY'
import json
import pathlib
import re
import sys

log_path = pathlib.Path(sys.argv[1])
metadata_path = pathlib.Path(sys.argv[2])
marker = "ALIS_ABYSS_POC"
payload = None
for line in reversed(log_path.read_text(encoding="utf-8", errors="replace").splitlines()):
    if marker not in line:
        continue
    tail = line.split(marker, 1)[1]
    match = re.search(r"(\{.*\})", tail)
    if match:
        payload = json.loads(match.group(1))
        break
if payload is None:
    raise SystemExit(f"no parseable {marker} JSON in {log_path}")
metadata_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

    local capture_output
    capture_output="$(python3 - "$metadata" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle)["output"])
PY
)"
    if [[ -z "$capture_output" ]]; then
        printf 'PoC did not report an output for %s/%s.\n' "$edge" "$source_t" >&2
        return 1
    fi
    if [[ -n "$output" && "$capture_output" != "$output" ]]; then
        printf 'PoC output mismatch: requested %s, rendered %s.\n' "$output" "$capture_output" >&2
        return 1
    fi

    # Full-output context capture.
    grim -o "$capture_output" "$png"

    # Focused contact crop. grim -g consumes compositor layout coordinates, so
    # add ShellScreen.x/y to the output-local semantic popup geometry. Keep the
    # crop scale-independent; grim itself chooses the capture pixel scale.
    local detail_geometry
    detail_geometry="$(python3 - "$metadata" <<'PY'
import json
import math
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    d = json.load(handle)

edge = d["edge"]
out_x = float(d["outputX"])
out_y = float(d["outputY"])
out_w = float(d["outputWidth"])
out_h = float(d["outputHeight"])
popup_x = float(d["popupX"])
popup_y = float(d["popupY"])
popup_w = float(d["popupWidth"])
popup_h = float(d["popupHeight"])
owner = float(d["ownerThickness"])
fuse = float(d["fuse"])

tangent_margin = max(32.0, fuse * 1.5)
cross_span = max(96.0, fuse * 3.2)

if edge in ("top", "bottom"):
    x = popup_x - tangent_margin
    width = popup_w + 2.0 * tangent_margin
    seam = owner if edge == "top" else out_h - owner
    y = seam - cross_span / 2.0
    height = cross_span
else:
    y = popup_y - tangent_margin
    height = popup_h + 2.0 * tangent_margin
    seam = owner if edge == "left" else out_w - owner
    x = seam - cross_span / 2.0
    width = cross_span

left = max(0, math.floor(x))
top = max(0, math.floor(y))
right = min(math.ceil(out_w), math.ceil(x + width))
bottom = min(math.ceil(out_h), math.ceil(y + height))
if right <= left or bottom <= top:
    raise SystemExit(f"invalid detail crop for {edge}: {(left, top, right, bottom)}")

print(f"{math.floor(out_x + left)},{math.floor(out_y + top)} "
      f"{right - left}x{bottom - top}")
PY
)"
    grim -g "$detail_geometry" "$detail"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$edge" "$source_t" "$mode" "$profile" \
        "$png" "$detail" "$metadata" "$log" >> "$manifest"

    cleanup
}

for edge in top bottom left right; do
    for source_t in 0.02 0.50 0.98; do
        capture_case "$edge" "$source_t"
    done
done

contact="$out_dir/contact-sheet-${mode}-${profile}.png"
detail_contact="$out_dir/detail-sheet-${mode}-${profile}.png"
images=(
    "$out_dir/top-0p02-${mode}-${profile}.png"
    "$out_dir/top-0p50-${mode}-${profile}.png"
    "$out_dir/top-0p98-${mode}-${profile}.png"
    "$out_dir/bottom-0p02-${mode}-${profile}.png"
    "$out_dir/bottom-0p50-${mode}-${profile}.png"
    "$out_dir/bottom-0p98-${mode}-${profile}.png"
    "$out_dir/left-0p02-${mode}-${profile}.png"
    "$out_dir/left-0p50-${mode}-${profile}.png"
    "$out_dir/left-0p98-${mode}-${profile}.png"
    "$out_dir/right-0p02-${mode}-${profile}.png"
    "$out_dir/right-0p50-${mode}-${profile}.png"
    "$out_dir/right-0p98-${mode}-${profile}.png"
)

detail_images=(
    "$out_dir/top-0p02-${mode}-${profile}-detail.png"
    "$out_dir/top-0p50-${mode}-${profile}-detail.png"
    "$out_dir/top-0p98-${mode}-${profile}-detail.png"
    "$out_dir/bottom-0p02-${mode}-${profile}-detail.png"
    "$out_dir/bottom-0p50-${mode}-${profile}-detail.png"
    "$out_dir/bottom-0p98-${mode}-${profile}-detail.png"
    "$out_dir/left-0p02-${mode}-${profile}-detail.png"
    "$out_dir/left-0p50-${mode}-${profile}-detail.png"
    "$out_dir/left-0p98-${mode}-${profile}-detail.png"
    "$out_dir/right-0p02-${mode}-${profile}-detail.png"
    "$out_dir/right-0p50-${mode}-${profile}-detail.png"
    "$out_dir/right-0p98-${mode}-${profile}-detail.png"
)

if command -v magick >/dev/null 2>&1; then
    magick montage "${images[@]}" -tile 3x4 -geometry '640x360+8+8' "$contact"
    magick montage "${detail_images[@]}" -tile 3x4 -geometry '560x300+8+8' "$detail_contact"
    printf 'contact sheet: %s\n' "$contact"
    printf 'detail sheet:  %s\n' "$detail_contact"
elif command -v montage >/dev/null 2>&1; then
    montage "${images[@]}" -tile 3x4 -geometry '640x360+8+8' "$contact"
    montage "${detail_images[@]}" -tile 3x4 -geometry '560x300+8+8' "$detail_contact"
    printf 'contact sheet: %s\n' "$contact"
    printf 'detail sheet:  %s\n' "$detail_contact"
else
    printf 'ImageMagick not found; full and focused captures are available in %s\n' "$out_dir"
fi

printf 'manifest: %s\n' "$manifest"
printf 'session:  %s\n' "$session_metadata"
