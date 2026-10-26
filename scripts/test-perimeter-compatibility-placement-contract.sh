#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
screen_edges="$root/modules/screenCorners/ScreenEdges.qml"
screen_edge_fallback="$root/modules/screenCorners/ScreenEdgeLegacyFallback.qml"
sidebar="$root/modules/sidebar/SidebarHost.qml"
settings="$root/modules/settings/ShellLayoutConfig.qml"

fail() {
    printf 'FAIL: connected placement compatibility contract: %s\n' "$1" >&2
    exit 1
}

for file in "$screen_edges" "$screen_edge_fallback" "$sidebar" "$settings"; do
    [[ -f "$file" ]] || fail "missing ${file#$root/}"
done

grep -Fq 'Config.options?.appearance?.screenEdge?.width ?? 10' "$screen_edges" \
    || fail 'persistent Screen Edge width/default contract is missing'
grep -Fq 'component FrameWindow: PanelWindow {' "$screen_edges" \
    || fail 'canonical Screen Edge FrameWindow is missing'
grep -Fq 'ScreenEdgeField {' "$screen_edges" \
    || fail 'canonical analytic Screen Edge field is missing'
grep -Fq 'Qt.resolvedUrl("ScreenEdgeLegacyFallback.qml")' "$screen_edges" \
    || fail 'canonical Screen Edge error fallback loader is missing'
! grep -Fq 'import QtQuick.Shapes' "$screen_edges" \
    || fail 'healthy Screen Edge path must not import legacy Shapes'
! grep -Fq 'import QtQuick.Effects' "$screen_edges" \
    || fail 'healthy Screen Edge path must not import legacy Effects'
grep -Fq 'fillRule: ShapePath.OddEvenFill' "$screen_edge_fallback" \
    || fail 'canonical Screen Edge odd-even fallback geometry is missing'
for edge in top bottom left right; do
    grep -Fq "ReservationWindow { edge: \"$edge\" }" "$screen_edges" \
        || fail "persistent Screen Edge missing $edge reservation"
done

for token in \
    'required property string edge' \
    'GlobalStates.sidebarLeftPresentationOutput' \
    'GlobalStates.sidebarRightPresentationOutput' \
    'ConnectedSurfaceAbyssEdgeSurface {' \
    'ownerThickness: root.screenEdgeHoverWidth' \
    'readonly property real hiddenTranslateDistance:' \
    '- root.screenEdgeHoverWidth)'; do
    grep -Fq -- "$token" "$sidebar" || fail "Sidebar direct-edge/Abyss contract missing: $token"
done
for retired in 'sidebarBridgeGeometry' 'ConnectedSurfaceConnector {' 'ConnectedSurfaceJoinFlares' 'directEdgeInset'; do
    ! grep -Fq "$retired" "$sidebar" || fail "Sidebar restored retired edge geometry: $retired"
done

grep -Fq 'visible: surfaceSection.sidebarRole' "$settings" \
    || fail 'Shell Layout must retain supported sidebar sizing controls'
grep -Fq 'text: Translation.tr("Width")' "$settings" \
    || fail 'Shell Layout must retain sidebar width setting'

printf 'PASS: locked Screen Edge and Abyss left/right Sidebar placement remain supported\n'
