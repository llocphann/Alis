#!/usr/bin/env bash
# Launch the configured terminal emulator
# Reads from Alis config (including Flatpak / .desktop identities), falls back to kitty

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/config-path.sh
source "$SCRIPT_DIR/lib/config-path.sh"

CONFIG_FILE="$(alis_config_file)"
HELPER_PY="$SCRIPT_DIR/default_apps_helper.py"

TARGET_CWD=""
if [[ "${1:-}" == "--cwd" && -n "${2:-}" ]]; then
    TARGET_CWD="$2"
    shift 2
fi

if [[ -n "$TARGET_CWD" && -d "$TARGET_CWD" ]]; then
    cd "$TARGET_CWD" || true
    # Opening terminal at an explicit folder always spawns a fresh window (never focus an existing unrelated one).
    if [[ -f "$HELPER_PY" ]] && command -v python3 &>/dev/null; then
        RESOLVED_JSON="$(python3 "$HELPER_PY" resolve-launch terminal "$CONFIG_FILE" -- "$@" 2>/dev/null || true)"
        if [[ -n "$RESOLVED_JSON" ]]; then
            if [[ "${ALIS_LAUNCH_DRY_RUN:-0}" == "1" ]]; then
                printf '%s\n' "$RESOLVED_JSON"
                exit 0
            fi
            mapfile -t RESOLVED_ARGV < <(python3 -c '
import json, sys
data = json.loads(sys.argv[1])
if data.get("ok") and data.get("argv"):
    for item in data["argv"]:
        print(item)
' "$RESOLVED_JSON" 2>/dev/null || true)
            if [[ ${#RESOLVED_ARGV[@]} -gt 0 ]]; then
                if command -v systemd-run &>/dev/null; then
                    exec systemd-run --user --scope --quiet --collect --working-directory="$TARGET_CWD" --property="Description=Alis Terminal" -- "${RESOLVED_ARGV[@]}"
                else
                    exec "${RESOLVED_ARGV[@]}"
                fi
            fi
        fi
    fi
fi

if [[ -f "$HELPER_PY" ]] && command -v python3 &>/dev/null; then
    RESOLVED_JSON="$(python3 "$HELPER_PY" focus-or-launch terminal "$CONFIG_FILE" -- "$@" 2>/dev/null || true)"
    if [[ -n "$RESOLVED_JSON" ]]; then
        if [[ "${ALIS_LAUNCH_DRY_RUN:-0}" == "1" ]]; then
            printf '%s\n' "$RESOLVED_JSON"
            exit 0
        fi
        ACTION="$(python3 -c 'import json, sys; print(json.loads(sys.argv[1]).get("action", ""))' "$RESOLVED_JSON" 2>/dev/null || true)"
        if [[ "$ACTION" == "focused" ]]; then
            exit 0
        fi
        mapfile -t RESOLVED_ARGV < <(python3 -c '
import json, sys
data = json.loads(sys.argv[1])
if data.get("ok") and data.get("argv"):
    for item in data["argv"]:
        print(item)
' "$RESOLVED_JSON" 2>/dev/null || true)
        if [[ ${#RESOLVED_ARGV[@]} -gt 0 ]]; then
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

_systemd_cwd_args=()
if [[ -n "$TARGET_CWD" && -d "$TARGET_CWD" ]]; then
    _systemd_cwd_args=(--working-directory="$TARGET_CWD")
fi

if command -v "$TERMINAL" &>/dev/null; then
    if command -v systemd-run &>/dev/null; then
        exec systemd-run --user --scope --quiet --collect "${_systemd_cwd_args[@]}" --property="Description=Alis Terminal" -- "$TERMINAL" "$@"
    else
        exec "$TERMINAL" "$@"
    fi
fi

# Fallback chain: project default first, then popular alternatives
for fallback in kitty foot ghostty alacritty wezterm konsole xterm; do
    if command -v "$fallback" &>/dev/null; then
        if command -v systemd-run &>/dev/null; then
            exec systemd-run --user --scope --quiet --collect "${_systemd_cwd_args[@]}" --property="Description=Alis Terminal" -- "$fallback" "$@"
        else
            exec "$fallback" "$@"
        fi
    fi
done

echo "No terminal emulator found" >&2
exit 1
