#!/usr/bin/env bash
# Migration: Remove configuration state for retired shell modules/renderers.
#
# Mascot, Workspace Strip, Orbit and the non-Classic Bar renderers were removed
# from the runtime. Keep existing user configs aligned with the live schema so
# stale state cannot be mistaken for supported configuration.

MIGRATION_ID="039-retired-shell-config"
MIGRATION_TITLE="Remove retired shell config"
MIGRATION_DESCRIPTION="Removes orphan config for Mascot, Workspace Strip, Orbit, and retired Bar appearance renderers."
MIGRATION_TARGET_FILE="~/.config/inir/config.json"
MIGRATION_REQUIRED=true

_retired_config_path() {
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

_retired_paths() {
  local conf="$1"
  jq -r '
    [
      (if has("workspaceStrip") then "workspaceStrip" else empty end),
      (if has("mascot") then "mascot" else empty end),
      (if has("orbit") then "orbit" else empty end),
      (if ((.enabledPanels? | type) == "array" and (.enabledPanels | index("iiMascotCompanion")) != null) then "enabledPanels[iiMascotCompanion]" else empty end),
      (if ((.knownPanels? | type) == "array" and (.knownPanels | index("iiMascotCompanion")) != null) then "knownPanels[iiMascotCompanion]" else empty end),
      (if (try (.background.widgets | has("mascot")) catch false) then "background.widgets.mascot" else empty end),
      (if (try (.background.widgets | has("mascotInstances")) catch false) then "background.widgets.mascotInstances" else empty end),
      (if (try (.bar | has("appearanceStyle")) catch false) then "bar.appearanceStyle" else empty end),
      (if (try (.bar | has("pill")) catch false) then "bar.pill" else empty end),
      (if (try (.bar | has("islands")) catch false) then "bar.islands" else empty end),
      (if (try (.bar | has("m3")) catch false) then "bar.m3" else empty end)
    ] | .[]
  ' "$conf"
}

migration_check() {
  local conf
  conf="$(_retired_config_path)"
  [[ -f "$conf" ]] || return 1

  [[ -n "$(_retired_paths "$conf" 2>/dev/null)" ]]
}

migration_preview() {
  local conf
  conf="$(_retired_config_path)"
  echo "Will remove configuration that no longer has a runtime consumer from $conf:"
  echo ""
  echo -e "  ${STY_RED}- workspaceStrip${STY_RST}"
  echo -e "  ${STY_RED}- mascot${STY_RST}"
  echo -e "  ${STY_RED}- orbit${STY_RST}"
  echo -e "  ${STY_RED}- iiMascotCompanion from enabledPanels / knownPanels${STY_RST}"
  echo -e "  ${STY_RED}- background.widgets.mascot / mascotInstances${STY_RST}"
  echo -e "  ${STY_RED}- bar.appearanceStyle / pill / islands / m3${STY_RST}"
  echo ""
  echo "Classic remains the only Material Bar appearance; unrelated live Bar and widget settings are preserved."
}

migration_diff() {
  local conf
  conf="$(_retired_config_path)"
  echo "Retired config paths present:"
  if [[ ! -f "$conf" ]]; then
    echo "  (config file not found)"
    return
  fi

  local paths
  paths="$(_retired_paths "$conf" 2>/dev/null || true)"
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
  conf="$(_retired_config_path)"
  [[ -f "$conf" ]] || { echo "  Config file not found, skipping."; return 0; }

  local tmp
  tmp="$(mktemp "${conf}.migration-tmp.XXXXXX")" || return 1

  if ! jq '
    del(.workspaceStrip, .mascot, .orbit)
    | if ((.enabledPanels? | type) == "array")
      then .enabledPanels |= map(select(. != "iiMascotCompanion"))
      else . end
    | if ((.knownPanels? | type) == "array")
      then .knownPanels |= map(select(. != "iiMascotCompanion"))
      else . end
    | if ((.background? | type) == "object" and (.background.widgets? | type) == "object")
      then del(.background.widgets.mascot, .background.widgets.mascotInstances)
      else . end
    | if ((.bar? | type) == "object")
      then del(.bar.appearanceStyle, .bar.pill, .bar.islands, .bar.m3)
      else . end
  ' "$conf" > "$tmp"; then
    rm -f "$tmp"
    echo "  Failed to parse/update config; original file left unchanged." >&2
    return 1
  fi

  chmod --reference="$conf" "$tmp" 2>/dev/null || true
  mv "$tmp" "$conf"
  echo "  Removed retired shell configuration"
}
