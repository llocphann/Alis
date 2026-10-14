# Hadalis Chat Bridge

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
