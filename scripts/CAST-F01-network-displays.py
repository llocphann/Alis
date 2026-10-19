#!/usr/bin/env python3
"""CAST-F01: GNOME Network Displays user-session D-Bus bridge.

Stdout: exactly one compact JSON response. No shell, sudo, NetworkManager,
firewall, PipeWire or portal configuration changes. Only explicit 'scan'
may launch the user-session GNOME Network Displays daemon if installed.
The system's screencast portal remains responsible for consent/source choice.
"""
import argparse
from collections import Counter
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

BUS = "org.gnome.NetworkDisplays.Manager"
OBJ = "/org/gnome/NetworkDisplays/Manager"
IFACE = BUS
NM_BUS = "org.freedesktop.NetworkManager"
NM_OBJECT = "/org/freedesktop/NetworkManager"
NM_P2P_IFACE = "org.freedesktop.NetworkManager.Device.WifiP2P"
NM_PEER_IFACE = "org.freedesktop.NetworkManager.WifiP2PPeer"
NM_DEVICE_PATH = re.compile(r"^/org/freedesktop/NetworkManager/Devices/[A-Za-z0-9_]+$")
NM_PEER_PATH = re.compile(r"^/org/freedesktop/NetworkManager/[A-Za-z0-9_/-]+$")
UNIT = re.compile(r"^gnome-network-displays-stream-[A-Za-z0-9_.:-]{1,128}\.service$")
IDENTITY = re.compile(r"^[A-Za-z0-9_.:-]{1,128}$")
PROTOCOLS = {0: "Unknown", 1: "Miracast P2P", 2: "Miracast MICE", 3: "Chromecast"}
STATES = {0: "disconnected", 0x50: "firewall", 0x100: "p2p",
          0x110: "socket", 0x120: "buffering",
          0x1000: "streaming", 0x10000: "error"}
DAEMON_PATHS = ("/usr/bin/gnome-network-displays-daemon",
                "/usr/libexec/gnome-network-displays-daemon",
                "/usr/lib/gnome-network-displays/gnome-network-displays-daemon")


class CastError(Exception):
    pass


def run(args, timeout=5):
    try:
        p = subprocess.run(args, text=True, capture_output=True,
                           timeout=timeout, check=False)
    except (FileNotFoundError, OSError, subprocess.TimeoutExpired) as exc:
        raise CastError("Command unavailable or timed out: " + args[0]) from exc
    if p.returncode != 0:
        # Error messages can include identifiers and local network addresses.
        raise CastError(args[0] + " returned an error; check user journal")
    return p.stdout


def bus(*args):
    output = run(["busctl", "--user", "--auto-start=no",
                  "--json=short", *args], timeout=6)
    # A successful D-Bus method with no out args (StopStream) may print no
    # JSON. An empty successful reply is still a valid completion.
    return json.loads(output) if output.strip() else {"type": "", "data": []}


def typed(value, default=None):
    if isinstance(value, dict) and "type" in value and "data" in value:
        data = value["data"]
        # busctl may return a variant as a singleton array of another
        # typed value; unwrap only D-Bus variants, not ordinary arrays.
        if value["type"] == "v":
            if isinstance(data, list) and len(data) == 1:
                data = data[0]
            return typed(data, default)
        return data
    return value if value is not None else default


def dictionary(obj):
    """Parse busctl lossless JSON, including systemd #28711 flat dict arrays."""
    obj = typed(obj)
    if isinstance(obj, dict):
        return {str(k): typed(v) for k, v in obj.items()}
    if not isinstance(obj, list):
        return {}
    # get-property and call may wrap aa{sv} in different outer tuple
    # layers. Unwrap singleton arrays but never substitute an invented sink.
    while len(obj) == 1 and isinstance(obj[0], list):
        obj = obj[0]
    if len(obj) % 2 == 0 and all(isinstance(obj[i], str) for i in range(0, len(obj), 2)):
        return {obj[i]: typed(obj[i + 1]) for i in range(0, len(obj), 2)}
    if all(isinstance(x, list) and len(x) == 2 and isinstance(x[0], str) for x in obj):
        return {x[0]: typed(x[1]) for x in obj}
    return {}


def displays(payload):
    if payload.get("type") not in ("aa{sv}", "v", "(aa{sv})"):
        raise CastError("GNOME Network Displays returned an unexpected D-Bus type")
    items = typed(payload)
    if payload["type"] == "v":
        items = typed(items)
    if not isinstance(items, list):
        raise CastError("GNOME Network Displays returned an invalid display list")
    found = []
    seen = set()
    for entry in items[:80]:
        row = dictionary(entry)
        uid = str(row.get("uuid") or "")
        title = str(row.get("display-name") or "").strip()
        if not IDENTITY.fullmatch(uid) or not title or uid in seen:
            continue
        seen.add(uid)
        try:
            protocol, state = int(row.get("protocol", 0)), int(row.get("state", 0))
        except (ValueError, TypeError):
            protocol, state = 0, 0
        found.append({"uuid": uid, "name": title[:140],
                      "protocol": PROTOCOLS.get(protocol, "Unknown"),
                      "protocolId": protocol,
                      "state": STATES.get(state, "unknown"),
                      "stateCode": state})
    return sorted(found, key=lambda row: (row["name"].lower(), row["uuid"]))


def system_bus(*args):
    """Read-only NetworkManager system D-Bus; never initiate a P2P search."""
    raw = run(["busctl", "--system", "--auto-start=no", "--json=short", *args],
              timeout=3)
    return json.loads(raw)


def object_paths(reply):
    """Extract D-Bus ao paths from the different busctl JSON tuple shapes."""
    if reply.get("type") != "ao":
        return []
    items = typed(reply)
    while isinstance(items, list) and len(items) == 1 and isinstance(items[0], list):
        items = items[0]
    return [p for p in items if isinstance(p, str) and p.startswith("/")] \
        if isinstance(items, list) else []


def p2p_signal_samples():
    """Current NetworkManager P2P peer strengths, never access-point strength.

    Fail closed on any missing/inaccessible system D-Bus API. Do not expose
    MAC addresses, peer object paths or local network information in JSON.
    """
    try:
        device_paths = object_paths(system_bus(
            "call", NM_BUS, NM_OBJECT, NM_BUS, "GetDevices"))
        samples = []
        seen_paths = set()
        for device in device_paths[:24]:
            if not NM_DEVICE_PATH.fullmatch(device):
                continue
            try:
                peers = object_paths(system_bus(
                    "get-property", NM_BUS, device, NM_P2P_IFACE, "Peers"))
            except (CastError, ValueError, TypeError):
                # Other devices (Ethernet, normal Wi-Fi) have no P2P interface.
                continue
            for peer in peers[:32]:
                if not NM_PEER_PATH.fullmatch(peer) or peer in seen_paths:
                    continue
                seen_paths.add(peer)
                try:
                    props = system_bus("call", NM_BUS, peer,
                                       "org.freedesktop.DBus.Properties",
                                       "GetAll", "s", NM_PEER_IFACE)
                    if props.get("type") != "a{sv}":
                        continue
                    row = dictionary(props.get("data"))
                    name = str(row.get("Name") or "").strip().casefold()
                    strength = row.get("Strength")
                    seen = row.get("LastSeen")
                    if not name or isinstance(strength, bool):
                        continue
                    pct = int(strength)
                    last_seen = int(seen)
                    if not (1 <= pct <= 100 and last_seen >= 0):
                        continue
                    # LastSeen is CLOCK_BOOTTIME seconds (not wall time).
                    now = time.clock_gettime(time.CLOCK_BOOTTIME)
                    if not (0 <= now - last_seen <= 180):
                        continue
                    samples.append((name, pct))
                except (CastError, ValueError, TypeError, AttributeError):
                    continue
        return samples
    except (CastError, ValueError, TypeError, AttributeError):
        return []


def add_receiver_signal_strength(receivers, samples):
    """Only annotate an exact, unique, fresh Miracast P2P peer name match.

    The GNOME receiver UUID is randomly generated, NOT the P2P peer MAC.
    Do not assign AP/router strength to Chromecast or Miracast MICE.
    """
    wanted = Counter(str(item.get("name") or "").strip().casefold()
                     for item in receivers if item.get("protocolId") == 1)
    candidates = {}
    for peer_name, strength in samples:
        name = str(peer_name or "").strip().casefold()
        if name and isinstance(strength, int) and not isinstance(strength, bool) \
                and 1 <= strength <= 100:
            candidates.setdefault(name, []).append(strength)
    for item in receivers:
        if item.get("protocolId") != 1:
            continue
        name = str(item.get("name") or "").strip().casefold()
        strengths = candidates.get(name, [])
        if wanted[name] != 1 or len(strengths) != 1:
            continue
        value = strengths[0]
        item["signalStrength"] = value
        item["signalQuality"] = ("Strong" if value >= 75 else
                                 "Good" if value >= 50 else
                                 "Fair" if value >= 30 else "Weak")
    return receivers


def name_owned():
    try:
        out = run(["busctl", "--user", "--no-pager", "--no-legend",
                   "list", "--acquired"], timeout=4)
        return any(line.split()[0] == BUS for line in out.splitlines() if line.strip())
    except CastError:
        return False


def daemon_executable():
    for name in ("gnome-network-displays-daemon",):
        p = shutil.which(name)
        if p:
            return p
    return next((p for p in DAEMON_PATHS if Path(p).is_file()), "")


def ensure_daemon():
    """Start the *user-session* upstream daemon only when Scan is requested.

    Keep failure causes distinct: a missing package is not the same as a
    crashing daemon, broken user D-Bus session or receiver discovery failure.
    """
    if name_owned():
        return {"ok": True, "code": "ready", "message": ""}
    if not shutil.which("busctl"):
        return {"ok": False, "code": "busctl_missing",
                "message": "systemd busctl is unavailable; check the installed systemd package."}
    binary = daemon_executable()
    if not binary:
        return {"ok": False, "code": "daemon_missing",
                "message": "GNOME Network Displays daemon missing. Install version 0.98+ with the daemon enabled, then Scan again."}
    try:
        proc = subprocess.Popen([binary], stdin=subprocess.DEVNULL,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                start_new_session=True, close_fds=True)
    except OSError:
        return {"ok": False, "code": "daemon_launch_failed",
                "message": "Could not launch Network Displays daemon; check executable and user journal."}
    for _ in range(24):
        if name_owned():
            return {"ok": True, "code": "ready", "message": ""}
        if proc.poll() is not None:
            return {"ok": False, "code": "daemon_exited",
                    "message": "Network Displays daemon exited before D-Bus became ready; inspect its user journal."}
        time.sleep(0.25)
    return {"ok": False, "code": "daemon_not_ready",
            "message": "Network Displays daemon started but did not publish its D-Bus service; check session bus and user journal."}


def scan():
    readiness = ensure_daemon()
    if not readiness["ok"]:
        return {"ok": False, "backend": False, "streamReady": False,
                "code": readiness["code"], "displays": [],
                "message": readiness["message"]}
    try:
        p = bus("get-property", BUS, OBJ, IFACE, "Displays")
        installed = stream_binary_available()
        receivers = displays(p)
        if any(device["protocolId"] == 1 for device in receivers):
            add_receiver_signal_strength(receivers, p2p_signal_samples())
        return {"ok": True, "backend": True, "streamReady": installed,
                "code": "ready" if installed else "stream_helper_missing",
                "displays": receivers, "message": "" if installed else
                "TV discovery works, but /usr/libexec/gnome-network-displays-stream is missing. Rebuild the native package or use Open app."}
    except (CastError, ValueError, json.JSONDecodeError):
        return {"ok": False, "backend": True, "streamReady": False,
                "code": "dbus_property_error", "displays": [],
                "message": "Network Displays is running, but reading Displays failed. Inspect the installed daemon version and session D-Bus."}


def valid_unit(value):
    return bool(UNIT.fullmatch(value or ""))


def stream_binary_available():
    # Upstream nd-systemd-helpers.c builds ExecStart with this *exact*
    # absolute location. A package installed under /usr/lib or with
    # build_daemon=false may support discovery but not native connect.
    return Path("/usr/libexec/gnome-network-displays-stream").is_file()


def start(uid):
    if not IDENTITY.fullmatch(uid or ""):
        raise CastError("Invalid TV identifier")
    if not stream_binary_available():
        raise CastError("Network Displays streaming helper missing at upstream libexec path")
    # A receiver must be in the actual current device list, never an
    # unchecked ID from the UI or an issue/comment.
    available = scan()
    if not available["ok"] or uid not in {d["uuid"] for d in available["displays"]}:
        raise CastError("TV is not in the current discovery list")
    reply = bus("call", BUS, OBJ, IFACE, "StartStream", "s", uid)
    data = typed(reply)
    unit = data[0] if isinstance(data, list) and len(data) == 1 else None
    if reply.get("type") != "s" or not isinstance(unit, str) or not valid_unit(unit):
        raise CastError("TV backend did not return a valid stream service")
    return {"ok": True, "unit": unit, "message": "Connecting; choose a source in the system screen-share dialog."}


def status(unit):
    if not valid_unit(unit):
        raise CastError("Invalid stream service")
    try:
        output = run(["systemctl", "--user", "show", "--no-pager",
                      "--property=ActiveState", "--property=SubState",
                      "--property=Result", unit], timeout=4)
        values = dict(line.split("=", 1) for line in output.splitlines() if "=" in line)
    except CastError:
        return {"ok": False, "state": "unknown", "message": "Unable to inspect stream service"}
    active = values.get("ActiveState", "unknown")
    sub = values.get("SubState", "unknown")
    return {"ok": active in ("active", "activating"), "state": active,
            "subState": sub, "result": values.get("Result", ""),
            "message": "Stream process active; verify TV picture and sound."
            if active == "active" else "TV stream is not active."}


def stop(unit):
    if not valid_unit(unit):
        raise CastError("Invalid stream service")
    # Only stop a GNOME Network Displays service matching our strict prefix.
    bus("call", BUS, OBJ, IFACE, "StopStream", "s", unit)
    return {"ok": True, "message": "TV disconnect requested."}


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("scan", "start", "status", "stop", "probe"))
    parser.add_argument("argument", nargs="?", default="")
    args = parser.parse_args(argv)
    try:
        if args.action == "scan":
            response = scan()
        elif args.action == "probe":
            running = name_owned()
            daemon = bool(daemon_executable())
            response = {"ok": running, "backend": running,
                        "daemonInstalled": daemon,
                        "appInstalled": bool(shutil.which("gnome-network-displays")),
                        "streamReady": stream_binary_available(),
                        "code": "ready" if running else
                            "daemon_not_running" if daemon else "daemon_missing",
                        "message": "D-Bus manager running" if running else
                            "Daemon installed, but not running" if daemon else
                            "GNOME Network Displays daemon is not installed"}
        elif args.action == "start":
            response = start(args.argument)
        elif args.action == "status":
            response = status(args.argument)
        else:
            response = stop(args.argument)
    except (CastError, ValueError, json.JSONDecodeError):
        response = {"ok": False, "message": "TV operation failed; check user journal."}
    print(json.dumps(response, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
