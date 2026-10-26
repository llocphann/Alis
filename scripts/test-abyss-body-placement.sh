#!/usr/bin/env bash
# Real host lifecycle: same-anchor stacking, readable reflow, animated eviction,
# retained drafts/input release and automatic restoration.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    printf 'SKIP: body placement (Quickshell/Wayland unavailable)\n'
    exit 0
fi
placement_test_root="$(mktemp -d)"
trap 'rm -rf -- "$placement_test_root"' EXIT
for entry in modules services GlobalStates.qml qmldir assets scripts defaults translations; do
    ln -s "$repo_root/$entry" "$placement_test_root/$entry"
done
mkdir -p "$placement_test_root/config/illogical-impulse"
cp "$repo_root/defaults/config.json" "$placement_test_root/config/illogical-impulse/config.json"
cat > "$placement_test_root/Card.qml" <<'QML'
import QtQuick
Item {
    property var participant: null
    property string draft: "unsaved note"
}
QML
cat > "$placement_test_root/shell.qml" <<'QML'
//@ pragma ShellId alis-abyss-body-placement-test
import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.abyss

ShellRoot {
    id: root
    property int step: 0
    property bool finished: false
    property var retained: null
    property real requestedAnchor: 0

    function check(ok,message): bool {
        if(ok) return true
        console.error("BODY_PLACEMENT_FAIL",message)
        finished=true
        return false
    }
    function center(host): real {
        const placement=host.placement
        return placement ? placement.along+placement.span/2 : -1
    }

    AbyssSurfaceController {
        id: controller
        outputWidth: viewport.width
        outputHeight: viewport.height
        edgeInsets: ({left:16,right:16,top:16,bottom:16})
    }

    FloatingWindow {

        color: "#111820"
        visible: true
        implicitWidth: 1100
        implicitHeight: 800
        Item {
            id: viewport
            width: 1100
            height: 800

            AbyssBodyHost {
                id: older
                anchors.fill: parent
                controller: controller
                edge: "bottom"
                identity: "older"
                animatePresentation: true
                largeSurface: true
                span: 900
                depth: 260
                minimumSpan: 520
                minimumDepth: 220
                along: 100
                edgeInsets: controller.edgeInsets
                source: Qt.resolvedUrl("Card.qml")
            }
            AbyssBodyHost {
                id: newer
                anchors.fill: parent
                controller: controller
                edge: "bottom"
                identity: "newer"
                animatePresentation: false
                largeSurface: true
                span: 420
                depth: 200
                minimumSpan: 300
                minimumDepth: 160
                along: 340
                edgeInsets: controller.edgeInsets
                source: Qt.resolvedUrl("Card.qml")
            }
        }
    }

    Timer {
        interval: 230
        running: !root.finished
        repeat: true
        onTriggered: {
            if(!Config.ready) return
            if(root.step===0) {
                Config.setNestedValue("panelFamily","abyss")
                GlobalStates.deferredPanelsReady=true
                older.open=true
            } else if(root.step===2) {
                root.retained=older.contentItem.item
                if(!root.check(older.ready && older.presented,"first host loads")) return
                root.retained.draft="keep this draft"
                root.requestedAnchor=older.requestedRecord.along+older.requestedRecord.span/2
                newer.open=true
            } else if(root.step===4) {
                if(!root.check(older.presented && newer.presented,
                    "same-anchor contents coexist when readable space exists")) return
                if(!root.check(Math.abs(root.center(older)-root.requestedAnchor)<.01,
                    "older body keeps its physical anchor while stacking inward")) return
                if(!root.check(older.inputBounds.y+older.inputBounds.height<newer.inputBounds.y,
                    "inward partitioning prevents overlap")) return
                older.depth=viewport.height*.9
            } else if(root.step===6) {
                if(!root.check(older.presented && older.placement.shrunk,
                    "large older body reflows before eviction")) return
                if(!root.check(Math.abs(root.center(older)-root.requestedAnchor)<.01,
                    "reflow still keeps the requested anchor")) return
                if(!root.check(older.contentItem.item===root.retained
                    && root.retained.draft==="keep this draft",
                    "reflow preserves the loaded draft")) return
                // Raise the readable floor so the same body can no longer share
                // the viewport. It should begin a visual retract while input is
                // released immediately and the Loader/draft stay alive.
                older.minimumDepth=700
                Qt.callLater(() => {
                    root.check(older.placement.evicted && !older.presented
                        && older.inputBounds.width===0,
                        "unfit older body is evicted and releases input")
                    root.check(older.contentItem.item===root.retained,
                        "eviction keeps the loaded feature alive")
                })
            } else if(root.step===8) {
                if(!root.check(older.placement.evicted && older.progress<.05,
                    "evicted body completes its slide-close")) return
                if(!root.check(!older.contentParent.visible && older.contentItem.item===root.retained,
                    "closed visual retains hidden draft state")) return
                newer.open=false
            } else if(root.step===10) {
                if(!root.check(older.presented && older.inputBounds.width>0
                    && older.contentItem.item===root.retained,
                    "closing newer restores older without recreating its draft")) return
                if(!root.check(Math.abs(root.center(older)-root.requestedAnchor)<.01,
                    "restored body returns to the same physical anchor")) return
                older.open=false
            } else if(root.step===13) {
                if(!root.check(!older.ready && controller.inputBounds.length===0,
                    "semantic close unloads retained content and clears input")) return
                console.info("BODY_PLACEMENT_PASS")
                root.finished=true
            }
            root.step++
        }
    }
}
QML
status=0
env -u QS_CONFIG_PATH -u QS_CONFIG_NAME -u QS_MANIFEST QT_QPA_PLATFORM=wayland \
    XDG_CONFIG_HOME="$placement_test_root/config" XDG_STATE_HOME="$placement_test_root/state" \
    XDG_CACHE_HOME="$placement_test_root/cache" timeout 20s qs -p "$placement_test_root" --no-color \
    > "$placement_test_root/runtime.log" 2>&1 || status=$?
if [[ "$status" != 124 ]] || ! rg -q BODY_PLACEMENT_PASS "$placement_test_root/runtime.log" \
        || rg -q 'BODY_PLACEMENT_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign|is not a type' "$placement_test_root/runtime.log"; then
    cat "$placement_test_root/runtime.log"
    exit 1
fi
printf 'PASS: anchor retention, readable reflow, animated eviction, input release, draft restoration and close unload\n'
