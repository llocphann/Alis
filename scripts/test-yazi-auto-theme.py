#!/usr/bin/env python3
"""TERM-I01: regression checks for Alis-generated Yazi automatic theming."""
import ast
import os
import re
import tempfile
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
        cls.generate = load_yazi_generator()

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
        directory_rule = '{ name = "*/", fg = "#D78ACF" }'
        catch_all_rule = '{ name = "*",  fg = "#C5B8CE" }'

        self.assertIn(directory_rule, filetype)
        self.assertIn(catch_all_rule, filetype)
        self.assertLess(filetype.index(directory_rule), filetype.index(catch_all_rule))
        self.assertIn('cwd = { fg = "#D78ACF" }', flavor)

    def test_focus_and_active_tab_use_semantic_selection_colors(self):
        flavor, _ = self.render(self.colors())
        self.assertIn(
            'hovered         = { fg = "#F9F0FF", bg = "#493650" }', flavor
        )
        self.assertIn(
            'tab_active      = { fg = "#F9F0FF", bg = "#493650" }', flavor
        )

    def test_snake_case_surface_token_fallback_keeps_focus_readable(self):
        colors = self.colors()
        colors.pop("app_selection")
        colors.pop("app_on_selection")
        colors["surface_container"] = "#302A38"

        flavor, _ = self.render(colors)
        self.assertIn(
            'hovered         = { fg = "#F4F0FF", bg = "#302A38" }', flavor
        )
        self.assertIn(
            'tab_active      = { fg = "#F4F0FF", bg = "#302A38" }', flavor
        )

    def test_theme_integration_preserves_unrelated_user_settings(self):
        existing_theme = (
            '[mgr]\n'
            'linemode = "size"\n\n'
            '[flavor]\n'
            'use = "another-flavor"\n'
        )
        _, theme = self.render(self.colors(), existing_theme)
        self.assertIn('linemode = "size"', theme)
        self.assertIn('[flavor]\nuse = "ii-auto"', theme)


if __name__ == "__main__":
    unittest.main()
