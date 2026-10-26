#!/usr/bin/env bash
# Construct the mature content adapters in a real Qt window and release them.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]]; then printf 'SKIP: Abyss shared content (Quickshell/Wayland unavailable)\n'; exit 0; fi
content_test_root="$(mktemp -d)"
trap 'rm -rf -- "$content_test_root"' EXIT
for entry in modules services GlobalStates.qml qmldir assets scripts defaults translations; do
    ln -s "$repo_root/$entry" "$content_test_root/$entry"
done
mkdir -p "$content_test_root/config/illogical-impulse"
cp "$repo_root/defaults/config.json" "$content_test_root/config/illogical-impulse/config.json"
cat > "$content_test_root/shell.qml" <<'QML'
//@ pragma ShellId alis-abyss-shared-content-test
import QtQuick
import Quickshell
import qs
import qs.modules.common
ShellRoot {
    id: root
    property int step: 0
    readonly property var sources: ["AbyssDashboardContent","AbyssControlContent","AbyssOverviewContent","AbyssLeftContent","AbyssRightContent","AbyssNotificationsContent"]
    FloatingWindow {
        color: "#111820"
        visible: true; implicitWidth: 1380; implicitHeight: 900
        Loader {
            id: content; anchors.fill: parent
            onLoaded: {
                if(item.participant!==undefined) item.participant={open:true,width:1920,height:1080,outputName:"test",controller:null}
                if(item.outputName!==undefined) item.outputName="test"
            }
        }
    }
    Timer {
        interval: 400; running: true; repeat: true
        onTriggered: {
            if(root.step===0) {
                Config.setNestedValue("panelFamily","abyss")
                Config.setNestedValue("performance.reduceAnimations",true)
                Config.setNestedValue("sidebar.news.enable",false)
            }
            if(root.step%2===0 && root.step/2<root.sources.length)
                content.source=Qt.resolvedUrl("modules/abyss/content/"+root.sources[root.step/2]+".qml")
            else if(root.step%2===1) {
                if(content.status!==Loader.Ready || content.item.width<1000 || content.item.height<700) {
                    console.error("SHARED_CONTENT_FAIL",root.step,content.status);Qt.quit();return
                }
                content.source=""
            }
            if(root.step===root.sources.length*2) { console.info("SHARED_CONTENT_PASS");Qt.quit() }
            root.step++
        }
    }
}
QML
if ! dbus-run-session -- env -u QS_CONFIG_PATH -u QS_CONFIG_NAME -u QS_MANIFEST QT_QPA_PLATFORM=wayland \
    XDG_CONFIG_HOME="$content_test_root/config" XDG_STATE_HOME="$content_test_root/state" \
    XDG_CACHE_HOME="$content_test_root/cache" timeout 12s qs -p "$content_test_root" --no-color \
    > "$content_test_root/runtime.log" 2>&1; then
    cat "$content_test_root/runtime.log";exit 1
fi
if ! rg -q 'SHARED_CONTENT_PASS' "$content_test_root/runtime.log" || rg -q 'SHARED_CONTENT_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign|is not a type|Type .* unavailable' "$content_test_root/runtime.log"; then
    cat "$content_test_root/runtime.log";exit 1
fi
printf 'PASS: mature Dashboard, Control Panel, Overview, feature, system and notification content adapters load and unload at usable size\n'
