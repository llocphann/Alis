#!/usr/bin/env bash
# No owner keyring touched. Exercise actual lookup script using fake secret-tool.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
lookup="$root/scripts/keyring/try_lookup.sh"
qml="$root/services/deferred/KeyringStorage.qml"
fail() { printf 'FAIL: Alis keyring migration: %s\n' "$*" >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
cat > "$tmp/secret-tool" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == lookup && "$2" == application ]] || exit 2
case "$3" in
    alis) [[ -n "${MOCK_NEW:-}" ]] && printf '%s\n' "$MOCK_NEW" ;;
    illogical-impulse) [[ -n "${MOCK_OLD:-}" ]] && printf '%s\n' "$MOCK_OLD" ;;
    *) exit 2 ;;
esac
exit 0
MOCK
chmod 755 "$tmp/secret-tool"
bash -n "$lookup" || fail 'invalid lookup script'
grep -Fq '"application": "alis"' "$qml" ||
    fail 'new secrets would still write under upstream identity'
grep -Fq 'Translation.tr("%1 Safe Storage").arg("Alis")' "$qml" ||
    fail 'settings still show the old keyring label'
actual="$(PATH="$tmp:$PATH" MOCK_OLD='{"token":"untouched-old"}' MOCK_NEW= bash "$lookup")"
[[ "$actual" == '{"token":"untouched-old"}' ]] ||
    fail 'old secrets are not readable as fallback'
actual="$(PATH="$tmp:$PATH" MOCK_NEW='{"token":"current"}' MOCK_OLD='{"token":"untouched-old"}' bash "$lookup")"
[[ "$actual" == '{"token":"current"}' ]] ||
    fail 'new Alis secret did not take priority'
[[ "$(grep -Fc "secret-tool lookup 'application' 'illogical-impulse'" "$lookup")" == 1 ]] ||
    fail 'historical fallback removed'
echo 'PASS: new Alis keyring identity with safe old-secret read fallback'
