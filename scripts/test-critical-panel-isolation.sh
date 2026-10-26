#!/usr/bin/env bash
set -euo pipefail

root="${ALIS_CRITICAL_ISOLATION_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
critical="$root/modules/ii/critical/ShellIiCriticalPanels.qml"
deferred="$root/ShellIiPanels.qml"

fail() {
    printf 'FAIL: critical panel isolation contract: %s\n' "$1" >&2
    exit 1
}

[[ -f "$critical" ]] || fail 'missing modules/ii/critical/ShellIiCriticalPanels.qml'
[[ -f "$deferred" ]] || fail 'missing ShellIiPanels.qml'

# Critical composition must not import concrete optional presentation packages.
# Those components stay behind URL-based LazyLoader boundaries so a local type
# failure does not make the critical root unavailable at startup.
optional_import_re='^[[:space:]]*import[[:space:]]+qs\.modules\.(background|bar|dock|verticalBar|perimeter)([[:space:];]|$)'
if offending_import="$(grep -En -m1 "$optional_import_re" "$critical" || true)"; [[ -n "$offending_import" ]]; then
    fail "critical root still imports optional/broad presentation module: $offending_import"
fi

concrete_type_re='(Background|Bar|VerticalBar|Dock|PerimeterRuntime)'
if grep -Eq "^[[:space:]]*${concrete_type_re}[[:space:]]*\\{" "$critical" \
        || grep -Eq "^[[:space:]]*component[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*${concrete_type_re}[[:space:]]*\\{" "$critical"; then
    fail 'critical root still embeds a concrete presentation component'
fi

if grep -Fq '../../perimeter/PerimeterRuntime.qml' "$critical"; then
    fail 'critical root reintroduced the retired PerimeterRuntime source'
fi
if grep -Fq '../../sidebar/SidebarEdgeConnectors.qml' "$critical"; then
    fail 'critical root reintroduced the retired standalone Sidebar edge bridge'
fi

for source_path in \
    '../../screenCorners/ScreenEdges.qml' \
    '../../background/Background.qml' \
    '../../bar/Bar.qml' \
    '../../verticalBar/VerticalBar.qml' \
    '../../dock/Dock.qml'; do
    grep -Fq "source: Qt.resolvedUrl(\"$source_path\")" "$critical" \
        || fail "critical root does not source-load $source_path"
    resolved="$(realpath -m "$(dirname -- "$critical")/$source_path")"
    [[ -f "$resolved" ]] || fail "critical source target is missing: $source_path"
done

grep -Fq 'component CriticalPanelLoader: LazyLoader {' "$critical" \
    || fail 'critical presentation loader no longer inherits LazyLoader'

# The non-critical ii subtree is already parent-gated by shell.qml and keeps its
# own deferred-ready boundary. It must not wait on a retired perimeter registry.
grep -Fq 'source: "modules/ii/ShellIiPanelsImpl.qml"' "$deferred" \
    || fail 'deferred ii presentation subtree is not source-loaded'
grep -Fq 'loading: GlobalStates.deferredPanelsReady' "$deferred" \
    || fail 'deferred ii presentation subtree lost its readiness gate'
grep -Fq 'activeAsync: GlobalStates.deferredPanelsReady' "$deferred" \
    || fail 'deferred ii presentation subtree lost its async readiness gate'
[[ -f "$root/modules/ii/ShellIiPanelsImpl.qml" ]] \
    || fail 'deferred ii presentation source target is missing'

for retired in \
    'perimeterFeaturesReady' \
    'PerimeterFeatureRegistry' \
    'qs.modules.perimeter'; do
    if grep -Fq "$retired" "$deferred"; then
        fail "deferred ii root still depends on retired perimeter bootstrap: $retired"
    fi
done

printf 'PASS: critical presentation modules use supported source-isolation boundaries\n'
