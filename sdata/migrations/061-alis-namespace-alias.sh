#!/usr/bin/env bash
# Optional Alis aliases: legacy XDG directories remain the source of truth.
# Foreign Alis application data (notably ~/.cache/alis) is NEVER overwritten.
MIGRATION_ID="061-alis-namespace-alias"
MIGRATION_TITLE="Add Alis XDG namespace aliases"
MIGRATION_DESCRIPTION="Optionally alias free Alis config/cache/data/state paths to existing Alis roots. Skip foreign Alis paths without touching them."
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
        [[ -d "$base/alis" ]] || continue
        _alis_alias_sources+=("$base/alis")
        _alis_alias_destinations+=("$base/alis")
    done
}

_alis_alias_compatible() {
    local src="$1" dest="$2" linked=""
    [[ -L "$dest" ]] || return 1
    linked="$(readlink -- "$dest" 2>/dev/null || true)"
    [[ "$linked" == "$src" || "$linked" == "alis" ]]
}

migration_check() {
    _alis_alias_collect
    local i dest
    for i in "${!_alis_alias_sources[@]}"; do
        dest="${_alis_alias_destinations[i]}"
        # A foreign Alis root is not a reason to repeatedly prompt users:
        # only paths free for creating an alias can be pending.
        [[ -e "$dest" || -L "$dest" ]] || return 0
    done
    return 1
}

migration_preview() {
    _alis_alias_collect
    local i src dest
    if [[ ${#_alis_alias_sources[@]} -eq 0 ]]; then
        printf 'No existing Alis XDG directories need aliases.\n'
    fi
    for i in "${!_alis_alias_sources[@]}"; do
        src="${_alis_alias_sources[i]}"
        dest="${_alis_alias_destinations[i]}"
        if _alis_alias_compatible "$src" "$dest"; then
            printf '  Existing compatible alias: %s\n' "$dest"
        elif [[ -e "$dest" || -L "$dest" ]]; then
            printf '  SKIP — existing user-owned Alis path: %s\n' "$dest"
        else
            printf '  Create: %s -> %s\n' "$dest" "$src"
        fi
    done
    printf 'Original files and foreign Alis data remain untouched.\n'
}

migration_apply() {
    _alis_alias_collect
    local i j src dest
    local -a created=()
    # The four paths are independent conveniences, not a primary namespace
    # transition. Never rename, merge or delete a pre-existing Alis directory
    # or a symlink belonging to some other application.
    for i in "${!_alis_alias_sources[@]}"; do
        src="${_alis_alias_sources[i]}"
        dest="${_alis_alias_destinations[i]}"
        if [[ ! -d "$src" ]]; then
            printf 'migration %s: legacy source disappeared at %s; no change\n' "$MIGRATION_ID" "$src" >&2
            return 1
        fi
        if [[ -e "$dest" || -L "$dest" ]] &&
                ! _alis_alias_compatible "$src" "$dest"; then
            printf 'migration %s: SKIP existing user-owned path %s; data preserved\n' "$MIGRATION_ID" "$dest" >&2
        fi
    done
    for i in "${!_alis_alias_sources[@]}"; do
        src="${_alis_alias_sources[i]}"
        dest="${_alis_alias_destinations[i]}"
        _alis_alias_compatible "$src" "$dest" && continue
        [[ -e "$dest" || -L "$dest" ]] && continue
        if ! ln -sT -- "$src" "$dest"; then
            printf 'migration %s: link failed at %s; undoing aliases made this attempt\n' "$MIGRATION_ID" "$dest" >&2
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
