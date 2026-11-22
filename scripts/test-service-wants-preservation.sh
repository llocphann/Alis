#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/alis-service-wants-test.XXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

export HOME="$TMP_DIR/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
mkdir -p "$HOME/.local/bin" "$XDG_CONFIG_HOME/systemd/user" "$TMP_DIR/bin" "$TMP_DIR/repo/scripts/lib" "$TMP_DIR/repo/assets/systemd" "$TMP_DIR/units"

cp "$ROOT/scripts/alis" "$TMP_DIR/repo/scripts/alis"
chmod +x "$TMP_DIR/repo/scripts/alis"
cp "$ROOT/scripts/lib/"*.sh "$TMP_DIR/repo/scripts/lib/"
cp "$ROOT/assets/systemd/alis.service" "$TMP_DIR/repo/assets/systemd/alis.service"
printf '%s\n' '#!/usr/bin/env bash' > "$TMP_DIR/repo/setup"
chmod +x "$TMP_DIR/repo/setup"
printf '%s\n' 'import Quickshell' > "$TMP_DIR/repo/shell.qml"

cat > "$TMP_DIR/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--user" ]]; then
    shift
fi
case "${1:-}" in
    cat)
        exit 1
        ;;
    is-active|is-enabled)
        exit 1
        ;;
    show)
        printf 'KillMode=process\n'
        exit 0
        ;;
    daemon-reload)
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "$TMP_DIR/bin/systemctl"

export PATH="$TMP_DIR/bin:/usr/bin:/bin"
SYSTEMD_USER="$XDG_CONFIG_HOME/systemd/user"

# Case 1: Empty unit detection must NOT wipe compositor-specific wants links,
# while still removing legacy graphical-session.target.wants/alis.service.
mkdir -p "$SYSTEMD_USER/niri.service.wants" \
    "$SYSTEMD_USER/wayland-wm@Hyprland.service.wants" \
    "$SYSTEMD_USER/graphical-session.target.wants"
ln -sf "$SYSTEMD_USER/alis.service" "$SYSTEMD_USER/niri.service.wants/alis.service"
ln -sf "$SYSTEMD_USER/alis.service" "$SYSTEMD_USER/wayland-wm@Hyprland.service.wants/alis.service"
ln -sf "$SYSTEMD_USER/alis.service" "$SYSTEMD_USER/graphical-session.target.wants/alis.service"

ALIS_SYSTEMD_SYSTEM_UNIT_DIRS="" bash "$TMP_DIR/repo/scripts/alis" service install >/dev/null

[[ -L "$SYSTEMD_USER/niri.service.wants/alis.service" ]] || fail "Case 1 deleted niri.service.wants/alis.service on empty compositor detection"
[[ -L "$SYSTEMD_USER/wayland-wm@Hyprland.service.wants/alis.service" ]] || fail "Case 1 deleted Hyprland wants link on empty compositor detection"
[[ ! -e "$SYSTEMD_USER/graphical-session.target.wants/alis.service" && ! -L "$SYSTEMD_USER/graphical-session.target.wants/alis.service" ]] || fail "Case 1 left stale graphical-session.target.wants/alis.service"

# Case 2: Static unit fallback detects niri.service even if 'systemctl --user cat' fails,
# keeping niri.service.wants/alis.service and pruning non-active compositor/legacy links.
printf '[Unit]\nDescription=Fake Niri\n' > "$TMP_DIR/units/niri.service"
ln -sf "$SYSTEMD_USER/alis.service" "$SYSTEMD_USER/graphical-session.target.wants/alis.service"

ALIS_SYSTEMD_SYSTEM_UNIT_DIRS="$TMP_DIR/units" bash "$TMP_DIR/repo/scripts/alis" service install >/dev/null

[[ -L "$SYSTEMD_USER/niri.service.wants/alis.service" ]] || fail "Case 2 lost niri.service.wants/alis.service with static unit fallback"
[[ ! -e "$SYSTEMD_USER/wayland-wm@Hyprland.service.wants/alis.service" && ! -L "$SYSTEMD_USER/wayland-wm@Hyprland.service.wants/alis.service" ]] || fail "Case 2 kept mismatched Hyprland wants link"
[[ ! -e "$SYSTEMD_USER/graphical-session.target.wants/alis.service" && ! -L "$SYSTEMD_USER/graphical-session.target.wants/alis.service" ]] || fail "Case 2 left stale graphical-session.target.wants/alis.service"

# Case 3: 'alis service enable' succeeds via static unit fallback when D-Bus cat fails.
rm -f "$SYSTEMD_USER/niri.service.wants/alis.service"
ALIS_SYSTEMD_SYSTEM_UNIT_DIRS="$TMP_DIR/units" bash "$TMP_DIR/repo/scripts/alis" service enable >/dev/null

[[ -L "$SYSTEMD_USER/niri.service.wants/alis.service" ]] || fail "Case 3 did not create niri.service.wants/alis.service"
[[ "$(readlink "$SYSTEMD_USER/niri.service.wants/alis.service")" == "$SYSTEMD_USER/alis.service" ]] || fail "Case 3 symlink points to unexpected target"

printf 'PASS: service wants preservation and static compositor fallback verified\n'
