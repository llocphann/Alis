#!/usr/bin/env bash
# Wi-Fi and Bluetooth already live in System Tray. Abyss briefly exposed them
# as duplicate Screen Edge modules; remove those persisted placements while
# preserving the mature connection popups now opened from tray hover.

MIGRATION_ID="053-retire-abyss-connectivity-modules"
MIGRATION_TITLE="Retire duplicate Abyss connectivity modules"
MIGRATION_DESCRIPTION="Removes persisted Wi-Fi/Bluetooth Screen Edge modules. Their existing System Tray icons now open the same connection popups on hover."
MIGRATION_REQUIRED=true

_abyss_connectivity_config_path() {
  local root="${XDG_CONFIG_HOME:-$HOME/.config}"
  if [[ -f "$root/illogical-impulse/config.json" ]]; then
    printf '%s' "$root/illogical-impulse/config.json"
  else
    printf '%s' "$root/inir/config.json"
  fi
}

MIGRATION_TARGET_FILE="$(_abyss_connectivity_config_path)"

migration_check() {
  local conf
  conf="$(_abyss_connectivity_config_path)"
  [[ -f "$conf" ]] || return 1
  jq -e '
    [
      (.abyss.modules.placements[]?.kind),
      (.abyss.modules.outputLayouts[]?.placements[]?.kind)
    ] | any(. == "wifi" or . == "bluetooth")
  ' "$conf" >/dev/null 2>&1
}

migration_preview() {
  echo -e "${STY_RED:-}- duplicate Abyss Wi-Fi/Bluetooth Edge modules${STY_RST:-}"
  echo -e "${STY_GREEN:-}+ keep System Tray icons; hover opens existing connection popups${STY_RST:-}"
}

migration_apply() {
  local conf tmp
  conf="$(_abyss_connectivity_config_path)"
  [[ -f "$conf" ]] || return 0
  tmp="${conf}.migration-tmp"
  jq '
    if .abyss?.modules then
      .abyss.modules.placements = ((.abyss.modules.placements // [])
        | map(select(.kind != "wifi" and .kind != "bluetooth")))
      | .abyss.modules.outputLayouts = ((.abyss.modules.outputLayouts // [])
        | map(.placements = ((.placements // [])
          | map(select(.kind != "wifi" and .kind != "bluetooth")))))
    else . end
  ' "$conf" > "$tmp" && mv "$tmp" "$conf"
}
