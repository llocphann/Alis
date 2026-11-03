#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
style = (root / "modules/settings/SidebarsConfig.qml").read_text()
positions = (root / "modules/abyss/settings/AbyssPositionSettings.qml").read_text()
notes = (root / "modules/screenCorners/QuickNotesPopup.qml").read_text()
center = (root / "modules/notificationCenter/NotificationCenterPopup.qml").read_text()

for needle in [
    "Left edgebar",
    'Config.setNestedValue("quickNotes.popupWidth",value)',
    'Config.setNestedValue("quickNotes.popupHeight",value)',
    "Right edgebar",
    'Config.setNestedValue("notificationCenter.popupWidth",value)',
    'Config.setNestedValue("notificationCenter.popupHeight",value)',
]:
    assert needle in style, needle

assert "All Edge Bar popups" in positions
assert "Quick Notes / Timers Edge Bar" in positions
assert "Notifications / Activity Edge Bar" in positions

# Runtime surfaces must consume the exact same settings keys exposed above.
assert "Config.options?.quickNotes?.popupWidth ?? 420" in notes
assert "Config.options?.quickNotes?.popupHeight ?? 300" in notes
assert "Config.options?.notificationCenter?.popupWidth ?? 420" in center
assert "Config.options?.notificationCenter?.popupHeight ?? 560" in center

print("abyss Edge Bar popup sizing contract: ok")
