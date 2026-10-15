#!/usr/bin/env bash
# Offline AUDIO-I01 drop-in contract, no real user systemd or PipeWire touched.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
manager="$root/scripts/audio/easyeffects-autostart-guard.sh"
source_file="$root/assets/systemd/90-alis-audio-i01-easyeffects-autostart.conf"
bash -n "$manager"
grep -Fxq 'After=pipewire.service wireplumber.service' "$source_file"
grep -Fxq 'Environment="PIPEWIRE_PROPS={ node.lock-quantum = true }"' "$source_file"
sandbox="$(mktemp -d)"
trap 'rm -rf -- "$sandbox"' EXIT
export XDG_CONFIG_HOME="$sandbox/config"
unit='app-com.github.wwmm.easyeffects@autostart.service'
desktop="$XDG_CONFIG_HOME/autostart/com.github.wwmm.easyeffects.desktop"
target="$XDG_CONFIG_HOME/systemd/user/$unit.d/90-alis-audio-i01-quantum.conf"
mkdir -p "$(dirname "$desktop")"
# Installer integration must use the installed runtime helper without
# implicitly enabling EasyEffects as an autostart application.
installer="$root/sdata/subcmd-install/3.files.sh"
grep -Fq '"$_alis_ee_guard" prepare' "$installer"
grep -Fq 'ALIS_AUDIO_I01_AUTOSTART_GUARD:-1' "$installer"
mkdir -p "$sandbox/bin"
printf '#!/bin/sh\nexit 0\n' > "$sandbox/bin/easyeffects"
chmod +x "$sandbox/bin/easyeffects"
PATH="$sandbox/bin:$PATH" "$manager" prepare >/dev/null
cmp -s "$source_file" "$target"
[[ ! -e "$desktop" ]] || { echo 'prepare unexpectedly created autostart' >&2; exit 1; }
"$manager" disable >/dev/null
if "$manager" enable >/dev/null 2>&1; then echo 'Enabled without autostart entry' >&2; exit 1; fi
[[ ! -e "$target" ]]
printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Exec=flatpak run com.github.wwmm.easyeffects' > "$desktop"
if "$manager" enable >/dev/null 2>&1; then echo 'Decorated untested Flatpak autostart' >&2; exit 1; fi
PATH="$sandbox/bin:$PATH" "$manager" prepare | grep -Fq 'preserving it without changes'
[[ ! -e "$target" ]] || { echo 'Prepared foreign autostart' >&2; exit 1; }
printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Exec=easyeffects --hide-window --service-mode' > "$desktop"
PATH="$sandbox/bin:$PATH" "$manager" prepare >/dev/null
cmp -s "$source_file" "$target"
"$manager" disable >/dev/null
"$manager" status | grep -Fq 'disabled'
"$manager" enable >/dev/null
cmp -s "$source_file" "$target"
"$manager" status | grep -Fq 'installed'
"$manager" enable | grep -Fq 'already enabled'
"$manager" disable >/dev/null
[[ ! -e "$target" ]]
"$manager" disable | grep -Fq 'already disabled'
printf '%s\n' 'user owned' > "$target"
if "$manager" enable >/dev/null 2>&1; then echo 'Overwrote foreign drop-in' >&2; exit 1; fi
if "$manager" disable >/dev/null 2>&1; then echo 'Deleted foreign drop-in' >&2; exit 1; fi
grep -Fxq 'user owned' "$target"
rm -- "$target"
ln -s "$source_file" "$target"
if "$manager" enable >/dev/null 2>&1; then echo 'Overwrote symlink' >&2; exit 1; fi
if "$manager" disable >/dev/null 2>&1; then echo 'Deleted symlink' >&2; exit 1; fi
[[ -L "$target" ]]
if "$manager" unknown >/dev/null 2>&1; then echo 'Unknown operation accepted' >&2; exit 1; fi
printf '%s\n' 'AUDIO_I01_AUTOSTART_DROPIN_PASS'
