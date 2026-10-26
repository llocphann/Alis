#!/usr/bin/env bash
# Exercise actual screen captures and process cancellation without hardware writes.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null || ! command -v grim >/dev/null || ! command -v magick >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    printf 'SKIP: anti-flashbang capture runtime (Quickshell/Wayland/grim/magick unavailable)\n'
    exit 0
fi
sampler_test_root="$(mktemp -d)"
trap 'rm -rf -- "$sampler_test_root"' EXIT
for entry in modules services GlobalStates.qml qmldir assets scripts defaults translations; do
    ln -s "$repo_root/$entry" "$sampler_test_root/$entry"
done
mkdir -p "$sampler_test_root/config/illogical-impulse"
cp "$repo_root/defaults/config.json" "$sampler_test_root/config/illogical-impulse/config.json"
cat > "$sampler_test_root/shell.qml" <<'QML'
//@ pragma ShellId alis-anti-flashbang-sampler-test
import QtQuick
import Quickshell
import qs.services
ShellRoot {
    id: root
    property int stage: 0
    property int ticks: 0
    property bool finished: false
    property real bright: 0
    property int oldSuccesses: 0
    property int oldFailures: 0
    function check(ok,message): bool {
        if(ok) return true
        console.error("ANTI_CAPTURE_FAIL",message,"stage",stage,"samples",sampler.successes,"errors",sampler.failures,"lightness",sampler.lastLightness)
        finished=true;return false
    }
    function captureFixture(nextStage): void {
        // A floating test window need not cover the live output: other desktop
        // work can occlude it. Capture its real Qt pixels for the white/dark
        // sensitivity oracle, while retaining the production grim probe first.
        surface.grabToImage(result => {
            if(!root.check(result.saveToFile(Quickshell.shellPath("fixture.png")),"controlled framebuffer capture saved")) return
            root.stage=nextStage;sampler.active=true
        })
    }
    FloatingWindow {
        id: win;visible: true;implicitWidth: 1000;implicitHeight: 700
        Rectangle { id: surface;anchors.fill: parent;color: "white" }
    }
    AntiFlashbangSampler {
        id: sampler;outputName: win.screen?.name ?? "";sampleInterval: 250
        timeoutMs: 200
    }
    Timer {
        interval: 100;repeat: true;running: !root.finished
        onTriggered: {
            root.ticks++
            if(root.ticks>140) { root.check(false,"runtime deadline");return }
            if(root.stage===0 && sampler.outputName) {
                sampler.timeoutMs=1200;sampler.active=true;root.stage=1
            } else if(root.stage===1 && sampler.successes>=2) {
                if(!root.check(Number.isFinite(sampler.lastLightness)&&sampler.lastLightness>0,"real reduced-resolution captures are finite")) return
                sampler.active=false;root.oldSuccesses=sampler.successes;root.stage=10
                sampler.captureCommand=["/bin/bash","-o","pipefail","-c",
                    "magick \"$1\" -resize 10% -colorspace Gray -format '%[fx:mean*100]' info:",
                    "_",Quickshell.shellPath("fixture.png")]
                root.captureFixture(11)
            } else if(root.stage===11 && sampler.successes>=root.oldSuccesses+2) {
                if(!root.check(sampler.lastLightness>98,"controlled white frame is measured")) return
                root.bright=sampler.lastLightness;root.oldSuccesses=sampler.successes
                sampler.active=false;root.stage=10;surface.color="#080808";root.captureFixture(2)
            } else if(root.stage===2 && sampler.successes>=root.oldSuccesses+2) {
                if(!root.check(sampler.lastLightness<root.bright-1,"periodic sampling follows in-app content without a focus event")) return
                sampler.active=false;root.oldSuccesses=sampler.successes;root.ticks=0;root.stage=3
            } else if(root.stage===3 && root.ticks>=6) {
                if(!root.check(!sampler.capturing && sampler.successes===root.oldSuccesses,"inactive sampler stops capture and periodic work")) return
                sampler.captureCommand=["/bin/bash","-c","printf invalid"]
                root.oldFailures=sampler.failures;sampler.active=true;root.stage=4
            } else if(root.stage===4 && sampler.failures>root.oldFailures) {
                if(!root.check(sampler.successes===root.oldSuccesses && !Number.isFinite(sampler.lastLightness),"malformed output never becomes a sample")) return
                sampler.active=false
                sampler.captureCommand=["/bin/bash","-c","sleep .5; printf 75"]
                sampler.active=true;root.stage=5
            } else if(root.stage===5 && sampler.capturing) {
                for(let i=0;i<40;i++) sampler.request()
                sampler.active=false;root.ticks=0;root.stage=6
            } else if(root.stage===6 && root.ticks>=7) {
                if(!root.check(sampler.successes===root.oldSuccesses && !sampler.capturing,"disable cancels coalesced requests and rejects late results")) return
                sampler.captureCommand=["timeout","--kill-after=0.1s","2s","/bin/bash","-c","sleep 5;printf 99"]
                sampler.timeoutMs=150;root.oldFailures=sampler.failures
                sampler.active=true;root.ticks=0;root.stage=7
            } else if(root.stage===7 && sampler.failures>root.oldFailures) {
                if(!root.check(root.ticks<6 && !sampler.capturing && sampler.successes===root.oldSuccesses,"watchdog terminates a stuck capture without publishing")) return
                sampler.active=false
                sampler.captureCommand=["/bin/bash","-c","sleep .3;printf 75"]
                sampler.active=true;root.stage=8
            } else if(root.stage===8 && sampler.capturing) {
                sampler.active=false
                sampler.captureCommand=["/bin/bash","-c","printf 23"]
                sampler.active=true;root.stage=9
            } else if(root.stage===9 && sampler.successes>root.oldSuccesses) {
                if(!root.check(sampler.lastLightness===23,"fast reactivation cannot publish the canceled generation")) return
                sampler.active=false
                console.info("ANTI_CAPTURE_PASS", "white",root.bright,"dark",surface.color,"samples",sampler.successes,"errors",sampler.failures)
                root.finished=true
            }
        }
    }
}
QML
status=0
env -u QS_CONFIG_PATH -u QS_CONFIG_NAME -u QS_MANIFEST QT_QPA_PLATFORM=wayland \
    XDG_CONFIG_HOME="$sampler_test_root/config" XDG_STATE_HOME="$sampler_test_root/state" \
    XDG_CACHE_HOME="$sampler_test_root/cache" timeout 20s qs -p "$sampler_test_root" --no-color \
    > "$sampler_test_root/runtime.log" 2>&1 || status=$?
if [[ "$status" != 124 ]] || ! rg -q ANTI_CAPTURE_PASS "$sampler_test_root/runtime.log" \
        || rg -q 'ANTI_CAPTURE_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign|is not a type' "$sampler_test_root/runtime.log"; then
    cat "$sampler_test_root/runtime.log";exit 1
fi
printf 'PASS: production screencopy probe, controlled white/dark Qt pixel captures, periodic sensitivity, cancellation and watchdog\n'
