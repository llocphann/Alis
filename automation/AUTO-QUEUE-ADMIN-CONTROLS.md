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

## Clear Queue

Settings → Automation → GitHub tasks → **Clear queue** → **Confirm clear**.
The helper requires `queue-clear --approve`, performs the mutation under
the exclusive queue flock and archives the original manifest privately in
`~/.local/state/hadalis-automation/taskflow/queue-history/`. The path is a
legacy migration alias, not product branding.

The operation is accepted only when a queue is undispatched/idle, or is
already terminal and has no active/queued work. It refuses an approved
selector, an active or waiting queue, a claimed task, a task with an active
handoff, unresolved work or existing job receipts. Individual task records,
historical results, worker receipt inventory, GitHub queue files, pending
AUDIO-I01 payload and worker services are never deleted or cancelled by
Clear Queue. An archive remains for audit/restore; this UI action never
automatically resumes an archived queue.

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
