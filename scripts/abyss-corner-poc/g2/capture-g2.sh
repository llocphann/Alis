#!/usr/bin/env bash
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$here/../../.." && pwd)"
output="${ALIS_ABYSS_G2_OUTPUT:-}"
warmup="${ALIS_ABYSS_G2_CAPTURE_WARMUP:-0.25}"

if [[ -z "${WAYLAND_DISPLAY:-}" || -z "${XDG_RUNTIME_DIR:-}" ]]; then
    printf 'capture-g2.sh requires an existing Wayland session.\n' >&2
    exit 2
fi
for cmd in grim python3 git; do
    command -v "$cmd" >/dev/null 2>&1 || {
        printf 'Missing required command: %s\n' "$cmd" >&2
        exit 127
    }
done

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

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out_dir="${ALIS_ABYSS_G2_CAPTURE_DIR:-$here/captures/g2-$stamp}"
if [[ -e "$out_dir" && ! -d "$out_dir" ]]; then
    printf 'G2 evidence path exists but is not a directory: %s\n' "$out_dir" >&2
    exit 2
fi
if [[ -d "$out_dir" && -n "$(find "$out_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    printf 'G2 evidence directory must be new or empty: %s\n' "$out_dir" >&2
    exit 2
fi
mkdir -p "$out_dir"
out_dir="$(cd -- "$out_dir" && pwd)"

scope=(
    "scripts/abyss-corner-poc/g2"
    "scripts/abyss-corner-poc/AbyssField.frag"
    "scripts/abyss-corner-poc/g2/AbyssField.frag.qsb"
    "scripts/test-abyss-g2-contract.py"
)
if ! git -C "$repo_root" diff --quiet -- "${scope[@]}" \
    || ! git -C "$repo_root" diff --cached --quiet -- "${scope[@]}"; then
    printf 'G2 source scope has staged or unstaged changes.\n' >&2
    exit 2
fi
untracked="$(git -C "$repo_root" ls-files --others --exclude-standard -- "${scope[@]}")"
if [[ -n "$untracked" ]]; then
    printf 'G2 source scope has untracked files:\n%s\n' "$untracked" >&2
    exit 2
fi

printf 'G2 preflight: split-composition source contract\n'
python3 "$repo_root/scripts/test-abyss-g2-contract.py"

repo_head="$(git -C "$repo_root" rev-parse HEAD)"
g2_tree_sha="$(git -C "$repo_root" rev-parse 'HEAD:scripts/abyss-corner-poc/g2')"
shader_blob_sha="$(git -C "$repo_root" rev-parse 'HEAD:scripts/abyss-corner-poc/AbyssField.frag')"
qsb_blob_sha="$(git -C "$repo_root" rev-parse 'HEAD:scripts/abyss-corner-poc/g2/AbyssField.frag.qsb')"
contract_blob_sha="$(git -C "$repo_root" rev-parse 'HEAD:scripts/test-abyss-g2-contract.py')"

cat > "$out_dir/g2-run.txt" <<EOF
started_at_utc=$stamp
repo_head=$repo_head
g2_tree_sha=$g2_tree_sha
shader_blob_sha=$shader_blob_sha
qsb_blob_sha=$qsb_blob_sha
contract_blob_sha=$contract_blob_sha
requested_output=$output
progresses=1.00,0.55
source_scope_clean=true
evidence_dir_was_empty=true
EOF

session="$out_dir/session.json"
python3 - "$session" "$output" "$warmup" "$qs_bin" "$(command -v grim)" <<'PY'
import datetime
import json
import os
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
payload = {
    "capturedAtUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "requestedOutput": sys.argv[2],
    "warmupSeconds": float(sys.argv[3]),
    "quickshellExecutable": sys.argv[4],
    "grimExecutable": sys.argv[5],
    "waylandDisplay": os.environ.get("WAYLAND_DISPLAY", ""),
    "detailCropCoordinates": "compositor-layout-logical",
    "devicePixelRatioAppliedToCrop": False,
    "composition": "top-owner/overlay-popup",
}
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

manifest="$out_dir/manifest.tsv"
printf 'edge\tsource_t\tprogress\tpng\tdetail_png\tmetadata_json\tlog\n' > "$manifest"

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
    local progress="$3"
    local safe_t="${source_t/./p}"
    local safe_p="${progress/./p}"
    local stem="${edge}-${safe_t}-p${safe_p}"
    local png="$out_dir/$stem.png"
    local detail="$out_dir/$stem-detail.png"
    local metadata="$out_dir/$stem.json"
    local log="$out_dir/$stem.log"

    printf 'capture %-6s source=%s progress=%s\n' "$edge" "$source_t" "$progress"

    ALIS_ABYSS_G2_EDGE="$edge" \
    ALIS_ABYSS_G2_SOURCE_T="$source_t" \
    ALIS_ABYSS_G2_PROGRESS="$progress" \
    ALIS_ABYSS_G2_OUTPUT="$output" \
    ALIS_ABYSS_G2_GUIDES=1 \
        "$qs_bin" -n -p "$here" >"$log" 2>&1 &
    current_pid=$!

    local ready=0
    for _ in $(seq 1 120); do
        if grep -Fq 'ALIS_ABYSS_G2' "$log" 2>/dev/null; then
            ready=1
            break
        fi
        if ! kill -0 "$current_pid" 2>/dev/null; then
            printf 'G2 PoC exited before readiness for %s/%s/%s.\n' "$edge" "$source_t" "$progress" >&2
            cat "$log" >&2 || true
            return 1
        fi
        sleep 0.05
    done
    if [[ "$ready" -ne 1 ]]; then
        printf 'Timed out waiting for G2 readiness for %s/%s/%s.\n' "$edge" "$source_t" "$progress" >&2
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
out = pathlib.Path(sys.argv[2])
payload = None
for line in reversed(log_path.read_text(encoding="utf-8", errors="replace").splitlines()):
    if "ALIS_ABYSS_G2" not in line:
        continue
    match = re.search(r"(\{.*\})", line.split("ALIS_ABYSS_G2", 1)[1])
    if match:
        payload = json.loads(match.group(1))
        break
if payload is None:
    raise SystemExit(f"no parseable ALIS_ABYSS_G2 JSON in {log_path}")
out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

    local capture_output
    capture_output="$(python3 - "$metadata" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["output"])
PY
)"
    [[ -n "$capture_output" ]] || {
        printf 'G2 PoC reported an empty output.\n' >&2
        return 1
    }
    if [[ -n "$output" && "$capture_output" != "$output" ]]; then
        printf 'G2 output mismatch: requested %s, rendered %s.\n' "$output" "$capture_output" >&2
        return 1
    fi

    grim -o "$capture_output" "$png"

    local detail_geometry
    detail_geometry="$(python3 - "$metadata" <<'PY'
import json
import math
import sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
edge = d["edge"]
out_x, out_y = float(d["outputX"]), float(d["outputY"])
W, H = float(d["outputWidth"]), float(d["outputHeight"])
px, py = float(d["popupX"]), float(d["popupY"])
pw, ph = float(d["popupWidth"]), float(d["popupHeight"])
seam = float(d["attachmentBoundary"])
fuse = float(d["fuse"])
owner = float(d["ownerThickness"])
margin = fuse + 24.0
cross = max(150.0, owner + fuse * 3.0)

if edge in ("top", "bottom"):
    left = max(0.0, px - margin)
    right = min(W, px + pw + margin)
    if edge == "top":
        top, bottom = 0.0, min(H, seam + cross)
    else:
        top, bottom = max(0.0, seam - cross), H
else:
    top = max(0.0, py - margin)
    bottom = min(H, py + ph + margin)
    if edge == "left":
        left, right = 0.0, min(W, seam + cross)
    else:
        left, right = max(0.0, seam - cross), W

x = math.floor(out_x + left)
y = math.floor(out_y + top)
w = max(1, math.ceil(right) - math.floor(left))
h = max(1, math.ceil(bottom) - math.floor(top))
print(f"{x},{y} {w}x{h}")
PY
)"
    grim -g "$detail_geometry" "$detail"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$edge" "$source_t" "$progress" "$png" "$detail" "$metadata" "$log" >> "$manifest"

    cleanup
}

for progress in 1.00 0.55; do
    for edge in top bottom left right; do
        for source_t in 0.02 0.50 0.98; do
            capture_case "$edge" "$source_t" "$progress"
        done
    done
done

for progress in 1p00 0p55; do
    sheet="$out_dir/detail-sheet-progress-$progress.png"
    images=()
    for edge in top bottom left right; do
        for source_t in 0p02 0p50 0p98; do
            images+=("$out_dir/${edge}-${source_t}-p${progress}-detail.png")
        done
    done
    if command -v magick >/dev/null 2>&1; then
        magick montage "${images[@]}" -tile 3x4 -geometry '640x320+8+8' "$sheet"
        printf 'detail sheet: %s\n' "$sheet"
    elif command -v montage >/dev/null 2>&1; then
        montage "${images[@]}" -tile 3x4 -geometry '640x320+8+8' "$sheet"
        printf 'detail sheet: %s\n' "$sheet"
    fi
done

printf '\nG2 structural evidence verification\n'
python3 "$here/verify-g2-evidence.py" "$out_dir"

printf '\nG2 evidence directory: %s\n' "$out_dir"
printf 'Review:\n'
printf '  %s\n' "$out_dir/detail-sheet-progress-1p00.png"
printf '  %s\n' "$out_dir/detail-sheet-progress-0p55.png"
printf '  %s\n' "$manifest"
printf '  %s\n' "$session"
