#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/colors/lib/publish-if-changed.sh
source "$repo_root/scripts/colors/lib/publish-if-changed.sh"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

destination="$tmp/generated.json"
printf '%s\n' '{"primary":"#123456"}' > "$destination"
original_identity="$(stat -c '%i:%y' "$destination")"

staged="$tmp/generated.json.tmp"
printf '%s\n' '{"primary":"#123456"}' > "$staged"
publish_if_changed "$staged" "$destination"
[[ ! -e "$staged" ]] || { echo "unchanged staged file was not removed" >&2; exit 1; }
[[ "$(stat -c '%i:%y' "$destination")" == "$original_identity" ]] || {
    echo "unchanged publication replaced or touched the destination" >&2
    exit 1
}

printf '%s\n' '{"primary":"#abcdef"}' > "$staged"
publish_if_changed "$staged" "$destination"
[[ ! -e "$staged" ]] || { echo "changed staged file was not moved" >&2; exit 1; }
grep -Fxq -- '{"primary":"#abcdef"}' "$destination" || {
    echo "changed publication did not update destination" >&2
    exit 1
}

: > "$staged"
if publish_if_changed "$staged" "$destination"; then
    echo "empty staged file should fail publication" >&2
    exit 1
fi
grep -Fxq -- '{"primary":"#abcdef"}' "$destination" || {
    echo "failed publication damaged the previous destination" >&2
    exit 1
}

# Symlink destinations must still be replaced rather than silently preserved.
real_target="$tmp/target"
symlink_destination="$tmp/symlink.json"
printf '%s\n' '{"primary":"#abcdef"}' > "$real_target"
ln -s "$real_target" "$symlink_destination"
printf '%s\n' '{"primary":"#abcdef"}' > "$staged"
publish_if_changed "$staged" "$symlink_destination"
[[ ! -L "$symlink_destination" && -f "$symlink_destination" ]] || {
    echo "symlink destination was not replaced" >&2
    exit 1
}

printf '%s\n' 'THEME_FILE_PUBLICATION_PASS unchanged files preserve identity; changed files publish; empty files fail safely; symlinks are replaced'
