#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
common="$root/modules/common/perimeter"
styled="$root/modules/bar/StyledPopup.qml"
sidebar="$root/modules/sidebar/SidebarHost.qml"
screen_edge="$root/modules/screenCorners/ScreenEdges.qml"
overview="$root/modules/overview/Overview.qml"
dashboard="$root/modules/overview/OverviewDashboard.qml"
dock="$root/modules/dock/Dock.qml"

fail() {
    printf 'FAIL: perimeter shared contract: %s\n' "$1" >&2
    exit 1
}

for file in \
    PerimeterTokens.qml \
    ConnectedSurfaceGeometry.qml \
    ConnectedSurfaceConnector.qml \
    ConnectedSurfaceFrame.qml \
    ConnectedSurfaceRevealClip.qml \
    ConnectedSurfaceContentHost.qml \
    ConnectedSurfaceMask.qml \
    ConnectedSurfaceAbyssField.qml \
    ConnectedSurfaceAbyssFrame.qml \
    ConnectedSurfaceBodyMask.qml \
    ConnectedSurfaceAbyssEdgeSurface.qml \
    AbyssField.frag \
    AbyssField.frag.qsb; do
    [[ -f "$common/$file" ]] || fail "missing shared primitive $file"
done

for retired in \
    "$common/ConnectedSurfaceJoinFlares.qml" \
    "$common/PerimeterCornerShadow.qml" \
    "$root/modules/common/widgets/RoundCorner.qml"; do
    [[ ! -e "$retired" ]] || fail "retired round-wedge primitive still exists: ${retired#$root/}"
done
for token in 'ConnectedSurfaceJoinFlares 1.0' 'PerimeterCornerShadow 1.0'; do
    ! grep -Fq "$token" "$common/qmldir" || fail "retired perimeter export remains: $token"
done
! grep -Fq 'RoundCorner 1.0' "$root/modules/common/widgets/qmldir" \
    || fail 'retired RoundCorner export remains'

for primitive in ConnectedSurfaceGeometry ConnectedSurfaceAbyssFrame ConnectedSurfaceRevealClip ConnectedSurfaceContentHost ConnectedSurfaceBodyMask; do
    grep -Fq "$primitive" "$styled" \
        || fail "StyledPopup must keep using $primitive"
done

grep -Fq 'mask: connectedMask' "$styled" \
    || fail 'StyledPopup must keep the shaped connected input mask'
grep -Fq 'progress: root.revealProgress' "$styled" \
    || fail 'StyledPopup must keep driving shared reveal geometry'
grep -Fq 'ConnectedSurfaceRevealClip {' "$styled" \
    || fail 'StyledPopup must clip translated pixels at the resting Bar/Screen Edge seam'
for token in \
    'readonly property real _barSurfaceThickness:' \
    'Appearance.sizes.verticalBarWidth' \
    'Appearance.sizes.barHeight' \
    'const tangentY = root.centerOnOutput' \
    'return Qt.rect(barX, tangentY, thickness, sceneHeight)' \
    'const tangentX = root.centerOnOutput' \
    'return Qt.rect(tangentX, barY, sceneWidth, thickness)' \
    'readonly property real _popupScreenMargin: root._screenEdgeThickness' \
    'screenEdge?.physicalShadow?.enabled ?? true' \
    'Qt.alpha(Appearance.m3colors.m3shadow, root._edgeShadowOpacity)'; do
    grep -Fq "$token" "$styled" \
        || fail "StyledPopup must keep control-centered tangent placement while attaching to the physical Bar edge: $token"
done
grep -Fq 'readonly property rect sdfBodyRect:' "$common/ConnectedSurfaceAbyssFrame.qml" \
    || fail 'Abyss tangent joins must weld only the SDF body record'
grep -Fq 'x: root.sdfBodyRect.x' "$common/ConnectedSurfaceAbyssFrame.qml" \
    || fail 'Abyss popup shape must consume the tangent-welded SDF rect'
grep -Fq 'property real connectorWidth: PerimeterTokens.connectorWidth' "$common/ConnectedSurfaceGeometry.qml" \
    || fail 'connected geometry must source neck width from PerimeterTokens'
grep -Fq 'readonly property real connectorWidth: 40' "$common/PerimeterTokens.qml" \
    || fail 'shared connector width token changed unexpectedly'
for token in \
    'width: Math.max(0, root.effectiveSidebarWidth' \
    '- Appearance.sizes.elevationMargin' \
    '- root.screenEdgeHoverWidth)' \
    '? root.screenEdgeHoverWidth' \
    ': Appearance.sizes.elevationMargin' \
    'ConnectedSurfaceAbyssEdgeSurface {' \
    'ownerThickness: root.screenEdgeHoverWidth' \
    'exclusionMode: ExclusionMode.Ignore' \
    'sidebarContentLoader.x + sidebarContentLoader.animTranslateX' \
    'progress: root.presentationOpen || sidebarContentLoader.animating ? 1 : 0' \
    'readonly property real hiddenTranslateDistance:' \
    'Math.ceil(root.effectiveSidebarWidth) + Math.max(' \
    'PerimeterTokens.abyssFuseDepth' \
    '? -root.hiddenTranslateDistance' \
    ': root.hiddenTranslateDistance'; do
    grep -Fq -- "$token" "$sidebar" \
        || fail "SidebarHost must use owner-clipped Abyss Screen Edge composition: $token"
done
if grep -Fq 'id: sidebarBridgeGeometry' "$sidebar" \
        || grep -Fq 'ConnectedSurfaceConnector {' "$sidebar" \
        || grep -Fq 'ConnectedSurfaceJoinFlares {' "$sidebar"; then
    fail 'SidebarHost must not retain connector/flare patch geometry'
fi

for token in \
    'import qs.modules.common.perimeter' \
    'readonly property bool bottomBarOwnsEdge:' \
    'Config.options?.bar?.screenList' \
    'readonly property real bottomAttachmentThickness:' \
    'readonly property real bottomAttachmentY:' \
    '- root.bottomAttachmentThickness' \
    'readonly property bool dashboardPresentationMode:' \
    'root.bottomAttachmentY - bodyBottomInColumn' \
    'popupPresented: root._presentedOpen'; do
    grep -Fq -- "$token" "$overview" \
        || fail "Overview dashboard must stay directly attached and popup-like: $token"
done
if grep -Fq 'ConnectedSurfaceConnector {' "$overview" \
        || grep -Fq 'overviewBottomConnectorGeometry' "$overview"; then
    fail 'Overview must not restore connector/stem geometry'
fi
for token in \
    'import qs.modules.common.perimeter' \
    'property bool directBottomAttachment: false' \
    'property bool popupPresented: true' \
    'property real revealProgress: 0' \
    'property real attachmentThickness:' \
    'id: dashboardSurfaceLayer' \
    '(1 - root.revealProgress) * dashContainer.height' \
    'clip: root.directBottomAttachment' \
    'ConnectedSurfaceAbyssEdgeSurface {' \
    'edge: "bottom"' \
    'ownerThickness: root.attachmentThickness' \
    'root.height + root.attachmentThickness' \
    'fillColor: Appearance.colors.colLayer0' \
    'readonly property rect connectedSurfaceRect:'; do
    grep -Fq "$token" "$dashboard" \
        || fail "OverviewDashboard must use the Abyss bottom-owner composition: $token"
done
if grep -Fq 'ConnectedSurfaceJoinFlares {' "$dashboard" \
        || grep -Fq 'joinFlareRadius' "$dashboard"; then
    fail 'OverviewDashboard must not retain the legacy flare renderer/tokens'
fi

for token in \
    'import qs.modules.common.perimeter' \
    'ConnectedSurfaceAbyssEdgeSurface {' \
    'id: dockAbyssSurface' \
    'edge: root.position' \
    'ownerThickness: dockRoot.screenEdgeThickness' \
    'dockMouseArea.x + dockBackground.x + dockConnectedBody.x' \
    'screenEdge?.physicalShadow?.enabled ?? true' \
    'screenEdge?.physicalShadow?.size ?? 15' \
    'screenEdge?.physicalShadow?.opacity ?? 0.70' \
    'Qt.alpha(Appearance.m3colors.m3shadow, dockRoot.screenEdgeShadowOpacity)'; do
    grep -Fq "$token" "$dock" \
        || fail "Dock must use the shared Abyss/Screen Edge shadow contract: $token"
done
if grep -Fq 'StyledRectangularShadow {' "$dock"; then
    fail 'Dock must not retain a detached local shadow beside the shared Abyss field'
fi

for shared_shadow_surface in "$sidebar" "$dashboard" "$dock"; do
    grep -Fq 'screenEdge?.physicalShadow?.enabled ?? true' "$shared_shadow_surface" \
        || fail "${shared_shadow_surface#$root/} lost shared Screen Edge shadow ownership"
    grep -Fq 'Appearance.m3colors.m3shadow' "$shared_shadow_surface" \
        || fail "${shared_shadow_surface#$root/} lost Material Screen Edge shadow ink"
done
for file in "$root/modules/overview/SearchWidget.qml" "$root/modules/onScreenKeyboard/OnScreenKeyboard.qml" "$common/ConnectedSurfaceFrame.qml"; do
    if grep -Fq 'ConnectedSurfaceJoinFlares' "$file" || grep -Fq 'joinFlareRadius' "$file"; then
        fail "${file#$root/} retained legacy round-wedge geometry"
    fi
done

for token in \
    'import qs.modules.waffle.looks as WaffleLooks' \
    'readonly property bool waffleBarPanelEnabled:' \
    '(Config.options?.enabledPanels ?? []).includes("wBar")' \
    'readonly property string waffleBarEdge:' \
    'Config.options?.waffles?.bar?.screenList' \
    '? WaffleLooks.Looks.colors.bg0' \
    'function barOwnsEdge(outputName, edge)' \
    'GlobalStates.widgetEditMode' \
    'Config.options?.bar?.screenList' \
    'function iiBarOwnsEdge(outputName, edge)' \
    'root.iiBarOwnsEdge(outputName, "left")' \
    'root.iiBarOwnsEdge(outputName, "right")' \
    'root.iiBarOwnsEdge(outputName, "top")' \
    'root.iiBarOwnsEdge(outputName, "bottom")' \
    '&& !root.barOwnsEdge(outputName, edge)'; do
    grep -Fq "$token" "$screen_edge" \
        || fail "Screen Edge must suppress the Bar-owned edge/corners and share the Material Bar surface token: $token"
done

if grep -Fq 'qs.modules.perimeter' "$styled" || grep -Fq 'qs.modules.perimeter' "$sidebar"; then
    fail 'active connected surfaces must not import the retired broad perimeter module'
fi

printf 'PASS: shared connected-surface primitives remain the active popup/sidebar contract\n'
