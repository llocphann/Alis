#!/usr/bin/env bash

# Library file: intended to be sourced by other scripts.
# Do not set shell options here; callers own execution mode.

# Canonical Alis config directory is ~/.config/alis.
# Legacy installs used ~/.config/illogical-impulse.
#
# Compatibility policy:
# - Canonical alis directory wins when present (matching QML).
# - Before cutover, a standalone legacy directory remains readable.
# - If neither exists, default to alis.

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

ALIS_CONFIG_DIR_NEW="${XDG_CONFIG_HOME}/alis"
ALIS_CONFIG_DIR_OLD="${XDG_CONFIG_HOME}/illogical-impulse"

alis_config_dir() {
    # The active QML runtime reads ~/.config/alis. Never point helper
    # scripts back to an old real directory once canonical Alis exists.
    if [[ -d "$ALIS_CONFIG_DIR_NEW" ]]; then
        printf '%s\n' "$ALIS_CONFIG_DIR_NEW"
        return
    fi

    # Preserve pre-cutover standalone workflows when only upstream exists.
    if [[ -d "$ALIS_CONFIG_DIR_OLD" ]]; then
        printf '%s\n' "$ALIS_CONFIG_DIR_OLD"
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
