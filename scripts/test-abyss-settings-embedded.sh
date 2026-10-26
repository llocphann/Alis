#!/usr/bin/env bash
# Exercise the real mature card in an embedded surface with deep-link routing.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]]; then printf 'SKIP: embedded Settings (Quickshell unavailable)\n'; exit 0; fi
settings_test_root="$(mktemp -d)"
trap 'rm -rf -- "$settings_test_root"' EXIT
for entry in modules services GlobalStates.qml qmldir assets scripts defaults translations; do
    ln -s "$repo_root/$entry" "$settings_test_root/$entry"
done
mkdir -p "$settings_test_root/config/illogical-impulse"
cp "$repo_root/defaults/config.json" "$settings_test_root/config/illogical-impulse/config.json"
cat > "$settings_test_root/shell.qml" <<'QML'
//@ pragma ShellId hadalis-abyss-settings-embedded-test
import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.abyss
import qs.modules.settings
ShellRoot {
    id: root
    property int step: 0
    property bool finished: false
    function check(value,message): bool {
        if(value) return true
        console.error("EMBEDDED_SETTINGS_FAIL",message);finished=true;return false
    }
    function embeddedPage(item,name) {
        if(item?.settingsPageName===name && item?.embedded===true) return item
        for(const child of Array.from(item?.children ?? [])) {
            const found=root.embeddedPage(child,name)
            if(found) return found
        }
        return null
    }
    function positionControls(item) {
        if(item?.position!==undefined && item?.outputName!==undefined && typeof item.change==="function") return item
        for(const child of Array.from(item?.children ?? [])) {
            const found=root.positionControls(child)
            if(found) return found
        }
        return null
    }
    FloatingWindow {
        color: "#111820"
        visible: true; implicitWidth: 1280; implicitHeight: 900
        AbyssBodyHost {
            id: body; anchors.fill: parent
            edge: "bottom"; largeSurface: true; span: 1150; depth: 800
            along: 65; source: Qt.resolvedUrl("modules/abyss/content/AbyssSettingsContent.qml")
            open: GlobalStates.settingsOverlayOpen
        }
    }
    Timer {
        interval: 300; running: !root.finished; repeat: true
        onTriggered: {
            if(!Config.ready || !Persistent.ready) return
            if(root.step===0) {
                Config.setNestedValue("panelFamily","abyss")
                Config.setNestedValue("settingsUi.overlayMode",false)
                Config.setNestedValue("performance.reduceAnimations",true)
                GlobalStates.deferredPanelsReady=true
                GlobalStates.openSettingsPage(10)
                if(!root.check(GlobalStates.settingsOverlayOpen,"Abyss opens embedded settings regardless of window preference")) return
            }
            if(root.step===3) {
                if(!root.check(body.ready,"mature Settings wrapper loaded")) return
                const card=Array.from(body.contentItem.item.children).find(c=>c.maxCardWidth!==undefined)
                if(!root.check(!!card && card.parent===body.contentItem.item,"same Settings card reparented into the liquid host")) return
                const canvas=body.contentItem.item,content=body.record.content
                // A private output may be narrower than the requested window.
                // Check the real host's complete content area and original
                // scale, instead of imposing the owner's monitor dimensions.
                if(!root.check(card.scale===1 && card.width>0 && card.height>0
                    && card.width===canvas.width && card.height===canvas.height
                    && canvas.width===content.width && canvas.height===content.height,
                    "mature layout fills the actual host at original scale")) return
                if(!root.check(GlobalStates.settingsOverlayCurrentPage===10,"deep link survives page initialization")) return
                GlobalStates.openSettingsPage(1)
            }
            if(root.step===5) {
                if(!root.check(GlobalStates.settingsOverlayCurrentPage===1,"shared page navigation remains functional")) return
                if(!root.check(SettingsPageRegistry.pageIndexForKey("abyss")===2,"Abyss replaces the former Bar route without renumbering shared pages")) return
                GlobalStates.openSettingsSection(2,"waves")
            }
            if(root.step===7) {
                if(!root.check(GlobalStates.settingsOverlayCurrentPage===2,"dedicated Abyss controls receive deep links")) return
                if(!root.check(body.contentItem.item.currentPage?.activeSection==="waves","deep link selects the visible Waves tab")) return
                GlobalStates.openSettingsSection(2,"popups")
            }
            if(root.step===9) {
                const positions=root.positionControls(body.contentItem.item.currentPage)
                if(!root.check(!!positions,"dedicated popup position controls load")) return
                positions.kind="volume";positions.outputName="A";positions.change("edge","left");positions.change("alignment","end")
                positions.outputName="B";positions.change("edge","bottom")
                const entries=Array.from(Config.options.abyss.positions)
                if(!root.check(entries.length===2 && entries[0].outputName==="A" && entries[0].edge==="left" && entries[0].alignment==="end" && entries[1].outputName==="B" && entries[1].edge==="bottom","Settings persists distinct per-output IPC positions")) return
            }
            if(root.step===11) GlobalStates.openSettingsSection(2,"spectrum")
            if(root.step===13) {
                if(!root.check(body.contentItem.item.currentPage?.activeSection==="spectrum","Spectrum deep link reaches its controls")) return
                GlobalStates.openSettingsSection(22,"")
            }
            if(root.step===15) {
                if(!root.check(GlobalStates.settingsOverlayCurrentPage===22 && body.contentItem.item.currentPage?.settingsPageName==="Dock","mature Dock page keeps stable route")) return
                GlobalStates.openSettingsSection(2,"bar")
            }
            if(root.step===17) {
                if(!root.check(body.contentItem.item.currentPage?.activeSection==="bar","module backend settings remain accessible")) return
                const modules=root.embeddedPage(body.contentItem.item.currentPage,"Bar")
                if(!root.check(modules && modules.activeSection==="modules" && modules.abyssContent && modules.implicitHeight>100,"mature media/tray/workspace settings load in Abyss")) return
                GlobalStates.openSettingsSection(23,"")
            }
            if(root.step===19) {
                if(!root.check(GlobalStates.settingsOverlayCurrentPage===23 && body.contentItem.item.currentPage?.settingsPageName==="Sidebars","mature Sidebars page keeps stable route")) return
            }
            if(root.step===21) {
                GlobalStates.settingsOverlayOpen=false
                if(!root.check(body.inputBounds.width===0,"Settings closes with immediate input release")) return
            }
            if(root.step===23) { console.info("EMBEDDED_SETTINGS_PASS");root.finished=true }
            root.step++
        }
    }
}
QML
status=0
python3 - "$repo_root" "$settings_test_root" > "$settings_test_root/runtime.log" 2>&1 <<'PY' || status=$?
import sys
from pathlib import Path
sys.path.insert(0,str(Path(sys.argv[1])/"scripts"))
from native_test_session import private_wayland,run_qs
folder=Path(sys.argv[2])
with private_wayland(folder) as env:
    if env is None:
        print("SKIP: embedded Settings require private Niri")
        raise SystemExit(77)
    result=run_qs(folder,env,timeout=20)
    print(result.stdout)
    raise SystemExit(result.returncode)
PY
if [[ "$status" == 77 ]];then cat "$settings_test_root/runtime.log";exit 0;fi
# Keep the scene alive after its assertions: an early exit/crash fails, including
# one after PASS. Avoid Qt.quit tearing down a live embedded Settings scene.
if [[ "$status" != 124 ]] || ! rg -q 'EMBEDDED_SETTINGS_PASS' "$settings_test_root/runtime.log" || rg -q 'EMBEDDED_SETTINGS_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign' "$settings_test_root/runtime.log"; then
    cat "$settings_test_root/runtime.log";exit 1
fi
printf 'PASS: mature Settings card embeds at original scale, consumes deep links, navigates and releases input\n'
