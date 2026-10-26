#!/usr/bin/env bash
# Migration: Remove local Music state owned by the retired private mpv backend.
#
# Local Music now delegates queue, shuffle, repeat and volume state to MPD.
# Keep only connection/library settings in Hadalis config so stale mpv-era
# values cannot look like live preferences.

MIGRATION_ID="044-local-music-mpd-state-cleanup"
MIGRATION_TITLE="Remove retired local Music player state"
MIGRATION_DESCRIPTION="Removes obsolete local Music normalize, shuffle, repeat and volume values now owned by MPD."
MIGRATION_TARGET_FILE="~/.config/inir/config.json"
MIGRATION_REQUIRED=true

_local_music_config_path() {
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

_retired_local_music_paths() {
  local conf="$1"
  jq -r '
    [
      (if (try (.sidebar.music | has("normalizeVolume")) catch false) then "sidebar.music.normalizeVolume" else empty end),
      (if (try (.sidebar.music | has("shuffleMode")) catch false) then "sidebar.music.shuffleMode" else empty end),
      (if (try (.sidebar.music | has("repeatMode")) catch false) then "sidebar.music.repeatMode" else empty end),
      (if (try (.sidebar.music | has("volume")) catch false) then "sidebar.music.volume" else empty end)
    ] | .[]
  ' "$conf"
}

migration_check() {
  local conf
  conf="$(_local_music_config_path)"
  [[ -f "$conf" ]] || return 1
  [[ -n "$(_retired_local_music_paths "$conf" 2>/dev/null)" ]]
}

migration_preview() {
  local conf
  conf="$(_local_music_config_path)"
  echo "Will remove retired local Music player state from $conf:"
  echo ""
  echo -e "  ${STY_RED}- sidebar.music.normalizeVolume${STY_RST}"
  echo -e "  ${STY_RED}- sidebar.music.shuffleMode${STY_RST}"
  echo -e "  ${STY_RED}- sidebar.music.repeatMode${STY_RST}"
  echo -e "  ${STY_RED}- sidebar.music.volume${STY_RST}"
  echo ""
  echo "MPD remains the runtime authority for shuffle, repeat and volume."
}

migration_diff() {
  local conf
  conf="$(_local_music_config_path)"
  echo "Retired local Music paths present:"
  if [[ ! -f "$conf" ]]; then
    echo "  (config file not found)"
    return
  fi

  local paths
  paths="$(_retired_local_music_paths "$conf" 2>/dev/null || true)"
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
  conf="$(_local_music_config_path)"
  [[ -f "$conf" ]] || { echo "  Config file not found, skipping."; return 0; }

  local tmp
  tmp="$(mktemp "${conf}.migration-tmp.XXXXXX")" || return 1
  if ! jq '
    if ((.sidebar? | type) == "object" and (.sidebar.music? | type) == "object")
      then del(
        .sidebar.music.normalizeVolume,
        .sidebar.music.shuffleMode,
        .sidebar.music.repeatMode,
        .sidebar.music.volume
      )
      else . end
  ' "$conf" > "$tmp"; then
    rm -f "$tmp"
    echo "  Failed to parse/update config; original file left unchanged." >&2
    return 1
  fi

  chmod --reference="$conf" "$tmp" 2>/dev/null || true
  mv "$tmp" "$conf"
  echo "  Removed retired local Music player state"
}
