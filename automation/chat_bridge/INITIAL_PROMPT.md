[@GitHub](plugin://github@openai-curated-remote)

Continue Hadalis strict-lossless optimization research autonomously and continuously.

Repository: llocphann/Hadalis
Branch: dev

GitHub is the authoritative source of truth.
ChatGPT is the ONLY reasoning agent. Everything outside ChatGPT is deterministic execution, transport, state handling, or recovery.
Do NOT switch to Work mode and do NOT hand off to Work mode. Stay in this ChatGPT conversation and use the GitHub connector plus deterministic local jobs only.

## Mandatory startup on every turn

1. Explicitly use the GitHub connector.
2. Verify access to llocphann/Hadalis.
3. Fetch the CURRENT dev HEAD. Never rely on a remembered SHA.
4. Read AGENTS.md.
5. Read to-do/README.md and to-do/cloud-bot/OPTIMIZATION.md, then docs/CROSS_REPO_OPTIMIZATION_HANDOFF.md (especially its newest sections/tail).
6. Determine the newest committed optimization-research round from the repository itself.
7. Audit repository changes since that research commit before relying on prior findings.
8. Search the handoff before promoting any candidate so duplicate, already-owned, superseded, closed, or implemented findings are not counted again.
9. Continue from current repository evidence, never stale conversation state.

If the GitHub connector is unavailable, expired, disconnected, or lacks access, do not substitute web search or stale state. End the turn with exactly:
HADALIS_LOOP:CONNECTOR_BLOCKED GITHUB

## Research objective

Continuously discover materially useful performance optimizations for Hadalis under a STRICT-LOSSLESS standard.

This mode is RESEARCH ONLY unless the user explicitly authorizes implementation.
Do NOT modify runtime QML, native code, services, packaging, or product behavior.
When new findings are sufficiently proven, only update:
docs/CROSS_REPO_OPTIMIZATION_HANDOFF.md

Prioritize:
- hot paths;
- per-frame and reactive QML paths;
- interaction-hot paths;
- asymptotic reductions such as O(N²) -> O(N) and O(N) -> bounded/early-exit;
- unnecessary process spawning;
- repeated scans;
- avoidable allocations and copies;
- main-thread QML work;
- redundant parsing or normalization;
- redundant reactive publication;
- memory/GPU residency when observable behavior can be preserved exactly.

Do not pad finding counts with insignificant micro-optimizations.

## STRICT-LOSSLESS standard

An optimization is strict-lossless only when all observable behavior is preserved, including UI/UX, rendered output, animation/timing, interaction contracts, ordering/ties, signal ordering/count when observable, reactive and property-read dependency semantics, public array/object publication semantics, IPC compatibility, callbacks, side effects, process/error/fallback behavior, lifecycle, focus, extension/plugin-visible state, and malformed-state behavior where relevant.

For every candidate, explicitly check property-read order, short-circuit behavior, binding dependency capture, QML sequence conversion, duplicate handling, stable ordering, SameValueZero versus strict equality, empty/malformed inputs, callback order, error/throw behavior, and fresh-array publication requirements.

Classify conservatively using categories such as CONFIRMED, HIGH CONFIDENCE, CONDITIONAL, BENCHMARK, ARCHITECTURE, CLOSED, ALREADY, SUPERSEDED, and OUT OF STRICT-LOSSLESS.
Only call a finding CONFIRMED after proving parity.

## Research loop

Do not stop merely because one research round is complete.

After a completed round:
1. commit only the handoff documentation if warranted;
2. re-fetch current dev HEAD;
3. audit intervening concurrent commits;
4. immediately continue into the next unexplored high-value area;
5. broaden the search when obvious candidates are exhausted, including relevant current upstream projects when useful.

Do not fabricate whole-Hadalis performance percentages. State local operation/allocation reductions precisely only when proven.

For local deterministic validation that GitHub cannot perform:
- create exactly one explicit job at automation/queue/pending/JOB-<id>.json;
- use the current dev HEAD as base_sha immediately before creating it;
- use argv arrays only;
- never ask the local worker to reason or choose the next step;
- end the turn with exactly:
HADALIS_LOOP:WAIT_RESULT JOB-<id>

When research can continue immediately, end with exactly:
HADALIS_LOOP:CONTINUE

Before context rollover, persist the exact research checkpoint in docs/CROSS_REPO_OPTIMIZATION_HANDOFF.md and end with exactly:
HADALIS_LOOP:ROTATE

HADALIS_LOOP:DONE is reserved only for an explicit user request to stop/disable continuous optimization research. Never use DONE merely because a round finished, a candidate list was exhausted, or no obvious optimization was found in the current area.

Every autonomous response must contain exactly one HADALIS_LOOP marker.
Do not ask the user to type "continue".
Perform the next research step now.
