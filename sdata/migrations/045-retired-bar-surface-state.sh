#!/usr/bin/env bash
# Migration: Remove Bar surface options whose renderer branches are retired.
#
# Hug is the only Classic Bar geometry. cornerStyle/showBackground remain narrow
# normalization inputs, but float shadow and private blur state have no runtime
# consumer and should not survive as apparent user preferences.

MIGRATION_ID="045-retired-bar-surface-state"
MIGRATION_TITLE="Remove retired Bar surface state"
MIGRATION_DESCRIPTION="Removes orphan Classic Bar float-shadow and blur-background configuration."
MIGRATION_TARGET_FILE="~/.config/inir/config.json"
MIGRATION_REQUIRED=true

_retired_bar_config_path() {
  if declare -F resolve_inir_config_dir >/dev/null 2>&1; then
    printf '%s/config.json\n' "$(resolve_inir_config_dir)"
    return
  fi

  local xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  local config_new="${xdg_config_home}/inir/config.json"
  local config_legacy="${xdg_config_home}/illogical-impulse/config.json"
  if [[ -f "$config_new" ]]; then
    printf '%s\n' "$config_new"
  elif [[ -f "$config_legacy" ]]; then
    printf '%s\n' "$config_legacy"
  else
    printf '%s\n' "$config_new"
  fi
}

_retired_bar_surface_paths() {
  local conf="$1"
  jq -r '
    [
      (if (try (.bar | has("floatStyleShadow")) catch false) then "bar.floatStyleShadow" else empty end),
      (if (try (.bar | has("blurBackground")) catch false) then "bar.blurBackground" else empty end)
    ] | .[]
  ' "$conf"
}

migration_check() {
  local conf
  conf="$(_retired_bar_config_path)"
  [[ -f "$conf" ]] || return 1
  [[ -n "$(_retired_bar_surface_paths "$conf" 2>/dev/null)" ]]
}

migration_preview() {
  local conf
  conf="$(_retired_bar_config_path)"
  echo "Will remove retired Classic Bar surface state from $conf:"
  echo ""
  echo -e "  ${STY_RED}- bar.floatStyleShadow${STY_RST}"
  echo -e "  ${STY_RED}- bar.blurBackground${STY_RST}"
  echo ""
  echo "Hug geometry, opacity, borderless state and compatibility normalization are preserved."
}

migration_diff() {
  local conf
  conf="$(_retired_bar_config_path)"
  echo "Retired Bar surface paths present:"
  if [[ ! -f "$conf" ]]; then
    echo "  (config file not found)"
    return
  fi
  local paths
  paths="$(_retired_bar_surface_paths "$conf" 2>/dev/null || true)"
  if [[ -z "$paths" ]]; then
    echo "  (none found)"
    return
  fi
  while IFS= read -r path; do
    [[ -n "$path" ]] && printf '  %s\n' "$path"
  done <<< "$paths"
}

migration_apply() {
  local conf
  conf="$(_retired_bar_config_path)"
  [[ -f "$conf" ]] || { echo "  Config file not found, skipping."; return 0; }

  local tmp
  tmp="$(mktemp "${conf}.migration-tmp.XXXXXX")" || return 1
  if ! jq '
    if ((.bar? | type) == "object")
      then del(.bar.floatStyleShadow, .bar.blurBackground)
      else . end
  ' "$conf" > "$tmp"; then
    rm -f "$tmp"
    echo "  Failed to parse/update config; original file left unchanged." >&2
    return 1
  fi

  chmod --reference="$conf" "$tmp" 2>/dev/null || true
  mv "$tmp" "$conf"
  echo "  Removed retired Bar surface state"
}
