#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$repo/scripts/repair-niri-alis-keybinds.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" XDG_BIN_HOME="$tmp/home/.local/bin"
mkdir -p "$XDG_BIN_HOME" "$XDG_CONFIG_HOME/niri/config.d"
printf '#!/bin/sh\nexit 0\n' > "$XDG_BIN_HOME/alis"
chmod +x "$XDG_BIN_HOME/alis"
root="$XDG_CONFIG_HOME/niri/config.kdl"
binds="$XDG_CONFIG_HOME/niri/config.d/70-binds.kdl"
overrides="$XDG_CONFIG_HOME/niri/config.d/75-inir-launcher-binds.kdl"
startup="$XDG_CONFIG_HOME/niri/config.d/50-startup.kdl"
cat > "$root" <<'KDL'
include "config.d/70-binds.kdl"
include "config.d/75-inir-launcher-binds.kdl"
include "config.d/50-startup.kdl"
KDL
cat > "$binds" <<'KDL'
binds {
    Mod+Return { spawn "inir" "terminal"; }
    Mod+Q repeat=false { spawn "inir" "close-window"; }
    Super+E { spawn "nautilus"; }
    Mod+D { maximize-column; }
}
KDL
cat > "$overrides" <<'KDL'
binds {
    Mod+Return { spawn "/bin/sh" "-c" "PATH=\"${XDG_BIN_HOME:-$HOME/.local/bin}:$PATH\"; exec inir \"$@\"" "inir-keybind" "terminal"; }
    Mod+Q repeat=false { spawn "/bin/sh" "-c" "PATH=\"${XDG_BIN_HOME:-$HOME/.local/bin}:$PATH\"; exec inir \"$@\"" "inir-keybind" "close-window"; }
}
KDL
cat > "$startup" <<'KDL'
spawn-at-startup "inir" "input-method" "start"
KDL
cp "$overrides" "$tmp/original"
bash -n "$helper" || fail "helper syntax"
bash "$helper" || fail "repair failed"
grep -Fq "spawn \"$XDG_BIN_HOME/alis\" \"terminal\"" "$binds" || fail "Super+Enter"
grep -Fq "spawn \"$XDG_BIN_HOME/alis\" \"close-window\"" "$binds" || fail "Super+Q"
grep -Fq 'Super+E { spawn "nautilus"; }' "$binds" || fail "changed native Super+E"
grep -Fq 'Mod+D { maximize-column; }' "$binds" || fail "changed native Mod+D"
grep -Fq 'exec alis \"$@\"' "$overrides" || fail "stale 75-inir wrapper"
grep -Fq '"alis-keybind"' "$overrides" || fail "stale 75 shim"
grep -Fq "spawn-at-startup \"$XDG_BIN_HOME/alis\"" "$startup" || fail "legacy startup"
cmp "$tmp/original" "$overrides.brand-cli.bak" || fail "backup not lossless"
sha_before="$(sha256sum "$binds" "$overrides" "$startup")"
bash "$helper" || fail "idempotent repair failed"
[[ "$sha_before" == "$(sha256sum "$binds" "$overrides" "$startup")" ]] || fail "second run changed bytes"
rm "$overrides"
if bash "$helper" >/dev/null 2>&1; then fail "missing include silently ignored"; fi
[[ "$(grep -Fc 'scripts/repair-niri-alis-keybinds.sh' "$repo/setup")" -eq 2 ]] || fail "both update branches not covered"
echo 'PASS: safe hotkeys repair including 75-inir override'
