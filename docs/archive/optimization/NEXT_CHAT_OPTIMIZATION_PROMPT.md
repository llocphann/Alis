> **ARCHIVED / SUPERSEDED — 2026-10-07.** Current work starts at [the categorized task entry](../../../to-do/README.md); [optimization research](../../optimization/README.md) stays separate. This dated prompt is retained only for history.

# Prompt — Next Chat: Optimization / Bug Fix / Refinement

Continue work on the GitHub repository `llocphann/Alis`, branch `dev`.

**Hard workflow lock:** work and commit directly on `dev`. Do not create or switch to another branch and do not open a pull request unless the maintainer explicitly asks for it.

The Abyss integration phase is complete. Treat the current Abyss/perimeter
architecture as the production baseline; this new phase is for **optimization,
bug fixing and refinement of existing features**, not another migration.

Before editing, read `to-do/README.md` and the applicable `to-do/cloud-bot/` checklist. This prompt is a dated handoff snapshot, not a competing active task list.

Before editing:

1. Refetch the latest `dev` because other agents may push concurrently.
2. Read:
   - `README.md` §1.1;
   - `docs/ABYSS_INTEGRATION_COMPLETE.md`;
   - `docs/PERIMETER.md`;
   - `docs/SHELL_SURFACE_CONTRACTS.md`.
3. Do not create/switch to a work branch or open a PR unless explicitly requested.
4. Do not merge/reset/rebase/force-push shared history.
5. Preserve unrelated concurrent work.
6. If a previous fix is disproved by runtime evidence, revert/surgically remove
   that failed change before trying a different approach. Do not stack patches.

Current maintainer findings:

- Settings task-tab indicator is still unresolved: expanding/collapsing **Headings** can make the indicator jump downward. The latest attempt improved stability but was not accepted; do not stack another workaround on top of it.
- System Monitor popup refinement is source-complete on `dev`: CPU Load now reserves a two-digit width floor and RPM/Level have Material icons. It still needs live acceptance for no 1↔2 digit popup resize and correct fan-row alignment.
- Material-only cleanup is actively progressing across remaining leaf/widget/plugin/overlay surfaces; it is not complete until the active-tree residue audit and maintainer validation pass.

Architecture constraints:

- Physical Screen Edge geometry is locked and owned only by
  `modules/screenCorners/ScreenEdges.qml`.
- Normal ii Bar physical perimeter is part of that same locked frame.
- ii Bar popups use `StyledPopup -> ConnectedSurfaceAbyssFrame/AbyssField`.
- Sidebar/Dashboard/Settings use `ConnectedSurfaceAbyssEdgeSurface`.
- Dashboard-owned Applications Search shares the Dashboard Abyss field and must
  not paint a second connected field.
- Motion remains slide-only through `SurfaceMotion`.
- Do not reintroduce `ConnectedSurfaceJoinFlares`, `PerimeterCornerShadow`,
  common `RoundCorner`, fake screen-rounding paint, `joinFlare*` tokens,
  helper wedges or geometry patches.
- Tangent welding is SDF-only. Content, input and shadow stay at the real owner
  boundary.
- ii Bar popup shadow follows `appearance.screenEdge.physicalShadow`.
- Waffle is a separate supported family; do not touch it unless explicitly
  requested.

Working method for every issue:

- inspect the complete feature path and its callers/consumers first;
- reproduce the root cause from source/runtime evidence;
- prefer deletion/simplification over adding compensating geometry;
- keep interaction contracts intact: focus, Escape, outside-click, hover
  transfer, multi-output ownership and fullscreen lifecycle;
- watch for stale Loader/window lifetime, duplicate renderers, unnecessary
  bindings, excessive recomputation, animation churn and hidden surfaces that
  still render;
- preserve visual consistency with the existing Material design and current
  connected-surface model;
- update/add regression contracts when behavior or ownership changes;
- run the narrow relevant tests first, then
  `bash scripts/validate-maintainer-local.sh` when appropriate;
- for runtime-sensitive changes, ask for/inspect real Niri screenshots or logs
  before declaring the defect solved.

Priority for this phase:

1. correctness and regressions;
2. lifecycle/performance/resource usage;
3. animation smoothness and interaction quality;
4. layout/adaptive behavior;
5. code simplification and removal of proven-dead paths;
6. small UX refinements without architectural rewrites.

When starting, first audit the latest `dev` and summarize:
- current HEAD;
- any concurrent changes relevant to the requested feature;
- the exact source path responsible for the issue;
- the minimal root-cause fix you intend to make.

Then implement the fix directly on `dev` with focused commits.
