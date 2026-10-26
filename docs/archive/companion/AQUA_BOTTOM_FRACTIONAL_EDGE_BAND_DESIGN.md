> Historical snapshot archived on 2026-10-10 from Hadalis `8b2ed6f0a1fccddade206f0060ed19d19337a5da`. This document does not assign active work or prove that pending acceptance is complete. Use [the current categorized tasks](../../../to-do/README.md).

> Companion implementation and remaining product tasks belong to [Alis-Companion](https://github.com/llocphann/Alis-Companion). Original Hadalis receipts keep their original scope.

<!-- hadalis-doc-kind: research -->

# Aqua original BOTTOM fractional virtual panel-band diagnostic

**Status:** Source staged on `dev`; fake-only and owner-local actual Qt are NOT yet verified.

## What the real owner-local checkpoint establishes

The owner reported original frozen full-scene BOTTOM×1.5 at source SHA
`74c016de533da681bfbf10b9c38a154a4aa7359a`: margin0 has exterior
paint and a virtual boundary-contact band, while margin1 eliminates the
thresholded exterior AND loses that specific synthetic two-row band.
Margins2/3 also lack the band. These are locally reported original Qt
samples, not a GitHub-published report or actual panel screenshot.
The earlier independent 32-frame margin0/margin1 spring A/B does not
prove virtual band continuity under animation.

## Source geometry and falsifiable candidates

Original `AbyssCompanion.qml` blob
`b5b01835a282458eba0d0268396ae2c350d919d2` contains two original
host children: a centered rotated procedural body and the separately
bottom-anchored rounded 58×10 cradle. In the original private source-pinned
320×300, BOTTOM×1.5 host, the logical host bottom maps to raster y=222.5;
original cradle bottom with *private-only* bottomMargin `m` maps to
`222.5 − 1.5m`. Values 0,.25,.5,.75,1 map to 222.5, 222.125, 221.75,
221.375, 221.0. At threshold24, original inside edge raster row221
and support row220, a fractional candidate may show **both** absence of
exterior alpha and retention of at least three contiguous central-x
pixels in BOTH rows. This is a hypothesis: actual Qt rasterization may
yield no such margin. The method cannot determine real panel pixels or
perceived connection.

## Private probe contracts

New files pinned independently:

- `scripts/aqua-fixtures/paint-bottom-fractional-band/shell.qml`,
  blob `9203e9bf935c0a0ab995380dadf6a6ff27cc004d`.
- `scripts/aqua-private-bottom-fractional-band-model.py`,
  blob `f1c91fc2742b21a1cee9cb2911be7c614e8aeee5`.
- `scripts/aqua-manual-private-bottom-fractional-band.py`,
  blob `9c8e30eeef28d791966748bdc664e7ff204ccf67`.
- `scripts/test-aqua-private-bottom-fractional-band-contract.py`,
  blob `d3f4a7c1dd1e5a230c012ab33fa8dbb79b9a67ce`.

An existing qualified strict source guard and the prior unchanged bounded
RGBA8 parser are re-used recursively. The fixture contains ONE original
full companion at a frozen invariant original body pose in ONE offscreen
Qt process. Only the temporary cradle anchors.bottomMargin varies; each
capture is strictly staged, uniquely owned and private. The runner
requires current clean trusted `dev`, source-pin and original positive
controls; the fake-only test checks synthetic variants and fail-closed
negative states. Any real image/log remains outside the source checkout.
No default-on Aqua, production QML, Region, native Rust, or stable change.

With the additional **explicit** publication flag, *after* classification
and the source/working-tree integrity checks, the runner may commit a
single whitelisted JSON report containing only source SHA, fixed sample
labels and booleans, missing-gate descriptors, and owner-local provenance.
It verifies current remote `dev` equals source SHA before one
non-force push. It never retries or rebases on concurrent dev advances;
if publication fails, only short fixed categories can be relayed by owner.

## Inference limits and future gates

Even if a fractional inset has no thresholded exterior and has the
two-row virtual band in this sampled pose, real visual panel attachment
may differ. Separate gates: real original spring motion in both phases,
additional sampled alpha/extrema, real Wayland panel and screen-edge
visual inspection, pointer hover/click/popup transfer, all remaining
edges/scales including fractional monitor scales, system events and
canonical maintainer validation. If none of the three fractions passes
both private signals, design a separate strictly host-contained
connector or host/panel-edge layout experiment; do not silently choose
margin1 or weaken the production input mask.


## 2026-10-02 correction after first owner-local attempt

First owner-local revised source SHA `f5c689cea67d8e8db036b6c364274b7a78d7f69a`
returned `SOURCE_PINS=PASS`, `AQUA_PRIVATE_FRACTIONAL_BAND_INERT_PASS`
and `GATE=PRIVATE_FRACTIONAL_BAND_UNAVAILABLE`. The test wrapper, not
the original source or user environment, had selected the wrong clone
layout: `aqua-fractional.*/Hadalis`. The recursively inherited exact
original source audit in `scripts/aqua-manual-private-paint-core.py`
requires `aqua-paint-canary.*/repo`, owner-private directory modes,
and current working directory equal to the repo root. Therefore this
attempt fails a known pre-Qt guard. The generic gate does not establish
whether additional faults exist; no new real Qt evidence can be claimed.

The staged revised runner blob
`27620b5659ce7d0f3d4e0941dbc0633e053a8107` introduces a
same-policy explicit preflight with fixed
`GATE=FRACTIONAL_CLONE_LAYOUT_INVALID` before inherited audits, to
prevent a similarly opaque failure. The revised fake test blob
`ed9edeb3b1c7eeb92b3850a45ec116546092ee30` adds synthetic
valid layout and wrong parent/repository/current-directory/permission
rejection. Its new cases and real Qt still require a fresh owner-local
run. The manual command must use `aqua-paint-canary.*/repo`; no
original QML, default-off Aqua, production Region or stable change.


## Optional Git HTTPS report publication: non-interactive correction

Owner reported the last corrected local command stalled at a GitHub username
prompt, but provided no later fixed categories or resulting report. Source
review found that optional `git push` inherited an interactive terminal,
possibly triggering credential prompting. That is a plausible explanation,
not proof of actual Qt PASS or the particular subprocess that prompted.

Staged fractional runner blob
`da49d48850374c6f6da0db7ef11883959baebce1`
sets `GIT_TERMINAL_PROMPT=0`, `GCM_INTERACTIVE=never`,
`GIT_ASKPASS=/bin/false`, `SSH_ASKPASS=/bin/false`, disables
Git credential interactivity and sets child stdin DEVNULL on
its entire OPTIONAL git-report subprocess sequence. If preconfigured
noninteractive Git authentication is absent, optional report publication
returns `REPORT_PUBLISHED=NO` without retrying or leaking credentials;
the existing short safe categorical output is enough for owner to relay.
Updated fake-only static/source pin test blob
`8c5243aeb513aec855e84d90721724b16deac4b8`
has NOT yet been owner executed. This does not change prior real Qt
requirements or authorize a production fix.


## Owner-local static fractional result (source 0d7cdc5; no report push)

Maintainer supplied actual short local output showing five original full frozen
BOTTOM×1.5 Qt images captured on ONE original source-pinned component at
source SHA `0d7cdc50092a8269aa3fed34035dee71366324ef` and inert contract PASS.
M0 has exterior paint and virtual boundary band; M0.25 and M0.5 both have
**no thresholded exterior** and **positive abstract two-row edge band**;
M0.75 and M1 have no exterior but no band. The runner returned
`REPORT_PUBLISHED=NO`, so this is OWNER-SUPPLIED evidence, not a GitHub
report or independent replay. Its `JOINT_FRACTIONAL_CANDIDATE=YES` is only
same-frozen-pose raster evidence; no actual panel-edge visual connection,
spring motion in this trial, live compositor, input or popup qualification.

NEXT: a separate source-pinned original FULL two-case .25-vs-original0
**moving** private Qt run should measure painted exterior AND abstract band
from the SAME captures in BOTH active original spring phases with strict
independent state/mapped-motion witnesses. Require original positive
controls for interpretation. If .25 fails, consider .5 separately, not an
unjustified production margin change. All original production source/masks
remain unchanged.
