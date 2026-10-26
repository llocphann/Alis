#!/usr/bin/env bash
MIGRATION_ID="057-unified-wallpaper-selector"
MIGRATION_TITLE="Unified wallpaper carousel and liquid transition"
MIGRATION_DESCRIPTION="Replaces picker styles with one Abyss carousel and uses the iNiR liquid wallpaper transition."
MIGRATION_REQUIRED=true
_wallpaper_config() {
 local config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
 if [[ -f "$config_root/illogical-impulse/config.json" ]]; then printf '%s' "$config_root/illogical-impulse/config.json"; else printf '%s' "$config_root/inir/config.json"; fi
}
MIGRATION_TARGET_FILE="$(_wallpaper_config)"
migration_check() {
 local conf;conf="$(_wallpaper_config)"
 [[ -f "$conf" ]] && jq -e '(.wallpaperSelector.style // "grid") != "caelestia" or .wallpaperSelector.useSystemFileDialog == true or .background.transition.type != "inirMelt" or any(.enabledPanels[]?; .=="iiWallpaperLauncher" or .=="iiCoverflowSelector")' "$conf" >/dev/null 2>&1
}
migration_preview() { printf '%s\n' '+ One centered wallpaper carousel; iNiR liquid melt transition'; }
migration_apply() {
 local conf tmp;conf="$(_wallpaper_config)"
 [[ -f "$conf" ]] || return 0
 tmp="$(mktemp "${conf}.wallpaper.XXXXXX")" || return 1
 if jq '.wallpaperSelector.style="caelestia" | .wallpaperSelector.useSystemFileDialog=false
   | .background.transition.type="inirMelt"
   | if .enabledPanels then .enabledPanels |= (if any(.[]; .=="iiWallpaperLauncher" or .=="iiCoverflowSelector") then .+["iiWallpaperSelector"] else . end | map(select(.!="iiWallpaperLauncher" and .!="iiCoverflowSelector")) | unique) else . end' "$conf" > "$tmp"; then
   chmod --reference="$conf" "$tmp" && mv -- "$tmp" "$conf"
 else rm -f -- "$tmp";return 1;fi
}
