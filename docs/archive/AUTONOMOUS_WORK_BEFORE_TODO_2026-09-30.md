# Archived agent/WORK.md checkpoint

**Historical only**; current work starts at [the categorized task entry](../../to-do/README.md), ordered Issues/bugs → Rework/optimization → New features.

# Active autonomous work

## Objective

Run Alis strict-lossless optimization research continuously and autonomously.

ChatGPT is the only reasoning agent. Local components are deterministic transport/execution only.

## Research contract

- Repository: `llocphann/Alis`
- Branch: `dev`
- GitHub is the authoritative source of truth.
- Research only unless the maintainer explicitly authorizes implementation.
- Do not modify runtime QML/native/service/product code as part of optimization research.
- Proven research findings are recorded in `docs/optimization/STRICT_LOSSLESS_GPU_RAM_CPU_AUDIT.md`.
- Re-fetch current `dev` HEAD every turn and before every write.
- Read the newest handoff tail and audit intervening commits.
- Search the handoff before promoting candidates to avoid duplicates, ALREADY, CLOSED, or SUPERSEDED findings.
- Apply the strict-lossless standard conservatively; only classify CONFIRMED after parity is proven.
- Prefer material hot-path, per-frame/reactive, interaction-hot, asymptotic, allocation/copy, process-spawn, parsing, publication, main-thread, and memory/GPU opportunities.
- Do not fabricate whole-Alis speedup percentages.

## Continuous loop policy

The research service must not stop after one round.

- `ALIS_LOOP:CONTINUE`: continue the next research step immediately.
- `ALIS_LOOP:WAIT_RESULT JOB-...`: wait for one deterministic local validation job, then continue automatically.
- `ALIS_LOOP:ROTATE`: persist the research checkpoint to the handoff and resume in a fresh chat before context rollover.
- `ALIS_LOOP:CONNECTOR_BLOCKED GITHUB`: stop only because the GitHub connector is unavailable.
- `ALIS_LOOP:DONE`: reserved for an explicit maintainer request to stop/disable continuous research. Completing a round is not DONE.

The runtime also enforces continuous-research mode: an accidental DONE is converted into another continuation rather than terminating the bridge.

## Automation status

- autonomous prompts now explicitly forbid switching/handing off to Work mode; they must remain in the current ChatGPT conversation and use the GitHub connector plus deterministic local jobs.
- prompt submission now refuses to write into a non-empty composer or while a Stop/generation control is active. For submitted turns, completion requires a new post-submit ALIS_LOOP marker and baseline-aware extraction no longer falls back to an older marker. This prevents a continuation prompt from being pasted into the composer while the previous response is still generating.
- `JOB-AUTONOMOUS-PROMPT-GUARD-001` passed Python compile, chat-bridge protocol/state tests, desktop driver/CLI syntax, and marker-scanner regression.
The desktop transport, rich GitHub mention path, completion detection, marker extraction, deterministic worker, and systemd rollout have been validated. The bridge/worker service path is installed.

Continuous-research changes are covered by `JOB-CONTINUOUS-RESEARCH-VALIDATE-002`, which passed:
- Python compile checks for runtime/protocol/installer;
- chat-bridge protocol/state regression;
- desktop driver syntax;
- desktop CLI syntax.

The latest optimization handoff commit observed while configuring this mode was Round 49, but autonomous turns must discover the current research baseline from the repository instead of relying on that observation.

## Next step

Fast-forward the maintainer checkout, reinstall/reset the user services so the bridge receives `ALIS_CONTINUOUS_RESEARCH=1`, and start a fresh autonomous research session. From then on, research should continue across rounds without the maintainer typing `continue`.

