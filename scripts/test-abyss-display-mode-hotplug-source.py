#!/usr/bin/env python3
"""Guard mirror-session hotplug check ordering without changing real outputs."""
from pathlib import Path
p=Path(__file__).resolve().parents[1]/"services/DisplayMode.qml"
text=p.read_text()
start=text.index("function normalizeSelections()")
end=text.index("function setMirrorSource",start)
body=text[start:end]
assert body.index("mirrorPairConnected(names, _runningMirrorPair)") < body.index("if (!names.length)")
assert body.index("mirrorPairConnected(names, _runningMirrorPair)") < body.index("mirrorSource = primaryOutput")
assert "property var _runningMirrorPair: null" in text
assert "_runningMirrorPair = {source: spec.source, target: spec.target}" in text
assert "mirrorPairConnected(connectedOutputs, spec)" in text
assert "root._runningMirrorPair = null" in text
assert "stopMirror()" in body
print("DISPLAY_MODE_HOTPLUG_SOURCE_PASS")
