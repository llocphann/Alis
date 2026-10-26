#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
styled="$root/modules/bar/StyledPopup.qml"
media="$root/modules/bar/Media.qml"
weather_bar="$root/modules/bar/weather/WeatherBar.qml"
weather_popup="$root/modules/bar/weather/WeatherPopup.qml"
sidebar="$root/modules/sidebar/SidebarHost.qml"

fail() {
    printf 'FAIL: supported connected route contract: %s\n' "$1" >&2
    exit 1
}

for file in "$styled" "$media" "$weather_bar" "$weather_popup" "$sidebar"; do
    [[ -f "$file" ]] || fail "missing ${file#$root/}"
done

for token in \
    'property bool requestedVisible' \
    'property bool _lingerVisible' \
    'property real revealProgress' \
    'retractTimer' \
    'progress: root.revealProgress'; do
    grep -Fq "$token" "$styled" || fail "StyledPopup route lifecycle missing: $token"
done

grep -Fq 'StyledPopup {' "$media" \
    || fail 'Media expanded presentation must use StyledPopup'
grep -Fq 'keyboardFocus: root.barMediaPopupVisible' "$media" \
    || fail 'Media expanded presentation must preserve focused connected-popup routing'
grep -Fq 'StyledPopup {' "$weather_popup" \
    || fail 'Weather hover presentation must use StyledPopup'
python3 "$root/scripts/test-connected-route-lifecycle.py" \
    || fail 'Weather connected actions or hover-owned route regressed'
grep -Fq 'ConnectedSurfaceAbyssEdgeSurface {' "$sidebar" \
    || fail 'left/right SidebarHost must use the shared Abyss edge adapter'
grep -Fq 'readonly property real hiddenTranslateDistance:' "$sidebar" \
    || fail 'left/right SidebarHost must fully clear its native host on close'
if grep -Fq 'ConnectedSurfaceConnector {' "$sidebar"; then
    fail 'left/right SidebarHost surfaces must not use connector stems'
fi

for file in "$media" "$weather_bar" "$weather_popup" "$sidebar"; do
    if grep -Fq 'SurfaceRouteController' "$file" || grep -Fq 'qs.modules.perimeter' "$file"; then
        fail "normal UX route must not depend on retired broad perimeter routing: ${file#$root/}"
    fi
done

printf 'PASS: Media/Weather/SidebarHost routes use supported connected presentation paths\n'
