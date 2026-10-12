#!/usr/bin/env bash
# Exercise editor draft/cancel/save against actual QML Config and placement bindings.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]]; then printf 'SKIP: Abyss editor (Quickshell unavailable)\n'; exit 0; fi
abyss_editor_test="$(mktemp -d)"
trap 'rm -rf -- "$abyss_editor_test"' EXIT
for entry in modules services GlobalStates.qml qmldir assets scripts defaults translations; do ln -s "$repo_root/$entry" "$abyss_editor_test/$entry"; done
mkdir -p "$abyss_editor_test/config/illogical-impulse"
cp "$repo_root/defaults/config.json" "$abyss_editor_test/config/illogical-impulse/config.json"
cat > "$abyss_editor_test/shell.qml" <<'QML'
import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.abyss
import qs.modules.abyss.bar
import "modules/abyss/looks/AbyssPresentation.js" as Presentation
ShellRoot {
    id: root
    property int step: 0
    property bool finished: false
    property bool executing: false
    property real smallOutputHeight: 0
    property string beforePositions: ""
    property string before: ""
    property var originalModule: null
    function check(ok,message): bool {
        if(ok) return true
        console.error("EDITOR_FAIL",message);root.finished=true;return false
    }
    AbyssSurfaceController { id: liquid }
    TestCase { id:driver;when:false;optional:true }
    function settleControls(): bool {
        // Relocation is intentionally debounced for 90 ms. Let it complete,
        // then wait for real layout polish before deriving a pointer position.
        driver.wait(120)
        if(!editor.expandedControls) {
            driver.mouseClick(driver.findChild(editor,"abyssEditorOptions"))
            driver.wait(120)
        }
        return root.check(driver.waitForPolish(editor.Window.window,3000),"editor controls did not finish layout")
    }
    function clickControl(item): bool {
        let viewport=item.parent
        while(viewport && viewport.contentHeight===undefined) viewport=viewport.parent
        if(!root.check(!!viewport,"editor control has a real scroll viewport")) return false
        const contentPoint=item.mapToItem(viewport.contentItem,0,0)
        viewport.contentY=Math.max(0,Math.min(viewport.contentHeight-viewport.height,
            contentPoint.y-viewport.height/2))
        driver.wait(80)
        const point=item.mapToItem(viewport,0,0)
        if(!root.check(point.x>=-.01 && point.y>=-.01
            && point.x+item.width<=viewport.width+.01
            && point.y+item.height<=viewport.height+.01,
            "editor control is fully visible inside its input clip "+JSON.stringify({step:root.step,
                text:item.text,edge:editor.toolbarEdge,x:point.x,y:point.y,width:item.width,height:item.height,
                viewportWidth:viewport.width,viewportHeight:viewport.height,contentY:viewport.contentY}))) return false
        driver.mouseClick(item)
        return true
    }
    FloatingWindow {
        color: "#111820"
        visible: true;implicitWidth:1000;implicitHeight:700
        Item {
            width:parent.width
            height:root.smallOutputHeight>0 ? root.smallOutputHeight : parent.height
            AbyssBar {
                id: layer;anchors.fill:parent;outputName:"A";edge:"top"
                editing: editor.visible;draftPlacements: editor.visible?editor.draft:null
                draftOptions: editor.visible?editor.draftOptions:null
            }
            AbyssEdgeEditor {
                id: editor;anchors.fill:parent;outputName:"A";moduleLayer:layer;controller:liquid
                visible: GlobalStates.abyssEditing
            }
        }
    }
    Timer {
        interval:200;running:!root.finished;repeat:true
        onTriggered: {
            if(!Config.ready || root.executing) return
            root.executing=true
            if(root.step===0) {
                Config.setNestedValue("panelFamily","abyss")
                // Draft/input contract: toolbar motion has separate coverage.
                // Keep the pointer target stationary while its layout changes.
                Config.setNestedValue("performance.reduceAnimations",true)
                GlobalStates.deferredPanelsReady=true
                Config.setNestedValue("abyss.modules.configured",true)
                Config.setNestedValue("abyss.modules.placements",[{id:"clock",kind:"clock",edge:"top",position:.4}])
                Config.setNestedValue("abyss.modules.outputLayouts",[{outputName:"B",placements:[],edgeJoinModules:{left:true}}])
                root.before=JSON.stringify(Config.options.abyss.modules.placements)
                GlobalStates.abyssEditing=true
            }
            if(root.step===1) {
                root.originalModule=layer.itemForId("clock")
                if(!root.check(root.originalModule!==null,"mature module exists before drag")) return
                editor.moduleScale=1.2
                for(const edge of ["top","right","bottom","left"]) {
                    const x=edge==="left" ? 10 : edge==="right" ? editor.width-10 : editor.width/2
                    const y=edge==="top" ? 10 : edge==="bottom" ? editor.height-10 : editor.height/2
                    editor.move("clock",x,y,false)
                    editor.edgeSizes=Object.assign({},editor.edgeSizes,{[edge]:1.4})
                    editor.singleModuleExpansion=Object.assign({},editor.singleModuleExpansion,{[edge]:"local"})
                    const record=layer.layoutRecords[0]
                    const cross=["top","bottom"].includes(edge) ? record.content.height : record.content.width
                    if(!root.check(Math.abs(cross-32*Appearance.fontSizeScale*1.4*1.2)<.1,"shared size and overall scale update the actual "+edge+" module")) return
                    if(!root.check(layer.deformations.length===1 && layer.deformations[0].edge===edge,"single-module local surface follows "+edge)) return
                    editor.edgeThicknesses=Object.assign({},editor.edgeThicknesses,{[edge]:32})
                    const thickRecord=layer.layoutRecords[0]
                    const thickCross=["top","bottom"].includes(edge) ? thickRecord.content.height : thickRecord.content.width
                    if(!root.check(Math.abs(thickCross-cross*2)<.1 && editor.edgeInsets[edge]===32,"physical px thickness updates the actual "+edge+" module and resting Edge")) return
                    editor.edgeWidthAffectsModules=Object.assign({},editor.edgeWidthAffectsModules,{[edge]:false})
                    editor.edgeThicknesses=Object.assign({},editor.edgeThicknesses,{[edge]:0})
                    editor.move("clock",edge==="left"?10:edge==="right"?editor.width-10:40,edge==="top"?10:edge==="bottom"?editor.height-10:40,false)
                    if(!root.settleControls()) return
                    const corner=driver.findChild(editor,"abyssModuleJoinCorner")
                    if(!root.check(corner?.enabled && !!editor.nearbyCorner,"nearest module exposes corner control on "+edge)) return
                    if(!root.clickControl(corner)) return
                    if(!root.check(editor.selected.joinCorner && layer.deformations[0].along===0,"corner checkbox extends the actual local paint on "+edge)) return
                    if(!root.clickControl(corner)) return
                    const rounding=driver.findChild(editor,"abyssModuleRounding")
                    if(!root.check(rounding?.visible,"edge-only policy exposes rounding on "+edge)) return
                    rounding.value=0;rounding.moved()
                    if(!root.check(editor.edgeModuleRadii[edge]===0 && layer.deformations[0].radius===0,"rounding slider propagates square field geometry on "+edge)) return
                    editor.edgeModuleRadii=Object.assign({},editor.edgeModuleRadii,{[edge]:32})
                    if(!root.check(layer.deformations[0].radius===32,"per-Edge rounding updates local record")) return
                    editor.move("clock",x,y,false)
                    if(!root.check(editor.edgeInsets[edge]===0 && layer.layoutRecords.length===1 && layer.deformations.length===1,"zero bare "+edge+" retains independent module and backing")) return
                    editor.add("battery")
                    if(!root.settleControls()) return
                    const join=driver.findChild(editor,"abyssJoinNearbyModules")
                    const beforeJoin=layer.itemForId("clock")
                    if(!root.check(join?.visible && layer.deformations.length===2,"edge-only width exposes the join checkbox on "+edge)) return
                    if(!root.clickControl(join)) return
                    if(!root.check(editor.edgeJoinModules[edge] && layer.deformations.length===1 && layer.layoutRecords.length===2 && layer.itemForId("clock")===beforeJoin,"actual checkbox joins local paint while preserving modules on "+edge)) return
                    if(!root.clickControl(join)) return
                    if(!root.check(!editor.edgeJoinModules[edge] && layer.deformations.length===2,"unchecking restores individual backing")) return
                    editor.draft=editor.draft.filter(p=>p.id==="clock");editor.selectedId="clock";editor.refreshHandles()
                    root.originalModule=layer.itemForId("clock")
                    editor.edgeThicknesses=Object.assign({},editor.edgeThicknesses,{[edge]:32})
                    editor.edgeWidthAffectsModules=Object.assign({},editor.edgeWidthAffectsModules,{[edge]:true})
                    if(!root.check((Config.options.abyss.modules.edgeThicknesses[edge] ?? -1)===-1,"thickness slider stays in draft")) return
                }
                editor.move("clock",editor.width*.6,10)
                editor.move("clock",editor.width-10,editor.height/2)
                if(!root.check(layer.itemForId("clock")===root.originalModule,"drag preserves the mature module instance")) return
                if(!root.check(layer.layoutRecords[0].edge==="right","cross edge live placement")) return
                editor.move("clock",editor.width-10,40);editor.change("joinCorner",true)
                if(!root.check(layer.children.find(item=>item.kind==="clock")?.popupJoinedEdge==="top","near-corner draft reaches the actual module popup anchor")) return
                if(!root.check(JSON.stringify(Config.options.abyss.modules.placements)===root.before,"drag writes only draft")) return
                editor.finish(false)
            }
            if(root.step===2) {
                if(!root.check(layer.layoutRecords[0].edge==="top","Cancel restores saved presentation")) return
                if(!root.check(!layer.placements[0].joinCorner,"Cancel restores unchecked corner preference")) return
                if(!root.check(!layer.layoutOptions.edgeJoinModules.right,"Cancel restores saved module-join preference")) return
                if(!root.check(layer.layoutOptions.size===1 && layer.deformations.length===0 && editor.edgeInsets.top===48 && layer.layoutOptions.edgeThicknesses.right===-1,"Cancel restores saved scale, thickness and full Edge presentation")) return
                GlobalStates.abyssEditing=true
            }
            if(root.step===3) {
                editor.move("clock",editor.width-10,editor.height/2);editor.gap=17
                editor.edgeSizes={top:1.1,right:1.25,bottom:1,left:1}
                editor.edgeThicknesses={top:-1,right:24,bottom:-1,left:-1}
                editor.moduleScale=1.3;editor.singleModuleExpansion={right:"local"}
                editor.edgeWidthAffectsModules=Object.assign({},editor.edgeWidthAffectsModules,{right:false})
                editor.edgeJoinModules=Object.assign({},editor.edgeJoinModules,{right:true})
                editor.edgeModuleRadii=Object.assign({},editor.edgeModuleRadii,{right:28})
                editor.change("alignment","center");editor.change("joinCorner",true)
                if(!root.check(editor.selected.joinCorner,"corner option belongs to draft module")) return
                editor.add("media");editor.change("enabled",false)
                editor.finish(true)
            }
            if(root.step===4) {
                const profiles=Array.from(Config.options.abyss.modules.outputLayouts)
                if(!root.check(profiles.length===2 && profiles[0].outputName==="B","Done merges latest output profiles")) return
                if(!root.check(profiles[0].edgeJoinModules.left && profiles[1].edgeJoinModules.right && layer.layoutOptions.edgeJoinModules.right,"Done scopes module joining to this output and preserves another")) return
                if(!root.check(profiles[1].edgeModuleRadii.right===28 && layer.layoutOptions.edgeModuleRadii.right===28,"Done saves this output's module curvature")) return
                if(!root.check(layer.layoutRecords[0].edge==="right" && profiles[1].gap===17 && !profiles[1].placements[1].enabled,"persisted normalized edge, gap and disable")) return
                if(!root.check(profiles[1].edgeThicknesses.right===24 && editor.edgeInsets.right===24,"Done preserves pixel thickness scoped to this output")) return
                if(!root.check(profiles[1].edgeSizes.right===1.25 && !profiles[1].placements[0].customSize && profiles[1].placements[0].alignment==="center" && profiles[1].placements[0].joinCorner,"Done persists shared edge sizes and grouped alignment")) return
                if(!root.check(profiles[1].size===1.3 && profiles[1].singleModuleExpansion.right==="local" && layer.layoutOptions.size===1.3 && layer.deformations.length===1,"Done keeps scale and local expansion scoped to this output")) return
                GlobalStates.abyssEditing=true
                editor.editingPopups=true
                root.beforePositions=JSON.stringify(Config.options.abyss.positions)
            }
            if(root.step===6) {
                if(!root.check(editor.previewHost.ready && editor.previewHost.contentItem.item.kind==="volume" && !editor.previewHost.contentItem.item.enabled,"actual IPC layout loads with safe preview controls")) return
                const module=layer.layoutRecords[0].content,preview=editor.previewHost.record.content
                if(!root.check(preview.x+preview.width<=module.x || module.x+module.width<=preview.x || preview.y+preview.height<=module.y || module.y+module.height<=preview.y,"IPC preview clears modules on another Edge")) return
                editor.movePreview(editor.width-8,editor.height*.5)
                if(!root.check(editor.previewHost.edge==="right" && editor.previewPosition.alignment==="custom" && JSON.stringify(Config.options.abyss.positions)===root.beforePositions,"preview drag updates only an output-local draft")) return
                const moved=editor.previewHost.record.content
                if(!root.check(moved.x+moved.width<=module.x,"IPC preview clears the local module on its source Edge")) return
                editor.movePreview(8,80)
                const joined=Object.assign({},editor.previewPosition,{joinCorner:true})
                editor.editPosition(Presentation.save(editor.draftPositions,"volume","A",joined),"volume","A",joined)
                if(!root.check(editor.previewHost.joinedEdge==="top" && editor.previewHost.record.joinedEdge==="top" && editor.previewHost.record.surface.y===-50,"IPC draft joins the adjacent physical Edge in the shared geometry")) return
                editor.movePreview(8,editor.height/2)
                if(!root.check(editor.previewHost.joinedEdge==="" && editor.previewPosition.joinCorner,"moving away suspends the connector without losing its preference")) return
                if(!root.check(JSON.stringify(Config.options.abyss.positions)===root.beforePositions,"IPC join remains draft-only")) return
                editor.finish(false)
            }
            if(root.step===7) {
                if(!root.check(JSON.stringify(Config.options.abyss.positions)===root.beforePositions && editor.previewHost.inputBounds.width===0,"Cancel discards positions and releases preview input")) return
                GlobalStates.abyssEditing=true;editor.editingPopups=true
                editor.movePreview(editor.width-80,8)
                const joined=Object.assign({},editor.previewPosition,{joinCorner:true})
                editor.editPosition(Presentation.save(editor.draftPositions,"volume","A",joined),"volume","A",joined)
                Config.setNestedValue("abyss.positions",[{kind:"clock",outputName:"B",edge:"left",alignment:"end"}])
                editor.finish(true)
            }
            if(root.step===9) {
                const positions=Array.from(Config.options.abyss.positions)
                if(!root.check(positions.length===2 && positions.some(p=>p.kind==="clock" && p.outputName==="B" && p.edge==="left") && positions.some(p=>p.kind==="volume" && p.outputName==="A" && p.edge==="top" && p.alignment==="custom" && p.joinCorner),"Done merges position and join edits into latest config without overwriting another output")) return
                root.smallOutputHeight=360
                GlobalStates.abyssEditing=true
                editor.move("clock",editor.width-10,40,false)
                editor.change("joinCorner",false)
            }
            if(root.step===11) {
                if(!root.settleControls()) return
                const corner=driver.findChild(editor,"abyssModuleJoinCorner")
                let viewport=corner.parent
                while(viewport && viewport.contentHeight===undefined) viewport=viewport.parent
                if(!root.check(viewport.contentHeight>viewport.height && viewport.interactive,
                    "small horizontal output retains access to overflow controls")) return
                driver.mouseWheel(viewport,viewport.width/2,viewport.height/2,0,-1200)
                driver.wait(120)
                // A wheel scroll can retain a kinetic grab; a press during it
                // stops the flick instead of activating the child checkbox.
                for(let n=0;viewport.moving && n<20;++n) driver.wait(100)
                if(!root.check(!viewport.moving,"small-output scrolling settles")) return
                if(!root.clickControl(corner)) return
                if(!root.check(editor.selected.joinCorner && layer.deformations[0].along===0,
                    "small output accepts a real corner-control click after scrolling")) return
                editor.finish(false)
                console.info("EDITOR_PASS");root.finished=true
            }
            root.step++
            root.executing=false
        }
    }
}
QML
status=0
python3 - "$repo_root" "$abyss_editor_test" > "$abyss_editor_test/runtime.log" 2>&1 <<'PY' || status=$?
import sys
from pathlib import Path
sys.path.insert(0,str(Path(sys.argv[1])/"scripts"))
from native_test_session import private_wayland,run_qs
folder=Path(sys.argv[2])
with private_wayland(folder) as env:
    if env is None:
        print("SKIP: Abyss editor requires private Niri")
        raise SystemExit(77)
    result=run_qs(folder,env,timeout=45)
    print(result.stdout)
    raise SystemExit(result.returncode)
PY
if [[ "$status" == 77 ]];then cat "$abyss_editor_test/runtime.log";exit 0;fi
if [[ "$status" != 124 ]] || ! rg -q EDITOR_PASS "$abyss_editor_test/runtime.log" || rg -q 'EDITOR_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign|is not a type' "$abyss_editor_test/runtime.log";then cat "$abyss_editor_test/runtime.log";exit 1;fi
printf 'PASS: four-edge visible controls, small-output wheel/click input, module identity, popup/IPC drafts, Cancel, latest-config merge and output isolation\n'
