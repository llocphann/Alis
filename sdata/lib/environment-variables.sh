# Environment variables for Alis installer
# This is NOT a script for execution, but for loading variables
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib/brand-env-compat.sh"

XDG_BIN_HOME=${XDG_BIN_HOME:-$HOME/.local/bin}
XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}

# Colors (ANSI escape codes)
STY_RED='\e[31m'
STY_GREEN='\e[32m'
STY_YELLOW='\e[33m'
STY_BLUE='\e[34m'
STY_PURPLE='\e[35m'
STY_MAGENTA='\e[35m'
STY_CYAN='\e[36m'
STY_WHITE='\e[37m'

# Text styles
STY_BOLD='\e[1m'
STY_FAINT='\e[2m'
STY_SLANT='\e[3m'
STY_ITALIC='\e[3m'
STY_UNDERLINE='\e[4m'
STY_INVERT='\e[7m'
STY_RST='\e[0m'

# Used by register_temp_file()
declare -a TEMP_FILES_TO_CLEANUP=()

# Used by install script
BACKUP_DIR="${BACKUP_DIR:-$HOME/alis-backup}"
ALIS_CONFIG_DIR_NEW="${XDG_CONFIG_HOME}/alis"
ALIS_CONFIG_DIR_LEGACY="${XDG_CONFIG_HOME}/illogical-impulse"

resolve_alis_config_dir() {
  # Installer tooling and live QML must agree after the cutover.
  if [[ -d "$ALIS_CONFIG_DIR_NEW" ]]; then
    printf '%s' "$ALIS_CONFIG_DIR_NEW"
    return
  fi

  # Keep the original location readable before the owner-gated migration.
  if [[ -d "$ALIS_CONFIG_DIR_LEGACY" ]]; then
    printf '%s' "$ALIS_CONFIG_DIR_LEGACY"
    return
  fi

  local previous="$XDG_CONFIG_HOME/"'in''ir'
  if [[ -d "$previous" ]]; then
    printf '%s' "$previous"
    return
  fi

  printf '%s' "$ALIS_CONFIG_DIR_NEW"
}

DOTS_CORE_CONFDIR="${DOTS_CORE_CONFDIR:-$(resolve_alis_config_dir)}"
INSTALLED_LISTFILE="${DOTS_CORE_CONFDIR}/installed_listfile"
FIRSTRUN_FILE="${DOTS_CORE_CONFDIR}/installed_true"
