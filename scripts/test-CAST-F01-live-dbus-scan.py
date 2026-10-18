#!/usr/bin/python3
"""CAST-F01 integration smoke test with a *real* isolated session D-Bus.

Only for CI: run under dbus-run-session with system Python/dbus-python + GLib.
Publishes two fake receiver properties on a private temporary bus and calls
the real CAST-F01 bridge, which in turn executes real busctl --json=short.
No TV/network/user services are accessed, and no system config is modified.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

ROOT = Path(__file__).resolve().parents[1]
BUS = "org.gnome.NetworkDisplays.Manager"
PATH = "/org/gnome/NetworkDisplays/Manager"


class FakeManager(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(dbus.service.BusName(BUS, bus=bus), PATH)

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, interface, prop):
        if interface != BUS or prop != "Displays":
            raise dbus.exceptions.DBusException("Unknown property")
        receivers = [
            dbus.Dictionary({
                "uuid": dbus.String("dummy-miracast-001"),
                "display-name": dbus.String("Preflight Classroom TV"),
                "protocol": dbus.UInt32(1),
                "state": dbus.UInt32(0),
                "priority": dbus.UInt32(10),
            }, signature="sv"),
            dbus.Dictionary({
                "uuid": dbus.String("dummy-chromecast-002"),
                "display-name": dbus.String("Preflight Chromecast"),
                "protocol": dbus.UInt32(3),
                "state": dbus.UInt32(0),
                "priority": dbus.UInt32(5),
            }, signature="sv"),
        ]
        # dbus-python must marshal an aa{sv} inside a D-Bus variant.
        return dbus.Array(receivers, signature="a{sv}", variant_level=1)


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    service = FakeManager(bus)

    def check():
        direct = subprocess.run([
            "busctl", "--user", "--auto-start=no", "--json=short",
            "get-property", BUS, PATH, BUS, "Displays",
        ], capture_output=True, text=True, timeout=6, check=True)
        decoded = json.loads(direct.stdout)
        assert decoded["type"] == "aa{sv}", direct.stdout

        bridge = subprocess.run([
            sys.executable, str(ROOT / "scripts/CAST-F01-network-displays.py"),
            "scan",
        ], capture_output=True, text=True, timeout=8, check=True)
        result = json.loads(bridge.stdout)
        assert result["ok"] and result["backend"], result
        assert [r["name"] for r in result["displays"]] == [
            "Preflight Chromecast", "Preflight Classroom TV",
        ], result
        assert [r["protocol"] for r in result["displays"]] == [
            "Chromecast", "Miracast P2P",
        ], result
        print("CAST_F01_REAL_DBUS_SCAN_PASS: busctl JSON + live bus + real bridge")
        return False

    GLib.idle_add(check)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
