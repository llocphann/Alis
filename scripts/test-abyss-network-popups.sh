#!/usr/bin/env bash
# Rehost real network forms without opening another dialog or touching a radio.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
layout="$repo_root/modules/abyss/looks/AbyssLayout.js"
module="$repo_root/modules/abyss/bar/AbyssBarModule.qml"
tray="$repo_root/modules/bar/SysTray.qml"
status_indicators="$repo_root/modules/bar/BarStatusIndicators.qml"
migration="$repo_root/sdata/migrations/053-retire-abyss-connectivity-modules.sh"

for token in '"wifi"' '"bluetooth"'; do
    grep -Fq "$token" "$layout" && {
        printf 'FAIL: retired connectivity Edge module remains in Abyss catalog: %s\n' "$token" >&2
        exit 1
    }
done
grep -Fq 'MIGRATION_ID="053-retire-abyss-connectivity-modules"' "$migration"     || { printf 'FAIL: retired connectivity module migration missing\n' >&2; exit 1; }
grep -Fq 'property bool autoDismissOnIdle: true' "$repo_root/modules/abyss/content/AbyssNetworkPopup.qml" \
    || { printf 'FAIL: network popup idle-dismiss contract missing\n' >&2; exit 1; }
grep -Fq 'property bool triggerHovered: false' "$repo_root/modules/abyss/content/AbyssNetworkPopup.qml" \
    || { printf 'FAIL: network popup cannot retain while the tray trigger is hovered\n' >&2; exit 1; }
grep -Fq 'signal connectivityHoverChanged(string kind, bool hovered)' "$repo_root/modules/bar/BarStatusIndicators.qml" \
    || { printf 'FAIL: connectivity trigger hover state is not exported\n' >&2; exit 1; }
grep -Fq 'triggerHovered: root.participant?.triggerHovered ?? false' "$repo_root/modules/abyss/content/AbyssPopupContent.qml" \
    || { printf 'FAIL: popup host hover state is not bound into network content\n' >&2; exit 1; }
grep -Fq '["wifi","bluetooth","utilities","launcher","dockAppMenu"].includes(root.kind)' "$repo_root/modules/abyss/content/AbyssPopupContent.qml" \
    || { printf 'FAIL: network popup no longer shares the generic hover/focus dismissal lease\n' >&2; exit 1; }
grep -Fq 'showEmbeddedFooter: false' "$repo_root/modules/abyss/content/AbyssNetworkPopup.qml" \
    || { printf 'FAIL: System Tray network popup still exposes mature footer actions\n' >&2; exit 1; }
grep -Fq 'glyph: "settings"' "$repo_root/modules/abyss/content/AbyssNetworkPopup.qml" \
    || { printf 'FAIL: network Details action was not promoted to a compact header icon\n' >&2; exit 1; }
grep -Fq 'visible:Presentation.canJoin(root.kind)' "$repo_root/modules/abyss/settings/AbyssPositionSettings.qml" \
    || { printf 'FAIL: Wi-Fi/Bluetooth Join Edge option is not exposed in Edit Abyss Layout\n' >&2; exit 1; }
grep -Fq 'joinedEdge: Presentation.joinedEdge(root.activeKind,' "$repo_root/modules/abyss/AbyssGenericPopupPresenter.qml" \
    || { printf 'FAIL: connected Wi-Fi/Bluetooth host does not consume Join Edge position state\n' >&2; exit 1; }

migration_tmp="$(mktemp -d)"
trap 'rm -rf -- "$migration_tmp"' EXIT
mkdir -p "$migration_tmp/alis"
cat > "$migration_tmp/alis/config.json" <<'JSON'
{"abyss":{"modules":{"placements":[{"id":"wifi","kind":"wifi"},{"id":"clock","kind":"clock"},{"id":"bluetooth","kind":"bluetooth"}],"outputLayouts":[{"outputName":"A","placements":[{"id":"bt-a","kind":"bluetooth"},{"id":"media","kind":"media"}]}]}}}
JSON
(
    export XDG_CONFIG_HOME="$migration_tmp"
    source "$migration"
    migration_check || { printf 'FAIL: connectivity migration did not detect retired modules\n' >&2; exit 1; }
    migration_apply || { printf 'FAIL: connectivity migration apply failed\n' >&2; exit 1; }
    migration_check && { printf 'FAIL: connectivity migration is not idempotent\n' >&2; exit 1; }
    jq -e '(.abyss.modules.placements | map(.kind)) == ["clock"]
        and (.abyss.modules.outputLayouts[0].placements | map(.kind)) == ["media"]'         "$XDG_CONFIG_HOME/alis/config.json" >/dev/null         || { printf 'FAIL: connectivity migration removed/preserved wrong placements\n' >&2; exit 1; }
)

if ! command -v qs >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    printf 'SKIP: Abyss network popup runtime (Quickshell/Wayland unavailable)\n'
    exit 0
fi
network_test_root="$(mktemp -d)"
trap 'rm -rf -- "$network_test_root" "$migration_tmp"' EXIT
for entry in modules services GlobalStates.qml qmldir assets scripts defaults translations; do
    ln -s "$repo_root/$entry" "$network_test_root/$entry"
done
mkdir -p "$network_test_root/config/illogical-impulse"
cp "$repo_root/defaults/config.json" "$network_test_root/config/illogical-impulse/config.json"
cat > "$network_test_root/shell.qml" <<'QML'
//@ pragma ShellId alis-abyss-network-popup-test
import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.abyss
import qs.modules.abyss.bar
import qs.modules.abyss.content
ShellRoot {
    id: root
    property int step: 0
    property bool finished: false
    property int dismissed: 0
    property int requests: 0
    function check(ok,message): bool {
        if(ok) return true
        console.error("NETWORK_POPUP_FAIL",message);root.finished=true;return false
    }
    function visibleText(item,expected) {
        if(item?.text===expected && item.visible && item.opacity>0 && item.width>0 && item.height>0 && (item.color?.a ?? 1)>0) return true
        return Array.from(item?.children ?? []).some(child=>root.visibleText(child,expected))
    }
    AbyssSurfaceController {
        id: controller; outputName: "network-test"
        outputWidth: 960; outputHeight: 720
    }
    FloatingWindow {
        color: "#111820"
        visible: true; implicitWidth: 960; implicitHeight: 720
        Item {
            width:960;height:720
        AbyssBodyHost {
            id: body; anchors.fill: parent
            property bool triggerHovered: true
            identity: "networkPopup"; outputName: "network-test"; controller: controller
            edgeInsets: controller.edgeInsets
            edge: "top"; along: 100; span: 288; depth: 358
            stableContentSize: true; largeSurface: true
            source: Qt.resolvedUrl("modules/abyss/content/AbyssPopupContent.qml")
            contentKind: "wifi"
            onCloseRequested: { root.dismissed++;open=false }
        }
        AbyssBarModule {
            id: trayModule; width: 160; height: 32; outputName: "network-test"; kind: "tray"
            onHoverRequest: kind=> { if(["wifi","bluetooth"].includes(kind)) root.requests++ }
        }
        }
    }
    Timer {
        interval: 350; running: !root.finished; repeat: true
        onTriggered: {
            if(!Config.ready) return
            if(root.step===0) {
                Config.setNestedValue("panelFamily","abyss")
                Config.setNestedValue("performance.reduceAnimations",true)
                GlobalStates.deferredPanelsReady=true;body.open=true
            } else if(root.step===1 || root.step===3) {
                const popup=body.contentItem.item,network=popup?.feature,form=network?.dialog
                if(network) network.autoDismissOnIdle=false
                if(!root.check(body.ready && body.inputBounds.width>0 && popup.desiredWidth===260 && popup.desiredHeight===330,"bounded network popup content loads")) return
                if(!root.check(form?.show && form.effectiveEmbedded && !form.liquidHosted && controller.activeDialog===null,"mature form reuses the popup rather than acquiring a dialog host")) return
                if(!root.check(form.showEmbeddedFooter===false,"System Tray embedding removes the Done/Details footer")) return
                if(!root.check(root.visibleText(form,root.step===1 ? "Connect to Wi-Fi" : "Bluetooth devices"),"mature connection title is visible with nonzero text bounds and alpha")) return
                if(!root.check(trayModule.feature && trayModule.naturalSpan>=0,"System Tray module is usable")) return
                trayModule.feature.hoverPopupRequested(root.step===1 ? "wifi" : "bluetooth")
                if(!root.check(root.requests===(root.step===1 ? 1 : 2),"System Tray hover sends the matching popup request")) return
                if(root.step===1) { body.contentKind="bluetooth" }
                else { form.dismiss() }
            } else if(root.step===2) {
                const network=body.contentItem.item?.feature
                if(network) network.autoDismissOnIdle=false
            } else if(root.step===4) {
                if(!root.check(root.dismissed===1 && !body.open && body.inputBounds.width===0,"dismissal releases the existing host and input")) return
                body.edge="right";body.span=358;body.depth=288;body.open=true
            } else if(root.step===5) {
                if(!root.check(body.inputBounds.x>=0 && body.inputBounds.y>=0 && body.inputBounds.x+body.inputBounds.width<=960 && body.inputBounds.y+body.inputBounds.height<=720,"popup can move to a vertical Edge")) return
                body.contentItem.item.enabled=false
                if(!root.check(!body.contentItem.item.feature.enabled,"layout preview disables connection controls")) return
                body.open=false
            } else if(root.step===6) {
                if(!root.check(!body.ready && controller.records.length===0,"closed popup unloads and releases the field")) return
                console.info("NETWORK_POPUP_PASS");root.finished=true
            }
            root.step++
        }
    }
}
QML
status=0
dbus-run-session -- env -u QS_CONFIG_PATH -u QS_CONFIG_NAME -u QS_MANIFEST QT_QPA_PLATFORM=wayland \
    XDG_CONFIG_HOME="$network_test_root/config" XDG_STATE_HOME="$network_test_root/state" \
    XDG_CACHE_HOME="$network_test_root/cache" timeout 20s qs -p "$network_test_root" --no-color \
    > "$network_test_root/runtime.log" 2>&1 || status=$?
if [[ "$status" != 124 ]] || ! rg -q 'NETWORK_POPUP_PASS' "$network_test_root/runtime.log" \
        || rg -q 'NETWORK_POPUP_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign|is not a type' "$network_test_root/runtime.log"; then
    cat "$network_test_root/runtime.log"; exit 1
fi
printf 'PASS: Wi-Fi/Bluetooth compact actions, idle-dismiss contract, System Tray hover routing, retired Edge modules and input release\n'
