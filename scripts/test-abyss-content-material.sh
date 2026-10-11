#!/usr/bin/env bash
# GPU pixel evidence for independent body opacity/blur in the one field pass.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]];then printf 'SKIP: content material (Quickshell/Wayland unavailable)\n';exit 0;fi
material_test_root="$(mktemp -d)"
trap 'rm -rf -- "$material_test_root"' EXIT
for entry in modules services GlobalStates.qml qmldir assets scripts defaults translations;do ln -s "$repo_root/$entry" "$material_test_root/$entry";done
mkdir -p "$material_test_root/config/illogical-impulse"
cp "$repo_root/defaults/config.json" "$material_test_root/config/illogical-impulse/config.json"
python3 - "$material_test_root/checker.png" <<'PY'
from PIL import Image
import sys
image=Image.new('RGB',(420,300));image.putdata([(235,100,25) if (x//8+y//8)%2 else (15,100,230) for y in range(300) for x in range(420)]);image.save(sys.argv[1])
PY
cat > "$material_test_root/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.abyss.looks
ShellRoot {
    id:root;property int step:0;property bool finished:false;property int captures:0
    function capture(name): void { field.grabToImage(result=> { result.saveToFile(Quickshell.env("MATERIAL_OUTPUT")+"/"+name+".png");root.captures++ }) }
    FloatingWindow {
        visible:true;implicitWidth:420;implicitHeight:300;color:"transparent"
        AbyssField {
            id:field;anchors.fill:parent;edgeInsets:({left:10,right:10,top:10,bottom:10})
            records:[{surface:{x:100,y:140,width:220,height:210}}]
        }
    }
    Timer {
        interval:320;running:!root.finished;repeat:true
        onTriggered: {
            if(!Config.ready || !field.ready) return
            if(root.step===0) Config.setNestedValues({"panelFamily":"abyss","abyss.quality":"quality","abyss.surface.opacity":.85,
                "abyss.content.opacity":.3,"abyss.content.blurRadius":0,"abyss.effects.blur.enabled":false,
                "abyss.effects.refraction.enabled":true,"abyss.effects.refraction.strength":1,"abyss.waves.enabled":false,
                "abyss.effects.surfaceHighlight":0,"abyss.effects.glow.strength":0,"abyss.effects.shadowStrength":0,
                "background.wallpaperPath":Quickshell.env("MATERIAL_OUTPUT")+"/checker.png"})
            if(root.step===2) { if(!field.wallpaperReady) return;root.capture("clear") }
            if(root.step===3 && root.captures<1) return
            if(root.step===4) Config.setNestedValue("abyss.content.blurRadius",24)
            if(root.step===5) root.capture("blurred")
            if(root.step===6 && root.captures<2) return
            if(root.step===6) Config.setNestedValue("abyss.content.opacity",1)
            if(root.step===7) root.capture("opaque")
            if(root.step===8 && root.captures<3) return
            if(root.step===8) Config.setNestedValues({"abyss.content.opacity":.45,"abyss.content.cardOpacity":.12})
            if(root.step===9) {
                if(root.captures!==3) return
                if(Math.abs(AbyssStyle.contentLayer.a-.45)>.01 || AbyssStyle.cardOpacity!==AbyssStyle.contentOpacity) { console.error("MATERIAL_FAIL","shared content tint/retired key",AbyssStyle.contentLayer.a,root.captures);root.finished=true;return }
            }
            if(root.step===10) Config.setNestedValues({"abyss.quality":"performance",
                "abyss.surface.opacity":0,"abyss.content.opacity":1,
                "abyss.effects.blur.enabled":false,"abyss.effects.refraction.enabled":false})
            if(root.step===11) {
                if(AbyssStyle.surfaceOpacity!==0 || AbyssStyle.surface.a>.01) { console.error("MATERIAL_FAIL","Screen Edge opacity must allow a fully wallpaper-facing clear state");root.finished=true;return }
                if(AbyssStyle.contentOpacity!==1) { console.error("MATERIAL_FAIL","clear Screen Edge must not force panel content transparent");root.finished=true;return }
                if(AbyssStyle.contentBlurRadius!==0 || field.wantsWallpaper) { console.error("MATERIAL_FAIL","performance quality must release wallpaper effects when blur/refraction are off");root.finished=true;return }
                console.info("MATERIAL_PASS");root.finished=true
            }
            root.step++
        }
    }
}
QML
status=0
env -u QS_CONFIG_PATH -u QS_CONFIG_NAME -u QS_MANIFEST QT_QPA_PLATFORM=wayland MATERIAL_OUTPUT="$material_test_root" XDG_CONFIG_HOME="$material_test_root/config" XDG_STATE_HOME="$material_test_root/state" XDG_CACHE_HOME="$material_test_root/cache" timeout 20s qs -p "$material_test_root" --no-color > "$material_test_root/runtime.log" 2>&1 || status=$?
if [[ "$status" != 124 ]] || ! rg -q MATERIAL_PASS "$material_test_root/runtime.log" || rg -q 'MATERIAL_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign|is not a type|ShaderEffect.*Error' "$material_test_root/runtime.log";then cat "$material_test_root/runtime.log";exit 1;fi
if [[ -n "${ABYSS_MATERIAL_OUTPUT:-}" ]];then mkdir -p "$ABYSS_MATERIAL_OUTPUT";cp "$material_test_root/clear.png" "$material_test_root/blurred.png" "$material_test_root/opaque.png" "$ABYSS_MATERIAL_OUTPUT/";fi
python3 - "$material_test_root" <<'PY'
from PIL import Image, ImageChops
from pathlib import Path
import sys
root=Path(sys.argv[1]);clear=Image.open(root/'clear.png').convert('RGBA');blurred=Image.open(root/'blurred.png').convert('RGBA');opaque=Image.open(root/'opaque.png').convert('RGBA')
edge=(2,100);body=(210,220)
assert abs(clear.getpixel(edge)[3]-217)<=3,'Edge opacity remains independent'
assert abs(clear.getpixel(body)[3]-77)<=3,'body opacity reaches actual pixels'
assert opaque.getpixel(body)[3]>=253 and abs(opaque.getpixel(edge)[3]-217)<=3,'opaque body preserves Edge alpha'
diff=ImageChops.difference(clear.crop((135,185,280,260)),blurred.crop((135,185,280,260)))
assert sum(sum(pixel[:3]) for pixel in diff.getdata())>500,'body blur changes the sampled wallpaper'
assert clear.getchannel('A').tobytes()==blurred.getchannel('A').tobytes(),'blur preserves silhouette and alpha'
print('PASS: GPU body opacity/blur, independent Edge alpha, zero-alpha wallpaper reveal, live card tint and performance effect release')
PY
