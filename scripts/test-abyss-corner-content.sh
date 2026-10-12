#!/usr/bin/env bash
# Exercise mature corner content through the shared Abyss host, without another popup window.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
perimeter="$repo_root/modules/abyss/AbyssPerimeter.qml"
corners="$repo_root/modules/abyss/AbyssCorners.qml"
editor="$repo_root/modules/abyss/AbyssEdgeEditor.qml"
positions="$repo_root/modules/abyss/settings/AbyssPositionSettings.qml"
presentation="$repo_root/modules/abyss/looks/AbyssPresentation.js"
for token in \
    'property string quickNotesEditorOutput: ""' \
    'function setQuickNotesEditorOutput(outputName, focused): void' \
    'quickNotesEditorOutput: root.quickNotesEditorOutput' \
    'onQuickNotesEditorLeaseChanged:(outputName,focused)=>'; do
    grep -Fq "$token" "$perimeter" || { printf 'FAIL: Abyss perimeter Quick Notes lease missing: %s\n' "$token" >&2; exit 1; }
done
for token in \
    'signal quickNotesEditorLeaseChanged(string outputName, bool focused)' \
    'quickNotesEditorOutput.length === 0' \
    'quickNotesEditorOutput === outputName' \
    'onEditorFocusedChanged:' \
    'root.quickNotesEditorLeaseChanged(root.outputName,editorFocused)'; do
    grep -Fq "$token" "$corners" || { printf 'FAIL: Abyss corner Quick Notes lease missing: %s\n' "$token" >&2; exit 1; }
done
for token in \
    'function niriOverviewOwnsCorner(cornerName: string): bool' \
    'NiriService.isOverviewHotCornerActive(root.outputName, cornerName)' \
    '!root.niriOverviewOwnsCorner("bottomLeft")' \
    '!root.niriOverviewOwnsCorner("bottomRight")' \
    'readonly property string cornerName: atBottom' \
    '!root.niriOverviewOwnsCorner(corner.cornerName)'; do
    grep -Fq "$token" "$corners" || { printf 'FAIL: Abyss corner Niri Overview priority missing: %s\n' "$token" >&2; exit 1; }
done
# Check capabilities rather than freezing the spelling/order of the catalog.
node - "$presentation" <<'JS'
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const policy=vm.createContext({});vm.runInContext(fs.readFileSync(process.argv[2],'utf8'),policy);
for(const kind of ['osd','volume','brightness','mic','mediaOsd','keyboardLayout','voiceSearch',
                    'quickNotes','notificationCenter','notifications','wifi','bluetooth','launcher'])
  assert.equal(policy.canJoin(kind),true,'corner join capability: '+kind);
assert.equal(policy.canJoin('utilities'),false,'Utilities is an input utility surface, not a corner owner');
assert.equal(policy.canJoin('media'),false,'media popup is distinct from media OSD');
assert.equal(policy.canJoin('unknown'),false);
JS
grep -Fq 'visible:Presentation.canJoin(root.kind)' "$positions" \
    || { printf 'FAIL: popup position editor does not expose Join nearby corner for corner/network kinds\n' >&2; exit 1; }
# Popup corner ownership lives in the shared perimeter; the Edit Abyss
# Layout control only independently positions IPC/OSD surfaces.
for token in 'buttonText:"IPC"' 'allowedKinds:["osd","volume","brightness","mic","mediaOsd","keyboardLayout","voiceSearch"]' 'joinedEdge:Presentation.joinedEdge(root.previewKind,'; do
    grep -Fq "$token" "$editor" || { printf 'FAIL: IPC-only edit preview contract missing: %s\n' "$token" >&2; exit 1; }
done
for token in 'readonly property string configuredJoinedEdge:' 'Presentation.joinedEdge(presentationKind,'; do
    grep -Fq "$token" "$perimeter" || { printf 'FAIL: mature StyledPopup join routing missing: %s\n' "$token" >&2; exit 1; }
done
if ! command -v qs >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]]; then printf 'SKIP: Abyss corner content runtime (source lease + Niri hot-corner + Join Edge contracts passed; Quickshell/Wayland unavailable)\n';exit 0;fi
corner_test_root="$(mktemp -d)"
trap 'rm -rf -- "$corner_test_root"' EXIT
for entry in modules services GlobalStates.qml qmldir assets scripts defaults translations; do ln -s "$repo_root/$entry" "$corner_test_root/$entry";done
mkdir -p "$corner_test_root/config/illogical-impulse"
cp "$repo_root/defaults/config.json" "$corner_test_root/config/illogical-impulse/config.json"
cat > "$corner_test_root/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.abyss
import qs.services
ShellRoot {
    id: root
    property int step: 0
    property bool finished: false
    property real notificationHeight: 0
    function check(ok,message): bool {
        if(ok) return true
        console.error("ABYSS_CORNERS_FAIL",message);finished=true;return false
    }
    function find(item,predicate) {
        if(!item) return null
        if(predicate(item)) return item
        for(const child of item.children ?? []) { const match=find(child,predicate);if(match) return match }
        return null
    }
    AbyssSurfaceController { id: liquid;outputName:Quickshell.screens[0].name;presentationItem:scene;popupHost:body;outputWidth:scene.width;outputHeight:scene.height }
    FloatingWindow {
        color: "#111820"
        id: window;visible:true;implicitWidth:1200;implicitHeight:900
        Item {
            id: scene;anchors.fill:parent
            AbyssCorners { id: corners;anchors.fill:parent;controller:liquid;outputName:Quickshell.screens[0].name }
            AbyssBodyHost {
                id: body;anchors.fill:parent;identity:"styledPopup";controller:liquid;edge:"bottom"
                open:liquid.activePopup?.requestedVisible ?? false
                embeddedItem:liquid.activePopup?.contentItem ?? null
                span:(liquid.activePopup?.requestedPopupWidth ?? 420)
                depth:(liquid.activePopup?.requestedPopupHeight ?? 300)
                along:liquid.activePopup===corners.centerPopup ? scene.width-span-16 : 16
                animatePresentation:false;largeSurface:depth>height*.42
            }
        }
    }
    Timer {
        interval:240;running:!root.finished;repeat:true
        onTriggered: {
            if(!Config.ready) return
            if(root.step===0) {
                Config.setNestedValue("panelFamily","abyss")
                Config.setNestedValue("performance.reduceAnimations",true)
                Config.setNestedValue("quickNotes.enable",true)
                Config.setNestedValue("notificationCenter.enable",true)
                GlobalStates.deferredPanelsReady=true
                corners.notesAnchor.containsMouse=true
            } else if(root.step===3) {
                if(!root.check(liquid.activePopup===corners.notesPopup && corners.notesPopup.presentationActive && !corners.notesPopup.active,"Notes joins the field without a native popup")) return
                if(!root.check(root.find(body.contentParent,item=>typeof item.flushPendingSave==="function")!==null,"real Notes editor loads")) return
                if(!root.check(body.inputBounds.width>200 && corners.notesPopup.presentationWindow===window,"content and keyboard use the presentation window")) return
                corners.notesPopup.selectedNotesTab=1
            } else if(root.step===5) {
                if(!root.check(root.find(body.contentParent,item=>item.showAddDialog!==undefined)!==null,"real To-do loads")) return
                corners.notesPopup.selectedMainTab=1
            } else if(root.step===7) {
                if(!root.check(root.find(body.contentParent,item=>item.compactMode===true && item.tabButtonList?.length===3)!==null,"Pomodoro, Timer and Stopwatch modes remain available")) return
                corners.notesAnchor.containsMouse=false
                corners.notesPopup.dismissPresentation()
                GlobalStates.openNotificationCenter(corners.outputName)
            } else if(root.step===9) {
                if(!root.check(liquid.activePopup===corners.centerPopup && corners.centerPopup.presentationActive && !corners.centerPopup.active,"Notifications joins the same field")) return
                if(!root.check(root.find(body.contentParent,item=>typeof item.focusSearch==="function")!==null,"real Notifications content loads")) return
                corners.centerPopup.enterKeyboardMode()
                if(!root.check(corners.centerPopup.keyboardInteraction,"notification search can acquire keyboard focus")) return
                root.notificationHeight=body.inputBounds.height
                corners.centerPopup.selectedTab=1
            } else if(root.step===11) {
                if(!root.check(corners.centerPopup.selectedTab===1 && corners.centerPopup.requestedPopupHeight===560 && body.inputBounds.height===root.notificationHeight,"Activity keeps the exact Notification footprint")) return
                Config.setNestedValue("notificationCenter.popupHeight",260)
                if(!root.check(corners.centerPopup.visibleAppLimit===2,"short custom Activity footprint limits rows to readable space")) return
                corners.centerPopup.dismissPresentation()
                Config.setNestedValue("sidebar.cornerOpen.enable",true)
                Config.setNestedValue("sidebar.cornerOpen.cornerRegionWidth",180)
                Config.setNestedValue("sidebar.cornerOpen.cornerRegionHeight",12)
                // The fixture owns its service instance, not the compositor's
                // config. Exercise both priority states explicitly instead of
                // assuming the owner's top-left hot corner is disabled.
                if (CompositorService.isNiri) {
                    NiriService.overviewHotCornersByOutput = {[corners.outputName]:["topLeft"]}
                    if(!root.check(!corners.leftSidebarCorner.available,"Niri Overview owns its configured physical corner")) return
                    NiriService.overviewHotCornersByOutput = {[corners.outputName]:[]}
                }
                if(!root.check(corners.leftSidebarCorner.available && corners.leftSidebarCorner.width===180 && corners.leftSidebarCorner.height===12,"Sidebar corners inherit mature size settings")) return
                corners.leftSidebarCorner.activate()
                if(!root.check(GlobalStates.sidebarLeftOpen,"mature corner action opens the Sidebar")) return
                GlobalStates.closeSidebarLeft()
                Config.setNestedValue("sidebar.cornerOpen.bottom",true)
                if(!root.check(!corners.leftSidebarCorner.available && !corners.rightSidebarCorner.available,"mature Notes and Notifications retain bottom-corner priority")) return
                corners.blocked=true
                if(!root.check(!corners.notesAvailable && !corners.centerAvailable && body.inputBounds.width===0 && liquid.activePopup===null,"blocked corners and closed bodies release input")) return
                console.info("ABYSS_CORNERS_PASS");root.finished=true;return
            }
            root.step++
        }
    }
}
QML
runtime_status=0
dbus-run-session -- env -u QS_CONFIG_NAME -u QS_CONFIG_PATH -u QS_MANIFEST QT_QPA_PLATFORM=wayland \
 XDG_CONFIG_HOME="$corner_test_root/config" XDG_STATE_HOME="$corner_test_root/state" XDG_CACHE_HOME="$corner_test_root/cache" \
 timeout 15s qs -p "$corner_test_root" --no-color > "$corner_test_root/runtime.log" 2>&1 || runtime_status=$?
if [[ "$runtime_status" != 124 ]] || ! rg -q ABYSS_CORNERS_PASS "$corner_test_root/runtime.log" || rg -q 'ABYSS_CORNERS_FAIL|ReferenceError:|TypeError:|Binding loop|Cannot anchor|Unable to assign|is not a type|Type .* unavailable' "$corner_test_root/runtime.log";then cat "$corner_test_root/runtime.log";exit 1;fi
printf 'PASS: mature corner content, cross-output Quick Notes lease, Niri Overview hot-corner priority, focus and input release\n'
