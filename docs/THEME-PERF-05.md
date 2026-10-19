# THEME-PERF-05 — One-command Auto Theming diagnostics

## Run once on your Alis computer

From the Alis repository (branch dev), use:

    git pull --ff-only origin dev
    bash scripts/collect-auto-theme-diagnostics.sh

This builds the checked-out Rust alis-theme binary and then runs all bundled
non-destructive tests and performance probes in one process.

At the end, copy the JSON filename from:

    THEME-PERF-05 diagnostic bundle: /tmp/alis-auto-theme-diagnostics-YYYYMMDD-HHMMSS.json

Upload **only that one JSON file**. It includes enough summary statistics for
a follow-up analysis. Full image paths, raw logs, config contents, and template
output files are not included.

## Automatically included

1. Rust backend and generated-state snapshot (read-only).
2. Existing regression scripts for file publication, CAVA, force-dark,
   SDDM deferral, loader lifecycle, Liquid deferral, profiler, and preview cache.
3. Rust/Python theme and template parity on a synthetic isolated fixture, if
   the optional Python libraries are installed (otherwise SKIP_DEPENDENCY).
4. Fixed-seed and current-image baseline, with CPU/wall timing distributions.
5. Extraction-size sweep: 64, 96, 128, 192, 256 (including seed/scheme
   changes and decode/resize/auto-scheme/quantization substage timings).
6. Original image vs. exact resolved-seed generation, comparing all five
   palette-related outputs for dark, light, invert, soften, strength and smart
   settings. Any mismatch is reported as a FAIL (a performance optimization
   must not sacrifice palette fidelity).
7. Synthetic template render comparison at 0/1/8/24 templates. All template
   manifests and destinations are explicitly inside the temporary sandbox.
8. Optional aggregation of existing opt-in QML/shell/external timing markers.

No sudo, root, Quickshell restart, wallpaper switch, app theme apply,
or SDDM synchronization is performed by this suite. Rust compilation updates
the checkout's native/target/release/alis-theme executable; if the installed
Alis backend selects this same path, future normal theme requests use the newly
built executable. The currently running Quickshell process is not restarted.
Nonzero test results remain FAIL;
missing optional Python libraries are marked SKIP_DEPENDENCY rather than PASS.

## Optional arguments

Specify a wallpaper manually if auto-detection cannot find an image:

    bash scripts/collect-auto-theme-diagnostics.sh --image "/path/to/wallpaper.jpg"

Control repetitions or save the report at an explicit path:

    bash scripts/collect-auto-theme-diagnostics.sh --runs 10 --matrix-runs 5 --out /tmp/my-theme-diagnostics.json

If you already have a Quickshell log with THEME-PERF-04 markers:

    bash scripts/collect-auto-theme-diagnostics.sh --runtime-log "/path/to/existing/log"

The collector only retains numeric aggregate timing markers from the log.
It does not launch a new Quickshell process or enable profiling on an existing
session. QML measurements require the shell to have been launched with
ALIS_THEME_PROFILE=1. True click-to-presented-frame latency, rapid user
wallpaper interactions, live CAVA/GTK/SDDM effects and CPU spikes during UI
transitions cannot be validated by a read-only suite. Those are separate
Owner-verified desktop acceptance checks.

## Developer validation

    python3 -m py_compile scripts/collect-auto-theme-diagnostics.py scripts/test-theme-perf-05.py
    bash -n scripts/collect-auto-theme-diagnostics.sh
    python3 scripts/test-theme-perf-05.py
    cargo test --manifest-path native/Cargo.toml -p alis-theme

The offline test uses a mocked Rust binary and private temporary fixtures.
