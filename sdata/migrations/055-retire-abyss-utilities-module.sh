#!/usr/bin/env bash
# Utilities is a connected popup launched from the Quick Actions module. Fold
# the short-lived standalone Screen Edge placement into Quick Actions when a
# profile does not already contain it; otherwise remove only the duplicate.
# Popup position settings and unrelated modules remain untouched.

MIGRATION_ID="055-retire-abyss-utilities-module"
MIGRATION_TITLE="Move Abyss Utilities into Quick Actions"
MIGRATION_DESCRIPTION="Folds persisted standalone Utilities Screen Edge modules into Quick Actions so the Utilities launcher remains reachable without a duplicate module."
MIGRATION_REQUIRED=true

_abyss_utilities_config_path() {
  local root="${XDG_CONFIG_HOME:-$HOME/.config}"
  if [[ -f "$root/illogical-impulse/config.json" ]]; then
    printf '%s' "$root/illogical-impulse/config.json"
  else
    printf '%s' "$root/inir/config.json"
  fi
}

MIGRATION_TARGET_FILE="$(_abyss_utilities_config_path)"

migration_check() {
  local conf
  conf="$(_abyss_utilities_config_path)"
  [[ -f "$conf" ]] || return 1
  jq -e '
    [
      (.abyss.modules.placements[]?.kind),
      (.abyss.modules.outputLayouts[]?.placements[]?.kind)
    ] | any(. == "utilities")
  ' "$conf" >/dev/null 2>&1
}

migration_preview() {
  echo -e "${STY_RED:-}- standalone Abyss Utilities Edge module${STY_RST:-}"
  echo -e "${STY_GREEN:-}+ Utilities icon inside Quick Actions${STY_RST:-}"
}

migration_apply() {
  local conf tmp
  conf="$(_abyss_utilities_config_path)"
  [[ -f "$conf" ]] || return 0
  tmp="${conf}.migration-tmp"
  jq '
    def fold_utilities:
      if any(.[]?; .kind == "utilButtons") then
        map(select(.kind != "utilities"))
      elif any(.[]?; .kind == "utilities") then
        ([.[] | select(.kind != "utilities")]
          + [(first(.[] | select(.kind == "utilities"))
              | .kind = "utilButtons"
              | .id = "utilButtons")])
      else .
      end;

    if .abyss?.modules then
      .abyss.modules.placements = ((.abyss.modules.placements // []) | fold_utilities)
      | .abyss.modules.outputLayouts = ((.abyss.modules.outputLayouts // [])
        | map(.placements = ((.placements // []) | fold_utilities)))
    else . end
  ' "$conf" > "$tmp" && mv "$tmp" "$conf"
}
