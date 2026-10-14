#!/usr/bin/env bash
# R10 audit is read-only and rejects the wrong or duplicate session owner.
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
    state="${MOCK_ALIS_STATE:-inactive}"
    if [[ "$*" == *--value* ]]; then printf '%s\n' "$state"; else printf 'ActiveState=%s\n' "$state"; fi ;;
  *inir.service*)
    state="${MOCK_INIR_STATE:-inactive}"
    if [[ "$*" == *--value* ]]; then printf '%s\n' "$state"; else printf 'ActiveState=%s\n' "$state"; fi ;;
  *) printf 'Unexpected user unit query\n' >&2; exit 90 ;;
esac
UNIT
chmod 755 "$stage/bin/alis" "$stage/bin/systemctl"
export HOME="$stage/home" XDG_CONFIG_HOME="$stage/config" XDG_STATE_HOME="$stage/state"
export XDG_DATA_HOME="$stage/data" XDG_CACHE_HOME="$stage/cache"
export PATH="$stage/bin:$PATH"

case_expected=inir
if grep -Fxq '//@ pragma ShellId alis' "$repo/shell.qml"; then
    case_expected=alis
elif ! grep -Fxq '//@ pragma ShellId inir' "$repo/shell.qml"; then
    fail 'cannot identify checked-out ShellId'
fi

assert_result() {
    local name="$1" old="$2" new="$3" code="$4" needle="$5" rc=0
    MOCK_INIR_STATE="$old" MOCK_ALIS_STATE="$new" \
        bash "$repo/scripts/brand-owner-audit.sh" > "$stage/$name.log" || rc=$?
    [[ "$rc" == "$code" ]] || fail "$name: exit $rc, expected $code"
    grep -Fq "$needle" "$stage/$name.log" || fail "$name: missing diagnostic: $needle"
    [[ "$(cat "$stage/config/inir/config.json")" == 'do not touch preferences' ]] ||
        fail "$name: modified user preferences"
    [[ "$(cat "$stage/state/quickshell/user/first_run.txt")" == 'wizard already complete' ]] ||
        fail "$name: modified wizard marker"
}
assert_result duplicate active active 2 'BLOCKER: inir.service and alis.service are BOTH active'
assert_result absent inactive inactive 2 'BLOCKER:'
if [[ "$case_expected" == alis ]]; then
    assert_result canonical active inactive 2 'canonical ShellId alis requires alis.service active'
    assert_result canonical_ok inactive active 0 'Session ownership (expected ShellId and sole unit: alis)'
else
    assert_result compatible inactive active 2 'compatibility ShellId inir requires inir.service active'
    assert_result compatible_ok active inactive 0 'Session ownership (expected ShellId and sole unit: inir)'
fi
printf 'PASS: R10 audit is read-only; correct owner accepted, missing/wrong/duplicate owners refused (%s)\n' "$case_expected"
