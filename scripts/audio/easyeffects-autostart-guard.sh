#!/usr/bin/env bash
# AUDIO-I01: manage only Alis' drop-in for the generated native EasyEffects XDG autostart.
set -euo pipefail
if (( $# != 1 )); then
    printf '%s\n' 'Usage: easyeffects-autostart-guard.sh {enable|status|disable}' >&2
    exit 64
fi
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
source_file="$repo_root/assets/systemd/90-alis-audio-i01-easyeffects-autostart.conf"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
desktop="$config_home/autostart/com.github.wwmm.easyeffects.desktop"
unit='app-com.github.wwmm.easyeffects@autostart.service'
target_dir="$config_home/systemd/user/$unit.d"
target="$target_dir/90-alis-audio-i01-quantum.conf"

if [[ ! -f "$source_file" || -L "$source_file" ]]; then
    printf 'AUDIO-I01: missing managed source: %s\n' "$source_file" >&2
    exit 66
fi
is_managed() {
    [[ -f "$target" && ! -L "$target" ]] && cmp -s -- "$source_file" "$target"
}
case "$1" in
    enable)
        if [[ ! -f "$desktop" || -L "$desktop" ]] ||
           ! grep -Eq '^Exec=(/usr/bin/)?easyeffects --hide-window --service-mode[[:space:]]*$' "$desktop"; then
            printf 'AUDIO-I01: expected native EasyEffects XDG autostart command not found: %s\n' "$desktop" >&2
            exit 65
        fi
        if [[ -e "$target" || -L "$target" ]]; then
            if is_managed; then
                printf 'AUDIO-I01 autostart drop-in already enabled: %s\n' "$target"
                exit 0
            fi
            printf 'AUDIO-I01: refusing to overwrite foreign/modified drop-in: %s\n' "$target" >&2
            exit 73
        fi
        mkdir -p -- "$target_dir"
        tmp="$(mktemp "${target}.tmp.XXXXXXXX")"
        trap 'rm -f -- "$tmp"' EXIT
        install -m 0644 -- "$source_file" "$tmp"
        if [[ -e "$target" || -L "$target" ]]; then
            printf 'AUDIO-I01: destination appeared concurrently: %s\n' "$target" >&2
            exit 73
        fi
        mv -T -- "$tmp" "$target"
        trap - EXIT
        printf 'AUDIO-I01 autostart drop-in enabled: %s\n' "$target"
        printf '%s\n' 'Run: systemctl --user daemon-reload; log out and back in to test.'
        ;;
    status)
        if [[ ! -e "$target" && ! -L "$target" ]]; then
            printf 'AUDIO-I01 autostart drop-in: disabled (%s)\n' "$target"
        elif is_managed; then
            printf 'AUDIO-I01 autostart drop-in: installed (%s)\n' "$target"
        else
            printf 'AUDIO-I01 autostart drop-in: foreign/modified, untouched (%s)\n' "$target"
            exit 73
        fi
        ;;
    disable)
        if [[ ! -e "$target" && ! -L "$target" ]]; then
            printf 'AUDIO-I01 autostart drop-in already disabled: %s\n' "$target"
            exit 0
        fi
        if ! is_managed; then
            printf 'AUDIO-I01: refusing to delete foreign/modified drop-in: %s\n' "$target" >&2
            exit 73
        fi
        rm -- "$target"
        printf 'AUDIO-I01 autostart drop-in disabled: %s\n' "$target"
        printf '%s\n' 'Run: systemctl --user daemon-reload; log out and back in to compare.'
        ;;
    *)
        printf '%s\n' 'Usage: easyeffects-autostart-guard.sh {enable|status|disable}' >&2
        exit 64
        ;;
esac
