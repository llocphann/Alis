#!/usr/bin/env python3
"""CAST-F01 measured P2P signal regression tests; no hardware or user bus access."""
import importlib.util
import time
from pathlib import Path
from unittest import mock

root = Path(__file__).resolve().parents[1]
script = root / "scripts/CAST-F01-network-displays.py"
spec = importlib.util.spec_from_file_location("cast_f01_signal", str(script))
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)

def receiver(name, protocol=1, uuid="abc-123"):
    return {"name": name, "uuid": uuid, "protocolId": protocol, "protocol": "Miracast P2P"}

# Real NetworkManager object properties include a percentage, peer name
# and CLOCK_BOOTTIME timestamp. No SSID, BSSID, MAC or AP strength required.
p2p_path = "/org/freedesktop/NetworkManager/Devices/4"
eth_path = "/org/freedesktop/NetworkManager/Devices/1"
peer_path = "/org/freedesktop/NetworkManager/WifiP2PPeer/8"
now = int(time.clock_gettime(time.CLOCK_BOOTTIME))

def measured_bus(*args):
    if args[-1] == "GetDevices":
        return {"type": "ao", "data": [[eth_path, p2p_path]]}
    if args[-1] == "Peers":
        if eth_path in args:
            raise bridge.CastError("Not a P2P device")
        return {"type": "ao", "data": [[peer_path]]}
    if args[-3:] == ("GetAll", "s", bridge.NM_PEER_IFACE):
        return {"type": "a{sv}", "data": [[
            "Name", {"type": "s", "data": "Classroom Miracast"},
            "Strength", {"type": "y", "data": 82},
            "LastSeen", {"type": "i", "data": now - 3},
            "HwAddress", {"type": "s", "data": "11:22:33:44:55:66"},
        ]]}
    raise AssertionError(f"Unexpected system D-Bus request: {args!r}")

with mock.patch.object(bridge, "system_bus", side_effect=measured_bus):
    readings = bridge.p2p_signal_samples()
assert readings == [("classroom miracast", 82)], readings

out = bridge.add_receiver_signal_strength([
    receiver("Classroom Miracast"),
    receiver("Samsung TV", protocol=3, uuid="cc-123"),
], readings)
assert out[0]["signalStrength"] == 82
assert out[0]["signalQuality"] == "Strong"
assert "signalStrength" not in out[1], "Chromecast is not a P2P peer"

for pct, expected in [(95, "Strong"), (75, "Strong"), (65, "Good"), (50, "Good"),
                      (40, "Fair"), (30, "Fair"), (29, "Weak"), (1, "Weak")]:
    x = bridge.add_receiver_signal_strength([receiver("Display")], [("display", pct)])
    assert (x[0]["signalStrength"], x[0]["signalQuality"]) == (pct, expected)

for samples in ([], [("elsewhere", 88)], [("display", 0)],
                [("display", 101)], [("display", True)],
                [("display", 61), ("display", 79)]):
    x = bridge.add_receiver_signal_strength([receiver("Display")], samples)
    assert "signalStrength" not in x[0], samples

duplicate = bridge.add_receiver_signal_strength(
    [receiver("Twin TV", uuid="a1"), receiver("twin tv", uuid="a2")],
    [("twin tv", 72)])
assert all("signalStrength" not in v for v in duplicate)

mice = bridge.add_receiver_signal_strength([receiver("Classroom Miracast", protocol=2)], readings)
assert "signalStrength" not in mice[0], "MICE is LAN, not peer P2P"
chromecast = bridge.add_receiver_signal_strength([receiver("Classroom Miracast", protocol=3)], readings)
assert "signalStrength" not in chromecast[0]

# Read-only system D-Bus missing/unavailable -> no fake signal.
with mock.patch.object(bridge, "system_bus", side_effect=bridge.CastError("NM unavailable")):
    assert bridge.p2p_signal_samples() == []

# Real scan JSON remains usable even when the optional NM metric is absent.
discovery = {"type": "aa{sv}", "data": [[
    "uuid", {"type": "s", "data": "real-receiver-uuid"},
    "display-name", {"type": "s", "data": "Classroom Miracast"},
    "protocol", {"type": "u", "data": 1},
    "state", {"type": "u", "data": 0},
]]}
with mock.patch.object(bridge, "ensure_daemon", return_value={"ok": True, "code": "ready"}), \
        mock.patch.object(bridge, "bus", return_value=discovery), \
        mock.patch.object(bridge, "stream_binary_available", return_value=True), \
        mock.patch.object(bridge, "p2p_signal_samples", return_value=readings):
    scan = bridge.scan()
assert scan["ok"] and scan["streamReady"]
assert scan["displays"][0]["signalStrength"] == 82
with mock.patch.object(bridge, "ensure_daemon", return_value={"ok": True, "code": "ready"}), \
        mock.patch.object(bridge, "bus", return_value=discovery), \
        mock.patch.object(bridge, "stream_binary_available", return_value=True), \
        mock.patch.object(bridge, "p2p_signal_samples", return_value=[]):
    scan = bridge.scan()
assert scan["ok"] and "signalStrength" not in scan["displays"][0]

# Stale peer measurements are not re-used as fresh TV signal.
def stale_bus(*args):
    result = measured_bus(*args)
    if result.get("type") == "a{sv}":
        result["data"][0][5]["data"] = now - 240
    return result

with mock.patch.object(bridge, "system_bus", side_effect=stale_bus):
    assert bridge.p2p_signal_samples() == []

qml = (root / "modules/abyss/content/AbyssUtilitiesPopup.qml").read_text()
assert "receiverRow.modelData.signalStrength" in qml
assert "receiverRow.modelData.signalQuality" in qml
assert "receiverRow.modelData.protocolId === 1" in qml
assert 'text: "wifi"' in qml
assert "NetworkDisplays.displays" in qml
assert "NetworkDisplays.connectToSelected()" in qml
assert "NetworkDisplays.disconnect()" in qml
assert "nmcli" not in script.read_text(), "Don't use the router RSSI"
print("CAST_F01_SIGNAL_STRENGTH_PASS: fresh unique Miracast P2P only; unknown hidden")
