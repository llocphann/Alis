#!/usr/bin/env python3
"""Contract guard for concise Settings copy and shared base surface color."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
README = (ROOT / "README.md").read_text(encoding="utf-8")
INTEGRATIONS = (ROOT / "modules" / "settings" / "IntegrationsConfig.qml").read_text(encoding="utf-8")
OBSIDIAN = (ROOT / "modules" / "settings" / "ObsidianThemeSettings.qml").read_text(encoding="utf-8")
SERVICES = (ROOT / "modules" / "settings" / "ServicesConfig.qml").read_text(encoding="utf-8")
OVERLAY = (ROOT / "modules" / "settings" / "SettingsOverlay.qml").read_text(encoding="utf-8")
FOCUS = (ROOT / "modules" / "settings" / "SettingsFocus.qml").read_text(encoding="utf-8")
MODULES = (ROOT / "modules" / "settings" / "ModulesConfig.qml").read_text(encoding="utf-8")
WINDOW = (ROOT / "settings.qml").read_text(encoding="utf-8")
SCREEN_EDGE = (ROOT / "modules" / "screenCorners" / "ScreenEdges.qml").read_text(encoding="utf-8")
BAR = (ROOT / "modules" / "bar" / "BarContent.qml").read_text(encoding="utf-8")

assert "Settings copy stays terse." in README
assert "only a few words or one short clause" in README
assert "paragraph-length explanation" in README

# Hadalird tests its owned vault labels/help and native field behavior. Core
# must retain the disabled-by-default wrapper instead of a duplicate editor.
assert 'active: Hadalird.obsidianEnabled' in OBSIDIAN
assert 'source: Hadalird.settingsSource("obsidian")' in OBSIDIAN

overlay_start = OVERLAY.index("id: overlayContentContainer")
overlay_end = OVERLAY.index("// ── Page header", overlay_start)
overlay_content = OVERLAY[overlay_start:overlay_end]
assert 'color: "transparent"' in overlay_content
assert "Appearance.colors.colLayer0" not in overlay_content
assert "colSurfaceContainerLow" not in overlay_content

assert 'color: "transparent"' in WINDOW
window_surface_start = WINDOW.index("id: windowBaseSurface")
window_surface_end = WINDOW.index("Shortcut {", window_surface_start)
window_surface = WINDOW[window_surface_start:window_surface_end]
assert 'color: root.uiReady ? Appearance.colors.colLayer0 : "transparent"' in window_surface

window_start = WINDOW.index("id: contentContainer")
window_end = WINDOW.index("// ── Page header", window_start)
window_content = WINDOW[window_start:window_end]
assert 'color: "transparent"' in window_content
assert "Appearance.colors.colLayer0" not in window_content
assert "colSurfaceContainerLow" not in window_content

# Source-of-truth comparison: physical Screen Edge and normal ii Bar use the
# same Material base token that Settings now uses.
assert ": Appearance.colors.colLayer0" in SCREEN_EDGE
assert "return Appearance.colors.colLayer0" in BAR

# The connected surface owns colLayer0 exactly once; inner content must not
# repaint it because colLayer0 may carry global transparency.
overlay_surface_start = OVERLAY.index("id: settingsCard")
overlay_surface_end = OVERLAY.index("anchors.horizontalCenter", overlay_surface_start)
overlay_surface = OVERLAY[overlay_surface_start:overlay_surface_end]
assert "readonly property color surfaceFillColor: Appearance.colors.colLayer0" in overlay_surface
assert "panelBgOpacity" not in overlay_surface
assert "CF.ColorUtils.applyAlpha(" not in overlay_surface

focus_surface_start = FOCUS.index("id: card")
focus_surface_end = FOCUS.index("anchors.horizontalCenter", focus_surface_start)
focus_surface = FOCUS[focus_surface_start:focus_surface_end]
assert "readonly property color surfaceFillColor: Appearance.colors.colLayer0" in focus_surface
assert "CF.ColorUtils.applyAlpha(" not in focus_surface

assert 'Translation.tr("Panel background opacity (%)")' not in MODULES
assert "Settings base surface has one owner." in README

# Standalone Settings must handle Config already being ready before
# Connections.onReadyChanged can observe the transition, just like shell.qml.
assert "if (Config.ready) {" in WINDOW
assert "Qt.callLater(() => ThemeService.applyCurrentTheme())" in WINDOW


# Overlay dimming must never tint the physical Screen Edge or the connected
# colLayer0 body. Both presentation modes share the same curved workspace mask.
SCRIM = (ROOT / "modules" / "settings" / "SettingsWorkspaceScrim.qml").read_text(encoding="utf-8")
for host, card_id in ((OVERLAY, "settingsCard"), (FOCUS, "card")):
    assert "SettingsWorkspaceScrim {" in host
    assert 'outputName: String(settingsPanel.screen?.name ?? "")' in host
    assert f"cardRect: Qt.rect({card_id}.x, {card_id}.y," in host
    assert f"cardRadius: {card_id}.radius" in host
    assert "Appearance.colors.colScrim" not in host
assert "ShapePath {" in SCRIM
assert "PerimeterTokens.frameRadius" in SCRIM
assert "Appearance.sizes.verticalBarWidth" in SCRIM
assert "Appearance.sizes.barHeight" in SCRIM
assert "layer.effect: OpacityMask {" in SCRIM
assert "invert: true" in SCRIM
assert "bottomLeftRadius: 0" in SCRIM and "bottomRightRadius: 0" in SCRIM
assert "fillColor: Appearance.colors.colScrim" in SCRIM

# SET-R03: sidebar hover help stays short in both source and English catalog.
SIDEBARS = (ROOT / "modules" / "settings" / "SidebarsConfig.qml").read_text(encoding="utf-8")
EN_US = json.loads((ROOT / "translations" / "en_US.json").read_text(encoding="utf-8"))
assert "Hover a side Screen Edge; enter the sidebar to keep it open." in SIDEBARS
assert "Why this is cool:" not in SIDEBARS
for hint in (
    "Hover the corner tip; scroll controls remain available elsewhere.",
    "Offset corner hover vertically to avoid horizontal-edge triggers.",
):
    assert hint in SIDEBARS, hint
    assert EN_US.get(hint) == hint, hint

# Waffle is a supported family. Keep the short labels discoverable in English
# without losing the GPU-cost warning or original-recording assurance.
WAFFLE_HELP = {
    "WGeneralPage.qml": ("Maximize a lone tiled window; restore its size when another opens.",),
    "WBackgroundPage.qml": (
        "Animated wallpaper blur is separate from window blur; high GPU cost.",
        "Hide wallpaper behind fullscreen windows; keep the Task View backdrop.",
        "Blur wallpaper behind windows; pause during transitions.",
        "Blur animated backdrops; may greatly increase GPU load.",
    ),
    "WInterfacePage.qml": (
        "Create a smaller sharing copy; keep the original recording.",
        "Show media feedback; Pill also announces track changes outside games.",
    ),
}
for page, hints in WAFFLE_HELP.items():
    source = (ROOT / "modules" / "waffle" / "settings" / "pages" / page).read_text(encoding="utf-8")
    for hint in hints:
        assert hint in source, (page, hint)
        assert EN_US.get(hint) == hint, (page, hint)

print("Settings concise-copy/shared-surface contract: PASS")
