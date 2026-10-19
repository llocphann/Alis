#!/usr/bin/env python3
"""WALL-R02 offline test for Liquid diagnostics; never invokes running shell."""
import importlib.util
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
script = root / "scripts/diagnose-wallpaper-liquid.py"
component = (root / "modules/common/widgets/WallpaperCrossfader.qml").read_text()
spec = importlib.util.spec_from_file_location("wall_r02_diag", script)
diag = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diag)

for expected in ("shaderFallbackCount", "shaderSuccessCount", "lastShaderFallback",
                 "configuredTransition", "_noteShaderFallback"):
    assert expected in component, "missing diagnostic signal: " + expected
for reason in ("software_renderer", "window_not_presented",
               "presentation_timeout", "shader_compile_error"):
    assert reason in component, "missing shader fallback reason: " + reason

sample = [{
    "output": "eDP-1", "configuredPath": "/home/example/private-a.png",
    "external": False, "visible": True, "backdrop": False,
    "wallpaper": {
        "displayedSource": "file:///home/example/private-a.png",
        "pendingSource": "/home/example/private-b.png",
        "transitioning": True, "primePending": True,
        "shader": "alisMelt", "shaderStatus": 1, "shaderReady": True,
        "shaderPresented": False,
        "shaderRequested": True, "configuredTransition": "alisMelt",
        "shaderFallbackCount": 0, "shaderSuccessCount": 0,
        "lastShaderFallback": "",
    }
}]
parsed = diag.parse_ipc(json.dumps(json.dumps(sample)))
assert parsed == sample
outputs = diag.sanitize(parsed)
report_str = json.dumps(outputs)
assert "private-a.png" not in report_str
assert "private-b.png" not in report_str
assert outputs[0]["has_pending"]
assert outputs[0]["configured_matches_displayed"] is True
assert "deployment_state" in script.read_text()
assert "all_runtime_assets_match" in script.read_text()
s = diag.summary([{"elapsed_ms": 50, "outputs": outputs}], {})
assert s["seen_liquid_requested"] and s["seen_shader_active"]
assert s["interpretation"] == "SHADER_NOT_CONFIRMED"

sample[0]["wallpaper"].update({
    "shaderFallbackCount": 1, "lastShaderFallback": "presentation_timeout",
    "shader": "", "shaderPresented": False, "primePending": False,
})
fallback = diag.summary([{"elapsed_ms": 110, "outputs": diag.sanitize(sample)}], {})
assert fallback["interpretation"] == "FALLBACK_OBSERVED"
assert fallback["fallback_reasons"] == ["presentation_timeout"]

sample[0]["wallpaper"].update({
    "shaderFallbackCount": 1, "shaderSuccessCount": 1,
    "shaderPresented": True, "shader": "alisMelt",
})
success = diag.summary([{"elapsed_ms": 150, "outputs": diag.sanitize(sample)}], {})
assert success["interpretation"] == "LIQUID_SHADER_PRESENTED"

sample[0]["wallpaper"]["configuredTransition"] = "fade"
other = diag.summary([{"elapsed_ms": 250, "outputs": diag.sanitize(sample)}], {})
assert other["interpretation"] == "NOT_LIQUID_SELECTED"

print("WALL_R02_PASS read-only renderer IPC parsing, fallback attribution, path privacy")
