#!/usr/bin/env bash
# Exercise the real output OSD host; aliases expose state only in a private copy.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null || [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    printf 'SKIP: Abyss IPC corner (Quickshell/Wayland unavailable)\n'; exit 0
fi
ipc_test_root="$(mktemp -d)"
trap 'rm -rf -- "$ipc_test_root"' EXIT
python3 - "$repo_root" "$ipc_test_root" <<'PYSETUP'
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
s=s.replace('id: root\n',f'id: root\n    readonly property var qaWindows: {variants_id}.instances\n    readonly property bool qaIPCReady: qaOsdController.initialized\n',1)
s=s.replace('    AbyssOsdController {}','    AbyssOsdController { id: qaOsdController }',1)
s=s.replace('id: window\n','id: window\n            property alias qaOsd: osd\n            property alias qaEditor: editor\n            property alias qaField: field\n',1)
p.write_text(s)
(base/'config/illogical-impulse').mkdir(parents=True)
shutil.copy2(repo/'defaults/config.json',base/'config/illogical-impulse/config.json')
PYSETUP
cat > "$ipc_test_root/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.abyss
ShellRoot {
    id:root
    property int step:0
    property string joinedContent:""
    property var edges:["top","right","bottom","left"]
    function check(ok,message) { if(ok) return true; console.error("IPC_CORNER_FAIL",message);Qt.quit();return false }
    AbyssPerimeter { id:perimeter }
    Timer {
        interval:400;running:true;repeat:true
        onTriggered: {
            if(!Config.ready || !perimeter.qaWindows.length || !perimeter.qaIPCReady) return
            const output=perimeter.qaWindows[0],osd=output.qaOsd
            if(!output.qaField.ready) return
            if(root.step===0) {
                Config.setNestedValue("panelFamily","abyss")
                Config.setNestedValue("performance.reduceAnimations",true)
                Config.setNestedValue("enabledPanels",["abyssPerimeter","abyssOnScreenDisplay"])
                GlobalStates.shellEntryReady=true;GlobalStates.deferredPanelsReady=true
            } else if(root.step<=12) {
                const index=Math.floor((root.step-1)/3),phase=(root.step-1)%3,edge=root.edges[index]
                if(phase===0) {
                    Config.setNestedValue("abyss.positions",[{kind:"osd",edge:edge,alignment:"start",joinCorner:true}])
                    GlobalStates.osdRequested("volume")
                } else if(phase===1) {
                    const adjacent=["top","bottom"].includes(edge)?"left":"top"
                    console.info("IPC_CORNER_STATE",edge,osd.open,osd.ready,osd.edge,osd.joinedEdge,JSON.stringify(osd.record),GlobalStates.osdVolumeOpen)
                    if(!root.check(osd.open && osd.ready && osd.edge===edge && osd.record.joinedEdge===adjacent,"real IPC inherits OSD join on "+edge)) return
                    root.joinedContent=JSON.stringify(osd.record.content)
                    Config.setNestedValue("abyss.positions",[{kind:"osd",edge:edge,alignment:"start",joinCorner:true},
                        {kind:"volume",outputName:output.outputName,edge:edge,alignment:"start",joinCorner:false}])
                } else {
                    if(!root.check(osd.joinedEdge==="" && osd.record.joinedEdge===undefined && JSON.stringify(osd.record.content)===root.joinedContent,"output override disables joining without resizing IPC content on "+edge)) return
                }
            } else if(root.step===13) {
                Config.setNestedValue("osd.timeout",300)
                GlobalStates.startAbyssEditing(output.outputName)
                output.qaEditor.editingPopups=true
                GlobalStates.osdRequested("volume")
            } else if(root.step===15) {
                if(!root.check(!GlobalStates.osdVolumeOpen && !osd.open && output.qaEditor.previewHost.open && output.qaEditor.previewHost.ready && output.qaEditor.previewHost.inputBounds.width>0,"IPC edit preview stays visible after OSD timeout while suppressing duplicate live OSD")) return
                output.qaEditor.finish(false)
            }
            root.step++
            if(root.step===16) { console.info("IPC_CORNER_PASS");Qt.quit() }
        }
    }
}
QML
status=0
python3 - "$repo_root" "$ipc_test_root" > "$ipc_test_root/runtime.log" 2>&1 <<'PY' || status=$?
import sys
from pathlib import Path
sys.path.insert(0,str(Path(sys.argv[1])/"scripts"))
from native_test_session import private_wayland,run_qs
folder=Path(sys.argv[2])
with private_wayland(folder) as env:
    if env is None:
        print("SKIP: Abyss IPC corner requires private Niri")
        raise SystemExit(77)
    result=run_qs(folder,env,timeout=15)
    print(result.stdout)
    raise SystemExit(result.returncode)
PY
if [[ "$status" == 77 ]];then cat "$ipc_test_root/runtime.log";exit 0;fi
if [[ "$status" != 0 ]];then
    cat "$ipc_test_root/runtime.log";exit 1
fi
if ! rg -q IPC_CORNER_PASS "$ipc_test_root/runtime.log" || rg -q 'IPC_CORNER_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign|is not a type|Type .* unavailable' "$ipc_test_root/runtime.log"; then
    cat "$ipc_test_root/runtime.log";exit 1
fi
printf 'PASS: real IPC joins all four Edges, inherits category preferences and retains content/input sizing through output overrides\n'
