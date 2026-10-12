#!/usr/bin/env python3
from pathlib import Path
r=Path(__file__).resolve().parents[1]
e=(r/"modules/abyss/AbyssEdgeEditor.qml").read_text()
p=(r/"modules/abyss/settings/AbyssPositionSettings.qml").read_text()
assert "editorBody.record?.surface" in e
assert "editorSurface.y+editorSurface.height+12" in e
assert "editorSurface.x+editorSurface.width+12" in e
assert '"Drag IPC · Enter save · Esc cancel"' in e
assert 'buttonText:"IPC"' in e
assert 'allowedKinds:["osd","volume","brightness","mic","mediaOsd","keyboardLayout","voiceSearch"]' in e
assert "visible: root.outputSelectionEnabled || !root.compactVertical" in p
assert "Override Edge and position for this output." in p
print("abyss edge editor external hints + compact IPC contract: ok")
