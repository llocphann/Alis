#!/usr/bin/env python3
"""Source contract for deferring SDDM work behind the palette publication event."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
loader = (root / "services/MaterialThemeLoader.qml").read_text()
wallpapers = (root / "services/Wallpapers.qml").read_text()
theme_service = (root / "services/ThemeService.qml").read_text()
generator = (root / "scripts/colors/generate_colors_material.py").read_text()
sddm = (root / "scripts/sddm/sync-pixel-sddm.py").read_text()
rust = (root / "native/alis-theme/src/main.rs").read_text()
target = (root / "scripts/colors/targets/sddm.json").read_text()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


require("function wallpaperSwitchCommand(args)" in loader
        and "root.defaultApplyExternal && appsAndShellEnabled" in loader
        and '"ALIS_THEME_SKIP_SDDM_SYNC=1"' in loader,
        "only a live shell with external theming enabled may defer the synchronous SDDM hook")
require("MaterialThemeLoader.wallpaperSwitchCommand([" in wallpapers
        and "MaterialThemeLoader.wallpaperSwitchCommand([" in theme_service,
        "wallpaper changes and config-driven regeneration must use the guarded command helper")
require('os.environ.get("ALIS_THEME_SKIP_SDDM_SYNC") != "1"' in generator
        and "ALIS_THEME_SKIP_SDDM_SYNC" in rust,
        "both Python fallback and Rust backend must honor the same defer flag")
require('"configKey": "appearance.wallpaperTheming.enableAppsAndShell"' in target,
        "the deferred follow-up must retain the same enabled/disabled gate as the SDDM module")
require("if content == original_content:" in sddm
        and "filecmp.cmp(src, dst, shallow=True)" in sddm
        and "video_stamp_path" in sddm,
        "the deferred SDDM worker must skip unchanged config/avatar/static wallpaper work and cache video frames")
print("THEME_SDDM_DEFERRAL_PASS live-shell gate, Rust/Python parity, module enablement and no-op sync")
