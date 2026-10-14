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
cat > "$HOME/bin/inir" <<'OLD'
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
  start)
    echo "start:$1" >> "$TEST_HOME/ops"
    [[ "${FAIL_LEGACY_START:-0}" != 1 || "$1" != inir.service ]] || exit 1
    printf 'active\n' > "$TEST_HOME/state-${1%.service}" ;;
  daemon-reload) echo reload >> "$TEST_HOME/ops" ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$HOME/bin/inir" "$HOME/bin/systemctl"
cat > "$HOME/config/systemd/user/inir.service" <<UNIT
[Service]
ExecStart=$HOME/bin/inir run --session
UNIT
cat > "$HOME/config/systemd/user/alis.service" <<'UNIT'
[Service]
BusName=org.kde.StatusNotifierWatcher
ExecStart=/usr/bin/alis run --session
UNIT
wants="$HOME/config/systemd/user/niri.service.wants"
ln -s "$HOME/config/systemd/user/alis.service" "$wants/alis.service"
printf 'inactive\n' > "$HOME/state-inir"
printf 'active\n' > "$HOME/state-alis"
helper="$repo/scripts/brand-canonical-rollback.sh"
bash -n "$helper"
data_hash="$(sha256sum "$HOME/config/alis/config.json" | cut -d' ' -f1)"
bash "$helper" --dry-run > "$tmp/dry" || fail 'safe preview'
[[ -L "$wants/alis.service" && ! -e "$wants/inir.service" ]] || fail 'dry run modified wiring'
if bash "$helper" --apply > "$tmp/denied" 2>&1; then fail 'missing owner approval accepted'; fi
[[ "$(cat "$HOME/state-alis")" == active ]] || fail 'consent refusal mutated service'
if FAIL_LEGACY_START=1 bash "$helper" --apply --owner-approved > "$tmp/fail" 2>&1; then
  fail 'legacy start error incorrectly accepted'
fi
[[ "$(cat "$HOME/state-inir")" == inactive && "$(cat "$HOME/state-alis")" == active ]] ||
  fail 'failed legacy start did not restore Alis'
[[ -L "$wants/alis.service" && ! -e "$wants/inir.service" ]] ||
  fail 'failed old startup lost Alis wiring'
bash "$helper" --apply --owner-approved > "$tmp/ok" || fail 'approved rollback'
[[ "$(cat "$HOME/state-inir")" == active && "$(cat "$HOME/state-alis")" == inactive ]] ||
  fail 'two owners after successful rollback'
[[ -L "$wants/inir.service" && ! -e "$wants/alis.service" ]] ||
  fail 'old compositor link not restored'
[[ -f "$HOME/config/systemd/user/alis.service" ]] || fail 'Alis unit deleted'
[[ "$(sha256sum "$HOME/config/alis/config.json" | cut -d' ' -f1)" == "$data_hash" ]] ||
  fail 'settings mutated'
if bash "$helper" --apply --owner-approved > "$tmp/again" 2>&1; then
  fail 'second rollback accepted without Alis owner'
fi
echo 'PASS: consent, dry run, exclusive owner rollback, failed start recovery, byte-preserved settings'
