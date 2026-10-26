#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
guard="$repo_root/scripts/test-critical-panel-isolation.sh"
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT

fail() {
    printf 'critical panel isolation regression failed: %s\n' "$1" >&2
    exit 1
}

make_fixture() {
    local root="$1"
    mkdir -p \
        "$root/modules/ii/critical" \
        "$root/modules/ii" \
        "$root/modules/screenCorners" \
        "$root/modules/background" \
        "$root/modules/bar" \
        "$root/modules/verticalBar" \
        "$root/modules/dock"

    cat > "$root/modules/ii/critical/ShellIiCriticalPanels.qml" <<'QML'
import QtQuick
import Quickshell

Item {
    component CriticalPanelLoader: LazyLoader {
        required property string identifier
    }

    LazyLoader {
        source: Qt.resolvedUrl("../../screenCorners/ScreenEdges.qml")
    }
    CriticalPanelLoader {
        source: Qt.resolvedUrl("../../background/Background.qml")
    }
    CriticalPanelLoader {
        source: Qt.resolvedUrl("../../bar/Bar.qml")
    }
    CriticalPanelLoader {
        source: Qt.resolvedUrl("../../verticalBar/VerticalBar.qml")
    }
    CriticalPanelLoader {
        source: Qt.resolvedUrl("../../dock/Dock.qml")
    }
}
QML

    cat > "$root/ShellIiPanels.qml" <<'QML'
Item {
    source: "modules/ii/ShellIiPanelsImpl.qml"
    loading: GlobalStates.deferredPanelsReady
    activeAsync: GlobalStates.deferredPanelsReady
}
QML

    for target in \
        modules/screenCorners/ScreenEdges.qml \
        modules/background/Background.qml \
        modules/bar/Bar.qml \
        modules/verticalBar/VerticalBar.qml \
        modules/dock/Dock.qml \
        modules/ii/ShellIiPanelsImpl.qml; do
        : > "$root/$target"
    done
}

run_guard() {
    ALIS_CRITICAL_ISOLATION_ROOT="$1" bash "$guard"
}

expect_failure() {
    local root="$1"
    local needle="$2"
    local output
    if output="$(run_guard "$root" 2>&1)"; then
        fail "guard unexpectedly accepted negative fixture: ${root#$stage/}"
    fi
    grep -Fq -- "$needle" <<<"$output" \
        || fail "negative fixture ${root#$stage/} did not report: $needle"
}

positive="$stage/positive"
make_fixture "$positive"
run_guard "$positive" >/dev/null \
    || fail 'guard rejected supported source-isolated positive fixture'

aliased_import="$stage/aliased-import"
make_fixture "$aliased_import"
sed -i '3i import qs.modules.bar as OptionalBar;' \
    "$aliased_import/modules/ii/critical/ShellIiCriticalPanels.qml"
expect_failure "$aliased_import" 'critical root still imports optional/broad presentation module'

direct_runtime="$stage/direct-runtime"
make_fixture "$direct_runtime"
sed -i '/^Item {/a\    PerimeterRuntime {}' \
    "$direct_runtime/modules/ii/critical/ShellIiCriticalPanels.qml"
expect_failure "$direct_runtime" 'critical root still embeds a concrete presentation component'

runtime_source="$stage/runtime-source"
make_fixture "$runtime_source"
sed -i '/^Item {/a\    LazyLoader { source: Qt.resolvedUrl("../../perimeter/PerimeterRuntime.qml") }' \
    "$runtime_source/modules/ii/critical/ShellIiCriticalPanels.qml"
expect_failure "$runtime_source" 'critical root reintroduced the retired PerimeterRuntime source'

sidebar_bridge="$stage/sidebar-bridge"
make_fixture "$sidebar_bridge"
mkdir -p "$sidebar_bridge/modules/sidebar"
: > "$sidebar_bridge/modules/sidebar/SidebarEdgeConnectors.qml"
sed -i '/^Item {/a\    LazyLoader { source: Qt.resolvedUrl("../../sidebar/SidebarEdgeConnectors.qml") }' \
    "$sidebar_bridge/modules/ii/critical/ShellIiCriticalPanels.qml"
expect_failure "$sidebar_bridge" 'critical root reintroduced the retired standalone Sidebar edge bridge'

inline_bar="$stage/inline-bar"
make_fixture "$inline_bar"
sed -i '/^Item {/a\    component EmbeddedBar: Bar {}' \
    "$inline_bar/modules/ii/critical/ShellIiCriticalPanels.qml"
expect_failure "$inline_bar" 'critical root still embeds a concrete presentation component'

perimeter_bootstrap="$stage/perimeter-bootstrap"
make_fixture "$perimeter_bootstrap"
sed -i '1i import qs.modules.perimeter' "$perimeter_bootstrap/ShellIiPanels.qml"
sed -i '/^Item {/a\    property bool perimeterFeaturesReady: PerimeterFeatureRegistry.registerAll()' \
    "$perimeter_bootstrap/ShellIiPanels.qml"
expect_failure "$perimeter_bootstrap" 'deferred ii root still depends on retired perimeter bootstrap'

printf '%s\n' '1..1'
printf '%s\n' 'ok 1 - critical panel isolation guard rejects broad perimeter bootstrap and concrete startup dependencies'
