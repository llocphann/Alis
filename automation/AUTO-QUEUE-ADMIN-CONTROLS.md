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

## Clear queued tasks while the current task remains active

Settings → Automation → GitHub tasks → **Clear queued** → **Confirm clear**.

This action now explicitly removes **only entries with state `queued`**,
including when another item is `active` (for example AUDIO-I01). It does
not stop/modify the active item, reset its scheduler profile, cancel its
worker actions, approve any pending handoff, edit underlying per-task JSON,
or remove any receipt. Previously completed entries and current
active-task identity/selection stay exactly as they were.

The UI may retain a last-known queue snapshot if `queue-status` failed.
For cleanup only, it can still offer **Clear queued**, since the helper
requires the exact displayed `repository:task-code` sequence in
`--expected-queued` and rechecks it under the **exclusive queue.lock**.
If the live queue has changed, no mutation occurs; refresh and confirm again.
Unlike Start, cleanup never accepts a stale snapshot as dispatch authority.

Before any change, the complete original manifest is archived under the
private legacy-XDG `hadalis-automation/taskflow/queue-history/` directory.
The legacy path is for migration compatibility, not product naming.
For an active queue, only queued entries are removed and the new manifest
remains `active`. For an undispatched prepared queue, the original manifest
is moved to history and the UI queue becomes empty. An approved selector,
`waiting` mode, an unverified active-task identity, or active/uncertain
job phases fail closed instead of cancelling anything. All GitHub queues
and worker receipts are outside the scope of this UI operation.

No installed service or local task inventory has been changed merely by
committing this feature; the owner must first update the running Alis UI
and Python source to expose it.

## Optional sudo password

Settings → Automation → **Administrator access** uses a masked one-time
password field. Only when the owner clicks **Authorize** is the password
transferred to `alis-automation-task.py sudo-authenticate` via ephemeral
standard input. It is passed over a same-UID, mode-0600 Unix socket to the
already-installed `hadalis-privilege.service` broker. That broker invokes
`sudo -S -p '' -v` with a single input; no password appears in command-line
arguments, settings files, GitHub, receipts, logs, or process environment.
After submission the Settings buffer is cleared. **Check** consults the
broker's own noninteractive sudo cache, with no password. The cache may
expire according to host sudo policy. No permission is implied by a
successful UI form alone.

**This is not blanket root access.** Existing worker
`NoNewPrivileges=yes` stays enabled. The broker authorizes only its
preconfigured `system-service-status` and `system-service-restart`
operations for specifically allowlisted `*.service` names. Owners can
configure locally using the existing private
`~/.config/hadalis/automation-privilege.json` policy:

```json
{
  "units": ["example.service"],
  "authentication": "sudo-cache"
}
```

Replace `example.service` with an actual, explicitly approved service;
this JSON is a documented **example**, not a default grant. An absent or
empty allowlist, failed broker, or polkit-only policy makes the password
field fail closed. Never add an arbitrary `exec` privilege or forward the
password through the AI agent's prompts and GitHub handoffs. Root-capable
actions still require individual pinned-job authorization and durable
one-attempt receipts.

## Production scope

These features update source and offline CI on `dev`. They do not enable
native managed ChatGPT transport, switch Desktop UI mode, restart worker or
privilege services, add root privileges, change `stable`, or dispatch a job.
The existing service binaries must be safely updated by the owner before the
new command and broker protocol become available. Desktop cutover remains
on hold as requested.
