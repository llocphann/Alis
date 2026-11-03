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
overrides="$XDG_CONFIG_HOME/niri/config.d/75-alis-launcher-binds.kdl"
startup="$XDG_CONFIG_HOME/niri/config.d/50-startup.kdl"
user_extra="$XDG_CONFIG_HOME/niri/config.d/90-user-extra.kdl"
cat > "$root" <<'KDL'
include "config.d/70-binds.kdl"
include "config.d/75-alis-launcher-binds.kdl"
include "config.d/50-startup.kdl"
include "config.d/90-user-extra.kdl"
KDL
cat > "$binds" <<'KDL'
binds {
    Mod+Return { spawn "alis" "terminal"; }
    Mod+Q repeat=false { spawn "alis" "close-window"; }
    Super+E { spawn "nautilus"; }
    Mod+D { maximize-column; }
}
KDL
cat > "$overrides" <<'KDL'
binds {
    Mod+Return { spawn "/bin/sh" "-c" "PATH=\"${XDG_BIN_HOME:-$HOME/.local/bin}:$PATH\"; exec alis \"$@\"" "alis-keybind" "terminal"; }
    Mod+Q repeat=false { spawn "/bin/sh" "-c" "PATH=\"${XDG_BIN_HOME:-$HOME/.local/bin}:$PATH\"; exec alis \"$@\"" "alis-keybind" "close-window"; }
}
KDL
cat > "$startup" <<'KDL'
spawn-at-startup "alis" "input-method" "start"
KDL
# This user's live config overrides 70-binds in the later 90 file.
# The repair must retain their yazi argument, hotkeys and unrelated commands.
cat > "$user_extra" <<'KDL'
binds {
    Mod+Return { spawn "/home/owner/.local/bin/alis" "terminal"; }
    Super+E { spawn "/home/owner/.local/bin/alis" "terminal" "yazi"; }
    Mod+P { spawn "custom-app" "--flag"; }
    // Old alis path is only mentioned in this comment.
}
KDL
cp "$user_extra" "$tmp/original-user-extra"
cp "$overrides" "$tmp/original"
bash -n "$helper" || fail "helper syntax"
bash "$helper" || fail "repair failed"
grep -Fq "spawn \"$XDG_BIN_HOME/alis\" \"terminal\"" "$binds" || fail "Super+Enter"
grep -Fq "spawn \"$XDG_BIN_HOME/alis\" \"close-window\"" "$binds" || fail "Super+Q"
grep -Fq 'Super+E { spawn "nautilus"; }' "$binds" || fail "changed native Super+E"
grep -Fq 'Mod+D { maximize-column; }' "$binds" || fail "changed native Mod+D"
grep -Fq 'exec alis \"$@\"' "$overrides" || fail "stale 75-alis wrapper"
grep -Fq '"alis-keybind"' "$overrides" || fail "stale 75 shim"
grep -Fq "spawn-at-startup \"$XDG_BIN_HOME/alis\"" "$startup" || fail "legacy startup"
grep -Fq 'Mod+Return { spawn "/home/owner/.local/bin/alis" "terminal"; }' "$user_extra" || fail "90 override Super+Enter still uses alis"
grep -Fq 'Super+E { spawn "/home/owner/.local/bin/alis" "terminal" "yazi"; }' "$user_extra" || fail "90 override Super+E/yazi was lost"
grep -Fq 'Mod+P { spawn "custom-app" "--flag"; }' "$user_extra" || fail "foreign user bind was changed"
cmp "$tmp/original" "$overrides.brand-cli.bak" || fail "backup not lossless"
cmp "$tmp/original-user-extra" "$user_extra.brand-cli.bak" || fail "custom override backup not lossless"
sha_before="$(sha256sum "$binds" "$overrides" "$startup" "$user_extra")"
bash "$helper" || fail "idempotent repair failed"
[[ "$sha_before" == "$(sha256sum "$binds" "$overrides" "$startup" "$user_extra")" ]] || fail "second run changed bytes"
rm "$overrides"
if bash "$helper" >/dev/null 2>&1; then fail "missing include silently ignored"; fi
[[ "$(grep -Fc 'scripts/repair-niri-alis-keybinds.sh' "$repo/setup")" -eq 2 ]] || fail "both update branches not covered"
echo 'PASS: safe hotkeys repair including 75 and custom 90 overrides'
