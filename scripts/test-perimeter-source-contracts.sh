#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
common="$root/modules/common/perimeter"
widgets="$root/modules/common/widgets"
sidebar="$root/modules/sidebar/SidebarHost.qml"
dashboard="$root/modules/overview/OverviewDashboard.qml"
dock="$root/modules/dock/Dock.qml"
search="$root/modules/overview/SearchWidget.qml"
osk="$root/modules/onScreenKeyboard/OnScreenKeyboard.qml"
screen_corners="$root/modules/screenCorners/ScreenCorners.qml"
waffle="$root/modules/waffle/bar/BarPopup.qml"

fail() {
    printf 'FAIL: perimeter source retirement contract: %s\n' "$1" >&2
    exit 1
}

bash "$root/scripts/test-perimeter-contracts.sh" >/dev/null

# Whole-runtime-QML sweep: old round-wedge/corner implementations must be gone,
# not merely disconnected from the most visible callers.
unexpected="$(git -C "$root" grep -n -E \
    'ConnectedSurfaceJoinFlares|PerimeterCornerShadow|RoundCorner[[:space:]]*\{|RoundCorner\.CornerEnum|fakeScreenRounding|joinFlareRadius|joinFlareCrossScale' \
    -- '*.qml' || true)"
if [[ -n "$unexpected" ]]; then
    printf '%s\n' "$unexpected" >&2
    fail 'tracked runtime QML still references retired round-wedge/corner geometry'
fi

[[ ! -e "$common/ConnectedSurfaceJoinFlares.qml" ]] || fail 'ConnectedSurfaceJoinFlares.qml still exists'
[[ ! -e "$common/PerimeterCornerShadow.qml" ]] || fail 'PerimeterCornerShadow.qml still exists'
[[ ! -e "$widgets/RoundCorner.qml" ]] || fail 'RoundCorner.qml still exists'
! grep -Fq 'ConnectedSurfaceJoinFlares 1.0' "$common/qmldir" || fail 'JoinFlares export remains'
! grep -Fq 'PerimeterCornerShadow 1.0' "$common/qmldir" || fail 'PerimeterCornerShadow export remains'
! grep -Fq 'RoundCorner 1.0' "$widgets/qmldir" || fail 'RoundCorner export remains'
! grep -Fq '"fakeScreenRounding"' "$root/defaults/config.json" || fail 'fakeScreenRounding default remains'
! grep -Fq 'property int fakeScreenRounding' "$root/modules/common/Config.qml" || fail 'fakeScreenRounding schema remains'

for token in \
    'ConnectedSurfaceAbyssEdgeSurface {' \
    'id: sidebarAbyssSurface' \
    'readonly property real hiddenTranslateDistance:' \
    'PerimeterTokens.abyssFuseDepth' \
    '? -root.hiddenTranslateDistance' \
    ': root.hiddenTranslateDistance'; do
    grep -Fq -- "$token" "$sidebar" || fail "Sidebar Abyss/full-hide contract missing: $token"
done

for token in \
    'ConnectedSurfaceAbyssEdgeSurface {' \
    'id: dashboardAbyssSurface' \
    'ownerThickness: root.attachmentThickness'; do
    grep -Fq "$token" "$dashboard" || fail "Dashboard Abyss edge contract missing: $token"
done

for token in \
    'ConnectedSurfaceAbyssEdgeSurface {' \
    'id: dockAbyssSurface' \
    'ownerThickness: dockRoot.screenEdgeThickness' \
    'screenEdge?.physicalShadow?.enabled ?? true' \
    'Appearance.m3colors.m3shadow'; do
    grep -Fq "$token" "$dock" || fail "Dock Abyss edge contract missing: $token"
done

for file in "$search" "$osk" "$common/ConnectedSurfaceFrame.qml"; do
    ! grep -Fq 'ConnectedSurfaceJoinFlares' "$file" || fail "${file#$root/} restored JoinFlares"
    ! grep -Fq 'joinFlareRadius' "$file" || fail "${file#$root/} restored joinFlareRadius"
done

for token in RoundCorner fakeScreenRounding showFakeRounding roundingSize; do
    ! grep -Fq "$token" "$screen_corners" || fail "ScreenCorners restored visual corner geometry: $token"
done
grep -Fq 'GlobalStates.toggleSidebarLeft' "$screen_corners" || fail 'ScreenCorners lost sidebar interaction'
# Orbit is retired. Niri's compositor-owned overview hot corner must still
# take precedence over shell corner actions, without reviving Orbit routing.
for token in \
    'readonly property bool niriOverviewOwnsCorner: CompositorService.isNiri' \
    'NiriService.isOverviewHotCornerActive(outputName, cornerName)'; do
    grep -Fq "$token" "$screen_corners" \
        || fail "ScreenCorners lost compositor-owned overview priority: $token"
done
! grep -Fq 'GlobalStates.openOrbit(' "$screen_corners" \
    || fail 'ScreenCorners restored retired Orbit interaction'

grep -Fq 'ConnectedSurfaceFrame {' "$waffle" || fail 'Waffle lost shared non-Abyss frame'
grep -Fq 'connectorVisible: false' "$waffle" || fail 'Waffle connector painter must stay disabled'
! grep -Fq 'function updateAnchor()' "$waffle" || fail 'Waffle restored manual anchor compatibility API'
! grep -Fq '_anchorRevision' "$waffle" || fail 'Waffle restored manual anchor revision shim'

printf 'PASS: runtime QML is free of retired round-wedge geometry; current Abyss/direct-seam routes are authoritative\n'
