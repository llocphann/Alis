#!/usr/bin/env python3
"""Static guard for WALL-R01; native shader/pixel acceptance is a separate gate."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
cross = (root / "modules/common/widgets/WallpaperCrossfader.qml").read_text()
awww = (root / "services/AwwwBackend.qml").read_text()
ui = (root / "modules/settings/BackgroundConfig.qml").read_text()

def require(ok, message):
    if not ok:
        raise AssertionError(message)

require('readonly property bool shaderTransitionRequested: Quickshell.env("ALIS_DISABLE_LIQUID_SHADER") !== "1"' in cross,
        "Liquid shader must be requested by default, with an explicit local opt-out")
require("ALIS_EXPERIMENTAL_MELT" not in cross, "legacy opt-in must not gate the Liquid effect")
require('readonly property var shaderTransitionTypes: ["alisMelt"]' in cross
        and 'return value === "inirMelt" || shaderTransitionTypes.indexOf(value) >= 0' in cross
        and 'return isShaderTransitionType(raw) ? "alisMelt" : ""' in cross,
        "old persisted inirMelt must resolve to the shipped alisMelt binary")
require('transitionType !== "alisMelt" && transitionType !== "inirMelt"' in awww,
        "awww must not cover the internal Liquid surface for either saved alias")
require('case "alisMelt":' in awww and 'case "inirMelt":' in awww,
        "Liquid aliases must keep the duration control available")
require('Translation.tr("Liquid")' in ui and '["alisMelt", "inirMelt"].includes(' in ui,
        "Liquid selection must display correctly for both saved aliases")
require('_requestShaderPresentationFrame' in cross
        and 'shaderTransition.shaderPresented = true' in cross.split('function onFrameSwapped(): void {', 1)[1].split('if (!root._shaderTexturePrimePending)', 1)[0],
        "shader must only be promoted after a window frame, not on compilation")
require('root._shaderTexturePrimePending && newSource !== root._shaderTexturePrimeSource' in cross,
        "new wallpaper must supersede an obsolete pre-transition texture lease")
require('onTriggered: root._finishShaderWaitWithoutShader()' in cross,
        "stalled shader must settle by the Ready-slot fallback")
require((root / "modules/common/widgets/wallpaperTransitions/alisMelt.frag.qsb").is_file(),
        "Liquid shader binary must ship with the source")
print("WALL-R01 static contract: PASS (native Niri/Quickshell rendering untested)")
