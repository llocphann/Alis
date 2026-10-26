#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/sdata/migrations/061-alis-namespace-alias.sh"
undo="$repo_root/scripts/brand-namespace-rollback.sh"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
export HOME="$root/home"
export XDG_CONFIG_HOME="$root/config"
export XDG_CACHE_HOME="$root/cache"
export XDG_DATA_HOME="$root/data"
export XDG_STATE_HOME="$root/state"
for dir in "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"; do
    mkdir -p "$dir/inir"
    printf 'private-%s\n' "${dir##*/}" > "$dir/inir/user-state"
done
migration_apply || fail 'setup fixture'
bash "$undo" --dry-run >/dev/null || fail 'dry run'
[[ -L "$XDG_CONFIG_HOME/alis" ]] || fail 'dry run removed alias'
mkdir "$XDG_STATE_HOME/foreign"
rm -- "$XDG_STATE_HOME/alis"
ln -s "$XDG_STATE_HOME/foreign" "$XDG_STATE_HOME/alis"
if bash "$undo" --apply >/dev/null 2>&1; then fail 'foreign alias did not stop rollback'; fi
[[ -L "$XDG_CONFIG_HOME/alis" ]] || fail 'rollback failed to preflight all destinations'
[[ -d "$XDG_STATE_HOME/foreign" ]] || fail 'foreign data lost'
rm -- "$XDG_STATE_HOME/alis"
ln -s inir "$XDG_STATE_HOME/alis"
bash "$undo" --apply >/dev/null || fail 'rollback of owned aliases'
for dir in "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"; do
    [[ ! -e "$dir/alis" && ! -L "$dir/alis" ]] || fail "alias remained under $dir"
    [[ "$(cat "$dir/inir/user-state")" == "private-${dir##*/}" ]] || fail "data lost under $dir"
done
bash "$undo" --apply >/dev/null || fail 'idempotent rollback'
printf 'PASS: opt-in namespace alias undo is non-destructive, idempotent and fail-closed\n'
