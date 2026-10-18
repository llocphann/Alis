#!/usr/bin/env python3
"""CAST-F01 read-only local capability report (no installs, changes or service restarts).

Usage: python3 scripts/CAST-F01-capability-probe.py
Run ONLY on an Owner-authorized local desktop session. Stdout is compact JSON.
TV serials, Wi-Fi SSIDs, MACs, process lists and network credentials are omitted.
"""
import json
import re
import shutil
import subprocess
from pathlib import Path


def command(args, timeout=3):
    """A strictly read-only executable call with a bounded lifetime."""
    if not shutil.which(args[0]):
        return {"available": False, "ok": False, "output": ""}
    try:
        result = subprocess.run(
            args, capture_output=True, text=True, timeout=timeout, check=False
        )
        return {
            "available": True,
            "ok": result.returncode == 0,
            "output": result.stdout[:120000],
        }
    except (OSError, subprocess.TimeoutExpired):
        return {"available": True, "ok": False, "output": ""}


def output_summary(raw):
    """Never include Niri output serial numbers in this diagnostic."""
    try:
        data = json.loads(raw)
    except (TypeError, ValueError):
        return []
    if not isinstance(data, dict):
        return []
    result = []
    for name, info in sorted(data.items()):
        if not isinstance(info, dict):
            continue
        result.append({
            "connector": str(name)[:80],
            "manufacturer": str(info.get("make") or "")[:80],
            "model": str(info.get("model") or "")[:80],
            "active": bool(info.get("logical")),
        })
    return result


def main():
    bins = [
        "niri", "wl-mirror", "wpctl", "nmcli", "iw", "busctl",
        "gnome-network-displays", "gnome-network-displays-daemon",
        "gnome-network-displays-stream", "gst-inspect-1.0",
    ]
    installed = {name: shutil.which(name) is not None for name in bins}
    # Daemon stream binaries are often installed in libexec rather than PATH.
    stream_path = Path("/usr/libexec/gnome-network-displays-stream")
    installed["network_displays_stream_libexec"] = stream_path.is_file()
    installed["network_displays_daemon_libexec"] = Path(
        "/usr/libexec/gnome-network-displays-daemon"
    ).is_file()

    niri = command(["niri", "msg", "-j", "outputs"])
    bus = command(["busctl", "--user", "--no-pager", "--no-legend", "list"])
    iw = command(["iw", "list"])
    wire = command(["wpctl", "--version"])
    nm = command(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device", "status"])
    services = {
        service: command(["systemctl", "--user", "is-active", service])["ok"]
        for service in (
            "pipewire.service", "wireplumber.service",
            "xdg-desktop-portal.service", "xdg-desktop-portal-gnome.service",
        )
    }
    codecs = {
        codec: command(["gst-inspect-1.0", codec])["ok"]
        for codec in ("x264enc", "openh264enc", "vah264enc", "avenc_aac", "fdkaacenc")
    }
    report = {
        "schema": "alis.cast-f01.capabilities.v1",
        "read_only": True,
        "installed": installed,
        "niri_outputs": output_summary(niri["output"]),
        "session_manager": {
            "network_displays_dbus_name_owned": any(
                line.split(maxsplit=1)[0] == "org.gnome.NetworkDisplays.Manager"
                for line in bus["output"].splitlines() if line.strip()
            ),
            "services_active": services,
        },
        "wireless": {
            "networkmanager_available": nm["ok"],
            # Hints only: this does NOT establish concurrent P2P + STA support.
            "wifi_p2p_client_advertised": bool(
                re.search(r"\\bP2P-client\\b", iw["output"])
            ),
            "wifi_p2p_group_owner_advertised": bool(
                re.search(r"\\bP2P-GO\\b", iw["output"])
            ),
            "p2p_concurrent_connectivity": "NOT_TESTED",
        },
        "audio": {
            "wireplumber_version": wire["output"].strip()[:100] if wire["ok"] else "",
            "sound_routing": "NOT_TESTED",
        },
        "video_audio_encoders": codecs,
        "tv_picture_and_sound": "NOT_TESTED",
    }
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
