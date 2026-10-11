#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
text = (root / "modules/abyss/AbyssEdgeEditor.qml").read_text()

required = [
    'property string toolbarEdge: "bottom"',
    "function toolbarEdgeScore(edge): real",
    "function bestToolbarEdge(): string",
    "function scheduleToolbarRelocation(): void",
    "function relocateToolbar(): void",
    "score += 220",
    "onEditingEdgeChanged: root.scheduleToolbarRelocation()",
    "id: toolbarRelocate",
    "interval: 90",
    "edge: root.toolbarEdge",
    "root.toolbarOnHorizontalEdge",
]
for needle in required:
    assert needle in text, needle

# Draft change also records Undo now. Retain the relocation call contract
# without requiring the signal handler to contain only one statement.
assert re.search(r"onDraftChanged\s*:\s*(?:\{[^}]*?root\.|root\.)scheduleToolbarRelocation\(\)",text)

assert 'edge: "bottom"; identity: "edgeEditor"' not in text
print("abyss edge editor toolbar relocation contract: ok")
