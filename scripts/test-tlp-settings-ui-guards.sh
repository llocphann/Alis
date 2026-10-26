#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
classic="$repo_root/modules/settings/TlpSettingRow.qml"
waffle="$repo_root/modules/waffle/settings/WTlpSettingRow.qml"
general="$repo_root/modules/settings/GeneralConfig.qml"
general_core="$repo_root/modules/settings/GeneralConfigCore.qml"
power="$repo_root/modules/settings/TlpPowerSettings.qml"
waffle_page="$repo_root/modules/waffle/settings/pages/WTlpPage.qml"
charge_limit="$repo_root/modules/settings/BatteryChargeLimitSettings.qml"
selection_group_button="$repo_root/modules/common/widgets/SelectionGroupButton.qml"
registry="$repo_root/modules/settings/SettingsPageRegistry.qml"
arrangement="$repo_root/modules/settings/SettingsArrangement.qml"
legacy_tlp="$repo_root/modules/settings/TlpConfig.qml"

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    expected=$1
    actual=$2
    message=$3
    [ "$expected" = "$actual" ] || fail "$message (expected '$expected', got '$actual')"
}

assert_contains() {
    needle=$1
    file=$2
    message=$3
    grep -Fq -- "$needle" "$file" || fail "$message"
}

assert_not_contains() {
    needle=$1
    file=$2
    message=$3
    if grep -Fq -- "$needle" "$file"; then
        fail "$message"
    fi
}

for row in "$classic" "$waffle"; do
    assert_contains 'active: AlisIntergration.tlpEnabled' "$row" "$(basename "$row") must gate its optional payload"
    assert_not_contains 'gpuFrequencyGroupKeys' "$row" "$(basename "$row") must not duplicate integration implementation"
done

# Classic Settings integration: TLP is a System → Power task, not a separate
# navigation page. Static search must target the real embedded card titles so
# spotlight navigation can both switch tabs and scroll to the requested card.
assert_contains 'GeneralConfigCore {' "$general" \
    'System settings must retain the upstream GeneralConfig core'
assert_contains 'showIntegrationSettings: false' "$general" \
    'System settings must embed the TLP power controls'
assert_contains 'visible: root.activeSection === "power"' "$general" \
    'embedded TLP controls must only be visible in the Power task'
assert_contains 'SettingsPageRegistry.navigateToKey("integrations", "TLP "' "$general" \
    'TLP deep links must use the visible category model after battery-care integration'
if grep -Fq 'root.selectTlpCategory("battery-care")' "$general"; then
    fail 'charge-care deep links must land on the merged Power card, not a retired category tab'
fi
assert_contains 'SettingsPageRegistry.consumeLegacyTlpPowerRedirect()' "$general" \
    'legacy page-28 state must land on the Power task instead of Audio'
assert_contains 'property string settingsTaskSection: "power"' "$power" \
    'TLP controls must identify themselves as part of the Power task'
assert_not_contains 'settingsTaskSection: "power"' "$general_core" \
    'System settings must not render a second standalone Battery card'
assert_not_contains 'No charge limit active' "$charge_limit" \
    'inactive charge-limit state must not add redundant status text'
assert_contains '&& (!Battery.chargeLimitStateKnown || Battery.chargeLimitActive)' "$charge_limit" \
    'charge-limit status text must only appear for unknown or active state'
assert_contains 'Layout.fillWidth: root.leftAlignContent' "$selection_group_button" \
    'scoped category left alignment must consume trailing button space without changing global controls'
assert_contains 'import Quickshell' "$registry" \
    'SettingsPageRegistry must import the Quickshell Singleton type or shell startup will fail'
assert_contains 'readonly property int retiredTlpPageIndex: 28' "$registry" \
    'the historical TLP page index must stay retired from public navigation'
assert_contains 'if (!page)' "$registry" \
    'retired numeric slots must remain null migration gaps, not compatibility page instances'
assert_contains 'function isHiddenLegacyIndex(index: int): bool' "$registry" \
    'the registry must centralize filtering of retired navigation indexes'
assert_contains 'SettingsPageRegistryData.legacyHiddenIndexes.includes(index)' "$registry" \
    'the hidden-index invariant must come from the canonical retired-page list'
assert_contains 'pages:category.pages.filter(index=>root.isPageApplicable(index))' "$registry" \
    'retired compatibility pages must never reappear in sidebar categories'
assert_contains 'Persistent.states.settings.iiPage = root.systemPageIndex' "$registry" \
    'persisted legacy page 28 must migrate to System when Persistent becomes available'
assert_contains 'function consumeLegacyTlpPowerRedirect(): bool' "$registry" \
    'legacy current-page migration must expose a one-shot Power landing hint'
assert_not_contains 'redirected.pageIndex = root.systemPageIndex' "$registry" \
    'retired TLP search aliases must not survive in the runtime registry'
assert_contains 'const retired = SettingsPageRegistryData.legacyHiddenIndexes' "$arrangement" \
    'saved arrangements must derive hidden compatibility slots from the canonical retired-page list'
assert_contains 'for (const index of retired)' "$arrangement" \
    'all retired compatibility pages, including historical page 28, must stay internal-only'
[ ! -e "$legacy_tlp" ] || fail 'retired TlpConfig compatibility page must be deleted'

# Worker/kernel/schema/batch guards run in AlisIntergration. Keep host registration
# and supported Waffle routing/optional gates in the core.
assert_contains 'singleton TlpRuntimeCapabilities 1.0 TlpRuntimeCapabilities.qml' "$repo_root/services/qmldir" 'typed capability facade must remain registered'
assert_contains 'pageTitle: Translation.tr("Battery")' "$waffle_page" 'Waffle Battery page must remain registered'
assert_contains 'source: AlisIntergration.settingsSource("tlpWaffle")' "$waffle_page" 'Waffle page must load the optional presentation'
assert_contains 'active: root.visible && AlisIntergration.tlpEnabled' "$waffle_page" 'Waffle settings must be selected and visible'
assert_contains 'active: root.showIntegrationSettings && root.visible && AlisIntergration.tlpEnabled' "$power" 'core TLP card must require selected optional integration'

printf '%s\n' '1..1'
printf '%s\n' 'ok 1 - TLP UI guards and System Power integration are present'
