#!/usr/bin/env bash
# Launch the configured terminal emulator
# Reads from Alis config (including Flatpak / .desktop identities), falls back to kitty

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/config-path.sh
source "$SCRIPT_DIR/lib/config-path.sh"

CONFIG_FILE="$(alis_config_file)"
HELPER_PY="$SCRIPT_DIR/default_apps_helper.py"

if [[ -f "$HELPER_PY" ]] && command -v python3 &>/dev/null; then
    RESOLVED_JSON="$(python3 "$HELPER_PY" resolve-launch terminal "$CONFIG_FILE" -- "$@" 2>/dev/null || true)"
    if [[ -n "$RESOLVED_JSON" ]]; then
        mapfile -t RESOLVED_ARGV < <(python3 -c '
import json, sys
data = json.loads(sys.argv[1])
if data.get("ok") and data.get("argv"):
    for item in data["argv"]:
        print(item)
' "$RESOLVED_JSON" 2>/dev/null || true)
        if [[ ${#RESOLVED_ARGV[@]} -gt 0 ]]; then
            if [[ "${ALIS_LAUNCH_DRY_RUN:-0}" == "1" ]]; then
                printf '%s\n' "$RESOLVED_JSON"
                exit 0
            fi
            if command -v systemd-run &>/dev/null; then
                exec systemd-run --user --scope --quiet --collect --property="Description=Alis Terminal" -- "${RESOLVED_ARGV[@]}"
            else
                exec "${RESOLVED_ARGV[@]}"
            fi
        fi
    fi
fi

if [[ -f "$CONFIG_FILE" ]]; then
    TERMINAL=$(grep -o '"terminal"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" \
        | head -1 \
        | sed 's/.*"terminal"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi

TERMINAL="${TERMINAL:-kitty}"

if command -v "$TERMINAL" &>/dev/null; then
    if command -v systemd-run &>/dev/null; then
        exec systemd-run --user --scope --quiet --collect --property="Description=Alis Terminal" -- "$TERMINAL" "$@"
    else
        exec "$TERMINAL" "$@"
    fi
fi

# Fallback chain: project default first, then popular alternatives
for fallback in kitty foot ghostty alacritty wezterm konsole xterm; do
    if command -v "$fallback" &>/dev/null; then
        if command -v systemd-run &>/dev/null; then
            exec systemd-run --user --scope --quiet --collect --property="Description=Alis Terminal" -- "$fallback" "$@"
        else
            exec "$fallback" "$@"
        fi
    fi
done

echo "No terminal emulator found" >&2
exit 1
