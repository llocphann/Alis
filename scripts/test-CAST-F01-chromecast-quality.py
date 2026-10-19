#!/usr/bin/env python3
"""CAST-F01 Chromecast Connection Quality: measured LAN handshake only, no TV used."""
from pathlib import Path
from unittest import mock
import importlib.util
import socket

repo = Path(__file__).resolve().parents[1]
script = repo / "scripts/CAST-F01-network-displays.py"
spec = importlib.util.spec_from_file_location("cast_f01_quality", script)
cast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cast)

def receiver(name="KD-49X7500F", uuid="cast-uuid", protocol=3):
    return {"name": name, "uuid": uuid, "protocolId": protocol,
            "protocol": "Chromecast" if protocol == 3 else "Miracast P2P"}

# Actual avahi-browse -rtpk _googlecast._tcp output (resolved entries start '=')
browse = r'''
+;wlan0;IPv4;Chromecast-c42;_googlecast._tcp;local
=;wlan0;IPv4;Chromecast-c42;_googlecast._tcp;local;sony-tv.local;192.168.1.44;8009;"md=Google Cast" "id=c42" "fn=KD-49X7500F" "ca=1"
=;wlan0;IPv6;Chromecast-c42;_googlecast._tcp;local;sony-tv.local;fe80::ca9;8009;"fn=KD-49X7500F"
=;wlan0;IPv4;Unrelated TV;_googlecast._tcp;local;unrelated.local;192.168.1.25;8009;"fn=Neighbour TV"
'''
samples = cast.cast_mdns_records(browse)
assert ("kd-49x7500f", "192.168.1.44", 8009) in samples
assert len(samples) == 2, samples

# Strict LAN and Cast-port filtering; no arbitrary internet/loopback endpoint.
bad = '''
=;eth0;IPv4;evil;_googlecast._tcp;local;evil.local;8.8.8.8;8009;"fn=KD-49X7500F"
=;eth0;IPv4;evil;_googlecast._tcp;local;evil.local;127.0.0.1;8009;"fn=KD-49X7500F"
=;eth0;IPv4;evil;_googlecast._tcp;local;evil.local;192.168.1.44;22;"fn=KD-49X7500F"
=;eth0;IPv4;evil;_googlecast._tcp;remote;evil.local;192.168.1.44;8009;"fn=KD-49X7500F"
=;eth0;IPv4;evil;_http._tcp;local;evil.local;192.168.1.44;8009;"fn=KD-49X7500F"
=;eth0;IPv4;evil;_googlecast._tcp;local;evil.local;192.168.1.44;8009;"fn=x" "fn=y"
'''
assert cast.cast_mdns_records(bad) == []

# Duplicated IPv4 + interface entries for the same endpoint are deduplicated.
twice = browse + browse
assert cast.cast_mdns_records(twice) == samples

calls = []
def fake_probe(addr, port):
    calls.append((addr, port))
    return 17

result = cast.add_chromecast_connection_quality(
    [receiver(), receiver("Neighbour TV", uuid="other")], samples, fake_probe)
assert result[0]["connectionLatencyMs"] == 17
assert result[0]["connectionQuality"] == "Responsive"
assert calls == [("192.168.1.44", 8009), ("192.168.1.25", 8009)]

for latency, quality in [
    (1, "Responsive"), (30, "Responsive"), (31, "Moderate"),
    (100, "Moderate"), (101, "Slow"), (500, "Slow")
]:
    results = cast.add_chromecast_connection_quality(
        [receiver()], samples, lambda addr, port: latency)
    assert results[0]["connectionQuality"] == quality
    assert results[0]["connectionLatencyMs"] == latency

for measurement in (None, 0, False, -1, 2001, "12"):
    results = cast.add_chromecast_connection_quality(
        [receiver()], samples, lambda addr, port: measurement)
    assert "connectionLatencyMs" not in results[0]

# Unmatched/missing Avahi data must not leak a guessed quality or affect TV list.
assert "connectionQuality" not in cast.add_chromecast_connection_quality(
    [receiver()], [], fake_probe)[0]
assert "connectionQuality" not in cast.add_chromecast_connection_quality(
    [receiver(name="Another TV")], samples, fake_probe)[0]

# Same friendly name points to two devices; do not pick an arbitrary IP.
two_ips = samples + [("kd-49x7500f", "192.168.1.77", 8009)]
assert "connectionQuality" not in cast.add_chromecast_connection_quality(
    [receiver()], two_ips, fake_probe)[0]

# Two GNOME receivers share one name: do not assign one probe to both.
duplicates = cast.add_chromecast_connection_quality(
    [receiver(uuid="a"), receiver(uuid="b")], samples, fake_probe)
assert all("connectionQuality" not in d for d in duplicates)

# Miracast P2P/MICE aren't LAN Chromecast: no quality badge or probes.
calls.clear()
result = cast.add_chromecast_connection_quality([
    receiver(protocol=1), receiver(protocol=2)], samples, fake_probe)
assert calls == [] and all("connectionQuality" not in d for d in result)

# One explicit Scan may contact no more than four unique advertised TVs.
lots = [receiver(name=f"TV {i}", uuid=f"uuid{i}") for i in range(10)]
endpoints = [(f"tv {i}", f"192.168.1.{i + 20}", 8009) for i in range(10)]
calls.clear()
cast.add_chromecast_connection_quality(lots, endpoints, fake_probe)
assert len(calls) == 4

# Optional avahi-utils command absence/failure is safe.
with mock.patch.object(cast.shutil, "which", return_value=None):
    assert cast.cast_mdns_samples() == []
with mock.patch.object(cast.shutil, "which", return_value="/usr/bin/avahi-browse"), \
     mock.patch.object(cast, "run", side_effect=cast.CastError("Avahi unavailable")):
    assert cast.cast_mdns_samples() == []
with mock.patch.object(cast.shutil, "which", return_value="/usr/bin/avahi-browse"), \
     mock.patch.object(cast, "run", return_value=browse) as cli:
    assert cast.cast_mdns_samples() == samples
    assert cli.call_args.args[0] == ["avahi-browse", "-rtpk", "_googlecast._tcp"]
    assert cli.call_args.kwargs["timeout"] <= 4

class DummySocket:
    closed = False
    def close(self):
        self.closed = True

fake_sock = DummySocket()
with mock.patch.object(cast.time, "monotonic", side_effect=[100, 100.021]):
    assert cast.cast_tcp_probe(
        "192.168.1.44", 8009, lambda address, timeout: fake_sock) == 21
assert fake_sock.closed
def unavailable(address, timeout):
    raise OSError("Connection refused")
assert cast.cast_tcp_probe("192.168.1.44", 8009, unavailable) is None

# Integration: GNOME native scan still succeeds even if mDNS query unavailable.
payload = {"type": "aa{sv}", "data": [[
    "uuid", {"type": "s", "data": "cc-uuid"},
    "display-name", {"type": "s", "data": "KD-49X7500F"},
    "protocol", {"type": "u", "data": 3},
    "state", {"type": "u", "data": 0},
]]}
with mock.patch.object(cast, "ensure_daemon",
                       return_value={"ok": True, "code": "ready"}), \
     mock.patch.object(cast, "bus", return_value=payload), \
     mock.patch.object(cast, "stream_binary_available", return_value=True), \
     mock.patch.object(cast, "cast_mdns_samples", return_value=samples), \
     mock.patch.object(cast, "cast_tcp_probe", return_value=24):
    scan = cast.scan()
assert scan["ok"] and scan["streamReady"]
assert scan["displays"][0]["connectionQuality"] == "Responsive"
assert scan["displays"][0]["connectionLatencyMs"] == 24
with mock.patch.object(cast, "ensure_daemon",
                       return_value={"ok": True, "code": "ready"}), \
     mock.patch.object(cast, "bus", return_value=payload), \
     mock.patch.object(cast, "stream_binary_available", return_value=True), \
     mock.patch.object(cast, "cast_mdns_samples", return_value=[]):
    scan = cast.scan()
assert scan["ok"] and "connectionQuality" not in scan["displays"][0]

qml = (repo / "modules/abyss/content/AbyssUtilitiesPopup.qml").read_text()
assert "receiverRow.modelData.connectionLatencyMs" in qml
assert "receiverRow.modelData.connectionQuality" in qml
assert "Quality unavailable" in qml
assert "receiverRow.modelData.protocolId === 3" in qml
assert "NetworkDisplays.connectToSelected()" in qml
assert "NetworkDisplays.disconnect()" in qml

print("CAST_F01_CHROMECAST_QUALITY_PASS: unique mDNS, bounded LAN RTT, truthful unknown UI")
