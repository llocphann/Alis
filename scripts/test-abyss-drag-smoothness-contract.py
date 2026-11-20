#!/usr/bin/env python3
"""Contract check ensuring zero-stutter drag smoothing & Wayland input throttling in Abyss."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
editor = (ROOT / "modules" / "abyss" / "AbyssEdgeEditor.qml").read_text()
bar = (ROOT / "modules" / "abyss" / "bar" / "AbyssBar.qml").read_text()

# 1. AbyssEdgeEditor frame-coalesced VSync drag pump & toolbar freeze during drag
for needle in (
    "property var _pendingPointerDrag: null",
    "FrameAnimation {",
    "id: dragFramePump",
    "function _flushPendingPointerDrag(): void",
    "root._pendingPointerDrag = {",
    "if (root._dragging)\n            return",
    "root._flushPendingPointerDrag()",
    "objectName: \"abyssLayoutRuler\"",
    "function autoAlign(mode: string): void",
):
    assert needle in editor, f"AbyssEdgeEditor missing smooth-drag/ruler contract: {needle}"

# 2. AbyssBar eliminates per-frame inputRegion commits, JSON.stringify churn, and duplicate localSurfaces
for needle in (
    "if (root.editing)\n                    return",
    "onEditingChanged:",
    "modules.itemAt(i)?.invalidateInputRegion()",
    "root.editing ? deformations : Layout.localSurfaces",
    "Easing.OutQuad",
    "root.draggedIds.length > 0",
):
    assert needle in bar, f"AbyssBar missing zero-stutter contract: {needle}"

assert "JSON.stringify" not in bar, "AbyssBar hot path must not allocate JSON.stringify per frame"

print("ABYSS_DRAG_SMOOTHNESS_CONTRACT_PASS")
