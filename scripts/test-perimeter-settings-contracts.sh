#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
settings="$root/modules/settings/ShellLayoutConfig.qml"
registry="$root/modules/settings/SettingsPageRegistryData.qml"
background="$root/modules/background/Background.qml"
overlay="$root/modules/settings/SettingsOverlay.qml"
global_states="$root/GlobalStates.qml"

fail() {
    printf 'FAIL: perimeter settings retirement contract: %s\n' "$1" >&2
    exit 1
}

[[ -f "$settings" ]] || fail 'missing modules/settings/ShellLayoutConfig.qml'
[[ -f "$registry" ]] || fail 'missing modules/settings/SettingsPageRegistryData.qml'
[[ -f "$background" ]] || fail 'missing modules/background/Background.qml'
[[ -f "$overlay" ]] || fail 'missing modules/settings/SettingsOverlay.qml'
[[ -f "$global_states" ]] || fail 'missing GlobalStates.qml'

grep -Fq 'component: "modules/settings/ShellLayoutConfig.qml"' "$registry" \
    || fail 'Shell Layout page is no longer routed through the settings registry'
grep -Fq 'title: Translation.tr("Live shell layout")' "$settings" \
    || fail 'supported live shell layout controls were removed'
grep -Fq 'ShellLayoutController.surfacesForFamily' "$settings" \
    || fail 'Shell Layout no longer uses the supported live layout controller'
grep -Fq 'ShellEditSession.enter("")' "$settings" \
    || fail 'live desktop editor entrypoint was removed'
grep -Fq 'visible: surfaceSection.sidebarRole' "$settings" \
    || fail 'sidebar sizing controls were removed with perimeter cleanup'
if grep -Fq 'SettingsLayoutManager.editMode' "$overlay"; then
    fail 'Settings overlay retained retired Edit Layout mode binding'
fi
if grep -Fq 'navEditMode' "$overlay"; then
    fail 'Settings overlay retained retired Edit Navigation mode'
fi
grep -Fq 'GlobalStates.startAbyssEditing(bgRoot.screenName)' "$background" \
    || fail 'desktop context menu does not enter the same Abyss live editor'
grep -Fq 'ShellEditSession.enter(bgRoot.screenName)' "$background" \
    || fail 'desktop context menu lost non-Abyss shell-layout entrypoint'
if grep -Fq 'ShellEditSession.toggle()' "$background"; then
    fail 'desktop context menu still uses family-ambiguous ShellEditSession.toggle'
fi
grep -Fq 'root.setShellLayoutEditMode(false)' "$global_states" \
    || fail 'Abyss editor entry does not clear stale generic shell-layout edit mode'
grep -Fq 'root.setWidgetEditMode(false)' "$global_states" \
    || fail 'Abyss editor entry does not clear stale desktop widget edit mode'

for retired in \
    'Connected Perimeter' \
    'Use Connected Perimeter runtime' \
    'PerimeterCutoverPolicy' \
    'PerimeterConfig' \
    'PerimeterTopology' \
    'iiPerimeter' \
    'qs.modules.common.perimeter'; do
    if grep -Fq "$retired" "$settings"; then
        fail "retired cutover setting/API remains in ShellLayoutConfig.qml: $retired"
    fi
done

printf 'PASS: perimeter settings retirement contracts\n'
