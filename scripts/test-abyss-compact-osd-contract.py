#!/usr/bin/env python3
from pathlib import Path

r = Path(__file__).resolve().parents[1]
content = (r / "modules/abyss/content/AbyssOsdContent.qml").read_text()
ctrl = (r / "modules/abyss/AbyssOsdController.qml").read_text()

assert 'if (GlobalStates.osdVolumeOpen) kinds.push("volume")' in content
assert 'if (GlobalStates.osdBrightnessOpen) kinds.push("brightness")' in content
assert 'if (GlobalStates.osdMicOpen) kinds.push("mic")' in content
assert 'if (GlobalStates.osdKeyboardLayoutOpen) kinds.push("keyboardLayout")' in content
assert "RowLayout" in content and "spacing: 10" in content
assert 'const compact=["volume","brightness","mic","keyboardLayout"]' in ctrl
assert "Keep already-active compact" in ctrl

# IPC is a full Pyramid participant, not a second window or an independent
# reveal timer. The existing host progress and fullscreen physical-edge path
# must remain authoritative for each compact and media indicator.
perimeter = (r / "modules/abyss/AbyssPerimeter.qml").read_text()
host = (r / "modules/abyss/AbyssBodyHost.qml").read_text()
osd = perimeter.split('id: osd\n', 1)[1].split('            AbyssRecordingBody {', 1)[0]
assert 'identity: "osd"' in osd
assert 'stackPolicy: "pyramid"' in osd
assert "externalProgress: 1" in osd
assert "open: (window.presented || window.physicalOsdRequested)" in osd
assert "window.physicalOsdResident ? window.physicalInsets" in osd
assert 'source: "content/AbyssOsdContent.qml"' in osd
assert 'root.stackPolicy === "pyramid"' in host
assert "root.externalProgress >= 0" in host
assert "root.pyramidCoordinator?.beginClose(" in host
print("concurrent compact Abyss OSD contract: ok")
