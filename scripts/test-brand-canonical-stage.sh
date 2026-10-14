#!/usr/bin/env bash
# Isolated offline staging test: mock Cargo/runtime copy, no real service actions.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
fail() { echo "FAIL: canonical offline stage: $*" >&2; exit 1; }
mkdir -p "$tmp/root/scripts" "$tmp/root/sdata/lib" "$tmp/root/native/scripts" \
    "$tmp/root/assets/systemd" "$tmp/home/.local/bin" \
    "$tmp/home/.config/inir" "$tmp/home/.config/systemd/user" \
    "$tmp/home/.local/state/quickshell/user"
cp "$repo/scripts/brand-canonical-stage.sh" "$tmp/root/scripts/brand-canonical-stage.sh"
printf '%s\n' '//@ pragma ShellId alis' > "$tmp/root/shell.qml"
printf '%s\n' '# Canonical CLI and runtime name is Alis.' > "$tmp/root/scripts/alis"
printf '%s\n' 'BusName=org.kde.StatusNotifierWatcher' > "$tmp/root/assets/systemd/alis.service"
printf '%s\n' '[Service]' > "$tmp/home/.config/systemd/user/inir.service"
printf 'unmodified preferences' > "$tmp/home/.config/inir/config.json"
printf 'unmodified first run' > "$tmp/home/.local/state/quickshell/user/first_run.txt"
cat > "$tmp/root/sdata/lib/runtime-payload.py" <<'PY'
from pathlib import Path
import sys
args=sys.argv
dst=Path(args[args.index('--target')+1])
for filename in ('shell.qml','qmldir','setup','modules/common/Config.qml'):
    p=dst/filename
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text('//@ pragma ShellId alis\n' if filename=='shell.qml' else 'fixture\n')
PY
cat > "$tmp/root/native/scripts/install-runtime.sh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == --dest ]]
mkdir -p "$2"
for bin in alis-inputd alis-mpdd alis-native alis-theme; do
    printf '#!/bin/sh\nexit 0\n' > "$2/$bin"; chmod +x "$2/$bin"
done
MOCK
cat > "$tmp/home/.local/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
[[ "${1:-}" == --user && "${2:-}" == is-active ]] || exit 2
[[ "${3:-}" != alis.service ]] || echo inactive
[[ "${3:-}" != inir.service ]] || echo active
MOCK
cat > "$tmp/home/.local/bin/alis" <<'LEGACY'
#!/usr/bin/env bash
# Alis is the public command while the proven iNiR runtime owns the session.
script_dir="$(dirname -- "${BASH_SOURCE[0]}")"
export ALIS_INTERNAL_CLI=1
if [[ -f "$script_dir/inir" ]]; then
    exec bash "$script_dir/inir" "$@"
fi
exec inir "$@"
LEGACY
printf '#!/bin/sh\nexit 0\n' > "$tmp/home/.local/bin/cargo"
chmod +x "$tmp/root/native/scripts/install-runtime.sh" "$tmp/home/.local/bin/"*
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state" XDG_DATA_HOME="$HOME/.local/share"
export PATH="$HOME/.local/bin:$PATH"
helper="$tmp/root/scripts/brand-canonical-stage.sh"
hash1="$(sha256sum "$HOME/.config/inir/config.json" | cut -d' ' -f1)"
hash2="$(sha256sum "$HOME/.local/state/quickshell/user/first_run.txt" | cut -d' ' -f1)"
legacy_hash="$(sha256sum "$HOME/.local/bin/alis" | cut -d' ' -f1)"
bash -n "$helper"
preview="$(bash "$helper" --dry-run 2>&1)" || { printf 'Stage preview failed:\n%s\n' "$preview" >&2; fail 'dry run'; }
grep -Fq DRY-RUN <<< "$preview" || { printf 'Unexpected stage preview:\n%s\n' "$preview" >&2; fail 'dry run output'; }
[[ ! -e "$HOME/.config/quickshell/alis" ]] || fail 'dry-run mutated runtime'
cp "$HOME/.local/bin/alis" "$tmp/original-wrapper"
printf '#!/usr/bin/env bash\n# foreign command\n' > "$HOME/.local/bin/alis"
chmod +x "$HOME/.local/bin/alis"
if bash "$helper" --dry-run >/dev/null 2>&1; then fail 'foreign launcher accepted'; fi
cmp -s "$HOME/.local/bin/alis" <(printf '#!/usr/bin/env bash\n# foreign command\n') ||
    fail 'foreign launcher modified'
cp "$tmp/original-wrapper" "$HOME/.local/bin/alis"
ln -s "$HOME/.local/bin/alis" "$tmp/external-alis"
# An existing symlink at the launcher path must never be followed.
mv "$HOME/.local/bin/alis" "$tmp/wrapper-for-link"
ln -s "$tmp/wrapper-for-link" "$HOME/.local/bin/alis"
if bash "$helper" --dry-run >/dev/null 2>&1; then fail 'symlink launcher accepted'; fi
rm -- "$HOME/.local/bin/alis"
mv "$tmp/wrapper-for-link" "$HOME/.local/bin/alis"
if bash "$helper" --apply >/dev/null 2>&1; then fail 'unapproved apply succeeded'; fi
applied="$(bash "$helper" --apply --owner-approved 2>&1)" ||
    { printf 'Stage apply failed:\n%s\n' "$applied" >&2; fail 'explicit staging'; }
grep -Fq 'STAGED:' <<< "$applied" || fail 'explicit staging lacked installed runtime'
[[ -x "$HOME/.config/quickshell/alis/native/bin/alis-native" ]] || fail 'native runtime missing'
grep -Fq '# Canonical CLI and runtime name is Alis.' "$HOME/.local/bin/alis" ||
    fail 'legacy Alis wrapper was not replaced by canonical CLI'
backups=("$HOME"/.local/state/alis-cutover-backups/launcher-*/alis)
[[ "${#backups[@]}" == 1 && -f "${backups[0]}" ]] ||
    fail 'original Alis wrapper backup was not retained'
[[ "$(sha256sum "${backups[0]}" | cut -d' ' -f1)" == "$legacy_hash" ]] ||
    fail 'backed-up legacy launcher bytes changed'
backups_before="$(find "$HOME/.local/state/alis-cutover-backups" -type f -name alis | wc -l)"
again="$(bash "$helper" --apply --owner-approved 2>&1)" ||
    { printf 'Repeat stage failed:\n%s\n' "$again" >&2; fail 'idempotent stage'; }
grep -Fq 'ALREADY STAGED' <<< "$again" || fail 'repeat staging should be idempotent'
[[ "$(find "$HOME/.local/state/alis-cutover-backups" -type f -name alis | wc -l)" == "$backups_before" ]] ||
    fail 'idempotent stage duplicated legacy launcher backup'
# A previously canonical user launcher can still be older than the current
# repo. Only an approved refresh may replace it, after a verified backup.
printf '\n# previous canonical source revision\n' >> "$HOME/.local/bin/alis"
stale_hash="$(sha256sum "$HOME/.local/bin/alis" | cut -d' ' -f1)"
preview_stale="$(bash "$helper" --dry-run)" || fail 'canonical-stale preview'
[[ "$preview_stale" == *"canonical-stale"* ]] || fail 'missed stale canonical launcher'
[[ "$(sha256sum "$HOME/.local/bin/alis" | cut -d' ' -f1)" == "$stale_hash" ]] ||
    fail 'preview modified canonical launcher'
bash "$helper" --apply --owner-approved > "$tmp/stale-refresh.log" || fail 'stale canonical CLI refresh'
cmp -s "$HOME/.local/bin/alis" "$tmp/root/scripts/alis" || fail 'stale CLI not refreshed'
[[ "$(find "$HOME/.local/state/alis-cutover-backups" -type f -name alis | wc -l)" == 2 ]] ||
    fail 'original canonical launcher was not archived'
if ! grep -l 'previous canonical source revision' "$HOME"/.local/state/alis-cutover-backups/launcher-*/alis >/dev/null; then
    fail 'stale source backup does not match previous canonical CLI'
fi
[[ -f "$HOME/.config/systemd/user/inir.service" ]] || fail 'original service lost'
[[ "$(sha256sum "$HOME/.config/inir/config.json" | cut -d' ' -f1)" == "$hash1" ]] || fail 'preferences mutated'
[[ "$(sha256sum "$HOME/.local/state/quickshell/user/first_run.txt" | cut -d' ' -f1)" == "$hash2" ]] || fail 'first run reset'
bash "$helper" --dry-run | grep -Fq 'ALREADY STAGED' || fail 'complete stage not idempotent'
rm "$HOME/.config/quickshell/alis/native/bin/alis-native"
if bash "$helper" --apply --owner-approved >/dev/null 2>&1; then fail 'partial runtime overwrite'; fi
rm -rf "$HOME/.config/quickshell/alis"
echo '{"installMode":"package-managed"}' > "$HOME/.config/inir/version.json"
if bash "$helper" --apply --owner-approved >/dev/null 2>&1; then fail 'package-manager guard'; fi
[[ ! -e "$HOME/.config/quickshell/alis" ]] || fail 'package-manager guard wrote runtime'
echo 'PASS: offline stage consent, native payload, no service switch, user bytes unchanged, no collisions'
