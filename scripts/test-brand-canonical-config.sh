#!/usr/bin/env bash
# Isolated canonical configuration and historical-migration safety tests.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
fail() { printf 'FAIL: canonical config: %s\n' "$*" >&2; exit 1; }
mkdir -p "$tmp/config"/{alis,illogical-impulse,inir}
printf 'canonical bytes\n' > "$tmp/config/alis/config.json"
printf 'old upstream bytes\n' > "$tmp/config/illogical-impulse/config.json"
printf 'other old bytes\n' > "$tmp/config/inir/config.json"
export HOME="$tmp" XDG_CONFIG_HOME="$tmp/config"

actual="$(bash -c 'source "$1"; alis_config_dir' _ "$root/scripts/lib/config-path.sh")"
[[ "$actual" == "$tmp/config/alis" ]] || fail 'CLI helper still prioritizes legacy config'
actual="$(bash -c 'source "$1"; resolve_alis_config_dir' _ "$root/sdata/lib/environment-variables.sh")"
[[ "$actual" == "$tmp/config/alis" ]] || fail 'installer still prioritizes legacy config'
actual="$(bash -c 'REPO_ROOT="$1"; source "$1/sdata/lib/migrations.sh"; printf "%s" "$MIGRATIONS_STATE_FILE"' _ "$root")"
[[ "$actual" == "$tmp/config/alis/migrations.json" ]] ||
    fail 'migration state still diverges from runtime config'
grep -Fq 'property string shellConfig:' "$root/modules/common/Directories.qml" &&
grep -Fq '/alis' "$root/modules/common/Directories.qml" ||
    fail 'QML still reads from a different config root'

(
    REPO_ROOT="$root"
    source "$root/sdata/lib/migrations.sh"
    if is_migration_needed 019-config-dir-rename-compat; then
        fail 'historical migration 019 would recreate retired inir namespace'
    fi
    tui_check_skip() { :; }
    apply_migration 019-config-dir-rename-compat true ||
        fail 'superseded forced migration did not abort safely'
)
[[ "$(cat "$tmp/config/illogical-impulse/config.json")" == 'old upstream bytes' ]] ||
    fail 'old upstream bytes mutated'
[[ "$(cat "$tmp/config/inir/config.json")" == 'other old bytes' ]] ||
    fail 'old inir bytes mutated'

rm -rf -- "$tmp/config/alis"
actual="$(bash -c 'source "$1"; alis_config_dir' _ "$root/scripts/lib/config-path.sh")"
[[ "$actual" == "$tmp/config/illogical-impulse" ]] ||
    fail 'pre-cutover legacy compatibility lost'
actual="$(bash -c 'source "$1"; resolve_alis_config_dir' _ "$root/sdata/lib/environment-variables.sh")"
[[ "$actual" == "$tmp/config/illogical-impulse" ]] ||
    fail 'pre-cutover installer compatibility lost'
(
    REPO_ROOT="$root"
    source "$root/sdata/lib/migrations.sh"
    is_migration_needed 019-config-dir-rename-compat ||
        fail 'original historical migration should remain available pre-cutover'
)
[[ -f "$tmp/config/illogical-impulse/config.json" ]] ||
    fail 'pre-cutover migration check was destructive'
grep -Fq 'title: Translation.tr("Based on")' "$root/modules/settings/About.qml" ||
    fail 'upstream attribution section missing'
grep -Fq 'mainText: "iNiR"' "$root/modules/settings/About.qml" ||
    fail 'source credit incorrectly relabeled as Alis'
grep -Fq 'label: "iNiR"' "$root/modules/waffle/settings/pages/WAboutPage.qml" ||
    fail 'Waffle source credit incorrectly relabeled as Alis'
grep -Fq 'BASHPID' "$root/scripts/brand-canonical-cutover.sh" ||
    fail 'cutover backups lack a unique process identifier'
echo 'PASS: Alis config resolution, historical migration isolation, credits and unique backups'
