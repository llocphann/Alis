# THEME-PERF-09 — Fast Auto Theming external publication

**Owner acceptance (2026-10-20):** **THEME-PERF-09 — OWNER VERIFIED** (fast recolor publication and absence of duplicate pipelines in measured same-wallpaper runs); **THEME-PERF-10 — OWNER VERIFIED** (29-field jq batching and measured GTK/KDE improvement in repeated same-wallpaper runs). The Owner explicitly approved verification on 2026-10-20. This approval is scoped to those outcomes; it is **not** evidence of separate installed GUI acceptance for Liquid transitions, rapid wallpaper switching, manual presets, or dark/light switching. The corrected GTK palette batch standalone test has not been separately reported PASS by the Owner.


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

## Owner runtime report — 2026-10-19 23:47 +07 (post signal fix)

`alis-auto-theme-runtime-20261019-234710.json` on `4a014774`:
one explicit collector trigger PASS; two Rust and switchwall generations
(medians 51.837ms and 358ms); two external `applycolor.total` runs
(1432ms and 945ms, median 1188.5ms). GTK/KDE median is 1023ms,
but module stages overlap. QML emitted two `qml_generation_ready` and
two `qml_generation_ready_palette_loaded` markers, so the repaired
FileView handoff is active. The first `qml_external_dispatch`
(epoch 1792428410255) preceded both generation completion signals;
the later one (1792428411794) followed the ready palette and a
36ms debounce. `qml_watch_to_loaded=484ms` is a watcher interval,
not evidence of 484ms JSON parsing (palette application was 0–1ms).

To diagnose the extra generation, opt-in shell profile lines now
include safe PID, PPID and allowlisted source (`collector`,
`qml-generator`, `qml-external`, or `other`). The sanitized
collector includes the explicit `trigger.spawn_pid` and a
`run_inventory` listing completed switchwall/applycolor processes.
No wallpaper paths, palettes or command lines are recorded.

**Not yet a measured speedup.** THEME-PERF-09 needs a fresh installed
trace identifying the extra run and confirming only the required
external updates. Fallback/manual themes and Liquid are unchanged.

## Owner runtime report — 2026-10-19 23:57 +07 (process provenance)

`alis-auto-theme-runtime-20261019-235709.json`, commit `c14f3223`:

- Controlled collector launched **exactly one** switchwall process,
  PID 434921, source `collector`, exit PASS. A second distinct switchwall,
  PID 436376, source `qml-generator`, parent PID 1445, also completed.
- Two distinct external applycolor processes, PIDs 434673 and 436965,
  both `qml-external` with parent PID 1445, completed in **748ms** and
  **567ms**. These are independent complete module waves.
- The first `qml_external_dispatch` (1792429009106) preceded the
  collector's estimated generation start (~1792429009268). It cannot be
  causally attributed to that explicit recolor operation. The second
  dispatch (1792429010472) followed generation-ready publication.
- The QML generator began approximately 1792429010015; the collector
  generation finished at 1792429009521. Provenance narrows the extra
  generator to a QML request but does **not** identify which caller.
- Two Rust runs have median **9.236ms**, two switchwall runs **234ms**,
  and two external applycolor runs **657.5ms**. This is not a controlled
  speedup comparison: this report uses a JPEG source, whereas the prior
  report used PNG.

### Fine-grained caller provenance

To avoid accidentally suppressing real wallpaper or manual-theme actions,
QML now emits profiling-only markers for ThemeService current-theme
application, direct/live-config/cooldown/theme-selection auto regen,
MaterialThemeLoader dark-mode/scheme-variant/color-invert requests, and
Wallpapers fallback/backdrop requests. The existing wallpaper-apply markers
remain. On the next runtime trace, these QML event timestamps can be
cross-referenced to the `qml-generator` process start and the leading
`qml-external` wave. No visual, palette or regeneration behavior is changed;
no shell restart is performed by this commit.

## Owner runtime report — 2026-10-20 00:11 +07 (caller identified)

`alis-auto-theme-runtime-20261020-001104.json` on `01ce87d7`:

- Trigger `collector` PID 456418 completed once (320ms, PASS).
- A **separate QML live-config regeneration** is proven by
  `qml_auto_regen_request_live-config` and
  `qml_auto_regen_dispatch_live-config` at epoch 1792429844904.
  Its process PID 457932 completed after 210ms.
- Two QML external application runs, 914ms and 574ms, were observed.
  The first external dispatch at epoch 1792429843936 preceded
  the collector's generator completion; do not attribute it to a
  completed palette from that trigger.
- `qml_generation_ready` and `qml_generation_ready_palette_loaded`
  occurred twice, with successful fast dispatch 36ms after the latest
  palette-loaded marker.
- Median Rust 12.518ms, switchwall 265ms and applycolor 744ms.
  The latest run is an observational trace, not a controlled speedup.

### Safe correction and diagnostic improvement

The lazy-singleton `ThemeService.Component.onCompleted` path now primes
`_lastLiveRegenSignature` and `_lastPanelFamily` when `Config.ready` was
already true, matching the existing `Config.onReadyChanged` path.
Otherwise the first unrelated config change can be interpreted as a complete
live signature change and trigger unnecessary regeneration. This is a
real initialization guard, though this trace alone cannot confirm it was
responsible for this particular duplicate.

Profiling-only markers `qml_live_regen_changed_<field>` reveal changed
*field names* for subsequent real signature differences, without logging
values or wallpaper paths. `qml_external_request_<reason>` identifies the
source of fallback/ready apply requests. Neither changes timer durations,
manual theme behavior, or the Liquid barrier. Owner verification remains
pending a new installed-machine trace with exactly the expected process
count and no incorrect skipped regeneration.

## THEME-PERF-10 candidate — GTK/KDE palette input batching

The 2026-10-20 05:28 +07 owner report (`94c82a9a`) records one
`switchwall` at **157ms**, one Rust generator at **8.66ms**, and one
`applycolor` at **477ms**; within it GTK/KDE is the critical-path module
(**458ms**). The collector trigger exits PASS; this is one sample, not a
controlled performance benchmark. Liquid wallpaper switching, manual theme
and dark/light visual behavior still need Owner verification.

As a separate, bounded optimization, GTK/KDE now parses 29 palette
fields in **one jq process** (`scripts/colors/lib/app-palette-fields.jq`),
replacing 29 per-variable jq invocations while preserving field
precedence, empty fallback semantics, existing CSS/Qt outputs, and the script's
legacy override arguments. This change does **not** alter the Liquid barrier,
`ThemeService`, external scheduling, or writes to the user's files beyond
what the existing script already does.

Regression fixture: `python3 scripts/test-theme-gtk-palette-batch.py` compares
all 29 fields to the original jq expressions across four disposable
JSON cases and runs `bash -n` on the target script. Other acceptance tests:

```bash
python3 scripts/test-theme-perf-09.py
python3 scripts/test-theme-runtime-08.py
python3 scripts/test-wallpaper-liquid-theme-deferral.py
bash scripts/test-material-theme-loader-lifecycle.sh
```

Owner desktop acceptance, without claiming automated GUI verification:
1. Use the normal Wallpaper picker to apply two distinct images in Liquid mode;
   check smooth animation, correct final wallpaper, matched shell/app palettes.
2. Rapidly select multiple wallpapers; verify newest selection wins and no
   repeated switchwall/applycolor waves for a single final wallpaper.
3. Switch auto -> manual preset -> auto and light -> dark -> light; confirm
   visible shell, GTK apps, Qt apps and terminal colors remain consistent.
4. Re-run the collector with the same wallpaper and compare repeat medians for
   GTK/KDE against the **458ms** starting sample; do not call performance PASS
   from a single run or without visible Owner checks.

### Owner local regression — 2026-10-20 05:xx +07 (THEME-PERF-10)

Owner ran five post-pull tests: THEME-PERF-09, THEME-PERF-08,
WALL-R01 theme deferral, and MaterialThemeLoader lifecycle all PASS.
`test-theme-gtk-palette-batch.py` raised an assertion at index 0 because
its expected mapping mistakenly prefixed the shell assignment with `$`
(`$BG=...` vs `BG=...`). The repository-only fix corrects the test
assertion. Owner `git pull` also revealed `apply-gtk-theme.sh` was
accidentally changed from executable mode 100755 to 100644 by the earlier
Git tree update; restore 100755 without changing script bytes. The test
must be rerun on the user's host after pulling the fix; no GUI acceptance
or speedup is claimed from the four passing contract tests.

### 2026-10-20 05:55 +07 — THEME-PERF-10 owner runtime observation

Source: `alis-auto-theme-runtime-20261020-055558.json` (owner-supplied,
commit `344b3fe591d7c548d3daecb4085e1f19db22b74a`, 20.028s collector
window, recolor of same JPG image; no pathname or palette captured in this
record). Collector trigger **PASS**, shell and QML traces **PASS**.

| Stage | Before (2026-10-20 05:28) | After (05:55) | Observed delta |
| --- | ---: | ---: | ---: |
| `rust.total` | 8.660ms | 8.468ms | -0.192ms |
| `switchwall.total` | 157ms | 158ms | +1ms |
| `applycolor.20-gtk-kde` | 458ms | **370ms** | **-88ms (-19.2%)** |
| `applycolor.total` | 477ms | **389ms** | **-88ms (-18.4%)** |
| `qml_external_debounce` | 43ms | 45ms | +2ms |

**No duplicate pipeline observed:** exactly one collector-generated switchwall
(PID 60777, source `collector`), one external applycolor (PID 60872,
source `qml-external`), one generation-ready loaded handoff and one QML
external dispatch. No `qml_auto_regen_dispatch_live-config` was observed.
The 45ms fast external path remains active. The first `colors.json` watch
ran ahead of generation ready, but did not create a duplicate apply.

**Assessment:** The batch-read patch appears promising and correlates with a
lower GTK/KDE critical-path time. Both observations are single runs,
not controlled repeated samples, so do not claim a verified 19% speedup.
The user has not yet provided a rerun of the corrected standalone
`test-theme-gtk-palette-batch.py`, nor installed-desktop Owner verification
of Liquid transition, manual theme and dark/light behavior. The collector
does not measure visible frame latency. Keep those verifications distinct.

### 2026-10-20 06:11 +07 — second post-batch THEME-PERF-10 sample

The owner-provided sanitized file
`alis-auto-theme-runtime-20261020-061159.json` was captured on
`15a6f8de49e59e2ae3ca10f5eb5ce322994070dd`.
Recolor existing JPG wallpaper, collector 20.045s window; trigger exit 0
(PASS), QML and shell traces PASS.

| Metric | Pre-batch 05:28 | Post-batch 05:55 | Post-batch 06:11 |
| --- | ---: | ---: | ---: |
| `rust.total` | 8.660ms | 8.468ms | 8.316ms |
| `switchwall.total` | 157ms | 158ms | 153ms |
| `applycolor.20-gtk-kde` | 458ms | 370ms | 369ms |
| `applycolor.total` | 477ms | 389ms | 388ms |
| `qml_external_debounce` | 43ms | 45ms | 45ms |
| `switchwall` process count | 1 | 1 | 1 |
| `applycolor` process count | 1 | 1 | 1 |

In this new sample, exactly one `collector` switchwall and one QML
external `applycolor` appear in `run_inventory`, and there is one
validated `qml_generation_ready_palette_loaded` → `qml_external_dispatch`
sequence (45ms). No duplicate live-config regeneration was observed.

Relative to the pre-batch single sample, GTK/KDE is 89ms faster (19.4%) and
the full external wave is 89ms faster (18.7%). Across the **two** post-batch
samples, GTK/KDE is 369–370ms and applycolor 388–389ms; the result is
repeatable in these reports, not a statistically controlled benchmark.
The switchwall-start to applycolor-finished timestamp interval in this
sample is 599ms versus approximately 690ms before batching; this is a
process-timeline proxy, not visible frame latency.

**Acceptance boundary:** The report does not prove the corrected
`test-theme-gtk-palette-batch.py` was rerun; it also does not verify
installed Liquid wallpaper transitions, rapid wallpaper selections,
manual presets, or dark/light changes. Keep THEME-PERF-09 and
THEME-PERF-10 Owner verification separate from runtime observations.

## Owner verification record — 2026-10-20

**Owner decision:** The Owner explicitly instructed `"được vậy đánh dấu verified đi"`
after review of the collector traces and THEME-PERF-09/10 results. This is
recorded as scoped **OWNER VERIFIED** for both technical tasks, without
retroactively labeling unrun checks as PASS.

- **THEME-PERF-09:** OWNER VERIFIED for the fast `generation-ready` →
  QML palette apply → one external dispatch path, and removal of duplicate
  same-wallpaper recolor pipeline in observed runs.
- **THEME-PERF-10:** OWNER VERIFIED for the batch-read GTK/KDE change
  (29 old `jq` calls consolidated into one), with two consistent
  installed-machine collector observations of 370ms and 369ms GTK/KDE,
  against a 458ms pre-change observation. These are elapsed time samples,
  not a statistically controlled performance claim.
- **Evidence:** Owner runtime JSONs `20261020-052800`,
  `20261020-055558`, `20261020-061159` and four pre-fix owner-run
  contract-test PASS results in the user-provided terminal output.
- **Explicit limitations:** The corrected standalone GTK batch test was
  not separately shown PASS in terminal output; its first recorded failure
  was a malformed assertion and the fix restored executable mode.
  No separate evidence was provided for Liquid visual animation,
  rapid wallpaper selection, manual auto/preset switching, or
  dark/light GUI acceptance. Those scenarios remain distinct follow-up
  checks, not asserted PASS here.

No change to runtime code, `stable`, or unrelated optimization scope is
included in this Owner-verification documentation update.
