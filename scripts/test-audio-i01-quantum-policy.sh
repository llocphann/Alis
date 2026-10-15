#!/usr/bin/env bash
# No PipeWire daemon, EasyEffects process, or user configuration is touched.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
script="$root/scripts/audio/easyeffects-quantum-policy.sh"
source_file="$root/assets/pipewire/90-alis-easyeffects-quantum.conf"
case "$(cat "$source_file")" in *'node.name = "~ee_soe_.*"'*'node.lock-quantum = true'*) : ;; *) echo "Invalid node rule" >&2; exit 1 ;; esac
bash -n "$script"
dir="$(mktemp -d)"
trap 'rm -rf -- "$dir"' EXIT
export XDG_CONFIG_HOME="$dir"
target="$dir/pipewire/pipewire.conf.d/90-alis-easyeffects-quantum.conf"
"$script" status | grep -Fq 'disabled'
"$script" enable >/dev/null
cmp -s "$source_file" "$target"
"$script" enable | grep -Fq 'already installed'
"$script" status | grep -Fq 'installed'
"$script" disable >/dev/null
"$script" disable | grep -Fq 'already disabled'
[[ ! -e "$target" ]]
printf '%s\n' '# User-owned file' > "$target"
if "$script" enable >/dev/null 2>&1; then echo 'Foreign overwrite allowed' >&2; exit 1; fi
if "$script" disable >/dev/null 2>&1; then echo 'Foreign deletion allowed' >&2; exit 1; fi
grep -Fxq '# User-owned file' "$target"
rm -- "$target"
ln -s "$source_file" "$target"
if "$script" enable >/dev/null 2>&1; then echo 'Symlink overwrite allowed' >&2; exit 1; fi
if "$script" disable >/dev/null 2>&1; then echo 'Symlink deletion allowed' >&2; exit 1; fi
[[ -L "$target" ]]
if "$script" other >/dev/null 2>&1; then echo 'Invalid verb succeeded' >&2; exit 1; fi
printf '%s\n' 'AUDIO_I01_PIPEWIRE_POLICY_PASS'
