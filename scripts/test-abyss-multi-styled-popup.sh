#!/usr/bin/env bash
# Real multi-popup ownership: two mature StyledPopup instances share one Abyss
# output field without dismissing/recreating each other.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
body_host="$repo_root/modules/abyss/AbyssBodyHost.qml"
for token in \
    'readonly property var visualPlacement:' \
    'Behavior on visualPlacementInward' \
    'Behavior on visualPlacementSpan' \
    'largeSurface,visualPlacement)'; do
    grep -Fq "$token" "$body_host" \
        || { printf 'FAIL: connected popup placement motion missing: %s\n' "$token" >&2; exit 1; }
done
if ! command -v qs >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    printf 'SKIP: Abyss multi StyledPopup (Quickshell/Wayland unavailable)\n'
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
//@ pragma ShellId alis-abyss-multi-styled-popup-test
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.bar
import qs.modules.abyss

ShellRoot {
    id: root
    property int step: 0
    property bool finished: false
    property bool showA: false
    property bool showB: false
    property var retainedA: null

    function check(ok,message): bool {
        if(ok) return true
        console.error("ABYSS_MULTI_POPUP_FAIL",message)
        finished=true
        return false
    }
    function overlaps(a,b): bool {
        return a.x < b.x+b.width && a.x+a.width > b.x
            && a.y < b.y+b.height && a.y+a.height > b.y
    }

    AbyssSurfaceController {
        id: controller
        presentationItem: scene
        outputWidth: scene.width
        outputHeight: scene.height
        edgeInsets: ({left:16,right:16,top:16,bottom:16})
    }

    FloatingWindow {

        color: "#111820"
        id: window
        visible: true
        implicitWidth: 1200
        implicitHeight: 900

        Item {
            id: scene
            anchors.fill: parent

            MouseArea {
                id: anchorA
                x: 1160
                y: 120
                width: 28
                height: 72
                property var liquidController: controller
                property string attachedEdge: "right"
                property string kind: "clock"
            }
            MouseArea {
                id: anchorB
                x: 1160
                y: 520
                width: 28
                height: 72
                property var liquidController: controller
                property string attachedEdge: "right"
                property string kind: "clock"
            }

            Repeater {
                id: hosts
                model: controller.popupCapacity

                delegate: AbyssBodyHost {
                    id: host
                    required property int index
                    readonly property var popupEntry: controller.popupSlots[index] ?? null
                    readonly property var hostedPopup: popupEntry?.popup ?? null
                    readonly property rect anchorBounds:
                        hostedPopup?._anchorRect(scene.width,scene.height)
                            ?? Qt.rect(0,0,0,0)

                    anchors.fill: parent
                    identity: "styledPopup" + index
                    controller: controller
                    edge: hostedPopup?._attachmentEdge ?? "right"
                    open: hostedPopup?.presentationActive ?? false
                    externalProgress: hostedPopup?.revealProgress ?? 0
                    embeddedItem: hostedPopup?.contentItem ?? null
                    padding: 14
                    span: (embeddedItem?.implicitHeight ?? 280)+padding*2
                    depth: (embeddedItem?.implicitWidth ?? 360)+padding*2
                    along: anchorBounds.y+anchorBounds.height/2-span/2
                    edgeInsets: controller.edgeInsets

                    onPopupEntryChanged: retainedPlacement = null
                    Component.onCompleted: controller.registerPopupHost(index,host)
                    Component.onDestruction: controller.unregisterPopupHost(index,host)
                }
            }
        }
    }

    ClockCalendarPopup {
        id: popupA
        hoverTarget: anchorA
        hoverActivates: false
        alternativeVisibleCondition: root.showA
        keyboardFocus: true
        exclusiveKeyboardFocus: true
        closeOnOutsideClick: true
    }
    ClockCalendarPopup {
        id: popupB
        hoverTarget: anchorB
        hoverActivates: false
        alternativeVisibleCondition: root.showB
        keyboardFocusOnDemand: true
        closeOnOutsideClick: true
    }

    Timer {
        interval: 360
        running: !root.finished
        repeat: true
        onTriggered: {
            if(!Config.ready) return
            if(root.step===0) {
                Config.setNestedValue("panelFamily","abyss")
                root.showA=true
            } else if(root.step===1) {
                if(!root.check(controller.activePopups.length===1
                    && controller.activePopup===popupA,
                    "first mature popup owns one stable slot")) return
                if(!root.check(popupA.presentationActive && !popupA.active
                    && popupA.presentationWindow===window,
                    "first popup uses the shared Abyss field, not a native popup")) return
                if(!root.check(controller.popupFocusOwner===popupA
                    && controller.popupExclusiveFocus
                    && !controller.popupOnDemandFocus,
                    "explicit Exclusive popup owns the shared focus mode while alone")) return
                root.retainedA=popupA.contentItem
                root.showB=true
            } else if(root.step===2) {
                const a=controller.participants["styledPopup0"]?.inputBounds
                const b=controller.participants["styledPopup1"]?.inputBounds
                if(!root.check(controller.activePopups.length===2
                    && controller.activePopup===popupB,
                    "opening a second popup does not dismiss the first")) return
                if(!root.check(popupA.presentationActive && popupB.presentationActive
                    && !popupA.active && !popupB.active,
                    "both mature popup lifecycles remain resident in the field")) return
                if(!root.check(popupA.contentItem===root.retainedA
                    && popupA.contentItem.parent!==popupB.contentItem.parent,
                    "each popup keeps its original content object and a distinct host")) return
                if(!root.check(a && b && a.width>0 && b.width>0 && !root.overlaps(a,b),
                    "allocator gives simultaneous popups separate input/content regions")) return
                if(!root.check(controller.popupFocusOwner===popupB
                    && !controller.popupExclusiveFocus
                    && controller.popupOnDemandFocus,
                    "newer OnDemand popup supersedes an older Exclusive lease without changing ownership")) return
                if(!root.check(controller.popupInputBounds.length===2,
                    "shared output mask receives both popup input regions")) return
                root.showB=false
            } else if(root.step===4) {
                if(!root.check(controller.activePopups.length===1
                    && controller.activePopup===popupA && popupA.presentationActive,
                    "closing newer popup leaves the older popup alive")) return
                if(!root.check(popupA.contentItem===root.retainedA,
                    "older popup content is not recreated after peer close")) return
                if(!root.check(controller.popupFocusOwner===popupA
                    && controller.popupExclusiveFocus
                    && !controller.popupOnDemandFocus,
                    "closing newer popup restores the older explicit Exclusive lease")) return
                root.showA=false
            } else if(root.step===6) {
                if(!root.check(controller.activePopups.length===0
                    && controller.popupInputBounds.length===0,
                    "final close releases all popup slots and input")) return
                controller.presented=false
                console.info("ABYSS_MULTI_POPUP_PASS")
                root.finished=true
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
if [[ "$status" != 124 ]] || ! rg -q ABYSS_MULTI_POPUP_PASS "$test_root/runtime.log" \
        || rg -q 'ABYSS_MULTI_POPUP_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign|is not a type' "$test_root/runtime.log"; then
    cat "$test_root/runtime.log"
    exit 1
fi
printf 'PASS: simultaneous StyledPopup ownership, newest-focus arbitration/restoration, non-overlap, input aggregation and independent close\n'
