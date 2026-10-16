#!/usr/bin/env python3
"""WALL-R01: disabled workspace/sidebar parallax must not move Liquid wallpaper."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
background = (root / "modules/background/Background.qml").read_text()
runtime = (root / "scripts/test-wallpaper-background-apply-runtime.py").read_text()
defaults = json.loads((root / "defaults/config.json").read_text())
cross = (root / "modules/common/widgets/WallpaperCrossfader.qml").read_text()

def require(value, reason):
    if not value:
        raise AssertionError(reason)

parallax = defaults["background"]["parallax"]
require(parallax["enable"] is False and parallax["enableWorkspace"] is True
        and parallax["enableSidebar"] is True,
        "regression must cover saved sub-flags left on after main Parallax is disabled")

use_parallax = background.split("readonly property bool useParallax:", 1)[1].split(
    "readonly property bool showInternalStaticWallpaper:", 1
)[0]
require("bgRoot.dynamicParallaxRequested" in use_parallax,
        "internal Liquid wallpaper must obey actual enabled workspace/sidebar parallax")
require("bgRoot.fillMode" in use_parallax
        and "!bgRoot.externalMainWallpaperActive" in use_parallax,
        "preserve internal-renderer and supported-fill-mode gates")

require("readonly property bool workspaceParallaxEnabled: bgRoot.parallaxEnabled" in background
        and "readonly property bool sidebarParallaxEnabled: bgRoot.parallaxEnabled" in background
        and "readonly property bool dynamicParallaxRequested: bgRoot.workspaceParallaxEnabled || bgRoot.sidebarParallaxEnabled" in background,
        "sub-flags must be ANDed with the main Parallax preference")
require("readonly property bool effectiveHasPan: bgRoot.hasPan" in background
        and "readonly property real targetWidth: (useParallax || bgRoot.effectiveHasPan)" in background
        and "readonly property real targetHeight: (useParallax || bgRoot.effectiveHasPan)" in background,
        "explicit manual Pan/Zoom remains supported independently")
require("readonly property real targetX: useParallax" in background
        and "readonly property real targetY: useParallax" in background
        and ": panOffsetX" in background and ": panOffsetY" in background,
        "non-parallax image position must avoid inferred offset from decoded dimensions")
require('objectName: "desktopWallpaperContainer"' in background
        and 'findChild(window.contentItem,"desktopWallpaperContainer")' in runtime,
        "private native test must inspect actual desktop container geometry")
require('check(neutral(),"new wallpaper metrics shifted desktop with parallax off")' in runtime
        and 'check(neutral(),"wallpaper metrics restoration moved desktop with parallax off")' in runtime,
        "private native test must simulate asynchronous different image dimensions")
require('data["background"]["parallax"]["enable"] = False' in runtime
        and 'data["background"]["parallax"]["enableWorkspace"] = True' in runtime
        and 'data["background"]["parallax"]["enableSidebar"] = True' in runtime,
        "native fixture must exercise off-with-saved-subflags-on configuration")
require('readonly property var shaderTransitionTypes: ["alisMelt"]' in cross
        and 'function onFrameSwapped(): void' in cross,
        "Liquid shader source selection and previously verified frame priming remain intact")
print("WALL-R01 disabled-parallax geometry contract: PASS; native visual check separate")
