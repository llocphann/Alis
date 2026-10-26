#!/usr/bin/env bash
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$here/../.." && pwd)"
mode="${ALIS_ABYSS_POC_MODE:-card-owner}"

if [[ "$mode" != "card-owner" ]]; then
    printf 'G1 acceptance must use ALIS_ABYSS_POC_MODE=card-owner (got %s).\n' "$mode" >&2
    exit 2
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out_dir="${ALIS_ABYSS_POC_CAPTURE_DIR:-$here/captures/g1-$stamp}"

if [[ -e "$out_dir" && ! -d "$out_dir" ]]; then
    printf 'G1 evidence path exists but is not a directory: %s\n' "$out_dir" >&2
    exit 2
fi
if [[ -d "$out_dir" && -n "$(find "$out_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    printf 'G1 evidence directory must be new or empty: %s\n' "$out_dir" >&2
    exit 2
fi
mkdir -p "$out_dir"
out_dir="$(cd -- "$out_dir" && pwd)"

if ! command -v git >/dev/null 2>&1; then
    printf 'G1 provenance requires git.\n' >&2
    exit 127
fi
if ! git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'G1 provenance requires a Git checkout of Alis.\n' >&2
    exit 2
fi

source_scope=(
    "scripts/abyss-corner-poc"
    "scripts/test-abyss-corner-poc-contract.py"
    "sdata/runtime-exclusions.json"
)
if ! git -C "$repo_root" diff --quiet -- "${source_scope[@]}" \
    || ! git -C "$repo_root" diff --cached --quiet -- "${source_scope[@]}"; then
    printf 'G1 source scope has staged or unstaged changes; commit/stash them before capture.\n' >&2
    exit 2
fi
untracked_source="$(git -C "$repo_root" ls-files --others --exclude-standard -- "${source_scope[@]}")"
if [[ -n "$untracked_source" ]]; then
    printf 'G1 source scope has untracked files; remove/commit them before capture:\n%s\n' "$untracked_source" >&2
    exit 2
fi

repo_head="$(git -C "$repo_root" rev-parse HEAD)"
poc_tree_sha="$(git -C "$repo_root" rev-parse 'HEAD:scripts/abyss-corner-poc')"
contract_blob_sha="$(git -C "$repo_root" rev-parse 'HEAD:scripts/test-abyss-corner-poc-contract.py')"
runtime_exclusions_blob_sha="$(git -C "$repo_root" rev-parse 'HEAD:sdata/runtime-exclusions.json')"

printf 'G1 preflight: Abyss corner PoC source contract\n'
python3 "$repo_root/scripts/test-abyss-corner-poc-contract.py"

cat > "$out_dir/g1-run.txt" <<EOF
started_at_utc=$stamp
repo_head=$repo_head
poc_tree_sha=$poc_tree_sha
contract_blob_sha=$contract_blob_sha
runtime_exclusions_blob_sha=$runtime_exclusions_blob_sha
source_scope_clean=true
evidence_dir_was_empty=true
requested_output=${ALIS_ABYSS_POC_OUTPUT:-}
mode=card-owner
profiles=diagnostic,upstream-relative
EOF

for profile in diagnostic upstream-relative; do
    printf '\nG1 capture profile: %s\n' "$profile"
    ALIS_ABYSS_POC_CAPTURE_DIR="$out_dir" \
    ALIS_ABYSS_POC_MODE=card-owner \
    ALIS_ABYSS_POC_PROFILE="$profile" \
        "$here/capture-matrix.sh"
done

printf '\nG1 structural evidence verification\n'
python3 "$here/verify-g1-evidence.py" "$out_dir"

printf '\nG1 evidence directory: %s\n' "$out_dir"
printf 'Review:\n'
printf '  %s\n' "$out_dir/detail-sheet-card-owner-diagnostic.png"
printf '  %s\n' "$out_dir/detail-sheet-card-owner-upstream-relative.png"
printf '  %s\n' "$out_dir/manifest-card-owner-diagnostic.tsv"
printf '  %s\n' "$out_dir/manifest-card-owner-upstream-relative.tsv"
printf '  %s\n' "$out_dir/session-card-owner-diagnostic.json"
printf '  %s\n' "$out_dir/session-card-owner-upstream-relative.json"
