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
printf '#!/bin/sh\n# Canonical CLI and runtime name is Alis.\nexit 0\n' > "$tmp/home/.local/bin/alis"
printf '#!/bin/sh\nexit 0\n' > "$tmp/home/.local/bin/cargo"
chmod +x "$tmp/root/native/scripts/install-runtime.sh" "$tmp/home/.local/bin/"*
export HOME="$tmp/home" XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state" XDG_DATA_HOME="$HOME/.local/share"
export PATH="$HOME/.local/bin:$PATH"
helper="$tmp/root/scripts/brand-canonical-stage.sh"
hash1="$(sha256sum "$HOME/.config/inir/config.json" | cut -d' ' -f1)"
hash2="$(sha256sum "$HOME/.local/state/quickshell/user/first_run.txt" | cut -d' ' -f1)"
bash -n "$helper"
preview="$(bash "$helper" --dry-run 2>&1)" || { printf 'Stage preview failed:\n%s\n' "$preview" >&2; fail 'dry run'; }
grep -Fq DRY-RUN <<< "$preview" || { printf 'Unexpected stage preview:\n%s\n' "$preview" >&2; fail 'dry run output'; }
[[ ! -e "$HOME/.config/quickshell/alis" ]] || fail 'dry-run mutated runtime'
if bash "$helper" --apply >/dev/null 2>&1; then fail 'unapproved apply succeeded'; fi
bash "$helper" --apply --owner-approved | grep -Fq 'STAGED:' || fail 'explicit staging failed'
[[ -x "$HOME/.config/quickshell/alis/native/bin/alis-native" ]] || fail 'native runtime missing'
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
