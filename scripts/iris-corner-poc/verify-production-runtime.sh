#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
runtime_root="${HADALIS_RUNTIME_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/alis}"

fail() {
    printf 'Production iRiS runtime preflight: FAIL: %s\n' "$1" >&2
    exit 1
}

python3 "$root/scripts/test-iris-production-surface-contract.py"
bash "$root/scripts/test-perimeter-source-contracts.sh"

[[ -d "$runtime_root" ]] \
    || fail "runtime root not found: $runtime_root (set HADALIS_RUNTIME_ROOT for a direct repo run)"

assets=(
    modules/bar/StyledPopup.qml
    modules/common/perimeter/ConnectedSurfaceIrisField.qml
    modules/common/perimeter/ConnectedSurfaceIrisFrame.qml
    modules/common/perimeter/ConnectedSurfaceIrisEdgeSurface.qml
    modules/common/perimeter/ConnectedSurfaceBodyMask.qml
    modules/common/perimeter/IrisField.frag
    modules/common/perimeter/IrisField.frag.qsb
    modules/common/perimeter/PerimeterTokens.qml
    modules/common/perimeter/qmldir

    # Extended production callers. These are deliberately checked here rather
    # than relying on shader parity alone: a stale installed Sidebar/Dashboard
    # file can reproduce old geometry even while the QSB itself is current.
    modules/dock/Dock.qml
    modules/sidebar/SidebarHost.qml
    modules/sidebarLeft/SidebarLeftContent.qml
    modules/sidebarRight/SidebarRightContent.qml
    modules/sidebarRight/CompactSidebarRightContent.qml
    modules/settings/SettingsOverlay.qml
    modules/settings/SettingsFocus.qml
    modules/overview/Overview.qml
    modules/overview/OverviewDashboard.qml
    modules/overview/SearchWidget.qml
    modules/overview/SearchBar.qml
)

for relative in "${assets[@]}"; do
    source_file="$root/$relative"
    runtime_file="$runtime_root/$relative"
    [[ -f "$source_file" ]] || fail "source asset missing: $relative"
    [[ -f "$runtime_file" ]] || fail "installed runtime asset missing: $relative"
    cmp -s "$source_file" "$runtime_file" \
        || fail "installed runtime asset is stale/different: $relative"
done

cmp -s \
    "$root/modules/common/perimeter/IrisField.frag.qsb" \
    "$root/scripts/iris-corner-poc/IrisField.frag.qsb" \
    || fail "production QSB differs from the locked G1/G2 QSB"

printf 'Production iRiS runtime preflight: PASS\n'
printf 'repo_head=%s\n' "$(git -C "$root" rev-parse HEAD 2>/dev/null || printf unknown)"
printf 'runtime_root=%s\n' "$runtime_root"
printf '%s\n' 'Next gate is visual/interaction acceptance in the real Niri session.'
