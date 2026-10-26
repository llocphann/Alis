#!/usr/bin/env bash
# Pure synthetic service cutover rollback; no real session or owner data touched.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
fail() { echo "FAIL: staged service rollback: $*" >&2; exit 1; }
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/config" XDG_STATE_HOME="$tmp/home/state"
export XDG_CACHE_HOME="$tmp/home/cache" XDG_DATA_HOME="$tmp/home/share"
export TEST_HOME="$HOME" PATH="$HOME/bin:$PATH"
mkdir -p "$HOME/config/systemd/user/niri.service.wants" "$HOME/config/alis" "$HOME/bin"
printf 'private theme bytes\n' > "$HOME/config/alis/config.json"
cat > "$HOME/bin/alis" <<'OLD'
#!/usr/bin/env bash
[[ "${1:-}" == help ]] || exit 1
OLD
cat > "$HOME/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == --user ]] || exit 2
shift; action="$1"; shift
case "$action" in
  is-active) cat "$TEST_HOME/state-${1%.service}" ;;
  stop) printf 'inactive\n' > "$TEST_HOME/state-${1%.service}"; echo "stop:$1" >> "$TEST_HOME/ops" ;;
  show)
    unit="$1"; path="$TEST_HOME/config/systemd/user/$unit"
    if [[ -L "$path" && "$(readlink -- "$path")" == /dev/null ]]; then echo masked
    elif [[ -f "$path" ]]; then echo loaded
    else echo not-found; fi ;;
  start)
    echo "start:$1" >> "$TEST_HOME/ops"
    if [[ "$1" == alis.service && -f "$TEST_HOME/config/systemd/user/alis.service" ]]; then
      echo 'Two services allocated for the same bus name org.kde.StatusNotifierWatcher' >&2
      exit 1
    fi
    if [[ "$1" == alis.service && -f "$TEST_HOME/config/systemd/user/alis.service" ]]; then
      echo 'Two services allocated for the same bus name org.kde.StatusNotifierWatcher' >&2
      exit 1
    fi
    [[ "${FAIL_LEGACY_START:-0}" != 1 || "$1" != alis.service ]] || exit 1
    printf 'active\n' > "$TEST_HOME/state-${1%.service}" ;;
  daemon-reload) echo reload >> "$TEST_HOME/ops" ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$HOME/bin/alis" "$HOME/bin/systemctl"
cat > "$HOME/config/systemd/user/alis.service" <<UNIT
[Service]
ExecStart=$HOME/bin/alis run --session
UNIT
mkdir -p "$HOME/state/alis-cutover-backups"
mv -- "$HOME/config/systemd/user/alis.service" "$HOME/state/alis-cutover-backups/retired-alis.service"
ln -s /dev/null "$HOME/config/systemd/user/alis.service"
cat > "$HOME/config/systemd/user/alis.service" <<'UNIT'
[Service]
BusName=org.kde.StatusNotifierWatcher
ExecStart=/usr/bin/alis run --session
UNIT
wants="$HOME/config/systemd/user/niri.service.wants"
ln -s "$HOME/config/systemd/user/alis.service" "$wants/alis.service"
printf 'inactive\n' > "$HOME/state-alis"
printf 'active\n' > "$HOME/state-alis"
helper="$repo/scripts/brand-canonical-rollback.sh"
bash -n "$helper"
cp -p "$HOME/state/alis-cutover-backups/retired-alis.service" "$tmp/original-old-unit"
data_hash="$(sha256sum "$HOME/config/alis/config.json" | cut -d' ' -f1)"
bash "$helper" --dry-run > "$tmp/dry" || fail 'safe preview'
[[ -L "$wants/alis.service" && ! -e "$wants/alis.service" ]] || fail 'dry run modified wiring'
if bash "$helper" --apply > "$tmp/denied" 2>&1; then fail 'missing owner approval accepted'; fi
[[ "$(cat "$HOME/state-alis")" == active ]] || fail 'consent refusal mutated service'
if FAIL_LEGACY_START=1 bash "$helper" --apply --owner-approved > "$tmp/fail" 2>&1; then
  fail 'legacy start error incorrectly accepted'
fi
[[ "$(cat "$HOME/state-alis")" == inactive && "$(cat "$HOME/state-alis")" == active ]] ||
  fail 'failed legacy start did not restore Alis'
[[ -L "$wants/alis.service" && ! -e "$wants/alis.service" ]] ||
  fail 'failed old startup lost Alis wiring'
[[ -L "$HOME/config/systemd/user/alis.service" &&
   "$(readlink "$HOME/config/systemd/user/alis.service")" == /dev/null &&
   -f "$HOME/config/systemd/user/alis.service" &&
   -f "$HOME/state/alis-cutover-backups/retired-alis.service" ]] ||
  fail 'failed old start did not re-mask original and recover Alis singleton'
# Reproduce the deployed managed public shim: private service lifecycle works
# while public help is disabled. A byte-identical original runtime is required.
mkdir -p "$HOME/config/quickshell/alis/scripts"
printf '%s\n' '//@ pragma ShellId alis' > "$HOME/config/quickshell/alis/shell.qml"
cat > "$HOME/bin/alis" <<'GUARD'
#!/usr/bin/env bash
# BRAND-R01: keep the established scripts/alis engine
if [[ "${BASH_SOURCE[0]}" != */scripts/alis ]]; then
    if [[ -n "${INVOCATION_ID:-}" ]] && {
        [[ "${1:-}" == run && "${2:-}" == --session ]] ||
        [[ "${1:-}" == cleanup-orphans ]];
    }; then :; else exit 64; fi
fi
[[ "${1:-}" == help ]]
GUARD
chmod +x "$HOME/bin/alis"
cp -p "$HOME/bin/alis" "$HOME/config/quickshell/alis/scripts/alis"
if "$HOME/bin/alis" help; then fail 'fixture did not reproduce managed help refusal'; fi
bash "$helper" --dry-run > "$tmp/managed" || fail 'managed private engine recovery rejected'
grep -Fq 'VERIFIED: byte-identical' "$tmp/managed" || fail 'private recovery proof missing'
cp -p "$HOME/bin/alis" "$tmp/verified-cli"
printf '\n# edited public wrapper\n' >> "$HOME/bin/alis"
if bash "$helper" --dry-run > "$tmp/divergent" 2>&1; then fail 'divergent disabled CLI accepted'; fi
cp -p "$tmp/verified-cli" "$HOME/bin/alis"
mv "$HOME/config/quickshell/alis/scripts/alis" "$tmp/private-engine"
ln -s "$tmp/private-engine" "$HOME/config/quickshell/alis/scripts/alis"
if bash "$helper" --dry-run > "$tmp/symlink" 2>&1; then fail 'symlink private engine accepted'; fi
rm "$HOME/config/quickshell/alis/scripts/alis"
cp -p "$tmp/private-engine" "$HOME/config/quickshell/alis/scripts/alis"
bash "$helper" --apply --owner-approved > "$tmp/ok" || fail 'approved rollback'
[[ "$(cat "$HOME/state-alis")" == active && "$(cat "$HOME/state-alis")" == inactive ]] ||
  fail 'two owners after successful rollback'
[[ -L "$wants/alis.service" && ! -e "$wants/alis.service" ]] ||
  fail 'old compositor link not restored'
[[ ! -e "$HOME/config/systemd/user/alis.service" &&
   -f "$HOME/config/systemd/user/alis.service" &&
   ! -L "$HOME/config/systemd/user/alis.service" &&
   ! -e "$HOME/state/alis-cutover-backups/retired-alis.service" ]] ||
  fail 'post-success rollback still exposes competing D-Bus unit'
cmp -s "$tmp/original-old-unit" "$HOME/config/systemd/user/alis.service" ||
  fail 'post-success rollback modified original service unit bytes'
compgen -G "$HOME/state/alis-cutover-backups/rollback-backup-*/alis.service" >/dev/null ||
  fail 'canonical unit rollback backup missing'
[[ "$(sha256sum "$HOME/config/alis/config.json" | cut -d' ' -f1)" == "$data_hash" ]] ||
  fail 'settings mutated'
if bash "$helper" --apply --owner-approved > "$tmp/again" 2>&1; then
  fail 'second rollback accepted without Alis owner'
fi
echo 'PASS: exclusive D-Bus name before and after rollback, failed-start recovery, verified unit archives and preserved settings'
