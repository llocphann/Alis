#!/usr/bin/env bash
# Wi-Fi and Bluetooth are one System Tray connectivity popup family. Normalize
# old per-kind Abyss popup position records into one shared "wifi" record per
# output so Join Edge/placement cannot diverge between the two faces.

MIGRATION_ID="056-merge-abyss-connectivity-popup-position"
MIGRATION_TITLE="Merge Abyss Wi-Fi/Bluetooth popup position"
MIGRATION_DESCRIPTION="Uses one shared Abyss popup position and Join Edge setting for the System Tray Wi-Fi and Bluetooth popups."
MIGRATION_REQUIRED=true

_abyss_connectivity_position_config_path() {
  local root="${XDG_CONFIG_HOME:-$HOME/.config}"
  if [[ -f "$root/illogical-impulse/config.json" ]]; then
    printf '%s' "$root/illogical-impulse/config.json"
  else
    printf '%s' "$root/inir/config.json"
  fi
}

MIGRATION_TARGET_FILE="$(_abyss_connectivity_position_config_path)"

migration_check() {
  local conf
  conf="$(_abyss_connectivity_position_config_path)"
  [[ -f "$conf" ]] || return 1
  jq -e '[.abyss.positions[]? | select(.kind == "bluetooth")] | length > 0' "$conf" >/dev/null 2>&1
}

migration_preview() {
  echo -e "${STY_RED:-}- separate Bluetooth popup position / Join Edge record${STY_RST:-}"
  echo -e "${STY_GREEN:-}+ shared Wi-Fi / Bluetooth System Tray popup position${STY_RST:-}"
}

migration_apply() {
  local conf tmp
  conf="$(_abyss_connectivity_position_config_path)"
  [[ -f "$conf" ]] || return 0
  tmp="${conf}.migration-tmp"
  jq '
    def merge_connectivity:
      . as $all
      | reduce $all[] as $p
          ({items: [], seen: []};
            if ($p.kind == "wifi" or $p.kind == "bluetooth") then
              (($p.outputName // "") | tostring) as $scope
              | if (.seen | index($scope)) != null then .
                else
                  ([ $all[] | select(
                      (.kind == "wifi" or .kind == "bluetooth")
                      and (((.outputName // "") | tostring) == $scope)
                    ) ]) as $group
                  | (([$group[] | select(.kind == "wifi")][0]) // $group[0]) as $chosen
                  | .items += [($chosen | .kind = "wifi")]
                  | .seen += [$scope]
                end
            else
              .items += [$p]
            end)
      | .items;

    if .abyss then
      .abyss.positions = ((.abyss.positions // []) | merge_connectivity)
    else . end
  ' "$conf" > "$tmp" && mv "$tmp" "$conf"
}
