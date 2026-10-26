#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
common="$root/modules/common/perimeter"
qmldir="$common/qmldir"
styled="$root/modules/bar/StyledPopup.qml"
geometry="$common/ConnectedSurfaceGeometry.qml"
sidebar="$root/modules/sidebar/SidebarHost.qml"
overview="$root/modules/overview/Overview.qml"

fail() {
    printf 'FAIL: perimeter retirement contract: %s\n' "$1" >&2
    exit 1
}

for file in "$qmldir" "$styled" "$geometry" "$sidebar" "$overview"; do
    [[ -f "$file" ]] || fail "missing ${file#$root/}"
done

retired_files=(
    PerimeterConfig.qml
    PerimeterCutoverPolicy.qml
    PerimeterRuntimeHealth.qml
    ModuleRegistry.qml
    AnchorRegistry.qml
    SurfaceRouteController.qml
    PerimeterContext.qml
    PerimeterSlotModel.qml
    PerimeterModuleHost.qml
    PerimeterSlotHost.qml
    PerimeterOutputHost.qml
    AnchorPublisher.qml
    ConnectedSurfaceRouteState.qml
)
for file in "${retired_files[@]}"; do
    [[ ! -e "$common/$file" ]] || fail "retired common runtime helper still exists: $file"
    if grep -Fq "${file%.qml} " "$qmldir"; then
        fail "retired common runtime helper is still exported: $file"
    fi
done

for file in ConnectedSurfaceJoinFlares.qml PerimeterCornerShadow.qml; do
    [[ ! -e "$common/$file" ]] || fail "retired round-wedge primitive still exists: $file"
    ! grep -Fq "${file%.qml} 1.0" "$qmldir" || fail "retired round-wedge export remains: $file"
done
[[ ! -e "$root/modules/common/widgets/RoundCorner.qml" ]] || fail 'retired RoundCorner painter still exists'
! grep -Fq 'RoundCorner 1.0' "$root/modules/common/widgets/qmldir" || fail 'retired RoundCorner export remains'

for export in \
    'PerimeterTopology 1.0 PerimeterTopology.qml' \
    'PerimeterTokens 1.0 PerimeterTokens.qml' \
    'ConnectedSurfaceGeometry 1.0 ConnectedSurfaceGeometry.qml' \
    'ConnectedSurfaceConnector 1.0 ConnectedSurfaceConnector.qml' \
    'ConnectedSurfaceFrame 1.0 ConnectedSurfaceFrame.qml' \
    'ConnectedSurfaceContentHost 1.0 ConnectedSurfaceContentHost.qml' \
    'ConnectedSurfaceMask 1.0 ConnectedSurfaceMask.qml' \
    'ConnectedSurfaceAbyssField 1.0 ConnectedSurfaceAbyssField.qml' \
    'ConnectedSurfaceAbyssFrame 1.0 ConnectedSurfaceAbyssFrame.qml' \
    'ConnectedSurfaceAbyssEdgeSurface 1.0 ConnectedSurfaceAbyssEdgeSurface.qml' \
    'ConnectedSurfaceBodyMask 1.0 ConnectedSurfaceBodyMask.qml'; do
    grep -Fq "$export" "$qmldir" || fail "supported perimeter export missing: $export"
done

grep -Fq 'PerimeterTopology.inwardDirectionForEdge(edge)' "$geometry" \
    || fail 'ConnectedSurfaceGeometry lost the supported edge utility'
grep -Fq 'property real connectorWidth: PerimeterTokens.connectorWidth' "$geometry" \
    || fail 'ConnectedSurfaceGeometry lost shared connector tokens'

for primitive in ConnectedSurfaceGeometry ConnectedSurfaceAbyssFrame ConnectedSurfaceContentHost ConnectedSurfaceBodyMask; do
    grep -Fq "$primitive" "$styled" || fail "StyledPopup no longer uses supported primitive: $primitive"
done

grep -Fq 'ConnectedSurfaceAbyssEdgeSurface {' "$sidebar" \
    || fail 'SidebarHost lost the supported Abyss edge-surface adapter'
grep -Fq 'readonly property real hiddenTranslateDistance:' "$sidebar" \
    || fail 'SidebarHost lost its full-hide distance'
if grep -Fq 'ConnectedSurfaceConnector {' "$sidebar" \
        || grep -Fq 'ConnectedSurfaceJoinFlares {' "$sidebar"; then
    fail 'SidebarHost restored retired connector/flare patch geometry'
fi
grep -Fq 'attachmentThickness: root.bottomAttachmentThickness' "$overview" \
    || fail 'Overview no longer passes the real bottom owner thickness to Dashboard'

printf 'PASS: broad perimeter runtime/common helpers are retired; connected primitives remain supported\n'
