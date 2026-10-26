#!/usr/bin/env python3
"""Source-verified late activation and IPC diagnostic guard for Alis-Companion output.

Does not launch or alter the owner's active desktop. The owner still needs
to confirm Loader state and visual output after update/restart on hardware.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
surface = (root / "modules/abyss/AlisCompanionSurface.qml").read_text(encoding="utf-8")
host = (root / "services/AlisCompanion.qml").read_text(encoding="utf-8")
upstream = root / "sdata/companion-revision.txt"

assert upstream.is_file() and len(upstream.read_text().strip()) == 40
assert "readonly property var session: AlisCompanion.session" in surface
assert "active: root.session !== null" in surface
assert "function ensureOutputSource(): void" in surface
assert "status===Loader.Null" in surface, "never override an existing ready/loading/error instance"
assert 'String(source).length===0' in surface, "do not duplicate a configured source"
assert "setSource(AlisCompanion.outputSource,{adapter:root})" in surface, (
    "must supply the external QML component's required adapter on first load"
)
assert re.search(r"onActiveChanged:\s*\{\s*if \(active\) ensureOutputSource\(\)"
                 r"\s*else source=\"\"", surface), "session toggles must load/unload safely"
assert "Component.onCompleted: ensureOutputSource()" in surface, (
    "late-created outputs may start active, skipping the active-changed handler"
)
assert re.search(r"if \(extension\) return extension.status\(\)", surface), (
    "the full loaded-output diagnostics must remain unmodified"
)
assert "sourceSet:String(outputLoader.source).length>0" in surface
assert "sessionReady:root.session!==null" in surface
assert 'state:state,active:outputLoader.active' in surface
assert 'outputLoader.status===Loader.Loading' in surface
assert 'outputLoader.status===Loader.Error' in surface
assert 'console.warn("[Alis-Companion] QML output loader failed:"' in surface
assert "AlisCompanion.failLoad()" in surface, "real load errors must remain fail-closed"
assert "function status(): string" in host and "JSON.parse(session.status())" in host, (
    "the bounded per-output loader diagnostics must be visible via live IPC status"
)
print("PASS: late-created Companion output gets required adapter source; "
      "pending/error loader state is exposed without changing healthy output status")
