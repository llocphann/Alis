# Hadalis agent workflow

Hadalis uses a single-agent development workflow on `dev`.

These instructions apply equally to **Local and Cloud development AI**, on
every new request and continuation. Both use the same repository task lists.
The `cloud-bot` directory name does not create a separate workflow for Local AI.

## Working rules

1. Fetch/refetch the current `dev` HEAD before every audit and immediately before every write or ref update. Never assume a previously seen HEAD is current.
2. Work directly on `dev`. Do not create a branch or PR unless the maintainer explicitly asks for one. Never mutate `stable`.
3. Re-read every file you intend to edit from the current HEAD and avoid overwriting valid concurrent work. Fix forward; do not rewrite shared history.
4. Keep commits atomic and technical-purpose focused.
5. Use repository regression tests and the canonical local validator as the primary acceptance path. Do not infer product quality from GitHub Actions state.
6. Nix support stays in-tree but dedicated Nix validation is deferred/non-blocking for the maintainer workflow.
7. Waffle is a separate supported shell family. Never classify Waffle as legacy or remove it as ii/Connected Perimeter cleanup.
8. Prefer behavior/contract tests over implementation-spelling grep assertions. Do not change runtime behavior merely to make a stale test green.
9. Use `to-do/` as the single active chatbot task entry point. ChatGPT is the only reasoning agent; repository tests and the canonical maintainer validator are the execution/acceptance path. Do not create bot-number, ownership, collision-boundary, separate task-board or handoff bureaucracy. Continue the highest-value unresolved work in one agent context.
10. On receipt, automatically record/classify every actionable maintainer request into `Issues/bugs`, `Rework/optimization`, or `New features` before implementation. Merge duplicates and corrections; split mixed requests by outcome. Select the next actionable task autonomously using the shared policy below, without asking the maintainer to classify or choose routine work. Effective 2026-10-12, prioritize New features; address related Rework/optimization and Issues/bugs alongside the selected feature in the same single-agent context. Preserve explicit feature sequences and complete the current safe atomic milestone. When no feature can advance, continue related, then other actionable Rework/Issues. Keep unverified source fixes open with their remaining acceptance; archive fully completed items after seven days.

## Task routing

**Single portfolio backlog:** Alis dev also owns every task for
[Alis-Companion](https://github.com/llocphann/Alis-Companion) and
[Alis-Intergration](https://github.com/llocphann/Alis-Intergration).
Their code, package tests and technical evidence stay in their repositories;
the three Alis task categories alone own intake, priority, progress,
completion and archiving. The satellite repositories' previous TODO
documents are immutable *import evidence*, not competing active work queues.
Never create a separate Companion or Integration task board. Record the actual
implementation repository/ref, both compatible source SHAs and source/native
acceptance gates when executing external tasks; the general Alis dev-only rule
does not imply an external repository has a dev branch.

Read `to-do/README.md` after this file. Keep active work in `to-do/cloud-bot/`. Technical research remains in `docs/` and archives remain historical.

The only active task lists are `ISSUES.md`, `REWORK_OPTIMIZATION.md`, and `NEW_FEATURES.md` in `to-do/cloud-bot/`. Old ABYSS/OPTIMIZATION/RELEASE links are compatibility pointers, not competing checklists. Record new reports and meaningful progress in the appropriate category, not in another chronological handoff document.

Read and apply [the shared intake and task-selection policy](to-do/cloud-bot/README.md)
after the entry point. Re-evaluate it on new input, every continuation and after
each completed milestone. Prioritize impact/severity within a category, not file
position or the newest message alone. Keep a task awaiting unavailable evidence
open, record what it needs, then continue independent authorized work. A generic
"continue" means choose the next task from these lists and carry it through the
required implementation and validation; it does not require another task choice
from the maintainer.

## Current product priorities

Unless the maintainer changes them, these product directions guide implementation
within the selected task. They do not override the shared feature-first policy or an
explicit immediate priority.

1. Caelestia-like UI/UX using the existing iNiR surfaces: existing popups should visually connect to their bar/screen edge instead of introducing a second popup system.
2. Connected-surface presentation is the default for existing bar popups and must not require a user-facing toggle. Keep the broader `iiPerimeter` composition cutover guarded until it can replace the legacy composition without dropping functionality.
3. Keep Dock presentation simple: Panel is the canonical ii dock style; historical style values must degrade safely to Panel.
4. English-only localization. `translations/en_US.json` is the only shipped locale catalog; multilingual translation generation/auditing is not an active product requirement.
5. Runtime correctness, local regression coverage, install/update lifecycle, and source/package identity.

Documentation/wiki polish and release prose are lower priority and must not block the product/UI loop unless a change directly invalidates a required runtime or packaging contract.

## Validation

Canonical maintainer validation entry point:

```bash
bash scripts/validate-maintainer-local.sh
```

A PASS applies only to the exact SHA printed by that run. Environment-only desktop acceptance (live Niri/Quickshell interaction, multi-output/hotplug/suspend/fractional scaling) remains separate from static/local contract validation.
