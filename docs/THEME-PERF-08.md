# THEME-PERF-08 — One-command live Auto Theming diagnostics

## Owner command

First pull the new scripts:

    git pull --ff-only origin dev

Then collect a real shell/external-apply trace with **one command**:

    bash scripts/collect-auto-theme-runtime.sh --trigger

The command temporarily enables runtime profiling, then **regenerates the
current wallpaper's colors** with \`--noswitch --skip-config-write\`. It does
not change the selected wallpaper, edit the main config, restart Quickshell,
or request sudo. This is a live theme apply, so enabled applications and
SDDM integrations may update as they normally would. The generator's own
synchronous SDDM sync is skipped; Quickshell's external theming may still
invoke the SDDM integration if enabled.

For manual testing of A/B/C wallpaper switching and Liquid in one capture,
use read-only/passive monitoring and change wallpapers in Alis while it runs:

    bash scripts/collect-auto-theme-runtime.sh --duration 35

The collector writes one sanitized JSON file in \`/tmp\`:

    THEME-PERF-08 diagnostic bundle: /tmp/alis-auto-theme-runtime-YYYYMMDD-HHMMSS.json

**Upload that one JSON file.** It contains only numeric timing markers,
event names, and aggregate durations. It omits wallpaper paths, config
values, actual palette colors and raw application logs.

## What is measured

1. Kernel filesystem events for \`colors.json\`, \`app-palette.json\`,
   \`terminal.json\`, \`theme-meta.json\`, and themed module logs.
2. QML timeline markers from Quickshell's existing decoded log when available:
   wallpaper request/dispatch, palette load/apply, external debounce/dispatch.
3. Rust generation and module durations, appended to a **private temporary
   trace** only while the collector holds the runtime profiling marker.
4. Coarse publication intervals from colors.json to app palette and terminal.

QML controls monitor \`\${XDG_RUNTIME_DIR}/alis-theme-perf08/enabled\` and
periodically reload the tiny marker, allowing an **already running, updated
MaterialThemeLoader** to activate logging without a restart. The collector
removes the marker after capture. If the active shell still contains the old
QML code (or hot reload is disabled), the report explicitly says
\`NO_QML_PROFILE_EVENTS\`; kernel file events can still be collected.

The script **does not** claim frame presentation timing or absolute
wallpaper-click-to-visible-frame latency. A QML \`palette_apply\` marker
measures synchronous property updates, which are not the same as GPU
presentation. External module stages can overlap; sums are not end-to-end
latency. Absence of events is recorded, never inferred as success.

## Verification

    python3 scripts/test-theme-runtime-08.py
    bash -n scripts/collect-auto-theme-runtime.sh
    bash -n scripts/colors/lib/theme-profile.sh
    bash -n scripts/colors/switchwall.sh

If you want to compare with the previous Rust-only benchmark, retain the
THEME-PERF-06 JSON alongside this new runtime JSON. There is no need to
rerun the entire image-size matrix to diagnose external theme latency.
