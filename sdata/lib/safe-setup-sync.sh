#!/usr/bin/env bash
# Install one trusted, syntax-checked setup script without ever exposing a
# half-written copy at ~/.config/quickshell/alis/setup.
set -euo pipefail

if [[ $# != 2 ]]; then
    printf 'Usage: safe-setup-sync.sh SOURCE_SETUP DESTINATION_SETUP\n' >&2
    exit 2
fi
source_file="$1"
target_file="$2"
if [[ ! -f "$source_file" ]]; then
    printf 'safe-setup-sync: source missing: %s\n' "$source_file" >&2
    exit 1
fi
if ! bash -n "$source_file"; then
    printf 'safe-setup-sync: invalid source syntax; target not modified: %s\n' "$source_file" >&2
    exit 1
fi

# A repo-linked runtime may already reference exactly this file; do not
# overwrite its own source, even through a symlinked runtime directory.
if [[ -e "$target_file" && "$(readlink -f -- "$source_file")" == "$(readlink -f -- "$target_file")" ]]; then
    exit 0
fi

# Never follow or replace a foreign individual setup symlink. The directory
# itself may be a deliberate repo-link (handled by the equality check above).
if [[ -L "$target_file" || ( -e "$target_file" && ! -f "$target_file" ) ]]; then
    printf 'safe-setup-sync: refusing non-regular/symlink target: %s\n' "$target_file" >&2
    exit 1
fi

target_dir="$(dirname -- "$target_file")"
mkdir -p -- "$target_dir"
staged="$(mktemp "$target_dir/.setup-sync.XXXXXXXX")"
trap 'rm -f -- "$staged"' EXIT
install -m 755 -- "$source_file" "$staged"
if ! bash -n "$staged"; then
    printf 'safe-setup-sync: staged script invalid; original setup preserved\n' >&2
    exit 1
fi
# rename() on one filesystem replaces the directory entry atomically.
mv -f -- "$staged" "$target_file"
bash -n "$target_file"
