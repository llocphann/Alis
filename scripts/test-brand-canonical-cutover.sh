#!/usr/bin/env bash
# Deterministic fake user-service owner cutover tests; never touches desktop.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$root/scripts/brand-canonical-cutover.sh"
die() { printf 'FAIL: canonical cutover: %s\n' "$*" >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
bash -n "$helper" || die 'cutover helper Bash syntax'

make_fixture() {
    local name="$1"
    local home="$tmp/$name"
    mkdir -p "$home"/{bin,config/niri/config.d,config/quickshell/alis,config/systemd/user/niri.service.wants,config/inir,cache}
    cp "$root/scripts/alis" "$home/bin/alis"
    chmod +x "$home/bin/alis"
    printf '%s\n' '//@ pragma ShellId alis' > "$home/config/quickshell/alis/shell.qml"
    printf '%s\n' 'old user prefs' > "$home/config/inir/preferences.json"
    printf '#!/bin/bash\n[[ "${1:-}" == help ]]\n' > "$home/bin/inir"
    chmod +x "$home/bin/inir"
    printf '%s\n' '[Service]' 'Type=dbus' 'BusName=org.kde.StatusNotifierWatcher' "ExecStart=$home/bin/inir run --session" > "$home/config/systemd/user/inir.service"
    ln -s "$home/config/systemd/user/inir.service" "$home/config/systemd/user/niri.service.wants/inir.service"
    printf 'include "config.d/90-user-extra.kdl"\n' > "$home/config/niri/config.kdl"
    printf 'binds {\n  Super+E { spawn "/usr/bin/nautilus"; }\n}\n' > "$home/config/niri/config.d/90-user-extra.kdl"
    printf 'active\n' > "$home/state-inir"
    printf 'inactive\n' > "$home/state-alis"
    cat > "$home/bin/systemctl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == --user ]] || exit 2
shift
cmd="${1:-}"; shift || true
case "$cmd" in
    is-active)
        case "${1:-}" in
            inir.service) cat "$TEST_HOME/state-inir" ;;
            alis.service) cat "$TEST_HOME/state-alis" ;;
            *) echo inactive ;;
        esac
        ;;
    stop)
        if [[ "$1" == inir.service && "${WRITE_ON_STOP:-0}" == 1 ]]; then
            printf 'final shutdown preferences\n' > "$TEST_HOME/config/inir/preferences.json"
        fi
        printf '%s\n' inactive > "$TEST_HOME/state-${1%.service}"
        printf '%s\n' "stop $1" >> "$TEST_HOME/order"
        ;;
    show)
        unit="$1"; original="$TEST_HOME/config/systemd/user/$unit"
        if [[ -L "$original" && "$(readlink -- "$original")" == /dev/null ]]; then echo masked
        elif [[ -f "$original" ]]; then echo loaded
        else echo not-found; fi
        ;;
    start)
        printf '%s\n' "start $1" >> "$TEST_HOME/order"
        # Reproduce real systemd: two installed Type=dbus units cannot own the
        # same BusName, even if the other unit is inactive.
        if [[ "$1" == alis.service &&
              -f "$TEST_HOME/config/systemd/user/inir.service" ]] &&
           grep -Fq 'BusName=org.kde.StatusNotifierWatcher' "$TEST_HOME/config/systemd/user/inir.service"; then
            echo 'Two services allocated for the same bus name org.kde.StatusNotifierWatcher' >&2
            exit 1
        fi
        if [[ "$1" == inir.service &&
              -f "$TEST_HOME/config/systemd/user/alis.service" ]] &&
           grep -Fq 'BusName=org.kde.StatusNotifierWatcher' "$TEST_HOME/config/systemd/user/alis.service"; then
            echo 'Two services allocated for the same bus name org.kde.StatusNotifierWatcher' >&2
            exit 1
        fi
        if [[ "$1" == alis.service && "${FAIL_NEW_OWNER:-0}" == 1 ]]; then
            exit 1
        fi
        printf '%s\n' active > "$TEST_HOME/state-${1%.service}"
        ;;
    daemon-reload) printf '%s\n' reload >> "$TEST_HOME/order" ;;
    *) exit 2 ;;
esac
FAKE
    chmod +x "$home/bin/systemctl"
}

invoke() {
    local fixture="$1";shift
    export TEST_HOME="$tmp/$fixture"
    export HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/config"
    export XDG_CACHE_HOME="$TEST_HOME/cache"
    export XDG_DATA_HOME="$TEST_HOME/data"
    export XDG_STATE_HOME="$TEST_HOME/state"
    export PATH="$TEST_HOME/bin:/usr/bin:/bin"
    bash "$helper" "$@"
}

make_fixture stale_cli
printf '\n# stale source revision\n' >> "$tmp/stale_cli/bin/alis"
if invoke stale_cli --dry-run > "$tmp/stale-cli.log" 2>&1; then
    die 'accepted a stale canonical CLI before live owner switch'
fi
grep -Fq 'Installed canonical CLI differs from source' "$tmp/stale-cli.log" ||
    die 'stale canonical launcher rejection is not actionable'
[[ "$(cat "$tmp/stale_cli/state-inir")" == active ]] ||
    die 'stale CLI preflight stopped original owner'
make_fixture reject
# Owner's historic 90-user-extra shortcut must be rejected before any writes.
printf 'binds {\n Super+E { spawn "/home/user/.local/bin/inir" "terminal" "yazi"; }\n}\n' \
    > "$tmp/reject/config/niri/config.d/90-user-extra.kdl"
if invoke reject --dry-run > "$tmp/reject.log" 2>&1; then
    die 'allowed retired executable in final Niri overrides'
fi
grep -Fq 'Active Niri shortcut still invokes disabled inir' "$tmp/reject.log" ||
    die 'missing Niri preflight diagnostic'
[[ "$(cat "$tmp/reject/state-inir")" == active ]] ||
    die 'preflight stopped original service'
[[ ! -e "$tmp/reject/config/systemd/user/alis.service" ]] ||
    die 'preflight installed new unit'

make_fixture hidden
printf 'include "config.d/95-hidden.kdl"\n' >> "$tmp/hidden/config/niri/config.kdl"
printf 'binds { Super+E { spawn "/home/user/.local/bin/inir" "terminal" "yazi"; } }\n' \
    > "$tmp/hidden/config/niri/config.d/95-hidden.kdl"
if invoke hidden --dry-run > "$tmp/hidden.log" 2>&1; then
    die 'allowed retired CLI in an arbitrary referenced Niri fragment'
fi
grep -Fq 'Active Niri shortcut still invokes disabled inir' "$tmp/hidden.log" ||
    die 'hidden fragment rejection did not identify active retired CLI'
[[ "$(cat "$tmp/hidden/state-inir")" == active ]] ||
    die 'hidden fragment preflight stopped the original owner'

make_fixture nested
printf 'include "config.d/96-nested.kdl"\n' >> "$tmp/nested/config/niri/config.d/90-user-extra.kdl"
printf 'binds { Mod+Return { exec inir terminal; } }\n' \
    > "$tmp/nested/config/niri/config.d/96-nested.kdl"
if invoke nested --dry-run > "$tmp/nested.log" 2>&1; then
    die 'allowed retired CLI in a nested Niri include'
fi
grep -Fq 'Active Niri shortcut still invokes disabled inir' "$tmp/nested.log" ||
    die 'nested fragment was not inspected'

make_fixture dangling
printf 'include "config.d/not-present.kdl"\n' >> "$tmp/dangling/config/niri/config.kdl"
if invoke dangling --dry-run > "$tmp/dangling.log" 2>&1; then
    die 'accepted missing referenced Niri config during service cutover'
fi
grep -Fq 'Unresolved Niri include' "$tmp/dangling.log" ||
    die 'missing include failure lacks actionable diagnostic'

make_fixture link
mv "$tmp/link/config/niri/config.kdl" "$tmp/link/config/niri/config-source.kdl"
ln -s "$tmp/link/config/niri/config-source.kdl" "$tmp/link/config/niri/config.kdl"
if invoke link --dry-run > "$tmp/link.log" 2>&1; then
    die 'symlinked Niri entrypoint skipped all keybind preflights'
fi
grep -Fq 'Niri root is a symlink' "$tmp/link.log" ||
    die 'missing explicit symlink review boundary'

make_fixture archive_collision
mkdir -p "$tmp/archive_collision/state/alis-cutover-backups"
printf 'foreign retirement marker\n' > "$tmp/archive_collision/state/alis-cutover-backups/retired-inir.service"
if invoke archive_collision --dry-run > "$tmp/archive-collision.log" 2>&1; then
    die 'accepted pre-existing owner-unit archive collision'
fi
grep -Fq 'Existing retired service archive' "$tmp/archive-collision.log" ||
    die 'missing manual-review archive collision diagnostic'
[[ "$(cat "$tmp/archive_collision/state-inir")" == active ]] ||
    die 'archive collision stopped original desktop'

make_fixture good
mkdir -p "$tmp/good/state/inir"
printf '%s\n' 'private state byte' > "$tmp/good/state/inir/snapshot.dat"
dry="$(invoke good --dry-run)" || die 'dry run failed'
[[ "$dry" == *'DRY-RUN: no modifications.'* ]] || die 'no dry run result'
[[ ! -e "$tmp/good/config/alis" ]] || die 'dry run touched user data'
if invoke good --apply > "$tmp/unauthorized.log" 2>&1; then
    die 'applied without explicit owner approval'
fi
[[ "$(cat "$tmp/good/state-inir")" == active ]] ||
    die 'unauthorized request stopped original service'
invoke good --apply --owner-approved > "$tmp/success.log" ||
    die 'approved service cutover failed'
[[ "$(cat "$tmp/good/state-inir")" == inactive &&
   "$(cat "$tmp/good/state-alis")" == active ]] ||
    die 'two-service handoff state incorrect'
[[ -f "$tmp/good/config/alis/preferences.json" ]] ||
    die 'lost a copied user preference'
[[ -f "$tmp/good/state/alis/snapshot.dat" ]] ||
    die 'Alis state was not copied to the canonical state root'
[[ ! -e "$tmp/good/state/alis/inir/snapshot.dat" ]] ||
    die 'state copy nested the old namespace within the new one'
[[ -f "$tmp/good/config/inir/preferences.json" ]] ||
    die 'destructively removed original user preference'
[[ -L "$tmp/good/config/systemd/user/niri.service.wants/alis.service" ]] ||
    die 'Alis compositor service link missing'
[[ ! -e "$tmp/good/config/systemd/user/niri.service.wants/inir.service" ]] ||
    die 'old wants link still enabled'
retired="$tmp/good/state/alis-cutover-backups/retired-inir.service"
[[ -f "$retired" && ! -L "$retired" ]] ||
    die 'byte-identical original unit was not archived outside systemd'
[[ -L "$tmp/good/config/systemd/user/inir.service" &&
   "$(readlink "$tmp/good/config/systemd/user/inir.service")" == /dev/null ]] ||
    die 'old D-Bus unit was not masked before loading Alis'
grep -Fxq 'BusName=org.kde.StatusNotifierWatcher' "$retired" ||
    die 'original D-Bus declaration not retained for recovery'
[[ "$(cat "$tmp/good/state-inir")" == inactive ]] ||
    die 'old unit started alongside Alis'
[[ "$(grep -c 'start alis.service' "$tmp/good/order")" == 1 ]] ||
    die 'new service started more than once'
[[ "$(head -n 1 "$tmp/good/order")" == 'stop inir.service' ]] ||
    die 'started new service before old owner stopped'

# Original upstream settings may be linked into the public Alis namespace.
# The script must preserve the historical directory, replace only that
# recognized symlink, and copy the active config file without modifying bytes.
make_fixture upstream
mkdir -p "$tmp/upstream/config/illogical-impulse"
printf '%s\n' '{"language":"vi","userSetting":true}' > "$tmp/upstream/config/illogical-impulse/config.json"
ln -s "$tmp/upstream/config/illogical-impulse" "$tmp/upstream/config/alis"
invoke upstream --apply --owner-approved > "$tmp/upstream.log" ||
    die 'upstream configuration alias cutover failed'
[[ ! -L "$tmp/upstream/config/alis" ]] ||
    die 'recognized upstream alias not replaced with canonical directory'
cmp "$tmp/upstream/config/illogical-impulse/config.json" "$tmp/upstream/config/alis/config.json" ||
    die 'upstream settings changed during migration'

# Package metadata under the old upstream namespace must block a mutable
# service cutover, even when no inir/version.json exists.
make_fixture package
mkdir -p "$tmp/package/config/illogical-impulse"
printf '%s\n' '{"packageManager":"nix"}' > "$tmp/package/config/illogical-impulse/version.json"
if invoke package --dry-run > "$tmp/package.log" 2>&1; then
    die 'Nix installation was incorrectly treated as repo-copy'
fi
[[ "$(cat "$tmp/package/state-inir")" == active ]] ||
    die 'package-manager guard mutated old session'

make_fixture rollback
cp -p "$tmp/rollback/config/systemd/user/inir.service" "$tmp/rollback-old-unit"
if FAIL_NEW_OWNER=1 invoke rollback --apply --owner-approved > "$tmp/failure.log" 2>&1; then
    die 'simulated failed new unit was accepted'
fi
[[ "$(cat "$tmp/rollback/state-inir")" == active ]] ||
    die 'failed rollback did not reactivate original unit'
[[ "$(cat "$tmp/rollback/state-alis")" == inactive ]] ||
    die 'failed rollback left new unit active'
[[ ! -e "$tmp/rollback/config/systemd/user/alis.service" ]] ||
    die 'failed rollback left new service installed'
[[ -L "$tmp/rollback/config/systemd/user/niri.service.wants/inir.service" ]] ||
    die 'failed rollback did not restore original compositor link'
[[ -f "$tmp/rollback/config/inir/preferences.json" ]] ||
    die 'failed rollback deleted original user preference'
[[ -f "$tmp/rollback/config/systemd/user/inir.service" &&
   ! -L "$tmp/rollback/config/systemd/user/inir.service" ]] ||
    die 'failed cutover did not restore the original user unit'
cmp -s "$tmp/rollback-old-unit" "$tmp/rollback/config/systemd/user/inir.service" ||
    die 'failed cutover changed original service unit bytes'
[[ ! -e "$tmp/rollback/state/alis-cutover-backups/retired-inir.service" ]] ||
    die 'failed cutover stranded original unit in archive'


# An existing canonical cache is not an ownership conflict. The script must
# preserve existing canonical and legacy cache bytes, while copying settings.
make_fixture cache_existing
mkdir -p "$tmp/cache_existing/cache/inir" "$tmp/cache_existing/cache/alis"
printf 'historic cache bytes\n' > "$tmp/cache_existing/cache/inir/sentinel.bin"
printf 'user-created Alis cache bytes\n' > "$tmp/cache_existing/cache/alis/sentinel.bin"
legacy_cache_hash="$(sha256sum "$tmp/cache_existing/cache/inir/sentinel.bin" | cut -d ' ' -f1)"
alis_cache_hash="$(sha256sum "$tmp/cache_existing/cache/alis/sentinel.bin" | cut -d ' ' -f1)"
cache_preview="$(invoke cache_existing --dry-run)" || die 'existing Alis cache blocked dry run'
[[ "$cache_preview" == *"KEEP existing Alis cache unchanged"* ]] ||
    die 'missing read-only existing-cache explanation'
[[ "$cache_preview" != *"COPY $tmp/cache_existing/cache/inir -> $tmp/cache_existing/cache/alis"* ]] ||
    die 'dry run proposed overwriting a user-owned cache'
[[ "$(cat "$tmp/cache_existing/state-inir")" == active ]] ||
    die 'cache preview unexpectedly stopped original service'
invoke cache_existing --apply --owner-approved > "$tmp/cache-existing.log" ||
    die 'cache-preserving approved cutover failed'
[[ "$(sha256sum "$tmp/cache_existing/cache/inir/sentinel.bin" | cut -d ' ' -f1)" == "$legacy_cache_hash" ]] ||
    die 'cutover changed original cache'
[[ "$(sha256sum "$tmp/cache_existing/cache/alis/sentinel.bin" | cut -d ' ' -f1)" == "$alis_cache_hash" ]] ||
    die 'cutover overwrote foreign Alis cache'
[[ -f "$tmp/cache_existing/config/alis/preferences.json" ]] ||
    die 'skipping cache prevented config migration'
[[ "$(cat "$tmp/cache_existing/state-alis")" == active ]] ||
    die 'cache-preserving cutover failed to establish Alis sole owner'

# Only an existing REAL cache directory is skipped. A file or symlink at the
# destination must still fail closed before service writes.
make_fixture cache_file
mkdir -p "$tmp/cache_file/cache/inir"
printf 'historic bytes\n' > "$tmp/cache_file/cache/inir/sentinel"
printf 'foreign file bytes\n' > "$tmp/cache_file/cache/alis"
if invoke cache_file --dry-run > "$tmp/cache-file.log" 2>&1; then
    die 'accepted non-directory Alis cache destination'
fi
grep -Fq 'not a plain directory' "$tmp/cache-file.log" ||
    die 'cache file rejection lacked explanation'
[[ "$(cat "$tmp/cache_file/cache/alis")" == 'foreign file bytes' ]] ||
    die 'cache file was modified'
[[ "$(cat "$tmp/cache_file/state-inir")" == active ]] ||
    die 'cache file preflight stopped old owner'

make_fixture cache_symlink
mkdir -p "$tmp/cache_symlink/cache/inir" "$tmp/cache_symlink/foreign"
printf 'external cache bytes\n' > "$tmp/cache_symlink/foreign/sentinel"
ln -s "$tmp/cache_symlink/foreign" "$tmp/cache_symlink/cache/alis"
if invoke cache_symlink --dry-run > "$tmp/cache-symlink.log" 2>&1; then
    die 'accepted symlinked Alis cache destination'
fi
[[ -L "$tmp/cache_symlink/cache/alis" &&
   "$(cat "$tmp/cache_symlink/foreign/sentinel")" == 'external cache bytes' ]] ||
    die 'preflight mutated symlinked cache'

# Preserve the original strict fail-closed rule for non-cache namespaces.
for zone in config data state; do
    make_fixture "noncache_$zone"
    home="$tmp/noncache_$zone"
    case "$zone" in
        config) mkdir -p "$home/config/alis"; printf 'foreign config\n' > "$home/config/alis/sentinel" ;;
        data) mkdir -p "$home/data/inir" "$home/data/alis"
              printf 'old data\n' > "$home/data/inir/sentinel"
              printf 'foreign data\n' > "$home/data/alis/sentinel" ;;
        state) mkdir -p "$home/state/inir" "$home/state/alis"
               printf 'old state\n' > "$home/state/inir/sentinel"
               printf 'foreign state\n' > "$home/state/alis/sentinel" ;;
    esac
    if invoke "noncache_$zone" --dry-run > "$tmp/noncache-$zone.log" 2>&1; then
        die "accepted foreign Alis $zone root"
    fi
    grep -Fq 'Foreign Alis data root, refusing overwrite' "$tmp/noncache-$zone.log" ||
        die "missing explicit $zone collision diagnostic"
    [[ "$(cat "$home/state-inir")" == active ]] ||
        die "$zone preflight stopped legacy owner"
done

# Failed Alis service startup must also preserve both original and foreign
# cache roots and restore the previous owner.
make_fixture cache_failure
mkdir -p "$tmp/cache_failure/cache/inir" "$tmp/cache_failure/cache/alis"
printf 'historic rollback cache\n' > "$tmp/cache_failure/cache/inir/sentinel"
printf 'foreign rollback cache\n' > "$tmp/cache_failure/cache/alis/sentinel"
if FAIL_NEW_OWNER=1 invoke cache_failure --apply --owner-approved > "$tmp/cache-failure.log" 2>&1; then
    die 'accepted failed Alis service with retained cache'
fi
[[ "$(cat "$tmp/cache_failure/state-inir")" == active &&
   "$(cat "$tmp/cache_failure/state-alis")" == inactive ]] ||
    die 'failed cutover did not restore sole original owner'
[[ "$(cat "$tmp/cache_failure/cache/inir/sentinel")" == 'historic rollback cache' &&
   "$(cat "$tmp/cache_failure/cache/alis/sentinel")" == 'foreign rollback cache' ]] ||
    die 'failed cutover corrupted either cache'

echo 'PASS: canonical cutover reproduces duplicate D-Bus rejection, masks retired unit, preserves recovery archive'


make_fixture quiescent
WRITE_ON_STOP=1 invoke quiescent --apply --owner-approved > "$tmp/quiescent.log" || die 'quiescent snapshot'
cmp -s "$tmp/quiescent/config/inir/preferences.json" "$tmp/quiescent/config/alis/preferences.json" || die 'lost final shutdown writes'
grep -Fq 'final shutdown preferences' "$tmp/quiescent/config/alis/preferences.json" || die 'copied before owner stop'
echo 'PASS: final shutdown writes are captured after the previous owner stops'

make_fixture stale_helpers
printf 'spawn-at-startup "bash" "-c" "exec wl-paste --watch ~/.config/quickshell/inir/scripts/native-dispatch clipboard-store"\n' >> "$tmp/stale_helpers/config/niri/config.d/90-user-extra.kdl"
if invoke stale_helpers --dry-run > "$tmp/helpers-denied" 2>&1; then die 'old clipboard helper survived preflight'; fi
grep -Fq 'Active Niri helper still points' "$tmp/helpers-denied" || die 'missing stale helper diagnostic'
[[ "$(cat "$tmp/stale_helpers/state-inir")" == active ]] || die 'stale helper rejection stopped owner'
make_fixture stale_markers
printf '// >>> inir-managed-autostart >>>\n// <<< inir-managed-autostart <<<\n' >> "$tmp/stale_markers/config/niri/config.d/90-user-extra.kdl"
if invoke stale_markers --dry-run > "$tmp/markers-denied" 2>&1; then die 'legacy managed block survived preflight'; fi
grep -Fq 'Autostart delimiters require repair' "$tmp/markers-denied" || die 'missing old marker diagnostic'
echo 'PASS: legacy clipboard helper paths and Autostart delimiters block before any service write'
