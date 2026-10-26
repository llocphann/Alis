#!/usr/bin/env python3
"""SET-R04: ensure Alis does not reintroduce a dedicated IME integration."""

from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
RETIRED = ("fc" + "itx", "uni" + "key")
# Provenance and frozen optimization research record previous code paths; they
# are not executed or shipped as active Alis-owned integration.
HISTORICAL_PREFIXES = (
    "docs/archive/", "docs/evidence/", "docs/abyss/validation/",
    "docs/aqua-visual/",
    "docs/optimization/STRICT_LOSSLESS_GPU_RAM_CPU_AUDIT.md",
)
TEXT_EXT = {".qml", ".js", ".mjs", ".cjs", ".py", ".sh", ".fish", ".kdl",
            ".json", ".md", ".nix", ".yaml", ".yml", ".txt", ".service"}
TEXT_NAMES = {"PKGBUILD", "Makefile", "qmldir", "setup", "alis"}


class InputMethodDecouplingTest(unittest.TestCase):
    def test_no_retired_backend_in_active_source(self):
        result = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT,
                                capture_output=True, check=True)
        matches = []
        for raw in result.stdout.split(b"\0"):
            if not raw:
                continue
            relative = raw.decode("utf-8")
            if relative.startswith(HISTORICAL_PREFIXES):
                continue
            path = ROOT / relative
            if not path.is_file() or not (path.suffix in TEXT_EXT or path.name in TEXT_NAMES):
                continue
            data = path.read_text(encoding="utf-8", errors="replace").lower()
            if any(token in data or token in relative.lower() for token in RETIRED):
                matches.append(relative)
        self.assertEqual(matches, [], f"Retired backend remains: {matches}")

    def test_keyboard_and_normal_tray_are_intact(self):
        niri = (ROOT / "modules/settings/NiriConfig.qml").read_text(encoding="utf-8")
        chat = (ROOT / "modules/sidebarLeft/AiChat.qml").read_text(encoding="utf-8")
        tray = (ROOT / "services/TrayService.qml").read_text(encoding="utf-8")
        for section in ("Keyboard", "Touchpad", "Mouse"):
            self.assertIn(f'title: Translation.tr("{section}")', niri)
        self.assertIn("inputMethodComposing", chat)
        self.assertIn("property list<var> pinnedItems:", tray)
        self.assertIn("property list<var> unpinnedItems:", tray)

    def test_no_automatic_ime_session_start(self):
        # Both the modular defaults and compatibility config are shipped sources.
        sources = (
            "scripts/alis",
            "sdata/subcmd-install/3.files.sh",
            "defaults/niri/config.d/50-startup.kdl",
            "dots/.config/niri/config.kdl",
        )
        for relative in sources:
            source = (ROOT / relative).read_text(encoding="utf-8")
            with self.subTest(path=relative):
                self.assertNotIn("input-method start", source)
                self.assertNotIn('"input-method" "start"', source)

    def test_niri_configs_do_not_force_retired_ime(self):
        for relative in (
            "defaults/niri/config.d/40-environment.kdl",
            "defaults/niri/config.d/50-startup.kdl",
            "dots/.config/niri/config.kdl",
        ):
            source = (ROOT / relative).read_text(encoding="utf-8").lower()
            for retired in RETIRED:
                with self.subTest(path=relative, backend=retired):
                    self.assertNotIn(retired, source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
