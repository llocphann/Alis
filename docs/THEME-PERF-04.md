# THEME-PERF-04 — Auto Theming performance measurement

Status: instrumentation + isolated benchmark. **Not** an Owner desktop performance acceptance.

## 1. Safe, isolated Rust measurement

Build the Rust binary if required:

    cargo build --release --manifest-path native/Cargo.toml -p alis-theme

Benchmark a representative wallpaper **without changing the active theme**:

    python3 scripts/benchmark-auto-theming.py \
      --image "/absolute/path/to/wallpaper.jpg" --runs 10 --warmup 2 \
      --report /tmp/alis-theme-perf04.json

Or benchmark a fixed seed (fast, but NOT representative of image decoding):

    python3 scripts/benchmark-auto-theming.py --runs 10

Outputs and metadata go exclusively to a temporary directory that is deleted
after the run. The harness does not pass --render-templates, --cache, or user
configuration paths. It sets ALIS_THEME_SKIP_SDDM_SYNC=1 and does not start
Quickshell, modify wallpaper, or launch external theme modules.

The report records wall-time and child CPU-time distributions (median, p95,
min, max); Rust internal seed extraction, palette building and file write
times are also recorded. It intentionally does **not** claim that these measure
the time between a desktop click and a fully recolored shell.

## 2. Live session instrumentation (opt-in only)

Launch Alis with ALIS_THEME_PROFILE=1 in its environment using the normal
owner-controlled startup method. **Do not restart a running owner session just
for profiling without approval.** This enables small timing messages for:

- native Rust: seed_extract, palette_build, output_write, template_render,
  sddm_sync (when applicable), total
- switchwall: native_generation, file_publication, forced_dark_terminal,
  total
- QML MaterialThemeLoader: qml_palette_apply, qml_watch_to_loaded,
  qml_external_debounce, qml_external_dispatch
- external applycolor: individual module durations and total

Metrics are emitted on stderr (shell/Rust) or the Quickshell console (QML);
no profiling file or wallpaper path is written automatically. Collect the
logs using your existing Alis/Quickshell logging workflow. Only use logs you
have reviewed if you share them; ordinary application logs may contain paths.

Aggregate an existing log offline (no theme changes):

    python3 scripts/benchmark-auto-theming.py \
      --log /tmp/alis-theme-session.log \
      --report /tmp/alis-theme-runtime-summary.json

The analyzer reads at most the last 8 MB and reports only aggregate timing
metrics, not raw log lines. The QML timings use Date.now() and are therefore
millisecond-resolution estimates. Different stages may overlap; summing them
does not produce an end-to-end latency. For true click-to-visible end-to-end
measurement, correlate wallpaper request, matching generated palette, and
final presented frame for the same request on the installed session.

## 3. Comparisons and guardrails

Use the same wallpaper, mode, scheme, runtime load and number of samples
before/after a change. Compare median and p95 and look for unintended
regressions. Avoid performance claims without matching before/after traces.

Required follow-ups: rapid A/B/C wallpaper switching, scheme and forced-dark
switches, Liquid handoff, no duplicate external applies, preservation of
owner-selected settings, CPU usage, and correctness of SDDM / CAVA colors.
No user data, Quickshell process or wallpaper is modified by the isolated
benchmark.

Tests:

    python3 scripts/test-theme-perf-04.py
    bash -n scripts/colors/switchwall.sh
    bash -n scripts/colors/applycolor.sh
    bash -n scripts/colors/lib/theme-profile.sh
