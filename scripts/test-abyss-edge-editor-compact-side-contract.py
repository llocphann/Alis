#!/usr/bin/env python3
from pathlib import Path
import re
r=Path(__file__).resolve().parents[1]
e=(r/"modules/abyss/AbyssEdgeEditor.qml").read_text()
p=(r/"modules/abyss/settings/AbyssPositionSettings.qml").read_text()
assert "editorBody.record?.surface" in e
assert "editorSurface.y+editorSurface.height+12" in e
assert "editorSurface.x+editorSurface.width+12" in e
assert '"Drag IPC · Enter save · Esc cancel"' not in e
assert 'buttonText:"IPC"' in e
assert 'allowedKinds:["osd","volume","brightness","mic","mediaOsd","keyboardLayout","voiceSearch"]' in e
output=p.split('id:outputChoice',1)[1].split('Layout.fillWidth:',1)[0]
assert re.search(r'visible:\s*root.showOutputSelector\s*&&\s*\(root.outputSelectionEnabled\s*\|\|\s*!root.compactVertical\)',output)
assert 'showOutputSelector:false' in e
assert re.search(r'outputName:\s*root.outputOnly\s*\?\s*root.outputName\s*:\s*""',e)
assert "Override Edge and position for this output." in p
assert 'id:editFineControls' in e and 'id:selectedModuleControls' in e
print("abyss edge editor grouped toolbar + compact IPC contract: ok")
