# AUTO-R01 — GitHub task-code Automation (partial implementation)

This independent, **fail-closed foundation** lets Alis resolve a canonical GitHub Issue from one task code and persist an internal Cloudbot prompt. No user-authored initial/continuation/rotation prompts are required. The historical scheduler, native Desktop bridge and bounded worker have now been restored as source on `dev` under [AUTO-F01](https://github.com/llocphann/Alis/issues/103). They are **not installed or auto-started** by the GitHub commit. Actual ChatGPT Desktop/Quickshell acceptance and Owner verification remain separate.

## Operations

- \`python3 scripts/alis-automation-task.py resolve AUTO-R01\`: read the unique coded Issue, complete first-page comments and canonical owner branch SHA.
- \`python3 scripts/alis-automation-task.py prepare AUTO-R01\`: record a durable, private **prepared** intake under \`$XDG_STATE_HOME/hadalis-automation/taskflow\`; never implicitly submit a prompt or execute commands.
- Cloudbot, after it has examined the Issue/source, generates a JSON payload with \`schema\`, \`task\` (pinned Issue/repo/branch/SHA), an allowlisted \`commands\` list, \`checkpoint\` and one Cloudbot-written \`next_prompt\`. It calls \`automation.taskflow.package(payload)\` to produce the \`{payload,sha256,id}\` envelope. The hash detects accidental tampering but is **not an authorization signature**.
- \`python3 scripts/alis-automation-task.py verify bundle.json\`: inspect schema, pinned SHA and allowed test commands without executing.
- \`python3 scripts/alis-automation-task.py execute bundle.json /path/to/isolated/checkout --approve-local-tests\`: explicit consent and exact clean checkout required. Uses subprocess argv, no shell, bounded 180s per command. Once a receipt is created the job cannot be automatically replayed. **Only reviewable local test commands** are accepted.
- \`python3 scripts/alis-automation-task.py continuation bundle.json receipt.json\`: return the Cloudbot-authored continuation prompt *only* for an explicitly passing matching receipt. This does not itself send it to ChatGPT.

## Limitations and safety gates

This is not yet end-to-end autonomous operation. AUTO-F01 must provide independent profile scheduler, authenticated conversation/message identity, durable ack and safe message dispatch. No fallback to DOM, injected ChatGPT auth, arbitrary Issue scripts or automatic system installs. The input Issue and the manifest are untrusted; the digest is not sufficient authorization for privileged/deployment actions. The local executor only supports narrowly allowlisted tests. It does not write commits or apply patches. In-progress receipts remain quarantined if execution is interrupted; no uncertain effects are repeated. Human verification is needed before closing a GitHub Issue.

Tests: \`python3 scripts/test-automation-taskflow.py\` (offline fixture). Native/Desktop and canonical maintainer validation must be recorded separately on the installed target.


## Per-task bundle and automatic housekeeping (2026-10-15)

All **runtime** Cloudbot prompts, transient script drafts, handoff manifests, short reports and task state are consolidated into one private file per task code:

\`\`\`text
$XDG_STATE_HOME/hadalis-automation/taskflow/tasks/Alis/AUTO-R01.json
\`\`\`

Companion/Intergration use the same filename within their own repository directory to avoid task-code collisions. Run \`prepare AUTO-R01\` to create it, or \`save-handoff AUTO-R01 < bundle.json\` to embed an already prepared Cloudbot handoff. For direct authenticated scheduler integration, call \`taskflow.save_handoff()\` without generating a separate bundle file. \`run-task AUTO-R01 /absolute/checkout --approve-local-tests\` reads the embedded handoff. Embedded \`scripts\` are **review-only drafts** and cannot be executed directly: only allowed repository tests run. Reusable regression tests remain under \`scripts/test-*.py\` as normal repo source and are never garbage collected.

Every new task intake opportunistically runs the safe cleanup policy. \`cleanup\` previews changes, and \`cleanup --apply\` applies them. A future AUTO-F01 scheduler must call cleanup periodically. Retention defaults: at 7 days after a **durably acknowledged terminal** task, remove old full prompts, embedded scripts and report text while retaining the job digest/receipt identity; at 30 days, remove the terminal task file. Tasks without a confirmed delivery acknowledgment or marked unresolved (including prepared, paused, uncertain, and awaiting owner verification) are **never automatically deleted**. Reports within an active task are capped at 12 bounded entries to avoid unbounded growth. Durable per-job receipts remain separately under \`taskflow/receipts\` as minimal no-replay evidence; these are never blindly deleted. No legacy unknown files or reusable repository test scripts are touched.


## Restored legacy capabilities: GitHub token and automatic chat rollover

**GitHub token** — Settings → Automation → GitHub credential offers Save/Clear and status for the three allowed repositories. The secret is passed to `secret-tool store` via stdin and lives **only in the system Secret Service keyring**, not in the task JSON, arguments, prompts, logs or repo. Metadata stores a boolean only. Local `resolve/prepare` uses the repository-scoped keyring credential for GitHub API requests, if saved. `scripts/alis-automation-task.py github-token-status|github-token-save|github-token-clear <owner/repo>` are the corresponding CLI entrypoints; Save reads at most 513 bytes from stdin. The narrow `git-credential` command exposes the password only via Git's authorized credential protocol after HTTPS host and repository-path checks, never through the Settings UI. Existing legacy per-profile keyring secrets are **not modified**, silently extracted or deleted by this migration.

**Automatic managed chat rollover** — `automation.rotation` implements fail-closed `bind_managed_chat`, `observe_chat_limit` and `acknowledge_chat_rotation` adapters. No user-editable prompt or iteration-count thresholds remain. AUTO-F01's restored authenticated transport must report a structured verified context/turn-capacity signal before rollover can occur; plain error-text matching or speculative context estimates are insufficient. A durable `rotation_pending` intent and Cloudbot-created resume prompt live inside the **single task-code JSON**. Reopening after a crash must first reconcile any existing rotation with actual server conversation/message IDs. A successful verification records the new managed chat, retires the resume prompt, and allows later rotations. An uncertain pending local job blocks rotation. **The adapters do not themselves open a new chat or send prompts** until AUTO-F01 supplies verified transport/session identity and delivery acknowledgments.

Focused behavior tests run via `python3 scripts/test-automation-taskflow.py`; GitHub Actions runs them as an isolated CI step. A full release/native acceptance still requires the restored scheduler and local Desktop test.


## Verified follow-up and owner gates (AUTO-R01 milestone)

`automation.lifecycle` provides `acknowledge_cloud_delivery`, `awaiting_owner_verification` and `owner_verified`. These are **authenticated adapter contracts**, not new transport implementations. The restored AUTO-F01 bridge must inspect the actual ChatGPT managed conversation/message identity and compare the **exact Cloudbot-authored continuation prompt** before acknowledging delivery. The local result must already be a matching, persisted, passing receipt. Repeated acknowledgment of the same message is idempotent; a conflicting message is rejected. The owner gate is explicit and does not close GitHub Issues automatically. Legacy cleanup now counts its retention period from the later of confirmed message delivery and owner completion; review-pending tasks are retained.

`python3 scripts/alis-automation-task.py status AUTO-R01` returns redacted task state to Settings without exposing prompt/script bodies or tokens. The Settings page polls this **read-only** status while a task is selected and displays whether a managed chat rollover is pending.

**Remaining integration:** Restore the original automation services and capability-checked authenticated Desktop bridge under AUTO-F01, and wire its verified limit/delivery callbacks and periodic cleanup. A trusted bridge must recognize actual provider/transport capacity signals, create the next managed chat in the same project, persist the new conversation/message identity, and verify delivery before proceeding. Without those capabilities the system stays in a clearly labeled prepared/pending state; there is no speculative chat rotation or automatic resend.

## Multi-task queue and restored Activity/Logs (AUTO-R01)

Enter multiple canonical GitHub task codes separated by semicolons, e.g. AUTO-R01; ABYSS-R09; BRAND-F01, max 20.
The Cloudbot chooses task order switch is OFF by default (exact entered order). When ON, Cloudbot reviews the pending canonical Issues, dependencies and pinned SHAs, chooses exactly one eligible Issue, and provides a verifiable decision ID. The queue remains SERIAL: no parallel execution and no automatic bypass of an uncertain task.

Queue metadata is stored only in the compact taskflow/queue.json file; each task owns its prompts, short reports, transient script drafts, current handoff and activity in tasks/<repo>/<TASK_CODE>.json. queue.lock is an advisory coordination lock, not a growing task ledger.

CLI: queue-prepare 'AUTO-R01; ABYSS-R09' --mode ordered|cloud; queue-status; activity AUTO-R01 [--repo owner/repo]. The internal queue.cloud_selection_prompt() prepares a reasoning prompt for a Cloudbot decision. It does not run a model, send a message or authorize execution. Only the restored AUTO-F01 authenticated scheduler may call queue.claim(verified_start=...) and queue.advance(verify_completion=...). Advancing requires confirmed Cloudbot completion and matching delivery acknowledgment; an Issue awaiting Owner verification can leave the execution queue while remaining open for owner review.

Settings shows Tasks, Activity and Logs. Task lifecycle events are capped at 60 records; display up to 40. Diagnostics are bounded and redact known token patterns. Refresh and Copy are available for private inspection; raw logs and historical prompt files are not duplicated. Existing safe cleanup retains pending/uncertain data and excludes repository-wide reusable tests.

Integration still pending: AUTO-F01 authenticated scheduler, real Desktop/cloud message transport, Cloudbot automatic selection callbacks, installed Quickshell acceptance and Owner verification. Preparing a queue does not itself dispatch any task.

## Integration milestone — existing scheduler, no second daemon (2026-10-15)

Restored modules: automation/manager, automation/chat_bridge and automation/worker; restored installer scripts/install-hadalis-automation.py and original offline regression tests. Historical queue/pending JOB fixtures and results were deliberately not copied into dev. The restored default legacy research profile is disabled/manual, and the first service boot quarantines preexisting legacy desired=run state while retaining all uncertain pending receipts. Existing installed XDG/service aliases remain recognized.

Settings → Automation → Backend can check service health and explicitly install the user units without enabling or starting them. The user enters one or more semicolon-separated task codes and chooses Ordered or Cloudbot selection, then explicitly presses Start. This is an opt-in execution action; queue preparation alone never submits prompts. The restored manager starts units through its existing control flow only for the approved Start.

automation/managed_tasks.py generates internal task-specific initial/continuation/rollover prompts dynamically from the single task JSON, so the manager config stores only a task identifier, not full prompt copies. It routes ordered queues into the restored manager daemon. When a final server-observed Cloudbot DONE response contains a matching managed message and no pending local job, the queue marks that task awaiting_owner and schedules the next serial task. Owner verification remains separate and never auto-closes the GitHub Issue.

For Cloud mode, the existing manager opens a dedicated reasoning turn in the selected managed ChatGPT Project (default for **new** Automation profiles: **Automatic Alis**) asking Cloudbot to choose exactly one canonical queued Issue. A task choice is accepted only from the server-observed final assistant response, the exact managed conversation/message ID and a single HADALIS_TASK_CHOICE line. Duplicates, stale receipts and unsupported choices are quarantined; the queue does not guess or retry a possibly dispatched chat. The same selector profile is reused for the next choice after a completed task.

One existing manager tick also performs conservative daily cleanup. The restored manager's native ChatGPT transport is based on an installed-build capability probe and may be incompatible with newer Desktop builds; absence of an installed native acceptance receipt is never counted as PASS. The CI regression suite checks offline queue/manager/bridge/worker behavior, while the full canonical validator and physical Niri/Quickshell/ChatGPT Desktop/Localbot run require separate verification.

CLI: python3 scripts/alis-automation-task.py backend-status; queue-prepare 'AUTO-R01; ABYSS-R09' --mode ordered|cloud; start-queue --approve; queue-status; activity AUTO-R01; owner-verify AUTO-R01 --approve. The owner-verification action changes the private task state only, and deliberately leaves the GitHub Issue open.

## Installer runtime fix — missing Python modules (2026-10-15)

The shared installation manifest `sdata/runtime-payload-dirs.txt` now includes **`automation`**. Before this change, repo-copy, Nix, Arch and other packaged/runtime installers shipped `modules/settings/AutomationTaskConfig.qml` and `scripts/alis-automation-task.py` but silently omitted the Python `automation/` package. The CLI then failed during import (exit 1, empty stdout); Settings previously reported a generic JSON parse exception and later identified `Automation Python modules unavailable`. This was **not** evidence that the system keyring was missing or that the backend services were uninstalled.

The shared manifest is consumed by the package/runtime copying machinery, so this fix covers **fresh installs and managed updates**. For a repo-copy install, sync the updated `dev` checkout through the regular `./setup update --local` path. For Nix/Arch, rebuild or update the package from a source revision containing this fix. A repo-link install reads from the checkout directly. Do not copy only a standalone Python CLI into the runtime without its `automation/` dependencies, or install services in an attempt to repair a Python import failure.

Regression: `test_packaged_automation_runtime_imports_from_installed_layout` uses the canonical runtime manifest to materialize a minimal installed tree in an isolated temporary directory, then runs `queue-status`, `github-token-status` and `backend-status` as real Python subprocesses with `-I`. It also verifies source-only repository tests are excluded. This confirms import/path parity without interacting with a live desktop or existing task state. Native Quickshell and complete Cloudbot/Localbot functional acceptance are still separate.


## Default ChatGPT Project (2026-10-15)

New Automation task-manager and Cloudbot selector profiles default to the existing ChatGPT Project named **Automatic Alis**. New generic manager profiles also inherit this default; previously persisted profiles and any active/pending conversation retain their configured Project and exact conversation identity. This does **not** automatically create a ChatGPT Project. The authenticated Desktop transport must uniquely resolve the Project before starting a new chat; unavailable or ambiguous Project names fail closed. A future Settings Project selector must preserve the same queue-scoped identity and must not silently rebind in-flight sessions.
