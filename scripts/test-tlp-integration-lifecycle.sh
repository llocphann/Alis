#!/usr/bin/env bash
set -euo pipefail
script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
power_persistence="$repo_root/services/PowerProfilePersistence.qml"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
assert_file_contains() { grep -Fq -- "$1" "$2" || fail "$3"; }
assert_text_contains() { grep -Fq -- "$1" <<<"$2" || fail "$3"; }
# Worker timeout/cadence and helper behavior coverage is owned by AlisIntergration.
# Core still guards generic power-provider restoration and inert old migrations.
# Power profile restore must fail closed while tlp-pd ownership is unknown. A
# Process startup failure must cancel the timeout without pretending the probe
# completed; a real start arms the timeout, and the timeout must not stop an
# already-failed/not-running process.
tlp_probe_running_block="$(sed -n '/^[[:space:]]*onRunningChanged: {/,/^[[:space:]]*onStarted: {/p' "$power_persistence")"
tlp_probe_started_block="$(sed -n '/^[[:space:]]*onStarted: {/,/^[[:space:]]*onExited:/p' "$power_persistence")"
tlp_probe_timeout_block="$(sed -n '/^[[:space:]]*id: tlpPdTimeout$/,/^[[:space:]]*\/\/ Re-probe/p' "$power_persistence")"
[[ -n "$tlp_probe_running_block" && -n "$tlp_probe_started_block" && -n "$tlp_probe_timeout_block" ]] \
  || fail 'PowerProfilePersistence tlp-pd lifecycle blocks are missing'
assert_text_contains 'tlpPdProbe.startObserved = false' "$tlp_probe_running_block" \
  'tlp-pd startup attempt must begin unobserved'
assert_text_contains 'if (tlpPdProbe.startObserved)' "$tlp_probe_running_block" \
  'tlp-pd startup-failure handling must distinguish a real process start'
assert_text_contains 'tlpPdTimeout.stop()' "$tlp_probe_running_block" \
  'tlp-pd startup failure must cancel its timeout'
assert_text_contains 'root._tlpProbeDone = false' "$tlp_probe_running_block" \
  'tlp-pd startup failure must keep ownership unknown'
if grep -Fq 'root._tlpProbeDone = true' <<<"$tlp_probe_running_block"; then
  fail 'tlp-pd startup failure must not mark ownership probing complete'
fi
assert_text_contains 'tlpPdProbe.startObserved = true' "$tlp_probe_started_block" \
  'tlp-pd process start must be observed before timeout handling'
assert_text_contains 'tlpPdTimeout.restart()' "$tlp_probe_started_block" \
  'tlp-pd process start must arm its timeout'
assert_file_contains 'root._lastTlpProbeAt = Date.now()' "$power_persistence" \
  'successful tlp-pd probes must timestamp the cached ownership result'
assert_file_contains 'Date.now() - root._lastTlpProbeAt >= root._tlpProbeFreshnessMs' "$power_persistence" \
  'stale power-profile ownership must be refreshed on demand'
assert_file_contains 'interval: root._tlpSafetyProbeIntervalMs' "$power_persistence" \
  'tlp-pd background safety probing must use the sparse adaptive cadence'
assert_text_contains 'if (!tlpPdProbe.running)' "$tlp_probe_timeout_block" \
  'tlp-pd timeout must ignore an already-stopped process'
assert_text_contains 'tlpPdProbe.timedOut = true' "$tlp_probe_timeout_block" \
  'tlp-pd timeout must mark an actually running probe as timed out'

mkdir -p "$tmp/state"
printf '%s\n' fixture-profile > "$tmp/state/profile"
: > "$tmp/actions"
pkg_sudo() { printf 'pkg_sudo:%s\n' "$*" >> "$tmp/actions"; return 98; }
systemctl() { printf 'systemctl:%s\n' "$*" >> "$tmp/actions"; return 98; }
install() { printf 'install:%s\n' "$*" >> "$tmp/actions"; return 98; }
for identity in 037-battery-charge-limit-helper 038-tlp-profile-backend 041-thinkfan-helper-bridge; do
    source "$repo_root/sdata/migrations/$identity.sh"
    [[ "$MIGRATION_ID" == "$identity" && "$MIGRATION_REQUIRED" == false ]] || fail "retired $identity changed identity/required state"
    if migration_check; then fail "retired $identity became pending"; fi
    migration_preview >/dev/null || fail "retired $identity preview failed"
    migration_apply || fail "retired $identity apply failed"
done
[[ ! -s "$tmp/actions" ]] || fail 'core migration touched optional helpers/services'
[[ "$(cat "$tmp/state/profile")" == fixture-profile ]] || fail 'core migration changed existing profile'
printf '%s\n' '1..1' 'ok 1 - generic power ownership guards retained; retired optional migrations are inert'
