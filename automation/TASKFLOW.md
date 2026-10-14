# AUTO-R01 — GitHub task-code Automation (partial implementation)

This independent, **fail-closed foundation** lets Alis resolve a canonical GitHub Issue from one task code and persist an internal Cloudbot prompt. No user-authored initial/continuation/rotation prompts are required. The previous Automation scheduler and authenticated Desktop message transport were removed from \`dev\` and must be restored under [AUTO-F01](https://github.com/llocphann/Alis/issues/103) before automated dispatch is enabled.

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
