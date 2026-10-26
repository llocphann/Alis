#!/usr/bin/env bash
# Preserve existing Bar layouts when the distro icon gains its own module.

MIGRATION_ID="047-split-bar-sidebar-icons"
MIGRATION_TITLE="Separate Bar sidebar and distro modules"
MIGRATION_DESCRIPTION="Keeps the distro icon in existing Bar layouts while giving the sidebar its own control."
MIGRATION_TARGET_FILE="~/.config/inir/config.json"
MIGRATION_REQUIRED=true

_split_bar_config_path() {
  if declare -F resolve_inir_config_dir >/dev/null 2>&1; then
    printf '%s/config.json\n' "$(resolve_inir_config_dir)"
    return
  fi
  local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  if [[ -f "$config_home/inir/config.json" ]]; then
    printf '%s/inir/config.json\n' "$config_home"
  elif [[ -f "$config_home/illogical-impulse/config.json" ]]; then
    printf '%s/illogical-impulse/config.json\n' "$config_home"
  else
    printf '%s/inir/config.json\n' "$config_home"
  fi
}

migration_check() {
  local conf
  conf="$(_split_bar_config_path)"
  [[ -f "$conf" ]] || return 1
  jq -e '(.bar.modules | type) == "object" and ((.bar.modules | has("distroIcon")) | not)' "$conf" >/dev/null 2>&1
}

migration_preview() {
  echo "Keep the distro icon beside the new left Sidebar button in existing Bar layouts."
  echo "System status indicators now belong to the existing System Tray module."
}

migration_diff() {
  local conf
  conf="$(_split_bar_config_path)"
  jq '{left: .bar.layout.left, top: .bar.verticalLayout.top, leftSidebarButton: .bar.modules.leftSidebarButton}' "$conf" 2>/dev/null
}

migration_apply() {
  local conf tmp
  conf="$(_split_bar_config_path)"
  migration_check || return 0
  tmp="$(mktemp "${conf}.migration-tmp.XXXXXX")" || return 1
  if ! jq '
    def with_distro:
      if type == "array" and index("distroIcon") == null and index("leftSidebarButton") != null then
        (index("leftSidebarButton") + 1) as $at
        | .[0:$at] + ["distroIcon"] + .[$at:]
      else . end;
    .bar.modules.distroIcon = (if (.bar.modules | has("leftSidebarButton"))
      then .bar.modules.leftSidebarButton else true end)
    | if (.bar.layout.left | type) == "array" then .bar.layout.left |= with_distro else . end
    | if (.bar.verticalLayout.top | type) == "array" then .bar.verticalLayout.top |= with_distro else . end
  ' "$conf" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  chmod --reference="$conf" "$tmp" 2>/dev/null || true
  mv "$tmp" "$conf"
}
