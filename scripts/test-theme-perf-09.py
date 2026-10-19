#!/usr/bin/env python3
"""THEME-PERF-09: safe fast external theming publication contract.

The shell segment runs only inside a disposable fixture; no user wallpaper,
config, generated theme output or Quickshell session is modified.
"""
from __future__ import annotations
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
QML = (ROOT / "services/MaterialThemeLoader.qml").read_text()
SHELL = (ROOT / "scripts/colors/switchwall.sh").read_text()
WALL = (ROOT / "services/Wallpapers.qml").read_text()


def require(value, reason):
    if not value:
        raise AssertionError(reason)


# All fast dispatch requests must wait for all generated files to finish.
begin = SHELL.index("    # THEME-PERF-09: complete-publication signal")
end = SHELL.index("    theme_perf_stage switchwall total", begin)
generate = SHELL.index('if "$SCRIPT_DIR/../native-dispatch" theme', 0, begin)
publish = SHELL.index('theme_perf_stage switchwall file_publication', generate)
forced = SHELL.index('theme_perf_stage switchwall forced_dark_terminal', publish)
vesktop = SHELL.index('"$SCRIPT_DIR/system24_palette.sh"', forced)
post = SHELL.index('post_process "$max_width_desired"', vesktop)
require(generate < publish < forced < vesktop < post < begin < end,
        "Fast readiness marker must be published after all outputs/modules")
require('if [[ "$theme_generation_succeeded" == "true" ]]' in SHELL[begin:end],
        "Failed generation must not publish the fast readiness marker")
require("theme-generation-ready.txt" in SHELL[begin:end]
        and "mktemp" in SHELL[begin:end]
        and "mv -f --" in SHELL[begin:end],
        "Generation-ready signal must be unique and atomic")
require('theme_perf_stage switchwall generation_ready ' in SHELL,
        "Generation-ready marker must be visible to the profiler")

# Do not touch existing Liquid deferral or its 150ms final-frame safety margin.
require('liquidThemeDeadline.interval = 150' in WALL
        and 'onTriggered: root._flushLiquidTheme()' in WALL,
        "Fast external apply must not compete with the Liquid transition")

require('FileView {\n        id: generationReadyFileView' in QML,
        "QML must watch generation-complete token, not guess the publish time")
require('generationReadyFileView.reload()' in QML
        and 'root._generationReadyPendingPalette = true' in QML,
        "Readiness must request an authoritative colors.json reload")
require('const applied = root.applyColors(fileContent)' in QML
        and 'if (root._generationReadyPendingPalette && applied)' in QML
        and 'root.requestExternalApply(true)' in QML,
        "Fast external run must be gated by successful QML palette apply")
require('root._lastGenerationReadyToken = token' in QML
        and 'if (!root._generationReadyFileChanged) return' in QML,
        "Stale startup marker must not trigger a fast external apply")
require('else if (token === root._lastGenerationReadyToken)' in QML,
        "Duplicate marker must not trigger duplicate jobs")
require('delayedExternalApply.interval = 45' in QML
        and 'delayedExternalApply.interval = 600' in QML,
        "Fast path should be shorter while retaining 600ms fallback")
require('delayedExternalApply.running && delayedExternalApply.interval === 45' in QML,
        "Older fallback requests must not delay a ready fast dispatch")
require('root._lastFastPaletteContent = fileContent' in QML
        and 'themeFileView.text() !== root._lastFastPaletteContent' in QML,
        "Late colors.json watcher must not schedule a duplicate external wave")
require('root._lastFallbackPaletteContent = fileContent' in QML,
        "Poll-timer retries must not restart the fallback debounce endlessly")
require('if (!root.isAutoTheme && !root._forceApply)' in QML
        and 'root._forceApply = false' in QML
        and 'return true' in QML.split("function applyColors(", 1)[1].split(
            "function _applyPalette(", 1)[0],
        "Manual theme/invalid palette must not count as a successful apply")
require('if (root.previewActive)' in QML
        and 'root._previewExternalDeferred = true' in QML,
        "The existing preview guard must remain active")

# Execute the real marker-producing shell statements inside a disposable
# function to prove atomic publication and suppression when generation fails.
shell_fragment = SHELL[begin:end]
with tempfile.TemporaryDirectory(prefix="alis-theme-perf09-") as workspace:
    state = Path(workspace)
    generated = state / "user" / "generated"
    generated.mkdir(parents=True)
    (generated / "colors.json").write_text('{"background":"#112233"}')
    (generated / "terminal.json").write_text('{"terminal":1}')
    marker = generated / "theme-generation-ready.txt"
    env = {**os.environ, "STATE_DIR": str(state)}
    for i in range(2):
        setup = f"""#!/usr/bin/env bash
set -euo pipefail
theme_perf_stage() {{ :; }}
run() {{
  local _theme_perf_total=""
  local theme_generation_succeeded="false"
{shell_fragment}
}}
run
"""
        outcome = subprocess.run(["bash", "-c", setup], env=env, text=True,
                                 capture_output=True, timeout=6)
        require(outcome.returncode == 0, "Failed-generation branch must not crash")
        require(not marker.exists(), "Failed-generation branch wrote marker")

    emitted = set()
    for i in range(7):
        setup = setup.replace('theme_generation_succeeded="false"',
                              'theme_generation_succeeded="true"')
        outcome = subprocess.run(["bash", "-c", setup], env=env, text=True,
                                 capture_output=True, timeout=6)
        require(outcome.returncode == 0, "Real marker branch failed: "
                + outcome.stderr[-300:])
        require(marker.exists(), "Ready marker was not published")
        token = marker.read_text().strip()
        require(token and token not in emitted, "Each publish must be unique")
        emitted.add(token)
        require(not list(generated.glob(".theme-generation-ready.*")),
                "No pending generation marker temp files should remain")
    require((generated / "colors.json").read_text() ==
            '{"background":"#112233"}',
            "Marker protocol changed authoritative palette")
    require((generated / "terminal.json").read_text() == '{"terminal":1}',
            "Marker protocol changed auxiliary palette")

# The Rust production-boundary check must match executable names, not
# prefixed runtime directories such as /alis-theme-perf08.
import re
assert re.search(r"/alis-theme(?![A-Za-z0-9_.-])", "/alis-theme-perf08") is None
assert re.search(r"/alis-theme(?![A-Za-z0-9_.-])", "/opt/bin/alis-theme") is not None

print("THEME_PERF_09_PASS ordered atomic publication, fallback, dedup, Liquid deferral")
