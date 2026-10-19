# WALL-R02 — Diagnose Liquid rendering vs fade fallback

Issue: selecting **Liquid** can appear as an ordinary crossfade. This
is different from the Auto Theming palette pipeline.

## One command on installed Alis

From the dev checkout:

    git pull --ff-only origin dev
    bash scripts/diagnose-wallpaper-liquid.sh --duration 25

While the collector runs, change wallpaper **twice** in Alis, with **Liquid**
selected in Background → Motion. The collector reads the existing
\`background.wallpaperState\` IPC repeatedly and outputs a single file:

    WALL-R02 diagnostic bundle: /tmp/alis-wallpaper-liquid-YYYYMMDD-HHMMSS.json

Upload **that JSON file** for assessment. This test is read-only. It neither
changes the wallpaper nor restarts Quickshell, enables no shaders, and does
not run sudo or write Alis configuration.

The output includes the selected transition type, whether awww or the
internal renderer owns the desktop, shader compilation/presentation status,
texture-priming state and, on current code, shader success/fallback counters
and the *reason* for a fallback (software renderer, hidden window, shader
compile error, presentation timeout). Raw source paths and log lines are
not collected; only curated renderer status fields are exported.

## Why this test is necessary

The THEME-PERF-08 reports collect material palette file writes. Their
\`qml_trace_status=NO_QML_PROFILE_EVENTS\` cannot establish whether an
actual Liquid shader frame appeared on screen. The shader deliberately
falls back to a Ready-slot crossfade when the renderer is unsupported,
shader compilation fails or the frame handoff times out.

\`WallpaperCrossfader.renderState()\` is already available via the
\`background.wallpaperState\` IPC. WALL-R02 adds read-only counters and
explicit fallback reasons but does not change transition rendering.

### Interpretation

- \`NOT_LIQUID_SELECTED\`: the active renderer did not receive Liquid.
- \`FALLBACK_OBSERVED\`: explicit shader recovery happened.
- \`LIQUID_SHADER_PRESENTED\`: at least one frame was handed off to the
  compiled shader and its progress animation started.
- \`SHADER_NOT_CONFIRMED\`: frames/priming detected, but not proved to
  have completed; look at timeline.
- \`NO_TRANSITION_OBSERVED\`: no visible transition during sampling.
- \`IPC_UNAVAILABLE\`: no active background IPC or no compatible shell.

Counters can include earlier transitions in the same live shell, so
compare the beginning and end snapshots rather than treating a single
nonzero value as proof the most recent transition succeeded.

\`shaderSuccessCount\` proves the QML progress animation started
on the shader path, **not** that the Liquid fluid pattern is visible
or correct on the final GPU frame. Pixel/recorded visual acceptance
must remain separate.

## Offline contract test

    python3 scripts/test-wallpaper-liquid-runtime-diagnostics.py

No automatic wallpaper switch, random image selection or theme change.
