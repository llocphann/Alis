#!/usr/bin/env python3
"""Guard the QML layout contract that lets Settings page 38 load.

Qt Quick Flow's implicitHeight is a read-only, layout-computed property.
Assigning it fails QML component creation before the page can be shown.
This source-scope guard runs in CI when the native Niri/QML host is absent;
live SettingsPageHost instantiation remains the separate native acceptance.
"""
from pathlib import Path
import re

PAGE = Path(__file__).resolve().parents[1] / "modules/settings/IntegrationsConfig.qml"
qml = PAGE.read_text(encoding="utf-8")
flows = list(re.finditer(r"\bFlow\s*\{", qml))
assert len(flows) == 1, f"expected one package action flow, got {len(flows)}"


def flow_sections(begin):
    """Extract an outer Flow's bindings separately from its nested buttons."""
    depth = 1
    root = []
    complete = []
    quote = False
    escaped = False
    for char in qml[begin:]:
        if quote:
            if depth == 1:
                root.append(" ")
            complete.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quote = False
            continue
        if char == '"':
            quote = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                break
        complete.append(char)
        if depth == 1:
            root.append(char)
    assert depth == 0, "unclosed Flow body"
    return "".join(root), "".join(complete)


for i, match in enumerate(flows):
    outer, inside = flow_sections(match.end())
    assert re.search(r"\bLayout\.fillWidth\s*:\s*true\b", outer), (
        f"Flow #{i + 1} lost managed layout width"
    )
    assert re.search(r"\bspacing\s*:", outer), f"Flow #{i + 1} lost spacing"
    assert not re.search(r"\bimplicitHeight\s*:", outer), (
        f"Flow #{i + 1} writes Qt's read-only implicitHeight"
    )
    assert not re.search(r"\bwidth\s*:\s*parent\.width\b", outer), (
        f"Flow #{i + 1} bypasses Layout width management"
    )
    expected = "Install Alis-Intergration"
    assert expected in inside, f"Flow #{i + 1} changed roles or was emptied"

assert '"Refresh"' in qml
assert 'Hadalird.refreshSystemStatus()' in qml
assert '"Check status"' not in qml
assert 'Reinstall helpers' not in qml and 'Install gateway' not in qml
assert './setup integrations' in qml
assert 'Hadalird.manage("helpers-' not in qml and 'Hadalird.manage("gateway-' not in qml
assert 'root.primaryTabs' in qml and 'integrationCapabilityTabs' in qml
assert "settingsPageIndex: 38" in qml
print("HADALIRD_SETTINGS_FLOW_PASS all package, helper and gateway flows use Qt-safe layouts")
