# THEME-PERF-09 — Fast Auto Theming external publication

**Scope:** external application colors (terminal, GTK, editors, browser, etc.)
after wallpaper generation. The existing Rust seed cache (THEME-PERF-06)
and working Liquid animation remain unchanged.

## Before and after

Previously, QML restarted a **600ms** debounce after observing
`colors.json`, even if the generator had already finished publishing
`app-palette.json`, `terminal.json` and other outputs.

The new **fast path** uses a `theme-generation-ready.txt` token emitted
atomically by `scripts/colors/switchwall.sh` after successful native
generation, all generated auxiliary files, optional forced-dark terminal
generation and the shell's remaining post-processing. No marker is emitted
when native generation failed.

`MaterialThemeLoader.qml` watches that token and reloads `colors.json`
before any fast external work. Only a **successful QML palette application**
arms the short **45ms** coalescing interval. External modules do not read
half-written generated files. A separate 600ms debounce remains available
for callers without a ready signal, startup, stale watcher recovery,
failed native jobs and manual/global style changes.

Rapid identical token reloads are deduplicated; late `colors.json`
notifications do not schedule a second wave after the same ready palette.
The polling recovery loop never restarts fallback every 800ms for identical
data. During wallpaper previews, the existing deferred-external guard is
unchanged. The original Liquid barrier still waits for transition completion
plus a 150ms margin **before generator start**; we do not run CPU-intensive
theme work during the Liquid animation.

Potential ideal-case reduction in the *post-generation debounce* is 555ms
(600ms → 45ms), **not a measured end-to-end speedup**. Auxiliary generation,
QML reloading, and actual module durations still contribute. When a new
source has not been cached, Rust may spend longer extracting its seed.

## Owner runtime report — 2026-10-19 (pre signal fix)

`alis-auto-theme-runtime-20261019-233011.json`, commit `5d57720`,
captured one successful 20s recolor session:

- 2 Rust native generations (median 50.466ms), each reported a seed cache
  hit ~40.35ms. The full-content hash of a large PNG may dominate cache-hit
  cost; the earlier ~5ms isolated BMP cache result is not generalizable.
- 2 switchwall runs (median 290ms) and 2 atomic readiness publications.
- 1 earlier external apply (774ms) started *before* either generator's
  completion signal. This one apply is not evidence of the new fast path.
- 1 `qml_generation_ready` marker, but **zero**
  `qml_generation_ready_palette_loaded` markers and no subsequent
  `qml_external_dispatch`. Fast-path acceptance was therefore not confirmed.

The Quickshell FileView v0.3.2 `loaded` bool remains true during reload
of an already loaded file, while the `loaded()` signal fires for every
successful reload. Listening to `onLoadedChanged` can drop both the
ready token and colors.json follow-up; the amended QML listens to
`onLoaded` in both places. This preserves manual-theme safety gates,
fallback 600ms and the Liquid end-frame barrier.

The report also reveals a **possible duplicate recolor source** beyond
the profiler's explicit trigger; no per-process parent/initiator IDs
are available, so ownership of the extra generation is not yet known.
Do not mark end-to-end performance PASS until a new trace shows exactly
the fast ready-to-palette-to-dispatch sequence.

## Verification

Static publication/recovery and isolated atomic marker fixture:

    python3 scripts/test-theme-perf-09.py
    bash scripts/test-material-theme-loader-lifecycle.sh
    python3 scripts/test-theme-perf-04.py
    python3 scripts/test-theme-runtime-08.py
    bash -n scripts/colors/switchwall.sh

Live comparison **on the owner machine only**, no Quickshell restart:

    git pull --ff-only origin dev
    alis update

The standard `alis update` workflow may restart the installed shell,
so schedule it when convenient. Then collect an opt-in fresh runtime trace:

    bash scripts/collect-auto-theme-runtime.sh --trigger

The runtime JSON now reports `colors_to_generation_ready` and
`generation_ready_to_module_log` proxy intervals, if filesystem events
were observed. It also collects optional QML markers
`qml_generation_ready` and `qml_generation_ready_palette_loaded`.
File event timings indicate publication and are not GPU frame timing.
Some applications may update asynchronously after applycolor.sh exits.

## Safety

- Only the local `dev` tree is edited. No PR, no stable changes.
- The runtime token is a timestamp + process ID, not a wallpaper path,
  secret or palette value; the file is published with an atomic rename.
- Failed generation does not emit success; the previous external
  fallback path remains operational.
- No automatic Quickshell restart, wallpaper change or Owner verification.
- Real latency improvement and visual acceptance require a fresh installed
  desktop capture, not only CI/static tests.
