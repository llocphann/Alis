#!/usr/bin/env python3
"""TERM-I01: regression checks for Alis-generated Yazi automatic theming."""
import ast
import os
import re
import tempfile
import tomllib
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scripts" / "colors" / "generate_terminal_configs.py"


def load_yazi_generator():
    """Load only the generator function, without importing unrelated theme tools."""
    tree = ast.parse(GENERATOR.read_text(encoding="utf-8"), filename=str(GENERATOR))
    function = next(
        node
        for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name == "generate_yazi_config"
    )
    namespace = {"os": os, "re": re, "Path": Path}
    module = ast.Module(body=[function], type_ignores=[])
    exec(compile(module, str(GENERATOR), "exec"), namespace)
    return namespace["generate_yazi_config"]


class YaziAutoThemeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.generate = staticmethod(load_yazi_generator())

    def render(self, colors, theme_contents=None):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            config_dir = home / ".config" / "yazi"
            config_dir.mkdir(parents=True)
            theme_path = config_dir / "theme.toml"
            if theme_contents is not None:
                theme_path.write_text(theme_contents, encoding="utf-8")

            flavor_path = config_dir / "flavors" / "ii-auto.yazi" / "flavor.toml"
            with patch.dict(os.environ, {"HOME": str(home)}):
                self.generate(colors, str(flavor_path))

            return (
                flavor_path.read_text(encoding="utf-8"),
                theme_path.read_text(encoding="utf-8"),
            )

    @staticmethod
    def colors():
        return {
            "term0": "#101018",
            "term15": "#F4F0FF",
            "term7": "#C5B8CE",
            "term8": "#51485A",
            "term1": "#E36F82",
            "term2": "#79CBA1",
            "term3": "#E7B86B",
            "term4": "#7AA2F7",
            "term5": "#C792EA",
            "term6": "#79DCE8",
            # Deliberately differ so the test proves the semantic accent wins.
            "primary": "#7AA2F7",
            "app_accent": "#D78ACF",
            "app_selection": "#493650",
            "app_on_selection": "#F9F0FF",
            "surface_container": "#2A2330",
        }

    def test_directory_rule_precedes_catch_all_and_uses_current_accent(self):
        flavor, _ = self.render(self.colors())
        filetype = flavor.split("[filetype]", 1)[1]
        directory_rule = '{ url = "*/", fg = "#D78ACF" }'
        catch_all_rule = '{ url = "*",  fg = "#C5B8CE" }'

        self.assertIn(directory_rule, filetype)
        self.assertIn(catch_all_rule, filetype)
        self.assertLess(filetype.index(directory_rule), filetype.index(catch_all_rule))
        self.assertIn('cwd = { fg = "#D78ACF" }', flavor)

    def test_focus_and_active_tab_use_semantic_selection_colors(self):
        flavor, _ = self.render(self.colors())
        self.assertIn(
            'current = { fg = "#F9F0FF", bg = "#493650" }', flavor
        )
        self.assertIn(
            'active   = { fg = "#F9F0FF", bg = "#493650" }', flavor
        )

    def test_snake_case_surface_token_fallback_keeps_focus_readable(self):
        colors = self.colors()
        colors.pop("app_selection")
        colors.pop("app_on_selection")
        colors["surface_container"] = "#302A38"

        flavor, _ = self.render(colors)
        self.assertIn(
            'current = { fg = "#F4F0FF", bg = "#302A38" }', flavor
        )
        self.assertIn(
            'active   = { fg = "#F4F0FF", bg = "#302A38" }', flavor
        )

    def test_current_yazi_schema_and_toml_are_valid(self):
        flavor, _ = self.render(self.colors())
        parsed = tomllib.loads(flavor)
        allowed = {
            "mgr": {
                "cwd", "find_keyword", "find_position", "marker_selected",
                "marker_copied", "marker_cut", "border_symbol", "border_style",
                "count_copied", "count_cut", "count_selected",
            },
            "indicator": {"current", "preview"},
            "tabs": {"active", "inactive"},
            "mode": {
                "normal_main", "normal_alt", "select_main", "select_alt",
                "unset_main", "unset_alt",
            },
            "status": {
                "sep_left", "sep_right", "progress_label", "progress_normal",
                "progress_error", "perm_type", "perm_read", "perm_write",
                "perm_exec", "perm_sep",
            },
            "input": {"border", "title", "value", "selected"},
            "pick": {"border", "active", "inactive"},
            "tasks": {"border", "title", "hovered"},
            "which": {"mask", "cand", "rest", "desc", "separator", "separator_style"},
            "help": {"chord", "action", "hovered"},
            "filetype": {"rules"},
        }
        self.assertEqual(set(parsed), set(allowed))
        for section, values in parsed.items():
            self.assertLessEqual(set(values), allowed[section], section)
        rules = parsed["filetype"]["rules"]
        self.assertTrue(all("name" not in rule for rule in rules))
        self.assertTrue(all("url" in rule or "mime" in rule for rule in rules))

    def test_theme_integration_preserves_unrelated_user_settings(self):
        existing_theme = (
            '[mgr]\n'
            'cwd = { fg = "#123456" }\n\n'
            '[flavor]\n'
            'dark = "another-dark"\n'
            'light = "another-light"\n'
        )
        _, theme = self.render(self.colors(), existing_theme)
        parsed = tomllib.loads(theme)
        self.assertEqual(parsed["mgr"]["cwd"], {"fg": "#123456"})
        self.assertEqual(parsed["flavor"]["dark"], "ii-auto")
        self.assertEqual(parsed["flavor"]["light"], "ii-auto")
        self.assertNotIn('use = "ii-auto"', theme)

    def test_theme_integration_migrates_legacy_use_only_inside_flavor(self):
        existing_theme = (
            '[custom]\n'
            'use = "keep-me"\n\n'
            '[flavor]\n'
            'use = "another-flavor"\n'
        )
        _, theme = self.render(self.colors(), existing_theme)
        parsed = tomllib.loads(theme)
        self.assertEqual(parsed["custom"]["use"], "keep-me")
        self.assertEqual(parsed["flavor"]["dark"], "ii-auto")
        self.assertEqual(parsed["flavor"]["light"], "ii-auto")
        self.assertNotIn("use", parsed["flavor"])

    def test_missing_theme_file_creates_dark_and_light_flavors(self):
        _, theme = self.render(self.colors())
        parsed = tomllib.loads(theme)
        self.assertEqual(parsed["flavor"], {"dark": "ii-auto", "light": "ii-auto"})

    def test_missing_selection_pair_uses_accent_foreground_fallback(self):
        colors = self.colors()
        colors.pop("app_selection")
        colors.pop("surface_container")
        colors.pop("surfaceContainer", None)
        colors["app_on_accent"] = "#101018"
        flavor, _ = self.render(colors)
        self.assertIn(
            'current = { fg = "#101018", bg = "#D78ACF" }', flavor
        )
        self.assertIn(
            'active   = { fg = "#101018", bg = "#D78ACF" }', flavor
        )


if __name__ == "__main__":
    unittest.main()
