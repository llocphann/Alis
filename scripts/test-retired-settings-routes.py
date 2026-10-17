#!/usr/bin/env python3
"""AUTO-R02 regression: retiring a Settings page must preserve shell navigation."""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


class RetiredSettingsRoutesTest(unittest.TestCase):
    def test_removed_qml_has_no_registered_component(self):
        self.assertFalse((ROOT / "modules/settings/AutomationTaskConfig.qml").exists())
        self.assertNotIn("AutomationTaskConfig", source("modules/settings/qmldir"))

    def test_index_35_is_a_migration_gap_not_a_loadable_page(self):
        data = source("modules/settings/SettingsPageRegistryData.qml")
        registry = source("modules/settings/SettingsPageRegistry.qml")
        self.assertRegex(data, r"legacyHiddenIndexes:\s*\[[^\]]*\b35\b")
        self.assertIn("null, // Index 35: retired Automation", data)
        self.assertNotIn('key:"automation"', data)
        self.assertNotIn("pageIndex:35", data)
        self.assertNotIn("pages: [24, 35", data)
        self.assertIn("function safePageIndex(index: int): int", registry)
        self.assertIn("root.isPageApplicable(index)", registry)
        self.assertIn("root.panelsPageIndex", registry)

    def test_every_settings_chrome_rejects_retired_deep_links(self):
        standalone = source("settings.qml")
        overlay = source("modules/settings/SettingsOverlay.qml")
        for filename, text in (("settings.qml", standalone),
                               ("SettingsOverlay.qml", overlay)):
            with self.subTest(chrome=filename):
                self.assertIn("SettingsPageRegistry.safePageIndex(", text)
                self.assertIn("onCurrentPageChanged" if filename == "settings.qml"
                              else "onOverlayCurrentPageChanged", text)
        self.assertIn("root._requestedStartSection = \"\"", standalone)
        self.assertIn("if (!SettingsPageRegistry.isPageApplicable(requestedPage))", overlay)
        self.assertIn("GlobalStates.settingsOverlayRequestedPage = -1", overlay)

    def test_other_settings_services_stay_connected(self):
        data = source("modules/settings/SettingsPageRegistryData.qml")
        for component in ("CompanionConfig.qml", "IntegrationsConfig.qml",
                          "ServicesConfig.qml", "AiConfig.qml"):
            self.assertIn(component, data)
            self.assertTrue((ROOT / "modules/settings" / component).is_file())
        reg = source("modules/settings/SettingsPageRegistry.qml")
        self.assertIn("root.isPageApplicable(index)", reg)
        self.assertIn("root._migrateLegacyPersistentPage()", reg)

    def test_ci_and_shell_are_independent_of_retired_automation(self):
        ci = source(".github/workflows/ci.yml")
        self.assertIn("python3 scripts/test-retired-settings-routes.py", ci)
        self.assertNotIn("scripts/test-AUTO-F01-", ci)
        self.assertNotIn("scripts/test-hadalis-automation-", ci)
        self.assertFalse((ROOT / ".github/workflows/auto-f01.yml").exists())
        self.assertIn("SettingsPageRegistry", source("settings.qml"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
