#!/usr/bin/env python3
"""CAST-F01 G0 probe unit checks; no local desktop or device required."""
import ast
import json
import runpy
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
path = repo / "scripts/CAST-F01-capability-probe.py"
text = path.read_text(encoding="utf-8")
ast.parse(text)
api = runpy.run_path(str(path))
fake = json.dumps({
    "HDMI-A-1": {
        "make": "Acme TV", "model": "Classroom Display",
        "serial": "PRIVATE-DEVICE-SERIAL",
        "logical": {"x": 1920, "y": 0},
    },
    "eDP-1": {"logical": None, "serial": "PRIVATE-LAPTOP-SERIAL"},
})
summary = api["output_summary"](fake)
assert len(summary) == 2
assert summary[0]["connector"] == "HDMI-A-1"
assert summary[0]["active"] is True
assert summary[1]["active"] is False
assert "PRIVATE" not in json.dumps(summary)
assert api["output_summary"]("not-json") == []
assert api["output_summary"]("[]") == []

# No sudo, root, network mutation, installation or restart in invoked commands.
assert '["niri", "msg", "-j", "outputs"]' in text
assert '"is-active", service' in text
assert '["busctl", "--user", "--no-pager", "--no-legend", "list"]' in text
assert '["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device", "status"]' in text
assert 'subprocess.run(' in text
assert 'timeout=timeout' in text
for command in ('"systemctl", "--user", "restart"', '"nmcli", "connection", "modify"',
                '"wpctl", "set-default"', '"sudo"', '"pacman", "-S"', '"modprobe"'):
    assert command not in text, command
print("CAST_F01_CAPABILITY_PROBE_PASS: safe read-only inventory and serial redaction")
