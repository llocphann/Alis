#!/usr/bin/env python3
"""SET-R04: the retired Alis Fcitx Settings must stay absent, not merely hidden."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FcitxSettingsRemovalTest(unittest.TestCase):
    def test_retired_settings_files_are_gone(self):
        for relative in (
            "modules/settings/FcitxInputSettings.qml",
            "scripts/input-method/fcitx5-settings.py",
            "scripts/test-fcitx5-settings-integration.py",
        ):
            with self.subTest(path=relative):
                self.assertFalse((ROOT / relative).exists())

    def test_no_settings_route_or_background_polling(self):
        settings = ROOT / "modules/settings"
        retired_markers = (
            "FcitxInputSettings",
            "fcitx5-settings.py",
            "Vietnamese input · Fcitx5",
            "fcitx5-configtool",
        )
        for path in settings.rglob("*.qml"):
            content = path.read_text(encoding="utf-8")
            for marker in retired_markers:
                with self.subTest(path=path.relative_to(ROOT), marker=marker):
                    self.assertNotIn(marker, content)
        qmldir = (settings / "qmldir").read_text(encoding="utf-8")
        self.assertNotIn("FcitxInputSettings", qmldir)

    def test_keyboard_and_compositor_settings_remain(self):
        page = (ROOT / "modules/settings/NiriConfig.qml").read_text(encoding="utf-8")
        registry = (ROOT / "modules/settings/SettingsPageRegistryData.qml").read_text(encoding="utf-8")
        for section in ("Keyboard", "Touchpad", "Mouse"):
            self.assertIn(f'title: Translation.tr("{section}")', page)
        self.assertIn('description: Translation.tr("Keyboard layout and key repeat settings")', registry)
        for retired in ('"fcitx5"', '"unikey"', '"telex"', '"vni"', '"vietnamese"', '"unicode"', '"ime"'):
            self.assertNotIn(retired, registry)

    def test_native_session_and_tray_wiring_are_retained(self):
        session = ROOT / "scripts/input-method/fcitx5-session.sh"
        lifecycle = ROOT / "scripts/test-fcitx5-session-integration.py"
        tray = ROOT / "services/TrayService.qml"
        self.assertTrue(session.is_file())
        self.assertTrue(lifecycle.is_file())
        self.assertTrue(tray.is_file())
        self.assertIn("fcitx5 -d", session.read_text(encoding="utf-8"))
        self.assertIn("function isFcitxItem(item)", tray.read_text(encoding="utf-8"))
        docs = (ROOT / "docs/INPUT_METHOD_TELEX.md").read_text(encoding="utf-8")
        self.assertIn("fcitx5-configtool", docs)
        self.assertNotIn("## Hadalis Keyboard Settings", docs)


if __name__ == "__main__":
    unittest.main(verbosity=2)
