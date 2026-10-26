# Cross-repo optimization handoff

> **ARCHIVED / SUPERSEDED — 2026-10-07.** Active optimization research now lives in [`docs/optimization/STRICT_LOSSLESS_GPU_RAM_CPU_AUDIT.md`](../../optimization/STRICT_LOSSLESS_GPU_RAM_CPU_AUDIT.md). Preserve this file as historical research/evidence; do not append new rounds here.

## 2026-10-06 — Maintainer-scoped Screen Edge analytic renderer

The maintainer explicitly prioritized Screen Edges before Aqua and authorized
implementation in two classes: strict-lossless changes, and very small visual
deviation only when it buys a large rendering reduction. This checkpoint is
separate from the generic research-only optimization program.

### Implemented healthy path

- `modules/screenCorners/ScreenEdgeField.frag` +
  `ScreenEdgeField.qml` are the normal physical Screen Edge painter.
- The healthy path is one output-local analytic rounded-box SDF
  `ShaderEffect`: **zero texture samples, zero ShaderEffectSource capture,
  zero blur-pyramid intermediates and zero MultiEffect pass**.
- The accepted historical odd-even `ShapePath` / four-`PathArc` /
  `MultiEffect` renderer remains available only through a lazy
  `ShaderEffect.Error` Loader. It is not constructed on a healthy shader path.
- The exact existing frame insets, Bar-owned edge thickness, radius token,
  reservation windows, mapping/fullscreen lifecycle and click-through ownership
  remain unchanged.
- Shader QColor inputs use Qt's premultiplied representation correctly; no
  second alpha multiplication is applied.
- The inward physical shadow uses a three-band analytic response
  (sharp shoulder / middle rolloff / faint tail) chosen to track the accepted
  Qt 6.11 MultiEffect profile without sampling the blur pyramid.
- Deep workspace fragments are rejected before `length`, `fwidth` and
  `smoothstep`. The guard is geometry-safe and is covered by 50,000
  deterministic randomized cases. At the default 1920x1080 / 10 px frame /
  25 px radius / 15 px shadow geometry, about **92.9% of output pixels** fall
  into that guaranteed deep-interior early-return region. This is a structural
  fragment-work reduction, not a measured whole-GPU speedup percentage.
- The physical shadow work remains disabled when a fullscreen client covers the
  output and in minimal Game Mode, while the FrameWindow mapping lock remains
  intact.
- Screen Edge workspace-Overview support is lazy: bottom/left/right reservations
  no longer instantiate unusable Overview stacks, and a normal horizontal-Bar
  configuration retains no workspace-Overview support stack in Screen Edges.

### QSB source identity

`.github/workflows/screen-edge-shader-bake.yml` builds the shader twice and
requires byte equality between those two same-toolchain outputs. Publication is
fail-closed: it verifies that current `dev` still contains the exact GLSL
source that was baked before updating only
`modules/screenCorners/ScreenEdgeField.frag.qsb`.

The QSB corresponding to the current three-band field was published by commit
`f5e5a2ae232303c5f012ae87463472c362c490fa`. Later commits in this checkpoint
change tests/docs/job dispatch only, not the shader source.

### Validation status

At exact checkpoint `44a1b978c358d05eb3b67e5d9f48647dc415f0d2`,
the repository-wide CI invocation of the canonical validator reported:

- `test-screen-edge-analytic-field-contract.py`: PASS;
- `test-screen-edge-analytic-perceptual.py`: process PASS (owner-session visual
  mode was not enabled by canonical CI, so this is not live visual acceptance);
- `test-screen-edge-shadow-padding-parity.py`: PASS;
- `test-screen-edge-shadow-raster-perceptual.py`: process PASS (same
  owner-session qualification caveat);
- `test-shell-elevation-shadow-contract.py`: PASS;
- `test-shell-surface-contracts.py`: PASS;
- `test-bar-orientation-module-sync.py`: PASS;
- `test-performance-lifecycle.sh`: PASS;
- documentation contracts: PASS.

The same canonical run completed **417 PASS / 11 FAIL / 12 SKIP**. None of the
11 failures were Screen Edge failures; they were existing Abyss/Aqua and
MegaQML checks outside this scoped task. Do not present that run as a repository
canonical PASS.

The deterministic local worker has not published analytic Screen Edge receipts:
R63 through R69 remain pending while results stop at R62. Therefore the
authoritative local canonical PASS is **not claimed** for this checkpoint.

### Remaining acceptance boundary

Implementation/source work for this Screen Edge optimization is complete.
Two environment-owned acceptance items remain separate and must not be inferred
from source inspection:

1. run the analytic-vs-pre-cutover owner-session A/B with
   `HADALIS_SCREEN_EDGE_ANALYTIC_PERCEPTUAL=1` and retain the reported
   `global_mae` / edge-band diagnostic; the intended budget is <= 1% global
   normalized mean pixel error;
2. visually verify real Niri/Quickshell idle/maximized/fullscreen,
   top/bottom/left/right Bar ownership, fractional scaling and multi-output
   behavior on the exact runtime SHA.

No whole-Hadalis CPU/GPU/RAM/FPS percentage is claimed without before/after
measurement.


## 2026-10-06 — Screen Edge strict-lossless continuation checkpoint

This section supersedes the earlier full-output analytic-painter implementation
details while preserving the same visual/SDF contract. The maintainer requested
continued Screen Edge optimization with strict-lossless changes preferred and a
visual budget below 1% only where necessary.

### Additional implemented reductions

- **Adaptive four-tile rasterization.** The analytic field is no longer drawn as
  one full-output quad. Four disjoint `ShaderEffect` tiles cover only the
  perimeter region that can produce non-zero pixels; the centre is never
  rasterized. All tiles evaluate the same output-local SDF through `tileRect`.
- **Cheapest-axis partition selection.** The wrapper evaluates horizontal-corner
  and vertical-corner four-tile partitions and selects the smaller raster area
  without adding draw calls. At the default 1920x1080 / 10 px inset / 25 px
  radius / 15 px shadow geometry, the structural fragment-invocation footprint
  is below **9.7% of the output**; at 3840x2160 it is below **4.9%**. These are
  raster-area ratios, not measured GPU speedup percentages.
- The 50,000-case geometry oracle proves every omitted pixel belongs to the
  already-proven transparent deep-interior region. The owner-session
  `test-screen-edge-banded-perceptual.py` separately retains the <=1% global
  normalized-MAE budget for seam/derivative verification.
- **Exact SDF fast paths.** Straight-edge samples skip Euclidean
  `length/sqrt`; a 200,000-case float32 oracle requires bit-identical output
  against the canonical rounded-box formula. Exact outside/inside AA/shadow
  regions also bypass unnecessary smoothstep/composition work.
- **Minimal safe band bounds.** Conservative padding that was not needed by the
  proven SDF/shadow reach was removed; per-side shallow/deep extents retain the
  complete corner/shadow support.
- **Covered-frame sleep.** The physical FrameWindow remains mapped across
  fullscreen as required by the stacking lock, but `updatesEnabled` is false
  while the fullscreen client completely covers it.
- **Transparent reservation sleep.** Bottom/left/right reservation windows
  paint nothing and no longer render-update. The top reservation renders only
  when vertical-Bar workspace-Overview hover support is actually available;
  mapping, exclusive-zone and input-mask state remain independent.
- **Legacy type-graph isolation.** `QtQuick.Shapes` and `QtQuick.Effects`
  moved into `ScreenEdgeLegacyFallback.qml`, loaded by URL only after aggregate
  tiled `ShaderEffect` failure. The healthy ScreenEdges.qml path no longer
  imports or embeds the legacy Shape/MultiEffect graph.
- **Output-targeting allocation removal.** The old
  `Quickshell.screens.filter(...)` temporary result array is replaced by a
  complete-order scan that records only whether any configured output exists.
  A 50,000-case behavior/read-order oracle preserves answers and full screen
  traversal/dependency order.
- **Fallback bridge binding compaction.** The inactive legacy Loader previously
  kept ten value-proxy bindings per output (four insets, radius, padding,
  shadow state/size/color and edge color) resident even though the fallback
  renderer was not loaded. The healthy path now retains only two object
  references (`edgeRoot` + `frameHost`); all fallback value bindings are
  instantiated only after an actual tiled ShaderEffect error. This removes
  **8 resident fallback bindings per output** without changing fallback values
  or visual behavior.

The current analytic QSB containing the exact-SDF fast paths was published by
`f7d8d2d282326c2f906f2c385cca19ee5d1660f2`. Later commits in this
checkpoint change QML partitioning, lifecycle gating, tests and documentation;
they do not change the fragment shader source.

### Scoped validation

At exact runtime/source checkpoint
`254f7d3db6a787d6cdda444c778d3750fd574f83`, the repository-wide CI
invocation of the canonical validator completed **419 PASS / 11 FAIL / 12
SKIP**. The dedicated Nix package workflow for the same exact SHA also
completed successfully. All Screen Edge and connected-perimeter checks relevant to this work
passed, including:

- `test-screen-edge-analytic-field-contract.py`;
- `test-screen-edge-banded-perceptual.py` in its canonical process/skip mode;
- `test-screen-edge-output-targeting.py`;
- `test-screen-edge-shadow-padding-parity.py`;
- `test-shell-elevation-shadow-contract.py`;
- `test-shell-surface-contracts.py`;
- `test-bar-orientation-module-sync.py`;
- `test-performance-lifecycle.sh`;
- `test-perimeter-compatibility-placement-contract.sh`;
- packaging/make contracts and source-tree cleanliness.

The remaining 11 failures are existing Abyss/Aqua and MegaQML checks outside
this scoped Screen Edge task. Therefore this is a **scoped Screen Edge
validation checkpoint**, not a repository-wide canonical PASS. The CI host also
lacked `qmlformat`, so the strict parser pass remains unclaimed on this exact
SHA.

The deterministic local worker remains stalled with Screen Edge results ending
at R62 while R63-R69 remain pending. Do not create additional duplicate worker
jobs until that transport/backlog issue is resolved.

### Completion boundary

The current Screen Edge optimization implementation pass is complete through
`254f7d3db6a787d6cdda444c778d3750fd574f83`. No further runtime candidate is
promoted here because remaining ideas either add draw-call complexity, alter
QML reactive topology, or produce only micro-level savings relative to the
already-bounded raster footprint.

Live owner-session acceptance remains separate:

1. run `HADALIS_SCREEN_EDGE_BANDED_PERCEPTUAL=1
   python3 scripts/test-screen-edge-banded-perceptual.py` and retain
   `global_mae`, `edge_mae` and `max_channel_delta`; intended global budget
   is <=1%;
2. run the existing analytic-vs-pre-cutover visual fixture if historical visual
   comparison is still desired;
3. verify real Niri/Quickshell multi-output, fractional scaling, Bar ownership
   and fullscreen transitions.

No whole-Hadalis CPU/GPU/RAM/FPS percentage is claimed without before/after
measurement.

## 2026-10-06 — subsystem removal boundary

The maintainer removed the Hadalis Automation subsystem and the MegaQML/MEGAcmd
Cloud Storage integration from current `dev`. Older worker queues/results,
MegaQML failures, Cloud Storage qualification notes and exact-SHA validation
counts above are historical evidence only; they are not current runtime,
packaging or validation dependencies. Future work must use repository tests and
the canonical maintainer validator directly and must not dispatch local worker
jobs or expect MegaQML/Cloud Storage routes.

## 2026-10-07 — Wallpaper thumbnail queue strict-lossless research

Research-only continuation on current `dev`
`08fcc563311cde0e218672f4f97df006377e7a61`. No runtime/product source was
changed in this round.

Current source identities:

- `services/Wallpapers.qml`:
  `162dc98dcb742d7dec918a1da01659ef64265330`;
- `modules/common/widgets/ThumbnailImage.qml`:
  `64386a41505f5b1a3dc4942b2a549b04d0f0cf59`;
- `scripts/thumbnails/thumbgen.py`:
  `fdc9ce7e4557a4296e45e8d25aea9101caf90fa1`.

Repository/history search found no prior optimization note for
`_singleThumbPending`, `_knownThumbnailOutputs` or `_ffPending`.
This is distinct from the older Dashboard projection/overlap research.

### Candidate A — HIGH CONFIDENCE: stop cloning private thumbnail bookkeeping maps

`Wallpapers` currently uses copy-on-write for two private maps:

```qml
const pending = Object.assign({}, root._singleThumbPending)
pending[key] = true
root._singleThumbPending = pending
```

and:

```qml
const nextKnown = Object.assign({}, root._knownThumbnailOutputs)
nextKnown[normalizedPath] = true
root._knownThumbnailOutputs = nextKnown
```

The corresponding delete paths clone again before deleting the key.

Repository-wide search shows:

- `_singleThumbPending` is read/written only inside `Wallpapers.qml`;
- `_knownThumbnailOutputs` is exposed only through imperative
  `hasKnownThumbnail()/rememberThumbnail()/forgetThumbnail()`;
- no QML binding, `Connections`, change handler or external consumer depends
  on either property's change notification.

Therefore the copy-on-write reassignment is not part of the observable
contract. Directly mutating the private object preserves the current
dedup/existence answers while avoiding whole-map copies.

The allocation shape is materially worse than O(n): enqueueing n distinct
single-thumbnail requests copies approximately 0+1+...+(n-1) keys; draining
them copies the shrinking pending map again. The known-output set similarly
copies all previously known thumbnail paths on each newly learned path.
This can become quadratic JS key-copy/allocation work while browsing a large
wallpaper library.

Required oracle before implementation:

1. enqueue repeated and distinct thumbnail keys;
2. prove one queued request per unique pending key;
3. finish requests in success/failure order and prove pending membership parity;
4. prove `hasKnownThumbnail` answers are identical across remember/forget;
5. include empty/malformed paths and source-size changes.

No visual deviation is expected; this is bookkeeping-only.

### Candidate B — HIGH CONFIDENCE, protocol-gated: eliminate post-batch per-delegate `test -f` process fan-out

`ThumbnailImage.reloadThumbnail()` starts a dedicated Process when a thumbnail
path is not already in the shared known set:

```qml
_thumbnailCheckProc.command = ["test", "-f", targetPath]
_thumbnailCheckProc.running = true
```

The component is used by Quick Wallpaper, wallpaper selector directory/grid,
Coverflow, Skew, Waffle quick/background and related wallpaper surfaces.
Generation itself has already been centralized to avoid one
ImageMagick/ffmpeg process per delegate, but existence verification remains
per instantiated `ThumbnailImage`.

The batch generator already reports progress through stdout. However the
current machine protocol is **not a success protocol**:

```python
for result in p.imap(make_thumbnail, all_files):
    completed += 1
    print(f"PROGRESS {completed}/{total} FILE {all_files[completed - 1]}")
```

`make_thumbnail()` returns `False` both for an already-fresh cache entry and
for generation failure, and the parent currently ignores `result`.
Therefore QML must **not** treat the current `FILE` token as proof that the
thumbnail exists.

Strict-lossless direction:

1. extend the machine-progress protocol so the Python parent reports whether
   the expected thumbnail path exists after each worker result, e.g.
   `READY <source>` vs `FAILED <source>`;
2. compute that readiness in Python with in-process filesystem metadata, not a
   subprocess;
3. on READY, QML calls `rememberThumbnail(getExpectedThumbnailPath(...))`
   before emitting the existing source-file notification;
4. affected delegates then hit the shared known set and avoid their immediate
   `test -f` process;
5. FAILED retains the current fallback/generation behavior and must not be
   marked known.

The shell fallback generator
`generate-thumbnails-magick.sh` does not expose per-file machine progress, so
its rare fallback path can retain the existing end-of-directory reload/check
behavior unless separately measured.

Required evidence before promotion beyond HIGH CONFIDENCE:

- a fixture with fresh, newly generated and intentionally failed inputs proving
  READY/FAILED classification;
- identical delegate visible state and generation retry behavior;
- process-count comparison for a representative gallery open.

### Candidate C — CONFIRMED lifecycle asymmetry, but do not call the failure fix strict-lossless

The video first-frame dedup map currently does:

```qml
if (root._ffPending[videoPath]) return
root._ffPending[videoPath] = true
```

and no current source path deletes that key.

On success, `videoFirstFrames[videoPath]` is populated, so the stale pending
entry no longer changes subsequent answers because the success cache is checked
first. Removing the pending key inside `_cacheFirstFrame()` is therefore a
strict-lossless memory cleanup for successful paths.

On generation/check failure, however, the pending key remains true for the rest
of the shell session. That suppresses all retry attempts for that video. Simply
deleting the key on failure would change current behavior and could also create
a repeated ffmpeg retry loop when a reactive surface keeps asking for a bad
video.

Treat the failure side as a separate correctness/lifecycle decision, not as an
optimization. If product repair is authorized later, use an explicit failed
state with bounded retry/backoff rather than conflating “in flight” and “never
retry this session”.

### Non-candidates checked in this pass

- `KeyboardIndicators` lock-state maps are rebuilt from the current discovered
  LED path set by `_setLockPaths()`; stale device paths are pruned there, so
  the per-path copy-on-write code is not an unbounded session leak and the maps
  are normally tiny.
- `WindowPreviewService` explicitly prunes previews against the authoritative
  compositor window list and bounds decoded overview warm images to 12. Do not
  reopen it as a generic cache-growth candidate without new runtime evidence.
- `videoFirstFrames` itself must remain copy-on-write in the current design
  because multiple QML consumers deliberately depend on that property changing
  to refresh Image/ColorQuantizer bindings.

### Next measurement/research order

1. build a source-level oracle for Candidate A's private-map mutation parity;
2. inspect/fixture the thumbnail machine-progress protocol for Candidate B;
3. measure gallery process count before considering implementation;
4. then leave wallpaper thumbnails and diversify into another high-value hot
   path rather than accumulating micro-candidates in the same subsystem.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed from static analysis.

## 2026-10-07 — App identity-rule lookup hot-path research

Research-only continuation on `dev`
`5b1a7d44d7b66a84318f19c998ea32fe47ebd9b8`. No runtime/product source was
changed in this round.

Current source identities:

- `services/AppSearch.qml`:
  `74ea3c9e92860af62f10850c89118d79b7837543`;
- `services/TaskbarApps.qml`:
  `b05b0b39988a40faf7fa3cb84e6b0c747cf4a3ee`.

Repository/history search found no earlier optimization note for
`_parseIdentityRules()`, `_identityRulesKey` or the per-window
`JSON.stringify(appIdentityRules)` path.

### Candidate A — HIGH CONFIDENCE: move identity-rule cache validation out of every window lookup

`AppSearch` correctly caches the compiled regular expressions, but validates
that cache by serializing the entire configured rule list every time
`resolveWindowIdentity()` is called:

```qml
function _parseIdentityRules(): var {
    const rules = Config.options?.windows?.appIdentityRules ?? []
    const key = JSON.stringify(rules)
    if (root._identityRulesKey === key)
        return root._identityRules
    ...
}

function resolveWindowIdentity(toplevel): string {
    ...
    const rules = root._parseIdentityRules()
    ...
}
```

This means a cache hit still performs a complete `JSON.stringify(rules)`.

That lookup is used inside collection passes by:

- `TaskbarApps.qml`;
- `DockApps.qml`;
- `BarTaskbarPreview.qml`;
- `BarTaskbar.qml`;
- `AltSwitcherNoVisual.qml`;
- `AltSwitcher.qml`;
- `WaffleTaskViewContent.qml`.

For a pass over N windows, one unchanged identity-rule list can therefore be
serialized N times before the already-cached RegExp list is reused. Several
surfaces perform their own N-window passes, so this work can repeat again for
the same compositor snapshot.

The config schema already exposes:

```qml
property JsonObject windows: JsonObject {
    ...
    property list<var> appIdentityRules: []
}
```

and current `TaskbarApps` already relies on
`Config.options.windows.onAppIdentityRulesChanged`. The narrower invalidation
signal therefore exists today; no new Config API is required.

Strict-lossless direction:

1. keep the parsed rule array resident in `AppSearch`;
2. parse/rebuild it on initial use/Config-ready and on
   `appIdentityRulesChanged`, rather than fingerprinting it for every window;
3. let `resolveWindowIdentity()` read the current parsed array directly;
4. if `Config.options.windows` can be replaced during file reload, keep the
   `Connections.target` bound to the current object so the handler follows
   replacement;
5. preserve lazy desktop-entry resolution exactly as today: `desktopId` stays
   a string in the parsed rule and is not resolved during parsing.

Behavior that must remain byte-for-byte/logically equivalent:

- first matching rule wins;
- app-id regex and title regex are independently optional;
- at least one regex must be present;
- malformed regex rules are ignored;
- matching stays case-insensitive;
- empty app IDs return immediately;
- rules with missing/empty `desktopId` are ignored;
- rule ordering and configured object read order remain stable.

Required oracle before implementation:

- empty list;
- app-id-only/title-only/both-regex rules;
- malformed regex mixed with valid rules;
- multiple matching rules proving first-match ownership;
- repeated lookup of the same and different windows;
- rule-list replacement between lookups;
- Config object reload/replacement if the runtime can recreate the nested
  JsonObject;
- compare both result strings and malformed-rule behavior against current
  source.

Structural saving only: unchanged-rule cache validation becomes O(1) per window
lookup instead of serializing the rule list per lookup. No whole-shell CPU
percentage is claimed without runtime measurement.

### Candidate B — HIGH CONFIDENCE companion cleanup: Taskbar's identity revision is currently redundant

`TaskbarApps` owns:

```qml
property int _identityRulesRevision: 0
...
function onAppIdentityRulesChanged() {
    root._identityRulesRevision++
    refreshApps.restart()
}
...
function computeApps(): var {
    const identityRulesRevision = root._identityRulesRevision
    ...
}
```

Full-file occurrence inspection finds only those three references. The local
`identityRulesRevision` value is never consumed after assignment.

Because `computeApps()` is called imperatively by the 16 ms
`refreshApps` timer, the property read does not establish a live property
binding for `root.apps`. The same change handler already directly restarts
`refreshApps`, which is the actual invalidation mechanism.

After Candidate A establishes AppSearch's own rule invalidation, this revision
counter/read can be removed as a strict-lossless cleanup. Its standalone
resource value is negligible; keep it grouped with the identity-rule work
rather than advertising it as an independent optimization.

### Candidate C — LOWER PRIORITY: cache Taskbar ignored-app RegExp compilation only with log parity

Every `TaskbarApps.computeApps()` also rebuilds RegExp objects for configured
`dock.ignoredAppRegexes` plus the fixed system ignore patterns. Window list
changes can therefore recompile an unchanged pattern set.

The RegExp flags are only `i`, so successful regex instances have no
`lastIndex` state and are safe to reuse for matching. However invalid patterns
currently emit a warning each time `computeApps()` recompiles them. Silently
caching parse failures would change diagnostic log frequency.

Do not promote this as a trivial cache unless the implementation preserves that
observable diagnostic contract, e.g. cache valid compiled expressions and the
ordered invalid-pattern list while re-emitting the same warnings when the
current compute path would have done so. Given normal ignored-pattern counts,
this ranks below Candidate A.

### Non-candidates / corrections in this pass

- Do not claim `TaskbarApps.Config.onOptionsChanged` is equivalent to the
  explicit `Config.configChanged` signal. `Config.options` is an alias to a
  JsonAdapter object, and static source alone does not prove that its top-level
  `optionsChanged` fires for every nested mutation.
- Notification group reconstruction remains a real multi-pass candidate, but it
  was already recorded elsewhere in the optimization research as a
  notification derived-state single-pass direction. It is not counted again as
  a new finding here.
- Waffle Task View's wallpaper blur tree is instantiated only while Task View is
  open and captures a horizontal strip rather than the entire output. Static
  source alone does not justify a new residency/blur optimization claim.
- Current ScreenTime on Niri is already focus-event-driven with a coarse
  30-second heartbeat; no new high-confidence source-only polling reduction was
  established in this pass.

### Next research order

1. build a behavioral/read-order oracle for Candidate A;
2. benchmark rule-list sizes and window counts only if implementation is later
   authorized;
3. inspect another distinct collection hot path rather than expanding this into
   speculative AppSearch micro-caches.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed from static analysis.

## 2026-10-07 — Bar Taskbar pinned-order research

Research-only continuation on `dev`
`050a8b19059a150bacb9f97759592dab06ee0394`. No runtime/product source was
changed in this round.

Current source identities:

- `modules/bar/BarTaskbar.qml`:
  `3aca1b63e2633584c86f75c6a2e5eb2ebaebfdb3`;
- sibling reference `modules/dock/DockApps.qml`:
  `11b3ea8cc17c91a1cf3b6a1f41f64f392d4dfcc9`.

Repository/history search found no prior optimization note for
`BarTaskbar`'s `pinnedApps.findIndex()` comparator path.

### Candidate — HIGH CONFIDENCE: precompute pinned rank once per Bar Taskbar rebuild

When `dock.separatePinnedFromRunning` is enabled, `BarTaskbar` constructs
`sortedRunningApps` and sorts it with:

```qml
const aIndex = pinnedApps.findIndex(p => p.toLowerCase() === a.lowerAppId)
const bIndex = pinnedApps.findIndex(p => p.toLowerCase() === b.lowerAppId)
...
```

After the sort it again computes:

```qml
pinned: pinnedApps.some(p => p.toLowerCase() === lowerAppId)
```

The comparator can run O(R log R) times for R running app groups, and every
comparison linearly scans P pinned entries while lowercasing them. The final
publication then performs another O(R * P) membership scan.

The sibling Dock implementation has already eliminated this shape. It builds
one lowercase `pinnedOrder` Map before sorting and uses Map membership/rank
inside its comparator.

Strict-lossless Bar direction:

1. build one lowercase pinned-rank Map at the beginning of the separate-mode
   branch;
2. use Map membership/rank inside the existing comparator;
3. keep the Bar's current unpinned fallback ordering
   `lowerAppId.localeCompare()` — do **not** copy Dock's running-order fallback;
4. publish `pinned` from Map membership instead of rescanning
   `pinnedApps.some(...)`.

Important duplicate/case oracle:

Current `findIndex` returns the **first** case-insensitive occurrence. A naive
Map built with unconditional `set()` would instead retain the last duplicate
rank. Therefore the strict-lossless map must only set a lowercase key when it
is not already present.

Required behavioral oracle:

- empty pinned list;
- all-running unpinned apps;
- mixed pinned/running apps;
- duplicate exact pins;
- case-variant duplicate pins;
- pinned app missing a desktop entry;
- alphabetical order among unpinned running apps;
- separator placement and focused/running flags unchanged.

This removes repeated pinned-list scanning from each sort comparison and from
final membership publication. No whole-shell CPU percentage is claimed without
runtime measurement.

### Adjacent paths checked

- `DockApps.qml` already uses a precomputed pinned-order Map in the equivalent
  separate-mode sort; do not rewrite it.
- Both Dock and Bar already cache ignored-app RegExp objects. Their cache-hit
  check still serializes the small configured pattern list, but this ranks below
  the AppSearch identity-rule serialization finding because it happens once per
  model rebuild, not once per window.
- Compositor sorting is already demand-leased and debounce-limited; no new
  source-only lifecycle reduction was established in this pass.

### Next research order

Continue with another distinct high-value collection/process/render path rather
than multiplying taskbar micro-caches. Prefer a path where the same expensive
data transformation is demonstrably repeated within one event or visible frame.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed from static analysis.

## 2026-10-07 — Niri toplevel matching research

Research-only continuation on current `dev`
`580792f3785031cd79746b0305728503233d3652`. No runtime/product source was
changed in this round.

Current `services/NiriService.qml`:
`4c8194493fd380bf0ad8c51bc62990ad0c232738`.

Repository/history search found no prior optimization note for
`sortToplevels()`, `filterCurrentWorkspace()` or
`matchToplevelToWindow()`.

### Candidate — HIGH CONFIDENCE: bucket foreign toplevels by appId before Niri greedy matching

Both `sortToplevels()` and `filterCurrentWorkspace()` currently use the
same greedy nested match:

```qml
for (const niriWindow of ...) {
    let bestMatch = null
    let bestScore = -1

    for (const toplevel of toplevels) {
        if (usedToplevels.has(toplevel))
            continue

        const score = matchToplevelToWindow(toplevel, niriWindow)
        ...
    }
    ...
}
```

The matcher begins with:

```qml
if (toplevel.appId !== niriWindow.app_id)
    return 0
```

Therefore every comparison against a toplevel from a different app is
provably incapable of winning. On a desktop with W Niri windows and T foreign
toplevel handles, the current path can execute W*T matcher calls even when
nearly every window belongs to a different application.

Strict-lossless direction:

1. make one pass over the input `toplevels` and build
   `Map<appId, toplevel[]>`, preserving original toplevel order inside every
   bucket;
2. for each Niri window, scan only the bucket matching
   `niriWindow.app_id`;
3. preserve the existing `usedToplevels` rule inside each bucket;
4. keep `matchToplevelToWindow()` unchanged for title scoring;
5. preserve `sortWindowsByLayout(windows)` ordering in `sortToplevels()`;
6. preserve current workspace-window order in `filterCurrentWorkspace()`;
7. continue dropping all unmatched foreign handles so stale/ghost Wayland
   handles cannot reappear in Dock/Taskbar.

Why this is semantically safe:

- different-app candidates always score 0 today;
- a successful match always has score > 0;
- within one app bucket, retaining original toplevel order preserves tie
  behavior because the current algorithm updates only when
  `score > bestScore`, not on equality;
- an exact-title score 3 still stops scanning immediately;
- score-2 substring and score-1 same-app fallbacks retain the same candidate
  order and used-object exclusion.

The optimization changes only which candidates are known in advance to be
incapable of matching.

Expected complexity:

- bucket construction: O(T);
- matching: sum of same-app candidate scans rather than W*T global scans;
- worst case remains quadratic when every window belongs to the same app,
  which is necessary unless the title-scoring/greedy contract is redesigned;
- mixed-app desktops approach a much smaller comparison count.

This has broader leverage than a consumer-local taskbar cache because
`CompositorService.sortedToplevels` feeds Dock/Taskbar and other surfaces,
and `filterCurrentWorkspace()` contains the same matching debt separately.

### Required oracle before implementation

Use a pure helper/oracle with stable object identities and compare complete
matched source identity/order for:

- zero windows / zero toplevels;
- all unique app IDs;
- multiple windows of the same app;
- duplicate same-app/same-title handles;
- exact-title score 3;
- asymmetric substring score 2;
- same-app title mismatch score 1;
- mixed stale foreign handles absent from Niri;
- Niri window without a foreign handle;
- one foreign handle that could match multiple same-app Niri windows, proving
  used-handle exclusion and greedy order;
- reordered input toplevels to prove tie behavior follows current input order;
- workspace-filtered subset parity.

Ghost-window correctness is a hard boundary: unmatched foreign handles must
remain dropped exactly as current source specifies.

### Adjacent source notes

- `findNiriWindow()` also linearly scans `windows`, but its call frequency
  was not established as a hot path in this pass; do not merge it into this
  candidate without evidence.
- Do not replace greedy title scoring with a direct title Map. Duplicate titles,
  substring matches and one-handle-per-window ownership make that a behavioral
  redesign, not the strict-lossless bucket optimization above.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without runtime
measurement.

## 2026-10-07 — Niri layout-sort cache research

Research-only continuation on current `dev`
`3d607b1b01f9ec937122fdaf48bcfa938cafcfed`. No runtime/product source was
changed in this round.

Current `services/NiriService.qml`:
`4c8194493fd380bf0ad8c51bc62990ad0c232738`.

### Candidate — HIGH CONFIDENCE: cache the Niri layout-sorted window view instead of sorting it again on every toplevel match pass

`NiriService.windows` is already layout-sorted at the normal publication
boundary:

```qml
const nextWindows = sortWindowsByLayout(_pendingWindows)
windows = nextWindows
```

and it is explicitly re-sorted when output geometry changes. However
`sortToplevels()` still starts from:

```qml
for (const niriWindow of sortWindowsByLayout(windows)) {
    ...
}
```

so every compositor sort pass allocates another enriched array, sorts it and
maps it back before the actual Niri↔foreign-toplevel matching begins.

A direct replacement with `for (const niriWindow of windows)` is **not**
strict-lossless today. `handleWorkspacesChanged()` replaces the workspace map
and may change `ws.idx` or `ws.output`, both of which are sort keys, but it
does not reassign public `windows`; it only emits `windowOrderChanged()`.
The extra sort inside `sortToplevels()` currently repairs that derived order
before consumers observe it.

Strict-lossless direction:

1. maintain a private layout-sorted window view for matching;
2. refresh that view whenever any sort-key source changes:
   - normal batched window publication;
   - `WorkspacesChanged` (workspace index/output topology);
   - output geometry changes;
   - initial output fetch completion;
3. keep public `windows` assignments and `windowsChanged` signal count exactly
   as today;
4. let `sortToplevels()` iterate the private sorted view directly;
5. keep `windowOrderChanged()` emissions unchanged so current compositor
   scheduling remains intact.

The private-view requirement matters. Reassigning public `windows` from
`handleWorkspacesChanged()` merely to refresh order would introduce an extra
`windowsChanged` notification and could wake unrelated consumers; that is not
strict-lossless.

Expected structural saving:

- one `map -> sort -> map` pipeline is removed from each
  `sortToplevels()` call;
- sorting instead happens only when the authoritative inputs that determine
  layout order change;
- the benefit composes with the separate appId-bucket matching candidate:
  cached order removes redundant O(W log W) preparation, while bucketing removes
  impossible cross-app match comparisons.

Required oracle before implementation:

- window open/close/change publication;
- focus-only changes where layout order must not change;
- `WindowLayoutsChanged`;
- `WorkspacesChanged` changing workspace idx;
- workspace moved between outputs;
- `OutputsChanged` changing logical x/y;
- initial output fetch arriving after windows;
- zero-window transitions;
- verify public `windowsChanged`, `windowOrderChanged`,
  `activeWindowChanged` counts/order remain identical to the current source;
- compare complete `sortToplevels()` output identity/order before and after.

### Adjacent finding deliberately not promoted

`filterCurrentWorkspace()` currently filters from public `windows` and does
not call `sortWindowsByLayout()`. That means its order semantics differ from
`sortToplevels()` after a workspace-topology-only change until another public
window sort occurs. This is potentially a correctness consistency question, not
an optimization. Do not silently switch it to the new private view under a
strict-lossless patch without first establishing the intended consumer order.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without runtime
measurement.

## 2026-10-07 — Desktop-entry lookup memo research

Research-only continuation on current `dev`
`3153562a6dabe3d630360a3786a1e93461300547`. No runtime/product source was
changed in this round.

Current `services/AppSearch.qml`:
`74ea3c9e92860af62f10850c89118d79b7837543`.

Repository/history search found no prior optimization note for memoizing
`lookupDesktopEntry()` results.

### Candidate — HIGH CONFIDENCE: memoize exact desktop-entry lookup results per DesktopEntries epoch

`AppSearch.lookupDesktopEntry(appId)` already has good internal reverse maps,
but every call still restarts the whole lookup chain:

1. `DesktopEntries.heuristicLookup(appId)`;
2. direct lowercase/kebab map probes;
3. scoped/reverse-domain normalization candidates;
4. suffix stripping;
5. last-resort token-overlap scans across
   `_desktopIdStemMap` and `_startupClassMap`.

Many shell surfaces ask for the same application identity repeatedly across
model rebuilds and delegate bindings. Current callers include:

- `TaskbarApps.qml`;
- `DockApps.qml`;
- `BarTaskbar.qml`;
- Dock/Bar/Waffle task buttons;
- AltSwitcher;
- MPRIS hint resolution;
- ScreenTime history repair;
- Dock Settings;
- desktop-item validation/opening;
- icon-theme fallback paths.

A per-exact-input memo therefore avoids both repeated successful resolution and
repeated expensive misses.

Strict-lossless direction:

1. cache `appId -> DesktopEntry|null` after the current lookup chain finishes;
2. key by the exact incoming appId string rather than only lowercasing the key,
   so any behavior specific to `DesktopEntries.heuristicLookup()` input casing
   remains untouched;
3. distinguish an explicit cached miss from “not in memo”;
4. clear/invalidate the memo **immediately** in
   `DesktopEntries.applications.onValuesChanged`;
5. retain the existing 500 ms debounce for rebuilding the reverse maps;
6. keep the exact lookup precedence and token-score algorithm unchanged.

The immediate invalidation is required. Current source can observe a newly
installed/removed desktop entry through `DesktopEntries.heuristicLookup()`
before the debounced `_rebuildCache()` has rebuilt the local maps. If the memo
were invalidated only when `_cacheRevision` advances, a previously cached hit
or miss could remain stale for that debounce window.

This candidate can be implemented with a private JS Map or equivalent private
object; no QML binding or public change notification needs to depend on memo
mutation.

### Required oracle before implementation

Compare current and memoized lookup result identity for:

- exact desktop id/stem;
- StartupWMClass;
- executable basename;
- whitespace/kebab normalization;
- scoped IDs such as `@scope/app-desktop`;
- reverse-domain ids;
- suffix stripping;
- token-overlap fallback;
- no match;
- case variants;
- repeated hit and repeated miss;
- DesktopEntries add/remove/change between repeated lookups, including a change
  observed before the 500 ms reverse-map rebuild;
- malformed/unexpected but currently tolerated string inputs.

Cache invalidation must preserve the same first lookup result immediately after
a DesktopEntries change.

### Expected saving

Repeated lookup of an unchanged app identity becomes O(1) Map access rather
than re-running heuristic/normalization/token-overlap work. The structural gain
is largest for misses and unusual Electron/AppImage ids that fall through to
token scoring.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without runtime
measurement.

## 2026-10-07 — Clipboard/Booru image process research

Research-only continuation on current `dev`
`31665dcccb696c66741ca80d3d78a05f3159fd6d`. No runtime/product source was
changed in this round.

Current source identities:

- `modules/common/widgets/CliphistImage.qml`:
  `d210fa7c52aba17fddec09909cc464fe034ffa03`;
- `modules/sidebarLeft/anime/BooruImage.qml`:
  `69e9db92e3a900c0295f6eee309e900f30a503b6`;
- `modules/common/Directories.qml`:
  `0fb9ae0b8ce77bb5b280c3aef16c9b3d22d73f27`.

### Candidate A — HIGH CONFIDENCE: shared in-flight/success cache for Cliphist image decode

`CliphistImage` is correctly lazy: it only starts decoding once the delegate is
visible. It also publishes through a per-process temporary file and atomic
rename. However each visible `CliphistImage` still owns its own Bash process:

```qml
if [ -s '${imageDecodeFilePath}' ]; then
    exit 0
fi
_tmp='${imageDecodeFilePath}'.$$
if ${Cliphist.decodeCommand(root.entry)} > "$_tmp" && [ -s "$_tmp" ]; then
    /usr/bin/mv -f "$_tmp" '${imageDecodeFilePath}'
...
```

The source itself notes that multiple clipboard surfaces can render the same
entry concurrently. Current call sites include Overview search, ii Clipboard and
Waffle Clipboard.

Consequences today for the same clipboard entry:

- every visible instance forks its own Bash;
- a cache hit still forks Bash just to test `-s`;
- simultaneous misses can decode the same cliphist entry more than once;
- atomic rename prevents partial-file corruption but does not deduplicate the
  decode work.

Strict-lossless direction:

1. move per-entry decode ownership into the shared Cliphist/service layer or a
   dedicated shared resolver;
2. preserve demand gating: no decode until at least one visible image requests
   it;
3. maintain `entryNumber -> decodedPath` for **successful** decodes only;
4. maintain one in-flight request per entry number;
5. let all requesting delegates subscribe to the same completion;
6. on failure, clear in-flight state and do **not** cache failure, so a later
   delegate/open can retry just as current independent instances can;
7. preserve the current temporary-file + atomic-rename publication;
8. keep Directories' session cleanup boundary unchanged.

This removes duplicate decode processes without changing success/failure file
semantics or making failure sticky.

Required oracle:

- one visible instance, cold decode success;
- two/three simultaneous surfaces requesting the same entry;
- different entries requested concurrently;
- successful cache reuse after the first decode;
- decode failure followed by a later retry;
- delegate destroyed while decode is in flight;
- source file already present before the first request;
- malformed/zero entry number behavior matching current source;
- exact published path and visibility behavior unchanged.

Measure child-process count and cliphist decode invocation count before/after;
do not claim CPU/RSS percentages from source alone.

### Candidate B — P2 / INVESTIGATE: Booru manual-preview process burst

For providers listed by `BooruResponse` as manual-download providers
(`danbooru`, `waifu.im`, `t.alcy.cc`), each `BooruImage` delegate starts:

```qml
/usr/bin/bash -c "mkdir -p ... && [ -f path ] || curl ... -o path"
```

on component completion.

Unlike Favicon, this is not a persistent cross-session cache-hit problem:
`Directories.qml` deliberately removes and recreates `booruPreviews` on
shell startup. Unique images therefore legitimately need one network fetch in
the session. The remaining debt is burst/concurrency overhead:

- one Bash wrapper per manual-preview delegate;
- potentially many simultaneous curl processes as a result grid instantiates;
- repeated delegates for the same image in one session can still race/check
  independently.

Do not promote a serial queue blindly: changing download concurrency can change
visible image arrival order/timing. Measure representative result counts first.
A safer first optimization may be shared in-flight dedup plus direct curl
ownership after one directory-readiness gate, while retaining current
parallelism for distinct URLs.

### Separate correctness issue — Booru preview cache identity

`BooruImage.fileName` is derived from the remote file URL basename, while all
providers share `Directories.booruPreviews`. Therefore unrelated provider URLs
with the same basename can map to the same local preview path. Current
`[ -f path ]` logic can then reuse the wrong image.

This is a cache-identity correctness issue, not a strict-lossless optimization.
A future repair should key by normalized full source URL/provider+id or a hash
and define how legacy basename-only files are ignored/migrated. Do not fold that
behavioral change into a process-only optimization patch.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without runtime
measurement.

## 2026-10-07 — Media artwork resolver process research

Research-only continuation on current `dev`
`d52ea737adb5cd1d52926e15ec164beaa719a723`. No runtime/product source was
changed in this round.

Current source identities:

- `modules/common/widgets/MediaArtworkResolver.qml`:
  `801d6422216b4b5f8e1ed31111b27010b963006e`;
- canonical active-player singleton `modules/common/widgets/MediaArtwork.qml`:
  `22cde9d2038d0ebf4c226773cdb9ca9a8cc6721f`.

Repository/history search found no prior optimization note for shared in-flight
ownership inside `MediaArtworkResolver`.

### Candidate — HIGH CONFIDENCE structural duplicate: share exact-key artwork file work while keeping per-instance display state

`MediaArtworkResolver` intentionally gives each owner independent presentation
state: current display source, stale-art retention, generation counters, retry
timers and local-file reload handling. That independence must remain.

The expensive file/backend work is not independent, however. Every resolver
instance owns its own:

- `artExistsChecker` process;
- remote `artworkDownloader`;
- base64 writer;
- local-file MIME checker/cacher;
- stable-file readiness checker.

The remote/data/local cache destination is derived from the resolver's exact
metadata identity: normalized source URL + title + artist + album. Multiple
resolver instances with the same identity therefore target the same cache file,
yet can independently probe or produce it.

This can happen for active-player surfaces because Hadalis has both the
canonical `MediaArtwork` singleton and additional resolver instances in
`PlayerControl`, `PlayerBase`, `CavaTheme`, Bar media and YtMusic-specific
surfaces. Other owners legitimately resolve non-active players, so replacing
all of them with the active-player singleton would be incorrect.

Strict-lossless direction:

1. keep each resolver's presentation/generation state local;
2. centralize only backend work keyed by the exact output/cache identity
   (`artFilePath` or an equivalent exact metadata key + operation kind);
3. allow one producer/check pipeline at a time for a given exact key;
4. fan successful completion/path readiness back to all current waiters;
5. keep distinct metadata keys independent even when they share the same URL;
6. never use URL-only dedup because title/artist/album are intentionally part of
   cache identity;
7. preserve atomic temp-file publication and MIME validation;
8. do not make failures sticky.

The last point is important: current remote resolver instances each have their
own retry counter/timing. A shared backend must not silently convert several
independent retry opportunities into a permanent failed cache entry. The safest
design is success/in-flight sharing only, with failed in-flight state removed
and retry scheduling still owned by the requesting resolver(s), or another
oracle-proven policy that reproduces current visible recovery.

### Why not simply route everything through `MediaArtwork`

That would change behavior:

- `MediaControls` can render several players, not only the active player;
- LocalMusic can use a playback adapter;
- YtMusic-specific surfaces have dedicated metadata rules;
- some resolver metadata keys differ in album handling;
- each surface currently preserves its own previous artwork while the next
  source resolves.

Backend dedup is therefore the narrow optimization boundary.

### Required oracle before implementation

Exercise exact result/path and transition parity for:

- two simultaneous resolvers with identical remote metadata;
- identical URL but different title/artist/album;
- active-player singleton + `PlayerControl` / `PlayerBase` overlap;
- different players resolving concurrently;
- warm cache hit;
- cold remote download;
- HTTP failure followed by retries and later recovery;
- resolver destroyed while shared work is in flight;
- local file that appears late;
- local file replaced or deleted during readiness checks;
- Plasma/browser temporary art copied before the source disappears;
- base64 data URI success/failure;
- rapid track A -> B -> A generation changes;
- each resolver retaining its own stale display until its requested replacement
  is ready.

Measure process count (`test`, Bash, curl, file/stat helpers) for one active
track displayed on several surfaces before claiming a runtime saving.

### Adjacent non-candidate

Do not memoize a successful file path forever without filesystem invalidation.
Current resolvers re-check existence and can recover if a cache file is deleted
or replaced externally. A process-free session-known-success set would change
that recovery contract unless coupled to authoritative file lifetime/version
evidence.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without runtime
measurement.

## 2026-10-07 — Settings World Clock process research

Research-only continuation on current `dev`
`da0d94faa2b8376e1cd6f026f8474c9fd4982596`. No runtime/product source was
changed in this round.

Current source identities:

- `modules/settings/InterfaceConfig.qml`:
  `6f9e2c644aafebc0b3b54ba34df14c272bbbe52d`;
- sibling `modules/sidebarLeft/widgets/WorldClockWidget.qml`:
  `5f9272b1aeedc3fa91b76e3a13de150bb6e61829`;
- shared desktop `services/WorldClock.qml`:
  `1260b2d2ed85cf70339c2c8f366c296655dc3c9a`.

Repository/history search found no prior optimization note for the Settings
`liveTimeProc` child-process fan-out.

### Candidate — HIGH CONFIDENCE for supported timezone inputs: collapse Settings preview from 1+N processes to one Bash process

The World Clock settings preview refreshes every 20 seconds while the Widgets
section is active. It currently builds shell source like:

```qml
for (let i = 0; i < tzs.length; i++)
    script += `printf ... "$(TZ='timezone' date '+format|%:z')"\n`
liveTimeProc.command = ["/usr/bin/bash", "-c", script]
```

For N configured timezones, each refresh starts one Bash plus N external
`date` children.

Two existing sibling implementations already prove Hadalis does not need those
children:

- `services/WorldClock.qml`;
- `modules/sidebarLeft/widgets/WorldClockWidget.qml`.

Both pass timezone names as argv and use Bash's builtin
`printf '%(...)T' ... -1`, so one Bash process formats all requested zones.

Strict-lossless direction for the Settings preview:

1. keep the existing 20-second cadence and visibility gate unchanged;
2. keep one `liveTimeProc`;
3. pass each configured timezone as an argv entry;
4. use the already-proven sibling `TZ="$tz" printf '%(...)T' ... -1` loop;
5. preserve the exact output protocol currently consumed by `SplitParser`:
   `timezone|time|offset`;
6. preserve the configured 12/24-hour format choice;
7. do not merge Settings state with the desktop/background World Clock service,
   because the two features use different config namespaces.

Structural saving per refresh:

- current: 1 Bash + N `date` children;
- candidate: 1 Bash;
- child-process reduction: N external processes per refresh while this settings
  section is visible.

No cadence reduction is claimed here. Changing 20 seconds to one minute would
alter refresh timing and is a separate product/performance decision.

### Input-contract caveat

Current Settings code interpolates timezone strings into shell source inside
single quotes. The sibling argv implementations avoid that interpolation. For
valid IANA timezone names the behavior is directly equivalent.

Malformed strings containing shell-significant characters currently have
shell-parsing side effects rather than a well-defined timezone contract. Moving
them to argv is safer, but strict-lossless classification for malformed input
requires an oracle/decision rather than pretending those shell side effects are
a supported behavior.

Required oracle:

- empty timezone list;
- 1 and several valid zones;
- 12-hour and 24-hour formatting;
- positive/negative UTC offsets;
- DST transition fixture if practical;
- invalid but non-shell-significant timezone;
- timezone string containing whitespace/quote/metacharacters, explicitly
  deciding whether safe argv handling supersedes historical shell parsing;
- repeated refresh while a prior process is still running, if that condition is
  reachable in the current Settings process wrapper.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without runtime
measurement.

## 2026-10-07 — Shared MPRIS position ticker research

Research-only continuation on current `dev`
`70174b2cee2acd94f997ce993f55689acfc938e4`. No runtime/product source was
changed in this round.

Repository-wide source search finds ten `positionChanged()` occurrences in
the media path. Nine are producer-style refresh sites/timers; LyricsService is
a listener.

Current independent refresh owners include:

- horizontal Bar media;
- vertical Bar media;
- BarMediaPlayerItem;
- PlayerControl;
- PlayerBase;
- left-sidebar MediaPlayerWidget;
- Control Panel MediaSection;
- LockMediaWidget;
- Waffle Action Center MediaPaneContent;
- VolumeMixer music page.

Current cadences are not uniform:

- `PlayerBase`: 500 ms while its presentation explicitly requests updates;
- several rich surfaces: 1000 ms;
- Bar/VerticalBar/VolumeMixer: configurable resource interval, defaulting near
  3000 ms.

Every producer calls the same method on the same `MprisPlayer` object:

```qml
player.positionChanged()
```

That is a player-level signal refresh, not a private per-surface computation.
If multiple surfaces refer to the same player, the fastest timer already wakes
bindings attached to that player; slower owners can then add redundant signal
emissions/wakeups.

### Candidate — P1 / MEASURE THEN ADAPT: one demand-leased ticker per player identity

A shared ticker can potentially replace the independent periodic producers while
preserving each surface's demand boundary:

1. consumers acquire a lease for a specific player and requested interval;
2. one ticker per player runs at the minimum active requested interval;
3. releasing a consumer recomputes the required interval and stops the ticker
   when no consumer remains;
4. acquiring a consumer performs the current `triggeredOnStart` equivalent:
   request one immediate refresh even if another ticker is already running;
5. YtMusic/direct playback-adapter paths that do not rely on MPRIS position
   refresh remain outside this lease;
6. multi-player surfaces retain one logical ticker per player, not one global
   active-player ticker.

This direction has higher leverage than shaving individual timer intervals
because it attacks duplicated ownership, not merely cadence.

### Why this is not yet marked strict-lossless

The exact timing and count of `positionChanged()` emissions is observable to
bindings/listeners. Independent timers currently have separate phases. A shared
minimum-cadence ticker would change that signal schedule even when displayed
position values remain equivalent or fresher.

Before implementation, capture the current signal/callback sequence for:

- one Bar-only active player;
- PlayerControl only;
- PlayerBase/preset only;
- Bar + popup simultaneously;
- Bar + Sidebar/Control Panel;
- Dashboard + another active media surface;
- Lock transition;
- Waffle Action Center;
- two different MPRIS players in the multi-player surface;
- consumer open/close while playing;
- pause/resume;
- configured resource interval differing from 3000 ms.

Then define the parity contract around visible progress freshness rather than
assuming raw signal count is irrelevant.

### Important implementation boundary

Do not centralize this as a permanently running MPRIS poll. The current code is
already presentation/demand gated. Any shared owner must preserve that property
and balance all leases on destruction/visibility transitions.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without runtime
measurement.

## 2026-10-07 — Saved-theme catalog polling research

Research-only continuation on current `dev`
`10c4a09d0dc222a58cff316d1b6824b54611c286`. No runtime/product source was
changed in this round.

Current `modules/settings/ThemesConfig.qml`:
`fa617e33a5a4672e970a46ee19c2a3dae2c309be`.

Repository/history search found no prior optimization note for
`savedThemesProcess` / `refreshSavedThemes()`.

### Candidate A — HIGH CONFIDENCE: collapse per-poll theme catalog child fan-out

While the Custom Theme Editor is expanded, `ThemesConfig` refreshes the saved
theme catalog every 2000 ms.

The current scan starts one Bash and, for every saved JSON file, invokes:

- one external `basename`;
- one external `jq`.

For T saved themes, one unchanged poll therefore uses approximately
`1 + 2T` processes.

The same output can be produced without changing the polling cadence or model
semantics:

1. keep the current Bash owner and 2-second timer;
2. derive the basename with shell parameter expansion instead of an external
   `basename`;
3. invoke one `jq` over the complete ordered file argument list, deriving each
   record's name from `input_filename`;
4. preserve one compact JSON object per input file on stdout and the existing
   `SplitParser` consumption;
5. preserve glob/order semantics and invalid-file warning behavior through an
   oracle.

Structural process count per poll becomes roughly:

- current: `1 + 2T`;
- candidate: `1 Bash + 1 jq`, independent of T.

This is a narrow strict-lossless process optimization and does not require a
new service or watcher.

### Candidate B — P1 follow-up: replace fixed 2-second polling with filesystem-driven refresh only after overwrite semantics are proven

The repository already uses `FolderListModel` reactively for setup scripts and
other directory inventories. That makes event-driven saved-theme discovery a
natural follow-up.

However add/remove detection alone is not sufficient: an existing
`name.json` can be overwritten in place while keeping the same filename and
count. A watcher design must prove it catches content replacement, not merely
directory count changes.

A robust eventual design may combine:

- `FolderListModel` for add/remove/name/order changes;
- watched per-file content or another authoritative directory/content change
  signal for same-name overwrites;
- explicit refresh after Hadalis itself saves/deletes a theme.

Do not delete the polling timer merely because `FolderListModel.countChanged`
works for add/remove.

### Required oracle

For Candidate A:

- zero saved themes;
- one/many themes;
- filenames with spaces/dots;
- deterministic output order;
- invalid JSON mixed with valid JSON;
- one file removed during scan;
- one file replaced during scan;
- exact preset id/name/description/tags/colors parity;
- same warning/skip behavior for invalid entries.

For Candidate B later:

- external create/delete;
- external same-name overwrite;
- atomic rename replacement;
- Hadalis save/delete;
- editor closed/reopened;
- no refresh/process activity while the relevant settings surface is inactive.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without runtime
measurement.

## 2026-10-07 — Settings search registry hot-path research

Research-only continuation on current `dev`
`9b4ebaf9ad76f2b754ce612322533f40af669ad7`. No runtime/product source was
changed in this round.

Current `modules/common/widgets/SettingsSearchRegistry.qml`:
`836c9c061039bae7508aa6b44973722409ddf1dd`.

Repository/history search found no prior optimization note for
`SettingsSearchRegistry.buildResults()` field normalization or pre-top-50
highlight generation.

### Candidate A — HIGH CONFIDENCE: normalize immutable registry search fields once at registration

`registerOption(meta)` snapshots each live control's search metadata into an
entry:

- page index/name;
- section;
- label;
- description;
- provided + generated keywords.

There is no update-in-place API for these entry fields. Controls are
unregistered/re-registered when their searchable identity changes through
lifecycle recreation.

Despite that snapshot model, every `buildResults(query)` call currently
recreates the normalized search corpus for every active entry:

```qml
var label = (e.label || "").toLowerCase()
var desc = (e.description || "").toLowerCase()
var page = (e.pageName || "").toLowerCase()
var sect = (e.section || "").toLowerCase()
var kw = (e.keywords || []).join(" ").toLowerCase()
```

Settings search runs on text changes, so this repeats lowercase conversions and
keyword joining for the complete live-control registry on every keystroke.

Strict-lossless direction:

1. during `registerOption()`, keep the existing public/raw entry fields and
   additionally compute private normalized fields;
2. `buildResults()` reads those precomputed strings directly;
3. keep current auto-keyword generation, scoring weights, match order and
   page/tie ordering unchanged;
4. preserve entry removal/flush behavior exactly.

Because the current registry already snapshots those raw fields rather than
reactively rereading the control during search, caching their normalized forms
does not make metadata any staler than current behavior.

### Candidate B — HIGH CONFIDENCE: defer highlight markup until after score/sort/top-50 selection

Current `buildResults()` generates:

```qml
labelHighlighted: highlightTerms(e.label, matchedTerms)
descriptionHighlighted: highlightTerms(e.description, matchedTerms)
```

for every matched entry before sorting all matches and returning only:

```qml
out.slice(0, 50)
```

Highlight markup does not participate in scoring, applicability, ordering or
the top-50 cutoff.

Strict-lossless direction:

1. during the scoring pass, retain raw label/description plus
   `matchedTerms`;
2. perform the existing sort;
3. take the exact same first 50 entries;
4. only for those retained entries, call the existing `highlightTerms()` in
   the same term order and publish the same result fields.

This removes lowercase/substr/HTML-string work for matches that are guaranteed
to be discarded while preserving the complete visible result object for every
returned row.

### Required oracle before implementation

Compare complete result arrays/fields for:

- empty query;
- one and multiple terms;
- case variants;
- exact/prefix/mid-string matches;
- generated and caller-provided keywords;
- duplicate keyword terms;
- page/section/description-only matches;
- score ties and page-index tie ordering;
- more than 50 matching entries;
- overlapping highlight terms and term-order-sensitive markup;
- removed controls before the coalesced registry flush;
- unregister/re-register and page/control destruction/recreation;
- translated labels/descriptions as they exist at registration time.

The oracle should compare IDs, order, scores, matchedTerms, raw text and final
highlight markup, not merely result count.

### Adjacent non-candidates

- Do not add a keystroke debounce as part of this strict-lossless work. That
  changes when results become observable.
- Do not merge standalone Settings, SettingsOverlay, SettingsFocus and Waffle
  search orchestration merely because they call the same registry. Their
  applicability/easy-mode/navigation contracts differ, and static source does
  not prove those routes execute concurrently for one user query.
- Static `SettingsPageRegistry.searchIndex()` normalization can be examined
  separately, but it should not be conflated with the live-control registry
  candidate above.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without runtime
measurement.

## 2026-10-07 — Niri focus-only enrichment research

Research-only continuation on current `dev`
`0f2a13ad0723c3d94052dd8532c7dabd648239cc`. No runtime/product source was
changed in this round.

Current source identities:

- `services/CompositorService.qml`:
  `017c1405d39a2a2f954bb8d90d350ca4d4356f1d`;
- `services/NiriService.qml` remains
  `4c8194493fd380bf0ad8c51bc62990ad0c232738`.

### Candidate — MEASURE / PROVE FIRST: focus-only enriched-toplevel refresh

Current Niri compositor wiring schedules the same full sort/match path for both:

```qml
onWindowOrderChanged() { root.scheduleSort() }
onActiveWindowChanged() { root.scheduleSort() }
```

and the sort timer calls:

```qml
sortedToplevels = computeSortedToplevels()
```

which on Niri invokes `NiriService.sortToplevels()`.

A pure focus change does not change:

- Niri window membership;
- app id;
- title;
- workspace id;
- spatial/layout order;
- foreign toplevel membership.

It only changes which enriched item reports `activated: true`.

Static source therefore suggests a cheaper focus-only path could rebuild the
published enriched array from the already matched items by
`niriWindowId`, preserving order and all other fields, instead of rerunning
Niri↔foreign matching.

However this is **not promoted to HIGH CONFIDENCE** yet.

Quickshell's `ToplevelManager.toplevels.valuesChanged` is also a sort trigger.
Static source does not prove whether Wayland activation changes emit that signal
for every focus transition. If they do, a focus-only fast path would be followed
by the already-scheduled full sort and save little unless the trigger model is
also distinguished safely.

Required runtime/source evidence before implementation:

1. instrument one normal Niri focus-switch sequence;
2. count which triggers fire:
   - `NiriService.activeWindowChanged`;
   - `NiriService.windowOrderChanged`;
   - `ToplevelManager.toplevels.valuesChanged`;
3. confirm whether the sort timer is normally scheduled once or more per focus;
4. if active-window change is the only structural trigger, prototype a pure
   focus refresh only when no full sort is already scheduled;
5. compare complete `sortedToplevels` order, `_sourceKey`,
   `niriWindowId`, title/appId, action functions and activated flags.

If a fast path is later implemented, never let it replace an already-pending
full structural sort. Window open/close/title/app-id/workspace/output changes
must keep the authoritative matching path.

This candidate is intentionally kept below the already promoted appId bucketing
and private layout-sort cache, both of which have source-proven savings without
depending on undocumented Quickshell signal behavior.

## 2026-10-07 — Media artwork decode-size research

Research-only continuation on current `dev`
`a87aef29009bf0ae2457aa1804a474578cf77528`. No runtime/product source was
changed in this round.

Current source identities include:

- `modules/common/widgets/MediaCrossSlideImage.qml`:
  `99aacfef3bc12d58ab341e5cd530a5d776263ab6`;
- `modules/mediaControls/presets/CompactPlayer.qml`:
  `4642a25def2eff69ffe450dd09ca336d8f4b68bf`;
- `modules/mediaControls/presets/FullPlayer.qml`:
  `e51ef3d470192a245fe19b26bef3fcca8dc2a98a`;
- `modules/mediaControls/presets/AlbumArtPlayer.qml`:
  `f9c123d6b82073872dcafb7d1b9ba99b4ffeddf9`;
- `modules/waffle/actionCenter/MediaPaneContent.qml`:
  `dfea7b4e2cfb5a0629f8b77911dd56e7c883c354`;
- `modules/waffle/widgets/WidgetsContent.qml`:
  `7919f08b523479a5348660f0b95993d0b0b57544`;
- `modules/waffle/lock/WaffleLockSurface.qml`:
  `9cc7e75e21650c26572a17f61140b7d56fd9a734`;
- `modules/waffle/lock/WaffleLockSurfaceSafe.qml`:
  `86d038cdb3503b0aaae1d3c78b6fdb580263235b`;
- `modules/ii/overlay/volumeMixer/VolumeMixer.qml`:
  `612903a3b1d8cdd5ebb933a53abd90c79aa93f7b`.

Repository/history search found no prior focused optimization note for bounding
these media-art Image decode sizes.

### Candidate — HIGH CONFIDENCE for RAM/GPU, visual budget <1%: bound direct media-art decode size to conservative presentation resolution

Hadalis already has a local precedent for this exact class of image:
`MediaCrossSlideImage.qml` loads both transition layers with:

```qml
sourceSize.width: Math.max(1, Math.round(root.width * 2))
sourceSize.height: Math.max(1, Math.round(root.height * 2))
```

That keeps cover transitions sharp while avoiding decoding the original album
art at arbitrary source resolution.

Several direct media-art Image/StyledImage paths still have no `sourceSize`
at all even though their maximum presentation size is tightly bounded.

Confirmed examples:

| Surface | Presented size / role | Current decode bound |
|---|---|---|
| Waffle Action Center media art | about 104×104 logical px | none |
| Waffle Widgets foreground art | 108×108 logical px | none |
| Waffle Lock / Safe Lock art | 48×48 logical px | none |
| ii Volume Mixer art | 96×96 logical px | none |
| CompactPlayer blurred card background | card-sized | none |
| FullPlayer cover-art background | card-sized | none |
| AlbumArtPlayer blurred cover background | card-sized | none |
| Waffle Widgets blurred background source | roughly panel/card-sized | none |

The Waffle OSD already bounds its media art to 140×140, and
`CompactMediaPlayer.qml` already bounds its blurred card image to the card
size. Those existing paths are evidence that decode-size bounding is compatible
with current media artwork ownership.

Most of the unbounded paths use `cache: false`, so multiple simultaneously
resident surfaces can decode/retain their own image representation instead of
relying on the shared QML Image cache.

### Conservative implementation policy

Do **not** set every media image to 1× logical dimensions.

For foreground artwork, use a conservative target at least equivalent to the
existing cross-slide policy:

```text
requested decode width  = ceil(presentation width  × 2)
requested decode height = ceil(presentation height × 2)
```

or an explicit physical-pixel/DPR-aware equivalent if the runtime contract is
proven across 1.0/1.25/1.5/2.0 scale.

For full-card blurred artwork:

- request enough pixels for the actual visible card/body size;
- include whatever oversampling is required to keep the current blur/mipmap
  result within the visual budget;
- do not assume the same 1× policy as a tiny foreground icon;
- preserve `PreserveAspectCrop`, blur parameters, mipmap/smooth flags and
  transition timing unchanged.

This is intentionally classified as **<1% visual budget**, not exact
pixel-lossless. Pre-decoding/downscaling can change filtering by very small
amounts versus sampling the full-resolution source directly.

### Why the RAM/GPU opportunity can be material

An illustrative 2000×2000 RGBA decoded image represents about 16 MB of raw
pixel data before accounting for implementation-specific texture/mipmap/effect
overheads. A 216×216 conservative decode for a 108×108 foreground slot is about
0.18 MB of RGBA pixels.

Those numbers are size arithmetic, **not measured Hadalis RSS/VRAM savings**.
Actual decoder behavior varies by image format and Qt backend, and some formats
may transiently decode more data before scaling. The steady-state image/texture
residency, however, has a clear upper-bound opportunity.

The gain is especially relevant when the same large album cover is presented
by multiple `cache:false` media surfaces.

### Required visual/resource oracle

Before any implementation is called accepted:

1. fixture covers at low resolution, 512 px, 1k, 2k and 4k;
2. square and non-square source aspect ratios;
3. 1.0 / 1.25 / 1.5 / 2.0 output scale;
4. foreground 48/96/104/108/140 px art;
5. Compact/Full/AlbumArt blurred backgrounds;
6. moving cross-slide/track-change state;
7. compare baseline and bounded versions with:
   - global pixel-difference ratio;
   - edge/detail crop around album-art boundaries;
   - maximum per-channel difference;
   - subjective text/cover sharpness check;
8. record RSS/PSS and, where available, renderer texture/GPU memory for the same
   set of simultaneously visible surfaces.

A candidate that cannot stay below the maintainer's <1% visual-difference
budget at the chosen scale must be rejected or use a larger decode target.

### Adjacent non-candidates

- `MediaCrossSlideImage.qml` already uses a 2× source-size bound; do not reduce
  it from static reasoning.
- `Waffle MediaOSD` already requests a 140×140 source size.
- `CompactMediaPlayer` already bounds the blurred art source to the card.
- ColorQuantizer paths already use their own tiny rescale settings and are not
  the target of this work.

No whole-Hadalis RAM/GPU percentage is claimed without measurement.

## 2026-10-07 — MPRIS desktop-entry hint memo research

Research-only continuation on current `dev`
`fbcdae1136546d8a2ed081401fb32cbbe8348b94`. No runtime/product source was
changed in this round.

Current `services/MprisController.qml`:
`3a8184f9308f0816ea395ea26f182bb5a3fbcf15`.

### Candidate — HIGH CONFIDENCE: memoize `_desktopEntryForHint()` after its full fallback scan

MPRIS stream/player labeling first calls:

```qml
const direct = AppSearch.lookupDesktopEntry(hint)
if (direct) return direct
```

but a direct miss then performs a second, MPRIS-specific fuzzy resolver:

```text
for every DesktopEntry:
    inspect id/name/genericName/startupClass/command[0]
    normalize each candidate
    tokenize candidate
    compare exact/substring/token overlap
```

The same stable hint can be resolved repeatedly from:

- `playerDisplayName()`;
- `streamDesktopEntry()`;
- `streamDisplayName()`;
- `streamIconName()`;
- volume-mixer and media bindings that call those helpers again as reactive
  stream/player state changes.

The previously researched AppSearch exact-input memo only accelerates the first
stage. It does not remove this MPRIS-specific full DesktopEntries scan after an
AppSearch miss.

Strict-lossless direction:

1. normalize the incoming value with the existing
   `_cleanDisplayName(value)`;
2. memoize the **final** `DesktopEntry|null` result under that exact cleaned
   hint;
3. distinguish cached miss from not-cached;
4. invalidate the memo immediately when
   `DesktopEntries.applications.valuesChanged` fires;
5. keep every score, token rule, tie rule and the `bestScore >= 36` threshold
   unchanged;
6. do not key the cache by player/node identity: this resolver's output depends
   only on the cleaned hint plus the current DesktopEntries catalog.

Immediate DesktopEntries invalidation is required for the same reason as the
AppSearch memo candidate: a package install/remove/change must not leave an old
hit or miss visible during any later debounce window.

### Why this has broader leverage than one mixer-only cache

A single PipeWire node can ask for a desktop entry through multiple hint
sources:

```text
application.process.binary
player.desktopEntry
player.identity
application.id
application.name
```

and later ask again while building display name and icon. When the direct
AppSearch resolver cannot identify those strings, each request currently pays
the full MPRIS-specific DesktopEntries scan again.

Caching the final hint result therefore removes repeated tokenization and
catalog scans without changing player↔stream matching, volume state, active
player choice or MPRIS metadata.

### Required oracle

Compare current and memoized object identity/null result for:

- direct AppSearch hit;
- exact MPRIS fallback field match;
- substring match;
- token-overlap match;
- score below threshold;
- multiple equal-score entries proving current first-best/tie behavior;
- empty/malformed hints;
- case/whitespace/version-suffix variants;
- repeated hit and repeated miss;
- DesktopEntry added/removed/changed between calls.

Also verify `streamDisplayName()` and `streamIconName()` output for a
representative set of PipeWire nodes/browser players before and after memo use.

This is CPU/allocation work only; no visual or media-control behavior is
intended to change.

No whole-Hadalis CPU percentage is claimed without runtime measurement.

## 2026-10-07 — Cloudflare WARP direct-argv research

Research-only continuation on current `dev`
`ca83feb68910eab36c5820a63701a3f8ecf40fc3`. No runtime/product source was
changed in this round.

Current source identities:

- shared Waffle model
  `modules/common/models/quickToggles/CloudflareWarpToggle.qml`:
  `0ec62b42e71e805b3c18f2cbfc9ffb5cd78b0e3c`;
- Classic Sidebar toggle
  `modules/sidebarRight/quickToggles/classicStyle/CloudflareWarp.qml`:
  `fee5c5fa1e85ba12daa2fb963fb2d80239558059`;
- Android Sidebar toggle
  `modules/sidebarRight/quickToggles/androidStyle/AndroidCloudflareWarpToggle.qml`:
  `6c0e743dd92f2aa3016cc08e108d1576bde025e2`.

Repository/history search found no earlier optimization note for this process
wrapper.

### Candidate — HIGH CONFIDENCE: execute `warp-cli status` directly instead of forking a shell for every poll

All three implementations currently define the status Process as:

```qml
command: ["/bin/sh", "-c", root.warpCliPath + " status"]
```

where `root.warpCliPath` is the fixed literal:

```qml
readonly property string warpCliPath: "/usr/bin/warp-cli"
```

No shell feature is used by the status command:

- no pipe;
- no redirection;
- no variable expansion;
- no glob;
- no conditional;
- no compound command;
- no user-controlled interpolation.

The equivalent direct argv command is therefore:

```qml
command: [root.warpCliPath, "status"]
```

This removes one shell process from every status refresh while leaving
`warp-cli` stdout/exit status as the Process observation.

The common Waffle model is already lifecycle-gated:

```qml
running: root.available
    && (GlobalStates.sidebarRightOpen || GlobalStates.waffleActionCenterOpen)
```

and Classic/Android Sidebar implementations poll while the Sidebar is open.
The current interval is 5 seconds and `triggeredOnStart: true`, with additional
explicit refreshes after connect/disconnect/service-start actions.

Thus this is not an argument to change the 5-second freshness contract. It
removes only the unnecessary intermediate process.

### Expected structural saving

While the relevant surface is open, every periodic status refresh changes from:

```text
Quickshell Process
  -> /bin/sh -c
      -> /usr/bin/warp-cli status
```

to:

```text
Quickshell Process
  -> /usr/bin/warp-cli status
```

At a 5-second cadence, one minute of open-surface polling can avoid about
12 shell child processes per live WARP-toggle instance. Action-triggered
refreshes avoid the shell as well.

This is CPU/process churn, not a GPU/RAM headline item.

### Required oracle before implementation

For each of the three toggle implementations, compare current and direct-argv
behavior for:

- WARP installed and connected;
- installed and disconnected;
- daemon unavailable;
- `warp-cli status` nonzero exit;
- stdout containing the existing connected/disconnected/error strings;
- panel open/close poll start/stop;
- connect/disconnect action followed by immediate refresh;
- service-start action followed by refresh.

Assert identical:

- `available`;
- `_daemonRunning`;
- `toggled`;
- visibility behavior of legacy Classic/Android toggles;
- tooltip/status text;
- notification/error behavior.

### Adjacent shell-wrapper sweep

Other `sh -c` / `bash -c` sites inspected in the same pass were **not**
mechanically promoted. Most use real shell semantics such as pipes,
redirection, multiple commands, positional parameters, timeout composition or
filesystem tests. Examples include Audio sound enumeration, Brightness paired
queries, TLP capability probing, Hotspot setup, ResourceUsage GPU probes,
Weather GPS parsing and thumbnail/media cache helpers.

Only wrappers whose command can be represented as the exact same argv/process
contract should be converted under strict-lossless rules.

## 2026-10-07 — Hyprsunset direct-argv probe research

Research-only continuation on current `dev`
`86a60f30893011ff8eb7ef25d8de9249faa84ba9`. No runtime/product source was
changed in this round.

Current `services/Hyprsunset.qml`:
`ad37a89247439f2133ba65fb2248b81edbdc90b3`.

### Candidate — HIGH CONFIDENCE but low-frequency: remove the shell from Hyprland state probing

The Hyprland night-light state probe currently uses:

```qml
command: ["/usr/bin/bash", "-c", "hyprctl hyprsunset temperature"]
```

The shell command contains no shell syntax. Its only purpose is to execute
`hyprctl` with two argv entries.

The Process already owns all required control outside the shell:

- stdout collection;
- start-observed tracking;
- 5-second timeout;
- exit-code handling;
- output checks for empty / `Couldn't...` / `6500`;
- state publication and pending enable/disable continuation.

Therefore the equivalent direct command can be:

```qml
command: ["hyprctl", "hyprsunset", "temperature"]
```

(or an explicit resolved hyprctl path if the project decides PATH lookup should
be fixed).

This removes one Bash process from each Hyprland night-light state probe while
keeping the authoritative `hyprctl` observation unchanged.

### Priority

This is strict-lossless and simple, but lower value than the Cloudflare WARP
direct-argv candidate because Hyprsunset does not continuously poll at a short
cadence. Probes occur around deferred load, explicit state resolution and
post-action verification.

Keep it as a companion process-churn cleanup, not a headline optimization.

### Required oracle

Compare current and direct-argv behavior for:

- hyprsunset active;
- inactive / 6500 output;
- hyprctl error output;
- hyprctl missing / spawn failure;
- timeout;
- explicit enable/disable;
- temperature change while active;
- pending toggle before initial state becomes known.

Assert identical `stateKnown`, `active`, pending enable/disable state and
timeout/error behavior.

## 2026-10-07 — MPRIS grace-state session-growth research

Research-only continuation on current `dev`
`a0a88b34a63e14847358ade133c4e14a183c0ed4`. No runtime/product source was
changed in this round.

Current `services/MprisController.qml`:
`3a8184f9308f0816ea395ea26f182bb5a3fbcf15`.

### Candidate — HIGH CONFIDENCE: prune behaviorally expired player-grace entries during existing updates

The controller keeps a private grace map:

```qml
property var _playerGrace: ({})  // dbusName -> timestamp
```

and defines grace validity as:

```qml
const graceTime = _playerGrace[name]
if (!graceTime) return false
return (Date.now() - graceTime) < 2000
```

When a player has valid metadata or is playing, the update path does:

```qml
let nextGrace = Object.assign({}, _playerGrace)
nextGrace[name] = Date.now()
_playerGrace = nextGrace
```

Full-file occurrence inspection shows no path that removes an expired key.

Therefore every unique D-Bus player instance name seen during a long session can
remain in the map forever even though its behavioral value becomes permanently
dead after two seconds unless the exact same D-Bus name is updated again.
Browser tabs, transient mpv instances and players that encode a unique instance
suffix can grow this state gradually.

The cost is twofold:

1. stale JS key/value retention;
2. every later valid metadata update clones the entire accumulated map before
   changing one timestamp.

Strict-lossless direction:

- when `_updateGrace()` already needs to publish a new grace timestamp, build
  the next map from only entries whose current timestamp is still inside the
  same existing 2000 ms validity window, then write the current player;
- alternatively mutate the private map in-place only if an oracle proves no
  consumer depends on `_playerGraceChanged`; pruning is still required either
  way;
- do **not** add a cleanup timer;
- do **not** shorten the current 2000 ms window;
- keep `_isInGracePeriod()` comparison semantics unchanged.

A conservative implementation can preserve the current QML property
reassignment pattern while pruning, which makes the optimization independent of
any question about property-change notification.

### Required oracle

Use a deterministic clock helper and compare current/new
`_isInGracePeriod()` answers for:

- no entry;
- timestamp at 0/1/1999/2000/2001 ms age;
- multiple live entries;
- mixture of live and expired entries;
- current player's previous expired entry;
- repeated updates of the same D-Bus name;
- many unique historical names followed by one current-player update.

Assert:

- every grace answer for every non-expired player is identical;
- expired keys disappear only during an already-existing update event;
- no additional timer/wakeup is introduced;
- active/display player membership/order remains identical.

This is a cumulative session RAM/JS-allocation cleanup, not a GPU optimization,
and no whole-Hadalis percentage is claimed without runtime measurement.

### Adjacent private-map sweep

`NiriService._autoMaximizedWs` was inspected in the same pass. It is also a
private imperative map and uses copy-on-write, but it is bounded by active
workspace count and is actively pruned when tracked workspaces gain/lose tiling
windows. Its absolute value is much smaller, so it is not promoted as a
separate optimization.

`KeyboardIndicators` state maps are rebuilt from the currently discovered
LED path set and likewise do not form an unbounded session cache.

## 2026-10-07 — ResourceUsage process-backed GPU direct-argv research

Research-only continuation on current `dev`
`d06648d8c046245d520a97d943f7a04c310c7043`. No runtime/product source was
changed in this round.

Current `services/ResourceUsage.qml`:
`1d8e8693c230ee7450072366557b6070d433af58`.

### Candidate — HIGH CONFIDENCE: remove Bash from recurring NVIDIA/Intel GPU probes

The service deliberately polls process-backed GPU metrics less frequently than
CPU/RAM/sysfs metrics:

```qml
readonly property int _expensiveGpuUpdateIntervalMs:
    lowPower
        ? Math.max(15000, _effectiveUpdateIntervalMs)
        : Math.max(6000, _effectiveUpdateIntervalMs)
```

When the selected source is NVIDIA or Intel, each expensive poll currently
starts an extra shell:

```qml
// NVIDIA
command: ["/usr/bin/bash", "-c",
    root._nvidiaSmiPath
    + " --query-gpu=utilization.gpu,temperature.gpu "
    + "--format=csv,noheader,nounits 2>/dev/null | head -n 1"]

// Intel
command: ["/usr/bin/bash", "-c",
    "timeout 1 " + root._intelGpuTopPath + " -J -s 500 2>/dev/null"]
```

The shell is not required for either underlying tool invocation.

#### NVIDIA direct-argv shape

Equivalent process ownership can be:

```text
_nvidiaSmiPath
  --query-gpu=utilization.gpu,temperature.gpu
  --format=csv,noheader,nounits
```

with stderr consumed by an empty `StdioCollector` to preserve the current
`2>/dev/null` behavior.

The current `head -n 1` selects the first GPU row. Preserve that explicitly in
the QML parser by taking the first non-empty output line before splitting the
two CSV fields. Do not rely on the current whole-text comma split as an
accidental multi-GPU behavior.

#### Intel direct-argv shape

Equivalent timeout ownership can be:

```text
/usr/bin/timeout
  1
  <detected intel_gpu_top path>
  -J
  -s
  500
```

again with stderr consumed by an empty `StdioCollector`.

This retains:

- the one-second hard timeout;
- the 500 ms PMU sample request;
- the same stdout JSON;
- the same QML regex that takes the maximum reported engine `busy` value;
- the same poll cadence and `running` gate.

### Why this is strict-lossless

The shell contributes only:

- argv tokenization;
- stderr redirection;
- NVIDIA `head -n 1`;
- Intel invocation of `timeout`.

All four functions have direct equivalents in the existing Process/QML layer.
No sampling frequency, GPU wake policy, metric interpretation or consumer
lifecycle needs to change.

This candidate is independent of the separate ResourceUsage research about
demand-gating GPU/disk metrics. If demand gating later reduces the number of
polls, direct argv still removes one unnecessary shell process from every poll
that remains.

### Required oracle

NVIDIA:

- one GPU;
- multiple GPUs, proving first-row ownership is unchanged;
- empty output;
- malformed usage or temperature field;
- nonzero exit / driver unavailable;
- stderr-only error.

Intel:

- valid multi-engine JSON;
- no `busy` field;
- malformed/partial JSON output;
- timeout exit;
- tool nonzero exit;
- missing detected executable/spawn failure.

For both, assert identical published `gpuUsage` and `gpuTemp` values and no
new stderr noise.

### Structural saving

While a process-backed GPU source is actively monitored, one shell process is
removed from every expensive GPU sample. At the default minimum 6-second
cadence this is up to about ten avoided shell launches per minute of active
monitoring; low-power mode reduces both the original and optimized cadence.

No whole-Hadalis CPU/RAM percentage is claimed without runtime measurement.

## 2026-10-07 — Notification timer object-reuse research

Research-only continuation on current `dev`
`10bde01ceb00f0fc54db7e1c65997d1711e0d2b8`. No runtime/product source was
changed in this round.

Current `services/Notifications.qml`:
`a05c6744c123d8ed96ee19c8d04cccdbcdeeae0e`.

### Candidate — HIGH CONFIDENCE: stop re-looking-up notification objects that the caller already owns

Several notification paths already hold the exact notification QML object, but
call the public ID-based helper:

```qml
function cancelTimeout(id) {
    const index = root.list.findIndex(
        notif => notif.notificationId === id)
    if (index !== -1 && root.list[index]?.timer != null) {
        root.list[index].timer.stop()
        root.list[index].timer.destroy()
        root.list[index].timer = null
    }
}
```

That forces another full `root.list` scan.

#### Current `timeoutNotification(id)`

The function first performs:

```qml
const index = root.list.findIndex(...)
```

and then immediately calls:

```qml
root.cancelTimeout(id)
```

which performs the same lookup again.

This can be reduced to one lookup by retaining
`const notif = root.list[index]` and cancelling `notif.timer` directly.

#### Current `timeoutAll()`

`root.popupList` already contains the live notification objects:

```qml
root.popupList.forEach(notif => {
    root.cancelTimeout(notif.notificationId)
    root.timeout(notif.notificationId)
})
root.popupList.forEach(notif => {
    notif.popup = false
})
```

If P popup notifications exist in a retained history list of N notifications,
the cancellation phase can perform P separate O(N) ID scans even though the
correct object is already present.

Strict-lossless replacement can keep the exact logical order:

1. snapshot/use the current popup object list as today;
2. for each popup object:
   - stop/destroy/null its timer directly;
   - emit `root.timeout(notificationId)` in the same order;
3. perform the existing popup-flag clear in the same second pass if signal/order
   parity requires retaining that phase split;
4. call `triggerListChange()` once exactly as today.

#### Current `markReadForApp(identifiers)`

This function already iterates `root.list`:

```qml
root.list.forEach(notif => {
    if (notif.popup && appMatches) {
        cancelTimeout(notif.notificationId)
        notif.popup = false
        changed = true
    }
})
```

Each matching notification therefore triggers a second list scan. Directly
cancelling the timer on `notif` preserves the current behavior and turns the
path back into one list pass.

### Why this is strict-lossless

No new cache/index is required. The optimization only reuses an object reference
that the current caller already obtained from the authoritative list.

Preserve exactly:

- timer `stop()`;
- timer `destroy()`;
- assignment `notif.timer = null`;
- per-notification `timeout(id)` emission in `timeoutAll()`;
- popup-flag mutation order;
- final `triggerListChange()` behavior;
- `cancelTimeout(id)` itself for external callers that only have an ID
  (Classic/Waffle notification-group hover paths).

### Required oracle

Cover:

- one popup in one-item history;
- many popups in long retained history;
- mixture of popup and already-read notifications;
- notification with no timer;
- timeout of missing ID;
- `timeoutNotification()`;
- `timeoutAll()`;
- `markReadForApp()` matching zero/one/many notifications;
- verify identical `timeout(id)` signal count/order;
- verify timer destruction/null state;
- verify final popupList/group state.

Structural saving:

- `timeoutNotification`: two full-list ID scans become one;
- `timeoutAll`: P full-list scans are removed;
- `markReadForApp`: one extra full-list scan is removed per matching
  notification.

This is CPU/JS collection work only and no whole-Hadalis percentage is claimed
without runtime measurement.

## 2026-10-07 — Notification badge lookup research

Research-only continuation on current `dev`
`15273940fffa93c78308bf3bae10421b32982442`. No runtime/product source was
changed in this round.

Current source identities:

- `services/Notifications.qml`:
  `a05c6744c123d8ed96ee19c8d04cccdbcdeeae0e`;
- `modules/dock/DockAppButton.qml`:
  `e82cf611338e518d70f8c95e45808217c7b90934`.

### Candidate — HIGH CONFIDENCE: cache normalized popup-group badge lookup once per notification-group rebuild

Each Dock application button exposes:

```qml
readonly property int notificationCount: {
    ...
    return Notifications.countForApp([
        appToplevel?.originalAppId ?? appToplevel?.appId,
        root.desktopEntry?.name
    ])
}
```

The current helper normalizes the caller identifiers and then scans every popup
group, normalizing each group appName on every call:

```qml
function countForApp(identifiers): int {
    const keys = (identifiers ?? [])
        .map(root._normalizeAppKey)
        .filter(k => k.length > 0)
    if (keys.length === 0) return 0
    const groups = root.popupGroupsByAppName
    for (const appName in groups) {
        if (keys.indexOf(root._normalizeAppKey(appName)) !== -1)
            return groups[appName].notifications?.length ?? 0
    }
    return 0
}
```

Popup groups already have an explicit rebuild boundary in `_updateGroups()`.
The normalized app-name lookup can therefore be derived once per rebuilt popup
snapshot instead of once per Dock delegate evaluation.

Strict-lossless direction:

1. while publishing `_cachedPopupGroupsByAppName`, derive a private normalized
   lookup from that exact object insertion order;
2. store for each normalized key:
   - the first matching group's rank/order;
   - that group's notification count;
3. `countForApp(identifiers)` normalizes only the supplied identifiers,
   performs direct cached lookups and returns the count belonging to the
   **lowest-ranked** matching group;
4. invalidate/publish that lookup in the same `_updateGroups()` transaction as
   popup groups.

The rank rule is required for parity. Current semantics are not “sum all groups
whose normalized name matches” and are not “first caller identifier wins”.
The outer loop is the popup-group enumeration, so the **first group in current
object order that matches any supplied identifier** wins. If two distinct app
names normalize to the same key, a simple overwriting Map or summation would
change behavior.

### Expected structural saving

For D visible Dock app buttons and G popup app groups, current badge
re-evaluation can perform roughly D×G group iterations plus repeated regex
normalization of app names. The cached form moves group-name normalization to
the group-rebuild event and makes each button lookup proportional only to its
small identifier set (normally two strings).

The gain remains small when there are few notifications, but it is strict,
centralized and scales better for notification-heavy sessions.

### Required oracle

Compare current/new `countForApp()` for:

- empty groups and empty identifiers;
- one normal app match;
- appId vs desktop display-name match;
- punctuation/case differences;
- two caller identifiers matching different popup groups;
- two distinct group names that normalize to the same key;
- no match;
- popup timeout/read transition;
- group insertion/order changes after notification updates.

Assert exact count parity after every `_updateGroups()` snapshot.

### Adjacent note

This composes with the separate notification timer object-reuse finding, but it
must remain a separate patch/oracle: one optimizes group-derived badge reads,
the other removes redundant notification-ID scans during timeout/read
mutations.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without runtime
measurement.

## 2026-10-07 — System tray classification research

Research-only continuation on current `dev`
`cb11f16188f7e62480d2fc9c21ffa7fdee82eee7`. No runtime/product source was
changed in this round.

Current `services/TrayService.qml`:
`3f5e1f2580aebadf87ab40b91b4876c9ca68e76b`.

### Candidate — HIGH CONFIDENCE: classify SystemTray items once per source/config change

Current derived lists independently scan the same source collection:

```qml
property list<var> fcitxItems:
    SystemTray.items.values.filter(i => root.isFcitxItem(i))

property list<var> itemsInUserList:
    SystemTray.items.values.filter(i =>
        isValidItem(i)
        && !root.isFcitxItem(i)
        && _pinnedItems.includes(i.id))

property list<var> itemsNotInUserList:
    SystemTray.items.values.filter(i =>
        isValidItem(i)
        && !root.isFcitxItem(i)
        && !_pinnedItems.includes(i.id)
        && (!smartTray || i.status !== Status.Passive))
```

A tray-source/status/pin change can therefore:

- traverse `SystemTray.items.values` three times;
- run Fcitx id/title lowercase classification in all three derivations;
- linearly scan `_pinnedItems` for every non-Fcitx item in the two user-list
  derivations.

The three outputs are mutually derivable from one ordered pass.

Strict-lossless direction:

1. create one derived private classification object from:
   - `SystemTray.items.values`;
   - `_pinnedItems`;
   - `smartTray`;
2. create a JS `Set` from the raw pinned-id array for membership only;
3. iterate tray items once in source order:
   - invalid item: omit from all outputs;
   - Fcitx item: append only to `fcitx`;
   - valid pinned non-Fcitx item: append to `inUserList` regardless of passive
     status, exactly as current source;
   - valid unpinned non-Fcitx item: append to `notInUserList` only when
     `!smartTray || status !== Status.Passive`;
4. publish the existing `fcitxItems`, `itemsInUserList` and
   `itemsNotInUserList` properties from that one classification result;
5. leave `invertPins`, final pinned/unpinned concatenation and all tray action
   behavior unchanged.

A Set is semantically safe for the membership test because current
`Array.includes(item.id)` only asks whether an exact raw id value is present;
pin ordering/duplicates are not consulted by this classification path.
Do not use the Set to rewrite the persisted pin array or pin-management
semantics.

### Required oracle

Compare the three derived lists by object identity and order for:

- empty tray;
- null/invalid entries;
- Fcitx item by id and by title;
- pinned active/passive item;
- unpinned active/passive item with smartTray on/off;
- duplicate persisted pin ids;
- pin ids absent from the tray;
- invertPins true/false;
- item status changes without item insertion/removal;
- live pin/unpin mutations.

Also assert final `pinnedItems`/`unpinnedItems` arrays remain identical.

### Structural saving

One tray derivation event moves from three source-list filters plus repeated
linear pin membership checks to one source pass plus O(1)-average membership
lookups. Absolute gain will normally be modest because tray item counts are
small, but the service is shell-lifetime state and the change is fully
lossless.

No whole-Hadalis CPU/RAM percentage is claimed without runtime measurement.

## 2026-10-07 — Network nmcli helper direct-argv research

Research-only continuation on current `dev`
`8b43c897d73bc941b14307ae5ff9a9c86e1052f4`. No runtime/product source was
changed in this round.

Current `services/Network.qml`:
`a20c4c1edf1fbeb2f2a8285518af053bf72a09dc`.

### Candidate — HIGH CONFIDENCE: remove shell/head/awk wrappers from connected-network detail refresh

The network service is already event-driven through `nmcli monitor` and
debounces bursts for 200 ms. The remaining process overhead is inside the
refresh it performs after those events.

When an active link exists, the service currently resolves the displayed
connection name through:

```qml
command: [
    "sh", "-c",
    "nmcli -t -f NAME c show --active | head -1"
]
```

and Wi-Fi signal strength through:

```qml
command: [
    "sh", "-c",
    "nmcli -f IN-USE,SIGNAL,SSID device wifi | "
      + "awk '/^\\*/{if (NR!=1) {print $2}}'"
]
```

Each helper therefore launches a shell, one `nmcli` child and an additional
`head` or `awk` child.

Strict-lossless direction:

#### Active connection name

Run directly:

```text
nmcli -t -f NAME c show --active
```

collect stdout in QML and publish the first non-empty line. This is the direct
equivalent of the current `head -1` ownership.

Preserve exact first-row semantics; do not sort or prefer Wi-Fi over Ethernet.

#### Wi-Fi strength

Run `nmcli` directly and parse the active row in QML. Two safe implementation
shapes can be oracle-tested:

- retain current columns/output formatting:
  `nmcli -f IN-USE,SIGNAL,SSID device wifi`, then select the first row whose
  trimmed line begins with `*` and parse its signal column; or
- use terse output:
  `nmcli -t -f IN-USE,SIGNAL device wifi`, then parse the active `*:<signal>`
  record.

The chosen form must reproduce the current first-active-row result exactly.

No refresh cadence or monitor lifecycle changes are required.

### Why this is strict-lossless

The shell wrappers only provide pipeline text processing:

- `head -1` for connection name;
- `awk` selection/parsing for active Wi-Fi signal.

Both operations are deterministic over the collected stdout and can be moved
into QML without changing NetworkManager queries.

Keep unchanged:

- `LANG=C` / `LC_ALL=C` where parser behavior depends on nmcli output;
- updateConnectionType's existing status/connectivity/radio query;
- the failure-only `wifiStatusProcess`;
- the 200 ms monitor debounce;
- clearing stale `networkName`/`networkStrength` when no active link exists;
- no new polling timer.

### Required oracle

Connection-name cases:

- one active Wi-Fi profile;
- one active Ethernet profile;
- multiple active connections, proving first-line ownership;
- no active connection;
- nonzero nmcli exit.

Strength cases:

- one active AP;
- several visible APs with one active row;
- no active AP;
- signal 0/100 and malformed value;
- SSID containing spaces/colons;
- nonzero nmcli exit.

For a scripted fixture, compare current shell-pipeline result against the direct
argv + QML parser result byte/logically for every case.

### Structural saving

For each debounced connected-Wi-Fi detail refresh, up to four intermediary
processes disappear:

- connection name: shell + `head`;
- signal strength: shell + `awk`.

The two required `nmcli` queries remain. This complements rather than replaces
the existing event-driven monitor architecture.

No whole-Hadalis CPU/RAM percentage is claimed without runtime measurement.

## 2026-10-07 — Default-off startup probe ownership research

Research-only continuation on current `dev`
`fe236f306bbeded229db9b66d2a75a4d4eb87136`. No runtime/product source was
changed in this round.

Current source identities:

- `shell.qml`:
  `aae76205a819e9b098f6a4be7fb6d56e14ff4900`;
- `services/ThinkFanService.qml`:
  `943082413a143df3e642ee3d60587093dda1ec02`;
- `services/Battery.qml`:
  `e276ddc01dcbe01977e1f285ed2c7dc46e5928d2`;
- `services/TlpService.qml`:
  `4e0ef4fba76eb00df7ddc54941e205029dde07ec`;
- `services/Audio.qml`:
  `03e2286f1e4035113ba33523c196aca27904cdcc`;
- `modules/common/Appearance.qml`:
  `55480307855a511518206c8dbea5e5eb20d76c33`.

These candidates existed in older archive research but had not yet been carried
into the canonical cross-repo handoff. Current `dev` still exhibits the same
ownership shape.

### Candidate A — HIGH CONFIDENCE: do not force ThinkFan status discovery when profile fan control is disabled

`shell.qml` holds:

```qml
property var _thinkFanService: ThinkFanService
```

for session-long profile following.

The shipped default is:

```json
"powerProfiles": {
  "fanControl": {
    "enabled": false
  }
}
```

but `ThinkFanService.Component.onCompleted` immediately calls
`root.refresh()`, whose detector runs:

```text
/usr/libexec/inir-thinkfan --status
```

The long-lived ownership is only required when profile-follow is enabled.
Settings/System Monitor can materialize/refresh ThinkFan on explicit demand.

Strict-lossless ownership direction:

1. keep ThinkFan resident for the whole session when
   `powerProfiles.fanControl.enabled=true`;
2. react to that config becoming enabled at runtime and acquire/prime the
   singleton before applying the current profile intent;
3. when disabled from startup, do not force the singleton merely for
   profile-follow;
4. Settings/diagnostic surfaces explicitly demand/refresh capability state;
5. preserve the current active/managed polling and stale-status refresh behavior
   once the feature is enabled.

Do not remove the service or helper; only move default-off ownership.

### Candidate B — HIGH CONFIDENCE, deeper dependency: separate ordinary Battery telemetry from charge-limit/TLP capability

`Battery.qml` is normal session state for percentage/charge notifications, but
also directly re-exports many `TlpService` properties:

```qml
chargeLimitAvailable: TlpService.available
chargeLimitSupported: TlpService.supported
chargeLimitAdjustable: TlpService.adjustable
...
```

The shipped default is:

```json
"battery": {
  "chargeLimit": {
    "enable": false
  }
}
```

while `TlpService` still owns unconditional startup detection and runs:

```text
/usr/libexec/inir-battery-charge-limit --status
```

Normal UPower battery telemetry does not need that helper.

Strict-lossless direction:

- keep ordinary Battery percentage/state/cycle-count ownership independent;
- demand the charge-limit adapter when:
  - charge care is enabled in config, or
  - a Settings/TLP capability surface is presented;
- when demand first appears, run the current authoritative detection before
  presenting/writing policy;
- if charge care is enabled at boot, preserve current early reconciliation and
  ownership semantics;
- do not weaken TLP/plugin/vendor capability detection.

This needs a focused QML lifecycle test because Battery is widely referenced and
the current re-export API should remain usable by Settings consumers.

### Candidate C — HIGH CONFIDENCE: lazy-load the Audio sound-theme catalog

Audio itself is startup-relevant for device/microphone state. Its completion
handler correctly calls:

```qml
_refreshMicState()
```

but also unconditionally starts:

```qml
themeSoundsProc.running = true
```

whose command is:

```text
sh -> ls /usr/share/sounds/<theme>/stereo
   -> sed
   -> sort -u
```

Repository-wide current-source search finds `Audio.themeSounds` consumed only
by the shared `SoundPicker`, and `SoundPicker` is instantiated by Settings
pages.

Strict-lossless direction:

1. add idempotent `ensureThemeSoundsLoaded()`;
2. SoundPicker requests the catalog when it becomes resident;
3. keep a “catalog has been demanded” flag;
4. after first demand, `onAudioThemeChanged` refreshes the loaded catalog as
   today;
5. before first demand, theme changes do not enumerate a list no surface can
   read.

Microphone/device startup behavior remains untouched.

### Candidate D — HIGH CONFIDENCE with explicit-backend guard: demand-gate the Niri version blur-capability probe

`Appearance.qml` currently runs:

```qml
Process {
    id: nativeBlurVersionProbe
    running: CompositorService?.isNiri ?? false
    command: ["niri", "--version"]
}
```

for every Niri session.

The shipped default is:

```json
"performance": {
  "blurBackend": "auto"
}
```

and `blurBackendFor()` explicitly documents that `auto` is fidelity-first:
it returns wallpaper/off and never upgrades to compositor blur.

Current direct consumers of `nativeBlurSupported` are Effects Settings.
Runtime `compositorBlurActive` matters only when an effective area/backend
request explicitly resolves to `compositor`.

Strict-lossless direction:

- if any effective configured blur backend/area override explicitly requests
  `compositor`, prime the Niri version capability early enough that those
  surfaces keep the current compositor-or-wallpaper fallback behavior;
- otherwise, do not run `niri --version` merely for default `auto`;
- Effects Settings can explicitly ensure the capability probe before deciding
  whether the compositor-blur control is visible;
- cache the result for the session;
- if configuration changes from auto/wallpaper/off to compositor at runtime,
  trigger the probe and let dependent bindings re-evaluate on completion.

Do not treat “Niri is running” alone as blur-capability demand.

### Validation / ordering

These are four independent lifecycle cuts. Do not combine them into one broad
lazy-singleton refactor.

Suggested proof order:

1. Audio sound catalog — narrowest dependency surface;
2. Niri blur version probe — one process and explicit demand condition;
3. ThinkFan profile-follow ownership;
4. Battery/TLP charge-care split — widest API/lifecycle surface.

For each, compare child-process traces on default config and on the explicitly
enabled feature. Enabled-feature behavior must remain unchanged.

No whole-Hadalis startup percentage is claimed without a measured before/after
boot trace.

## 2026-10-07 — Pre-QML environment cache and ABI fast-path research

Research-only continuation on current `dev`
`3015b97b62ca1458e869873f10521c115929be9f`. No runtime/product source was
changed in this round.

Current `scripts/inir`:
`5cf6ca0ef112cf0f98ee28f23cc618cbb34d5018`.

### Candidate A — P0 / HIGH CONFIDENCE: make the documented systemd user-environment cache actually live in the parent shell

The launcher documents:

```bash
# Cached systemd user environment — avoids duplicate blocking calls.
# ... We call it once with a tight timeout and cache the result for both
# apply_qt_runtime_env() and ensure_systemd_graphical_env()
_cached_systemd_env=""
_cached_systemd_env_fetched=false
```

and the helper mutates those variables:

```bash
_get_systemd_user_env() {
    if [[ "$_cached_systemd_env_fetched" == true ]]; then
        printf '%s' "$_cached_systemd_env"
        return 0
    fi
    _cached_systemd_env_fetched=true
    _cached_systemd_env="$(
        timeout 3s systemctl --user show-environment 2>/dev/null
    )" || true
    printf '%s' "$_cached_systemd_env"
}
```

But both consumers invoke it through command substitution:

```bash
_qs_sys_env="$(_get_systemd_user_env)"
...
sys_env="$(_get_systemd_user_env)"
```

A Bash function executed inside command substitution runs in a subshell.
Therefore the helper's assignments to
`_cached_systemd_env_fetched` / `_cached_systemd_env` do not propagate back
to the parent launcher.

The second consumer can consequently execute the bounded
`systemctl --user show-environment` call again even though the source claims
the snapshot is shared.

This matters before Quickshell starts: the timeout is intentionally as large as
3 seconds because a fresh user D-Bus environment can be temporarily
unresponsive.

Strict-lossless direction:

1. split “populate cache” from “print cache”;
2. call the populate function normally in the parent shell;
3. let both consumers read `$_cached_systemd_env` directly;
4. preserve the current fail-open 3-second timeout and empty-snapshot behavior;
5. keep ShellExec's later live manager-environment read unchanged.

A focused shell test should provide a fake `systemctl` that increments a
counter and assert both startup consumers observe one identical snapshot with
exactly one `show-environment` invocation.

### Candidate B — HIGH CONFIDENCE follow-on: parse the cached environment once without repeated grep/head/cut subprocesses

`apply_qt_runtime_env()` currently retrieves up to fourteen named values from
the same multiline snapshot through command substitutions such as:

```bash
grep "^NAME=" <<< "$_qs_sys_env" | head -1 | cut -d= -f2-
```

and `ensure_systemd_graphical_env()` performs another series of
`grep -q '^NAME='` presence checks.

After Candidate A makes the snapshot genuinely shared, build one pure-shell
lookup/presence representation from that snapshot once and reuse it for both
consumers.

Constraints:

- preserve first-occurrence semantics;
- preserve values containing `=`;
- preserve empty-vs-missing distinction wherever current code relies on it;
- do not execute manager output as shell source;
- keep PATH merge order exactly as current source;
- keep compositor socket fallback/recovery logic untouched.

This removes startup helper fan-out without changing session variables.

### Candidate C — HIGH CONFIDENCE with cache-identity oracle: consult successful ABI identity before `qs --version`

`check_qs_abi()` currently starts with:

```bash
qs_output="$("$qs_bin" --version 2>&1 || true)"
```

and only afterward computes the successful ABI cache key:

```text
v2:<quickshell-binary-mtime>:<resolved-Qt6Core-mtime>
```

If that key matches the previous successful check, the later expensive
`strings` scan is skipped — but the `qs --version` process has already run.

A safe fast path can:

1. resolve the same Quickshell and Qt library identities used by the successful
   cache;
2. compare the exact successful cache key first;
3. return before `qs --version` only when both identities are unchanged;
4. fall through to the current primary/secondary mismatch detection for any
   missing/changed identity;
5. continue writing cache entries only for successful checks.

Do not cache a mismatch or bypass validation after either binary/library
identity changes.

Required oracle:

- no cache;
- valid successful cache;
- changed Quickshell mtime;
- changed resolved Qt library mtime;
- missing Qt library path;
- `qs --version` mismatch warning;
- secondary strings mismatch;
- successful full check then second cached invocation;
- stale/legacy cache prefix.

### Priority implication

This launcher work ranks above most single-QML micro-optimizations because it
sits on the critical pre-QML startup path and Candidate A repairs an already
documented cache contract that current code does not actually satisfy.

No startup percentage is claimed until a cold/warm before-after boot trace is
captured.

## 2026-10-07 — Weather primary fetch direct-argv research

Research-only continuation on current `dev`
`cdfdf26130de9de0aa1ab1612c59a4dc9d805d51`. No runtime/product source was
changed in this round.

Current `services/Weather.qml`:
`53ef5db3a161e6df18a29b1e6a7c6192d2e35a79`.

### Candidate — HIGH CONFIDENCE: remove Bash from the primary wttr.in fetch path

The primary weather provider currently builds a URL and then starts:

```qml
const cmd = `curl -s --max-time 15 'https://wttr.in/${query}?format=j1'`
fetcher.command = ["/usr/bin/bash", "-c", cmd]
```

No shell feature is required by this command. There is no pipe, redirect,
variable expansion or conditional execution. The same service already uses
direct argv for its Open-Meteo fallback and air-quality requests:

```qml
["/usr/bin/curl", "-s", "--max-time", "15", url]
```

Strict-lossless direction:

1. construct the exact same wttr.in URL string;
2. assign
   `fetcher.command = ["/usr/bin/curl", "-s", "--max-time", "15", url]`;
3. keep request-generation ownership, empty-response handling, parse fallback,
   retry counters and provider failover untouched;
4. do not alter query construction or provider ordering.

This removes one Bash process for every primary-provider request/retry while
keeping the curl process and stdout/exit semantics unchanged.

### Required oracle before implementation

- coordinates path;
- city-name path with spaces and non-ASCII characters;
- request generation cancellation;
- curl exit failure;
- empty payload;
- non-JSON payload;
- valid wttr JSON;
- three primary failures causing the existing Open-Meteo bypass window;
- force-refresh while another provider request is running.

Compare the exact argv URL against the current shell command's effective curl
argument. No network behavior, retry timing or visual state should change.

### GPS path is separate

The Geoclue fallback currently uses:

```text
where-am-i -t 10
  | grep latitude/longitude
  | head -2
  | paste -sd' '
```

That path genuinely uses a parsing pipeline. Do not classify it as the same
direct-argv cleanup. A future optimization would require capturing raw
`where-am-i` output and reproducing the current extraction semantics in QML or
a helper with a focused parser oracle.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without runtime
measurement.

## 2026-10-07 — ScreenTime startup FileView research

Research-only continuation on current `dev`
`c44541e07ca65ac283b168c00b9cdc3044545bd1`. No runtime/product source was
changed in this round.

Current `services/ScreenTime.qml`:
`1eabb174c464bf0a1e372ebbe8a43f671d2e9d89`.

### Candidate — HIGH CONFIDENCE: replace startup Bash test+cat with the existing FileView

ScreenTime owns a `FileView` for the current day's JSON:

```qml
FileView {
    id: todayFileView
    path: ""
}
```

It already uses that object for persistence via `setText()`. Startup loading,
however, currently launches:

```qml
["/usr/bin/bash", "-c",
 `test -f "${path}" && cat "${path}" || echo "__NOFILE__"`]
```

and routes stdout into `_finishStartupRead()`.

The shell is only being used to distinguish “file exists” from “file missing”
and to read text. `FileView` already exposes the exact lifecycle needed:

- `onLoaded` + `text()`;
- `onLoadFailed(error)`;
- `FileViewError.FileNotFound`.

The repository already uses this pattern in GameMode, InternalTodoBackend,
NotesContent and other services.

Strict-lossless direction:

1. set `todayFileView.path = Qt.resolvedUrl(root._todayFilePath())` when the
   startup read begins;
2. keep the existing `_loadingToday` reentrancy guard;
3. on `todayFileView.onLoaded`, if `_loadingToday` is true, call
   `_finishStartupRead(todayFileView.text())`;
4. on `FileNotFound`, call
   `_finishStartupRead("__NOFILE__")`;
5. preserve the current fallback behavior for any other load failure;
6. remove `startupReadProc` only after its start-failure contract has an
   equivalent FileView error path.

This removes one Bash process and one cat/test pipeline whenever ScreenTime is
initialized.

### Important FileView boundary

Do not generalize this change to external-edit reload paths. The repository
documents that `FileView.setText()` keeps an internal buffer and can return
that cached content after later reloads in some workflows. ScreenTime's startup
read happens before it writes the day's state, so the startup-only replacement
does not rely on post-write disk freshness.

The current range-history reader is also separate: it batches multiple daily
files into one shell read. Replacing that with one FileView per file could
increase event-loop work and change batching/order, so it is not part of this
candidate.

### Required oracle before implementation

- current-day file exists with valid JSON;
- missing file;
- empty file;
- malformed JSON;
- service enable/disable around initialization;
- double startup-read request while one load is pending;
- first persistence after successful/missing-file initialization;
- day rollover after startup;
- FileView non-FileNotFound failure.

Compare `ready`, `_todayData`, `_dirty`, current app/session fields and
`dataChanged()` timing/order against the current Process-backed path.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without runtime
measurement.

## 2026-10-07 — Region Selector script argv research

Research-only continuation on current `dev`
`21a9deb257b113c21cd71fb8e65d8fdfe603fa1f`. No runtime/product source was
changed in this round.

Current source identities:

- `modules/regionSelector/RegionSelection.qml`:
  `05fe24280c78cfe065dc70660827dedb68f316c0`;
- `scripts/videos/record.sh`:
  `8b81656296cce08caaff413653734c32b7f4f85a`;
- `scripts/images/find-regions-venv.sh`:
  `6a3bc215839758af4c4966a8a559570029d2a134`.

### Candidate A — HIGH CONFIDENCE: start recorder script directly instead of via `bash -c`

Region Selector currently starts recording with:

```qml
snipProc.command = ["/usr/bin/bash", "-c",
    `${Directories.recordScriptPath} --region '${slurpRegion}'`]
```

or the same command plus `--sound`.

No shell composition is required by these two branches. `slurpRegion` is one
logical argument and `--sound` is a normal flag.

The repository already invokes the same script directly in three places for
stop operations:

```qml
Quickshell.execDetached([Directories.recordScriptPath, "--stop"])
```

so executable/shebang ownership is already part of the runtime contract.

Strict-lossless replacement:

```qml
[Directories.recordScriptPath, "--region", slurpRegion]
[Directories.recordScriptPath, "--region", slurpRegion, "--sound"]
```

This removes the outer `bash -c` interpreter/parser and avoids re-parsing a
shell-escaped region string.

Required oracle:

- region with positive/negative coordinates if supported;
- normal and sound recording;
- recorder already running stop path;
- record script startup failure;
- RecorderStatus quick-check scheduling;
- exact `slurpRegion` argv observed by a fixture wrapper.

### Candidate B — HIGH CONFIDENCE: invoke the content-region wrapper as interpreter+script argv

Content-region detection currently does:

```qml
["/usr/bin/bash", "-c",
 "${scriptsPath}/images/find-regions-venv.sh --image '...' --max-width ... --max-height ..."]
```

The wrapper itself is Bash and forwards `"$@"` to `find_regions.py`. No
pipeline/redirection/conditional shell source is needed at the QML call site.

Use:

```qml
[
    "/usr/bin/bash",
    Directories.scriptsPath + "/images/find-regions-venv.sh",
    "--image", root.screenshotPath,
    "--max-width", String(...),
    "--max-height", String(...)
]
```

This keeps one Bash interpreter because the wrapper is a Bash script, but
removes the extra `-c` shell source layer and all shell quoting from the QML
boundary.

A direct script exec through its shebang is also possible only if executable
mode is explicitly part of the installed/runtime contract; interpreter+script
argv is the safer strict-lossless form.

### Deliberate non-candidates in the same file

Do not mechanically remove Bash from:

- Copy: crop -> tee -> wl-copy pipeline plus timestamped filename;
- non-native Edit: crop piped to annotation tool;
- Search: crop + three-provider upload fallback + URL validation;
- OCR: tesseract language pipeline + dual clipboard fan-out;
- initial screenshot: `mkdir -p && grim`.

Those branches use real shell composition. In particular
`Directories.screenshotTemp` is not created by the shared Directories bootstrap
today, so changing the initial capture to direct grim without replacing
directory ownership would be incorrect. Moving screenshotTemp creation to
global startup would trade an interaction-time shell for extra unconditional
startup I/O and is not justified by static analysis.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without runtime
measurement.

## 2026-10-07 — Sidebar World Clock process cadence research

Research-only continuation on current `dev`
`d1811fdd4327a6120b5233f40d9442b4ba9f6a17`. No runtime/product source was
changed in this round.

Current source identities:

- sidebar widget `modules/sidebarLeft/widgets/WorldClockWidget.qml`:
  `5f9272b1aeedc3fa91b76e3a13de150bb6e61829`;
- newer background service `services/WorldClock.qml`:
  `1260b2d2ed85cf70339c2c8f366c296655dc3c9a`;
- Settings world-clock section in `modules/settings/InterfaceConfig.qml`:
  `6f9e2c644aafebc0b3b54ba34df14c272bbbe52d`.

Repository/history search found no prior optimization note for the sidebar
widget's process-per-tick clock rendering.

### Candidate A — HIGH POTENTIAL, oracle-gated: separate timezone offset refresh from display ticking

The sidebar World Clock renders each configured timezone by starting one Bash
process on every display refresh:

```qml
Timer {
    interval: root.showSeconds ? 1000 : 30000
    running: GlobalStates.sidebarLeftOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: root._refresh()
}

function _refresh() {
    ...
    const command = [
        "/usr/bin/bash", "-c",
        "for tz; do TZ=\"$tz\" printf ...; done",
        "world-clock-widget"
    ]
    ...
    clockProcess.running = true
}
```

Therefore, while the sidebar is open:

- normal minute-only mode starts about two Bash processes per minute;
- `showSeconds=true` starts roughly one Bash process every second.

The process is doing two logically different jobs at once:

1. resolving timezone/DST offset and calendar metadata;
2. advancing the displayed clock.

The newer background `WorldClock` service already demonstrates a lower-wakeup
architecture: it resolves configured timezone offsets only every five minutes
and advances display time locally from one `now` value.

Research direction for the sidebar widget:

1. split the current process-backed refresh into a sparse **timezone metadata /
   offset refresh** and a cheap in-process **display tick**;
2. refresh offset metadata at startup/timezone changes and on a conservative
   cadence comparable to the newer service;
3. when seconds are disabled, schedule a one-shot update at the next minute
   boundary rather than every 30 seconds;
4. when seconds are enabled, update the rendered second in-process from
   `Date.now()` / a shared SystemClock rather than spawning Bash every second;
5. keep the current process path as a compatibility oracle/fallback until QML
   formatting proves parity.

This can remove nearly all recurring child-process creation from the visible
sidebar clock without reducing clock precision.

### Why this is not yet a source-only strict-lossless patch

The existing Bash output carries more than UTC offset:

```text
time | %z | localized date | day-of-year | hour24
```

and the widget derives cross-day badges from the day-of-year values.
Replacing those fields with QML/JS calculations must be qualified for:

- DST transitions;
- half-hour / quarter-hour zones;
- year rollover;
- locale/date formatting parity;
- local-zone day-delta behavior;
- system clock jumps;
- timezone config changes while a process is in flight.

The process cadence reduction is therefore a strong optimization direction,
but promotion to strict-lossless implementation requires a deterministic
old-vs-new formatting oracle.

### Candidate B — MEDIUM CONFIDENCE: process-free system-timezone fast path with readlink fallback

Both the sidebar widget and its Settings section independently execute:

```text
/usr/bin/readlink /etc/localtime
```

to infer the system IANA timezone. The QML runtime already exposes `Intl`
functionality — `services/WorldClock.qml` uses
`Intl.supportedValuesOf("timeZone")`.

A conservative path is:

1. first try
   `Intl.DateTimeFormat().resolvedOptions().timeZone`;
2. accept it only when it is a non-empty IANA-like value;
3. retain the current `readlink /etc/localtime` process as fallback when Intl
   is unavailable, empty or unsuitable.

This avoids one readlink process for normal supported runtimes while preserving
the existing filesystem fallback.

Do not remove the fallback from static reasoning alone. Systems can use copied
`/etc/localtime`, unusual timezone configuration, or Qt builds with incomplete
Intl behavior.

### Existing good lifecycle retained

The sidebar clock itself is not globally startup-resident by default. It is
instantiated through `DraggableWidgetContainer.visibleWidgets`, and its periodic
timer runs only while `GlobalStates.sidebarLeftOpen`.

The Settings timezone probe also runs only while the Widgets Settings section is
active.

Therefore this finding is about **visible-feature recurring process cadence**,
not default-idle shell startup.

### Required measurement/oracle

Before implementation:

- compare old Bash records and proposed in-process records for a timezone corpus
  covering UTC, DST, non-DST, +05:30, +05:45, -03:30 and date-line zones;
- include one minute boundary, midnight, year rollover and known DST boundary
  fixtures;
- verify 12h/24h, seconds on/off, date text, offset label, dayDelta and local
  highlight;
- record child-process count for 5 minutes of sidebar-open operation in normal
  and seconds modes.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without runtime
measurement.

## 2026-10-07 — Bounded wallpaper blur surface research

Research-only continuation on current `dev`
`1e53e355d92c5fca5ca102de194dc8d96ec13ce1`. No runtime/product source was
changed in this round.

Current source identities:

- `modules/common/widgets/GlassBackground.qml`:
  `0df61709dc3ab6f1667196ca66a1c85c188dd960`;
- `modules/common/widgets/RicelinSurface.qml`:
  `a3ac4e9c35e8b680ccd6a918d907bdd36c7f5516`;
- `modules/bar/BarContent.qml`:
  `3afa7aa5e27c069ceed6c3db71d34f1e7ef445d1`;
- `modules/dock/Dock.qml`:
  `a42cff209c3f9239ad0818987af7f50a00e1f645`;
- reference `modules/common/widgets/ZzzGlassWash.qml`:
  `b7b6c1273db0523dbfbe0315ab2e1964d0baf8fc`.

Repository search currently finds roughly 25 production references to
`GlassBackground` and 8 to `RicelinSurface`, in addition to dedicated
Bar/Dock fallback paths.

### Candidate — HIGH POTENTIAL GPU/RAM: blur only the visible screen-aligned surface plus exact kernel support

The common glass implementations still use a screen-sized wallpaper item even
when the visible host is a small panel:

```qml
Image {
    x: -root.screenX
    y: -root.screenY
    width: root.screenWidth
    height: root.screenHeight
    sourceSize.width: root.screenWidth
    sourceSize.height: root.screenHeight

    layer.enabled: ...
    layer.effect: MultiEffect {
        blurEnabled: true
        blurMax: 64
        ...
    }
}
```

The parent/root then clips or masks that full-screen blurred layer back to the
small surface.

The same shape exists in `RicelinSurface`, and the non-native-blur Bar/Dock
paths create a wallpaper Image sized to the entire output even though the
visible result is a narrow strip/body.

This means the decoded wallpaper can be shared in Qt's image cache, but each
effect host can still materialize an offscreen layer/FBO proportional to the
full output.

For scale only, one RGBA8 full-output surface is approximately:

- 1920×1080×4 = 7.9 MiB;
- 2560×1440×4 = 14.1 MiB;
- 3840×2160×4 = 31.6 MiB;

before any additional blur-pyramid/intermediate storage. These are texture-size
calculations, **not measured Hadalis RSS/VRAM savings**.

Strict visual direction:

1. keep the same decoded/cached wallpaper source and exact
   `PreserveAspectCrop` screen mapping;
2. derive the visible host rectangle in screen coordinates;
3. expand it by a conservative blur-support padding sufficient for the exact
   `MultiEffect` kernel at the current scale/blur value;
4. materialize only that expanded wallpaper source region into the effect item;
5. run the same saturation/blur settings;
6. crop/mask back to the original host geometry.

The optimization is **spatial bounding**, not a lower-resolution or weaker blur.
The desired visible pixels should remain identical if the source mapping and
kernel padding are exact.

### Bar and Dock are especially clean targets

Bar and Dock know their physical edge, dimensions and output size. Their
Aurora/Angel fallback blur therefore has a simple visible strip/body whose
screen-space rectangle is explicit.

A first proof should target one horizontal Bar and one Dock edge before
generalizing the common helper. If the bounded source can reproduce those
pixels exactly, the same mapping can then be abstracted for
`GlassBackground`/`RicelinSurface`.

### Required A/B oracle

Before implementation/promotion:

- top and bottom Bar;
- all four Dock edges;
- floating panel at arbitrary x/y;
- rounded corners and asymmetric radii;
- 1× and fractional output scale;
- 16:9, ultrawide and portrait outputs;
- wallpaper source wider/narrower than output;
- blur strengths including 0 and 1;
- Angel saturation/color-strength variants;
- mask edges and exact blur support near output boundaries.

Compare:

- normalized global MAE;
- edge-band MAE;
- maximum per-channel delta;
- pixel parity on the interior host area.

Strict-lossless promotion should target 0% visible difference. If the Qt
MultiEffect kernel makes exact support difficult to bound, keep this in the
user's allowed <1% visual-deviation program and document the measured delta
rather than silently reducing fidelity.

### Existing good work not to rediscover

`ZzzGlassWash` already addresses a related but different cost: its wallpaper
decode/effect source is intentionally rendered at `_washScale = 0.5` and the
blur radius is adjusted accordingly. Do not count that existing half-resolution
optimization as a new gain.

`GlassBackground` also already disables its effect layers while the host is
hidden, which is the correct lifecycle baseline. This candidate targets the
remaining **visible-state full-screen FBO area**, not hidden residency.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without runtime
measurement.

## 2026-10-07 — Connected iRiS shadow pass research

Research-only continuation on current `dev`
`72e7a55c8033ad97699583ce496ef4b739e927f7`. No runtime/product source was
changed in this round.

Current `modules/common/perimeter/ConnectedSurfaceIrisFrame.qml`:
`e703046f2a527ad30afc1a83ccd71f5e5a78cba7`.

The current shadow path is already spatially bounded to the popup body plus
fillet/blur reach, which is good. It still consists of:

```text
ConnectedSurfaceIrisField (shadowMaskField)
    -> ShaderEffectSource (shadowTextureSource)
    -> MultiEffect blur (blurredShadow)
    -> ShaderEffectSource crop (isolatedShadow)
    -> visible shadow
```

The second capture exists only to isolate the owner-clipped subrectangle after
the blur.

### Candidate A — HIGH CONFIDENCE GPU/RAM: replace the post-blur capture with rectangular clipping

The final `isolatedShadow` does not transform the blurred pixels. It selects:

```qml
sourceItem: blurredShadow
sourceRect: Qt.rect(
    shadowPaintBounds.x - rawShadowBounds.x,
    shadowPaintBounds.y - rawShadowBounds.y,
    shadowPaintBounds.width,
    shadowPaintBounds.height)
```

and displays that rectangle at `shadowPaintBounds`.

A strict-lossless experiment can instead:

1. create a parent Item at `shadowPaintBounds`;
2. set `clip: true`;
3. render the existing `blurredShadow` inside that parent with the exact
   `rawShadowBounds - shadowPaintBounds` offset;
4. keep `shadowTextureSource`, `MultiEffect`, blur radius, mask field and
   owner clipping math unchanged;
5. remove only the second `ShaderEffectSource`.

This should preserve the same rectangular scissor while eliminating one live
capture texture/pass.

The candidate is intentionally narrow. Do not simultaneously change the SDF,
blur algorithm, shadow extent or owner-boundary rules.

### Required A/B oracle for Candidate A

Compare current and clipped-direct presentation for:

- top/bottom/left/right owners;
- popup attached at each tangent end and centered;
- joined and unjoined corners;
- fractional output scale;
- minimum and maximum supported shadow extent;
- popup animation/reveal frames;
- body near output corners;
- ownerPaintOverlap values;
- shadow disabled/enabled transitions.

Require:

- exact owner-side cutoff;
- no dark band beneath the physical Screen Edge;
- no clipped fillet shoulders;
- no one-pixel seam at fractional scale;
- 0% target visual deviation.

### Candidate B — HIGH POTENTIAL, <1% program only: analytic iRiS shadow

After Candidate A, the remaining path still rasterizes the same iRiS silhouette
a second time into `shadowMaskField`, captures it, and feeds a blur pyramid.

A later experiment may compute shadow coverage analytically from the same SDF
field, analogous to the successful analytic Screen Edge work, and composite it
in/alongside the visible field pass.

Potentially removable stages:

```text
shadowMaskField
shadowTextureSource
MultiEffect blur
```

This is **not** assumed strict-lossless. A Gaussian-like MultiEffect blur and an
analytic SDF falloff are different kernels. Treat it as a separate visual
candidate under the user's <1% deviation budget.

Required measurements:

- normalized full-frame MAE;
- edge-band MAE around the complete shadow reach;
- max channel delta;
- contact-fillet/corner crops;
- live compositor acceptance across popup motion.

Do not promote merely because static screenshots look similar.

### Existing good work not to undo

The current implementation already avoids a much worse full-output shadow
texture:

- `rawShadowBounds` is body + explicit shadow/fuse/AA reach;
- `ShaderEffectSource.sourceRect` is bounded to that region;
- physical owner pixels are clipped before and after blur.

Any optimization must preserve those ownership and ghost-band guarantees.

No whole-Hadalis GPU/RAM/FPS percentage is claimed without before/after
measurement.

## 2026-10-07 — Private bounded-cache mutation research

Research-only continuation on current `dev`
`967b6dd1131170a19fb23f13693c084a113d561b`. No runtime/product source was
changed in this round.

Current source identities:

- `services/Wallhaven.qml`:
  `ce28a24564a964df2de7748080f8f7893e788ef8`;
- `modules/background/Background.qml`:
  `29bd40236ba9579077d361fb1012d4f994ef4a3a`.

Repository/history search found no prior optimization note for the
`Wallhaven._boundedCacheInsert()` copy-on-write path.

### Candidate A — HIGH CONFIDENCE: mutate Wallhaven's private bounded caches in place

Wallhaven owns three private bounded caches:

- tag suggestions: 64 entries;
- tag counts: 256 entries;
- wallpaper tags: 256 entries.

Every insertion currently performs:

```qml
const nextCache = Object.assign({}, cache)
const nextKeys = (keys || []).slice()
...
nextCache[key] = value
nextKeys.push(key)
...
return { cache: nextCache, keys: nextKeys }
```

and the caller then reassigns both cache and key-array properties.

Repository-wide occurrence inspection shows these cache objects and key arrays
are only consumed inside `services/Wallhaven.qml`; no external QML binding,
`Connections`, change handler or public API depends on their property-change
notifications.

The cache reads are imperative:

- direct key lookup before tag-suggestion requests;
- direct key lookup before tag-count requests;
- direct key lookup before wallpaper-tag fetches.

Therefore the copy-on-write identity change is not part of the observable
contract.

Strict-lossless direction:

1. replace `_boundedCacheInsert(cache, keys, ...)` with an in-place helper;
2. preserve current LRU/key ordering exactly:
   - if key already exists, remove its first occurrence from the order list;
   - update the cache value;
   - append key at the end;
   - evict oldest keys until `length <= limit`;
3. do not reassign the cache/key-array properties merely to publish identity;
4. keep TTL checks, request queues, network ordering and response signals
   unchanged.

Why this matters structurally:

- tag-count enrichment can insert many distinct ids sequentially;
- at cache size K, every insertion currently copies O(K) object keys and O(K)
  order entries;
- filling a cache from empty therefore creates O(K²) key-copy/allocation work
  even though only one entry changes at a time;
- limits of 256 are intentionally bounded, but large enough that the avoidable
  copies can become visible JS GC pressure during search/tag enrichment.

Required oracle before implementation:

- insert into empty cache;
- refresh existing key and verify it moves to newest position;
- insert past limit and verify the exact oldest key is evicted;
- repeated same-key update;
- TTL cache hit behavior before/after;
- tag suggestion/count/detail request dedup behavior;
- prove no `...Changed` signal is currently used as a wakeup contract.

This is bookkeeping-only. Visual output and network semantics should remain
identical.

### Candidate B — LOW PRIORITY but same safe class: mutate Background wallpaper-size cache in place

The shared Background wallpaper-size cache is also private:

```qml
property var _wallpaperSizeCache: ({})
property var _wallpaperSizeCacheKeys: []
readonly property int _wallpaperSizeCacheLimit: 64
```

`cacheWallpaperSize()` currently clones both structures on every successful
ImageMagick identify result before publishing them back.

Repository-wide search finds no external reader and no binding that depends on
cache/key-array identity. The only read is an imperative lookup before deciding
whether to spawn another `magick identify`.

An in-place bounded LRU update is therefore also strict-lossless in principle.

This ranks below Wallhaven because:

- the cache is smaller (64);
- writes happen only after a wallpaper dimension probe;
- normal sessions usually touch far fewer distinct wallpapers than Wallhaven
  can touch tag ids.

Keep it grouped as a cleanup after higher-value candidates rather than
advertising it as an independent major optimization.

### Non-candidates from the same copy-on-write sweep

Do **not** generalize this rule to every `Object.assign({}, property)` pattern.

Examples deliberately retained:

- `ScreenTime._todayData` reassigns object identity so QML consumers observe
  state changes;
- `AiProviderCatalog.providerStates` is reactive public state;
- `WindowPreviewService.previewCache` has presentation consumers;
- `GlobalStates` lease maps drive derived UI state;
- `KeyboardIndicators` state maps feed reactive lock-state recomputation;
- `videoFirstFrames` intentionally publishes object identity to image/color
  consumers.

The optimization criterion is not “object clone exists”; it is “private
imperative cache with no change-notification observer”.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without runtime
measurement.

## 2026-10-07 — Calendar event bucketing research

Research-only continuation on current `dev`
`e72cb942616e5d504abe22adb93ea4258745dd3e`. No runtime/product source was
changed in this round.

Current source identities:

- `services/CalendarSync.qml`:
  `6e0b89c56eda5ee612be8438d9c20d4851a09617`;
- `modules/dashboard/DashAgenda.qml`:
  `222f16088cf07d53c0ad606d1cc8a68d3abe717c`;
- `modules/sidebarRight/calendar/CalendarWidget.qml`:
  `4b5c53bc6392e7ce5f99df8e2643029969cdb98e`;
- `modules/waffle/notificationCenter/CalendarWidget.qml`:
  `820a50373bd475e583e8ce4cd9b66515a4acba01`.

Repository/history search found no prior optimization note for the existing
`_getEventBucketsForDates()` helper or month-grid event bucketing.

### Existing partial optimization already on current dev

`CalendarSync.qml` already contains a batch helper:

```qml
function _getEventBucketsForDates(dates) {
    ...
    for (const event of root.events) {
        ...
        for (let i = 0; i < targetTimes.length; i++) {
            ...
            buckets[i].push(event)
        }
    }
    return buckets
}
```

Several consumers have already migrated to it:

- `modules/sidebarRight/events/EventsWidget.qml` builds 30 dates once and
  consumes one batch result;
- `modules/sidebarRight/CompactSidebarRightContent.qml` does the same for
  14 dates;
- `modules/background/widgets/calendar/CalendarUpcomingWidget.qml` does the
  same for 30 dates.

Do not count those current-dev migrations as new gains.

### Candidate A — HIGH CONFIDENCE: finish the batch migration for remaining upcoming views

Two current consumers still repeat one full external-event scan per date:

**DashAgenda**

```qml
for (let i = 0; i < card.lookaheadDays; i++) {
    const d = ...
    const dayEvents = CalendarSync.getEventsForDate(d) || []
    ...
}
```

with `lookaheadDays = 14`.

**Waffle notification-center Calendar**

The upcoming section repeats the same pattern for three dates.

Strict-lossless direction:

1. construct the same ordered date list currently produced by the loops;
2. call `CalendarSync._getEventBucketsForDates(dates)` once;
3. iterate buckets in the same date order;
4. keep every later filter, clone, per-day sort and five-item cap unchanged.

This is semantically safer than replacing the loops with
`CalendarSync.getUpcomingEvents(days)`. The current per-day path deliberately
duplicates a multi-day all-day event into every matching day bucket. The batch
helper preserves that exact behavior; the range helper returns each event only
once.

Required oracle:

- timed event;
- single-day all-day event;
- RFC5545 all-day event with exclusive DTEND;
- multi-day all-day event proving repeated appearance in each matching day;
- event before `now` on today;
- empty external list;
- date-range crossing month/year boundary;
- complete resulting item identity/order equality before the final existing
  sort/cap.

### Candidate B — HIGH POTENTIAL CPU: compute month-grid local/external buckets once instead of scanning both lists twice per day cell

The classic Sidebar calendar constructs a six-week `monthCells` array. For
each of up to 42 cells it calls:

```text
getEventCountForDay()
  -> Events.getEventsForDate(date)
  -> CalendarSync.getEventsForDate(date)

getSourceColorsForDay()
  -> Events.getEventsForDate(date)
  -> CalendarSync.getSourceColorsForDate(date)
       -> CalendarSync.getEventsForDate(date)
```

So one month-grid rebuild can perform:

- up to 84 full scans of the local event list;
- up to 84 full scans of the external event list;

before deriving counts/colors.

The Waffle notification-center calendar has the same shape in its day
delegates: each day exposes both `eventCount` and `sourceColors`, and those
two functions independently query the same local/external event lists.

Strict-lossless direction:

1. derive the exact ordered set of visible cell dates for the current month
   model;
2. batch external events through the existing date-bucket helper;
3. add an equivalent local-event batch helper or build the local date buckets
   once from `Events.list`;
4. for each date bucket derive:
   - local count;
   - external count;
   - whether the local primary/accent dot exists;
   - ordered unique external source colors;
5. publish one private month-cell metadata array/map;
6. let count/color bindings become O(1) lookups into that snapshot.

Hard semantic requirements:

- local `notified` filtering must match `Events.getEventsForDate()`;
- all-day local events remain visible after notification;
- external multi-day/all-day inclusion must match
  `CalendarSync.getEventsForDate()`;
- external source colors retain first-event encounter order with duplicate
  source ids removed;
- previous/current/next-month cells shown in the six-week grid must use their
  actual dates;
- `_eventsTrigger`, `_externalTrigger` and month navigation still invalidate
  the snapshot at the same observable times.

A source-only implementation should not introduce a long-lived service-wide
date cache first. The visible month has a small fixed date set, so a
widget-local snapshot provides a bounded proof surface and avoids cache
invalidation complexity.

### Why this is higher leverage than a generic cache

This is not speculative memoization. The existing widget explicitly asks for
two derived values for every visible day cell, and both values currently rescan
the same lists. A month snapshot converts repeated list-wide work into one
batch pass per source plus O(42) metadata derivation.

The gain scales with event-history size and external ICS event count while
remaining independent of rendering fidelity.

### Non-candidate

Do not rewrite `CalendarSync.getUpcomingEvents()` merely to share this month
cache. Its semantics are different from per-day buckets, especially for
multi-day all-day events. Keep range and bucket APIs separate unless a later
oracle proves a common internal index can serve both exactly.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without runtime
measurement.

## 2026-10-07 — LocalMusic folder payload duplication research

Research-only continuation on current `dev`
`06caf4884e3c25a706a8972880ac768eb5298e0a`. No runtime/product source was
changed in this round.

Current source identities:

- `services/LocalMusic.qml`:
  `88263668b48d85323a576c4c3645d9f40909f466`;
- `modules/sidebarLeft/LocalMusicView.qml`:
  `d5b1880d5a1a3796f0faefe343cf3f2f9909953a`;
- Python MPD fallback `scripts/local_music_mpd.py`:
  `0e05af4f8a308072fbed7bed96994559b66bf6f1`;
- native MPD backend `native/inir-mpdd/src/main.rs`:
  `1c63b8e5281dad2a28e88ea3cb660f7cc0c0cb88`.

Repository-wide search finds no consumer of `LocalMusic.folderCollections`
outside `services/LocalMusic.qml` itself.

### Candidate A — HIGH CONFIDENCE RAM: stop retaining the dead `folderCollections` duplicate in QML

Current snapshot application retains three large library structures:

```qml
if (includeLibrary) {
    libraryTracks = payload.tracks ?? []
    playlists = payload.playlists ?? []
    folderCollections = payload.folders ?? []
}
```

but `folderCollections` has no runtime reader.

The current Songs browser does **not** consume that pre-grouped payload.
`LocalMusicView.qml` derives folder navigation directly from
`LocalMusic.libraryTracks`:

```qml
for (const track of LocalMusic.libraryTracks) {
    const folder = root.normalizedFolder(track?.folder)
    ...
    childMap[childPath] ...
}
```

and `folderTracks(path)` likewise filters `LocalMusic.libraryTracks`
directly.

Therefore the persistent QML copy of `payload.folders` is dead state at this
baseline.

Strict-lossless direction:

1. remove the unused `folderCollections` property;
2. stop assigning `payload.folders` in `_applyPayload()`;
3. keep `libraryTracks`, `playlists`, current queue and all MPD status fields
   unchanged;
4. do not alter Songs browser folder derivation.

This immediately lets the parsed `payload.folders` subtree become collectible
after the snapshot application returns instead of being retained for the life
of the library snapshot.

### Why the duplicate can be large

The native backend constructs the folder payload by cloning each library track:

```rust
for track in &tracks {
    let folder = track_value(track, "folder");
    if !folder.is_empty() {
        folders.entry(folder)
            .or_default()
            .push(Value::Object(track.clone()));
    }
}
```

and then serializes both:

```text
tracks  -> every library track object
folders -> the same track metadata cloned into folder arrays
```

The Python fallback has the equivalent structure: it groups the already-built
track dictionaries into `folders_map` and emits a `folders` list in the
snapshot.

So the current payload carries a second representation proportional to library
size, and QML currently retains both representations even though the UI only
reads `libraryTracks`.

No exact RSS percentage is claimed because JSON parser/string sharing and QML
engine representation must be measured.

### Candidate B — HIGH POTENTIAL transport/CPU/RAM, compatibility-gated: stop generating `folders` in the snapshot

After Candidate A proves no shell consumer needs `payload.folders`, the native
and Python snapshot helpers can avoid constructing and serializing that field.

Potentially removable native work:

- BTreeMap folder grouping over every track;
- `track.clone()` into every folder bucket;
- folder-entry sorting/building;
- JSON serialization of duplicated track metadata.

Potentially removable Python fallback work is the equivalent
`folders_map/folders` construction.

This is stronger than Candidate A because it removes the duplicate before it
crosses the process boundary.

However this second step is **not assumed internal-contract-neutral** solely from
repository search. `native-dispatch mpd snapshot` has a compatibility/fallback
role and an external/manual caller could theoretically parse the JSON field.

Promotion options:

1. verify the snapshot schema is repository-private and no documented IPC/CLI
   contract promises `folders`; then remove the field from both Rust and
   Python together; or
2. if compatibility must be retained, add an explicit snapshot mode/version
   where Hadalis requests the lean payload while the legacy CLI shape remains
   available.

Do not remove the field from only one backend: Rust/Python selector parity is a
maintained contract.

### Required oracle

For Candidate A:

- load a library with nested folders;
- compare Songs root entries, child folders, counts, navigation, search,
  selection and bulk folder actions;
- compare saved playlists and playback;
- prove no QML warning/reference to `folderCollections` remains;
- compare library snapshot state before/after excluding only the dead property.

For Candidate B:

- compare Rust and Python snapshot schemas in the chosen compatibility mode;
- prove all current LocalMusic frontend tests pass;
- measure snapshot stdout byte size and QML RSS for representative libraries,
  for example small, 1k-track and larger libraries;
- preserve folder metadata on each individual `libraryTracks` record because
  the UI derives hierarchy from that field.

### Adjacent findings not promoted

- `playPath()` performs a linear library scan, but it runs on an explicit user
  play-by-path action rather than a recurring hot loop.
- `_trackForIdentity()` currently has no repository call site beyond its
  definition, so it is dead helper code, not a performance hotspot.
- playlist payloads also duplicate track objects relative to the library, but
  saved playlists are a live UI feature and can contain ordering/membership
  semantics not equivalent to simple folder derivation. Do not collapse them
  without a separate contract.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.

## 2026-10-07 — LocalMusic search preparation research

Research-only continuation on current `dev`
`dbf6739b187622b4caf992cdda49dfcf5641526d`. No runtime/product source was
changed in this round.

Current source identities:

- `modules/sidebarLeft/LocalMusicView.qml`:
  `d5b1880d5a1a3796f0faefe343cf3f2f9909953a`;
- `modules/sidebarLeft/SidebarLeftContent.qml`:
  `06c8e5aa355b97d14d606f7d152123d29a8b36ab`.

Repository/history search found no prior optimization note for LocalMusic's
per-keystroke search normalization path.

### Candidate — HIGH CONFIDENCE CPU, transient bounded RAM: prepare search haystacks once per active search session

Current search is a direct QML binding:

```qml
readonly property string query: searchField.text.trim().toLowerCase()
readonly property var filteredTracks: {
    if (!root.query) return LocalMusic.libraryTracks
    const result = []
    for (const track of LocalMusic.libraryTracks) {
        const title = String(track?.title ?? "").toLowerCase()
        const artist = String(track?.artist ?? "").toLowerCase()
        const album = String(track?.album ?? "").toLowerCase()
        const folder = String(track?.folder ?? "").toLowerCase()
        const haystack = title + " " + artist + " " + album + " " + folder
        if (haystack.includes(root.query))
            result.push(track)
    }
    return result
}
```

There is no search debounce in `LocalMusicView`; editing the text therefore
re-normalizes four metadata strings and allocates a concatenated haystack for
every library track on every query change.

For a library of N tracks and a query typed through Q intermediate text states,
the current source performs roughly O(N*Q) lowercase/concatenation work even
though track metadata did not change between keystrokes.

The view itself is not always shell-resident. `SidebarLeftContent` keeps only
the current/next/previous SwipeView loaders active, so a prepared search index
can stay local to the Music view without adding permanent shell RAM.

Strict-lossless direction:

1. keep a private transient array such as
   `[{ track, searchText }]`;
2. build it only when query transitions from empty to non-empty, or lazily on
   the first non-empty filter evaluation;
3. each `searchText` must preserve the exact current construction:
   lowercase title + single space + artist + single space + album + single space
   + folder, with the same String/null fallbacks;
4. reuse that array for subsequent query edits while
   `LocalMusic.libraryTracks` identity is unchanged;
5. invalidate immediately on `libraryTracksChanged`;
6. release the prepared array when the query becomes empty, so the extra search
   strings are not retained during ordinary browsing;
7. return original track object references exactly as current code does.

This converts later keystrokes in one search session from repeated string
normalization/allocation into one `includes()` check per already-prepared
track.

### Interaction with the previous folder-payload finding

The prior research identified a much larger dead persistent duplicate:
`LocalMusic.folderCollections`, whose payload duplicates full track metadata
and has no consumer.

If both candidates are eventually implemented:

- remove the dead full-track folder duplicate first;
- add only a compact search string/reference pair while search is active;
- clear that transient index when search ends.

That ordering should make it possible to improve search CPU without replacing
the removed persistent duplicate with another permanent per-track structure.
Do not claim a net RAM number until measured.

### Required oracle

Compare current and prepared-search results for:

- empty query;
- title, artist, album and folder matches;
- mixed-case metadata/query;
- null/missing metadata;
- whitespace-only query;
- multi-word substring queries;
- duplicate tracks;
- library rescan while query is active;
- query clear then re-enter;
- exact result object identity/order.

The candidate must not add fuzzy matching, tokenization, Unicode normalization,
ranking or debounce. Those would change current search semantics.

### Adjacent collection work not promoted

`buildSongEntries()` also scans `libraryTracks` to derive the current folder
view, and `folderTracks()/resolveSelectedTracks()` perform additional scans on
explicit folder/selection operations. A compact folder index could reduce those
costs, but it adds more retained structure and changes a wider set of bulk
selection/navigation contracts. Measure large-library folder-navigation latency
before expanding this candidate into a full music-library index.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without runtime
measurement.

## 2026-10-07 — WorldClock timezone catalog research

Research-only continuation on current `dev`
`0d46417c9da64a4f548b6195099cc854182214b0`. No runtime/product source was
changed in this round.

Current `services/WorldClock.qml`:
`1260b2d2ed85cf70339c2c8f366c296655dc3c9a`.

Repository/history search found no prior optimization note for the full
timezone catalog/model.

### Candidate — HIGH CONFIDENCE lifecycle/RAM: materialize the full timezone picker model only when a picker needs it

The runtime clock needs only the configured timezone set, normally four values:

```qml
readonly property var timezones: {
    const configured =
        Config.options?.background?.widgets?.worldClock?.timezones
    ...
}
```

but every time the WorldClock singleton is materialized it also eagerly builds
the full IANA picker catalog:

```qml
readonly property var timezoneList: {
    if (typeof Intl !== "undefined"
            && typeof Intl.supportedValuesOf === "function")
        return Intl.supportedValuesOf("timeZone")
    return root.fallbackTimezones
}

readonly property var comboModel: root.timezoneList.map(tz => ({
    label: root.labelFor(tz),
    tz: tz,
    icon: ""
}))
```

Repository-wide occurrence inspection shows:

- `timezoneList` has no consumer except `comboModel`;
- `comboModel` is consumed only by:
  - the background World Clock edit-popover timezone pickers;
  - Desktop Widgets Settings timezone pickers;
- normal clock rendering reads `WorldClock.entries`, `timezones`,
  `offsetsMinutes` and `now`, not the full picker model.

Therefore the catalog is settings/editor data, not runtime clock state.

Strict-lossless direction:

1. replace eager `timezoneList/comboModel` evaluation with an idempotent lazy
   `ensureTimezoneCatalog()`;
2. keep an initially empty/private catalog state;
3. call the ensure function from each picker owner before the picker becomes
   visible/materialized;
4. compute `Intl.supportedValuesOf("timeZone")` once per WorldClock singleton;
5. build labels once and reuse the same model for all four pickers;
6. retain the exact fallback timezone list and `labelFor()` formatting;
7. keep currently selected timezone values independent of catalog readiness.

The edit-popover is declared through `editPopoverContent: Component`, so its
picker subtree is not required for ordinary widget rendering. Settings can
explicitly prime the catalog when its timezone controls are loaded.

### Expected structural saving

When WorldClock is used only as a clock:

- no full IANA timezone array is materialized;
- no second array of `{label,tz,icon}` objects is allocated;
- no label splitting/replacement is performed for every supported timezone.

This is not a default-shell saving when WorldClock never materializes, but it
removes unnecessary CPU/RAM from every session that displays the clock without
opening its timezone editor.

### Required oracle

- Intl supported-values path;
- fallback path when `Intl.supportedValuesOf` is unavailable/throws;
- normal clock rendering before catalog creation;
- open widget edit popover for the first time;
- open Desktop Widgets Settings first instead;
- open both surfaces in either order;
- selected index for all configured timezones;
- custom/configured timezone not present in the catalog;
- change timezone and verify current clock state/offset refresh exactly as
  before.

No visual change is expected outside the moment the picker is intentionally
opened; the picker must still present the complete model on its first visible
frame.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.

## 2026-10-07 — Background active-workspace occupancy research

Research-only continuation on current `dev`
`0f3507b160bdd6f57c94a38cb8ceba6eeacec74b`. No runtime/product source was
changed in this round.

Current source identities:

- `services/NiriService.qml`:
  `4c8194493fd380bf0ad8c51bc62990ad0c232738`;
- `modules/background/Background.qml`:
  `29bd40236ba9579077d361fb1012d4f994ef4a3a`;
- `modules/waffle/background/WaffleBackground.qml`:
  `6e9bcbdf8daef77c9f8169ed998c44bc72b94fa6`.

Repository/history search found no prior optimization note for the duplicated
per-output `hasWindowsOnCurrentWorkspace` scan.

### Candidate A — HIGH CONFIDENCE: centralize active-workspace occupancy for Niri

Both Classic/ii Background and Waffle Background independently bind:

```qml
const allWs = Object.values(NiriService.workspaces)
const currentWs = allWs.find(ws =>
    ws.output === outputName && ws.is_active)
return NiriService.windows.some(w =>
    w.workspace_id === currentWs.id)
```

This expression exists once per output instance. Any change to
`NiriService.windows` or `NiriService.workspaces` can therefore make every
background instance repeat:

- `Object.values(workspaces)`;
- a scan to locate the active workspace for its output;
- a scan of the complete Niri window list to test occupancy.

With M outputs, W workspaces and N windows, the source shape is approximately
O(M * (W + N)) per relevant publication, duplicated independently by the two
panel families' implementations.

The requested visual result is only one boolean per output:
“does this output's currently active Niri workspace contain at least one
window?”

Strict-lossless direction:

1. derive once in `NiriService` (or one shared compositor helper) an
   `activeWorkspaceIdByOutput` map from the authoritative workspace snapshot;
2. derive once an `occupiedWorkspaceIds` Set/map from the authoritative
   published window snapshot;
3. expose an imperative helper such as
   `activeWorkspaceHasWindows(outputName)`;
4. ensure the helper's reactive invalidation is backed by a small revision or
   replaced derived object whenever either source snapshot changes;
5. switch both Background families to the same helper;
6. retain `false` for unknown output, no active workspace, empty workspace
   map, non-Niri compositor and exception/fail-closed cases.

A local-only variant can compute one shared output->bool map at the Background
root and let every per-screen delegate read from it. Centralizing in
`NiriService` has more leverage because `modules/bar/Workspaces.qml` already
builds its own occupied-workspace Set and could reuse the same authoritative
index in a later, separately qualified change.

Do not derive this from foreign toplevels. Niri's own `windows` snapshot is the
authority used by current code, including workspace ids and stale-handle
behavior.

### Required oracle

- zero windows;
- zero workspaces;
- one and multiple outputs;
- active workspace changes on one output;
- window open/close/move between workspaces;
- window move across outputs;
- workspace id/index/output topology changes;
- focused-window-only changes that must not alter occupancy;
- multiple windows on one workspace;
- output removed/re-added;
- compare both Classic/ii and Waffle `hasWindowsOnCurrentWorkspace`,
  `focusWindowsPresent` and resulting blur-progress transitions.

No visual change is expected; only repeated collection scans are removed.

### Candidate B — HIGH CONFIDENCE but low priority: mutate the private wallpaper-size LRU in place

Classic `Background.qml` keeps a shared bounded cache for
`magick identify` results:

```qml
property var _wallpaperSizeCache: ({})
property var _wallpaperSizeCacheKeys: []
readonly property int _wallpaperSizeCacheLimit: 64
```

On every successful metrics lookup it currently copies both structures:

```qml
const cache = Object.assign({}, root._wallpaperSizeCache)
const keys = root._wallpaperSizeCacheKeys.slice()
...
root._wallpaperSizeCache = cache
root._wallpaperSizeCacheKeys = keys
```

Repository-wide occurrence inspection shows:

- both properties are private to this Background root;
- there is no `...Changed` handler or binding depending on their reassignment;
- the cache is read imperatively by `wallpaperSizeDebounce`;
- the key list is used only by `cacheWallpaperSize()` itself for LRU order.

Therefore direct mutation of the private object/array preserves the current
lookup/LRU contract while avoiding object and array copies on each insertion.

Required oracle:

- first insert;
- same-path refresh moves key to newest position;
- eviction at 64 -> 65 entries;
- cache hit returns identical width/height;
- rapid wallpaper switching while one metrics process is active;
- stale metrics result for a no-longer-current wallpaper remains ignored as
  today.

This is intentionally ranked below Candidate A because insertions are
infrequent and the cache is capped at 64 entries.

### Non-candidate checked in the same pass

`ScreenTime._todayData = Object.assign({}, _todayData)` cannot be removed as a
pure private-map optimization. `ScreenTime.todayData` is publicly bound by the
Waffle Action Center main page, and the reassignment currently supplies the
property-notify after nested usage data is mutated. The service also emits a
separate `dataChanged()` signal for other consumers, but not every
`todayData` consumer listens to that signal. Any future in-place mutation must
first replace that notification contract explicitly.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without runtime
measurement.

## 2026-10-07 — Hyprland Background collection-pass research

Research-only continuation on current `dev`
`5335ffef47622d598b0ecea2c197c12bd56b7535`. No runtime/product source was
changed in this round.

Current source identities:

- `modules/background/Background.qml`:
  `29bd40236ba9579077d361fb1012d4f994ef4a3a`;
- `modules/screenCorners/ScreenCorners.qml`:
  `3fc43bf7e1b7ec63fae6d27f55a5dd48fbb4cb00`.

Repository/history search found no prior optimization note for the Hyprland
Background window-range pipeline or the duplicated fullscreen
`filter().filter()[0]` path.

### Candidate A — HIGH CONFIDENCE: replace Background's filter+sort window range with one summary pass

Classic Background currently builds:

```qml
property list<var> relevantWindows:
    HyprlandData.windowList
        .filter(win => win.monitor == monitor?.id
            && win.workspace.id >= 0)
        .sort((a, b) => a.workspace.id - b.workspace.id)

property int firstWorkspaceId:
    relevantWindows[0]?.workspace.id || 1

property int lastWorkspaceId:
    relevantWindows[relevantWindows.length - 1]?.workspace.id || 10
```

and later tests current-workspace occupancy with:

```qml
relevantWindows.some(w =>
    w.workspace.id === monitor.activeWorkspace.id)
```

Repository-wide occurrence inspection shows `relevantWindows` is used only
for those three purposes.

The full sorted array is therefore stronger state than the consumer needs.
A single reactive pass over `HyprlandData.windowList` can derive:

- minimum eligible workspace id on this monitor;
- maximum eligible workspace id on this monitor;
- whether the monitor's current active workspace contains a window.

Strict-lossless direction:

```text
summary = { first, last, hasCurrent }
for each window:
    if monitor differs -> continue
    if workspace.id < 0 -> continue
    update min/max
    if workspace.id == activeWorkspace.id -> hasCurrent = true
```

Then preserve the current fallback semantics exactly:

- `firstWorkspaceId = summary.first || 1`;
- `lastWorkspaceId = summary.last || 10`.

Using `||` rather than a nullish fallback matters because the existing source
would treat workspace id 0 as falsy for first/last defaults even though the
filter permits id 0. Do not silently “fix” that edge case in an optimization
patch.

Expected structural change per relevant Hyprland update:

- remove one filtered array allocation;
- remove one O(N log N) sort;
- remove a later O(N) `some()`;
- replace with one O(N) scan per output.

This is strictly stronger than merely replacing `filter` with `find`.

### Candidate B — HIGH CONFIDENCE: replace nested fullscreen filters with one find/some pass

Classic Background and ScreenCorners both currently construct:

```qml
workspacesForMonitor =
    Hyprland.workspaces.values.filter(workspace =>
        workspace.monitor
        && workspace.monitor.name == monitor.name)

activeWorkspaceWithFullscreen =
    workspacesForMonitor.filter(workspace =>
        workspace.toplevels.values.filter(window =>
            window.wayland?.fullscreen)[0] != undefined
        && workspace.active)[0]
```

The requested answer is only “does this monitor's active workspace contain a
fullscreen Wayland window?”

Equivalent allocation-free shape:

```qml
Hyprland.workspaces.values.find(workspace =>
    workspace.monitor
    && workspace.monitor.name == monitor.name
    && workspace.active
    && workspace.toplevels.values.some(window =>
        window.wayland?.fullscreen))
```

or a small shared helper returning the boolean directly.

Strict-lossless requirements:

- preserve loose monitor-name equality if current source relies on it;
- preserve the requirement that the workspace itself is active;
- preserve Wayland-only fullscreen detection through
  `window.wayland?.fullscreen`;
- return false/undefined equivalently when monitor/workspace/toplevel data is
  absent;
- do not change the Niri path, which already delegates fullscreen authority to
  `GameMode.hasFullscreenOnOutput()`.

Because the same allocation pattern exists in both Background and
ScreenCorners, one shared Hyprland helper is preferable if it does not create a
new lifecycle dependency. Otherwise make the same local semantic replacement in
both files and cover them with one oracle.

### Required oracle

For Candidates A/B:

- one/multiple Hyprland outputs;
- no windows;
- windows with negative/special workspace ids;
- workspace id 0;
- multiple workspace ids out of order in `windowList`;
- current workspace empty vs occupied;
- active workspace changes without window-list order change;
- monitor migration;
- active fullscreen Wayland window;
- inactive workspace fullscreen window;
- XWayland/non-Wayland window with no `wayland.fullscreen`;
- fullscreen exit/enter;
- compare Background visibility, first/last workspace range and
  ScreenCorners fullscreen state exactly.

### Priority

Candidate A is the more meaningful CPU/allocation saving because the current
sort can run whenever the Hyprland window list changes. Candidate B is a clean
secondary allocation reduction and should be bundled only if its regression
oracle is already being added.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.

## 2026-10-07 — GameMode fullscreen snapshot cache research

Research-only continuation on current `dev`
`b61a5886f19db7b532fcf28d483fb2fb520ee728`. No runtime/product source was
changed in this round.

Current `services/GameMode.qml`:
`692f3e200b7c46835f44f152c88f231e2d0bd2b5`.

### Candidate — HIGH CONFIDENCE: derive fullscreen state once per Niri snapshot and make all per-output queries O(1)

GameMode currently evaluates the same published Niri state through several
independent full-list scans:

```qml
readonly property bool hasAnyFullscreenWindow:
    checkAnyFullscreenWindow()

readonly property bool hasVisibleFullscreenWindow: {
    for (let i = 0; i < NiriService.windows.length; ++i) {
        if (!isWindowFullscreen(NiriService.windows[i])) continue
        const ws = NiriService.workspaces[...]
        if (ws?.is_active) return true
    }
}

function hasFullscreenOnOutput(outputName): bool {
    for (let i = 0; i < NiriService.windows.length; ++i) {
        const ws = NiriService.workspaces?.[w.workspace_id]
        if (!(ws?.is_active ?? false)) continue
        if (outputName.length > 0 && ws.output !== outputName) continue
        if (_isWindowFullscreenWithWorkspace(w, ws, true)) return true
    }
}
```

`hasFullscreenOnOutput()` is consumed by many simultaneously resident
surfaces/services, including:

- Classic Bar;
- Screen Edges;
- Screen Corners;
- Classic Background;
- Waffle Background;
- SidebarHost;
- Abyss Perimeter/reservation logic;
- WidgetPowerManager;
- Family work-area guard paths.

Each binding can therefore rescan the same `NiriService.windows` snapshot after
one window/layout/workspace publication.

Strict-lossless direction:

derive one private snapshot object from exactly the same current sources:

```text
{
    any: bool,
    visible: bool,
    activeOutputs: { outputName: true, ... }
}
```

For every Niri window in source order:

1. resolve its workspace from `NiriService.workspaces[workspace_id]`;
2. evaluate fullscreen with the existing
   `_isWindowFullscreenWithWorkspace()` logic;
3. set `any` when any window is fullscreen;
4. only when the workspace exists and is active, set `visible`;
5. for an active workspace with a known output, set
   `activeOutputs[ws.output] = true`.

Then:

- `hasAnyFullscreenWindow` reads `snapshot.any`;
- `hasVisibleFullscreenWindow` reads `snapshot.visible`;
- `hasFullscreenOnOutput("")` returns `snapshot.visible`, matching today's
  empty-name semantics;
- `hasFullscreenOnOutput(name)` becomes an O(1) activeOutputs lookup.

The snapshot must retain the current distinction between these cases:

- `checkAnyFullscreenWindow()` may report true even when workspace metadata is
  temporarily missing, because `isWindowFullscreen()` can use the existing
  single-output fallback;
- visible/per-output state currently requires a resolved active workspace and
  therefore stays false when that workspace record is missing.

Do not accidentally promote the single-output fallback into visible/per-output
ownership.

### Focused-window auto-detection remains a separate path

`_doCheckFullscreen()` currently finds the focused window from
`NiriService.windows` (with `activeWindow` fallback) because focus flags and
layout events can arrive independently. Preserve that lookup initially.

The optimization here is to make the secondary
`|| root.hasVisibleFullscreenWindow` check O(1), not to redesign focus
authority in the same patch.

### Relationship to older GameMode research

Historical optimization notes proposed a `liveWindows`-style behavioral view
to improve freshness/correctness relative to Niri's batched presentation list.
That is a different question.

This candidate is valid even if the source remains the current published
`NiriService.windows`: it removes duplicate scans of whichever authoritative
snapshot GameMode is currently specified to use. If a future correctness patch
switches GameMode to a fresher source, build the same derived snapshot over that
new source rather than discarding this optimization shape.

### Required oracle

Compare current and cached behavior for:

- no outputs/windows;
- single-output workspace metadata temporarily missing;
- one/multiple outputs;
- fullscreen on inactive workspace (any=true, visible=false);
- fullscreen on active workspace;
- fullscreen isolated to one output;
- two outputs fullscreen simultaneously;
- `window.is_fullscreen === true` direct path;
- size-heuristic fullscreen path;
- tolerance ±2 px;
- layout update before workspace update;
- output geometry update;
- workspace active/inactive transition;
- fullscreen exit;
- empty-string `hasFullscreenOnOutput("")`;
- all existing Bar/ScreenEdge/Sidebar/Abyss/WidgetPowerManager consumers.

Signal/binding frequency should stay source-driven by the same
windows/workspaces/outputs inputs; do not add a polling timer.

### Expected structural saving

Instead of O(C * N) scans for C fullscreen-query consumers and N windows, the
service performs one O(N) derivation per relevant Niri snapshot and O(1)
lookups thereafter.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.

## 2026-10-07 — DesktopItems snapshot research

Research-only continuation on current `dev`
`29b0fcea1b229611f9039d0b61d3557d536a69ce`. No runtime/product source was
changed in this round.

Current source identities:

- `services/DesktopItems.qml`:
  `415be57a15cfe34f373c8d2290e481bf978643ae`;
- `modules/background/desktopItems/DesktopItemDelegate.qml`:
  `88000b9820fb3b68cee5a007cec6a698b50948ba`.

### Candidate A — HIGH CONFIDENCE: publish one cloned item-list snapshot per items revision instead of cloning all items once per output

`DesktopItems.items` is stored as an id->record object. `listItems()` currently
builds a fresh array and a fresh object for every item on every call:

```qml
function listItems(): list<var> {
    return Object.keys(root.items).map(itemId =>
        Object.assign({ id: itemId }, root.items[itemId]))
}
```

Classic Background renders desktop items per output through:

```qml
model: widgetCanvas._desktopItemsForOutput(outputName)
```

and that helper begins with:

```qml
DesktopItems.listItems().filter(...)
```

Therefore every output delegate rebuilds/clones the complete desktop-item set
before retaining only its output subset. With M outputs and I items, one
DesktopItems revision can allocate approximately M * I cloned records before
the per-output Repeater models settle.

The delegate does not mutate `itemData` directly. Its writes are routed through
`DesktopItems.update/remove/repair`, including drag/drop persistence,
rename/lock/layer changes and cross-output moves.

Strict-lossless direction:

1. expose a derived read snapshot owned by `DesktopItems`, rebuilt only when
   `root.items` changes:
   `[{id, ...record}, ...]`;
2. keep the existing imperative `listItems()` API if callers are expected to
   receive defensive copies;
3. let Background consume the shared derived snapshot instead of calling
   `listItems()` once per output;
4. perform only the per-output filter in Background;
5. keep orphaned-output fallback semantics unchanged: an item whose saved output
   is no longer connected is still shown only on the focused fallback output.

A later extension could publish output buckets too, but that mixes screen/focus
state into the persistence service and is unnecessary for the first
optimization.

### Snapshot identity boundary

The derived snapshot may share record objects among read-only presentation
consumers only if no consumer mutates them. Current DesktopItemDelegate reads
fields and sends explicit patches back to the service; it does not assign into
`itemData`.

If a future caller needs a mutable defensive copy, it should keep using
`get()/listItems()` rather than receiving the presentation snapshot.

### Required oracle

- zero items;
- one/many outputs;
- create/update/remove/undo;
- rename/lock/layer changes;
- drag persistence;
- move item across outputs;
- disconnected/stale output name fallback to focused output;
- invalid-record preservation remains storage-only and never leaks into the
  visible snapshot;
- Repeater model identity/order after each `items` reassignment;
- verify no delegate-side mutation of the shared snapshot.

### Candidate B — MEASURE FIRST: `arrangePosition()` builds and sorts the full grid candidate set

When grid snap is enabled, `DesktopItems.arrangePosition()` currently:

1. builds every candidate grid cell in the work area;
2. stores `{x,y,distance}` objects;
3. sorts the complete list by squared distance, then y, then x;
4. tests candidates in order until the first collision-free position.

This is not a pointer-frame hot path. Current delegate usage calls it on:

- component position reconciliation;
- work-area/grid changes;
- drag release;
- cross-output move.

The candidate count is also bounded by a pitch based on the desktop-item
footprint, not the raw grid size. Therefore do not rewrite this algorithm from
static complexity alone.

If startup/edit traces show it matters with large item counts or 4K/8K work
areas, then research an exact-order nearest-free search or precomputed candidate
offset strategy. Any replacement must preserve the current ordering tuple
`(distance, y, x)`, collision rectangle semantics and anchor fallback exactly.

### Adjacent process note

Every non-application/non-http desktop item also performs a bounded
`test -e` target probe on component completion/target change. This is real
child-process fan-out for large file/folder desktop collections, but the repo
currently has no in-process filesystem existence API with proven identical path
semantics. Keep it measurement-gated rather than replacing it with an
unqualified QML/FileView approximation.

No whole-Hadalis CPU/RAM/GPU/FPS percentage is claimed without measurement.

