#!/usr/bin/env python3
"""Guard startup-critical QML failures that can disable whole surface trees."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ACRYLIC = ROOT / "modules" / "waffle" / "looks" / "AcrylicButton.qml"
CALENDAR = ROOT / "modules" / "bar" / "ClockCalendarContent.qml"
NOTIFICATIONS = (
    ROOT / "modules" / "notificationCenter" / "NotificationCenterPopup.qml"
)
MATERIAL_THEME_LOADER = ROOT / "services" / "MaterialThemeLoader.qml"
ABYSS_EDGE_EDITOR = ROOT / "modules" / "abyss" / "AbyssEdgeEditor.qml"
ABYSS_BAR = ROOT / "modules" / "abyss" / "bar" / "AbyssBar.qml"
WINDOW_DIALOG = ROOT / "modules" / "common" / "widgets" / "WindowDialog.qml"
EVENTS_DIALOG = ROOT / "modules" / "sidebarRight" / "events" / "EventsDialog.qml"


def fail(message: str) -> None:
    raise SystemExit("FAIL: " + message)


acrylic = ACRYLIC.read_text(encoding="utf-8")
calendar = CALENDAR.read_text(encoding="utf-8")
notifications = NOTIFICATIONS.read_text(encoding="utf-8")
material_theme_loader = MATERIAL_THEME_LOADER.read_text(encoding="utf-8")
abyss_edge_editor = ABYSS_EDGE_EDITOR.read_text(encoding="utf-8")
abyss_bar = ABYSS_BAR.read_text(encoding="utf-8")
window_dialog = WINDOW_DIALOG.read_text(encoding="utf-8")
events_dialog = EVENTS_DIALOG.read_text(encoding="utf-8")

# A previous remote edit serialized real line breaks as literal "\\n" tokens in
# a QML expression. That makes AcrylicButton unparseable and takes the entire
# Waffle bar type chain down with it.
expected_border = (
    "colBackgroundBorder: ColorUtils.transparentize(color,\n"
    "        (root.checked || root.hovered) "
    "? Looks.backgroundTransparency : 0)"
)
if expected_border not in acrylic:
    fail("AcrylicButton border expression must remain valid multiline QML")
border_tail = acrylic.split("colBackgroundBorder:", 1)[1].split("color:", 1)[0]
if "\\n" in border_tail:
    fail("AcrylicButton contains serialized newline escape tokens in QML code")

# ClockCalendarContent references Appearance directly, so the common module must
# stay imported even when the calendar is composed through the Bar module.
if "import qs.modules.common\n" not in calendar:
    fail("ClockCalendarContent must import qs.modules.common for Appearance")

# StyledPopup's default property is Item-only. Non-visual Connections objects
# must be held on an explicit QObject property or construction of ScreenCorners
# fails before the bottom-left/bottom-right popup surfaces can instantiate.
screen_time_direct = "\n    Connections {\n        target: ScreenTime"
if screen_time_direct in notifications:
    fail("NotificationCenterPopup must not route Connections into StyledPopup content")
if "property QtObject _screenTimeConnections: Connections {" not in notifications:
    fail("NotificationCenterPopup must keep ScreenTime Connections on a QtObject property")

# BOOT-I01: Optional profiler marker FileView must suppress missing-file printErrors
# so its 1500ms polling timer does not spam the Quickshell scene log.
profile_block = material_theme_loader.split("id: themeProfileControl", 1)[1].split("}", 1)[0]
if "printErrors: false" not in profile_block:
    fail("MaterialThemeLoader themeProfileControl FileView must set printErrors: false")

# BOOT-I01: AbyssEdgeEditor edgeEditorColumn child GridLayouts must not flip column
# count off a 0->270 live width transition during initial ColumnLayout::rearrange().
edge_col_block = abyss_edge_editor.split("id:edgeEditorColumn", 1)[1].split("RowLayout {", 1)[0]
if "width:Layout.preferredWidth" not in edge_col_block:
    fail("AbyssEdgeEditor edgeEditorColumn must initialize width:Layout.preferredWidth to avoid recursive rearrange")

# BOOT-I01: AbyssBar delegate teardown must guard root references against null.
if "onNaturalSpanChanged: if (root) root.measure(modelData,naturalSpan)" not in abyss_bar:
    fail("AbyssBar must guard root.measure during delegate teardown")
if "enabled: !(root?.editing ?? false) && visible" not in abyss_bar:
    fail("AbyssBar must guard root.editing during delegate teardown")

# BOOT-I01: Hidden WindowDialog / EventsDialog text inputs must not remain enabled
# while closed, avoiding spurious Wayland text-input surface disable warnings on hover.
if "enabled: root.show" not in window_dialog:
    fail("WindowDialog contentColumn must gate enabled on root.show")
if "component EventTextField: MaterialTextField {\n        enabled: root.show" not in events_dialog:
    fail("EventsDialog EventTextField must gate enabled on root.show")

print("ok - startup QML surface regression")
