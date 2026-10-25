#!/usr/bin/env bash
set -euo pipefail
# Apply Qt/KDE/GTK theme colors from Alis's generated palette contract.
# Generates:
#   - GTK3 and GTK4/libadwaita CSS overrides
#   - kdeglobals (KDE/Qt app colors for Dolphin, etc.)
#   - Darkly.colors (Qt style color scheme)
#   - Pywalfox colors (Firefox theming)
#   - Vesktop/Discord theme (if enabled)
#   - qt5ct/qt6ct color scheme config
# Prefers palette.json and falls back to colors.json for compatibility.

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
PALETTE_JSON="$XDG_STATE_HOME/quickshell/user/generated/palette.json"
APP_PALETTE_JSON="$XDG_STATE_HOME/quickshell/user/generated/app-palette.json"
COLORS_JSON="$XDG_STATE_HOME/quickshell/user/generated/colors.json"
KDEGLOBALS="$HOME/.config/kdeglobals"
DARKLY_COLORS="$XDG_DATA_HOME/color-schemes/Darkly.colors"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_LOCK="$XDG_STATE_HOME/quickshell/user/generated/app-theme.lock"
mkdir -p "$(dirname "$THEME_LOCK")"
exec 9>"$THEME_LOCK"
if ! flock -w 15 9; then
    echo "[apply-gtk-theme] timed out waiting for another theme application"
    exit 1
fi

# shellcheck source=scripts/lib/config-path.sh
source "$SCRIPT_DIR/../lib/config-path.sh"
SHELL_CONFIG_FILE="$(alis_config_file)"

# Read config options
enable_apps_shell="true"
enable_qt_apps="true"
if [[ -f "$SHELL_CONFIG_FILE" ]] && command -v jq &>/dev/null; then
    enable_apps_shell=$(jq -r '.appearance.wallpaperTheming.enableAppsAndShell // true' "$SHELL_CONFIG_FILE")
    enable_qt_apps=$(jq -r '.appearance.wallpaperTheming.enableQtApps // true' "$SHELL_CONFIG_FILE")
fi

# Exit only when both shell/GTK and Qt app theming are disabled
if [[ "$enable_apps_shell" == "false" && "$enable_qt_apps" == "false" ]]; then
    exit 0
fi

# Read colors from the explicit palette contract first, then fall back to colors.json
COLOR_SOURCE="$APP_PALETTE_JSON"
if [[ ! -f "$COLOR_SOURCE" ]]; then
    COLOR_SOURCE="$PALETTE_JSON"
fi
if [[ ! -f "$COLOR_SOURCE" ]]; then
    COLOR_SOURCE="$COLORS_JSON"
fi

if [[ ! -f "$COLOR_SOURCE" ]] || ! command -v jq &>/dev/null; then
    echo "[apply-gtk-theme] palette/colors JSON not found or jq missing, skipping"
    exit 0
fi

# The configured icon theme names a family. Apply the installed sibling
# matching the generated light/dark mode so symbolic icons retain contrast.
THEME_MODE=$(jq -r '.mode // empty' "$XDG_STATE_HOME/quickshell/user/generated/theme-meta.json" 2>/dev/null || true)
if [[ "$THEME_MODE" != "light" && "$THEME_MODE" != "dark" ]]; then
    [[ "$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)" == "'prefer-light'" ]] \
        && THEME_MODE="light" || THEME_MODE="dark"
fi
CHOSEN_ICON_THEME=$(jq -r '.appearance.iconTheme // empty' "$SHELL_CONFIG_FILE" 2>/dev/null || true)
[[ -z "$CHOSEN_ICON_THEME" ]] && CHOSEN_ICON_THEME=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'" || true)
APPLIED_ICON_THEME=""
if [[ -n "$CHOSEN_ICON_THEME" ]]; then
    APPLIED_ICON_THEME=$(bash "$SCRIPT_DIR/icon-theme-for-mode.sh" "$CHOSEN_ICON_THEME" "$THEME_MODE" 2>/dev/null || echo "$CHOSEN_ICON_THEME")
    if [[ "$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")" != "$APPLIED_ICON_THEME" ]]; then
        gsettings set org.gnome.desktop.interface icon-theme "$APPLIED_ICON_THEME" 2>/dev/null || true
    fi
fi

# Read the app palette in one jq invocation rather than starting 29 jq
# processes during every wallpaper recolor. The ordered fields are defined in
# lib/app-palette-fields.jq and preserve the former fallback precedence (e.g. .app_foreground // .on_surface).
if ! COLOR_VALUES_TEXT="$(jq -r -f "$SCRIPT_DIR/lib/app-palette-fields.jq" "$COLOR_SOURCE" 2>/dev/null)"; then
    echo "[apply-gtk-theme] invalid palette JSON, skipping GTK/KDE refresh" >&2
    exit 0
fi
mapfile -t COLOR_VALUES <<< "$COLOR_VALUES_TEXT"
BG="${COLOR_VALUES[0]:-}"
FG="${COLOR_VALUES[1]:-}"
PRIMARY="${COLOR_VALUES[2]:-}"
ON_PRIMARY="${COLOR_VALUES[3]:-}"
PRIMARY_CONTAINER="${COLOR_VALUES[4]:-}"
ON_PRIMARY_CONTAINER="${COLOR_VALUES[5]:-}"
SURFACE="${COLOR_VALUES[6]:-}"
ON_SURFACE="${COLOR_VALUES[7]:-}"
SURFACE_CONTAINER="${COLOR_VALUES[8]:-}"
SURFACE_CONTAINER_HIGH="${COLOR_VALUES[9]:-}"
SURFACE_CONTAINER_LOW="${COLOR_VALUES[10]:-}"
SURFACE_DIM="${COLOR_VALUES[11]:-}"
OUTLINE_VARIANT="${COLOR_VALUES[12]:-}"
SURFACE_CONTAINER_HIGHEST="${COLOR_VALUES[13]:-}"
APP_HEADERBAR_BG="${COLOR_VALUES[14]:-}"
APP_SIDEBAR_BG="${COLOR_VALUES[15]:-}"
APP_CARD_BG="${COLOR_VALUES[16]:-}"
APP_POPOVER_BG="${COLOR_VALUES[17]:-}"
APP_DIALOG_BG="${COLOR_VALUES[18]:-}"
APP_SELECTION="${COLOR_VALUES[19]:-}"
APP_SELECTION_HOVER="${COLOR_VALUES[20]:-}"
APP_ON_SELECTION="${COLOR_VALUES[21]:-}"
APP_SUCCESS="${COLOR_VALUES[22]:-}"
APP_WARNING="${COLOR_VALUES[23]:-}"
APP_ERROR="${COLOR_VALUES[24]:-}"
ERROR_COLOR="${COLOR_VALUES[25]:-}"
TERTIARY="${COLOR_VALUES[26]:-}"
SECONDARY="${COLOR_VALUES[27]:-}"
SECONDARY_CONTAINER="${COLOR_VALUES[28]:-}"

# If ThemePresets passes args (bg fg primary on_primary surface surface_dim), use them
# This avoids the race condition between generateColorsJson() writing to disk and this script reading
if [[ -n "${1:-}" ]]; then
    BG="$1"
    FG="${2:-$FG}"
    PRIMARY="${3:-$PRIMARY}"
    ON_PRIMARY="${4:-$ON_PRIMARY}"
    PRIMARY_CONTAINER="${7:-$PRIMARY_CONTAINER}"
    ON_PRIMARY_CONTAINER="${8:-$ON_PRIMARY_CONTAINER}"
    SURFACE="${5:-$SURFACE}"
    SURFACE_DIM="${6:-$SURFACE_DIM}"
    # Derive extra colors from available values when args provided
    ON_SURFACE="$FG"
    SURFACE_CONTAINER="$SURFACE"
    SURFACE_CONTAINER_HIGH="$SURFACE"
    SURFACE_CONTAINER_LOW="$SURFACE_DIM"
    OUTLINE_VARIANT="$SURFACE_DIM"
    SURFACE_CONTAINER_HIGHEST="$SURFACE"
fi

# Helper
adjust_color() {
    local hex="${1#\#}"
    local amount="$2"
    local r=$((0x${hex:0:2} + amount))
    local g=$((0x${hex:2:2} + amount))
    local b=$((0x${hex:4:2} + amount))
    ((r < 0)) && r=0; ((r > 255)) && r=255
    ((g < 0)) && g=0; ((g > 255)) && g=255
    ((b < 0)) && b=0; ((b > 255)) && b=255
    printf "#%02x%02x%02x" $r $g $b
}

# Break a symlink, replacing it with a regular file slot.
# Prevents writing through symlinks to external themes.
break_symlink() {
    if [[ -L "$1" ]]; then
        rm -f "$1"
    fi
}

# Atomically replace a generated file only when its content changed. GTK apps
# read user CSS during process startup, so avoiding partial writes matters when
# wallpaper/style changes arrive close together.
write_if_changed() {
    local target="$1"
    local temp
    temp=$(mktemp "${target}.tmp.XXXXXX")
    cat > "$temp"
    if [[ -f "$target" ]] && cmp -s "$temp" "$target"; then
        rm -f "$temp"
        return 1
    fi
    if [[ -f "$target" ]]; then
        chmod --reference="$target" "$temp" 2>/dev/null || chmod 0644 "$temp"
    else
        chmod 0644 "$temp"
    fi
    mv -f "$temp" "$target"
    return 0
}

# Derive missing surface variants from BG — fallback when palette.json is incomplete
[[ -z "$SURFACE_DIM" ]]              && SURFACE_DIM=$(adjust_color "$BG" -10)
[[ -z "$SURFACE_CONTAINER" ]]        && SURFACE_CONTAINER=$(adjust_color "$BG" 13)
[[ -z "$SURFACE_CONTAINER_LOW" ]]    && SURFACE_CONTAINER_LOW=$(adjust_color "$BG" 9)
[[ -z "$SURFACE_CONTAINER_HIGH" ]]   && SURFACE_CONTAINER_HIGH=$(adjust_color "$BG" 23)
[[ -z "$SURFACE_CONTAINER_HIGHEST" ]] && SURFACE_CONTAINER_HIGHEST=$(adjust_color "$BG" 34)
[[ -z "$OUTLINE_VARIANT" ]]          && OUTLINE_VARIANT=$(adjust_color "$BG" 52)
[[ -z "$PRIMARY_CONTAINER" ]]        && PRIMARY_CONTAINER=$(adjust_color "$PRIMARY" -26)
[[ -z "$ON_PRIMARY_CONTAINER" ]]     && ON_PRIMARY_CONTAINER="$FG"
[[ -z "$APP_HEADERBAR_BG" ]]         && APP_HEADERBAR_BG="$BG"
[[ -z "$APP_SIDEBAR_BG" ]]           && APP_SIDEBAR_BG="$BG"
[[ -z "$APP_CARD_BG" ]]              && APP_CARD_BG="$SURFACE_CONTAINER_LOW"
[[ -z "$APP_POPOVER_BG" ]]           && APP_POPOVER_BG="$SURFACE_CONTAINER"
[[ -z "$APP_DIALOG_BG" ]]            && APP_DIALOG_BG="$SURFACE_CONTAINER_HIGH"

# Derive semantic color fallbacks from Material tokens
[[ -z "$ERROR_COLOR" ]] && ERROR_COLOR="#ff6b6b"
[[ -z "$TERTIARY" ]]    && TERTIARY="#ffa94d"
[[ -z "$SECONDARY" ]]   && SECONDARY="#69db7c"
[[ -z "$SECONDARY_CONTAINER" ]] && SECONDARY_CONTAINER=$(adjust_color "$PRIMARY_CONTAINER" 8)

# Map to KDE/GTK semantic names from the shared app palette when available.
FG_NEGATIVE="${APP_ERROR:-$ERROR_COLOR}"
FG_NEUTRAL="${APP_WARNING:-$TERTIARY}"
FG_POSITIVE="${APP_SUCCESS:-$SECONDARY}"

avg_brightness() {
    local hex="${1#\#}"
    local r=$((0x${hex:0:2}))
    local g=$((0x${hex:2:2}))
    local b=$((0x${hex:4:2}))
    echo $(((r + g + b) / 3))
}

bg_avg=$(avg_brightness "$BG")
fg_avg=$(avg_brightness "$FG")

# Use smaller deltas for very dark/light colors to avoid clamping to #000000/#ffffff
bg_alt_delta=20
bg_dark_delta=-20
fg_inactive_delta=-60

if (( bg_avg < 40 )); then
    bg_alt_delta=12
    bg_dark_delta=-10
fi
if (( fg_avg < 80 )); then
    fg_inactive_delta=-35
fi

BG_ALT=$(adjust_color "$BG" $bg_alt_delta)
BG_DARK=$(adjust_color "$BG" $bg_dark_delta)
FG_INACTIVE=$(adjust_color "$FG" $fg_inactive_delta)

generate_pywalfox() {
    # Generate pywalfox-compatible JSON from Alis palette for Firefox theming
    local wallpaper_path=""
    local wp_file="$XDG_STATE_HOME/quickshell/user/generated/wallpaper/path.txt"
    [[ -f "$wp_file" ]] && wallpaper_path=$(cat "$wp_file" | tr -d '\n')

    cat << EOF
{
  "wallpaper": "$wallpaper_path",
  "alpha": "100",
  "special": {
    "background": "$BG",
    "foreground": "$FG",
    "cursor": "$PRIMARY"
  }
}
EOF
}

generate_kdeglobals() {
    local icon_theme font_raw mono_raw font_name font_size mono_name mono_size
    icon_theme=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")

    # Read current GTK fonts so wallpaper theme changes don't reset user fonts
    font_raw=$(gsettings get org.gnome.desktop.interface font-name 2>/dev/null | tr -d "'")
    mono_raw=$(gsettings get org.gnome.desktop.interface monospace-font-name 2>/dev/null | tr -d "'")
    if [[ -n "$font_raw" ]]; then
        font_size="${font_raw##* }"
        font_name="${font_raw% *}"
        font_name="${font_name%"${font_name##*[![:space:]]}"}"
    fi
    if [[ -n "$mono_raw" ]]; then
        mono_size="${mono_raw##* }"
        mono_name="${mono_raw% *}"
        mono_name="${mono_name%"${mono_name##*[![:space:]]}"}"
    fi
    if [[ -z "$icon_theme" ]]; then
        if [[ -d "$HOME/.local/share/icons/WhiteSur-dark" || -d "/usr/share/icons/WhiteSur-dark" ]]; then
            icon_theme=$(bash "$SCRIPT_DIR/icon-theme-for-mode.sh" WhiteSur-dark "$THEME_MODE")
        else
            icon_theme="Adwaita"
        fi
    fi

    cat << EOF
[ColorEffects:Disabled]
Color=${BG}
ColorAmount=0.5
ColorEffect=3
ContrastAmount=0
ContrastEffect=0
IntensityAmount=0
IntensityEffect=0

[ColorEffects:Inactive]
ChangeSelectionColor=true
Color=${BG_DARK}
ColorAmount=0.025
ColorEffect=0
ContrastAmount=0.1
ContrastEffect=0
Enable=false
IntensityAmount=0
IntensityEffect=0

[Colors:Button]
BackgroundAlternate=${BG_ALT}
BackgroundNormal=${SURFACE}
DecorationFocus=${PRIMARY}
DecorationHover=${PRIMARY_CONTAINER}
ForegroundActive=${FG}
ForegroundInactive=${FG_INACTIVE}
ForegroundLink=${PRIMARY}
ForegroundNegative=${FG_NEGATIVE}
ForegroundNeutral=${FG_NEUTRAL}
ForegroundNormal=${FG}
ForegroundPositive=${FG_POSITIVE}
ForegroundVisited=${PRIMARY}

[Colors:Selection]
BackgroundAlternate=${KDE_SELECTION_ALT}
BackgroundNormal=${KDE_SELECTION_BG}
DecorationFocus=${KDE_DECORATION_FOCUS}
DecorationHover=${KDE_DECORATION_HOVER}
ForegroundActive=${KDE_SELECTION_FG}
ForegroundInactive=${KDE_SELECTION_FG_INACTIVE}
ForegroundLink=${KDE_SELECTION_FG}
ForegroundNegative=${FG_NEGATIVE}
ForegroundNeutral=${FG_NEUTRAL}
ForegroundNormal=${KDE_SELECTION_FG}
ForegroundPositive=${FG_POSITIVE}
ForegroundVisited=${KDE_SELECTION_FG}

[Colors:Tooltip]
BackgroundAlternate=${BG_ALT}
BackgroundNormal=${BG}
DecorationFocus=${PRIMARY}
DecorationHover=${PRIMARY}
ForegroundActive=${FG}
ForegroundInactive=${FG_INACTIVE}
ForegroundLink=${PRIMARY}
ForegroundNegative=${FG_NEGATIVE}
ForegroundNeutral=${FG_NEUTRAL}
ForegroundNormal=${FG}
ForegroundPositive=${FG_POSITIVE}
ForegroundVisited=${PRIMARY}

[Colors:View]
BackgroundAlternate=${BG}
BackgroundNormal=${BG}
DecorationFocus=${PRIMARY}
DecorationHover=${ROW_HOVER_BG}
ForegroundActive=${FG}
ForegroundInactive=${FG_INACTIVE}
ForegroundLink=${PRIMARY}
ForegroundNegative=${FG_NEGATIVE}
ForegroundNeutral=${FG_NEUTRAL}
ForegroundNormal=${FG}
ForegroundPositive=${FG_POSITIVE}
ForegroundVisited=${PRIMARY}

[Colors:Window]
BackgroundAlternate=${BG}
BackgroundNormal=${BG}
DecorationFocus=${PRIMARY}
DecorationHover=${ROW_HOVER_BG}
ForegroundActive=${FG}
ForegroundInactive=${FG_INACTIVE}
ForegroundLink=${PRIMARY}
ForegroundNegative=${FG_NEGATIVE}
ForegroundNeutral=${FG_NEUTRAL}
ForegroundNormal=${FG}
ForegroundPositive=${FG_POSITIVE}
ForegroundVisited=${PRIMARY}

[Colors:Complementary]
BackgroundAlternate=${BG_DARK}
BackgroundNormal=${BG}
DecorationFocus=${PRIMARY}
DecorationHover=${ROW_HOVER_BG}
ForegroundActive=${FG}
ForegroundInactive=${FG_INACTIVE}
ForegroundLink=${PRIMARY}
ForegroundNegative=${FG_NEGATIVE}
ForegroundNeutral=${FG_NEUTRAL}
ForegroundNormal=${FG}
ForegroundPositive=${FG_POSITIVE}
ForegroundVisited=${PRIMARY}

[Colors:Header]
BackgroundAlternate=${BG}
BackgroundNormal=${BG}
DecorationFocus=${PRIMARY}
DecorationHover=${ROW_HOVER_BG}
ForegroundActive=${FG}
ForegroundInactive=${FG_INACTIVE}
ForegroundLink=${PRIMARY}
ForegroundNegative=${FG_NEGATIVE}
ForegroundNeutral=${FG_NEUTRAL}
ForegroundNormal=${FG}
ForegroundPositive=${FG_POSITIVE}
ForegroundVisited=${PRIMARY}

[Colors:Header][Inactive]
BackgroundAlternate=${BG}
BackgroundNormal=${BG}
DecorationFocus=${PRIMARY}
DecorationHover=${ROW_HOVER_BG}
ForegroundActive=${FG}
ForegroundInactive=${FG_INACTIVE}
ForegroundLink=${PRIMARY}
ForegroundNegative=${FG_NEGATIVE}
ForegroundNeutral=${FG_NEUTRAL}
ForegroundNormal=${FG}
ForegroundPositive=${FG_POSITIVE}
ForegroundVisited=${PRIMARY}

[Colors:Menu]
BackgroundAlternate=${BG_ALT}
BackgroundNormal=${BG}
DecorationFocus=${PRIMARY}
DecorationHover=${ROW_HOVER_BG}
ForegroundActive=${FG}
ForegroundInactive=${FG_INACTIVE}
ForegroundLink=${PRIMARY}
ForegroundNegative=${FG_NEGATIVE}
ForegroundNeutral=${FG_NEUTRAL}
ForegroundNormal=${FG}
ForegroundPositive=${FG_POSITIVE}
ForegroundVisited=${PRIMARY}

[General]
ColorScheme=Darkly
${font_name:+fixed=${mono_name:-$font_name},${mono_size:-$font_size},-1,5,50,0,0,0,0,0}
${font_name:+font=${font_name},${font_size},-1,5,50,0,0,0,0,0}
${font_name:+menuFont=${font_name},${font_size},-1,5,50,0,0,0,0,0}
${font_name:+toolBarFont=${font_name},${font_size},-1,5,50,0,0,0,0,0}

[Icons]
Theme=${icon_theme}

[KDE]
widgetStyle=Darkly

[WM]
activeBackground=${BG}
activeBlend=${FG}
activeForeground=${FG}
inactiveBackground=${BG}
inactiveBlend=${FG_INACTIVE}
inactiveForeground=${FG_INACTIVE}
EOF
}

# Helper to convert hex to RGB
hex_to_rgb() {
    local hex="${1#\#}"
    local r=$((0x${hex:0:2}))
    local g=$((0x${hex:2:2}))
    local b=$((0x${hex:4:2}))
    echo "$r,$g,$b"
}

# Blend two hex colors using integer percent of top over base.
# blend_rgb_percent "#base" "#top" 20  => 20% top, 80% base
blend_rgb_percent() {
    local base="${1#\#}"
    local top="${2#\#}"
    local pct="${3:-20}"
    local inv=$((100 - pct))

    local br=$((0x${base:0:2}))
    local bg=$((0x${base:2:2}))
    local bb=$((0x${base:4:2}))

    local tr=$((0x${top:0:2}))
    local tg=$((0x${top:2:2}))
    local tb=$((0x${top:4:2}))

    local r=$(((br * inv + tr * pct + 50) / 100))
    local g=$(((bg * inv + tg * pct + 50) / 100))
    local b=$(((bb * inv + tb * pct + 50) / 100))
    echo "$r,$g,$b"
}

blend_hex_percent() {
    local rgb
    rgb=$(blend_rgb_percent "$1" "$2" "${3:-20}")
    local r g b
    IFS=',' read -r r g b <<< "$rgb"
    printf "#%02X%02X%02X" "$r" "$g" "$b"
}

# Shared interaction tones (Vesktop-like subtle states, not raw accent blocks)
ROW_HOVER_BG=$(blend_hex_percent "$SURFACE_CONTAINER" "$PRIMARY" 12)
ROW_ACTIVE_BG=$(blend_hex_percent "$SURFACE_CONTAINER_HIGH" "$PRIMARY" 18)
ROW_ACTIVE_HOVER_BG=$(blend_hex_percent "$SURFACE_CONTAINER_HIGH" "$PRIMARY" 26)
ROW_SELECTED_FG="$FG"
[[ -n "$APP_SELECTION" ]]       && ROW_ACTIVE_BG="$APP_SELECTION"
[[ -n "$APP_SELECTION_HOVER" ]] && ROW_ACTIVE_HOVER_BG="$APP_SELECTION_HOVER"
[[ -n "$APP_ON_SELECTION" ]]    && ROW_SELECTED_FG="$APP_ON_SELECTION"

# Qt/KDE consumes semantic palette roles rather than CSS state rules. Keep the
# selected row/tab and focus decoration on the same quiet accent-container
# family as GTK, including readable secondary text on the selected fill.
KDE_SELECTION_BG="${APP_SELECTION:-$ROW_ACTIVE_BG}"
KDE_SELECTION_ALT="${APP_SELECTION_HOVER:-$ROW_ACTIVE_HOVER_BG}"
KDE_SELECTION_FG="${APP_ON_SELECTION:-$ROW_SELECTED_FG}"
KDE_SELECTION_FG_INACTIVE=$(blend_hex_percent "$KDE_SELECTION_FG" "$KDE_SELECTION_BG" 18)
KDE_DECORATION_HOVER="${APP_SELECTION:-$ROW_ACTIVE_BG}"
KDE_DECORATION_FOCUS="${APP_SELECTION_HOVER:-$ROW_ACTIVE_HOVER_BG}"

# Generate Darkly.colors for Qt style override
generate_darkly_colors() {
    local bg_rgb=$(hex_to_rgb "$BG")
    local bg_alt_rgb=$(hex_to_rgb "$BG_ALT")
    local bg_dark_rgb=$(hex_to_rgb "$BG_DARK")
    local fg_rgb=$(hex_to_rgb "$FG")
    local fg_inactive_rgb=$(hex_to_rgb "$FG_INACTIVE")
    local primary_rgb=$(hex_to_rgb "$PRIMARY")
    local on_primary_rgb=$(hex_to_rgb "$ON_PRIMARY")
    local surface_rgb=$(hex_to_rgb "$SURFACE")
    local error_rgb=$(hex_to_rgb "$FG_NEGATIVE")
    local neutral_rgb=$(hex_to_rgb "$FG_NEUTRAL")
    local positive_rgb=$(hex_to_rgb "$FG_POSITIVE")
    local selection_bg_rgb=$(hex_to_rgb "$KDE_SELECTION_BG")
    local selection_bg_alt_rgb=$(hex_to_rgb "$KDE_SELECTION_ALT")
    local selection_fg_rgb=$(hex_to_rgb "$KDE_SELECTION_FG")
    local decoration_hover_rgb=$(hex_to_rgb "$KDE_DECORATION_HOVER")
    local decoration_focus_rgb=$(hex_to_rgb "$KDE_DECORATION_FOCUS")

    cat << EOF
[ColorEffects:Disabled]
Color=${bg_rgb}
ColorAmount=0.5
ColorEffect=3
ContrastAmount=0.5
ContrastEffect=0
IntensityAmount=0
IntensityEffect=0

[ColorEffects:Inactive]
ChangeSelectionColor=true
Color=${bg_dark_rgb}
ColorAmount=0.4
ColorEffect=3
ContrastAmount=0.4
ContrastEffect=0
Enable=true
IntensityAmount=-0.2
IntensityEffect=0

[Colors:Button]
BackgroundAlternate=${bg_alt_rgb}
BackgroundNormal=${surface_rgb}
DecorationFocus=${primary_rgb}
DecorationHover=$(hex_to_rgb "$PRIMARY_CONTAINER")
ForegroundActive=${fg_rgb}
ForegroundInactive=${fg_inactive_rgb}
ForegroundLink=${primary_rgb}
ForegroundNegative=${error_rgb}
ForegroundNeutral=${neutral_rgb}
ForegroundNormal=${fg_rgb}
ForegroundPositive=${positive_rgb}
ForegroundVisited=${primary_rgb}

[Colors:Complementary]
BackgroundAlternate=${bg_dark_rgb}
BackgroundNormal=${bg_rgb}
DecorationFocus=${primary_rgb}
DecorationHover=$(hex_to_rgb "$PRIMARY_CONTAINER")
ForegroundActive=${fg_rgb}
ForegroundInactive=${fg_inactive_rgb}
ForegroundLink=${primary_rgb}
ForegroundNegative=${error_rgb}
ForegroundNeutral=${neutral_rgb}
ForegroundNormal=${fg_rgb}
ForegroundPositive=${positive_rgb}
ForegroundVisited=${primary_rgb}

[Colors:Selection]
BackgroundAlternate=${selection_bg_alt_rgb}
BackgroundNormal=${selection_bg_rgb}
DecorationFocus=${decoration_focus_rgb}
DecorationHover=${decoration_hover_rgb}
ForegroundActive=${selection_fg_rgb}
ForegroundInactive=$(hex_to_rgb "$KDE_SELECTION_FG_INACTIVE")
ForegroundLink=${selection_fg_rgb}
ForegroundNegative=${error_rgb}
ForegroundNeutral=${neutral_rgb}
ForegroundNormal=${selection_fg_rgb}
ForegroundPositive=${positive_rgb}
ForegroundVisited=${selection_fg_rgb}

[Colors:Header]
BackgroundAlternate=${bg_alt_rgb}
BackgroundNormal=${bg_rgb}
DecorationFocus=${primary_rgb}
DecorationHover=$(hex_to_rgb "$PRIMARY_CONTAINER")
ForegroundActive=${fg_rgb}
ForegroundInactive=${fg_inactive_rgb}
ForegroundLink=${primary_rgb}
ForegroundNegative=${error_rgb}
ForegroundNeutral=${neutral_rgb}
ForegroundNormal=${fg_rgb}
ForegroundPositive=${positive_rgb}
ForegroundVisited=${primary_rgb}

[Colors:Tooltip]
BackgroundAlternate=${bg_alt_rgb}
BackgroundNormal=${bg_rgb}
DecorationFocus=${primary_rgb}
DecorationHover=${primary_rgb}
ForegroundActive=${fg_rgb}
ForegroundInactive=${fg_inactive_rgb}
ForegroundLink=${primary_rgb}
ForegroundNegative=${error_rgb}
ForegroundNeutral=${neutral_rgb}
ForegroundNormal=${fg_rgb}
ForegroundPositive=${positive_rgb}
ForegroundVisited=${primary_rgb}

[Colors:View]
BackgroundAlternate=${bg_rgb}
BackgroundNormal=${bg_rgb}
DecorationFocus=${primary_rgb}
DecorationHover=$(hex_to_rgb "$PRIMARY_CONTAINER")
ForegroundActive=${fg_rgb}
ForegroundInactive=${fg_inactive_rgb}
ForegroundLink=${primary_rgb}
ForegroundNegative=${error_rgb}
ForegroundNeutral=${neutral_rgb}
ForegroundNormal=${fg_rgb}
ForegroundPositive=${positive_rgb}
ForegroundVisited=${primary_rgb}

[Colors:Window]
BackgroundAlternate=${bg_alt_rgb}
BackgroundNormal=${bg_rgb}
DecorationFocus=${primary_rgb}
DecorationHover=$(hex_to_rgb "$PRIMARY_CONTAINER")
ForegroundActive=${fg_rgb}
ForegroundInactive=${fg_inactive_rgb}
ForegroundLink=${primary_rgb}
ForegroundNegative=${error_rgb}
ForegroundNeutral=${neutral_rgb}
ForegroundNormal=${fg_rgb}
ForegroundPositive=${positive_rgb}
ForegroundVisited=${primary_rgb}

[General]
ColorScheme=Darkly
Name=Darkly
shadeSortColumn=true

[KDE]
contrast=0

[WM]
activeBackground=${bg_rgb}
activeBlend=255,255,255
activeForeground=${fg_rgb}
inactiveBackground=${bg_rgb}
inactiveBlend=${fg_inactive_rgb}
inactiveForeground=${fg_inactive_rgb}
EOF
}

# Apply KDE/Qt theming if enabled
if [[ "$enable_qt_apps" != "false" ]]; then
    generate_kdeglobals > "$KDEGLOBALS"

    # Generate Darkly color scheme for Qt style
    mkdir -p "$(dirname "$DARKLY_COLORS")"
    generate_darkly_colors > "$DARKLY_COLORS"
fi

# Generate Pywalfox colors for Firefox theming
mkdir -p "$XDG_STATE_HOME/quickshell/user/generated"
generate_pywalfox > "$XDG_STATE_HOME/quickshell/user/generated/pywalfox-colors.json"

# Generate GTK3 CSS (legacy apps)
gtk_css_changed=false
GTK3_CSS="$HOME/.config/gtk-3.0/gtk.css"
mkdir -p "$(dirname "$GTK3_CSS")"
break_symlink "$GTK3_CSS"
if write_if_changed "$GTK3_CSS" << EOF
/*
 * GTK Colors - Generated with Alis theming
 * This file is overwritten when you change wallpaper
 */

@define-color accent_color ${PRIMARY};
@define-color accent_fg_color ${ON_PRIMARY};
@define-color accent_bg_color ${PRIMARY};

@define-color window_bg_color ${BG};
@define-color window_fg_color ${FG};

@define-color headerbar_bg_color ${APP_HEADERBAR_BG};
@define-color headerbar_fg_color ${FG};

@define-color popover_bg_color ${APP_POPOVER_BG};
@define-color popover_fg_color ${ON_SURFACE};

@define-color view_bg_color ${BG};
@define-color view_fg_color ${FG};

@define-color card_bg_color ${APP_CARD_BG};
@define-color card_fg_color ${ON_SURFACE};

@define-color success_color ${FG_POSITIVE};
@define-color warning_color ${FG_NEUTRAL};
@define-color error_color ${FG_NEGATIVE};
@define-color destructive_color ${FG_NEGATIVE};
@define-color success_bg_color ${FG_POSITIVE};
@define-color warning_bg_color ${FG_NEUTRAL};
@define-color error_bg_color ${FG_NEGATIVE};
@define-color destructive_bg_color ${FG_NEGATIVE};
@define-color success_fg_color ${BG};
@define-color warning_fg_color ${BG};
@define-color error_fg_color ${BG};
@define-color destructive_fg_color ${BG};

@define-color sidebar_bg_color ${APP_SIDEBAR_BG};
@define-color sidebar_fg_color ${FG};
@define-color sidebar_border_color ${BG};
@define-color sidebar_backdrop_color ${BG};

headerbar {
    background-color: ${APP_HEADERBAR_BG};
    box-shadow: none;
    border-bottom: none;
}

headerbar separator {
    background-color: transparent;
}

.nautilus-window .sidebar,
.nautilus-window sidebar,
placessidebar,
placessidebar list {
    background-color: ${APP_SIDEBAR_BG};
    color: ${FG};
    border-right: none;
}

placessidebar row {
    background-color: transparent;
    color: ${FG};
}

placessidebar row:hover {
    background-color: ${ROW_HOVER_BG};
}

placessidebar row:selected,
placessidebar row:selected:hover {
    background-color: ${ROW_ACTIVE_BG};
    color: ${ROW_SELECTED_FG};
}

placessidebar image {
    color: inherit;
}

.view {
    background-color: ${BG};
}

separator.sidebar {
    background-color: transparent;
    min-width: 0;
}

/* Context menus and popovers */
popover,
popover.background {
    background-color: ${APP_POPOVER_BG};
    color: ${ON_SURFACE};
}

menu,
.context-menu,
.popup {
    background-color: ${APP_POPOVER_BG};
    color: ${ON_SURFACE};
}

menuitem {
    color: ${ON_SURFACE};
}

menuitem:hover,
menuitem:selected {
    background-color: ${ROW_HOVER_BG};
}

menuitem:active,
menuitem:selected:active {
    background-color: ${ROW_ACTIVE_BG};
    color: ${ROW_SELECTED_FG};
}

button:hover {
    background-color: ${ROW_HOVER_BG};
}

button:active {
    background-color: ${ROW_ACTIVE_BG};
    color: ${ROW_SELECTED_FG};
}

entry:focus,
textview:focus,
spinbutton:focus {
    border-color: alpha(${PRIMARY}, 0.60);
    box-shadow: 0 0 0 1px alpha(${PRIMARY}, 0.25) inset;
}

menu separator {
    background-color: alpha(${ON_SURFACE}, 0.12);
}
EOF
then
    gtk_css_changed=true
fi

# Generate GTK4/libadwaita CSS (Nautilus, GNOME apps)
# GTK4 does NOT support !important - use CSS custom properties instead
GTK4_CSS="$HOME/.config/gtk-4.0/gtk.css"
mkdir -p "$(dirname "$GTK4_CSS")"
break_symlink "$GTK4_CSS"
if write_if_changed "$GTK4_CSS" << EOF
/*
 * GTK4/libadwaita Colors — Generated by Alis theming
 * This file is overwritten when you change wallpaper or apply a color theme.
 *
 * GTK4 does not support !important - colors are set via CSS custom properties
 * which libadwaita widgets read from :root. Priority USER (800) > theme (200).
 */

/* CSS custom properties for libadwaita color overrides */
:root {
    /* Accent */
    --accent-bg-color: ${PRIMARY};
    --accent-fg-color: ${ON_PRIMARY};
    --accent-color: ${PRIMARY};

    /* Window */
    --window-bg-color: ${BG};
    --window-fg-color: ${FG};

    /* View */
    --view-bg-color: ${BG};
    --view-fg-color: ${FG};

    /* Headerbar */
    --headerbar-bg-color: ${APP_HEADERBAR_BG};
    --headerbar-fg-color: ${FG};
    --headerbar-backdrop-color: ${APP_HEADERBAR_BG};
    --headerbar-border-color: transparent;
    --headerbar-shade-color: transparent;
    --headerbar-darker-shade-color: transparent;

    /* Sidebar */
    --sidebar-bg-color: ${APP_SIDEBAR_BG};
    --sidebar-fg-color: ${FG};
    --sidebar-backdrop-color: ${APP_SIDEBAR_BG};
    --sidebar-border-color: transparent;
    --sidebar-shade-color: rgba(0, 0, 0, 0.25);

    /* Secondary Sidebar (Nautilus places) */
    --secondary-sidebar-bg-color: ${APP_SIDEBAR_BG};
    --secondary-sidebar-fg-color: ${FG};
    --secondary-sidebar-backdrop-color: ${APP_SIDEBAR_BG};
    --secondary-sidebar-border-color: transparent;
    --secondary-sidebar-shade-color: rgba(0, 0, 0, 0.25);

    /* Popover */
    --popover-bg-color: ${APP_POPOVER_BG};
    --popover-fg-color: ${ON_SURFACE};
    --popover-shade-color: rgba(0, 0, 0, 0.25);

    /* Dialog */
    --dialog-bg-color: ${APP_DIALOG_BG};
    --dialog-fg-color: ${ON_SURFACE};

    /* Card */
    --card-bg-color: ${APP_CARD_BG};
    --card-fg-color: ${ON_SURFACE};
    --card-shade-color: rgba(0, 0, 0, 0.15);

    /* Thumbnail */
    --thumbnail-bg-color: ${SURFACE_CONTAINER_HIGHEST};
    --thumbnail-fg-color: ${ON_SURFACE};

    /* Semantic status colours from the shared app palette */
    --success-color: ${FG_POSITIVE};
    --success-bg-color: ${FG_POSITIVE};
    --success-fg-color: ${BG};
    --warning-color: ${FG_NEUTRAL};
    --warning-bg-color: ${FG_NEUTRAL};
    --warning-fg-color: ${BG};
    --error-color: ${FG_NEGATIVE};
    --error-bg-color: ${FG_NEGATIVE};
    --error-fg-color: ${BG};
    --destructive-color: ${FG_NEGATIVE};
    --destructive-bg-color: ${FG_NEGATIVE};
    --destructive-fg-color: ${BG};

    /* Misc */
    --shade-color: rgba(0, 0, 0, 0.25);
    --scrollbar-outline-color: rgba(255, 255, 255, 0.1);
}

/* Tooltip styling - children need transparent bg */
tooltip * {
    background-color: transparent;
}

tooltip.background {
    background-color: ${APP_POPOVER_BG};
    color: ${ON_SURFACE};
}
EOF
then
    gtk_css_changed=true
fi

# Configure qt6ct to use the Darkly color scheme (fixes Dolphin and other Qt apps being white)
# qt6ct is the platform theme (QT_QPA_PLATFORMTHEME=qt6ct) — it needs a color scheme
QT6CT_CONF="$HOME/.config/qt6ct/qt6ct.conf"
mkdir -p "$(dirname "$QT6CT_CONF")"
touch "$QT6CT_CONF"
CURRENT_ICON_THEME="$APPLIED_ICON_THEME"
[[ -z "$CURRENT_ICON_THEME" ]] && CURRENT_ICON_THEME=$(grep '^icon_theme=' "$QT6CT_CONF" 2>/dev/null | cut -d= -f2 || true)
if [[ -z "$CURRENT_ICON_THEME" ]]; then
    if [[ -d "$HOME/.local/share/icons/WhiteSur-dark" || -d "/usr/share/icons/WhiteSur-dark" ]]; then
        CURRENT_ICON_THEME=$(bash "$SCRIPT_DIR/icon-theme-for-mode.sh" WhiteSur-dark "$THEME_MODE")
    else
        CURRENT_ICON_THEME="Adwaita"
    fi
fi
CURRENT_QT_STYLE=$(grep '^style=' "$QT6CT_CONF" 2>/dev/null | cut -d= -f2 || true)
[[ -z "$CURRENT_QT_STYLE" ]] && CURRENT_QT_STYLE="Darkly"
cat > "$QT6CT_CONF" << EOF
[Appearance]
color_scheme_path=${DARKLY_COLORS}
custom_palette=true
icon_theme=${CURRENT_ICON_THEME}
style=${CURRENT_QT_STYLE}
EOF

# Configure qt5ct to use the Darkly color scheme (mirrors qt6ct setup above)
QT5CT_CONF="$HOME/.config/qt5ct/qt5ct.conf"
mkdir -p "$(dirname "$QT5CT_CONF")"
touch "$QT5CT_CONF"
CURRENT_QT5_ICON_THEME="$APPLIED_ICON_THEME"
[[ -z "$CURRENT_QT5_ICON_THEME" ]] && CURRENT_QT5_ICON_THEME=$(grep '^icon_theme=' "$QT5CT_CONF" 2>/dev/null | cut -d= -f2 || true)
[[ -z "$CURRENT_QT5_ICON_THEME" ]] && CURRENT_QT5_ICON_THEME="$CURRENT_ICON_THEME"
CURRENT_QT5_STYLE=$(grep '^style=' "$QT5CT_CONF" 2>/dev/null | cut -d= -f2 || true)
[[ -z "$CURRENT_QT5_STYLE" ]] && CURRENT_QT5_STYLE="Darkly"
cat > "$QT5CT_CONF" << EOF
[Appearance]
color_scheme_path=${DARKLY_COLORS}
custom_palette=true
icon_theme=${CURRENT_QT5_ICON_THEME}
style=${CURRENT_QT5_STYLE}
EOF

# Keep static GTK settings aligned with GSettings. GTK applications are split
# between the desktop settings service and settings.ini readers, so stale files
# otherwise produce different fonts/themes depending on which process owns a
# dialog (notably xdg-desktop-portal-gtk file choosers).
gtk_settings_changed=false
ensure_valid_gtk_settings_ini() {
    local settings_file="$1"
    local defaults_file="$2"

    if [[ -f "$settings_file" ]] && grep -q '^\[Settings\][[:space:]]*$' "$settings_file"; then
        return 0
    fi

    mkdir -p "$(dirname "$settings_file")"
    if [[ -s "$settings_file" ]]; then
        local backup="${settings_file}.corrupt-$(date +%Y%m%d-%H%M%S).bak"
        cp -a "$settings_file" "$backup"
        echo "[apply-gtk-theme] backed up invalid GTK settings to $backup" >&2
    fi

    if [[ -f "$defaults_file" ]]; then
        cp -f "$defaults_file" "$settings_file"
    else
        printf '[Settings]\n' > "$settings_file"
    fi
    gtk_settings_changed=true
}

set_gtk_setting() {
    local settings_file="$1"
    local key="$2"
    local value="$3"
    [[ -n "$value" ]] || return 0

    local escaped
    escaped=$(printf '%s' "$value" | sed 's/[\\&|]/\\&/g')
    if grep -q "^${key}=" "$settings_file"; then
        sed -i "s|^${key}=.*|${key}=${escaped}|" "$settings_file"
    else
        printf '\n%s=%s\n' "$key" "$value" >> "$settings_file"
    fi
}

remove_gtk_setting() {
    local settings_file="$1"
    local key="$2"

    if grep -q "^${key}=" "$settings_file"; then
        sed -i "/^${key}=/d" "$settings_file"
    fi
}

sync_gtk_settings_ini() {
    local settings_file="$1"
    local defaults_file="$2"
    local legacy_dark_preference="${3:-false}"
    ensure_valid_gtk_settings_ini "$settings_file" "$defaults_file"

    local before current_icon current_cursor current_font current_theme current_scheme prefer_dark
    before=$(cksum "$settings_file" 2>/dev/null || true)
    current_icon=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
    current_cursor=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
    current_font=$(gsettings get org.gnome.desktop.interface font-name 2>/dev/null | tr -d "'")
    current_theme=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
    current_scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
    prefer_dark=0
    [[ "$current_scheme" == "prefer-dark" ]] && prefer_dark=1

    set_gtk_setting "$settings_file" "gtk-icon-theme-name" "$current_icon"
    set_gtk_setting "$settings_file" "gtk-cursor-theme-name" "$current_cursor"
    set_gtk_setting "$settings_file" "gtk-font-name" "$current_font"
    set_gtk_setting "$settings_file" "gtk-theme-name" "$current_theme"
    if [[ "$legacy_dark_preference" == "true" ]]; then
        set_gtk_setting "$settings_file" "gtk-application-prefer-dark-theme" "$prefer_dark"
    else
        # GTK4/libadwaita takes dark preference from the standardized
        # org.gnome.desktop.interface color-scheme setting. Keeping the old
        # GtkSettings key makes libadwaita emit a warning on every process
        # startup and can disagree with AdwStyleManager.
        remove_gtk_setting "$settings_file" "gtk-application-prefer-dark-theme"
    fi

    if [[ "$before" != "$(cksum "$settings_file" 2>/dev/null || true)" ]]; then
        gtk_settings_changed=true
    fi
}

sync_gtk_settings_ini "$HOME/.config/gtk-3.0/settings.ini" "$SCRIPT_DIR/../../defaults/gtk-3.0/settings.ini" true
sync_gtk_settings_ini "$HOME/.config/gtk-4.0/settings.ini" "$SCRIPT_DIR/../../defaults/gtk-4.0/settings.ini" false

# GTK user CSS is loaded per process. Refresh only consumers that are known to
# stay alive across theme changes; restarting the GTK portal backend makes new
# file chooser/access dialogs use the current generated palette.
if [[ "$gtk_css_changed" == true || "$gtk_settings_changed" == true ]]; then
    if pgrep -x nautilus >/dev/null 2>&1; then
        nautilus -q >/dev/null 2>&1 || true
    fi
    if command -v systemctl >/dev/null 2>&1 \
            && systemctl --user is-active --quiet xdg-desktop-portal-gtk.service; then
        systemctl --user try-restart xdg-desktop-portal-gtk.service >/dev/null 2>&1 || true
    fi
fi
