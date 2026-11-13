# Alis agent workflow — GitHub Issues

These rules apply to both Local and Cloud development AI. ChatGPT is the reasoning agent; tools, tests and workers execute the requested work.

## Source and safety
1. Work on **Alis `dev`**, refetch its HEAD and affected files before every edit, preserve concurrent changes, and do not change `stable` unless the owner explicitly requests it. Do not create a branch/PR by default.
2. **Each repository owns its own GitHub Issues:** [Alis](https://github.com/llocphann/Alis/issues) for core shell/host (`dev`); [Alis-Companion](https://github.com/llocphann/Alis-Companion/issues) for Companion (`main`); [Alis-Intergration](https://github.com/llocphann/Alis-Intergration/issues) for optional integrations (`main`). Cross-repo work keeps its primary Issue in the repository that owns the main outcome, with links to dependent Issues in other repositories. Never append tasks/status to Markdown ledgers. Old Alis Issues marked MOVED are historical pointers, not active work; do not reopen or recreate them in Alis.
3. **Intake goes directly to the owning repository's GitHub Issues:** on an actionable owner request, determine whether the primary outcome belongs to core Alis, Companion or Intergration. Search **open and closed Issues in that repository**, and search old Alis MOVED issues for historic task codes before creating a duplicate. Update/reopen the canonical matching Issue; create one only for a different outcome. Title: `[DOMAIN-F##]` (feature), `[DOMAIN-R##]` (rework), `[DOMAIN-I##]` (bug), followed by a short description. Check existing codes before assigning the next unused one. Do not stage the task in a file or create duplicate Issues.
   **Labels:** reuse GitHub's built-in `bug` for faults, `enhancement` for features/rework, and `documentation` for docs-only tasks (other built-ins such as `question`, `duplicate`, `invalid`, `good first issue`, `help wanted` only when literally applicable). Keep exactly one primary `area:*`. Add colored `complexity:high` only for substantial cross-module/architectural, GPU/CPU/RAM, difficult rendering, native lifecycle or safety-sensitive work; do not label minor UI tweaks as high complexity. Use `status:deferred`, `status:blocked`, `status:awaiting-owner` only when supported; remove stale status tags. Do not use obsolete `type:*` labels or invent priority. Custom label colors are maintained by `.github/issue-label-palette.json` and its dev workflow.
4. **Notes should be just enough:** write **Goal**, **Constraints** (only if relevant), and **Done when** (acceptance). Include repo/ref only when ownership differs. Usually a few lines suffice; for high-risk data, permissions or cross-repo changes, state the essential safeguards. Update the Issue body for changed requirements; comment only on meaningful milestones, with a brief outcome, tested SHA/exit status and next blocker where known. Link full logs/evidence instead of pasting them; no daily status spam.
5. **Issue lifecycle:** unfinished = **open**; bot-reported complete but unverified = **open, "Awaiting Owner verification"** (state separate test gates). Explicit maintainer approval = **close as completed**; withdrawn = **close as not planned**. Never convert a skipped/failed/unrun test into PASS or assume an owner approved without saying so. Reopen for real new scope/regression. GitHub Issues' own history is the changelog; don't mirror updates to task Markdown.
6. For work in **Alis-Companion** (`main`) or **Alis-Intergration** (`main`), create/update the Issue **in that exact repository**, not Alis. Preserve actual implementation repo/ref, matching host/package SHA, consent/permissions and package-local tests. When work crosses repositories, link related Issues explicitly without duplicating responsibility or claiming verification. Migrated source Issues in Alis are closed as **not planned here** solely to redirect; their new destination Issues remain open until normal Owner verification.

## Selection and priorities
- **Owner retirement 2026-10-18:** `AUTO-F01` (#103) and `AUTO-R01` (#104) are withdrawn/closed as not planned. Never build, resume, select, queue, dispatch, auto-approve or restart Automation; all previous automation queue and handoff approvals are superseded. Work only on the safe decommission `AUTO-R02` (#118) without using the automation worker itself. Keep uncertain receipts and user secrets until owner-supervised retention/cleanup.
- Explicit latest owner priority takes precedence. Otherwise work first on actionable **non-deferred New Features**, address related Rework and Issues alongside them, then remaining high-impact Rework/Issues. Within a group, prioritize crashes/data loss, regressions and unblocking dependencies.
- **Final phase:** `PERF-F01` and `AC-F01`–`AC-F10` are deferred until all other non-deferred tasks are done. **Very last:** `SYS-F01` after that deferred group, unless owner reprioritizes. Preserve their consent and native quality gates.
- Continue one safe atomic milestone at a time. A partial source milestone is not whole-task completion. Don't recreate features already Owner verified.

## Product and validation boundaries
- Prefer the existing connected Abyss/Quickshell presentation and faithful Caelestia-like UI. Waffle remains supported; do not classify Waffle as obsolete.
- Ship English-only UI (`translations/en_US.json`); preserve legacy config aliases, user files, source identity, test coverage, and optional package boundaries. No automatic privileged installs, model downloads or vault mutations.
- Validate through scoped regression tests and `bash scripts/validate-maintainer-local.sh` at an exact committed SHA. All automated tests and stutter/memory probes must run in **100% Silent / Zero-Focus mode** (`unset WAYLAND_DISPLAY DISPLAY` / `QT_QPA_PLATFORM=offscreen` or `native_test_session.py`; see `.agents/skills/alis-silent-verify/SKILL.md`). Physical Niri/Quickshell, installed-package, multi-output and owner visual/input acceptance are separate; never turn a STOPPED, FAIL or unrun check into PASS.
- Follow `.agents/rules/alis-design-and-runtime.md`: external Desktop Edit Stage docks (`Bottom`, `Left Popups & Panels` / `Tabs`, `Right Screen Edge` / `Layout & Grid` / `Manage Widgets`, `Take Screenshot`) with horizontally centered Desktop, balanced screen-edge clearances, flexible content-driven dock sizing capped at `80%` of the shrunk Desktop width (Top/Bottom) and height (Left/Right), monotonic edge-slide motion, and `Controls.Overlay.overlay` Stage exemption + input mask; concise UI copy, centered button icon+text alignment, zero text overlap / `marqueeActive`-gated `StyledText` eliding, equal `AiConfig` Bento row heights, and `SettingsMaterialPreset.standardBentoHeight` parity on Settings tabs; explicit `Item` width bindings when reparenting controls; inside-Desktop-only wallpaper shader transitions with live widgets visible; `alis-deps` only (no `inir-deps`); and zero-lag large surface & sidebar transitions (`targetRecord.content` static input mask on open, transient mid-slide `contentCanvas` layer, monotonic `OutCubic` slide with zero bounce on both Left/Right Sidebars and Cava modules, sequential post-boot idle warmup).

## Mandatory no-regression and legacy-data patch gates
- **Optimization / improvement = strict functional preservation.** Before changing an existing subsystem, inventory its public behavior, data contracts, saved settings, inputs, feature flags, animation/visual behavior, native lifecycle, optional integrations and other dependent surfaces. Establish a comparable before/after baseline at pinned SHAs. No previously working or Owner-accepted feature may silently disappear, be disabled, degrade, or change semantics for a CPU/RAM/GPU or UX improvement. If an intentional trade-off is unavoidable, record the exact impact and obtain explicit Owner approval **before** implementing it.
- **Bugfix / patch = existing-data parity, not just new-data correctness.** Trace every affected read/write path and every existing persisted record, legacy schema/config version, migration, cache/index and historical event. A fix must work for **already saved user data** as well as records created after the patch. Where older data need new fields, recalculation or normalization, implement a backward-compatible, versioned, idempotent, restart-safe migration/backfill or read-time compatibility strategy. Never silently discard, reset, duplicate or rewrite unrelated data. Preserve user-owned values, IDs, timestamps, recurrence, relations and backups; support partial-failure retry and rollback/recovery. Avoid unapproved destructive migrations.
- **Mandatory regression matrix.** For each change, test: (1) fresh/default state; (2) real/sanitized pre-patch persisted fixtures loaded after upgrade; (3) mixed old/new records and repeated patch application; (4) save/restart/reload/Cancel/rollback and failed/interrupted migration; (5) all impacted widgets/surfaces, output variants and optional dependencies. Include data persistence/readback and state transitions, not only source-text assertions or UI snapshots. For optimizations, rerun affected original behavior tests plus cross-feature interactions; do not weaken or delete existing oracles to obtain a PASS.
- **Acceptance gate.** Include affected-feature inventory, exact source/installed SHA, migration/backfill outcome and before/after PASS/FAIL/SKIP/UNRUN evidence in the canonical Issue. A scoped PASS cannot establish whole-system parity; a failing, skipped, unrun or stopped test stays explicit. Do not report implementation DONE/ready for Owner verification while known regressions or known legacy-data mismatches remain unresolved. Native desktop/Owner acceptance stays separate and mandatory where applicable.

## Behavioral guidelines to reduce common LLM coding mistakes

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

Tradeoff: These guidelines bias toward caution over speed. For trivial tasks, use judgment.

### 1. Think Before Coding

Don't assume. Don't hide confusion. Surface tradeoffs.

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

Minimum code that solves the problem. Nothing speculative.
- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

Touch only what you must. Clean up only your own mess.

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

Define success criteria. Loop until verified.

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

These guidelines are working if: fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

[Overview](README.md) · [Architecture](ARCHITECTURE.md) · [Structure](STRUCTURE.md) · [Alis Issues](https://github.com/llocphann/Alis/issues) · [Companion Issues](https://github.com/llocphann/Alis-Companion/issues) · [Intergration Issues](https://github.com/llocphann/Alis-Intergration/issues).
