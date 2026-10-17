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
assert "function recordProbeNotificationFrame(now, intervalMs): void" in perimeter
assert "property int _frameProbeNotificationFrameLimit: 160" in perimeter
assert "notificationFrames:window._frameProbeNotificationFrames.slice()" in perimeter
assert "window._frameProbeNotificationFrames = []" in perimeter
assert "enabled: window._frameProbeEnabled" in perimeter
assert "AbyssRecordingBody {\n                id: recording" in perimeter
assert "function onRecordsChanged(): void" in perimeter
trace_src=perimeter[perimeter.index("function recordProbeNotificationFrame(now, intervalMs)"):]
trace_src=trace_src[:trace_src.index("id: frameHeartbeat")]
for forbidden in ("notification.summary", "notification.body", "notification.image",
                  "notification.appIcon", "process.command", "filePath"):
    assert forbidden not in trace_src, forbidden
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
assert module.EXPECTED_NOTIFICATION_FRAME_LIMIT == 160
valid_ack = [{"output":"Display X","started":True,"maxIntervals":600,
              "notificationFrameLimit":160}]
module.validate_frame_probe_start(valid_ack)
try:
    module.validate_frame_probe_start([{"started":True,"maxIntervals":600}])
except module.StaleRuntimeError as exc:
    assert "STALE_RUNTIME" in str(exc)
else:
    raise AssertionError("old runtime must be rejected before capture")
try:
    module.validate_frame_probe_start([{"started":False,
                                        "notificationFrameLimit":160}])
except RuntimeError:
    pass
else:
    raise AssertionError("inactive runtime must not be accepted")
valid_stop = [{"output":"Display X","count":0,"exhausted":False,
               "notificationFrames":[],"notificationFramesDropped":0,
               "notificationFrameLimit":160,"heartbeatHistoryExhausted":False}]
module.validate_frame_probe_stop(valid_stop)
try:
    module.validate_frame_probe_stop([{"count":0,"exhausted":False}])
except module.StaleRuntimeError:
    pass
else:
    raise AssertionError("old stopFrames schema must be rejected")
# No live qs required: handshake must release a stale, already-armed probe.
original_call = module.checked_call
calls = []
def stale_call(config, name, timeout=5):
    calls.append(name)
    return ([{"started":True,"maxIntervals":600}] if name == "startFrames"
            else [{"count":0,"exhausted":False}])
module.checked_call = stale_call
try:
    try:
        module.sample_phase(None, 0, .15, "baseline")
    except module.StaleRuntimeError:
        pass
    else:
        raise AssertionError("stale runtime was not blocked")
    assert calls == ["startFrames", "stopFrames"], calls
finally:
    module.checked_call = original_call
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
assert frames[0]["metrics"]["exhausted"] is False
assert frames[0]["metrics"]["heartbeatHistoryExhausted"] is False
assert "privateContent" not in str(frames)
# Multiple private keys may appear in the raw probe; allowlist only geometry
# and numeric timing in the saved JSON receipt.
trace=module.sanitize_frames([{
 "output":"Display X",
 "notificationRecordUpdates":5,"fieldRecordUpdates":6,"allocatorUpdates":1,
 "notificationFramesDropped":2,"notificationFrameLimit":160,
 "notificationFrames":[
  {"timestampMs":100,"intervalMs":16,"progress":.95,"progressDelta":.2,
   "paintDepth":140,"targetDepth":180,"visualInward":52,
   "pyramidActive":True,"pyramidClosing":False,"pyramidReopening":False,
   "recordingVisible":True,"notificationRecordChanges":2,
   "fieldRecordChanges":3,"allocatorChanges":1,"fieldRecordCount":15,
   "summary":"PRIVATE TEST TITLE","body":"PRIVATE TEST PATH"},
  {"timestampMs":134,"intervalMs":34,"progress":.45,"progressDelta":-.5,
   "paintDepth":68,"targetDepth":180,"visualInward":52,
   "pyramidActive":True,"pyramidClosing":True,"pyramidReopening":False,
   "recordingVisible":True,"notificationRecordChanges":2,
   "fieldRecordChanges":2,"allocatorChanges":0,"fieldRecordCount":15}
 ]}])[0]
assert trace["metrics"]["fieldRecordUpdates"] == 6
assert trace["metrics"]["notificationFramesDropped"] == 2
assert trace["notificationFrames"][1]["intervalMs"] == 34
assert trace["notificationFrames"][1]["pyramidClosing"]
assert trace["notificationFrames"][0]["recordingVisible"]
assert "PRIVATE TEST" not in str(trace)
assert module.trace_incomplete({"frames":[trace]})
complete = module.sanitize_frames([{
    "output":"Display X","count":2,"exhausted":False,
    "heartbeatHistoryExhausted":False,"notificationFrameLimit":160,
    "notificationFramesDropped":0
}])[0]
assert not module.trace_incomplete({"frames":[complete]})
for key in ("exhausted", "heartbeatHistoryExhausted"):
    raw = {"output":"Display X","count":600,"exhausted":False,
           "heartbeatHistoryExhausted":False,
           "notificationFrameLimit":160,"notificationFramesDropped":0}
    raw[key] = True
    assert module.trace_incomplete({"frames":module.sanitize_frames([raw])}), key
baseline={"snapshots":[]}
moving={"frames":[{"notificationFrames":trace["notificationFrames"]}]}
assert module.phase_observed("toast-close",baseline,moving)
assert not module.phase_observed("toast-open",baseline,moving)
up={"frames":[{"notificationFrames":[{"progress":.1},{"progress":.7}]}]}
assert module.phase_observed("toast-open",baseline,up)
assert not module.phase_observed("toast-close",baseline,up)
idle={"frames":[{"notificationFrames":[{"progress":1},{"progress":1}]}]}
assert not module.phase_observed("toast-close",baseline,idle)
assert not module.phase_observed("toast-open",baseline,idle)

print("ABYSS_NOTIFICATION_PHASE_SOURCE_PASS runtime handshake, cleanup, bounded trace and phase contracts")
