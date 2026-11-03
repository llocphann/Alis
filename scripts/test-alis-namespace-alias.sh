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
    mkdir -p "$root/alis"
    printf 'keep-%s\n' "${root##*/}" > "$root/alis/secret.bin"
done
migration_check || fail 'existing legacy roots not detected'
migration_apply || fail 'migration failed on valid roots'
for root in "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"; do
    [[ -L "$root/alis" && "$(readlink -- "$root/alis")" == "$root/alis" ]] || fail "bad link at $root"
    [[ "$(cat "$root/alis/secret.bin")" == "keep-${root##*/}" ]] || fail 'original data mutated'
done
if migration_check; then fail 'idempotent migration reports pending'; fi
migration_apply || fail 'idempotent apply failed'
for root in "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"; do rm -- "$root/alis"; done
mkdir "$XDG_STATE_HOME/alis"
printf 'user-data\n' > "$XDG_STATE_HOME/alis/private"
migration_apply 2>"$case_root/collision.log" || fail 'existing user-owned path must be skipped without abort'
grep -Fq 'SKIP existing user-owned path' "$case_root/collision.log" || fail 'collision skip not explained'
for root in "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"; do
    [[ -L "$root/alis" && "$(readlink -- "$root/alis")" == "$root/alis" ]] || fail 'safe independent alias not created'
done
[[ "$(cat "$XDG_STATE_HOME/alis/private")" == user-data ]] || fail 'foreign directory mutated'
if migration_check; then fail 'completed partial aliases should not remain pending'; fi
for root in "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"; do rm -- "$root/alis"; done
rm -rf -- "$XDG_STATE_HOME/alis"
ln -s foreign-now-missing "$XDG_CACHE_HOME/alis"
migration_apply 2>"$case_root/dangling.log" || fail 'foreign dangling symlink must be skipped safely'
grep -Fq 'SKIP existing user-owned path' "$case_root/dangling.log" || fail 'dangling symlink collision not logged'
[[ "$(readlink "$XDG_CACHE_HOME/alis")" == foreign-now-missing ]] || fail 'foreign symlink mutated'
for root in "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"; do
    [[ -L "$root/alis" ]] || fail 'safe aliases were not created with foreign symlink'
    rm -- "$root/alis"
done
rm "$XDG_CACHE_HOME/alis"
ln -s alis "$XDG_CACHE_HOME/alis"
migration_apply || fail 'existing compatible relative link rejected'
[[ "$(readlink "$XDG_CACHE_HOME/alis")" == alis ]] || fail 'existing relative link rewritten'
for root in "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"; do
    [[ "$(cat "$root/alis/secret.bin")" == "keep-${root##*/}" ]] || fail 'source data changed'
done
# Real-world collision: an unrelated app owns ~/.cache/alis.
for root in "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"; do rm -- "$root/alis"; done
rm -- "$XDG_CACHE_HOME/alis"
mkdir "$XDG_CACHE_HOME/alis"
printf 'unrelated-cache-sentinel\n' > "$XDG_CACHE_HOME/alis/keep"
migration_preview > "$case_root/preview.txt"
grep -Fq 'SKIP' "$case_root/preview.txt" || fail 'preview hid foreign Alis cache'
migration_apply 2>"$case_root/cache.log" || fail 'safe aliases cannot be blocked by foreign cache'
grep -Fq 'SKIP existing user-owned path' "$case_root/cache.log" || fail 'foreign cache skip not logged'
[[ "$(cat "$XDG_CACHE_HOME/alis/keep")" == unrelated-cache-sentinel ]] || fail 'foreign cache bytes changed'
[[ -d "$XDG_CACHE_HOME/alis" && ! -L "$XDG_CACHE_HOME/alis" ]] || fail 'foreign cache replaced'
for root in "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"; do
    [[ -L "$root/alis" ]] || fail 'unconflicted alias absent'
done
if migration_check; then fail 'collision-only destinations must not endlessly reappear'; fi
printf '%s\n' 'PASS: optional XDG aliases skip foreign cache/links, preserve user data and apply safe roots'
