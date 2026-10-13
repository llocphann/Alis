#!/usr/bin/env bash
# Niri-session-wide Fcitx5/Unikey initialization. Never alter an existing profile.
set -euo pipefail

command -v fcitx5 >/dev/null 2>&1 || exit 0
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fcitx5"
data_dir="${ALIS_FCITX5_DATA_DIR:-/usr/share/fcitx5/inputmethod}"
if [[ ! -f "$data_dir/unikey.conf" ]]; then
    printf 'Hadalis: install fcitx5-unikey to enable Telex\n' >&2
    exit 0
fi

# An existing non-Fcitx session is not ours to take over. Niri default installs
# export fcitx; user-owned profiles may explicitly select another framework.
manager_env=""
if command -v systemctl >/dev/null 2>&1; then
    manager_env="$(systemctl --user show-environment 2>/dev/null || true)"
fi
manager_qt_im="$(printf '%s\n' "$manager_env" | sed -n 's/^QT_IM_MODULE=//p' | head -n 1)"
if [[ -n "${QT_IM_MODULE:-}" ]]; then
    [[ "$QT_IM_MODULE" == "fcitx" ]] || exit 0
elif [[ -n "$manager_qt_im" && "$manager_qt_im" != "fcitx" ]]; then
    exit 0
fi

umask 077
mkdir -p "$config_dir/conf"
# Keyboard US is the inactive EN state; Unikey is the VI state.
# Fcitx/Unikey preferences are user-owned once they exist.
if [[ ! -e "$config_dir/profile" ]]; then
    cat > "$config_dir/profile" <<'PROFILE'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=keyboard-us

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=unikey
Layout=

[GroupOrder]
0=Default
PROFILE
fi

if [[ ! -e "$config_dir/conf/unikey.conf" ]]; then
    cat > "$config_dir/conf/unikey.conf" <<'UNIKEY'
[Config]
InputMethod=0
OutputCharset=0
UNIKEY
fi

# Bridge the compositor's input-method environment to systemd app launchers.
# Respect an existing value (e.g. ibus or a custom Qt input method).
if command -v systemctl >/dev/null 2>&1; then
    assignments=()
    for assignment in 'QT_IM_MODULE=fcitx' 'XMODIFIERS=@im=fcitx'; do
        key="${assignment%%=*}"
        if ! grep -q "^${key}=" <<< "$manager_env"; then
            if [[ -z "${!key+x}" || "${!key}" == "${assignment#*=}" ]]; then
                assignments+=("$assignment")
            fi
        fi
    done
    if (("${#assignments[@]}" > 0)); then
        systemctl --user set-environment "${assignments[@]}" >/dev/null 2>&1 || true
    fi
fi

# Do not restart an existing instance (that would discard an in-flight word).
if ! pgrep -u "$(id -u)" -x fcitx5 >/dev/null 2>&1; then
    fcitx5 -d
fi
