#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
root_config="$repo_root/defaults/niri/config.kdl"
binds="$repo_root/defaults/niri/config.d/70-binds.kdl"
overrides="$repo_root/defaults/niri/config.d/75-alis-launcher-binds.kdl"
migration="$repo_root/sdata/migrations/040-niri-inir-keybind-path.sh"
repair="$repo_root/scripts/repair-niri-alis-keybinds.sh"

fail() {
    printf 'FAIL: Niri keybind launcher contract: %s\n' "$1" >&2
    exit 1
}

for file in "$root_config" "$binds" "$overrides" "$migration" "$repair"; do
    [[ -f "$file" ]] || fail "missing ${file#"$repo_root/"}"
done

# Niri evaluates included fragments in order. The path-safe Alis bindings must
# override the managed 70-binds entries while 90-user-extra remains last so user
# customizations retain final precedence.
python3 - "$root_config" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
needles = [
    'include "config.d/70-binds.kdl"',
    'include "config.d/75-alis-launcher-binds.kdl"',
    'include "config.d/80-layer-rules.kdl"',
    'include "config.d/90-user-extra.kdl"',
]
pos = [text.find(needle) for needle in needles]
if any(value < 0 for value in pos):
    raise SystemExit("FAIL: Niri launcher override include chain is incomplete")
if pos != sorted(pos):
    raise SystemExit("FAIL: Niri launcher override include order is incorrect")
PY

wrapper='spawn "/bin/sh" "-c" "PATH=\"${XDG_BIN_HOME:-$HOME/.local/bin}:$PATH\"; exec alis \"$@\"" "alis-keybind"'
if grep -Ev '^[[:space:]]*//' "$overrides" | grep -Eq 'spawn "(alis|inir)"|exec inir'; then
    fail 'launcher override contains a PATH-dependent bare command or a retired launcher'
fi
grep -Fq "$wrapper" "$overrides" \
    || fail 'launcher override file does not use the XDG_BIN_HOME-aware wrapper'
grep -Fq 'Mod+Q repeat=false' "$overrides" \
    || fail 'Mod+Q close-window override is missing'
grep -Fq '"close-window"; }' "$overrides" \
    || fail 'Mod+Q no longer routes to the close-window command'

# Keep the override layer mechanically equivalent to every managed Alis binding
# in 70-binds.kdl. This catches newly-added launcher-backed shortcuts that would
# otherwise reintroduce the same compositor-PATH failure.
python3 - "$binds" "$overrides" <<'PY'
from pathlib import Path
import sys

base = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
overrides = Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()
wrapper = 'spawn "/bin/sh" "-c" "PATH=\\"${XDG_BIN_HOME:-$HOME/.local/bin}:$PATH\\"; exec alis \\"$@\\"" "alis-keybind"'

def norm(line: str) -> str:
    return " ".join(line.strip().split())

expected = {
    norm(line.replace('spawn "alis"', wrapper))
    for line in base
    if 'spawn "alis"' in line and not line.lstrip().startswith("//")
}
actual = {
    norm(line)
    for line in overrides
    if wrapper in line and not line.lstrip().startswith("//")
}
missing = sorted(expected - actual)
extra = sorted(actual - expected)
if missing or extra:
    details = []
    if missing:
        details.append("missing overrides: " + " | ".join(missing))
    if extra:
        details.append("unexpected overrides: " + " | ".join(extra))
    raise SystemExit("FAIL: Alis launcher bind parity drift: " + "; ".join(details))
if not expected:
    raise SystemExit("FAIL: no managed Alis binds were discovered in 70-binds.kdl")
PY

# Exercise the exact shell lookup semantics with a deliberately restricted PATH.
# This proves the wrapper can find a developer launcher in ~/.local/bin even when
# the compositor environment itself cannot resolve `alis`.
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/home/.local/bin"
cat > "$tmp/home/.local/bin/alis" <<'SH'
#!/bin/sh
printf '%s\n' "$*"
SH
chmod +x "$tmp/home/.local/bin/alis"

result="$(HOME="$tmp/home" XDG_BIN_HOME= PATH=/usr/bin:/bin /bin/sh -c \
    'PATH="${XDG_BIN_HOME:-$HOME/.local/bin}:$PATH"; exec alis "$@"' \
    alis-keybind close-window)"
[[ "$result" == 'close-window' ]] \
    || fail 'fallback launcher lookup did not resolve ~/.local/bin/alis'

# Preserve migration 040's historical PATH repair. This is a pre-cutover input
# contract; the coordinated rebrand repair advances its output to Alis later.
legacy_wrapper='spawn "/bin/sh" "-c" "PATH=\"${XDG_BIN_HOME:-$HOME/.local/bin}:$PATH\"; exec inir \"$@\"" "inir-keybind"'
fixture="$tmp/config/niri/config.d/70-binds.kdl"
mkdir -p "$(dirname -- "$fixture")"
printf '%s\n' 'binds {' '  Mod+Q repeat=false { spawn "inir" "close-window"; }' '}' > "$fixture"
(
    export HOME="$tmp/home"
    export XDG_CONFIG_HOME="$tmp/config"
    export STY_RED='' STY_GREEN='' STY_RST=''
    # shellcheck source=/dev/null
    source "$migration"
    migration_check || fail 'migration does not detect a bare launcher bind'
    migration_apply
    ! migration_check || fail 'migration is not idempotent after repair'
)

grep -Fq "$legacy_wrapper" "$fixture" \
    || fail 'migration did not install the robust launcher wrapper'

# Older Niri installs can keep bindings directly in config.kdl. Exercise the
# migration through the real framework rather than calling migration_apply
# directly: the framework must back up the same monolithic file it mutates.
monolithic_root="$tmp/monolithic-config"
monolithic_fixture="$monolithic_root/niri/config.kdl"
mkdir -p "$(dirname -- "$monolithic_fixture")"
printf '%s\n' 'binds {' '  Mod+Q repeat=false { spawn "inir" "close-window"; }' '}' > "$monolithic_fixture"
cp -p "$monolithic_fixture" "$tmp/original-monolithic-config.kdl"
(
    export HOME="$tmp/home"
    export XDG_CONFIG_HOME="$monolithic_root"
    export REPO_ROOT="$repo_root"
    export STY_RED='' STY_GREEN='' STY_RST=''
    tui_dim() { :; }
    tui_check_ok() { :; }
    tui_check_fail() { :; }
    tui_info() { :; }
    # shellcheck source=/dev/null
    source "$repo_root/sdata/lib/migrations.sh"
    apply_migration '040-niri-inir-keybind-path' true
)

backup_file="$(find "$monolithic_root/alis/backups" -type f -name config.kdl -print -quit 2>/dev/null || true)"
[[ -n "$backup_file" && -f "$backup_file" ]] \
    || fail 'monolithic keybind migration did not back up config.kdl'
grep -Fq 'spawn "inir" "close-window"' "$backup_file" \
    || fail 'monolithic migration backup does not preserve the pre-migration bind'
cmp -s "$backup_file" "$tmp/original-monolithic-config.kdl" \
    || fail 'monolithic migration backup changed original config bytes'
if grep -Fq "$legacy_wrapper" "$backup_file"; then
    fail 'monolithic migration backup was captured after mutation'
fi
grep -Fq "$legacy_wrapper" "$monolithic_fixture" \
    || fail 'full migration framework did not repair monolithic config.kdl'

# The canonical handoff must repair both historical shapes without losing the
# original legacy-wrapper bytes. Repeat repair must leave backups unchanged.
printf '%s\n' 'include "config.d/70-binds.kdl"' > "$tmp/config/niri/config.kdl"
for config_root in "$tmp/config" "$monolithic_root"; do
    if [[ "$config_root" == "$tmp/config" ]]; then target="$fixture"; else target="$monolithic_fixture"; fi
    cp -p "$target" "$tmp/before-brand-repair.kdl"
    XDG_CONFIG_HOME="$config_root" XDG_BIN_HOME="$tmp/home/.local/bin" bash "$repair"
    grep -Fq "$wrapper" "$target" || fail 'canonical handoff did not replace the historical wrapper'
    cmp -s "$target.brand-cli.bak" "$tmp/before-brand-repair.kdl" \
        || fail 'canonical handoff did not preserve historical-wrapper bytes'
    cp -p "$target" "$tmp/after-brand-repair.kdl"
    XDG_CONFIG_HOME="$config_root" XDG_BIN_HOME="$tmp/home/.local/bin" bash "$repair"
    cmp -s "$target" "$tmp/after-brand-repair.kdl" || fail 'canonical wrapper repair is not idempotent'
    cmp -s "$target.brand-cli.bak" "$tmp/before-brand-repair.kdl" || fail 'repeat repair changed original backup'
done

printf 'PASS: Niri keybind launcher lookup contracts\n'
