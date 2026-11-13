#!/usr/bin/env bash
# Qualify actual Clipboard retraction without swapping in Overview/Dashboard.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${ALIS_SILENT_WL_WRAPPED:-0}" != "1" ]]; then
    export ALIS_SILENT_WL_WRAPPED=1
    exec bash "$repo_root/scripts/lib/silent-wayland-run.sh" --need-niri -- "$0" "$@"
fi
if ! command -v qs >/dev/null || ! command -v niri >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    printf 'SKIP: Abyss clipboard lifecycle (Quickshell/Niri/Wayland unavailable)\n'
    exit 0
fi
clipboard_test_root="$(mktemp -d)"
trap 'rm -rf -- "$clipboard_test_root"' EXIT
python3 - "$repo_root" "$clipboard_test_root" <<'PYSETUP'
from pathlib import Path
import re,shutil,sys
repo,base=map(Path,sys.argv[1:])
(base/'modules').mkdir()
for entry in (repo/'modules').iterdir():
    if entry.name=='abyss': shutil.copytree(entry,base/'modules'/entry.name)
    else: (base/'modules'/entry.name).symlink_to(entry)
for name in ['services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']: (base/name).symlink_to(repo/name)
p=base/'modules/abyss/AbyssPerimeter.qml';s=p.read_text()
variants_id=re.search(r'\bVariants\s*\{\s*id:\s*(\w+)',s).group(1)
s=s.replace('id: root\n',f'id: root\n    readonly property var qaWindows: {variants_id}.instances\n',1)
clipboard='clipboardBody' if 'id: clipboardBody' in s else 'aux'
s=s.replace('id: window\n','id: window\n            property alias qaClipboard: '+clipboard+'\n            property alias qaOverview: aux\n            property alias qaField: field\n',1)
p.write_text(s)
(base/'config/illogical-impulse').mkdir(parents=True)
shutil.copy2(repo/'defaults/config.json',base/'config/illogical-impulse/config.json')
PYSETUP
cat > "$clipboard_test_root/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.abyss
ShellRoot {
    id:root
    property int step:0
    property bool failed:false
    property string clipboardSource:""
    function check(ok,message) { if(ok) return true; console.error("CLIPBOARD_REFINE_FAIL",message);failed=true;Qt.quit();return false }
    AbyssPerimeter { id:perimeter }
    Timer {
        interval:400;running:!root.failed;repeat:true
        onTriggered: {
            if(!Config.ready || !perimeter.qaWindows.length) return
            const output=perimeter.qaWindows[0],clip=output.qaClipboard,overview=output.qaOverview
            if(!output.qaField.ready) return
            if(root.step===0) {
                Config.setNestedValue("panelFamily","abyss")
                Config.setNestedValue("performance.reduceAnimations",false)
                Config.setNestedValue("enabledPanels",["abyssPerimeter","abyssClipboard","abyssOverview","iiDashboard"])
                GlobalStates.shellEntryReady=true;GlobalStates.deferredPanelsReady=true
                GlobalStates.dashboardOpen=false;GlobalStates.clipboardOpen=true
            } else if(root.step===1) {
                if(!root.check(clip.open && clip.ready && !overview.ready && !GlobalStates.dashboardOpen,"only Clipboard content is loaded "+JSON.stringify({open:clip.open,ready:clip.ready,status:clip.contentItem.status,progress:clip.progress,presented:output.presented,fullscreen:output.fullscreenCovered,output:output.outputName,target:GlobalStates.abyssClipboardTargetOutput,resolved:GlobalStates.resolveOutputName(GlobalStates.abyssClipboardTargetOutput,[]),clipboard:GlobalStates.clipboardOpen,overview:overview.ready,dashboard:GlobalStates.dashboardOpen,panels:Config.options.enabledPanels}))) return
                root.clipboardSource=String(clip.contentItem.source)
                GlobalStates.clipboardOpen=false
                if(!root.check(clip.progress>0 && String(clip.contentItem.source)===root.clipboardSource && !overview.ready && !GlobalStates.dashboardOpen,"closing retains Clipboard while retracting without opening Dashboard")) return
            } else if(root.step===3) {
                if(!root.check(!clip.ready && !overview.ready && !GlobalStates.dashboardOpen,"closed Clipboard unloads with Dashboard unchanged")) return
                GlobalStates.dashboardOpen=true;GlobalStates.clipboardOpen=true
            } else if(root.step===4) {
                if(!root.check(clip.ready && !overview.ready && GlobalStates.dashboardOpen,"Clipboard leaves an already-open Dashboard flag intact")) return
                GlobalStates.clipboardOpen=false
                if(!root.check(String(clip.contentItem.source)===root.clipboardSource && !overview.ready && GlobalStates.dashboardOpen,"retraction preserves the already-open Dashboard")) return
            } else if(root.step===6) {
                if(!root.check(!clip.ready && !overview.ready && GlobalStates.dashboardOpen,"repeated close keeps prior Dashboard state")) return
                GlobalStates.dashboardOpen=false
                console.info("CLIPBOARD_REFINE_PASS");Qt.quit()
            }
            root.step++
        }
    }
}
QML
if ! python3 - "$repo_root" "$clipboard_test_root" <<'PYRUN'
from pathlib import Path
import sys
repo,folder=map(Path,sys.argv[1:])
sys.path.insert(0,str(repo/'scripts'))
from native_test_session import private_wayland, run_qs
with private_wayland(folder) as env:
    if env is None:
        raise RuntimeError("Private Niri did not become available")
    env.update(QT_QUICK_CONTROLS_STYLE="Basic", QT_QPA_PLATFORMTHEME="generic")
    result=run_qs(folder,env,timeout=25)
(folder/'runtime.log').write_text(result.stdout)
raise SystemExit(result.returncode)
PYRUN
then
    cat "$clipboard_test_root/runtime.log"; exit 1
fi
if ! rg -q CLIPBOARD_REFINE_PASS "$clipboard_test_root/runtime.log" || \
 rg -q 'CLIPBOARD_REFINE_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign|is not a type|Failed to load configuration' "$clipboard_test_root/runtime.log"; then
    cat "$clipboard_test_root/runtime.log"; exit 1
fi
printf 'PASS: Clipboard retains its content while retracting, unloads, and preserves closed/open Dashboard state\n'
