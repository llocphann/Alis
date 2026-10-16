#!/usr/bin/env python3
"""Source/collector contract; only real on-Niri measurements prove performance."""
import importlib.util
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
content = (ROOT/"modules/abyss/content/AbyssNotificationsContent.qml").read_text()
perimeter = (ROOT/"modules/abyss/AbyssPerimeter.qml").read_text()
ci = (ROOT/".github/workflows/ci.yml").read_text()
assert "readonly property real measuredPopupHeight:" in content
assert "popupLoader.item?.contentHeight" in content
assert "notificationPresentation:{" in perimeter
a=perimeter.index("notificationPresentation:{")
b=perimeter.index("genericPopup:{",a)
block=perimeter[a:b]
for key in ["toastCount","inhibited","recording","centerOpen","toastOpen",
            "toastResident","toastRevealProgress","toastSpan","toastDepth",
            "toastPaintDepth","toastTargetDepth",
            "toastAlong","toastDesiredHeight","toastMeasuredHeight","toastLayoutReady"]:
    assert key + ":" in block, key
for forbidden in ["notification.body","notification.summary","notification.image",
                  "SAVE_PATH","output_name","notificationObject?.body"]:
    assert forbidden not in block
assert "test-abyss-notification-presentation-probe.py" in ci
spec=importlib.util.spec_from_file_location("probe",
        ROOT/"scripts/collect-abyss-notification-frames.py")
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
raw='IPC Result: "{\\"timestamp\\":1,\\"family\\":\\"abyss\\",\\"outputs\\":[{\\"output\\":\\"Display X\\",\\"notificationPresentation\\":{\\"toastCount\\":2,\\"recording\\":true,\\"toastLayoutReady\\":true,\\"toastDesiredHeight\\":140},\\"popupSlots\\":[{\\"kind\\":\\"notificationCenter\\",\\"requestedVisible\\":true},{\\"kind\\":\\"secretMenu\\"}],\\"modules\\":[{\\"name\\":\\"private\\"}]}]}"'
parsed=module.parse_ipc(raw)
safe=module.sanitize_snapshot(parsed)
assert safe["outputs"][0]["toast"]["recording"]
assert safe["outputs"][0]["toast"]["toastLayoutReady"]
assert safe["outputs"][0]["measurements"]["toastCount"] == 2
assert safe["outputs"][0]["measurements"]["toastDesiredHeight"] == 140
assert len(safe["outputs"][0]["center"]) == 1
assert "Display X" not in str(safe) and "private" not in str(safe)
def state(record=False, count=0, center=False):
    return {"outputId":"screen-hash",
            "toast":{"recording":record},
            "measurements":{"toastCount":count},
            "center":[{"active":center}] if center else []}
def phase(before, after):
    return ({"snapshots":[{"outputs":[before]}]},
            {"snapshots":[{"outputs":[after]}]})
for label, a, b, expected in [
    ("record-start", state(), state(record=True), True),
    ("record-start", state(record=True), state(record=True), False),
    ("record-stop", state(record=True), state(count=1), True),
    ("record-stop", state(), state(count=1), False),
    ("record-stop", state(record=True), state(count=0), False),
    ("edge-hover", state(), state(center=True), True),
    ("edge-hover", state(center=True), state(center=True), False),
    ("edge-hover", state(), state(count=1), False)]:
    before,after=phase(a,b)
    assert module.phase_observed(label,before,after) is expected,label
frames=module.sanitize_frames([{"output":"Display X","count":20,"p95":35,
 "slowEvents":[{"timestampMs":1,"intervalMs":41,
                "popupMotion":[{"kind":"privateContent"}]}]}])
assert frames[0]["metrics"]["p95"] == 35
assert "privateContent" not in str(frames)
# NOTIF-I04: a cold grouped model must be measured even if the initial
# ListView contentHeight is zero and no height-changed callback is delivered.
assert "property int popupMeasureAttempts: 0" in content
assert "popupMeasureAttemptLimit: 10" in content
assert "function onPopupAppNameListChanged(): void" in content
measure=content[content.index("function schedulePopupMeasurement(): void"):
                content.index("Component.onCompleted:",content.index("function schedulePopupMeasurement(): void"))]
assert "if (Number(popupLoader.item?.contentHeight ?? 0) > 0)" not in measure
assert "popupMeasureTimer.restart()" in measure
assert "view.forceLayout()" in measure
assert "popupMeasureAttempts < root.popupMeasureAttemptLimit" in measure
assert "if (!Number.isFinite(height) || height <= 0)" in measure
assert measure.index("height <= 0") < measure.index("root.popupLayoutReady=true")
assert "root.popupMeasureAttempts=0" in content
print("ABYSS_NOTIFICATION_PHASE_SOURCE_PASS 31 source/collector contracts")
