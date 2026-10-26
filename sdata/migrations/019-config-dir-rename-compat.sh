#!/usr/bin/env bash

MIGRATION_ID="019-config-dir-rename-compat"
MIGRATION_TITLE="Config directory compatibility for ~/.config/inir"
MIGRATION_DESCRIPTION="Ensures config directory compatibility by linking legacy ~/.config/illogical-impulse to ~/.config/inir while preserving user data."
MIGRATION_TARGET_FILE="~/.config/inir"
MIGRATION_REQUIRED=true

migration_check() {
  local xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  local config_new="${xdg_config_home}/inir"
  local config_legacy="${xdg_config_home}/illogical-impulse"

  if [[ -L "$config_legacy" ]] \
    && [[ "$(readlink "$config_legacy" 2>/dev/null || true)" == "$config_new" ]] \
    && [[ -d "$config_new" ]]; then
    return 1
  fi

  return 0
}

migration_preview() {
  local xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  echo -e "${STY_YELLOW}~ create compatibility layout:${STY_RST}"
  echo "  - canonical: ${xdg_config_home}/inir"
  echo "  - legacy link: ${xdg_config_home}/illogical-impulse -> ${xdg_config_home}/inir"
}

migration_apply() {
  local xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  local config_new="${xdg_config_home}/inir"
  local config_legacy="${xdg_config_home}/illogical-impulse"

  mkdir -p "$xdg_config_home"

  if [[ -L "$config_legacy" ]]; then
    local target
    target="$(readlink "$config_legacy" 2>/dev/null || true)"
    if [[ "$target" == "$config_new" ]]; then
      mkdir -p "$config_new"
      return 0
    fi
    printf 'migration %s: refusing to replace legacy symlink %s -> %s; reconcile it manually before rerunning migration\n' \
      "$MIGRATION_ID" "$config_legacy" "${target:-<unreadable>}" >&2
    return 1
  fi

  if [[ -d "$config_legacy" && ! -e "$config_new" ]]; then
    mv "$config_legacy" "$config_new" || return 1
    if ! ln -s "$config_new" "$config_legacy"; then
      mv "$config_new" "$config_legacy" 2>/dev/null || true
      return 1
    fi
    return 0
  fi

  if [[ -d "$config_legacy" && -d "$config_new" ]]; then
    printf 'migration %s: both config directories exist; refusing destructive automatic merge:\n' "$MIGRATION_ID" >&2
    printf '  canonical: %s\n  legacy: %s\n' "$config_new" "$config_legacy" >&2
    printf 'reconcile the directories manually, preserving any needed files, then rerun migration\n' >&2
    return 1
  fi

  if [[ -e "$config_legacy" ]]; then
    printf 'migration %s: legacy config path is neither the expected directory nor compatibility symlink: %s\n' \
      "$MIGRATION_ID" "$config_legacy" >&2
    printf 'preserving it unchanged; reconcile the path manually before rerunning migration\n' >&2
    return 1
  fi

  mkdir -p "$config_new" || return 1
  ln -s "$config_new" "$config_legacy"
}
