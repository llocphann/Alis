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
    printf '#!/bin/bash\n# Canonical CLI and runtime name is Alis.\nexit 0\n' > "$home/bin/alis"
    chmod +x "$home/bin/alis"
    printf '%s\n' '//@ pragma ShellId alis' > "$home/config/quickshell/alis/shell.qml"
    printf '%s\n' 'old user prefs' > "$home/config/inir/preferences.json"
    printf '%s\n' '[Service]' 'ExecStart=/usr/bin/inir run --session' > "$home/config/systemd/user/inir.service"
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
        printf '%s\n' inactive > "$TEST_HOME/state-${1%.service}"
        printf '%s\n' "stop $1" >> "$TEST_HOME/order"
        ;;
    start)
        printf '%s\n' "start $1" >> "$TEST_HOME/order"
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
    export XDG_STATE_HOME="$TEST_HOME/state"
    export PATH="$TEST_HOME/bin:/usr/bin:/bin"
    bash "$helper" "$@"
}

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

echo 'PASS: canonical service cutover dry-run, old-hotkey guard, sole owner, rollback'
