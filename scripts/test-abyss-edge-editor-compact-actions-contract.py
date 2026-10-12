#!/usr/bin/env python3
from pathlib import Path
import re, subprocess

root = Path(__file__).resolve().parents[1]
editor = (root / "modules/abyss/AbyssEdgeEditor.qml").read_text()
positions = (root / "modules/abyss/settings/AbyssPositionSettings.qml").read_text()

for needle in [
    'text: "Reset"; glyph: "restart_alt"; compact: true',
    'text: "Cancel"; glyph: "close"; compact: true',
    'text: "Done"; glyph: "check"',
    'buttonIcon:"widgets";buttonText:"Modules"',
    'buttonIcon:"open_in_new";buttonText:"IPC"',
    'compactActions:root.toolbarOnHorizontalEdge',
    'text:"Add module";glyph:"add"',
    'text:"Snap to guides";glyph:"grid_4x4"',
    'text:"Inherit surface";glyph:"layers"',
    'text:"Expand whole Edge";glyph:"fit_screen"',
    '? "visibility" : "visibility_off"',
    'text:"Remove";glyph:"delete"',
]:
    assert needle in editor, needle

# Horizontal editor actions become compact icon controls. Side editor actions
# retain icon + text for readability in the vertical control rail.
assert editor.count("compact:root.toolbarOnHorizontalEdge") >= 5
assert 'property bool compactActions: false' in positions
assert 'text:"Reset position";glyph:"restart_alt"' in positions
assert 'compact:root.compactActions' in positions
assert 'description:root.ipcOnly ? "Reset IPC position"' in positions
# Popup placement choices must not be exposed by this screen-edge editor.
match = re.search(r'allowedKinds:\s*\[([^]]+)\]', editor)
assert match, "Editor must constrain independently positioned indicators"
choices = re.findall(r'"([^"]+)"', match.group(1))
assert set(choices) == {"osd","volume","brightness","mic","mediaOsd","keyboardLayout","voiceSearch"}, choices
assert '"clock"' not in choices and '"notificationCenter"' not in choices

# Ambiguous scope/placement semantics intentionally stay textual.
for needle in [
    'text:"This output only"',
    'text:"Custom size"',
]:
    assert needle in editor, needle

# Exercise the real binding for both the unjoined and nearby-Edge states;
# whitespace or a multiline conditional must not change this contract.
label=re.search(r'text:\s*(root\.nearbyCorner\s*\?[\s\S]*?)\n\s*checked:',editor)
assert label, "join action must expose a contextual text binding"
subprocess.run(["node","-e",r'''
const assert=require('node:assert/strict'),vm=require('node:vm');
for(const nearbyCorner of ['', 'top', 'right', 'bottom', 'left']) {
 const actual=vm.runInNewContext(process.argv[1],{root:{nearbyCorner}},{timeout:100});
 assert.equal(actual,nearbyCorner ? 'Connect to '+nearbyCorner+' corner' : 'Join nearby corner');
}
''',label.group(1)],check=True)

print("abyss editor compact action density contract: ok")
