#!/usr/bin/python3
"""CAST-F01 integration smoke test with a *real* isolated session D-Bus.

Always creates its own private bus, including canonical-validator invocations.
Publishes two fake receiver properties on a private temporary bus and calls
the real CAST-F01 bridge, which in turn executes real busctl --json=short.
No TV/network/user services are accessed, and no system config is modified.
"""
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
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


def run_fixture(address):
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.bus.BusConnection(address)
    service = FakeManager(bus)
    environment = dict(os.environ, DBUS_SESSION_BUS_ADDRESS=address)

    loop = GLib.MainLoop()
    failures = []

    def check():
        try:
            run_check()
        except Exception as exc:
            failures.append(str(exc))
        finally:
            GLib.idle_add(loop.quit)

    def run_check():
        direct = subprocess.run([
            "busctl", "--user", "--auto-start=no", "--json=short",
            "get-property", BUS, PATH, BUS, "Displays",
        ], env=environment, capture_output=True, text=True, timeout=6, check=True)
        decoded = json.loads(direct.stdout)
        assert decoded["type"] == "aa{sv}", direct.stdout

        bridge = subprocess.run([
            sys.executable, str(ROOT / "scripts/CAST-F01-network-displays.py"),
            "scan",
        ], env=environment, capture_output=True, text=True, timeout=8, check=True)
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

    # The D-Bus service needs its GLib main loop available while busctl waits
    # for Get/Properties replies: do *not* block it inside an idle callback.
    GLib.idle_add(lambda: threading.Thread(target=check, daemon=True).start() or False)
    loop.run()
    if failures:
        raise AssertionError(failures[0])


def main():
    # Do not trust an inherited session address or an opt-in flag: even when
    # invoked directly, fake receivers belong exclusively to this subprocess.
    with tempfile.TemporaryDirectory(prefix="alis-cast-test-bus-") as directory:
        socket = Path(directory) / "bus"
        address = "unix:path=" + str(socket)
        daemon = subprocess.Popen([
            "dbus-daemon", "--session", "--nofork", "--nopidfile",
            "--address=" + address,
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 4
            while not socket.is_socket():
                if daemon.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError("Private fixture bus did not start")
                time.sleep(0.02)
            run_fixture(address)
        finally:
            if daemon.poll() is None:
                daemon.terminate()
                try:
                    daemon.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    daemon.kill()
                    daemon.wait(timeout=3)


if __name__ == "__main__":
    main()
