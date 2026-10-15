#!/usr/bin/env bash
# Manage AUDIO-I01 per-user PipeWire node rule. Never restart the audio server.
set -euo pipefail

if (( $# != 1 )); then
    printf '%s\n' 'Usage: easyeffects-quantum-policy.sh {enable|disable|status}' >&2
    exit 64
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/../.." && pwd -P)"
source_file="${repo_root}/assets/pipewire/90-alis-easyeffects-quantum.conf"
config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
target_dir="${config_home}/pipewire/pipewire.conf.d"
target="${target_dir}/90-alis-easyeffects-quantum.conf"

if [[ ! -f "$source_file" || -L "$source_file" ]]; then
    printf 'AUDIO-I01: missing or invalid policy source: %s\n' "$source_file" >&2
    exit 66
fi

is_owned() {
    [[ -f "$target" && ! -L "$target" ]] && cmp -s -- "$source_file" "$target"
}

case "$1" in
    status)
        if [[ ! -e "$target" && ! -L "$target" ]]; then
            printf 'AUDIO-I01 policy: disabled (%s)\n' "$target"
        elif is_owned; then
            printf 'AUDIO-I01 policy: installed; re-login/restart PipeWire required after any change (%s)\n' "$target"
        else
            printf 'AUDIO-I01 policy: existing foreign or modified file, untouched (%s)\n' "$target"
            exit 73
        fi
        ;;
    enable)
        if [[ -e "$target" || -L "$target" ]]; then
            if is_owned; then
                printf 'AUDIO-I01 policy already installed: %s\n' "$target"
                exit 0
            fi
            printf 'AUDIO-I01: refusing to overwrite existing file: %s\n' "$target" >&2
            exit 73
        fi
        mkdir -p -- "$target_dir"
        tmp="$(mktemp "${target}.tmp.XXXXXXXX")"
        trap 'rm -f -- "$tmp"' EXIT
        install -m 0644 -- "$source_file" "$tmp"
        if [[ -e "$target" || -L "$target" ]]; then
            printf 'AUDIO-I01: destination appeared concurrently, aborting: %s\n' "$target" >&2
            exit 73
        fi
        mv -T -- "$tmp" "$target"
        trap - EXIT
        printf 'AUDIO-I01 policy enabled: %s\nLog out and back in before testing; EasyEffects must be newly started.\n' "$target"
        ;;
    disable)
        if [[ ! -e "$target" && ! -L "$target" ]]; then
            printf 'AUDIO-I01 policy already disabled: %s\n' "$target"
            exit 0
        fi
        if ! is_owned; then
            printf 'AUDIO-I01: refusing to delete modified or foreign file: %s\n' "$target" >&2
            exit 73
        fi
        rm -- "$target"
        printf 'AUDIO-I01 policy disabled: %s\nLog out and back in before comparing.\n' "$target"
        ;;
    *)
        printf '%s\n' 'Usage: easyeffects-quantum-policy.sh {enable|disable|status}' >&2
        exit 64
        ;;
esac
