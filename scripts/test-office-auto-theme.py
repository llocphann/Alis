#!/usr/bin/env python3
"""OFFICE-I01: private synthetic profiles; never touch installed app settings."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/colors"))
SPEC = importlib.util.spec_from_file_location("office_theme", ROOT / "scripts/colors/office_theme.py")
office = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(office)


class OfficeThemeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="alis-office-fixture-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.config_home, self.data_home, self.state_home = [self.base / n for n in ("config", "data", "state")]
        self.config = self.config_home / "onlyoffice/DesktopEditors.conf"
        self.theme = self.data_home / "onlyoffice/desktopeditors/uithemes/alis-auto.json"
        self.journal = self.state_home / "quickshell/user/generated/office/onlyoffice.json"
        self.palette = {"app_background": "#102030", "app_foreground": "#e0e4ef",
                        "app_surface_elevated": "#243040", "app_border": "#657080",
                        "app_accent": "#aabbff", "app_on_accent": "#101030",
                        "app_subtext": "#a0b0c0"}
        self.busy = patch.object(office, "app_busy", return_value=False)
        self.busy.start()
        self.addCleanup(self.busy.stop)

    def put(self, path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)

    def update(self, enabled=True, version="9.4.0-1"):
        return office.update_onlyoffice(self.config_home, self.data_home, self.state_home,
                                       enabled, self.palette, version)

    def test_opt_in_missing_config_does_nothing(self):
        self.assertEqual(self.update(False), "disabled")
        self.assertFalse(self.config.exists())
        self.assertFalse(self.journal.exists())

    def test_generate_semantic_palette_and_dark_mode(self):
        theme = json.loads(office.generate_theme(self.palette))
        self.assertEqual(theme["type"], "dark")
        self.assertEqual(theme["colors"]["background-normal"], "#102030")
        self.assertEqual(theme["colors"]["text-normal"], "#e0e4ef")
        self.assertEqual(theme["colors"]["text-link"], "#aabbff")
        self.assertEqual(theme["colors"]["text-accent-button"], "#101030")
        self.assertEqual(theme["id"], "theme-alis-auto")

    def test_light_mode_and_explicit_mode(self):
        self.palette["app_background"] = "#f8faff"
        self.assertEqual(json.loads(office.generate_theme(self.palette))["type"], "light")
        # Explicit mode metadata must not force light backgrounds to use
        # dark ink/theme defaults: real surface luminance controls readability.
        self.palette["darkmode"] = True
        self.assertEqual(json.loads(office.generate_theme(self.palette))["type"], "light")

    def test_desktop_home_settings_and_editor_surface_contrast(self):
        # ONLYOFFICE Desktop login/settings uses its own CSS variables;
        # covering only editor names painted a white panel with light text.
        for updates in (
            {},
            {"app_background": "#fafafa", "app_surface_elevated": "#171717",
             "app_foreground": "#eeeeee", "app_subtext": "#f4f4f4",
             "app_border": "#ffffff", "app_accent": "#fafafa", "app_on_accent": "#ffffff",
             "darkmode": True},
            {"app_background": "#101010", "app_surface_elevated": "#f0f0f0",
             "app_foreground": "#090909", "app_subtext": "#333333",
             "app_border": "#101010", "app_accent": "#151515", "app_on_accent": "#000000",
             "darkmode": False},
        ):
            with self.subTest(updates=updates):
                palette = {**self.palette, **updates}
                theme = json.loads(office.generate_theme(palette))
                colors = theme["colors"]
                self.assertEqual(colors["background-action-panel"], colors["background-toolbar"])
                self.assertEqual(colors["highlight-sidebar-item-pressed"], colors["background-action-panel"])
                self.assertEqual(colors["icon-normal"], colors["text-normal"])
                self.assertEqual(colors["text-tertiary"], colors["text-secondary"])
                self.assertEqual(colors["canvas-background"], "#114161" if theme["type"] == "dark" else colors["background-normal"])
                self.assertEqual(colors["canvas-ruler-background"], colors["canvas-background"])
                self.assertEqual(colors["canvas-ruler-margins-background"], colors["background-action-panel"])
                self.assertEqual(colors["canvas-scroll-thumb-border"], colors["canvas-scroll-thumb"])
                # The paper/cell data colors must remain under the suite's
                # document/night-page preference, not this shell palette.
                self.assertNotIn("canvas-content-background", colors)
                self.assertNotIn("canvas-cell-background", colors)
                for ink, ground in (
                    ("text-normal", "background-normal"),
                    ("text-normal", "background-action-panel"),
                    ("text-normal", "highlight-sidebar-item-pressed"),
                    ("text-secondary", "background-action-panel"),
                    ("text-tertiary", "background-normal"),
                    ("icon-normal", "background-normal"),
                    ("text-link", "background-action-panel"),
                    ("text-inverse", "background-accent-button"),
                    ("chb-check-mark-background", "chb-background-checked"),
                    ("canvas-ruler-mark", "canvas-ruler-background"),
                    ("canvas-cell-title-text", "canvas-cell-title-background"),
                ):
                    self.assertGreaterEqual(office.contrast_ratio(colors[ink], colors[ground]), 4.5,
                                            (ink, ground, theme["type"]))
                for ground in ("background-normal", "background-action-panel"):
                    self.assertGreaterEqual(office.contrast_ratio(colors["border-regular-control"], colors[ground]), 3.0)
                self.assertGreaterEqual(office.contrast_ratio(
                    colors["canvas-page-border"], colors["canvas-background"]), 3.0)
                self.assertGreaterEqual(office.contrast_ratio(
                    colors["canvas-ruler-border"], colors["canvas-ruler-background"]), 3.0)

    def test_onlyoffice_canvas_refreshes_with_palette_and_restores_original_settings(self):
        original = b"[General]\nUITheme=theme-night\nLanguage=en\n"
        self.put(self.config, original)
        self.update()
        first = json.loads(self.theme.read_bytes())
        self.assertEqual(first["colors"]["canvas-background"], "#114161")
        self.palette.update(app_background="#fafafa", app_surface_elevated="#f0f0f0",
                            app_foreground="#171717", app_subtext="#494949",
                            app_border="#555555", app_accent="#4840a0",
                            app_on_accent="#ffffff")
        self.update()
        second = json.loads(self.theme.read_bytes())
        self.assertEqual(second["type"], "light")
        self.assertEqual(second["colors"]["canvas-background"], "#fafafa")
        self.assertNotEqual(first["colors"]["canvas-background"], second["colors"]["canvas-background"])
        self.assertNotIn("canvas-content-background", second["colors"])
        self.update(False)
        self.assertEqual(self.config.read_bytes(), original)
        self.assertFalse(self.theme.exists())

    def test_invalid_or_missing_palette_never_writes(self):
        for value in ("red", "#abc", "#ffffff;payload", 123, None):
            with self.subTest(value=value):
                self.palette["app_accent"] = value
                with self.assertRaises(office.UnsafeConfig):
                    self.update()
                self.assertFalse(self.config.exists())
                self.assertFalse(self.theme.exists())

    def test_noninstalled_and_unknown_version_preserve_everything(self):
        self.put(self.config, b"this is not a valid ini\n")
        for version in (None, "9.3.0", "10.0.0", "9.40.0"):
            with self.subTest(version=version):
                self.update(version=version)
                self.assertEqual(self.config.read_bytes(), b"this is not a valid ini\n")
                self.assertFalse(self.theme.exists())

    def test_supported_epoch_package_version(self):
        self.assertIn("applied", self.update(version="1:9.4.0-1"))

    def test_new_profile_is_private_and_restores_absence(self):
        self.update()
        self.assertEqual(self.config.read_bytes(), b"[General]\nUITheme=alis-auto.json\n")
        for path in (self.config, self.theme, self.journal):
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.journal.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.update(False), "restored")
        self.assertFalse(self.config.exists())
        self.assertFalse(self.theme.exists())
        self.assertFalse(self.journal.exists())

    def test_existing_selector_unrelated_bytes_and_restore(self):
        original = (b"; fixture only\n[General]\nUITheme=theme-dark\nLanguage=vi\n"
                    b"[Cloud]\nServer=fixture.invalid\nOpaque=@ByteArray(abc)\n")
        self.put(self.config, original)
        self.update()
        self.assertEqual(self.config.read_bytes(), original.replace(b"UITheme=theme-dark", b"UITheme=alis-auto.json"))
        self.update(False)
        self.assertEqual(self.config.read_bytes(), original)

    def test_indented_selector_and_commented_sections_do_not_duplicate_or_capture_other_keys(self):
        original = b" [General] ; fixture\n  UITheme = theme-dark\n  Language=vi\n[Other] ; fixture\nUITheme=other-value\n"
        self.put(self.config, original)
        self.update()
        self.assertEqual(self.config.read_bytes().count(b"UITheme"), 2)
        self.assertIn(b"UITheme=other-value", self.config.read_bytes())
        self.update(False)
        self.assertEqual(self.config.read_bytes(), original)

    def test_insert_selector_preserves_all_original_bytes(self):
        original = b"[General]\n\nLanguage=vi\n\n[Other]\nKeep=x\n"
        self.put(self.config, original)
        self.update()
        self.assertEqual(self.config.read_bytes().replace(b"UITheme=alis-auto.json\n", b""), original)
        self.update(False)
        self.assertEqual(self.config.read_bytes(), original)

    def test_update_idempotency_and_palette_refresh(self):
        self.update()
        stamps = {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in (self.config, self.theme, self.journal)}
        self.update()
        for path, (data, stamp) in stamps.items():
            self.assertEqual(path.read_bytes(), data)
            self.assertEqual(path.stat().st_mtime_ns, stamp)
        self.palette["app_accent"] = "#eeaacc"
        self.update()
        self.assertEqual(json.loads(self.theme.read_bytes())["colors"]["text-link"], "#eeaacc")
        self.assertEqual(self.config.read_text().count("UITheme="), 1)

    def test_unrelated_user_edits_survive_disable(self):
        self.update()
        self.put(self.config, self.config.read_bytes() + b"Language=vi\n")
        self.update(False)
        self.assertEqual(self.config.read_bytes(), b"[General]\nLanguage=vi\n")

    def test_user_selector_edit_is_not_overwritten_on_update_or_disable(self):
        self.update()
        changed = self.config.read_bytes().replace(b"alis-auto.json", b"theme-night")
        self.put(self.config, changed)
        with self.assertRaises(office.UnsafeConfig):
            self.update()
        self.assertIn("selector", self.update(False))
        self.assertEqual(self.config.read_bytes(), changed)
        self.assertFalse(self.theme.exists())

    def test_user_theme_file_edit_is_preserved(self):
        self.update()
        self.put(self.theme, b'{"id":"theme-my-edited-copy"}\n')
        with self.assertRaises(office.UnsafeConfig):
            self.update()
        self.assertIn("theme", self.update(False))
        self.assertEqual(self.theme.read_bytes(), b'{"id":"theme-my-edited-copy"}\n')
        self.assertFalse(self.config.exists())

    def test_unowned_theme_and_dangling_selector_are_never_adopted(self):
        self.put(self.theme, b'{"id":"user-owned"}')
        with self.assertRaises(office.UnsafeConfig):
            self.update()
        self.assertFalse(self.config.exists())
        self.assertEqual(self.theme.read_bytes(), b'{"id":"user-owned"}')
        self.theme.unlink()
        self.put(self.config, b"[General]\nUITheme=alis-auto.json\n")
        with self.assertRaises(office.UnsafeConfig):
            self.update()
        self.assertFalse(self.theme.exists())

    def test_malformed_ini_duplicate_and_multiline_selectors_fail_safe(self):
        for original in (b"invalid", b"[General]\nUITheme=a\nUITheme=b\n",
                         b"[General]\n[General]\n", b"[General]\nUITheme=a\\\n next\n"):
            with self.subTest(original=original):
                self.put(self.config, original)
                with self.assertRaises(office.UnsafeConfig):
                    self.update()
                self.assertEqual(self.config.read_bytes(), original)
                self.assertFalse(self.theme.exists())

    def test_running_app_never_writes_and_receipt_is_retained(self):
        with patch.object(office, "app_busy", return_value=True):
            self.assertIn("deferred", self.update())
        self.assertFalse(self.config.exists())
        self.update()
        receipt = self.journal.read_bytes()
        with patch.object(office, "app_busy", return_value=True):
            self.assertIn("deferred", self.update(False))
        self.assertEqual(self.journal.read_bytes(), receipt)
        self.assertTrue(self.theme.exists())

    def test_symlink_and_hardlink_files_are_rejected(self):
        other = self.base / "unrelated"
        self.put(other, b"[General]\nUITheme=theme-dark\n")
        self.config.parent.mkdir(parents=True)
        self.config.symlink_to(other)
        with self.assertRaises(office.UnsafeConfig):
            self.update()
        self.config.unlink()
        os.link(other, self.config)
        with self.assertRaises(office.UnsafeConfig):
            self.update()
        self.assertEqual(other.read_bytes(), b"[General]\nUITheme=theme-dark\n")

    def test_symlink_parent_is_rejected(self):
        real = self.base / "real"
        real.mkdir()
        self.data_home.symlink_to(real)
        with self.assertRaises(office.UnsafeConfig):
            self.update()
        self.assertEqual(list(real.iterdir()), [])

    def test_interrupted_transaction_recovers_once_without_reapplying_old_config(self):
        original = office.write_file
        def fail_config(path, content, expected):
            if path == self.config:
                raise PermissionError("synthetic interruption")
            return original(path, content, expected)
        with patch.object(office, "write_file", side_effect=fail_config):
            with self.assertRaises(PermissionError):
                self.update()
        self.assertTrue(self.theme.exists())
        self.assertFalse(self.config.exists())
        self.assertIn("pending", json.loads(self.journal.read_bytes()))
        self.update()
        self.assertNotIn("pending", json.loads(self.journal.read_bytes()))
        self.put(self.config, self.config.read_bytes() + b"Language=vi\n")
        self.update()
        self.assertIn(b"Language=vi", self.config.read_bytes())

    def test_interrupted_transaction_with_concurrent_edit_stays_unresolved(self):
        original = office.write_file
        def fail_config(path, content, expected):
            if path == self.config:
                raise PermissionError("fixture")
            return original(path, content, expected)
        with patch.object(office, "write_file", side_effect=fail_config):
            with self.assertRaises(PermissionError):
                self.update()
        receipt = self.journal.read_bytes()
        changed = b"[General]\nUITheme=theme-gray\n"
        self.put(self.config, changed)
        with self.assertRaises(office.UnsafeConfig):
            self.update()
        self.assertEqual(self.config.read_bytes(), changed)
        self.assertEqual(self.journal.read_bytes(), receipt)

    def test_concurrent_edit_between_recovery_validation_and_write_is_not_adopted(self):
        original = office.write_file
        changed = b"[General]\nUITheme=theme-gray\n"
        def race(path, content, expected):
            result = original(path, content, expected)
            if path == self.theme:
                self.put(self.config, changed)
            return result
        with patch.object(office, "write_file", side_effect=race):
            with self.assertRaises(office.UnsafeConfig):
                self.update()
        self.assertEqual(self.config.read_bytes(), changed)
        self.assertIn("pending", json.loads(self.journal.read_bytes()))

    def test_permission_failure_retains_original_and_recovery_receipt(self):
        original = office.write_file
        def fail_theme(path, content, expected):
            if path == self.theme:
                raise PermissionError("fixture")
            return original(path, content, expected)
        with patch.object(office, "write_file", side_effect=fail_theme):
            with self.assertRaises(PermissionError):
                self.update()
        self.assertFalse(self.config.exists())
        self.assertIn("pending", json.loads(self.journal.read_bytes()))
        self.update(False)
        self.assertFalse(self.theme.exists())
        self.assertFalse(self.config.exists())

    def test_profile_change_does_not_replay_receipt_into_another_profile(self):
        self.update()
        self.config_home = self.base / "new-config"
        with self.assertRaises(office.UnsafeConfig):
            self.update(False)
        self.assertFalse(self.config_home.exists())
        self.assertTrue(self.journal.exists())

    def test_libreoffice_profile_is_independent_and_untouched(self):
        libre = self.config_home / "libreoffice/4/user/registrymodifications.xcu"
        original = b"fixture-only LibreOffice preferences\n"
        self.put(libre, original)
        self.update()
        self.update(False)
        self.assertEqual(libre.read_bytes(), original)

    def test_cli_default_disabled_with_private_xdg_does_not_launch_apps(self):
        config = self.config_home / "alis/config.json"
        self.put(config, b"{}")
        env = {**os.environ, "HOME": str(self.base), "XDG_CONFIG_HOME": str(self.config_home),
               "XDG_DATA_HOME": str(self.data_home), "XDG_STATE_HOME": str(self.state_home), "PATH": ""}
        result = subprocess.run([sys.executable, str(ROOT / "scripts/colors/office_theme.py"),
                                 "--config", str(config)], env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("disabled", result.stdout)
        self.assertFalse(self.config.exists())

    def test_legacy_config_and_palette_input_symlinks_are_read_only(self):
        alis = self.base / 'actual-alis'
        alis.mkdir()
        config = alis / 'config.json'
        config.write_text('{}')
        self.config_home.mkdir()
        (self.config_home / 'illogical-impulse').symlink_to(alis)
        output, status = office.run(self.config_home / 'illogical-impulse/config.json',
                                   self.config_home, self.data_home, self.state_home)
        self.assertEqual(status, 0)
        self.assertEqual(config.read_text(), '{}')
        generated = self.state_home / 'quickshell/user/generated'
        generated.mkdir(parents=True, exist_ok=True)
        palette = self.base / 'palette.json'
        palette.write_text(json.dumps(self.palette))
        (generated / 'app-palette.json').symlink_to(palette)
        self.assertEqual(office.load_palette(self.state_home), self.palette)
        self.assertEqual(json.loads(palette.read_text()), self.palette)

    def test_pipeline_runs_disabled_adapter_for_restore_and_settings_are_opt_in(self):
        manifest = json.loads((ROOT / "scripts/colors/targets/office.json").read_text())
        self.assertNotIn("configKey", manifest)
        defaults = json.loads((ROOT / "defaults/config.json").read_text())
        self.assertFalse(defaults["appearance"]["wallpaperTheming"]["enableOnlyOffice"])
        self.assertIn("enableOnlyOffice", (ROOT / "services/ThemeService.qml").read_text())
        self.assertIn("enableOnlyOffice", (ROOT / "modules/settings/AdvancedConfig.qml").read_text())


class LibreOfficeThemeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="alis-libreoffice-fixture-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.config_home, self.state_home = self.base / "config", self.base / "state"
        self.config = self.config_home / "libreoffice/4/user/registrymodifications.xcu"
        self.journal = self.state_home / "quickshell/user/generated/office/libreoffice.json"
        self.palette = {"background": "#102030", "on_surface": "#e0e4ef", "surface": "#243040",
                        "surface_container": "#354050", "outline": "#657080", "primary": "#aabbff",
                        "on_primary": "#101030", "on_surface_variant": "#a0b0c0"}
        self.busy = patch.object(office, "app_busy", return_value=False)
        self.busy.start()
        self.addCleanup(self.busy.stop)
        schema = self.base / "schema.xcd"
        roles = [key[-2] for key in office.libreoffice_values(self.palette) if key[:4] == office.LO_COLORS]
        text = ('<registry xmlns:oor="' + office.registry.OOR + '"><group oor:name="ColorScheme">'
                + ''.join('<group oor:name="' + role + '"><prop oor:name="Color" oor:type="xs:int"/></group>' for role in roles)
                + '</group><prop oor:name="ApplicationAppearance"/><prop oor:name="LibreOfficeTheme"/>'
                + '<prop oor:name="CurrentColorScheme"/></registry>')
        schema.write_text(text)
        original_check = office.check_libreoffice_schema
        self.schema_patch = patch.object(office, "check_libreoffice_schema", side_effect=lambda values: original_check(values, schema))
        self.schema_patch.start()
        self.addCleanup(self.schema_patch.stop)

    def put(self, data):
        self.config.parent.mkdir(parents=True, exist_ok=True)
        self.config.write_bytes(data)

    def update(self, enabled=True, version="26.8.1-2"):
        return office.update_libreoffice(self.config_home, self.state_home, enabled, self.palette, version)

    def test_explicit_libreoffice_workspace_blue_is_scheme_owned_and_restores(self):
        self.update()
        key = office.LO_COLORS + ("AppBackground", "Color")
        self.assertEqual(self.registry().value(key), str(0x114161))
        self.palette.update({"background": "#fafafa", "surface_container": "#eeeeee",
                             "on_surface": "#202020", "on_surface_variant": "#565656",
                             "primary": "#4b47a7", "on_primary": "#ffffff"})
        self.update()
        self.assertEqual(self.registry().value(key), str(0x114161))
        self.assertNotIn(office.LO_COLORS + ("DocColor", "Color"), self.registry().fields)
        self.update(False)
        self.assertFalse(self.config.exists())

    def test_readable_libreoffice_application_roles(self):
        for palette in (
            self.palette,
            {**self.palette, "background": "#fafafa", "surface_container": "#141414",
             "on_surface": "#ffffff", "on_surface_variant": "#eeeeee",
             "outline": "#fafafa", "primary": "#ededed", "on_primary": "#ffffff"},
        ):
            with self.subTest(background=palette["background"]):
                values = office.libreoffice_values(palette)
                def role(name):
                    return f"#{int(values[office.LO_COLORS + (name, 'Color')]):06x}"
                generated = json.loads(office.generate_theme(palette))
                self.assertEqual(role("AppBackground"), "#114161")
                self.assertEqual(role("WindowColor"), generated["colors"]["background-action-panel"])
                self.assertNotIn(office.LO_COLORS + ("DocColor", "Color"), values)
                self.assertNotIn(office.LO_COLORS + ("FontColor", "Color"), values)
                for ink, background in (
                    ("WindowTextColor", "WindowColor"),
                    ("WindowTextColor", "BaseColor"),
                    ("ButtonTextColor", "ButtonColor"),
                    ("MenuBarTextColor", "MenuBarColor"),
                    ("MenuTextColor", "MenuColor"),
                    ("ActiveTextColor", "ActiveColor"),
                    ("MenuBarHighlightTextColor", "MenuBarHighlightColor"),
                    ("MenuHighlightTextColor", "MenuHighlightColor"),
                    ("DisabledTextColor", "DisabledColor"),
                    ("InactiveTextColor", "InactiveColor"),
                ):
                    self.assertGreaterEqual(office.contrast_ratio(role(ink), role(background)), 4.5,
                                            (ink, background))

    def registry(self):
        return office.registry.Registry(self.config.read_bytes())

    def item(self, path, inner):
        return ('<item xmlns:oor="' + office.registry.OOR + '" oor:path="' + path + '">' + inner + '</item>').encode()

    def initial(self):
        return office.registry.EMPTY_REGISTRY.replace(b'</oor:items>',
            self.item('/org.openoffice.Office.Common/Appearance',
                      '<prop oor:name="ApplicationAppearance"><value>0</value></prop>'
                      '<prop oor:name="Unrelated"><value>preserve me &amp; unicode: Việt</value></prop>')
            + b'<!-- keep original layout -->\n</oor:items>')

    def test_default_disabled_is_noop(self):
        self.assertEqual(self.update(False), "disabled")
        self.assertFalse(self.config.exists())

    def test_new_registry_valid_palette_mode_and_restore(self):
        self.update()
        tree = self.registry()
        self.assertEqual(tree.value(office.LO_BASE + ('CurrentColorScheme',)), 'AlisAuto')
        self.assertEqual(tree.value(office.LO_APPEARANCE + ('ApplicationAppearance',)), '2')
        self.assertEqual(tree.value(office.LO_APPEARANCE + ('LibreOfficeTheme',)), '1')
        self.assertEqual(tree.value(office.LO_COLORS + ('AccentColor', 'Color')), str(0xaabbff))
        self.assertEqual(tree.value(office.LO_COLORS + ('WindowTextColor', 'Color')), str(0xe0e4ef))
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o600)
        self.update(False)
        self.assertFalse(self.config.exists())
        self.assertFalse(self.journal.exists())

    def test_non_ui_settings_bytes_and_original_mode_restore(self):
        original = self.initial()
        self.put(original)
        self.update()
        untouched = '<prop oor:name="Unrelated"><value>preserve me &amp; unicode: Việt</value></prop>'.encode()
        self.assertIn(untouched, self.config.read_bytes())
        self.update(False)
        self.assertEqual(self.config.read_bytes(), original)

    def test_idempotency_and_dark_to_light(self):
        self.update()
        before = {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in (self.config, self.journal)}
        self.update()
        for path, (content, stamp) in before.items():
            self.assertEqual(path.read_bytes(), content)
            self.assertEqual(path.stat().st_mtime_ns, stamp)
        # Switching the source palette to light must change the actual
        # surfaces, not just darkmode metadata while keeping a dark canvas.
        self.palette.update({'darkmode': False, 'background': '#fafafa',
                             'surface': '#eeeeee', 'surface_container': '#f3f3f3',
                             'on_surface': '#202020', 'on_surface_variant': '#565656',
                             'primary': '#4b47a7', 'on_primary': '#ffffff'})
        self.update()
        tree = self.registry()
        self.assertEqual(tree.value(office.LO_APPEARANCE + ('ApplicationAppearance',)), '1')
        self.assertEqual(tree.value(office.LO_COLORS + ('AccentColor', 'Color')), str(0x4b47a7))
        self.assertEqual(len(tree.fields), len(office.libreoffice_values(self.palette)))

    def test_user_edit_to_managed_color_blocks_update_but_is_preserved_on_restore(self):
        self.update()
        key = office.LO_COLORS + ('AccentColor', 'Color')
        self.put(self.registry().changed({key: office.registry.property_xml('Color', '123456')}))
        edited = self.config.read_bytes()
        with self.assertRaises(office.UnsafeConfig):
            self.update()
        self.assertEqual(self.config.read_bytes(), edited)
        self.assertIn('1 user-edited', self.update(False))
        self.assertEqual(self.registry().value(key), '123456')

    def test_user_unrelated_edits_remain_after_restore(self):
        self.update()
        key = ('org.openoffice.Office.Common', 'Misc', 'UserSetting')
        self.put(self.registry().changed({key: office.registry.property_xml('UserSetting', '42')}))
        self.update(False)
        self.assertEqual(self.registry().value(key), '42')
        self.assertEqual(len(self.registry().fields), 1)

    def test_document_overrides_inherit_and_user_edits_are_not_palette_owned(self):
        previous = office.LO_BASE + ('ColorSchemes', 'MyScheme')
        tree = office.registry.Registry(None)
        original = tree.changed({office.LO_BASE + ('CurrentColorScheme',): office.registry.property_xml('CurrentColorScheme', 'MyScheme'),
            previous + ('DocColor', 'Color'): office.registry.property_xml('Color', '16777215'),
            previous + ('FontColor', 'Color'): office.registry.property_xml('Color', '234567'),
            previous + ('Links', 'IsVisible'): office.registry.property_xml('IsVisible', 'true')})
        self.put(original)
        self.update()
        doc = office.LO_COLORS + ('DocColor', 'Color')
        self.assertEqual(self.registry().value(doc), '16777215')
        self.assertEqual(self.registry().value(office.LO_COLORS + ('Links', 'IsVisible')), 'true')
        self.put(self.registry().changed({doc: office.registry.property_xml('Color', '654321')}))
        self.palette['primary'] = '#edbbff'
        self.update()
        self.assertEqual(self.registry().value(doc), '654321')
        self.assertEqual(self.registry().value(previous + ('DocColor', 'Color')), '16777215')
        self.update(False)
        self.assertEqual(self.registry().value(doc), '654321')
        self.assertEqual(self.registry().value(office.LO_BASE + ('CurrentColorScheme',)), 'MyScheme')

    def test_existing_unowned_named_scheme_is_not_adopted(self):
        key = office.LO_COLORS + ('DocColor', 'Color')
        original = office.registry.Registry(None).changed({key: office.registry.property_xml('Color', '17')})
        self.put(original)
        with self.assertRaises(office.UnsafeConfig):
            self.update()
        self.assertEqual(self.config.read_bytes(), original)

    def test_existing_empty_named_scheme_is_also_preserved(self):
        original = office.registry.EMPTY_REGISTRY.replace(b'</oor:items>',
            self.item('/org.openoffice.Office.UI/ColorScheme/ColorSchemes', '<node oor:name="AlisAuto"/>') + b'</oor:items>')
        self.put(original)
        with self.assertRaises(office.UnsafeConfig):
            self.update()
        self.assertEqual(self.config.read_bytes(), original)

    def test_missing_and_unsupported_versions_do_not_inspect_or_change_profile(self):
        self.put(b'not xml')
        for version in (None, '25.8.1', '26.10.0', '27.0.0'):
            self.update(version=version)
            self.assertEqual(self.config.read_bytes(), b'not xml')

    def test_missing_capability_preserves_profile(self):
        original = self.initial()
        self.put(original)
        with patch.object(office, 'check_libreoffice_schema', side_effect=office.UnsafeConfig('unsupported schema')):
            with self.assertRaises(office.UnsafeConfig):
                self.update()
        self.assertEqual(self.config.read_bytes(), original)
        self.assertFalse(self.journal.exists())

    def test_busy_process_or_profile_lock_defers_without_reading_content(self):
        self.put(b'not xml')
        with patch.object(office, 'app_busy', return_value=True):
            self.assertIn('deferred', self.update())
        lock = self.config.parent.parent / '.lock'
        lock.touch()
        self.assertIn('deferred', self.update())
        self.assertEqual(self.config.read_bytes(), b'not xml')

    def test_interrupted_write_is_recorded_and_recoverable(self):
        original = office.write_file
        def interrupted(path, content, expected):
            if path == self.config:
                raise PermissionError('fixture')
            return original(path, content, expected)
        with patch.object(office, 'write_file', side_effect=interrupted):
            with self.assertRaises(PermissionError):
                self.update()
        self.assertFalse(self.config.exists())
        self.assertIn('pending', json.loads(self.journal.read_bytes()))
        self.update()
        self.assertNotIn('pending', json.loads(self.journal.read_bytes()))

    def test_interrupted_write_with_concurrent_edit_never_replays(self):
        original = office.write_file
        def interrupted(path, content, expected):
            if path == self.config:
                raise PermissionError('fixture')
            return original(path, content, expected)
        with patch.object(office, 'write_file', side_effect=interrupted):
            with self.assertRaises(PermissionError):
                self.update()
        receipt = self.journal.read_bytes()
        changed = self.initial()
        self.put(changed)
        with self.assertRaises(office.UnsafeConfig):
            self.update(False)
        self.assertEqual(self.config.read_bytes(), changed)
        self.assertEqual(self.journal.read_bytes(), receipt)

    def test_missing_journal_cannot_restore_a_different_profile(self):
        self.update()
        self.config_home = self.base / 'another-config'
        with self.assertRaises(office.UnsafeConfig):
            self.update(False)
        self.assertFalse(self.config_home.exists())

    def test_serialized_namespace_and_flattened_registry_forms_are_supported(self):
        self.update()
        values = {key: self.registry().value(key) for key in self.registry().fields}
        flat = office.registry.EMPTY_REGISTRY
        for key, value in values.items():
            if key[:len(office.LO_COLORS)] == office.LO_COLORS:
                path = "/org.openoffice.Office.UI/ColorScheme/ColorSchemes/org.openoffice.Office.UI:ColorScheme['AlisAuto']/" + key[-2]
            else:
                path = '/' + '/'.join(key[:-1])
            flat = flat.replace(b'</oor:items>', self.item(path, office.registry.property_xml(key[-1], value).decode()) + b'</oor:items>')
        # Simulate a config engine serializing namespace prefixes/order.
        self.put(ET.tostring(ET.fromstring(flat), encoding='utf-8'))
        self.update()
        self.assertEqual(len(self.registry().fields), len(values))
        self.update(False)
        self.assertEqual(len(self.registry().fields), 0)

    def test_xml_entities_duplicate_and_localized_values_fail_safe(self):
        duplicate = office.registry.EMPTY_REGISTRY.replace(b'</oor:items>',
            2 * self.item('/org.openoffice.Office.UI/ColorScheme', '<prop oor:name="CurrentColorScheme"><value>x</value></prop>') + b'</oor:items>')
        cases = [b'not xml', b'<!DOCTYPE x [<!ENTITY a "secret">]><x>&a;</x>', duplicate]
        for data in cases:
            self.put(data)
            with self.assertRaises(office.registry.RegistryError):
                self.update()
            self.assertEqual(self.config.read_bytes(), data)

    def test_ambiguous_set_member_paths_are_rejected_instead_of_losing_scheme_overrides(self):
        for path in ["/org.openoffice.Office.UI/ColorScheme/ColorSchemes/Type['unfinished",
                     "/org.openoffice.Office.UI/ColorScheme/ColorSchemes/Type['John's scheme']",
                     "/org.openoffice.Office.UI/ColorScheme//ColorSchemes"]:
            data = office.registry.EMPTY_REGISTRY.replace(b'</oor:items>',
                self.item(path, '<node oor:name="DocColor"><prop oor:name="Color"><value>123</value></prop></node>') + b'</oor:items>')
            self.put(data)
            with self.assertRaises(office.registry.RegistryError):
                self.update()
            self.assertEqual(self.config.read_bytes(), data)
            self.assertFalse(self.journal.exists())

    def test_self_closing_root_and_attribute_angle_are_supported(self):
        original = ('<x:items xmlns:x="' + office.registry.OOR + '" note="a &gt; b"/>').encode()
        self.put(original)
        self.update()
        self.assertTrue(self.registry().fields)
        self.update(False)
        self.assertFalse(self.registry().fields)
        self.assertIn(b'note="a &gt; b"', self.config.read_bytes())

    def test_independent_adapters_continue_after_one_failure_or_invalid_flag(self):
        alis_config = self.base / 'alis-config.json'
        alis_config.write_text(json.dumps({'appearance': {'wallpaperTheming': {
            'enableOnlyOffice': True, 'enableLibreOffice': True}}}))
        with patch.object(office, 'run_locked', side_effect=[office.UnsafeConfig('fixture failure'), 'applied fixture']):
            output, result = office.run(alis_config, self.config_home, self.base / 'data', self.state_home)
        self.assertEqual(result, 1)
        self.assertIn('LibreOffice: applied fixture', output)
        alis_config.write_text(json.dumps({'appearance': {'wallpaperTheming': {
            'enableOnlyOffice': 'invalid', 'enableLibreOffice': True}}}))
        with patch.object(office, 'run_locked', return_value='applied fixture') as call:
            output, result = office.run(alis_config, self.config_home, self.base / 'data', self.state_home)
        self.assertEqual(result, 1)
        self.assertEqual(call.call_args.args[0], 'libreoffice')
        self.assertIn('LibreOffice: applied fixture', output)


if __name__ == "__main__":
    unittest.main(verbosity=2)
