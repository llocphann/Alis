# Alis Chat Bridge

ChatGPT is the only reasoning agent. This layer transports explicit objectives and interprets only loop directives. Worker commands and code decisions come from ChatGPT; GitHub is authoritative for repository state. Session IDs, Desktop state, raw logs and credentials stay private locally.

Production uses `native_adapter.mjs` and `native_cli.mjs`, called by `automation.manager.daemon`. The adapter probes installed Desktop renderer capabilities, uses its authenticated HTTP/stream service and never reads auth tokens or cookies. Conversation/user-message identity drives polling independently of the selected chat, composer, project and UI toolbar. There is no DOM, keyboard, navigation or coordinate fallback for managed sessions. Unsupported builds fail closed before submission. Legacy DOM/controller modules remain for compatibility tests, not as the production scheduler.

Repository profiles carry the literal `[@GitHub](plugin://github@openai-curated-remote)` mention and require current dev, AGENTS.md and verified GitHub access. The native request binds the exact enabled GitHub plugin capability. Generic non-repository profiles may disable that requirement. All profiles stay in ChatGPT without switching or handing off to Work.

A final assistant message must belong to the exact submitted user turn, have successful terminal status and end_turn, and contain exactly one final directive:

```
HADALIS_LOOP:WAIT_RESULT JOB-000127
HADALIS_LOOP:CONTINUE
HADALIS_LOOP:ROTATE
HADALIS_LOOP:DONE
HADALIS_LOOP:CONNECTOR_BLOCKED GITHUB
```

The Python protocol validates the marker. Streaming text, tool steps, user prompts and replies from another user turn cannot complete a receipt. The scheduler saves submission intent before IPC and completion before continuation. An ambiguous send only permits observation of its original message ID. Read-only stream reattachment does not create a user message or a new generation. A server-proven terminal failure can schedule a distinct reconciliation step; it never replays uncertain effects. Project/conversation IDs survive Desktop restarts and reboot. Independent profiles progress through a bounded scheduler and resource-specific leases.

See automation/manager/README.md and docs/AUTOMATION_ARCHITECTURE.md for migration, checkpoint, recovery, evidence and acceptance contracts. Run `node scripts/test-hadalis-native-session.mjs` for message projection behavior; `HADALIS_TEST_INSTALLED_DESKTOP=1` also probes the installed adapter contract. Real acceptance is opt-in and never changes production profiles.

## Alis protocol redesign (2026-10-15)

The canonical loop directives for new prompts are ALIS_LOOP:CONTINUE,
ALIS_LOOP:WAIT_RESULT JOB-..., ALIS_LOOP:ROTATE, ALIS_LOOP:DONE and
ALIS_LOOP:CONNECTOR_BLOCKED GITHUB. The parser still accepts historical
HADALIS_LOOP directives from saved conversations for lossless migration.
Worker handoffs and receipts stay on GitHub with SHA-pinned job identities.
The legacy UI path now uses an fsynced, one-shot send journal and never
falls back from a click to Enter/CDP/Wayland resubmission. Any uncertain UI
send stops and preserves its intent for reconciliation, not replay.

The installed manager still uses the native adapter. The UI loop is not
silently activated by this change; its Desktop binding needs separate owner
acceptance. Existing hadalis-* service and XDG names are legacy compatibility
aliases only, not Alis product branding.

### Explicit single-owner UI scheduler

The existing `automation.manager.daemon` now has a separate
`--ui-loop-profile PROFILE_ID` option, using the **same**
`chat-bridge.lock` as native manager mode. Installer option
`--ui-loop-profile PROFILE_ID` generates that command in the existing
`hadalis-chat-bridge.service` unit; its default remains native mode.
Installing a unit **does not** start a profile, release a job, approve
a handoff, restart the running service or switch modes in memory.
Operators must opt in deliberately after checking no native pending
messages, unowned profile work or journal tombstones remain. Running
native and UI mode simultaneously fails via the exclusive lock.

The opted-in UI profile must already be enabled and explicitly started
using the existing profile controls, and its configured Project must
match the UI target Project. Only one enabled/running profile may own
the UI. This is a conservative single-owner mode, not the native
multi-profile concurrency feature.

The UI scheduler stores a `transport:alis-ui-once` pending intent inside
the existing durable manager state *before* attempting the Desktop
subprocess. It then invokes the bridge's fsynced UI journal and one-shot
Send. On completion, a private local UI response is written before
clearing the pending manager entry. After any crash, timeout, ambiguous
response or missing selected-chat identity, the profile is paused
with pending evidence intact; a restart cannot send it again.

The selected Project **alone** is not enough: the Desktop driver must
read a unique selected chat ID/conversation href and pin a local
SHA-256 fingerprint. Each subsequent continuation checks the exact
same fingerprint **before** filling the editor. Unknown/changed
UI structure is a hard stop, not permission to use a different chat.
The fingerprint is a UI continuity hint, not a server-authenticated
ChatGPT receipt.

`WAIT_RESULT` only resumes when the result belongs to the exact
profile, job ID, SHA-256 and settled status. Existing ownerless jobs,
including old smoke jobs, cannot awaken a different Alis profile.
After `DONE`, this mode stops even if the historical profile was
configured for continuous research.

**Still required before unattended production:** explicit installed
Desktop acceptance proving the UI provides a stable unique selected-chat
identity in the current renderer; safe switch/rollback between modes
with all existing receipts and native message intents preserved.
Do not delete `ui-send-journal/pending.json` manually or treat a
visible reply as proof of server-side identity. Current
`automation.transport_gate` for native managed task queue remains
closed and has not been bypassed.


### AUTO-F01 ordered Queue -> UI-only loop (owner opt-in)

The queue-only transport is separate from `--ui-loop-profile` and the
server-attested native gate. It is not a replacement for real installed
Desktop acceptance. Default installation stays native; no unattended message
is sent by installing or preparing a profile.

- `python3 scripts/AUTO-F01-ui-preflight.py --queue` is read-only. The
  first SHA-pinned task owns its own deterministic taskflow profile; do not
  start an unrelated enabled generic Automation profile.
- A disabled and explicitly stopped **generic legacy native** profile with a
  native pending message and session, but no job, may remain in the local
  manager state while the alternative UI scheduler operates. Its original
  pending/session/run-active evidence is **not erased, adopted, completed, or
  replayed**. Enabled, running, job-waiting, missing-config, taskflow, and
  ambiguous legacy profiles remain blocking. Native and UI managers share
  the same exclusive `chat-bridge.lock` and cannot run simultaneously.
- After owner review and **stopping the native bridge service** (not the
  worker), stage the first exact queue member:
  `python3 scripts/alis-automation-task.py queue-stage-ui --approve --expected-first llocphann/Alis:AI-I01`.
  This command only creates idle profile metadata; it does not claim
  `AI-I01` or change the six-item queue.
- Only after separately checking the installed Desktop and accepting the
  limitations, install the *alternate* bridge mode with
  `python3 scripts/install-hadalis-automation.py --ui-loop-queue`
  (without `--enable-now` or `--reset-session-state`), then explicitly
  start `hadalis-chat-bridge.service` under systemd user. These actions
  modify/restart local services and require the machine owner's consent.
  `node automation/chat_bridge/desktop_cli.mjs ui-target-check` provides a
  strictly read-only UI identity observation, NOT acceptance to send.
- For an **idle, prepared, ordered** queue, a healthy UI queue service, an
  exact staged profile and unchanged pinned first Issue, Settings offers
  **Start UI -> Confirm UI Start**. The equivalent *explicitly owner-approved*
  CLI is `python3 scripts/alis-automation-task.py start-ui-queue --approve --accept-ui-only-receipts --expected-first llocphann/Alis:AI-I01`.
  It records Start approval, claims only one task and schedules the exact
  profile. Neither method uses or bypasses the native `start-queue` gate.
- Each UI turn first persists a no-replay send intent, pins the UI chat
  fingerprint, and requires a completed assistant-only `ALIS_LOOP` response.
  The queue moves to the next task only after a matching private response
  receipt, `DONE`, exact profile, SHA and preserved owner Start. Receipts are
  explicitly tagged `attestation=local-ui-only`: **not server-confirmed
  conversation/message IDs**. An unknown or changed chat pauses further sends.
  Stop revokes next-task admission; an already persisted in-flight UI intent
  remains for review rather than silently retried.
- To roll back, use the normal Stop Queue confirmation, inspect pending UI
  send journals, then stop the UI bridge. Switch the installed unit back to
  native mode only after explicit reconciliation; do not clear
  `ui-send-journal/pending.json`, the historical native profile, any worker
  receipt or the queue manifest to make a green status.

This implementation has offline safety/logic CI. It does **not** certify
the real installed Desktop's exact composer/selected chat UI, a successful
live assistant response, server-side receipt identity, uninterrupted
unattended publication, or full native↔UI↔native host acceptance.
The owner must verify these on their installed host before relying on
unattended operation. `stable` is unaffected.

### AUTO-F01 one-command, owner-approved harmless Desktop smoke

If the exact `Automatic Alis` Project entry or its sidebar **New chat**
action is visible, the owner can perform a single bounded smoke test without
three separate manual commands:

```bash
node automation/chat_bridge/alis_ui_smoke_cli.mjs --owner-approved
```

This does **not** start the six-item Automation Queue. It navigates to a
fresh Project-scoped editor when needed (one exact Project-specific click,
**preserving any unrelated pre-existing draft**), requires one unique
**exact Project-scoped empty composer AND exact Project badge** with a
disabled Send and no selected target chat. A Project sidebar chat list may
be hidden/collapsed (count 0) on the new-chat landing; an ambiguous list
(count >1) is forbidden. The list's absence alone never authorizes a send.
The smoke writes an immutable
private acceptance journal, fills **only** the fixed harmless prompt and
clicks Send at most once. Afterward, it polls for roughly 9 seconds and
requires an assistant-only `ALIS_LOOP:DONE` turn and a stable UI chat key.
It emits one redacted JSON summary and never treats the `ALIS_LOOP:DONE`
inside the user prompt as assistant evidence.

The smoke journal uses a **fixed ID** across runs. If the journal has already
been written, rerunning cannot send a second smoke message. In particular,
`status=sent_unverified` or a timeout is **not** permission to rerun,
change the ID, reset the journal, or invoke the separate legacy acceptance.
All receipt booleans for server attestation and manager/queue authority
remain false even when a local UI reply is observed.

The command does not modify Native profiles, worker receipts, queue state,
service installation, or the Desktop's unrelated draft. After a single
Project navigation click it now allows roughly **3.2 seconds** for the
renderer to settle and requires **two consecutive** Project-scoped idle
checks before any composer fill. If the UI remains unverified, the
single-command result includes `post_navigation_diagnostics` (bounded
counts and categorical states only, including a pending dialog count), not
private chat text or titles. A modal dialog always blocks any Send. A failed
navigation is not retried. If the reply is still pending, inspect the Desktop manually;
the bounded read-only probes can be run later without sending. An
`AMBIGUOUS_VISIBLE_HARMLESS_MESSAGES` legacy whole-page count is not proof
of two sends: the text `ALIS_LOOP:DONE` also appears in the user instruction.
This smoke uses an assistant-turn extraction to avoid that false positive.

Once the owner sees the fixed harmless prompt and the assistant-only
`ALIS_LOOP:DONE` reply, **do not repeat the smoke** (the private attempt
journal is immutable). To diagnose a missing UI conversation ID without
another send, use:

```bash
node automation/chat_bridge/desktop_cli.mjs ui-session-inspect
```

This is read-only and emits a single redacted JSON. It distinguishes an
exact selected chat inside the Project's chat list, a global selected chat
whose Project membership is unverified, and a Project-scoped editor with no
selected chat key. No raw chat IDs, title, URL, href, prompt or draft are
printed. Even if its sampled accessibility counts are unchanged, it never
asserts server identity, a stable chat ID or UI Scheduler permission by
itself. Do not confuse `PROJECT_SIDEBAR_CHAT_KEY_OBSERVED` with the stronger
two-sample raw-key equality in `ui-target-check`, which is still required
for any managed continuation. A missing sidebar identity is not solved by
re-sending the already accepted smoke prompt.

For **future owner-approved harmless tests**, the same single-command smoke
now also captures `post_send_chat_key_witness` **inside its original Send
process** as soon as it observes the assistant-only reply. It compares
actual UI chat keys across two read-only samples, returning one of
`PROJECT_CHAT_KEY_STABLE_LOCAL_ONLY`,
`GLOBAL_CHAT_KEY_STABLE_PROJECT_UNVERIFIED`, or
`CHAT_KEY_MISSING_OR_CHANGED`. Project-sidebar proof still requires the
strict `uiTargetIdentity` verification before
`selected_chat_identity_stable=true`; an unbound global chat ID never
allows Scheduler/Queue activation. No raw ID, chat title, URL or prompt
content is exposed. A deleted conversation cannot be retrospectively
sampled: the already-spent immutable smoke ID MUST NOT be reused or reset.
Any future live test message requires separate owner consent. The existing
six-item queue and service configuration are unaffected by this work.

### Read-only cutover diagnosis (operator side)

Inspect the installed host **without submitting any message or changing
systemd**:

```bash
python3 scripts/AUTO-F01-ui-preflight.py strict-lossless-research
node automation/chat_bridge/desktop_cli.mjs ui-target-check
```

The first command reads existing manager configuration/state and the
installed bridge unit, without using the manager transaction lock (which
may perform recovery writes). It returns redacted booleans and categorical
blockers only. A still-active native bridge, pending/native sessions,
profiles scheduled to run, any outstanding job, another profile's work,
or a UI journal tombstone all **block** cutover. A positive local result
is **not** authorization to restart the unit or send a prompt.

The second command uses an existing Desktop CDP connection **read-only**.
It separates two distinct states without exposing a chat title, ID, href,
fingerprint, draft or private DOM content:

- `selected_chat_identity_stable=true` and
  `diagnosis=ALIS_UI_CHAT_TARGET_OBSERVED`: an **existing selected chat**
  in the exact Project list has a stable unique UI ID across two samples.
  This is a UI continuity hint, not server attestation.
- `selected_chat_identity_stable=false`,
  `empty_project_entry_ready=true` and
  `diagnosis=ALIS_UI_EMPTY_PROJECT_ENTRY_OBSERVED`: the exact
  Project-scoped composer is demonstrably empty and idle, with no selected
  conversation yet. This is expected when entering an empty Project before
  the first message. It is **not** selected-chat identity and does **not**
  authorize a send.
- Both booleans false: the target is unverified (different Project, generic
  unscoped editor, changed renderer, existing chat with missing ID, draft,
  ambiguity or busy UI). The same read-only command now returns
  `target_diagnostics`, containing **only** category/count/boolean signals
  (Project view/landing, composer scope, selected-chat count, draft-present
  flag, generation-busy flag and readiness-issue codes). A visually labeled
  empty Project landing with an unscoped generic composer is reported as
  `ALIS_UI_PROJECT_LANDING_COMPOSER_UNSCOPED`, **not** an authorized empty
  Project editor. Missing selected-chat IDs are separately reported as
  `ALIS_UI_SELECTED_CHAT_KEY_MISSING`. If the sidebar includes exactly
  one `New chat in Automatic Alis` action while the current composer is
  generic and idle, `ALIS_UI_PROJECT_NEW_CHAT_NAVIGATION_REQUIRED` gives
  the human-only next step: **click the Project-specific New chat button**
  inside ChatGPT Desktop and rerun `ui-target-check`. Simply opening the
  Project sidebar does not redirect the current composer. For the exact
  idle, draft-free sidebar-only condition, an **optional, explicit**
  *navigation-only* command is also available:
  `node automation/chat_bridge/desktop_cli.mjs ui-project-enter --approve-navigation`.
  It requires local CDP, uniquely identifies the Project's new-chat action,
  performs at most **one DOM navigation click**, never types/sends and
  never changes the queue or credentials. It returns either
  `ALIS_UI_EMPTY_PROJECT_ENTRY_OBSERVED` or an unverified/blocked
  categorical result. An unverified result is NOT reason to click blindly
  again: inspect the Desktop UI or share a redacted screenshot before
  continuing. Navigation alone neither creates an authorized message nor
  proves a server-side Project ID. Do not work around these checks by
  picking a random chat, replacing an unresolved journal or weakening the
  pinned target guard.

The read-only checker never sends a message. Initial UI Queue sends must
still be explicitly owner-approved, retain a durable one-shot intent, and
obtain a unique Project chat ID after the response before any continuation.
An initial message whose target remains unidentified stops for reconciliation,
not a replay. All results explicitly deny server identity attestation and
scheduler submission authority.

A new Alis UI send must also see an assistant-only completion: a **new**
response toolbar plus exactly one `ALIS_LOOP` directive extracted from
the associated assistant message container. Counting markers in the page
body is insufficient because the prompt itself can contain examples.
Missing toolbars/assistant containers block continuation, not fall back
to an ambiguous marker.
