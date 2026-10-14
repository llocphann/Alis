#!/usr/bin/env bash
set -euo pipefail

# restart-shell.sh — called by QML "Reload shell" buttons.
#
# Delegates to `alis restart` which correctly kills the wrapper process
# before killing the qs child, avoiding the race where the wrapper loop
# respawns qs before this script can detect the gap.

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_dir="$(cd -- "$script_dir/.." && pwd)"
launcher_script="$config_dir/scripts/alis"

if [[ ! -f "$launcher_script" ]]; then
    launcher_script="$script_dir/alis"
fi

if [[ ! -f "$launcher_script" ]]; then
    echo "restart-shell: cannot find alis launcher" >&2
    exit 1
fi

exec /usr/bin/env bash "$launcher_script" restart -c "$config_dir"
