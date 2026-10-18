#!/usr/bin/env python3
"""Guard Hadalis's Obsidian Settings wrapper after real owner width=0 report.

The parent settings page is a ColumnLayout. A plain Item child must explicitly
participate in width negotiation. Otherwise its deferred Hadalird child can
have positive implicitHeight with zero paint width, producing a blank page.
This is a source regression only; native Niri geometry still needs acceptance.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
theme = (root / "modules/settings/ObsidianThemeSettings.qml").read_text()
todo = (root / "modules/settings/ObsidianTodoSettings.qml").read_text()
page = (root / "modules/settings/IntegrationsConfig.qml").read_text()

for name, source in (("Theme", theme), ("Todo", todo)):
    assert "import QtQuick.Layouts" in source, f"{name}: missing layouts import"
    assert re.search(r"\bLayout\.fillWidth\s*:\s*true\b", source), (
        f"{name}: must fill parent ColumnLayout width")
    assert re.search(r"\bLoader\s*\{[\s\S]*?\bwidth\s*:\s*parent\.width", source), (
        f"{name}: deferred package loader lost wrapper width")
    assert "implicitHeight:" in source, f"{name}: cannot size page height"
    assert "Hadalird.obsidianEnabled" in source, f"{name}: lost opt-in gate"

assert 'objectName: "integrationPluginSettings"' in page
assert 'Layout.fillWidth: true' in page and 'Layout.preferredHeight: item?.implicitHeight ?? 0' in page
assert 'Hadalird.pluginEnabled(root.activePlugin)' in page
assert "Hadalird.systemProvisionerAvailable" in page, (
    "Privileged helper button must report the absent Hadalis system gateway")
print("HADALIRD_OBSIDIAN_WRAPPER_PASS both deferred cards fill page width; optional helper precondition visible")
