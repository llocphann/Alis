#!/usr/bin/env bash
#
# apply-chrome-theme.sh — Apply Material You wallpaper colors across web browsers
#
# Usage:
#   apply-chrome-theme.sh                  # auto-detect palette & apply (never prompts for sudo/pkexec)
#   apply-chrome-theme.sh "#ff6b35"        # explicit hex seed color
#   apply-chrome-theme.sh --disable        # remove Alis browser overrides & restore user themes
#   apply-chrome-theme.sh --setup-policies # interactive one-time policy directory setup for live reload
#   apply-chrome-theme.sh --zen-live-setup # open 1-click live extension installer in Zen Browser
#
# Supports (Native & Flatpak):
#   Zen Browser, Brave, Vivaldi, Google Chrome, Chromium, Microsoft Edge, Firefox / LibreWolf / Floorp

set -uo pipefail

XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="$XDG_STATE_HOME/quickshell"
CHROMIUM_THEME_FILE="$STATE_DIR/user/generated/chromium.theme"
LOG_FILE="$STATE_DIR/user/generated/chrome_theme.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/config-path.sh
source "$SCRIPT_DIR/../lib/config-path.sh"
mkdir -p "$STATE_DIR/user/generated" 2>/dev/null
: > "$LOG_FILE" 2>/dev/null

log() { echo "[chrome] $*" >> "$LOG_FILE"; }

hex_to_rgb() {
  local hex=$1
  hex="${hex#\#}"
  printf "%d,%d,%d" "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

rgb_to_hex() {
  local rgb="$1"
  local r g b
  IFS=',' read -r r g b <<< "$rgb"
  [[ "$r" =~ ^[0-9]+$ && "$g" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ ]] || return 1
  (( r >= 0 && r <= 255 && g >= 0 && g <= 255 && b >= 0 && b <= 255 )) || return 1
  printf '#%02X%02X%02X\n' "$r" "$g" "$b"
}

is_omarchy() {
  local bin_path
  bin_path=$(command -v "$1" 2>/dev/null || true)
  if [[ -n "$bin_path" ]] && command -v pacman &>/dev/null; then
    pacman -Qo "$bin_path" 2>/dev/null | grep -qi "omarchy" && return 0
  fi
  return 1
}

resolve_color() {
  if [[ -n "${1:-}" && "$1" =~ ^#[A-Fa-f0-9]{6}$ ]]; then
    echo "$1"
    return
  fi

  if [[ -f "$CHROMIUM_THEME_FILE" ]]; then
    local rgb_color hex_color
    rgb_color=$(tr -d '[:space:]' < "$CHROMIUM_THEME_FILE")
    if [[ "$rgb_color" =~ ^[0-9]{1,3},[0-9]{1,3},[0-9]{1,3}$ ]]; then
      hex_color=$(rgb_to_hex "$rgb_color" 2>/dev/null || true)
      if [[ -n "$hex_color" ]]; then
        echo "$hex_color"
        return
      fi
    fi
  fi

  local seed_file="$STATE_DIR/user/generated/color.txt"
  if [[ -f "$seed_file" ]]; then
    local c
    c=$(tr -d '\n[:space:]' < "$seed_file")
    if [[ -n "$c" && "$c" =~ ^#[A-Fa-f0-9]{6}$ ]]; then
      echo "$c"
      return
    fi
  fi

  local colors_json="$STATE_DIR/user/generated/app-palette.json"
  [[ -f "$colors_json" ]] || colors_json="$STATE_DIR/user/generated/palette.json"
  [[ -f "$colors_json" ]] || colors_json="$STATE_DIR/user/generated/colors.json"
  if [[ -f "$colors_json" ]] && command -v jq &>/dev/null; then
    local c
    c=$(jq -r '.primary // .app_accent // .app_headerbar_bg // .surface // .background // empty' "$colors_json" 2>/dev/null || true)
    if [[ -n "$c" ]]; then
      echo "$c"
      return
    fi
  fi
}

resolve_color_scheme() {
  local meta_file="$STATE_DIR/user/generated/theme-meta.json"
  if [[ -f "$meta_file" ]] && command -v jq &>/dev/null; then
    local mode
    mode=$(jq -r '.mode // empty' "$meta_file" 2>/dev/null || true)
    if [[ "$mode" == "dark" || "$mode" == "light" ]]; then
      echo "$mode"
      return
    fi
  fi

  local scss_file="$STATE_DIR/user/generated/material_colors.scss"
  if [[ -f "$scss_file" ]]; then
    local val
    val=$(grep '^\$darkmode:' "$scss_file" | sed 's/.*: *\(.*\);/\1/' | tr -d ' ')
    if [[ "$val" == "True" || "$val" == "true" ]]; then
      echo "dark"
      return
    fi
  fi
  echo "dark"
}

resolve_variant() {
  local config_file
  config_file="$(alis_config_file)"
  if [[ -f "$config_file" ]] && command -v jq &>/dev/null; then
    local variant chrome_variant
    variant=$(jq -r '.appearance.palette.type // "auto"' "$config_file" 2>/dev/null || true)
    if [[ -n "$variant" && "$variant" != "null" && "$variant" != "auto" ]]; then
      chrome_variant=$(echo "$variant" | sed 's/scheme-//' | tr '-' '_')
      case "$chrome_variant" in
        tonal_spot|neutral|vibrant|expressive)
          echo "$chrome_variant"
          return
          ;;
        *)
          echo "neutral"
          return
          ;;
      esac
    fi
  fi
  echo "tonal_spot"
}

setup_policies_interactive() {
  if [[ ! -t 0 || ! -t 1 ]]; then
    echo "Error: --setup-policies must be run interactively in a terminal." >&2
    return 1
  fi
  local dirs=(
    "/etc/chromium/policies/managed"
    "/etc/opt/chrome/policies/managed"
    "/etc/brave/policies/managed"
    "/etc/vivaldi/policies/managed"
    "/etc/opt/edge/policies/managed"
  )
  sudo mkdir -p "${dirs[@]}" && sudo chmod a+rw "${dirs[@]}"
}

main() {
  if [[ "${1:-}" == "--setup-policies" ]]; then
    setup_policies_interactive
    return $?
  fi

  if [[ "${1:-}" == "--zen-live-setup" ]]; then
    python3 "$SCRIPT_DIR/apply-browser-themes.py" --state-dir "$STATE_DIR"
    if command -v flatpak &>/dev/null && flatpak info app.zen_browser.zen &>/dev/null; then
      flatpak run app.zen_browser.zen "http://127.0.0.1:43821/install" >/dev/null 2>&1 & disown
    elif command -v zen-browser &>/dev/null; then
      zen-browser "http://127.0.0.1:43821/install" >/dev/null 2>&1 & disown
    elif command -v xdg-open &>/dev/null; then
      xdg-open "http://127.0.0.1:43821/install" >/dev/null 2>&1 & disown
    fi
    return 0
  fi

  if [[ "${1:-}" == "--disable" ]]; then
    python3 "$SCRIPT_DIR/apply-browser-themes.py" --disable --state-dir "$STATE_DIR"
    return $?
  fi

  local theme_color mode variant
  theme_color=$(resolve_color "${1:-}" || true)
  mode=$(resolve_color_scheme)
  variant=$(resolve_variant)

  local py_args=(--state-dir "$STATE_DIR" --mode "$mode" --variant "$variant")
  if [[ -n "$theme_color" ]]; then
    py_args+=(--color "$theme_color")
  fi

  python3 "$SCRIPT_DIR/apply-browser-themes.py" "${py_args[@]}"

  # Preserve Omarchy Chromium fork instant CLI update when running
  if [[ -n "$theme_color" ]]; then
    local rgb_color
    rgb_color=$(hex_to_rgb "$theme_color")
    for bin in chromium google-chrome-stable brave; do
      if command -v "$bin" &>/dev/null && pgrep -x "$bin" >/dev/null 2>&1 && is_omarchy "$bin"; then
        "$bin" --no-startup-window \
               --refresh-platform-policy \
               --set-user-color="$rgb_color" \
               --set-color-scheme="$mode" \
               --set-color-variant="$variant" >/dev/null 2>&1 & disown
      fi
    done
  fi
}

main "$@"
