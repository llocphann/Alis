#!/usr/bin/env python3
"""Contract guard for the append-only Todo backend configuration schema."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
config_qml = (ROOT / "modules" / "common" / "Config.qml").read_text(encoding="utf-8")
defaults = json.loads((ROOT / "defaults" / "config.json").read_text(encoding="utf-8"))

required_qml = [
    "property JsonObject todo: JsonObject {",
    'property string backend: "internal"',
    "property JsonObject obsidian: JsonObject {",
    'property string vaultPath: ""',
    'property string sourceMode: "markdown-note"',
    'property string notePath: "Alis/Todo.md"',
    'property string scope: "managed-section"',
    "property JsonObject dailyNote: JsonObject {",
    'property string folder: "00_Capture/01_Journal"',
    'property string format: "YYYY/MMMM/DD-MM-YYYY-dddd"',
    'property string plannerHeading: "Tasks"',
    "property int plannerHeadingLevel: 2",
    "property int defaultDurationMinutes: 30",
    "property bool preferTasksPlugin: true",
    "property bool allowBasicOfflineMutation: true",
]
for snippet in required_qml:
    assert snippet in config_qml, f"Todo config schema lost: {snippet}"

expected = {
    "backend": "internal",
    "obsidian": {
        "vaultPath": "",
        "sourceMode": "markdown-note",
        "notePath": "Alis/Todo.md",
        "scope": "managed-section",
        "dailyNote": {
            "folder": "00_Capture/01_Journal",
            "format": "YYYY/MMMM/DD-MM-YYYY-dddd",
            "plannerHeading": "Tasks",
            "plannerHeadingLevel": 2,
            "defaultDurationMinutes": 30,
        },
        "preferTasksPlugin": True,
        "allowBasicOfflineMutation": True,
    },
}
assert defaults.get("todo") == expected, "defaults/config.json Todo defaults drifted"
assert defaults["todo"]["backend"] == "internal", "Obsidian must remain opt-in"

print("Todo backend config schema contract: PASS")
