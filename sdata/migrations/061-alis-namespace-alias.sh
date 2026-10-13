#!/usr/bin/env bash
# Opt-in compatibility: keep the existing inir directories as source of truth.
MIGRATION_ID="061-alis-namespace-alias"
MIGRATION_TITLE="Add Alis XDG namespace aliases"
MIGRATION_DESCRIPTION="Create non-destructive Alis aliases to existing iNiR config/cache/data/state directories, without moving files or restarting the shell."
MIGRATION_TARGET_FILE=""
MIGRATION_REQUIRED=false

_alis_alias_sources=()
_alis_alias_destinations=()

_alis_alias_collect() {
    _alis_alias_sources=()
    _alis_alias_destinations=()
    local base
    for base in \
        "${XDG_CONFIG_HOME:-$HOME/.config}" \
        "${XDG_CACHE_HOME:-$HOME/.cache}" \
        "${XDG_DATA_HOME:-$HOME/.local/share}" \
        "${XDG_STATE_HOME:-$HOME/.local/state}"; do
        [[ -d "$base/inir" ]] || continue
        _alis_alias_sources+=("$base/inir")
        _alis_alias_destinations+=("$base/alis")
    done
}

_alis_alias_compatible() {
    local src="$1" dest="$2" linked=""
    [[ -L "$dest" ]] || return 1
    linked="$(readlink -- "$dest" 2>/dev/null || true)"
    [[ "$linked" == "$src" || "$linked" == "inir" ]]
}

migration_check() {
    _alis_alias_collect
    local i
    for i in "${!_alis_alias_sources[@]}"; do
        _alis_alias_compatible "${_alis_alias_sources[i]}" "${_alis_alias_destinations[i]}" || return 0
    done
    return 1
}

migration_preview() {
    _alis_alias_collect
    local i
    if [[ ${#_alis_alias_sources[@]} -eq 0 ]]; then
        printf 'No existing iNiR XDG directories need aliases.\n'
    fi
    for i in "${!_alis_alias_sources[@]}"; do
        printf '  %s -> %s\n' "${_alis_alias_destinations[i]}" "${_alis_alias_sources[i]}"
    done
    printf 'Original files and the running shell remain untouched.\n'
}

migration_apply() {
    _alis_alias_collect
    local i j src dest
    local -a created=()
    # Preflight every destination: never overwrite a foreign user-owned path.
    for i in "${!_alis_alias_sources[@]}"; do
        src="${_alis_alias_sources[i]}"
        dest="${_alis_alias_destinations[i]}"
        if [[ -e "$dest" || -L "$dest" ]]; then
            if ! _alis_alias_compatible "$src" "$dest"; then
                printf 'migration %s: conflicting path %s; preserving user data\n' "$MIGRATION_ID" "$dest" >&2
                return 1
            fi
        fi
    done
    for i in "${!_alis_alias_sources[@]}"; do
        src="${_alis_alias_sources[i]}"
        dest="${_alis_alias_destinations[i]}"
        _alis_alias_compatible "$src" "$dest" && continue
        if ! ln -sT -- "$src" "$dest"; then
            printf 'migration %s: could not link %s; reversing links created by this attempt\n' "$MIGRATION_ID" "$dest" >&2
            for j in "${!created[@]}"; do
                local created_dest="${created[j]}"
                local created_src="${_alis_alias_sources[j]}"
                if [[ -L "$created_dest" && "$(readlink -- "$created_dest" 2>/dev/null || true)" == "$created_src" ]]; then
                    rm -- "$created_dest" || true
                fi
            done
            return 1
        fi
        created[i]="$dest"
    done
    return 0
}
