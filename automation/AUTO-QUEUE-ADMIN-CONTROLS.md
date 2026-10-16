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

## Start UI is disabled: safe operator flow

**Start** stays disabled when a queue is `review_required` with no runnable
tasks. First use the blank-field **Recheck** action on the exact fully
parked manifest. An earlier `awaiting_cloud_ack` task must remain
**Ack pending**, and previously dispatched worker effects cannot be
replayed just to make the button active. At least one `queued` task and
a `prepared` ordered queue are required.

For a prepared queue, Alis checks the installed manager mode and its
first task's deterministic profile. The normal native ChatGPT transport
remains **server-receipt-gated**; an installed backend is not send
authorization. The alternate UI path is:

1. If Settings shows **Prepare UI**, click and confirm. This takes the
   exact full queue snapshot as a compare-and-swap token and creates
   only the first eligible task's **idle** profile. It does not send
   ChatGPT messages, Start/Stop a queue, start/restart the service,
   or rewrite previous task receipts. Profile staging is now permitted
   under an already-running `--ui-loop-queue` service (which cannot
   send a merely prepared queue), as well as an inactive manager.
2. Alis refreshes backend readiness after staging. When the installed
   `hadalis-chat-bridge.service` is **active** in
   `--ui-loop-queue` mode, the worker service is active, prior
   sessions are reconciled and the staged profile is idle, Settings
   offers **Start UI**. Clicking once shows the acceptance that
   ChatGPT response receipts are **local UI-only**, not authenticated
   server receipts. A second explicit confirmation grants ordered
   queue Start on that exact snapshot; it cannot bypass original
   pending/handoff checks.
3. If the bridge is **active in native or single-profile UI mode**,
   there is no safe one-click conversion. Settings now explains the
   actual blocker. A taskflow profile already present but holding an
   original pending send, local UI session, worker job or running state
   is also **not idle** and cannot be offered as Start-ready; its
   original evidence needs reconciliation first. Separately verify all existing sessions/jobs are
   settled and explicitly reconfigure the installer with
   `--ui-loop-queue` during a safe service cutover. Do not restart
   live services, reset unresolved sends or reuse historical receipts
   merely to unlock a button. Installing the unit alone does not
   change an already-running process mode.

The new `backend-status` response exposes bounded
`ui_queue_stage_available`, `ui_queue_service_mode`,
`ui_queue_service_state`, and `ui_queue_preflight_blockers` fields
for diagnosis. No private chat IDs, secrets or prompt contents are
included; no readiness check authorizes any delivery.

## Previously running profile still blocks Start

A queue can be **Ready** with eligible tasks while the UI-only Start gate
correctly rejects an unrelated old profile. Alis distinguishes:

- **Historical native chat only** — a stopped, idle/completed/disabled
  profile with no pending message, job, running intent, error recovery or
  removal. This session is preserved and does not itself block another
  queue. A session is *not* a pending Send receipt; saved native pending
  sends still block until reconciled.
- **Old default Automation profile scheduled but never sent** — if the
  original default profile is `desired=run` but has no pending Send, job,
  running action or uncertain recovery, the **active queue-only UI manager**
  cannot dispatch it. Settings may offer **Stop idle legacy**. Clicking
  and confirming revokes only this default profile's dormant schedule.
  The operation rechecks the exact full queue snapshot and the manager
  profile under its state lock. It preserves the entire old session,
  checkpoint, chat history, job/receipt files, and queued task records.
  No worker is killed, no ChatGPT message sent and no service restarted.
  Recheck backend status before using the separate **Prepare UI** and
  **Start UI** confirmations.
- **Genuinely unsettled old work** — a profile with a pending message,
  job, `run_active` state or other unmatched evidence. Start remains
  blocked. The status reply now includes redacted *counts* of scheduled,
  pending, job, native-session and harmless historical-session records.
  It does not include private conversation IDs or prompt data. Resolve
  the exact original evidence in the existing manager; do not Clear,
  re-pin or replay it simply to make Start available.

If the installed service is still **native** or **single-profile UI**,
an old schedule Stop cannot silently change its mode. Owner-approved
safe service cutover to `--ui-loop-queue` is separately required.
The installation on the Owner desktop and its live receipts must be
verified there; these source changes alone do not turn on Start.

## Bridge blocked after UI Queue safety exit (75)

An installed unit is not necessarily an active sender. Under
`--ui-loop-queue`, `ALIS_UI_*` safety failures exit with status **75**;
the installed unit uses `RestartPreventExitStatus=75`. Its service can
therefore remain **failed/blocked** after an earlier unsafe queue attempt,
even when the current queue has since become `prepared`. Normal
`backend-status` now includes the bridge's `exit_status`, `result`,
`ui_queue_bridge_recover_available`, and a privacy-bounded list of
unsettled profile **roles** and pending **transport types**. It never
returns conversation/message IDs, job tokens, profile names or prompts.

When the **queue-only UI unit** has specifically failed with status 75
and the exact ordered queue is still **prepared, unapproved and
inactive**, Settings offers **Recover Bridge**. The first click is a
warning; the second explicitly requests one `systemctl --user start
hadalis-chat-bridge.service` on the same exact queue snapshot. This
neither resets systemd's failure counters nor restarts an already active
service, changes unit mode, starts any queue, sends ChatGPT text, or
consumes/discards the previous pending record. If startup fails again,
inspect the local user service journal; the failed unit remains a gate.

**Important:** Bridge recovery is only one gate. A reported
`ui_queue_profile_counts.pending > 0` outside protected inert legacy
records is still an unresolved original send, even if
`native_unsettled=0` (for example a prior `alis-ui-once` UI attempt).
It must be reconciled with its exact first-send journal and local
receipt; there is no generic Clear Pending or force-start operation.
The new `ui_queue_unsettled_profiles` list shows only categorical
roles and booleans for identifying which class of work to inspect.

For host-side diagnosis without mutating services or queue:
```sh
python3 scripts/alis-automation-task.py backend-status
systemctl --user show hadalis-chat-bridge.service \\
  -p ActiveState -p Result -p ExecMainStatus
journalctl --user -u hadalis-chat-bridge.service -n 40 --no-pager
```
Review journal output for secrets or conversation details before
sharing it. A recent `journalctl` cause can differ from an old exit 75,
so do not infer the original failure solely from a saved unit status.

## Stopped original UI turn: redacted recovery preview

`python3 scripts/alis-automation-task.py backend-status` now includes
`ui_queue_pending_recovery_preview` for an ordered queue **stopping/stopped**
with its original active Issue still retained. It reports only the
public task code and bounded categorical readiness flags. It never
prints the original prompt, UUID attempts, conversation identifiers,
journal text, worker receipt body or digest.

A positive `read_only_observation_candidate` means only that the
**original saved** unique Alis request token, SHA-256 prompt integrity,
paused/stopped owner profile, pinned local UI first-turn key and original
send-journal command match without following symlinks. A live ChatGPT
observation still must prove the unique same-chat first/last continuity
and the full final assistant; afterward the original manager must
commit and archive that receipt under its existing no-replay locks.
**This preview is not an attestation, completed turn, pending clear, Start
button or authorization to send or run Localbot.** Installed Settings
will show the categorical reason during a stopped active queue.

If the journal is missing or mismatched, the pending is not eligible
for automatic observation-based acceptance. Inspect the original
private evidence and prior job receipts without altering them. An
empty/new installation should report `phase=not_eligible` without
initializing the manager or creating a scheduler profile. This check
is safe to repeat and does not reschedule the previously stopped
NOTES-F01 diagnostic turn.

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
