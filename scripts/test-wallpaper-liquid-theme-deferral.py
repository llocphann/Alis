#!/usr/bin/env python3
"""WALL-R01: keep expensive color generation off the Liquid GPU transition."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
service = (root / "services/Wallpapers.qml").read_text()
desktop = (root / "modules/background/Background.qml").read_text()
waffle = (root / "modules/waffle/background/WaffleBackground.qml").read_text()
palette = (root / "services/MaterialThemeLoader.qml").read_text()
color_runtime = (root / "scripts/test-wallpaper-color-preview-runtime.py").read_text()
shader = (root / "modules/common/widgets/WallpaperCrossfader.qml").read_text()
runtime = (root / "scripts/test-wallpaper-background-apply-runtime.py").read_text()


def require(value, description):
    if not value:
        raise AssertionError(description)


require('function _shouldDeferThemeForLiquid(path: string): bool' in service
        and '(type === "alisMelt" || type === "inirMelt")' in service
        and '!AwwwBackend.active' in service,
        "only internal Liquid and its saved alias can defer theme generation")
require('!WallpaperListener.isVideoPath(path)' in service
        and '!WallpaperListener.isGifPath(path)' in service,
        "videos and GIFs must keep their existing apply flow")
require('function _deferLiquidTheme(path: string, darkMode: bool)' in service
        and 'function liquidWallpaperTransitionFinished(displayedSource: string)' in service,
        "deferred owner lifecycle must be exposed")
require('const rendered = FileUtils.trimFileProtocol(String(displayedSource ?? ""))' in service
        and 'const pending = root._pendingLiquidThemePath' in service
        and 'if (!pending || rendered !== pending)' in service,
        "a stale or preview transition must not flush a newer wallpaper")
require('liquidThemeDeadline.interval = 32' in service
        and 'onTriggered: root._flushLiquidTheme()' in service,
        "2-frame texture-prime window and hidden surfaces must apply theme changes in parallel")
require('liquidThemeDeadline.interval = 16' in service,
        "theme work begins after the 2-frame texture prime swap")
require('root._pendingLiquidThemePath = ""' in service
        and 'root._queueWallpaperScript(path, darkMode, false)' in service,
        "flush must atomically drain the latest request")
require('if (root._pendingLiquidThemePath !== "")' in service,
        "ThemeService suppression must survive the deferred interval")

main = service.split('function apply(path, darkMode', 1)[1].split('function applyColorsOnly', 1)[0]
require('Config.setNestedValue("background.wallpaperPath", normalizedPath)' in main
        and 'root._deferLiquidTheme(normalizedPath, darkMode)' in main
        and main.index('Config.setNestedValue("background.wallpaperPath", normalizedPath)')
            < main.index('root._deferLiquidTheme(normalizedPath, darkMode)'),
        "real wallpaper source must change immediately before any deferred theme work")
require('liquidThemeDeadline.stop()' in main
        and 'root._queueWallpaperScript(normalizedPath, darkMode, false)' in main,
        "non-Liquid backend must keep the immediate apply path")
require('Wallpapers.liquidWallpaperTransitionFinished(wallpaper.renderState().displayedSource)' in desktop
        and 'Wallpapers.liquidWallpaperTransitionFinished(wallpaper.renderState().displayedSource)' in waffle,
        "both desktop families must release deferred colors on actual transition finish")
require('tryVerify(()=>Wallpapers._pendingLiquidThemePath==="",3500)' in runtime,
        "native regression test must exercise hidden-wallpaper deadline")
require('root._shaderTexturePrimeSwaps < 2' in shader
        and 'fragmentShader: root._activeShader !== ""' in shader,
        "previously restored working Liquid shader/texture lifecycle must stay unchanged")
require('root._shouldDeferThemeForLiquid(normalizedPath))' in service
        and 'MaterialThemeLoader.previewWallpaperPresented(rendered)' in service,
        "carousel highlights must defer palette generation until their own rendered frame")
require('function previewWallpaperColors(path: string, thumbnail = "", deferUntilPresented = false)' in palette
        and 'root._previewWaitingForPresentation = Boolean(deferUntilPresented)' in palette,
        "normal callers must retain immediate palettes while Liquid defers work")
require('if (root._previewWaitingForPresentation || previewProcess.running' in palette
        and 'root._previewPending = {serial: ++root._previewSerial' in palette,
        "rapid preview selections must coalesce to the newest pending palette request")
require('String(path ?? "") !== root.previewPath' in palette,
        "stale compositor frame must never release the newer palette request")
require('previewFrameDeadline.interval = 32' in palette
        and 'previewFrameDeadline.interval = 16' in palette,
        "preview palette waits only 2 prime frames before running in parallel with shader presentation")
require('previewFrameDeadline.stop()' in palette
        and 'root._previewWaitingForPresentation = false' in palette,
        "closing/canceling the preview must disarm deferred palette work")
require('"/usr/bin/nice", "-n", "10"' in palette,
        "preview palette worker must not compete at normal CPU priority")
require('MaterialThemeLoader.previewWallpaperPresented(root.images+"b.png")' in color_runtime,
        "native palette test must exercise Liquid presentation handoff")
print("WALL-R01 theme deferral source contract: PASS (native Niri rendering not run)")
