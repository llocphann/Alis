#!/usr/bin/env bash
set -euo pipefail
# Owner-invoked rollback ONLY for the optional BRAND-R01 XDG aliases.
# The authoritative inir directories and all their contents are never deleted.
usage() {
    printf 'Usage: %s [--dry-run|--apply]\n' "${0##*/}"
    printf 'Checks all Alis XDG alias paths for conflicts before unlinking any.\n'
}
case "${1:---dry-run}" in
    --dry-run) apply=false ;;
    --apply) apply=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 2; }
paths=()
for base in \
    "${XDG_CONFIG_HOME:-$HOME/.config}" \
    "${XDG_CACHE_HOME:-$HOME/.cache}" \
    "${XDG_DATA_HOME:-$HOME/.local/share}" \
    "${XDG_STATE_HOME:-$HOME/.local/state}"; do
    target="$base/alis"
    [[ -e "$target" || -L "$target" ]] || continue
    if [[ ! -L "$target" ]]; then
        printf 'Refusing non-symlink user data at %s\n' "$target" >&2
        exit 1
    fi
    dest="$(readlink -- "$target")"
    if [[ "$dest" != "$base/inir" && "$dest" != "inir" ]]; then
        printf 'Refusing foreign symlink at %s -> %s\n' "$target" "$dest" >&2
        exit 1
    fi
    paths+=("$target")
done
for target in "${paths[@]}"; do
    printf '%s: %s\n' "$([[ "$apply" == true ]] && printf Unlink || printf Would-unlink)" "$target"
done
if [[ "$apply" == true ]]; then
    for target in "${paths[@]}"; do
        base="${target%/alis}"
        dest="$(readlink -- "$target" 2>/dev/null || true)"
        if [[ -L "$target" && ( "$dest" == "$base/inir" || "$dest" == inir ) ]]; then
            rm -- "$target"
        else
            printf 'Alias changed since preflight, refusing %s\n' "$target" >&2
            exit 1
        fi
    done
fi
printf 'Authoritative inir directories were not touched.\n'
