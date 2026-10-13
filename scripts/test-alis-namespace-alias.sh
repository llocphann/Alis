#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/sdata/migrations/061-alis-namespace-alias.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
case_root="$(mktemp -d)"
trap 'rm -rf -- "$case_root"' EXIT
export HOME="$case_root/home"
export XDG_CONFIG_HOME="$case_root/config"
export XDG_CACHE_HOME="$case_root/cache"
export XDG_DATA_HOME="$case_root/data"
export XDG_STATE_HOME="$case_root/state"
if migration_check; then fail 'fresh install unexpectedly pending'; fi
migration_apply || fail 'empty migration failed'
[[ ! -e "$XDG_CONFIG_HOME" ]] || fail 'fresh check created config directories'
for root in "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"; do
    mkdir -p "$root/inir"
    printf 'keep-%s\n' "${root##*/}" > "$root/inir/secret.bin"
done
migration_check || fail 'existing legacy roots not detected'
migration_apply || fail 'migration failed on valid roots'
for root in "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"; do
    [[ -L "$root/alis" && "$(readlink -- "$root/alis")" == "$root/inir" ]] || fail "bad link at $root"
    [[ "$(cat "$root/alis/secret.bin")" == "keep-${root##*/}" ]] || fail 'original data mutated'
done
if migration_check; then fail 'idempotent migration reports pending'; fi
migration_apply || fail 'idempotent apply failed'
for root in "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"; do rm -- "$root/alis"; done
mkdir "$XDG_STATE_HOME/alis"
printf 'user-data\n' > "$XDG_STATE_HOME/alis/private"
if migration_apply 2>/dev/null; then fail 'accepted conflicting user directory'; fi
for root in "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"; do
    [[ ! -e "$root/alis" && ! -L "$root/alis" ]] || fail 'preflight wrote a partial alias'
done
[[ "$(cat "$XDG_STATE_HOME/alis/private")" == user-data ]] || fail 'foreign directory mutated'
rm -rf -- "$XDG_STATE_HOME/alis"
ln -s foreign-now-missing "$XDG_CACHE_HOME/alis"
if migration_apply 2>/dev/null; then fail 'accepted foreign dangling symlink'; fi
[[ "$(readlink "$XDG_CACHE_HOME/alis")" == foreign-now-missing ]] || fail 'foreign symlink mutated'
rm "$XDG_CACHE_HOME/alis"
ln -s inir "$XDG_CACHE_HOME/alis"
migration_apply || fail 'existing compatible relative link rejected'
[[ "$(readlink "$XDG_CACHE_HOME/alis")" == inir ]] || fail 'existing relative link rewritten'
for root in "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"; do
    [[ "$(cat "$root/inir/secret.bin")" == "keep-${root##*/}" ]] || fail 'source data changed'
done
printf '%s\n' 'PASS: opt-in Alis XDG aliases preserve config, cache, data, state and foreign paths'
