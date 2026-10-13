#!/usr/bin/env bash

# Library file: intended to be sourced by other scripts.
# Do not set shell options here; callers own execution mode.

# Canonical Alis config directory is ~/.config/alis.
# Legacy installs used ~/.config/illogical-impulse.
#
# Compatibility policy:
# - If legacy dir exists as a real directory, keep using it.
# - If legacy is a symlink and new dir exists, use new dir.
# - If only one exists, use that one.
# - If none exists, default to new dir.

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

ALIS_CONFIG_DIR_NEW="${XDG_CONFIG_HOME}/alis"
ALIS_CONFIG_DIR_OLD="${XDG_CONFIG_HOME}/illogical-impulse"

alis_config_dir() {
    # Legacy symlink -> new (post-migration steady state)
    if [[ -L "$ALIS_CONFIG_DIR_OLD" && -d "$ALIS_CONFIG_DIR_NEW" ]]; then
        printf '%s\n' "$ALIS_CONFIG_DIR_NEW"
        return
    fi

    # Legacy real directory wins for backwards compatibility.
    if [[ -d "$ALIS_CONFIG_DIR_OLD" ]]; then
        printf '%s\n' "$ALIS_CONFIG_DIR_OLD"
        return
    fi

    # New path when legacy is absent.
    if [[ -d "$ALIS_CONFIG_DIR_NEW" ]]; then
        printf '%s\n' "$ALIS_CONFIG_DIR_NEW"
        return
    fi

    # Fresh install default.
    printf '%s\n' "$ALIS_CONFIG_DIR_NEW"
}

alis_config_file() {
    printf '%s/config.json\n' "$(alis_config_dir)"
}

alis_version_file() {
    printf '%s/version.json\n' "$(alis_config_dir)"
}

alis_installed_marker_file() {
    printf '%s/installed_true\n' "$(alis_config_dir)"
}

alis_migrations_state_file() {
    printf '%s/migrations.json\n' "$(alis_config_dir)"
}
