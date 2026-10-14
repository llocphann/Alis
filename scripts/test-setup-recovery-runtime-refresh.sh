#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_root/sdata/subcmd-install/3.files.sh"
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT

fail() {
    printf 'setup recovery runtime refresh failed: %s\n' "$1" >&2
    exit 1
}

# Execute the real Quickshell install-stage prefix inside an isolated XDG tree.
# The source file is not functionized, so close its active case arm immediately
# after the Quickshell stage's terminal success marker. This keeps copy/manifest/
# cleanup behavior real while avoiding unrelated Niri/theme/system integration.
marker_re='^[[:space:]]*log_success "Quickshell alis config installed"[[:space:]]*$'
marker_count="$(grep -Ec "$marker_re" "$installer" || true)"
[[ "$marker_count" -eq 1 ]] \
    || fail "Quickshell install-stage boundary count is $marker_count"
install_prefix="$stage/install-quickshell-prefix.sh"
awk -v re="$marker_re" '
    { print }
    $0 ~ re {
        print "    ;;"
        print "esac"
        print "return 0"
        exit
    }
' "$installer" > "$install_prefix"
bash -n "$install_prefix" || fail 'isolated Quickshell install-stage prefix is not valid Bash'

export HOME="$stage/home"
export XDG_BIN_HOME="$stage/bin"
export XDG_CACHE_HOME="$stage/cache"
export XDG_CONFIG_HOME="$stage/config"
export XDG_DATA_HOME="$stage/data"
export XDG_STATE_HOME="$stage/state"
export REPO_ROOT="$repo_root"
mkdir -p "$HOME" "$XDG_BIN_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"

# This contract exercises runtime refresh/orphan cleanup, not Rust compilation.
# Keep it hermetic on validator hosts where rustup has no configured default.
export CARGO_TARGET_DIR="$stage/native-target"
cat > "$XDG_BIN_HOME/cargo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
release="${CARGO_TARGET_DIR:?}/release"
mkdir -p "$release"
for binary in alis-inputd alis-mpdd alis-native alis-theme; do
    printf '#!/usr/bin/env sh\nexit 0\n' > "$release/$binary"
    chmod +x "$release/$binary"
done
EOF
chmod +x "$XDG_BIN_HOME/cargo"
export PATH="$XDG_BIN_HOME:$PATH"

# Installer functions write to this bookkeeping file while copying the real
# canonical payload. Keep all other installer state inside the fixture root.
export INSTALLED_LISTFILE="$stage/installed-files"
export BACKUP_DIR="$stage/backup"
export FIRSTRUN_FILE="$stage/firstrun.done"
touch "$FIRSTRUN_FILE"

# shellcheck source=/dev/null
source "$repo_root/sdata/lib/functions.sh"
# shellcheck source=/dev/null
source "$repo_root/sdata/lib/robust-update.sh"

# Non-interactive recovery install: critically, this is NOT an update.
ask=false
quiet=true
INSTALL_FIRSTRUN=false
SKIP_BACKUP=true
SKIP_QUICKSHELL=false
SKIP_VERIFICATION=true
IS_UPDATE=false

# Styling/TUI hooks used by the sourced install stage. Keep output quiet and
# prevent integration probes from touching the real user systemd manager.
STY_CYAN=''; STY_RST=''; STY_FAINT=''; STY_GREEN=''; STY_BLUE=''; STY_YELLOW=''; STY_RED=''; STY_PURPLE=''; STY_BOLD=''; STY_SLANT=''
tui_info() { :; }
tui_warn() { :; }
tui_confirm() { return 1; }
systemctl() { return 1; }
sync_user_alis_service_from_repo_if_present() { return 1; }

# Recovery install must not accidentally take the update-only backup branch.
create_update_backup() {
    fail 'IS_UPDATE=false recovery install unexpectedly created an update backup'
}

runtime="$XDG_CONFIG_HOME/quickshell/alis"
mkdir -p "$runtime/scripts"
printf '%s\n' 'import QtQuick' > "$runtime/RetiredRoot.qml"
printf '%s\n' '# private excluded artifact' > "$runtime/scripts/test-local-private.sh"

run_recovery_stage() {
    # shellcheck source=/dev/null
    source "$install_prefix"
}

(
    cd "$repo_root"
    run_recovery_stage
) || fail 'recovery install-stage execution failed'

[[ ! -e "$runtime/RetiredRoot.qml" && ! -L "$runtime/RetiredRoot.qml" ]] \
    || fail 'IS_UPDATE=false recovery install preserved retired managed root QML'
[[ -f "$runtime/scripts/test-local-private.sh" ]] \
    || fail 'IS_UPDATE=false recovery install deleted excluded private runtime artifact'
[[ -f "$runtime/shell.qml" ]] \
    || fail 'recovery install did not copy the canonical runtime root'
[[ -f "$runtime/.alis-manifest" ]] \
    || fail 'recovery install did not finalize the canonical runtime manifest'
if grep -Fq 'RetiredRoot.qml' "$runtime/.alis-manifest"; then
    fail 'retired root fixture leaked into canonical runtime manifest'
fi
if grep -Fq 'scripts/test-local-private.sh' "$runtime/.alis-manifest"; then
    fail 'excluded private fixture leaked into canonical runtime manifest'
fi

printf '%s\n' '1..1'
printf '%s\n' 'ok 1 - recovery install refresh removes managed runtime orphans without deleting excluded private artifacts'
