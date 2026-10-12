#!/usr/bin/env bash
# Exercise the production host's loading/input/retraction lifecycle in QML.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    printf 'SKIP: Abyss runtime contract (Quickshell unavailable)\n'
    exit 0
fi
abyss_test_root="$(mktemp -d)"
trap 'rm -rf -- "$abyss_test_root"' EXIT
for entry in modules services GlobalStates.qml qmldir assets scripts defaults translations; do
    ln -s "$repo_root/$entry" "$abyss_test_root/$entry"
done
mkdir -p "$abyss_test_root/config/illogical-impulse"
cp "$repo_root/defaults/config.json" "$abyss_test_root/config/illogical-impulse/config.json"
cat > "$abyss_test_root/Content.qml" <<'QML'
import QtQuick
Item { property string outputName: ""; signal closeRequested() }
QML
cat > "$abyss_test_root/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.abyss
import qs.modules.abyss.bar
ShellRoot {
    property int step: 0
    property bool failed: false
    function check(condition, message): bool {
        if (condition) return true
        failed = true
        console.error("ABYSS_RUNTIME_FAIL", message)
        Qt.quit()
        return false
    }
    Loader { id: deferred; source: "modules/abyss/ShellAbyssPanelsImpl.qml" }
    AbyssSurfaceController { id: firstOutput; outputName: "DP-test" }
    AbyssSurfaceController { id: secondOutput; outputName: "DP-other" }
    AbyssBar { id: moduleLayer; outputName: "DP-test"; edge: "top"; width: 1000; height: 700 }
    Item {
        width: 1000; height: 700
        AbyssBodyHost {
            id: body
            anchors.fill: parent
            edge: "right"; outputName: "DP-test"
            identity: "runtimeBody"; controller: firstOutput
            along: 80; span: 450; depth: 300
            source: Qt.resolvedUrl("Content.qml")
        }
    }
    Timer {
        interval: 400; running: true; repeat: true
        onTriggered: {
            if (failed) return
            if (step === 0) {
                Config.setNestedValue("abyss.waves.enabled",true)
                if (!check(deferred.status === Loader.Ready,"shared fallback composition")) return
                GlobalStates.shellEntryReady = true
                GlobalStates.deferredPanelsReady = false
                body.open = true
            } else if (step === 1) {
                if (!check(!body.ready && body.inputBounds.width === 0,"deferred gate")) return
                GlobalStates.deferredPanelsReady = true
            } else if (step === 2) {
                if (!check(body.ready && body.inputBounds.width > 0 && body.inputBounds.height > 0,"visible content input")) return
                if (!check(firstOutput.records.length === 1 && firstOutput.inputBounds.length === 1 && secondOutput.records.length === 0,"output-local participant geometry/input")) return
                if (!check(firstOutput.waves.simulation.displacement.some(value => value > 0.01),"opening pulls the physical wave loop")) return
                if (!check(body.contentItem.item.outputName === "DP-test","output binding")) return
                firstOutput.waves.reset()
                body.open = false
                if (!check(firstOutput.waves.simulation.velocity.some(value => value < 0),"closing returns a negative rebound impulse")) return
                if (!check(body.inputBounds.width === 0 && body.inputBounds.height === 0,"immediate input release")) return
                if (!check(firstOutput.inputBounds.length === 0,"registry immediate input release")) return
                if (!check(!body.contentItem.enabled,"disabled content while retracting")) return
            } else if (step === 4) {
                if (!check(!body.ready && body.record.surface.width === 0,"retracted host unload")) return
                if (!check(firstOutput.records.length === 0,"registry retracts with body")) return
                body.controller = secondOutput
                moduleLayer.draftPlacements = [
                    {id:"clock",kind:"clock",edge:"top",position:.4,enabled:true,size:1,depth:1,influence:1},
                    {id:"media",kind:"media",edge:"right",position:.5,enabled:true,size:1,depth:1,influence:1}]
                Config.setNestedValue("performance.reduceAnimations",true)
                body.open = true
            } else if (step === 5) {
                if (!check(body.ready && body.inputBounds.width > 0,"reopen")) return
                if (!check(firstOutput.records.length === 0 && secondOutput.records.length === 1,"participant migration releases previous output")) return
                body.open = false
                if (!check(body.inputBounds.width === 0,"reopen close input release")) return
                if (!check(body.progress === 0,"reduced motion closes synchronously")) return
            } else if (step === 7) {
                if (!check(!body.ready,"reopen unload")) return
                if (!check(moduleLayer.layoutRecords.length === 2 && moduleLayer.inputRegions.length === 2,"module-only input regions follow cross-edge placement")) return
                if (!check(moduleLayer.deformations.length === 0,"resting modules do not dent the flat Screen Edge")) return
                if (!check(moduleLayer.moduleIds.every((id,index) => {
                    const module=moduleLayer.itemForId(id),region=moduleLayer.inputRegions[index]
                    return module && region && region.width>0 && region.height>0
                        && region.x===Math.floor(module.x) && region.y===Math.floor(module.y)
                        && region.width===Math.ceil(module.x+module.width)-Math.floor(module.x)
                        && region.height===Math.ceil(module.y+module.height)-Math.floor(module.y)
                        && region.width<moduleLayer.width && region.height<moduleLayer.height
                }),"no fullscreen module input")) return
                const clock = moduleLayer.itemForId("clock")
                const clockRegion = moduleLayer.inputRegions[moduleLayer.moduleIds.indexOf("clock")]
                if (!check(clock && clockRegion &&
                    clockRegion.x === Math.floor(clock.x) &&
                    clockRegion.y === Math.floor(clock.y) &&
                    clockRegion.width === Math.ceil(clock.x + clock.width) - Math.floor(clock.x) &&
                    clockRegion.height === Math.ceil(clock.y + clock.height) - Math.floor(clock.y),
                    "normal-mode pointer region must track real rendered module geometry")) return
                // Move the module after the Region object is already in the
                // parent mask; it must follow geometry without remounting.
                const oldX = clockRegion.x
                moduleLayer.draftPlacements = moduleLayer.draftPlacements.map(p =>
                    p.id === "clock" ? Object.assign({}, p, {position:.62}) : p)
                if (!check(clockRegion.x !== oldX
                    && clockRegion.x === Math.floor(clock.x),
                    "moving a module must refresh the already-bound input Region")) return
                moduleLayer.editing = true
                if (!check(moduleLayer.inputRegions.every(region => region.width === 0 && region.height === 0),
                    "Edit Mode must leave module hitboxes to the editor handles")) return
                moduleLayer.editing = false
                if (!check(clockRegion.width > 0 && clockRegion.height > 0,
                    "normal-mode input region must recover without recreating modules")) return
                console.info("ABYSS_RUNTIME_PASS")
                Qt.quit()
            }
            step++
        }
    }
}
QML
if ! dbus-run-session -- env -u QS_CONFIG_NAME -u QS_CONFIG_PATH -u QS_MANIFEST QT_QPA_PLATFORM=wayland XDG_CONFIG_HOME="$abyss_test_root/config" XDG_STATE_HOME="$abyss_test_root/state" XDG_CACHE_HOME="$abyss_test_root/cache" timeout 12s qs -p "$abyss_test_root" --no-color > "$abyss_test_root/runtime.log" 2>&1; then
    cat "$abyss_test_root/runtime.log"
    exit 1
fi
if ! rg -q 'ABYSS_RUNTIME_PASS' "$abyss_test_root/runtime.log" \
        || rg -q 'ReferenceError:|TypeError:|Binding loop|ABYSS_RUNTIME_FAIL' "$abyss_test_root/runtime.log"; then
    cat "$abyss_test_root/runtime.log"
    exit 1
fi
printf 'PASS: production Abyss host deferred loading, output binding, immediate input release and unload/reopen\n'
