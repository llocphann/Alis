MIGRATION_ID="016-launcher-structure-compat"
MIGRATION_TITLE="Launcher compatibility for the current Alis structure"
MIGRATION_DESCRIPTION="Updates old Niri launcher bindings from qs/ii-era commands and hardcoded runtime script paths to the current alis launcher structure."
MIGRATION_TARGET_FILE="~/.config/niri/config.kdl"
MIGRATION_REQUIRED=true

migration_check() {
  local config="${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl"
  [[ -f "$config" ]] || return 1
  grep -Eq 'spawn-at-startup "qs" "-c" "(ii|alis)"|spawn-at-startup "alis" "start"|spawn "qs" "-c" "(ii|alis)"( "ipc" "call")?|spawn "alis"( "ipc" "call")? |\.config/quickshell/(ii|alis)/scripts/(launch-terminal|close-window)\.sh|\$\(alis path\)/scripts/(launch-terminal|close-window)\.sh' "$config"
}

migration_preview() {
  local launcher_path="${XDG_BIN_HOME:-$HOME/.local/bin}/alis"
  echo -e "${STY_RED}- spawn-at-startup \"alis\" \"start\"${STY_RST}"
  echo -e "${STY_GREEN}+ spawn-at-startup \"${launcher_path}\" \"start\"${STY_RST}"
  echo ""
  echo -e "${STY_RED}- spawn \"alis\" \"overview\" \"toggle\";${STY_RST}"
  echo -e "${STY_GREEN}+ spawn \"${launcher_path}\" \"overview\" \"toggle\";${STY_RST}"
  echo ""
  echo -e "${STY_RED}- spawn \"bash\" \"-c\" \"\$HOME/.config/quickshell/ii/scripts/launch-terminal.sh\";${STY_RST}"
  echo -e "${STY_GREEN}+ spawn \"${launcher_path}\" \"terminal\";${STY_RST}"
}

migration_diff() {
  local config="${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl"
  grep -E 'spawn-at-startup|spawn "qs"|spawn "alis"|spawn ".*/alis"|launch-terminal\.sh|close-window\.sh' "$config" 2>/dev/null | head -20
}

migration_apply() {
  local config="${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl"
  local launcher_path="${XDG_BIN_HOME:-$HOME/.local/bin}/alis"

  if ! migration_check; then
    return 0
  fi

  export ALIS_MIGRATION_LAUNCHER_PATH="${launcher_path}"
  python3 << 'MIGRATE'
import os
import re

config_path = os.path.expanduser(os.environ.get("XDG_CONFIG_HOME", "~/.config")) + "/niri/config.kdl"
launcher_path = os.environ.get("ALIS_MIGRATION_LAUNCHER_PATH", os.path.expanduser("~/.local/bin/alis"))
with open(config_path, "r", encoding="utf-8") as f:
    content = f.read()

content = re.sub(
    r'spawn-at-startup\s+"qs"\s+"-c"\s+"(?:ii|alis)"',
    f'spawn-at-startup "{launcher_path}" "start"',
    content,
)

content = re.sub(
    r'spawn-at-startup\s+"(?:[^"]*/)?alis"\s+"start"',
    f'spawn-at-startup "{launcher_path}" "start"',
    content,
)

content = re.sub(
    r'spawn\s+"qs"\s+"-c"\s+"(?:ii|alis)"\s+"settings"\s*;',
    f'spawn "{launcher_path}" "settings";',
    content,
)

content = re.sub(
    r'spawn\s+"(?:[^"]*/)?alis"\s+"settings"\s*;',
    f'spawn "{launcher_path}" "settings";',
    content,
)

def replace_ipc(match):
    target = match.group(1)
    func = match.group(2)
    if target == "settings" and func == "open":
        return f'spawn "{launcher_path}" "settings";'
    return f'spawn "{launcher_path}" "{target}" "{func}";'

content = re.sub(
    r'spawn\s+"(?:qs"\s+"-c"\s+"(?:ii|alis)"\s+"ipc"\s+"call|(?:[^"]*/)?alis"\s+"ipc"\s+"call)"\s+"([^"]+)"\s+"([^"]+)"\s*;',
    replace_ipc,
    content,
)

content = re.sub(
    r'spawn\s+"(?:[^"]*/)?alis"\s+"([^"]+)"\s+"([^"]+)"\s*;',
    lambda match: f'spawn "{launcher_path}" "{match.group(1)}" "{match.group(2)}";',
    content,
)

content = re.sub(
    r'spawn\s+"alis"\s+"([^"]+)"\s*;',
    lambda match: f'spawn "{launcher_path}" "{match.group(1)}";',
    content,
)

content = re.sub(
    r'spawn\s+"bash"\s+"-(?:l)?c"\s+"(?:\$HOME/\.config/quickshell/(?:ii|alis)/scripts/launch-terminal\.sh|exec\s+\\"?\$\(alis path\)/scripts/launch-terminal\.sh\\"?)"\s*;',
    f'spawn "{launcher_path}" "terminal";',
    content,
)

content = re.sub(
    r'spawn\s+"bash"\s+"-(?:l)?c"\s+"(?:\$HOME/\.config/quickshell/(?:ii|alis)/scripts/close-window\.sh|exec\s+\\"?\$\(alis path\)/scripts/close-window\.sh\\"?)"\s*;',
    f'spawn "{launcher_path}" "close-window";',
    content,
)

with open(config_path, "w", encoding="utf-8") as f:
    f.write(content)
MIGRATE
}
