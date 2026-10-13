#!/usr/bin/env bash
# R10 audit must be read-only and fail closed on two active shell services.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
fail() { printf 'FAIL: owner audit: %s\n' "$*" >&2; exit 1; }
mkdir -p "$stage/bin" "$stage/config/inir" "$stage/state/quickshell/user"
printf 'do not touch preferences\n' > "$stage/config/inir/config.json"
printf 'wizard already complete\n' > "$stage/state/quickshell/user/first_run.txt"
cat > "$stage/bin/alis" <<'CLI'
#!/usr/bin/env bash
printf 'Alis test version\n'
CLI
cat > "$stage/bin/systemctl" <<'UNIT'
#!/usr/bin/env bash
case "$*" in
  *alis.service*)
    if [[ "$*" == *--value* ]]; then printf '%s\n' "${MOCK_ALIS_STATE:-inactive}"; else printf 'ActiveState=%s\n' "${MOCK_ALIS_STATE:-inactive}"; fi ;;
  *inir.service*)
    if [[ "$*" == *--value* ]]; then printf 'active\n'; else printf 'ActiveState=active\nMainPID=1234\n'; fi ;;
  *) printf 'Unexpected user unit query\n' >&2; exit 90 ;;
esac
UNIT
chmod 755 "$stage/bin/alis" "$stage/bin/systemctl"
export HOME="$stage/home" XDG_CONFIG_HOME="$stage/config" XDG_STATE_HOME="$stage/state"
export XDG_DATA_HOME="$stage/data" XDG_CACHE_HOME="$stage/cache"
export PATH="$stage/bin:$PATH"
MOCK_ALIS_STATE=inactive bash "$repo/scripts/brand-owner-audit.sh" > "$stage/ok.log" ||
    fail 'read-only audit failed on one active legacy owner'
if MOCK_ALIS_STATE=active bash "$repo/scripts/brand-owner-audit.sh" > "$stage/bad.log"; then
    fail 'read-only audit accepted two active session services'
else
    status="$?"
    [[ "$status" == 2 ]] || fail "expected explicit session collision exit 2, got $status"
fi
grep -Fq 'BLOCKER: inir.service and alis.service are BOTH active' "$stage/bad.log" ||
    fail 'two-service safety warning absent'
[[ "$(cat "$stage/config/inir/config.json")" == 'do not touch preferences' ]] ||
    fail 'owner configuration changed by audit'
[[ "$(cat "$stage/state/quickshell/user/first_run.txt")" == 'wizard already complete' ]] ||
    fail 'First Run marker changed by audit'
printf 'PASS: owner audit is read-only and blocks two active shell services\n'
