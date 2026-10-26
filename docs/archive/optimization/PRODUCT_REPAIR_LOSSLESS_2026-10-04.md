# Abyss widget editing, Settings, Waves and lossless Aqua — 2026-10-04

> **ARCHIVED IMPLEMENTATION JOURNAL — 2026-10-07.** The scoped repair/lossless work recorded here is historical. Any still-open product acceptance/work is routed through current `to-do/` state and retained evidence, not this document.

The maintainer requested four product changes: connect desktop Edit Widget
controls to Abyss and avoid nearby widgets; reconcile the forty reported local
validation failures and duplicate Settings tabs; begin lossless optimization;
and restrain the named Waves presets. The follow-up adds notification lifetime
repair and free-position Settings. Automation remains excluded.

## Product behavior

The original desktop controls now use the existing Abyss body, field painting
and native input region. No additional popup window or shader pass is added.
Placement considers bottom, top, left and right edges, available positions and
expanded widget footprints. The selected widget receives extra clearance
priority; widgets themselves retain their geometry. Crowded outputs use the
least overlapping bounded candidate. Vertical rails keep icons upright;
narrow outputs allow scrolling to reach every control, including Done.

Grid snap, size, widget toggles, manager, Settings and Done keep their original
callbacks. Registry ownership is output-specific and identity-checked on
retirement. Semantic close releases input immediately. Waffle restores the
existing horizontal toolbar. Dashboard editing also reserves its actual
toolbar margins so controls stay within content and input bounds.

Notification hover previously destroyed the timeout timer, leaving popups
visible indefinitely. Hover now pauses the remaining lifetime and resumes it
when the final output leaves. Delegate retirement also releases its hold;
notifications arriving in an already hovered group receive the same pause.
Expiry, explicit dismissal and mark-read retire the timer. Persistent and
critical notifications retain their existing lifetime policy.

Abyss notification Settings now embeds the existing free-position editor,
including edge/custom placement, output-specific values and reset. It writes
the canonical Abyss position store used by the perimeter. The old Anchor and
margin controls remain available to the supported non-Abyss presentation.
The existing **Ignore app timeout** setting is now visible beside Timeout:
users can choose whether an app's requested lifetime or their configured
lifetime takes precedence. Existing saved settings are not changed silently.

Settings merges repeated headings after trimming and case normalization while
retaining saved order, hidden pages and stable page slots. The two different
destinations previously named Modules are now **Shell & interface** and **Bar
modules**. Shell & interface links to the existing Bar modules controls;
controls are not copied into another page. The focused Waves and Popups pages,
search/deep links and Waffle navigation remain supported.

The named Waves preset change is intentional visual tuning, separate from
lossless optimization. Balanced equals every coefficient of the former Calm.
Custom retains explicit values and the former default coefficients.

| Preset | Previous amplitude | Current amplitude |
| --- | ---: | ---: |
| Calm | 0.12 | 0.035 |
| Balanced | 0.8 | 0.12 |
| Fluid | 2 | 0.32 |
| Deep | 4 | 0.65 |

Damping, propagation, tension, rebound and corner response are also restrained.
The solver's stress tests retain their former demanding coefficients through
explicit Custom inputs rather than weakening their workloads.

## Strict lossless reduction

Aqua's swept-segment obstacle check replaces its private lower/upper bound
arrays with scalar values. All four geometry reads still occur before either
axis test. Arithmetic, tolerances, early exits, thrown-read behavior, path
results and Qt dependency/NOTIFY behavior remain equivalent.

| Scope | Temporary arrays before → after | Scoped reduction |
| --- | --- | ---: |
| Aqua segment check, per visited obstacle | 2 → 0 | 100% |
| Previously implemented Abyss Sidebar obstacle publication | 3 → 1 | 66.7% |
| Previously implemented Abyss Dock combination, maximum | 4 → 2 | 50% |

These percentages count specific temporary array objects. Whole-application
CPU, GPU, RAM, FPS and latency savings have not been measured. They must not be
inferred by adding the percentages or treating allocation counts as timings.

The Aqua native QV4 oracle covers 3,821 result/error/read-order cases including
120 path comparisons, plus 13 reactive Qt steps. The general scene regression
covers 3,345 cases and 14 paths. Earlier Abyss allocation parity evidence is
retained; a new canonical run verifies the integrated source independently.

## Reconciliation of the reported forty failures

Original frozen source: `901e98864157211dd8a857e320efc5c1ac041d20` —
372 PASS, 40 FAIL, 2 SKIP. The
[original summary](../../aqua-visual/abyss-water-20261004/canonical-summary.txt)
and its evidence remain unchanged.

| Original failures | Disposition |
| --- | --- |
| 3 OSD/editor/Dashboard runtime checks | Writable OSD kind, isolated preview selection, mature OSD feature access and Dashboard margin/draft-boundary fixes |
| 27 other regression checks | Current mature contracts and valid fixtures; no product rollback to satisfy stale spellings |
| 1 documentation check | Research citations distinguished from active manuals; active paths, links, IPC and localization checks remain enforced |
| 5 MegaQML helpers/history gate | Explicit phase-helper/frozen-evidence exclusions; standalone argumentless calls cannot prove phase acceptance |
| 3 MegaQML phase runners | Explicit manual runners requiring SHA/output and potentially publishing evidence |
| 1 installed Desktop repair check | Explicit live session/automation acceptance, outside this authorized run |

Native fixtures now use actual mature owner interfaces and clipping regions.
The corner fixture explicitly tests Niri Overview priority instead of assuming
the owner's top-left corner is free. Anti-flashbang retains a production
screencopy probe and uses actual captured Qt white/dark pixels for a controlled
sensitivity oracle, independent of other desktop windows.

## Acceptance

The first clean canonical run at
`151e86a5b26e094982a329d34216afad702907e8` completed with **407 PASS,
1 FAIL, 11 SKIP** (408 checks), with strict Qt 6.11.2 parsing PASS. All
31 active checks from the original forty failures passed. The remaining new
failure was an anti-flashbang fixture that assumed the owner's entire output
stayed white; the controlled real-Qt-pixel fixture repair is `e7952384f`.
The failed run remains recorded in its
[summary](../../evidence/abyss-product/20261004-151e86a5b/canonical-summary.txt)
and [validation record](../../evidence/abyss-product/20261004-151e86a5b/canonical-validation.json).

A fresh clean canonical run at
`e6d6f9083be1e251c958e7c9fa6228fcd60bc9c7` includes the brightness fixture
repair, both notification repairs and concurrent Aqua development.
It completed with **415 PASS, 0 FAIL, 11 SKIP**, including strict Qt 6.11.2
parsing PASS. The exact result is retained in the
[summary](../../evidence/abyss-product/20261004-e6d6f9083/canonical-summary.txt),
[validation record](../../evidence/abyss-product/20261004-e6d6f9083/canonical-validation.json)
and [complete log](../../evidence/abyss-product/20261004-e6d6f9083/canonical-run.txt).
The [forty-failure reconciliation](../../evidence/abyss-product/20261004-e6d6f9083/original-failure-reconciliation.json)
records every active PASS and every explicit phase/manual exclusion.
Nix remains deferred/non-blocking. This PASS applies to the printed source;
later concurrent Aqua changes and subsequent product requests require their
own qualification.

The notification regressions use private D-Bus/XDG fixtures and real native
notification ingress. They cover configured/app lifetimes, two-output hover,
remaining-time resume, arriving notifications, delegate destruction, history,
critical/persistent policy and transient expiry. The Settings fixture covers
the actual free-position editor, per-output storage/reset, timeout preference
and family switching. Successful exact-SHA canonical output is retained in the
[focused manifest](../../evidence/abyss-product/20261004-e6d6f9083/canonical-focused-outputs.json).

Focused native editor interaction passed four edges, narrow-output reachability,
manager/grid callbacks, input release and family/output lifecycle. Its captured
images use an isolated fixture theme and do not represent the owner's installed
desktop palette. The four captures are
[bottom](../../evidence/abyss-product/20261004-151e86a5b/bottom.png),
[top](../../evidence/abyss-product/20261004-151e86a5b/top.png),
[left](../../evidence/abyss-product/20261004-151e86a5b/left.png) and
[right](../../evidence/abyss-product/20261004-151e86a5b/right.png).
Full owner-session acceptance for multi-output, hotplug,
suspend, scaling, fullscreen and input/focus remains **HOLD / NOT_COMPLETE**.

No automation files, jobs, state, profiles or services were changed or controlled.
Concurrent Aqua work and unrelated MEGA evidence were preserved. The active
entry point remains [to-do/cloud-bot/OPTIMIZATION.md](../../../to-do/cloud-bot/OPTIMIZATION.md).


## Maintainer stop checkpoint — 2026-10-05

The maintainer stopped implementation and requested a pushed repository note.
Niri/Quickshell reload success now uses normal Notifications at source commit
`159c4f79203c352f53d09747c75896b75975a143`; focused native ingress/hover/expiry,
transient removal, silent reload and error-path checks passed. It was pushed
through `069d148f799f795281f3d37614a49e5fe6893a71`. Its new canonical run is pending.

The external Dashboard editor is **NOT_COMPLETE**. Its fourteen-file draft,
exact base/file hashes, partial native passes and failed composed fixture are
preserved in the [stop checkpoint](../../evidence/abyss-product/20261005-dashboard-editor-draft/README.md).
The draft was archived out of the runtime source tree. Resume only after a new
maintainer instruction, refetch/reconcile current `dev`, finish field/narrow
input/lifecycle and rendering checks, and validate a new committed SHA.
Further related bug finding/lossless work and desktop acceptance remain pending.
The prior canonical PASS above does not qualify this later candidate.

No automation source or jobs were authored or controlled by this continuation.
Concurrent owner automation and Cloud Storage commits were integrated intact;
this integration is separate from product changes described here.
