#!/usr/bin/env bash
# Exercise the Utilities popup host without changing displays, audio devices or light state.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
layout="$repo_root/modules/abyss/looks/AbyssLayout.js"
quick_actions="$repo_root/modules/bar/UtilButtons.qml"
module="$repo_root/modules/abyss/bar/AbyssBarModule.qml"
migration="$repo_root/sdata/migrations/055-retire-abyss-utilities-module.sh"
utility_popup="$repo_root/modules/abyss/content/AbyssUtilitiesPopup.qml"
monitor_config="$repo_root/modules/settings/MonitorVisibilityConfig.qml"
settings_section="$repo_root/modules/common/widgets/SettingsCardSection.qml"
popup_content="$repo_root/modules/abyss/content/AbyssPopupContent.qml"
night_light_dialog="$repo_root/modules/sidebarRight/nightLight/NightLightDialog.qml"
perimeter="$repo_root/modules/abyss/AbyssPerimeter.qml"

for token in \
    'signal utilitiesHoverChanged(bool hovered)' \
    'Component.onDestruction: root.utilitiesHoverChanged(false)' \
    'onButtonHoveredChanged: root.utilitiesHoverChanged(buttonHovered)'; do
    grep -Fq "$token" "$quick_actions" \
        || { printf 'FAIL: Utilities trigger hover contract missing: %s\n' "$token" >&2; exit 1; }
done
grep -Fq 'onButtonHoveredChanged: root.utilitiesHoverChanged(buttonHovered)' "$quick_actions" \
    || { printf 'FAIL: Utilities trigger does not reuse RippleButton hover state\n' >&2; exit 1; }
if sed -n '/id: utilitiesButton/,/MaterialSymbol {/p' "$quick_actions" | grep -Fq 'HoverHandler {'; then
    printf 'FAIL: Utilities trigger inserts a PointerHandler into CircleUtilButton Item-only content\n' >&2
    exit 1
fi

for token in \
    'onUtilitiesHoverChanged: hovered =>' \
    'root.hoverRequest("utilities")'; do
    grep -Fq "$token" "$module" \
        || { printf 'FAIL: Abyss Utilities hover routing missing: %s\n' "$token" >&2; exit 1; }
done
for token in \
    '["wifi","bluetooth","utilities","launcher","dockAppMenu"].includes(root.kind)' \
    'property bool autoDismissOnIdle: true' \
    'id: idleDismiss'; do
    grep -Fq "$token" "$popup_content" \
        || { printf 'FAIL: shared popup hover/focus lease missing: %s\n' "$token" >&2; exit 1; }
done
grep -Fq 'kind === "utilities" && same' "$perimeter" \
    || { printf 'FAIL: Utilities click is not idempotent while hover-open\n' >&2; exit 1; }
if grep -Fq 'description: "Close utilities"' "$utility_popup" || grep -Fq 'glyph: "close"' "$utility_popup"; then
    printf 'FAIL: Utilities still exposes a manual Close action\n' >&2
    exit 1
fi
for token in \
    'Audio.inputDevices.map' \
    'Audio.setDefaultSource(device)' \
    'Audio.micVolume' \
    'Audio.setSourceVolume(value)' \
    'Audio.toggleMicMute()'; do
    grep -Fq "$token" "$utility_popup" \
        || { printf 'FAIL: Utilities Sound page missing input control: %s\n' "$token" >&2; exit 1; }
done

grep -Fq 'focus: false' "$utility_popup" \
    || { printf 'FAIL: hover-owned Utilities pre-focuses and can retain its dismissal lease\n' >&2; exit 1; }

for token in \
    'font.pixelSize: Appearance.font.pixelSize.small' \
    'font.pixelSize: Appearance.font.pixelSize.smaller' \
    'font.pixelSize: Appearance.font.pixelSize.smallest' \
    'visible: !DisplayMode.mirrorAvailable' \
    'text: Translation.tr("Duplicate unavailable: install wl-mirror.")'; do
    grep -Fq "$token" "$utility_popup" \
        || { printf 'FAIL: Utilities compact Weather-like typography missing: %s\n' "$token" >&2; exit 1; }
done
for redundant in \
    'Choose active displays.' \
    'wl-mirror ready' \
    'Mirror via wl-mirror.' \
    'text: "Output device"' \
    'text: "Input device"'; do
    if grep -Fq "$redundant" "$utility_popup"; then
        printf 'FAIL: Utilities retains redundant copy: %s\n' "$redundant" >&2
        exit 1
    fi
done

for token in \
    'visible: !root.embeddedPresentation' \
    'id: nightLightPrimaryToggles' \
    'columns: root.embeddedPresentation ? 2 : 1' \
    '? Translation.tr("Enable")' \
    ': Translation.tr("Enable now")' \
    'component EmbeddedSliderRow: RowLayout' \
    'Layout.preferredWidth: 190' \
    'id: embeddedSliderControl' \
    'id: embeddedSliderValue' \
    'label: Translation.tr("Intensity")' \
    'label: Translation.tr(parent.modelData.label)' \
    'label: Translation.tr("Brightness")'; do
    grep -Fq "$token" "$night_light_dialog" \
        || { printf 'FAIL: embedded Eye protection inline-slider contract missing: %s\n' "$token" >&2; exit 1; }
done
if [[ "$(grep -Fc 'WindowDialogSeparator {' "$night_light_dialog")" -ne 3 ]]; then
    printf 'FAIL: Eye protection separator structure changed unexpectedly\n' >&2
    exit 1
fi
if [[ "$(grep -Fc 'visible: !root.embeddedPresentation' "$night_light_dialog")" -lt 4 ]]; then
    printf 'FAIL: Eye protection separators are still visible in embedded Utilities\n' >&2
    exit 1
fi
if grep -Fq 'Math.max(160, protectionContent.width - 64)' "$night_light_dialog"; then
    printf 'FAIL: Eye protection still carries embedded separator-width styling\n' >&2
    exit 1
fi
if grep -Fq 'id: embeddedBrightnessRow' "$night_light_dialog" \
        || grep -Fq 'id: embeddedBrightnessSlider' "$night_light_dialog"; then
    printf 'FAIL: Eye protection still carries the one-off Brightness slider row\n' >&2
    exit 1
fi
if [[ "$(grep -Fc 'EmbeddedSliderRow {' "$night_light_dialog")" -lt 3 ]]; then
    printf 'FAIL: Eye protection sliders are not consistently using the shared inline row\n' >&2
    exit 1
fi

grep -Fq 'SwipeView {' "$utility_popup" \
    || { printf 'FAIL: Utilities horizontal page slider missing\n' >&2; exit 1; }
grep -Fq 'interactive: true' "$utility_popup" \
    || { printf 'FAIL: Utilities horizontal swipe interaction missing\n' >&2; exit 1; }
if grep -Fq 'Behavior on implicitWidth' "$utility_popup" \
        || grep -Fq 'Behavior on implicitHeight' "$utility_popup"; then
    printf 'FAIL: Utilities tab changes still layer popup resize motion over the horizontal slide\n' >&2
    exit 1
fi
for token in \
    'readonly property int panelWidth: 560' \
    'readonly property int panelHeight: 360' \
    'implicitWidth: panelWidth' \
    'implicitHeight: panelHeight'; do
    grep -Fq "$token" "$utility_popup" \
        || { printf 'FAIL: Utilities fixed viewport contract missing: %s\n' "$token" >&2; exit 1; }
done
for obsolete in \
    'geometryPage' \
    'pendingGeometryPage' \
    'queuePageGeometry' \
    'geometrySettleTimer'; do
    if grep -Fq "$obsolete" "$utility_popup"; then
        printf 'FAIL: Utilities still carries per-tab geometry retargeting: %s\n' "$obsolete" >&2
        exit 1
    fi
done
grep -Fq 'readonly property bool arrangementChromeVisible: !embeddedArrangementOnly' "$monitor_config" \
    || { printf 'FAIL: embedded Monitor Arrangement chrome gate missing\n' >&2; exit 1; }
grep -Fq 'showHeader: root.arrangementChromeVisible' "$monitor_config" \
    || { printf 'FAIL: embedded Monitor Arrangement still exposes its drop-down header\n' >&2; exit 1; }
for token in \
    'embeddedArrangementOnly ? Math.max(160, height - 55) : 292' \
    'embeddedArrangementOnly ? 0.65 : 0.70' \
    '? Math.min(height, 252) : height' \
    'objectName: "monitorArrangementCanvas"' \
    'fitScale * root.arrangementVisualScale' \
    'implicitWidth: root.embeddedArrangementOnly ? 30 : 34'; do
    grep -Fq "$token" "$monitor_config" \
        || { printf 'FAIL: compact embedded Monitor Arrangement contract missing: %s\n' "$token" >&2; exit 1; }
done
grep -Fq 'property bool showHeader: true' "$settings_section" \
    || { printf 'FAIL: reusable Settings section cannot suppress embedded header chrome\n' >&2; exit 1; }

grep -Fq '"utilities"' "$layout" && {
    printf 'FAIL: Utilities remains a standalone Abyss Edge module\n' >&2
    exit 1
}
grep -Fq 'Config.options?.bar?.utilButtons?.showUtilitiesLauncher ?? true' "$module" \
    || { printf 'FAIL: Abyss Quick Actions does not enable the Utilities launcher\n' >&2; exit 1; }
grep -Fq 'signal utilitiesRequested()' "$quick_actions" \
    || { printf 'FAIL: shared Quick Actions lacks the opt-in Utilities launcher contract\n' >&2; exit 1; }
grep -Fq 'MIGRATION_ID="055-retire-abyss-utilities-module"' "$migration" \
    || { printf 'FAIL: retired Utilities module migration missing\n' >&2; exit 1; }

migration_tmp="$(mktemp -d)"
trap 'rm -rf -- "$migration_tmp"' EXIT
mkdir -p "$migration_tmp/inir"
cat > "$migration_tmp/inir/config.json" <<'JSON'
{"abyss":{"modules":{"placements":[{"id":"utilities","kind":"utilities"},{"id":"quick","kind":"utilButtons"}],"outputLayouts":[{"outputName":"A","placements":[{"id":"u-a","kind":"utilities"},{"id":"clock","kind":"clock"}]},{"outputName":"B","placements":[{"id":"u-b","kind":"utilities"}]}]}}}
JSON
(
    export XDG_CONFIG_HOME="$migration_tmp"
    source "$migration"
    migration_check || { printf 'FAIL: Utilities migration did not detect retired module\n' >&2; exit 1; }
    migration_apply || { printf 'FAIL: Utilities migration apply failed\n' >&2; exit 1; }
    migration_check && { printf 'FAIL: Utilities migration is not idempotent\n' >&2; exit 1; }
    jq -e '
        (.abyss.modules.placements | map(.kind)) == ["utilButtons"]
        and ((.abyss.modules.outputLayouts[0].placements | map(.kind) | sort) == ["clock","utilButtons"])
        and (.abyss.modules.outputLayouts[1].placements | map(.kind)) == ["utilButtons"]
        and (.abyss.modules.outputLayouts[0].placements[] | select(.kind=="utilButtons") | .id) == "utilButtons"
    ' "$XDG_CONFIG_HOME/inir/config.json" >/dev/null \
        || { printf 'FAIL: Utilities migration did not preserve/insert Quick Actions correctly\n' >&2; exit 1; }
)

if ! command -v qs >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    printf 'SKIP: Abyss Utilities popup runtime (Quickshell/Wayland unavailable)\n'
    exit 0
fi
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
for entry in modules services GlobalStates.qml qmldir assets scripts defaults translations; do
    ln -s "$repo_root/$entry" "$test_root/$entry"
done
mkdir -p "$test_root/config/illogical-impulse"
cp "$repo_root/defaults/config.json" "$test_root/config/illogical-impulse/config.json"
cat > "$test_root/shell.qml" <<'QML'
//@ pragma ShellId hadalis-abyss-utilities-popup-test
import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.abyss.content

ShellRoot {
    id: root
    property int step: 0
    property bool finished: false
    property int dismissed: 0
    property real monitorWidth: 0
    property real monitorHeight: 0
    TestCase { id: driver; when: false; optional: true }
    function check(ok,message): bool {
        if (ok) return true
        console.error("UTILITIES_POPUP_FAIL",message)
        root.finished = true
        return false
    }

    FloatingWindow {

        color: "#111820"
        visible: true
        implicitWidth: 900
        implicitHeight: 720
        AbyssPopupContent {
            id: popup
            // Measure the real 560x360 popup footprint, not the larger
            // outer 900x720 fixture window.
            anchors.centerIn: parent
            width: 560
            height: 360
            kind: "utilities"
            autoDismissOnIdle: false
            outputName: "utilities-test"
            onCloseRequested: root.dismissed++
        }
    }

    Timer {
        interval: 350
        repeat: true
        running: !root.finished
        onTriggered: {
            if (!Config.ready) return
            const utility = popup.feature
            if (root.step === 0) {
                Config.setNestedValue("panelFamily","abyss")
            } else if (root.step === 1) {
                if (!root.check(utility !== null, "Utilities feature loads through AbyssPopupContent")) return
                if (!root.check(utility.implicitWidth === 560 && utility.implicitHeight === 360,
                    "Utilities feature uses the shared 560x360 viewport")) return
                root.monitorWidth = popup.desiredWidth
                root.monitorHeight = popup.desiredHeight
                const canvas = driver.findChild(utility, "monitorArrangementCanvas")
                const dots = driver.findChild(utility, "utilitiesPageIndicators")
                if (!root.check(!!canvas && !!dots, "monitor canvas and pager are loaded")) return
                const gap = dots.mapToItem(utility, 0, 0).y
                    - canvas.mapToItem(utility, 0, canvas.height).y
                if (!root.check(gap >= 0 && gap <= 56,
                    "monitor canvas has no oversized blank band before dots: " + gap)) return
                if (!root.check(utility.currentPage === 0 && utility.loadedPageCount > 0
                    && utility.loadedPageCount <= 3, "pages are lazy rather than all eagerly loaded")) return
                utility.currentPage = 1
            } else if (root.step === 2) {
                if (!root.check(utility.currentPage === 1 && utility.currentFeature !== null,
                    "Display mode page participates in horizontal navigation")) return
                if (!root.check(popup.desiredWidth === root.monitorWidth && popup.desiredHeight === root.monitorHeight,
                    "Utilities footprint stays fixed across tabs")) return
                utility.currentPage = 2
            } else if (root.step === 3) {
                if (!root.check(utility.currentPage === 2 && utility.currentFeature !== null,
                    "Sound page loads without changing the default sink/source")) return
                if (!root.check(utility.loadedPageCount <= 3,
                    "lazy page window remains bounded while swiping")) return
                utility.currentPage = 3
            } else if (root.step === 4) {
                if (!root.check(utility.currentPage === 3 && utility.currentFeature !== null,
                    "Eye protection page participates in horizontal navigation")) return
                if (!root.check(popup.desiredWidth === root.monitorWidth && popup.desiredHeight === root.monitorHeight,
                    "Utilities footprint stays fixed through Eye protection")) return
                utility.closeRequested()
            } else if (root.step === 5) {
                if (!root.check(root.dismissed === 1, "Utilities close request propagates through popup content")) return
                console.info("UTILITIES_POPUP_PASS")
                root.finished = true
            }
            root.step++
        }
    }
}
QML
status=0
env -u QS_CONFIG_PATH -u QS_CONFIG_NAME -u QS_MANIFEST QT_QPA_PLATFORM=wayland \
    XDG_CONFIG_HOME="$test_root/config" XDG_STATE_HOME="$test_root/state" \
    XDG_CACHE_HOME="$test_root/cache" timeout 20s qs -p "$test_root" --no-color \
    > "$test_root/runtime.log" 2>&1 || status=$?
if [[ "$status" != 124 ]] || ! rg -q 'UTILITIES_POPUP_PASS' "$test_root/runtime.log" \
        || rg -q 'UTILITIES_POPUP_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign|is not a type' "$test_root/runtime.log"; then
    cat "$test_root/runtime.log"
    exit 1
fi
printf 'PASS: Utilities uses a compact shared viewport and inline Eye protection sliders\n'
