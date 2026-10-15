# AUTO-F01 — production rollout boundary (2026-10-15)

**Scope:** operator-supervised, opt-in GitHub DONE handoffs to the existing
user-level deterministic worker. **Not** unattended ChatGPT Project messaging,
automatic managed task queues, autonomous chat rollover, or a whole-repository
`stable` promotion. This document authorizes no job, service or deployment
operation. Owners must still approve the **exact immutable job digest** before
any new DONE handoff; code in this repository is not itself consent.

## Decision and evidence

The owner explicitly elected to skip another harmless publication smoke test
and requested production progression. That choice does **not** turn unknown
publication behavior into verified behavior.

| Area | Evidence | Production boundary |
| --- | --- | --- |
| Installed worker | Owner's read-only `doctor`: service active, heartbeat fresh, v1 handoff observed, source unit/process rooted at same checkout, no active work, full inventory of **240 published / 0 unsettled** receipts | Continue existing owner-approved **single-job handoff** operations without restarting the worker. The v1 marker does not attest every later Python patch was loaded into the running process. |
| First owner-hosted E2E | `JOB-AUTO-F01-SMOKE-20261015-01` ran `/usr/bin/true` once; local passed receipt, remote result and matching control cleanup accepted in Git | Result was pushed via separately owner-approved **publish-existing**, after seven failed automatic pushes. Do **not** claim unattended push was accepted. |
| Worker source CI | [AUTO-F01 focused safety #38747044776](https://github.com/llocphann/Alis/actions/runs/38747044776) passed at `bd62665fb695241ef9968b8889f9956dacefbe75` | Synthetic code-level checks passed. Not evidence of a running-process hot reload, live publication, or full release. |
| Whole-repository validation | [CI #38747044715](https://github.com/llocphann/Alis/actions/runs/38747044715) **failed** at that SHA: 87 failed checks across GUI/native/test/install families; [packaging #38746945234](https://github.com/llocphann/Alis/actions/runs/38746945234) also failed | No whole-project `stable` merge, package publication or claim of a green production release. |
| Source branches | `stable` and `dev` diverged: GitHub compare reported 3,762 commits ahead, one behind; stable still has historical pending job sources | Never merge the entire dev queue/old pending jobs into the production worker. No reset, force push or automated stable cutover. |
| AUDIO-I01 | Git `dev` currently retains `automation/queue/pending/JOB-AUDIO-I01-BASELINE-20261015-01.json`; its expired `ACTIVE.json` was previously retired in `9470466f`. No result on GitHub at inspection | Pending source is **not** approval. Do not recreate, release, delete, adopt or replay it under AUTO-F01. |
| ChatGPT managed transport | `automation.transport_gate.readiness()` reports `CHATGPT_PROJECT_SERVER_RECEIPT_UNATTESTED`; `scheduler_submission_authorized=false` | Native Project auto-send, managed queue Start, autonomous rollover and unattended Scheduler are **BLOCKED**. No env, UI, token, CDP or source-branch workaround. |

## Allowed limited-production behavior

1. Keep the existing worker's deterministic read-only diagnostics, bounded
   receipt storage and publication retry logic available. **Do not restart**
   currently healthy services just to label the system production.
2. If a new task is actually desired, a human owner must separately review its
   new pinned first-parent source SHA, exact SHA-256, run UUID, task code and
   bounded actions. Use a new job ID; stage `PREPARING`; require the exact
   local approval; only then may that *specific* control become `DONE`.
3. Failed or uncertain execution/publication is a durable receipt, **not**
   permission to execute again. Investigate the categorical phase first.
   `publish-existing` is **only** for an already-passed matching local receipt
   and separate owner approval; it never reruns actions.
4. The publishing code now checks the entire public receipt projection when
   reconciling an existing result, and matches run UUID, task code, base SHA,
   digest and job ID before retiring any `ACTIVE.json`. Maintain those checks
   in subsequent releases; no partial matching.
5. Any new deployment of changed worker Python modules needs a separately
   authorized worker-only upgrade *after* a fresh read-only doctor/receipt
   preflight. Existing service, source checkout, local receipt inventory and
   keyring must be protected. Do not restart other services.

## Release gates still open

- **AUTO-F01-PROD-01 — full canonical CI and packaging:** investigate failures
  against the matching source SHA. A passing focused suite is insufficient for
  a whole-project `stable` promotion. Avoid unrelated fixes under AUTO-F01.
- **AUTO-F01-PROD-02 — newly loaded worker:** verify exact installed module
  revision, durable 240+ receipt inventory and local source provenance
  *without* unapproved restart/dispatch.
- **AUTO-F01-PROD-03 — unattended publication:** since the owner skipped a new
  smoke test, classify fresh background receipt push/atomic cleanup as
  **unverified**. Production operators must supervise individually approved
  jobs and reconcile evidence; do not claim zero-touch delivery.
- **AUTO-F01-PROD-04 — managed ChatGPT transport:** require supported,
  authenticated server Project/conversation/message/final receipt binding and
  independent acceptance. `transport_gate` must continue to deny submissions
  until then.
- **AUTO-F01-PROD-05 — safe production branch migration:** inspect historical
  source/queue/responses and the diverged branch topology; create an isolated,
  auditable promotion with explicit data exclusions, not `dev -> stable`
  wholesale.

## Operator stop conditions

Stop any *new* dispatch and preserve all state if doctor loses heartbeat or
source provenance; any receipt is `preparing`, `executing`, `finished`,
`publishing`, malformed or unreadable; a control's job ID, run UUID, task code,
base SHA or digest differs; a remote receipt conflicts with the local public
projection; credentialed push is uncertain; or the ChatGPT transport cannot
attest a server identity. Do not force a transition to `published`, delete
uncertain evidence, restart a busy worker, or reuse a job identity.

**Rollout assessment:** the already-running GitHub worker is permitted to stay
operational for **explicitly owner-gated individual jobs**; this is an existing
limited mode, not an authorization to dispatch any job. Whole-system automated
production and `stable` cutover are **not yet accepted**.
