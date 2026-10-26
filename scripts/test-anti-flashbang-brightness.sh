#!/usr/bin/env bash
# Integrate the real service/pixel pipeline with isolated fake brightness devices.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null || ! command -v grim >/dev/null || ! command -v magick >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    printf 'SKIP: anti-flashbang brightness integration (desktop capture unavailable)\n';exit 0
fi
brightness_test_root="$(mktemp -d)"
trap 'rm -rf -- "$brightness_test_root"' EXIT
for entry in modules services GlobalStates.qml qmldir assets scripts defaults translations; do
    ln -s "$repo_root/$entry" "$brightness_test_root/$entry"
done
mkdir -p "$brightness_test_root/config/illogical-impulse" "$brightness_test_root/bin"
cp "$repo_root/defaults/config.json" "$brightness_test_root/config/illogical-impulse/config.json"
cat > "$brightness_test_root/bin/brightnessctl" <<'PY'
#!/usr/bin/env python3
import os,sys,json
from pathlib import Path
args=sys.argv[1:]
if '-l' in args: print('test-backlight,backlight,50,50%,100')
elif 'g' in args: print(50)
elif 'm' in args: print(100)
elif 's' in args:
    value=int(args[args.index('s')+1])
    assert 1<=value<=50, 'anti-flashbang must never brighten or corrupt the device value'
    with Path(os.environ['ANTI_TEST_WRITES']).open('a') as file: file.write(str(value)+'\n')
PY
printf '#!/bin/sh\nexit 0\n' > "$brightness_test_root/bin/ddcutil"
# First probe the production compositor capture, then feed real Qt fixture
# pixels through the same PPM/magick service pipeline. A floating white window
# is not a guarantee that the entire owner's output remains white after wake.
real_grim="$(command -v grim)"
cat > "$brightness_test_root/bin/grim" <<'SH'
#!/bin/sh
if [ -f "$ANTI_TEST_FRAME" ]; then
    exec magick "$ANTI_TEST_FRAME" -resize 10% ppm:-
fi
exec "$ANTI_TEST_REAL_GRIM" "$@"
SH
chmod +x "$brightness_test_root/bin/brightnessctl" "$brightness_test_root/bin/ddcutil" "$brightness_test_root/bin/grim"
cat > "$brightness_test_root/shell.qml" <<'QML'
//@ pragma ShellId alis-anti-flashbang-brightness-test
import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
ShellRoot {
    id:root;property int stage:0;property int ticks:0;property bool finished:false
    readonly property var monitor: Brightness.getMonitorForScreen(win.screen)
    function check(ok,message):bool {
        if(ok)return true
        console.error("ANTI_BRIGHTNESS_FAIL",message,"stage",stage,"active",Brightness.antiFlashbangActive,"base",monitor?.brightness,"gain",monitor?.brightnessMultiplier)
        finished=true;return false
    }
    function captureFixture(nextStage, action): void {
        root.stage=10
        const accepted=surface.grabToImage(result=>{
            if(!root.check(result.saveToFile(Quickshell.shellPath("fixture.png")),"controlled framebuffer saved"))return
            if(action)action()
            root.stage=nextStage
        })
        root.check(accepted,"framebuffer capture accepted")
    }
    AntiFlashbangSampler {
        id:probe;outputName:win.screen?.name ?? ""
        active:Config.ready && root.monitor?.ready;sampleInterval:250
    }
    FloatingWindow {
        id:win;visible:true;implicitWidth:1000;implicitHeight:700
        Rectangle {id:surface;anchors.fill:parent;color:"white"}
    }
    Timer {
        interval:100;running:!root.finished;repeat:true
        onTriggered: {
            root.ticks++
            if(root.ticks>150){root.check(false,"integration deadline");return}
            if(root.stage===0 && Config.ready && root.monitor?.ready && probe.successes>=2) {
                if(!root.check(Number.isFinite(probe.lastLightness),"production output capture is finite"))return
                probe.active=false
                Config.setNestedValue("panelFamily","abyss")
                Config.setNestedValue("light.antiFlashbang.darkOnly",false)
                Config.setNestedValue("light.antiFlashbang.sampleInterval",250)
                Config.setNestedValue("light.antiFlashbang.responseMs",40)
                root.captureFixture(1,()=>Config.setNestedValue("light.antiFlashbang.enable",true))
            } else if(root.stage===1 && root.monitor.brightnessMultiplier<.5) {
                if(!root.check(root.monitor.brightness===.5 && root.monitor.multipliedBrightness<.3,"bright content dims without overwriting selected brightness"))return
                surface.color="#080808";root.captureFixture(2,null)
            } else if(root.stage===2 && root.monitor.brightnessMultiplier>.98 && root.monitor.multipliedBrightness>.48) {
                GlobalStates.screenLocked=true;root.stage=3
            } else if(root.stage===3 && !Brightness.antiFlashbangActive) {
                if(!root.check(root.monitor.brightnessMultiplier===1 && root.monitor.brightness===.5,"lock disables sampling and resets gain"))return
                surface.color="white"
                root.captureFixture(4,()=>GlobalStates.screenLocked=false)
            } else if(root.stage===4 && root.monitor.brightnessMultiplier<.5) {
                Brightness.sleepBegin();root.stage=5
            } else if(root.stage===5 && !Brightness.antiFlashbangActive) {
                if(!root.check(root.monitor.brightnessMultiplier===1,"sleep cancels adaptive dimming"))return
                Brightness.restoreAfterWake();root.stage=6
            } else if(root.stage===6 && root.monitor.brightnessMultiplier<.5) {
                Config.setNestedValue("light.antiFlashbang.enable",false);root.stage=7
            } else if(root.stage===7 && root.monitor.multipliedBrightness>.48) {
                if(!root.check(!Brightness.antiFlashbangActive && root.monitor.brightness===.5 && root.monitor.brightnessMultiplier===1,"disable restores the chosen brightness"))return
                console.info("ANTI_BRIGHTNESS_PASS");root.finished=true
            }
        }
    }
}
QML
status=0
env -u QS_CONFIG_PATH -u QS_CONFIG_NAME -u QS_MANIFEST QT_QPA_PLATFORM=wayland \
    PATH="$brightness_test_root/bin:$PATH" ANTI_TEST_WRITES="$brightness_test_root/writes" \
    ANTI_TEST_FRAME="$brightness_test_root/fixture.png" ANTI_TEST_REAL_GRIM="$real_grim" \
    XDG_CONFIG_HOME="$brightness_test_root/config" XDG_STATE_HOME="$brightness_test_root/state" \
    XDG_CACHE_HOME="$brightness_test_root/cache" timeout 20s qs -p "$brightness_test_root" --no-color \
    > "$brightness_test_root/runtime.log" 2>&1 || status=$?
if [[ "$status" != 124 ]] || ! rg -q ANTI_BRIGHTNESS_PASS "$brightness_test_root/runtime.log" \
    || rg -q 'ANTI_BRIGHTNESS_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign|is not a type|AssertionError' "$brightness_test_root/runtime.log"; then
    cat "$brightness_test_root/runtime.log";exit 1
fi
python3 - "$brightness_test_root/writes" <<'PY'
from pathlib import Path
import sys
values=[int(value) for value in Path(sys.argv[1]).read_text().splitlines()]
assert values and min(values)<25 and values[-1]==50 and all(1<=value<=50 for value in values), values
print('PASS: production screencopy probe and controlled Qt pixels; real service dimming, unchanged base, lock/sleep cancellation, wake resampling and disable restoration with fake hardware',values)
PY
