#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$repo_root/sdata/migrations/019-config-dir-rename-compat.sh"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT

run_with_config_home() {
  XDG_CONFIG_HOME="$1" migration_apply
}

# Legacy-only installs should move the directory, preserve its contents, and
# leave the compatibility symlink pointing at the canonical directory.
case_root="$stage/legacy-only"
mkdir -p "$case_root/illogical-impulse"
printf 'legacy-data\n' > "$case_root/illogical-impulse/config.json"
run_with_config_home "$case_root" >/dev/null
[[ -f "$case_root/inir/config.json" ]] || fail 'legacy-only migration did not preserve config data'
[[ -L "$case_root/illogical-impulse" ]] || fail 'legacy-only migration did not create compatibility symlink'
[[ "$(readlink "$case_root/illogical-impulse")" == "$case_root/inir" ]] \
  || fail 'legacy-only compatibility symlink points at the wrong target'

# A compatibility link can survive while its canonical directory is removed.
# The check must keep this migration pending so apply can recreate the target.
case_root="$stage/dangling-compat-link"
mkdir -p "$case_root"
ln -s "$case_root/inir" "$case_root/illogical-impulse"
if ! XDG_CONFIG_HOME="$case_root" migration_check; then
  fail 'migration check skipped a dangling compatibility symlink'
fi
run_with_config_home "$case_root" >/dev/null
[[ -d "$case_root/inir" ]] || fail 'migration did not recreate the canonical config directory'
if XDG_CONFIG_HOME="$case_root" migration_check; then
  fail 'migration check still reports a repaired compatibility layout as pending'
fi

# Two real config trees are ambiguous. The migration must fail closed and leave
# both trees untouched instead of merging and deleting the legacy directory.
case_root="$stage/conflicting-directories"
mkdir -p "$case_root/inir" "$case_root/illogical-impulse"
printf 'canonical\n' > "$case_root/inir/config.json"
printf 'legacy\n' > "$case_root/illogical-impulse/config.json"
if run_with_config_home "$case_root" >/dev/null 2>&1; then
  fail 'migration accepted conflicting canonical and legacy directories'
fi
[[ "$(cat "$case_root/inir/config.json")" == 'canonical' ]] \
  || fail 'migration changed canonical data during conflict handling'
[[ "$(cat "$case_root/illogical-impulse/config.json")" == 'legacy' ]] \
  || fail 'migration changed legacy data during conflict handling'

# A legacy symlink owned by another layout must never be silently replaced.
case_root="$stage/foreign-symlink"
mkdir -p "$case_root/foreign"
ln -s "$case_root/foreign" "$case_root/illogical-impulse"
if run_with_config_home "$case_root" >/dev/null 2>&1; then
  fail 'migration replaced a foreign legacy symlink'
fi
[[ "$(readlink "$case_root/illogical-impulse")" == "$case_root/foreign" ]] \
  || fail 'migration changed a foreign legacy symlink'

# Unexpected non-directory legacy paths are user data too; preserve them and
# require manual reconciliation instead of marking the migration successful.
case_root="$stage/legacy-file"
mkdir -p "$case_root"
printf 'do-not-delete\n' > "$case_root/illogical-impulse"
if run_with_config_home "$case_root" >/dev/null 2>&1; then
  fail 'migration accepted an unexpected legacy file'
fi
[[ "$(cat "$case_root/illogical-impulse")" == 'do-not-delete' ]] \
  || fail 'migration changed an unexpected legacy file'

# Keep the safety contract wired into release publication and user-facing
# lifecycle/configuration guidance so behavior and documentation cannot drift.
grep -Fq '"$script_dir/test-config-namespace-migration.sh"' "$repo_root/scripts/release.sh" \
  || fail 'release helper no longer runs the config namespace migration contract'
grep -Fq 'Migration 019 is intentionally fail-closed' "$repo_root/docs/INSTALL.md" \
  || fail 'install docs no longer explain fail-closed config migration behavior'
grep -Fq 'the migration stops and preserves both states unchanged' "$repo_root/docs/INSTALL.md" \
  || fail 'install docs no longer state that conflicting config trees are preserved'
# Migration 019 is a HISTORICAL iNiR-to-illogical-impulse compatibility
# contract; canonical Alis must not advertise the retired public CLI again.
grep -Fq 'Migration 019 is historical:' "$repo_root/docs/CONFIG_SYSTEM.md" \
  || fail 'config docs no longer distinguish historical migration 019 from canonical Alis'
grep -Fq 'refusal to overwrite divergent real directories or foreign symlinks' "$repo_root/docs/CONFIG_SYSTEM.md" \
  || fail 'config docs no longer explain fail-closed namespace conflict handling'
grep -Fq 'Do not run old migration 019 to prepare an Alis installation.' "$repo_root/docs/CONFIG_SYSTEM.md" \
  || fail 'config docs no longer protect canonical installs against retired migration 019'
grep -Fq 'before running `alis migrate`' "$repo_root/docs/CONFIG_SYSTEM.md" \
  || fail 'config docs no longer require manual reconciliation before canonical migration'

printf '%s\n' '1..1'
printf '%s\n' 'ok 1 - config namespace migration preserves data and repairs compatibility layout'
