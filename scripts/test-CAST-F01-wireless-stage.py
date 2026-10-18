#!/usr/bin/env python3
"""CAST-F01: offline GNOME D-Bus bridge regression tests; no real TV needed."""
import importlib.util
from pathlib import Path
from unittest import mock

root = Path(__file__).resolve().parents[1]
script = root / "scripts/CAST-F01-network-displays.py"
spec = importlib.util.spec_from_file_location("cast_f01_wireless", str(script))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def field(kind, value):
    return {"type": kind, "data": value}


receiver1 = ["uuid", field("s", "00112233-abcd"),
             "display-name", field("s", "Classroom TV"),
             "state", field("u", 4096),
             "priority", field("u", 10),
             "protocol", field("u", 3)]
receiver2 = ["uuid", field("s", "00224466-abcd"),
             "display-name", field("s", "Projector"),
             "state", field("u", 256),
             "priority", field("u", 9),
             "protocol", field("u", 1)]
payload = {"type": "aa{sv}", "data": [receiver1, receiver2]}
values = module.displays(payload)
assert len(values) == 2
assert values[0]["name"] == "Classroom TV"
assert values[0]["protocol"] == "Chromecast"
assert values[0]["state"] == "streaming"
assert values[1]["name"] == "Projector"
assert values[1]["protocol"] == "Miracast P2P"
assert values[1]["state"] == "p2p"
assert module.displays({"type": "aa{sv}", "data": []}) == []
assert module.displays({"type": "aa{sv}", "data": [receiver1, receiver1]}) == values[:1]
assert module.displays({"type": "aa{sv}", "data": [[
    ["uuid", field("s", "abcdef12")],
    ["display-name", field("s", "Another TV")],
    ["protocol", field("u", 2)],
]]})[0]["protocol"] == "Miracast MICE"

try:
    module.displays({"type": "as", "data": ["fake TV"]})
    assert False, "must reject unexpected variant signatures"
except module.CastError:
    pass

def fake_scan():
    return {"ok": True, "backend": True, "displays": values}

unit = "gnome-network-displays-stream-00112233-abcd.service"
with mock.patch.object(module, "scan", fake_scan), mock.patch.object(
        module, "bus", return_value={"type": "s", "data": [unit]}) as called:
    result = module.start("00112233-abcd")
    assert result["ok"] and result["unit"] == unit
    assert called.call_args.args[-2:] == ("s", "00112233-abcd")
    try:
        module.start("00112233;rm -rf /")
        assert False
    except module.CastError:
        pass
    try:
        module.start("unseen-tv")
        assert False
    except module.CastError:
        pass

with mock.patch.object(module, "bus",
                       return_value={"type": "s", "data": ["malicious.service"]}):
    try:
        module.start("00112233-abcd")
        assert False
    except module.CastError:
        pass

with mock.patch.object(module, "run", return_value=""):
    assert module.bus("call", module.BUS, module.OBJ, module.IFACE,
                      "StopStream", "s", unit) == {"type": "", "data": []}

with mock.patch.object(module, "bus", return_value={"type": "", "data": []}) as called:
    assert module.stop(unit)["ok"]
    assert called.call_args.args[-2:] == ("s", unit)

for bogus in ("", "sudo.service", "gnome-network-displays-stream-a.service; rm -rf /"):
    for fun in (module.stop, module.status):
        try:
            fun(bogus)
            assert False, bogus
        except module.CastError:
            pass

with mock.patch.object(module, "run", return_value="ActiveState=active\nSubState=running\nResult=success\n"):
    s = module.status(unit)
    assert s["state"] == "active"
    assert "verify TV" in s["message"]

with mock.patch.object(module, "run", return_value="ActiveState=failed\nSubState=failed\nResult=exit-code\n"):
    assert not module.status(unit)["ok"]

qml = (root / "services/NetworkDisplays.qml").read_text()
popup = (root / "modules/abyss/content/AbyssUtilitiesPopup.qml").read_text()
audio = (root / "services/ProjectAudio.qml").read_text()
policy = (root / "services/ProjectAudioPolicy.js").read_text()
qmldir = (root / "services/qmldir").read_text()

for word in ('singleton NetworkDisplays 1.0 NetworkDisplays.qml',):
    assert word in qmldir
for word in ("function scan(): void", "function connectToSelected(): void",
             "function disconnect(): void", '["python3", bridge, "scan"]',
             '["python3", bridge, "start", target.uuid]',
             '["python3", bridge, "stop", activeUnit]',
             '["python3", bridge, "status", activeUnit]',
             "ProjectAudio.beginWireless(root.activeUuid)",
             "ProjectAudio.endWired()"):
    assert word in qml, word
for word in ("NetworkDisplays.displays", "NetworkDisplays.scan()",
             "NetworkDisplays.connectToSelected()", "NetworkDisplays.disconnect()",
             "Flickable {", "NetworkDisplays.selectedUuid"):
    assert word in popup, word
assert 'function beginWireless(uuid)' in audio
assert 'Policy.findWirelessSink(Audio.outputDevices, _wirelessUuid)' in audio
assert "function findWirelessSink(devices, uuid)" in policy

# Do not use fake receiver names or mutate network, bypass portals or restart.
assert "nmcli" not in script.read_text()
assert "systemctl" in script.read_text() and "ActiveState" in script.read_text()
print("CAST_F01_WIRELESS_PASS: typed D-Bus discovery, request ownership and QML UI")
