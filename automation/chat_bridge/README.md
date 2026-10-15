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
