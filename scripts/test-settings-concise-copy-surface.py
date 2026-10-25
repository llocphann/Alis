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


# SET-R03 continued: standalone/Overlay Settings copy has concise, translated
# labels. This contract checks the rendered lookup string, not a comment or a
# loose substring; controls, handlers and config keys remain separately owned.
SHARED_SETTINGS_HELP = {
    "DashboardConfig.qml": (
        "Dashboard requires Material (ii). Select it under Modules → Panel Style.",
        "Dashboard → Edit widgets lets you move or resize modules; outside Edit mode, layout is locked.",
        "Snap moved or resized modules to the grid on release.",
        "Resizing can adjust neighbors; moving modules never changes their sizes.",
    ),
    "ModulesConfig.qml": (
        "Manage modules, terminals and interface behavior.",
        "Overlay opens Settings above the shell for live previews.",
        "Overlay replaces the separate Settings window. Restart required.",
        "Blur wallpaper behind Settings; 0 disables the effect.",
    ),
    "AdvancedConfig.qml": (
        "Color-generation controls and runtime diagnostics.",
        "Manage ~/.config/cava/config; internal visualizers stay independent.",
        "On hybrid laptops, GPU polling can wake the dGPU; disabling pins Qt to iGPU after restart.",
        "Shared wave fill opacity; bar spectrum has its own setting.",
    ),
    "SidebarsConfig.qml": (
        "Sidebar content stays loaded between openings.",
        "Sidebar layout, widgets, media and edge behavior.",
        "Open sidebars from screen corners.",
    ),
    "BackgroundConfig.qml": (
        "Choose wallpaper reveal direction.",
        "Wallpaper source, rotation, motion and effects.",
        "Parallax uses internal rendering for synchronized motion.",
        "Waffle: use Waffle Style for backgrounds. Backdrop applies to both.",
        "Fit the entire backdrop; mismatched aspect ratios may show bars.",
        "Update theme colors on wallpaper changes (slower).",
        "Blur video/GIF wallpapers; may increase GPU load.",
    ),
}
for page, hints in SHARED_SETTINGS_HELP.items():
    source = (ROOT / "modules" / "settings" / page).read_text(encoding="utf-8")
    for hint in hints:
        assert f"Translation.tr({json.dumps(hint, ensure_ascii=False)})" in source, (page, hint)
        assert EN_US.get(hint) == hint, (page, hint)


# Explicit privacy/tooling caveats survive the concise-copy rework, including
# the Waffle family (whose UI remains a supported Settings frontend).
AI_AND_INTEGRATION_HELP = {
    "modules/settings/AiConfig.qml": (
        "Choose a provider and opt in to voice or privacy-sensitive features.",
        "Choose local, free online or connected models; availability is discovered automatically.",
        "Models and API protocol are discovered from the selected provider.",
        "Add a custom endpoint only if the provider is unsupported.",
        "OpenAI-compatible: OpenAI, Mistral, Ollama, OpenRouter, vLLM.",
        "Local only: use on-device models (Ollama, LM Studio).",
    ),
    "modules/waffle/settings/pages/WAiPage.qml": (
        "No custom providers; add one only if unsupported.",
        "Typed tools preview changes; raw commands require Advanced mode.",
        "Local only: use on-device models (Ollama, LM Studio).",
    ),
    "modules/settings/IntegrationsConfig.qml": (
        "Paste a compatible ICS/iCal feed URL; no account sign-in within Alis.",
    ),
    "modules/settings/GeneralConfigCore.qml": (
        "Power, cooling, language, input and safety settings.",
    ),
    "modules/settings/BackgroundConfig.qml": (
        "Use a custom backdrop for theme colors; disable Use main wallpaper.",
    ),
}
for path, hints in AI_AND_INTEGRATION_HELP.items():
    source = (ROOT / path).read_text(encoding="utf-8")
    for hint in hints:
        assert f"Translation.tr({json.dumps(hint, ensure_ascii=False)})" in source, (path, hint)
        assert EN_US.get(hint) == hint, (path, hint)

# Never simplify away the API-key storage disclosure to chase word counts.
for path in ("modules/settings/AiConfig.qml", "modules/waffle/settings/pages/WAiPage.qml"):
    source = (ROOT / path).read_text(encoding="utf-8")
    assert "process environment" in source, path
    assert "commands or config files" in source, path


# SET-R03: additional core Settings groups preserve semantics when copy is brief:
# Niri's 15-second revert, manual notification counters, owned/external
# autostarts, compositor scope and reduced-motion/theme caveats.
RUNTIME_SETTINGS_HELP = {
    "ServicesConfig.qml": (
        "System, network, search, updates and data sources.",
        "Run setup in a terminal for full output; off updates silently with bar status.",
        "Enter city or coordinates; blank uses IP. Weather: wttr.in/Open-Meteo; air quality: Open-Meteo.",
        "Check for shell updates and notify on the bar.",
        "Tolerates typos but may misread acronyms (e.g., GIMP).",
    ),
    "InterfaceConfig.qml": (
        "Panels, notifications, widgets and floating tools.",
        "Sync badges with live popup count, including externally cleared alerts; off uses manual count.",
        "Hover bottom-right for history; assigned compositor hot corners take priority.",
        "Mark history read and retract matching toasts (shared read flag).",
        "No timezones yet; add or reorder regional suggestions.",
        "Silence daily popups; notifications remain in history.",
    ),
    "AutostartConfig.qml": (
        "Manage startup apps and commands written to niri.",
        "Niri launches these at login; they keep running after shell restarts.",
        "App autostart works only while niri is the active compositor.",
        "Toggle niri login apps. External entries must be edited in the startup file below.",
        "Niri shell commands support pipes, environment variables and &&.",
    ),
    "NiriConfig.qml": (
        "Tune displays, input, layout and rules; unconfirmed display previews revert.",
        "Common niri options are validated; advanced options remain in raw KDL.",
        "Maximize a lone tiled window; restore its size when another opens.",
        "Display previews revert after 15 seconds unless confirmed.",
        "Choose an app preset or custom command.",
        "Gap from tiled windows to the Screen Edge/Bar; Edge thickness is reserved separately.",
        "Higher stiffness reacts faster; damping reduces bounce.",
    ),
    "ThemesConfig.qml": (
        "Material colors, typography, motion and advanced themes.",
        "Choose light/dark from wallpaper brightness; overrides manual mode on wallpaper change.",
        "Use complementary shell colors; external apps retain their colors.",
    ),
    "BarConfig.qml": (
        "Shared shadow for Edge, popups, Dock, Sidebar and Dashboard; hidden in fullscreen/lock.",
        "Classic Material settings; Waffle has separate taskbar controls.",
        "Horizontal and vertical module layouts are separate; visibility is shared.",
    ),
}
for page, hints in RUNTIME_SETTINGS_HELP.items():
    source = (ROOT / "modules" / "settings" / page).read_text(encoding="utf-8")
    for hint in hints:
        assert f"Translation.tr({json.dumps(hint, ensure_ascii=False)})" in source, (page, hint)
        assert EN_US.get(hint) == hint, (page, hint)


# Preserve explanatory safety/behavior constraints while shortening copy:
# capture never remembers recording mode, image bounds require no AI,
# H.264 preserves source recordings and failures remain visible.
TOOLS_WIDGET_HELP = {
    "ToolsConfig.qml": (
        "Capture, selection and overlay settings by tool.",
        "Snip menu remembers action/shape; dedicated shortcuts stay fixed. Recording is never remembered; off defaults to rectangle capture.",
        "Local image processing estimates object bounds (no AI); may be inaccurate.",
        "Two-pass H.264 makes a smaller copy; original stays intact. Higher CPU load.",
        "Show media actions and Pill track changes; in games, manual skips only.",
    ),
    "QuickConfig.qml": (
        "Choose separate capture folders; detailed paths in Tools.",
        "Wallpaper accent saturation: 100% default; higher is more vivid.",
        "Load grid on demand; full selector remains available.",
        "Show reload notices; errors always appear.",
    ),
    "DesktopWidgetsConfig.qml": (
        "Keep widget in its selected screen zone as dimensions change.",
        "Adapt widget text to wallpaper; off keeps colors stable when moved.",
        "Custom QML widgets: ~/.config/inir/widgets/ (widget.json and .qml required).",
        "Use one wallpaper palette for built-in widgets; individual overrides remain.",
        "Create an editable .qml template with imports and sample layout.",
    ),
    "MonitorVisibilityConfig.qml": (
        "Primary monitor sets the fallback output; display controls are in Compositor.",
    ),
    "DockConfig.qml": (
        "Hover reveals the Dock at the edge; Empty workspace shows it on an empty desktop.",
    ),
}
for page, hints in TOOLS_WIDGET_HELP.items():
    source = (ROOT / "modules" / "settings" / page).read_text(encoding="utf-8")
    for hint in hints:
        assert f"Translation.tr({json.dumps(hint, ensure_ascii=False)})" in source, (page, hint)
        assert EN_US.get(hint) == hint, (page, hint)


# Waffle is a supported, independently selectable Settings frontend.
WAFFLE_LATE_HELP = {
    "WModulesPage.qml": ("Waffle modules are inactive; configure them now or switch panel family.", "Changes apply when Waffle becomes active.", "All workspaces and windows; carousel or centered focus.", "Fit the Widgets sidebar to content height.",),
    "WWorkspaceStripPage.qml": ("Optional edge navigator (off by default). Hover to inspect, click to focus, drag windows, hold × to close. Niri provides snapshots.", "Wheel switches workspaces rather than scrolling thumbnails.", "Show playback controls in a top media card.", "Live active preview; refreshed snapshots for hidden workspaces.", "Focus the workspace when scrolling the strip.",),
    "WThemesPage.qml": ("Complementary shell colors; external apps remain unchanged.", "Choose light/dark automatically from wallpaper brightness.", "Generate Neovim/LazyVim theme at ~/.config/nvim/lua/plugins/neovim.lua.",),
    "WBackgroundPage.qml": ("Generate theme colors from the backdrop instead of the main wallpaper.", "Drag to place manually, or use the least busy region.", "Use global clock format or a wallpaper-clock override.",),
    "WBarPage.qml": ("Waffle-only settings; enable Waffle under Modules.",),
    "WWaffleStylePage.qml": ("Waffle-only settings; enable Waffle under Modules.",),
}
for page, hints in WAFFLE_LATE_HELP.items():
    source = (ROOT / "modules" / "waffle" / "settings" / "pages" / page).read_text(encoding="utf-8")
    for hint in hints:
        assert f"Translation.tr({json.dumps(hint, ensure_ascii=False)})" in source, (page, hint)
        assert EN_US.get(hint) == hint, (page, hint)


# Optional plugin wrappers retain loader/retry behavior while help is localized.
OPTIONAL_SETTINGS_HELP = {
    "CompanionConfig.qml": ("Companion unavailable. Run ./setup update, then Recheck Companion.", "Recheck Companion",),
    "ObsidianThemeSettings.qml": ("Install Alis-Intergration; enable this integration in Settings → Integrations.",),
    "ObsidianTodoSettings.qml": ("Install Alis-Intergration; enable Obsidian in Settings → Integrations.",),
    "ThinkfanSettings.qml": ("Install Alis-Intergration; enable Thinkfan in Settings → Integrations.",),
}
for page, hints in OPTIONAL_SETTINGS_HELP.items():
    source = (ROOT / "modules" / "settings" / page).read_text(encoding="utf-8")
    for hint in hints:
        assert f"Translation.tr({json.dumps(hint, ensure_ascii=False)})" in source, (page, hint)
        assert EN_US.get(hint) == hint, (page, hint)
companion_source = (ROOT / "modules/settings/CompanionConfig.qml").read_text(encoding="utf-8")
assert "active: Hadanion.available" in companion_source
assert "source: Hadanion.settingsSource" in companion_source
assert "onClicked: Hadanion.refresh()" in companion_source
for name, dynamic_source in (
    ("ThinkfanSettings.qml", 'Hadalird.settingsSource("thinkfan")'),
    ("ObsidianThemeSettings.qml", 'Hadalird.settingsSource("obsidian")'),
    ("ObsidianTodoSettings.qml", 'Hadalird.settingsSource("obsidianTodo")'),
):
    source = (ROOT / "modules/settings" / name).read_text(encoding="utf-8")
    assert dynamic_source in source, name
waffle_tlp_source = (ROOT / "modules/waffle/settings/pages/WTlpPage.qml").read_text(encoding="utf-8")
tlp_hint = "Install Alis-Intergration; enable TLP in Settings → Integrations."
assert f"Translation.tr({json.dumps(tlp_hint, ensure_ascii=False)})" in waffle_tlp_source
assert EN_US.get(tlp_hint) == tlp_hint


# Shared Themes/Effects and Waffle parent must retain concise and safe help.
OTHER_SETTINGS_HELP = {
    "EffectsConfig.qml": ("Set rendering policy, then adjust specific effects.",),
    "CustomThemeEditor.qml": ("Light mode is experimental; start with a light preset (Angel Light, Latte or Sakura).", "Changes preview live; adjust individual colors as needed.",),
    "ShellLayoutConfig.qml": ("Arrange persistent surfaces here or on the desktop; both use live layout.",),
    "WaffleConfig.qml": ("Waffle-only settings; choose Waffle in Modules → Panel Style.", "Waffle wallpaper, taskbar, themes and switching.", "Backdrop appears behind Niri Overview (Mod+Tab).",),
}
for page, hints in OTHER_SETTINGS_HELP.items():
    source = (ROOT / "modules" / "settings" / page).read_text(encoding="utf-8")
    for hint in hints:
        assert f"Translation.tr({json.dumps(hint, ensure_ascii=False)})" in source, (page, hint)
        assert EN_US.get(hint) == hint, (page, hint)

print("Settings concise-copy/shared-surface contract: PASS")
