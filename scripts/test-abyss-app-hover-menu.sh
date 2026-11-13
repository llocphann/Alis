#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${ALIS_SILENT_WL_WRAPPED:-0}" != "1" ]]; then
    export ALIS_SILENT_WL_WRAPPED=1
    exec bash "$repo_root/scripts/lib/silent-wayland-run.sh" -- "$0" "$@"
fi
if ! command -v qs >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]];then printf 'SKIP: app hover menus (Quickshell/Wayland unavailable)\n';exit 0;fi
menu_test_root="$(mktemp -d)"
trap 'rm -rf -- "$menu_test_root"' EXIT
for entry in modules services GlobalStates.qml qmldir assets scripts defaults translations;do ln -s "$repo_root/$entry" "$menu_test_root/$entry";done
mkdir -p "$menu_test_root/config/illogical-impulse"
cp "$repo_root/defaults/config.json" "$menu_test_root/config/illogical-impulse/config.json"
cat > "$menu_test_root/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.dock
import qs.modules.bar
ShellRoot {
    id:root;property int step:0;property bool finished:false
    function check(ok,message): bool { if(ok)return true;console.error("APP_HOVER_FAIL",message);finished=true;return false }
    QtObject {
        id:owner
        signal closeAllContextMenus(var exceptOwner)
        function setAbyssContextMenuHover(button, hovered) {}
        property bool contextMenuOpen:false
        property bool dragActive:false
        property bool buttonHovered:false
        property var lastHoveredButton:null
        property var toplevelsByUniqueId:({})
    }
    QtObject {
        id:barOwner
        signal closeAllContextMenus()
        property bool contextMenuOpen:false
        property bool dragActive:false
        property bool buttonHovered:false
        property var lastHoveredButton:null
        property var toplevelsByUniqueId:({})
    }
    FloatingWindow {
        color: "#111820"
        visible:true;implicitWidth:800;implicitHeight:600
        DockAppButton { id:dock;x:220;y:400;width:50;height:50;appListRoot:owner;appToplevel:({appId:"org.quickshell",originalAppId:"org.quickshell",uniqueId:"qa",toplevels:[]}) }
        BarTaskbarButton { id:bar;x:340;y:80;width:50;height:40;taskbarRoot:barOwner;appEntry:({appId:"org.quickshell",originalAppId:"org.quickshell",toplevels:[]}) }
    }
    Timer {
        interval:180;running:!root.finished;repeat:true
        onTriggered: {
            if(root.step===0) {
                Config.setNestedValue("panelFamily","abyss")
                Config.setNestedValue("performance.reduceAnimations",true)
                Config.setNestedValue("dock.hoverPreview",false)
                Config.setNestedValue("dock.hoverPreviewDelay",240)
                dock.buttonHovered=true
            } else if(root.step===3) {
                if(!root.check(owner.contextMenuOpen && GlobalStates.activeContextMenu?.model?.length>0,"hover opens mature Dock actions for an app without windows")) return
                dock.buttonHovered=false
            } else if(root.step===8) {
                if(!root.check(!owner.contextMenuOpen && GlobalStates.activeContextMenuCount===0,"Dock menu closes after its hover handoff grace")) return
                bar.buttonHovered=true
            } else if(root.step===11) {
                if(!root.check(barOwner.contextMenuOpen && GlobalStates.activeContextMenu?.model?.length>0,"hover opens mature taskbar actions")) return
                bar.buttonHovered=false
                barOwner.closeAllContextMenus()
                Config.setNestedValue("panelFamily","waffle")
                dock.buttonHovered=true
            } else if(root.step===14) {
                if(!root.check(owner.contextMenuOpen && !barOwner.contextMenuOpen && GlobalStates.activeContextMenu?.model?.length>0,"configured Dock keeps its one app-actions hover contract with Waffle family")) return
                console.info("APP_HOVER_PASS");root.finished=true
            }
            root.step++
        }
    }
}
QML
status=0
python3 - "$repo_root" "$menu_test_root" > "$menu_test_root/runtime.log" 2>&1 <<'PY' || status=$?
import sys
from pathlib import Path
sys.path.insert(0,str(Path(sys.argv[1])/"scripts"))
from native_test_session import private_wayland,run_qs
folder=Path(sys.argv[2])
with private_wayland(folder) as env:
    if env is None:
        print("SKIP: app hover menus require private Niri")
        raise SystemExit(77)
    result=run_qs(folder,env,timeout=12)
    print(result.stdout)
    raise SystemExit(result.returncode)
PY
if [[ "$status" == 77 ]];then cat "$menu_test_root/runtime.log";exit 0;fi
if [[ "$status" != 124 ]] || ! rg -q APP_HOVER_PASS "$menu_test_root/runtime.log" || rg -q 'APP_HOVER_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign|Cannot anchor|is not a type' "$menu_test_root/runtime.log";then cat "$menu_test_root/runtime.log";exit 1;fi
printf 'PASS: Dock/taskbar hover exposes actionable app menus, pointer-exit grace closes them, configured Dock keeps the same actionable hover under Waffle\n'
