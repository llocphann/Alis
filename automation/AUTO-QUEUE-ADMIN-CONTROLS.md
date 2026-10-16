# Alis Automation — queue and administrator controls

The Automation Settings task-input field supports **two paths**:

- **Entered codes:** Alis queues those exact canonical GitHub Issues in the
  specified order (or offers the queued choices to Cloudbot). Each Issue must
  have a unique code and current pinned source SHA.
- **Blank field:** **Find tasks** discovers up to eight unique, currently open
  coded GitHub Issues from the allowlisted Alis repositories. It skips blocked
  or high-complexity visual/UI work, prioritizes Issue titles/labels mentioning
  Backend, daemon, API, worker, CI, security, database, or automation, and
  prepares a reviewable serial queue. No Issue body is treated as an
  instruction. Discovery never sends a ChatGPT prompt, schedules an unapproved
  job, bypasses the Desktop transport gate, or approves privileged execution.
  The user must review the list and activate Start separately. If no safe
  candidate exists, it reports an explicit error instead of selecting an
  arbitrary visual task.

## Old "Pin changed" queue recovery

An older saved queue can still show six or more deferred entries with
`source_pin_changed` after Alis is updated. That legacy label is NOT
proof that all GitHub sources changed: it was emitted before worker/ACK
state outranked branch-tip drift in the classifier. The current backend
does not generate that legacy reason for new queues.

For a fully parked `review_required` queue, leave the task-code input
blank: **Find** becomes **Recheck**. This is an explicit, no-send
classification of the **same originally requested** queue, not a new
Backend-first discovery. A stale UI snapshot is rejected under
`queue.lock`. The recheck verifies every original task file still
exists, re-resolves canonical open Issues, and preserves all task files,
saved base SHA, history, handoffs, pending messages, receipts, manager
profiles, and worker jobs. No Start approval is carried forward or
granted. Prior `awaiting_cloud_ack` work becomes **Ack pending**, prior
owner-review work becomes **Owner review**, unverified ancestry becomes
**Pin unverified**, and truly pristine ancestor-pinned work may become
**Queue**. The latest local manager session and original GitHub Issue
metadata must also pass all ordinary gates.

If the original task file, exact GitHub Issue evidence, or ancestor
proof is absent, remain parked and inspect the original evidence rather
than clearing/re-pinning/replaying. An active/selected/partially
completed queue is not eligible for recheck. This is not a workaround
for the separate native ChatGPT server receipt authorization gate.
For old installed Settings builds that do not offer **Recheck**,
update Alis `dev` and reload the installed UI/backend first; do not
assume a GitHub source-only update immediately changes running QML.

## Queue controls: Stop, Clear queued, Clear stopped queue

Settings → Automation → GitHub tasks shows separate owner-confirmed controls:

- **Stop queue → Confirm stop:** atomically revoke queue Start approval and
  change a live queue from active/waiting to **stopping**, then request
  **Stop** for that exact manager profile. Once the profile confirms its
  desired state is stopped, the queue becomes **stopped**. No next task will
  be dispatched. If a manager profile still exists but is unavailable
  or fails to acknowledge Stop, the queue stays **stopping / reconciliation
  required**. If the old profile no longer exists, the queue itself can be
  marked stopped after revoking approval, with an explicit **manager missing /
  worker still independent** warning. This permits archiving an orphaned
  queue without pretending to have cancelled an older worker action. Stop
  does **not** retract a sent message, terminate a worker process, discard
  a job ID or erase a receipt. The second Stop confirmation is bound to
  the SHA-256 identity of the complete displayed queue, not only its active
  task code. If another queue with the same first task replaces it, Stop
  rejects stale confirmation before revoking the newer run's approval.
- **Start UI → Confirm UI Start:** explicitly acknowledges local UI-only
  response evidence (not server-attested Project membership) for the exact
  prepared queue snapshot. Backend rechecks that snapshot under the queue
  lock immediately before recording Start approval. If any later task, pin
  or queue generation changed, Start rejects it without dispatch. The
  existing native transport gate remains unchanged.
- **Clear queued → Confirm clear:** remove only items with state `queued`
  (including while the first item is still `active` or its Stop is in
  **stopping** pending manager reconciliation). Preserve the active
  item, selected identity, approval, profile, task records and all machine
  evidence. If the UI shows a last-known queue, its exact ordered
  `repository:code` list **and** the opaque SHA-256 identity of the
  complete durable queue snapshot are rechecked under the exclusive queue
  lock. A new queue with identical codes, an intervening Start/Stop, or a
  changed active selection rejects a stale Clear instead of mutating that
  different version. Refresh and confirm again; a hash is only a comparison
  token, never approval or a transport receipt. Each newly prepared queue
  also has a fresh random generation ID, preventing a deleted/reprepared
  identical queue from reusing a previous confirmation even within one second.
  Existing legacy queue manifests are not rewritten during read-only status.
- **Clear stopped queue → Confirm clear:** once Stop was acknowledged,
  archive the complete stopped queue manifest and return the UI to an
  empty queue. This is **not** deleting the old worker's action/receipts
  and is **not** a cancellation of work that was already dispatched.
  Unacknowledged `stopping` is never considered safely stopped.

The full original manifest is archived in the local legacy-migration
`hadalis-automation/taskflow/queue-history/` folder before clearing.
All per-task records, GitHub pending handoffs, local receipts, historical
results and active/uncertain worker actions stay in their original stores.
The UI cannot modify `stable` or delete another task's GitHub data.
The folder name persists only for backward compatibility with installed
state, not as product branding.

## Optional sudo password — saved to local Secret Service

Settings → Automation → **Administrator access** offers a masked field,
**Save password**, **Clear**, and **Check sudo cache**. Saving places the
password in the operating system's Secret Service keyring under application
`alis-automation`, kind `sudo-password`, separate from GitHub tokens.
The password travels through one local stdin invocation to `secret-tool`;
it is never written into JSON, shell argv, GitHub, task prompts, worker
receipts or logs. Status returns only `saved`/availability, not plaintext.
Clear deletes this local keyring entry. The old one-shot
`sudo-authenticate` CLI remains for compatibility but is not the primary
Settings workflow.

**Saving does not grant permanent root mode.** Ordinary work runs as the
unprivileged Alis worker with `NoNewPrivileges=yes`. A separate, same-UID
broker may read the saved keyring entry **only after** receiving an
already SHA-pinned, owner-approved privileged operation, passing its service
allowlist, and recording the one-shot action intent. The broker checks
`sudo -n -v` first; only when the cache is absent does it attempt
`sudo -S -p '' -v` with local Secret Service input. The subsequent
allowlisted action still uses `sudo -n` and a strict timeout.

The current privileged operation set remains
`system-service-status` / `system-service-restart` for specifically
allowlisted systemd unit names. Configure the private local policy:

```json
{
  "units": ["example.service"],
  "authentication": "sudo-cache"
}
```

Replace `example.service` with a service explicitly approved by the
owner; this example **does not** add permissions on its own.
An empty allowlist, invalid policy, unavailable/locked keyring, invalid
password or unapproved task fails closed. The saved password cannot turn
an arbitrary GitHub Issue into a root shell. Broader administrator access
would require a distinct explicit scope and authorization design.

## Production scope

These features update source and offline CI on `dev`. They do not enable
native managed ChatGPT transport, switch Desktop UI mode, restart worker or
privilege services, add root privileges, change `stable`, or dispatch a job.
The existing service binaries must be safely updated by the owner before the
new command and broker protocol become available. Desktop cutover remains
on hold as requested.
