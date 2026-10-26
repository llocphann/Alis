#!/usr/bin/env bash
# Migration: retire the experimental Niri live/adaptive preview backend.
#
# Runtime returns to the existing bounded PNG snapshot cache. This migration
# removes package/files installed by the retired experiment and deletes only
# the preview settings that no longer have a consumer.

MIGRATION_ID="048-retired-niri-live-preview"
MIGRATION_TITLE="Remove retired Niri live preview"
MIGRATION_DESCRIPTION="Removes the experimental Niri native preview plugin and stale adaptive-preview configuration."
MIGRATION_TARGET_FILE="/usr/share/inir/niri-preview-plugin"
MIGRATION_REQUIRED=true

_retired_niri_preview_config_path() {
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

_retired_niri_preview_config_present() {
  local conf="$1"
  [[ -f "$conf" ]] || return 1
  jq -e '
    (.overview? | type) == "object" and (
      (.overview | has("previewMode")) or
      (.overview | has("maxLiveWindows")) or
      (.overview | has("liveOnHover")) or
      (.overview | has("liveFocusedWindow")) or
      (.overview | has("liveMediaWindows")) or
      (.overview | has("livePromotionDelayMs")) or
      (.overview | has("liveCooldownMs")) or
      (.overview | has("activityPromotionThreshold")) or
      (.overview | has("niriMaxLiveWindows")) or
      (.overview | has("niriPreviewMaxFps")) or
      (.overview | has("niriProbeMaxFps")) or
      (.overview | has("niriProbeSlots")) or
      (.overview | has("niriProbeWindowMs")) or
      (.overview | has("niriMotionSamples")) or
      (.overview | has("niriMotionSampleThreshold")) or
      (.overview | has("niriActivityPromotionThreshold")) or
      (.overview | has("niriMediaActivityPromotionThreshold")) or
      (.overview | has("niriFocusedActivityPromotionThreshold")) or
      (.overview | has("niriStaticCooldownMs"))
    )
  ' "$conf" >/dev/null 2>&1
}

_retired_niri_preview_plugin_present() {
  if command -v pacman >/dev/null 2>&1 && pacman -Q inir-niri-preview >/dev/null 2>&1; then
    return 0
  fi
  [[ -e /usr/share/inir/niri-preview-plugin
      || -e /usr/lib/qt6/qml/Hadalis/NiriPreview ]]
}

migration_check() {
  local conf
  conf="$(_retired_niri_preview_config_path)"
  _retired_niri_preview_config_present "$conf" || _retired_niri_preview_plugin_present
}

migration_preview() {
  echo "Return Niri Overview to the cached PNG snapshot backend."
  echo -e "  ${STY_RED}- inir-niri-preview package / QML plugin${STY_RST}"
  echo -e "  ${STY_RED}- retired Overview adaptive/live-preview settings${STY_RST}"
  echo "Existing snapshot cache settings and unrelated Overview options are preserved."
}

migration_diff() {
  local conf
  conf="$(_retired_niri_preview_config_path)"
  if _retired_niri_preview_plugin_present; then
    echo "Retired native preview plugin: installed/present"
  else
    echo "Retired native preview plugin: absent"
  fi
  if _retired_niri_preview_config_present "$conf"; then
    echo "Retired adaptive-preview config: present in $conf"
  else
    echo "Retired adaptive-preview config: absent"
  fi
}

migration_apply() {
  local conf
  conf="$(_retired_niri_preview_config_path)"

  if _retired_niri_preview_config_present "$conf"; then
    local tmp
    tmp="$(mktemp "${conf}.migration-tmp.XXXXXX")" || return 1
    if ! jq '
      if ((.overview? | type) == "object") then
        del(
          .overview.previewMode,
          .overview.maxLiveWindows,
          .overview.liveOnHover,
          .overview.liveFocusedWindow,
          .overview.liveMediaWindows,
          .overview.livePromotionDelayMs,
          .overview.liveCooldownMs,
          .overview.activityPromotionThreshold,
          .overview.niriMaxLiveWindows,
          .overview.niriPreviewMaxFps,
          .overview.niriProbeMaxFps,
          .overview.niriProbeSlots,
          .overview.niriProbeWindowMs,
          .overview.niriMotionSamples,
          .overview.niriMotionSampleThreshold,
          .overview.niriActivityPromotionThreshold,
          .overview.niriMediaActivityPromotionThreshold,
          .overview.niriFocusedActivityPromotionThreshold,
          .overview.niriStaticCooldownMs
        )
      else . end
    ' "$conf" > "$tmp"; then
      rm -f "$tmp"
      echo "Failed to remove retired preview config; original left unchanged." >&2
      return 1
    fi
    chmod --reference="$conf" "$tmp" 2>/dev/null || true
    mv "$tmp" "$conf"
    echo "Removed retired adaptive-preview config"
  fi

  if command -v pacman >/dev/null 2>&1 && pacman -Q inir-niri-preview >/dev/null 2>&1; then
    pkg_sudo pacman -R --noconfirm inir-niri-preview || {
      echo "Could not uninstall retired inir-niri-preview package." >&2
      return 1
    }
  fi

  if [[ -e /usr/share/inir/niri-preview-plugin
        || -e /usr/lib/qt6/qml/Hadalis/NiriPreview ]]; then
    pkg_sudo rm -rf \
      /usr/share/inir/niri-preview-plugin \
      /usr/lib/qt6/qml/Hadalis/NiriPreview || {
        echo "Could not remove retired Niri preview plugin files." >&2
        return 1
      }
  fi

  echo "Niri Overview now uses snapshot previews only"
}
