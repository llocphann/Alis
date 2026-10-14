# AUTO-F01 — Native transport acceptance and fail-closed decision

Status: **BLOCKED** — diagnostics are read-only, no submission authorized.
Target: `llocphann/Alis`, branch `dev`; preserve Project **Automatic Alis**, all 18 queued tasks, reserved `AUDIO-I01`, dispatch intents and response receipts.

## Installed Desktop observations (owner-provided)

- Installed renderer asset fingerprint prefix: `8ff0fd9c4b19`. Do not assume it matches another installed build.
- One exported scope definition and resolver source uniquely located in `app-shared`. Both static helper declarations are unique, distinct and bounded. **This proves syntax relationships only.**
- Seven distinct active React context Maps share one provider identity. Their key sets/entries differ; some are incomparable. `provider_selection = active_provider_ambiguous`; selecting the first match, deepest map, largest map or shared provider identity is **not** a valid transport binding.
- The resolver's cache-miss branch contains method calls including a write-like cache path. Its secondary helper has a syntactic `new Map` with no parentheses and then a Map-like write; local/module/closure constructor identity and effects remain unverified. Neither these facts nor the absence of detected helper-local Map shadowing prove a pure resolver.
- `resolution_attempted = false`. Keep it false for read-only diagnostics.
- `supported = false`, `submission_authorized = false` and no successful ChatGPT Desktop native stream or accepted assistant receipt is established by these diagnostics.

## Acceptance evidence required *before* enabling any managed submission

1. **Supported capability boundary:** A documented, stable interface which supports the intended ChatGPT Desktop account, project and conversation, with a compatibility/provenance check tied to the installed build. Unpublished minified exports, raw React Fiber Maps, cache side effects and guessed provider nodes cannot satisfy this requirement.
2. **Unique transport binding:** Resolve exactly one valid transport by a verified API contract, not by choosing one of the seven Maps by tree depth/size or by executing a possibly mutating `definition.resolve()` in a probe.
3. **Project/chat identity:** Authoritatively verify the exact Project ID *and membership of the target conversation* before any action. Project display-name matching, visual selection or a guessed conversation ID is not sufficient. Preserve and revalidate identity after chat rotation.
4. **Durable intent and receipt chain:** Persist dispatch intent with deterministic user message ID before any possible send; verify response belongs to that exact user turn and is terminal. On uncertain outcomes, only reconcile the original identity — never send again, regenerate, replay or repurpose a job ID.
5. **GitHub capability and local worker segregation:** Only the ChatGPT reasoning agent determines prompts and decisions. The local worker executes deterministic jobs and reports bounded evidence. GitHub capability must be tied to the intended task; no token, credential or message body may appear in a diagnostic report.
6. **Explicit owner-approved acceptance testing:** Offline/mock and GitHub CI can prove guard behavior; they cannot prove live transport. Require a separately planned, consented end-to-end acceptance procedure that preserves queued work and a verified rollback path. Until then no production activation.

## Product boundary: ChatGPT Projects vs OpenAI API Platform projects

Do **not** equate the owner's ChatGPT Project `Automatic Alis` with an OpenAI API Platform project. API Platform project endpoints manage organization/API access, service accounts, usage and budgets; they are not an attested method to append a user turn to an existing ChatGPT Project conversation. The ChatGPT Projects help article describes conversations, files and project instructions in the ChatGPT product; the distinct API Platform projects article describes API resource administration.

Official product references:
- https://help.openai.com/en/articles/10169521-using-projects-in-chatgpt
- https://help.openai.com/en/articles/9186755-managing-projects-in-the-api-platform

A future API-backed alternative would be a **separately authorized product architecture** with explicit migration, different conversation identity, key management and usage/cost semantics. It must not silently claim continuity with `Automatic Alis` or revive the 18 current queued jobs.

## Documented integration surfaces reviewed (direction matters)

OpenAI's documented ChatGPT Desktop site tools allow **ChatGPT to operate a website** that exposes tools in its built-in browser (WebMCP). Connected apps/plugins likewise expose supported external service actions *to ChatGPT*. These descriptions are **not an authenticated inbound transport** through which an external local scheduler can append a turn into an existing consumer ChatGPT Project conversation.

Sources reviewed (2026-10-15):
- https://help.openai.com/en/articles/20001423-using-site-tools-in-the-chatgpt-desktop-app
- https://help.openai.com/en/articles/11487775-connected-apps-in-chatgpt
- https://help.openai.com/en/articles/20001277-using-the-built-in-browser-in-the-chatgpt-desktop-app

This comparison does not establish that *no* alternative exists. It establishes that these particular public documents do not provide the required inbound, receipt-attested existing-Project chat transport. Do not treat an MCP app, site tool, desktop automation UI or API Platform project as a drop-in replacement.

## Reconciliation ambiguity discovered in the existing adapter

Static review of `automation/chat_bridge/native_adapter.mjs` found `discoverSubmission()` scans a bounded list of recently updated conversations and **returns the first conversation containing the pending `user_message_id`**. That procedure does not enforce cross-conversation uniqueness, require the message to be on the current active branch, or independently attest ChatGPT Project membership. A positive hit is therefore **not** a proven delivery receipt or authorization to dispatch a new message. This is a **code-level gap**, not evidence that any live user message was misdelivered.

New independent, offline-only audit:
- `automation/chat_bridge/reconciliation_evidence.mjs` — classifies exact message-ID matches on the current parent chain, duplicate conversation IDs, collisions across conversations, inconsistent pending IDs and corrupt snapshots. It returns categorical evidence only and always `submission_authorized:false` and `project_membership_verified:false`.
- `scripts/test-hadalis-reconciliation-evidence.mjs` — synthetic fixture tests with private content redacted.

This independent audit is **not connected to the production adapter**; integrating the check requires an authenticated transport and known Project/chat membership source. Never use the match status to re-send an indeterminate `user_message_id`.

## Final-turn receipt confusion in the existing projection

Static inspection of `projectTurn()` in `native_adapter.mjs` found two distinct acceptance gaps: it locates the pending user turn using **message ID OR branch node ID**, without requiring that the matching message has the `user` role; and `activeBranch()` may stop silently when an ancestor is missing or the chain is cyclic. Those are unsafe assumptions for a durable response receipt. They remain unproven live failure causes; this is source-level review only.

New *independent* offline shape checker:
- `automation/chat_bridge/receipt_evidence.mjs` requires a syntactically exact conversation ID and user-message ID, a complete and acyclic parent chain, exactly one matching user-authored message on the current branch, exactly one terminal assistant final response before the next user turn, and an optional exact assistant receipt ID match. All outcomes remain `blocked`, because input snapshot provenance, Project membership and transport capability have not been attested.
- `scripts/test-hadalis-receipt-evidence.mjs` includes forged node-ID, wrong-role, incomplete/failed tool response, next-turn, duplicate final/user and malformed parent-chain fixtures. No message, Project or conversation payload is emitted.
- `node scripts/test-hadalis-receipt-evidence.mjs` is offline only and integrated in the native fail-closed CI step.

**Do not** wire this checker into `native_adapter.mjs` while transport is unsupported. After an authenticated source is available, require both *single conversation matching* and *single final-message matching* before projecting a receipt; a reported match in unverified offline data is never proof of send success.

## Independent diagnostic ledger

`automation/chat_bridge/transport_evidence.mjs` classifies **redacted scope evidence** into categorical blocker codes. The read-only inspector adds it as `transport_evidence`. The ledger **always** returns `status: "blocked"`, `supported: false` and `submission_authorized: false`; it is *not* a capability bridge, a resolver, an API key checker or an escape hatch. Flags copied from user input, mock fixtures or static helper matches cannot authorize submission.

Test: `node scripts/test-hadalis-transport-evidence.mjs`. A passing synthetic test means only that the diagnostic guard stays closed. It does not establish connected-app state, runtime project identity, actual Desktop responses or a working native bridge.

## Adaptation track: historical Playwright/CDP UI transport

**Owner direction (2026-10-15):** adapt toward the old UI-based Desktop connection because it has a real positive historical receipt. At historical revision `0d05092faeb8`, `automation/results/JOB-DESKTOP-LIVE-ACCEPT-013.json` reports `status:passed`, `exit_code:0` for `scripts/test-hadalis-live-transport.mjs`, one new post-submit `HADALIS_LOOP:DONE` marker and `generation.completed:true`. Earlier jobs 009–012 had failed syntax, repeated marker, timeout and extraction checks, respectively. This proves one historical smoke-test dispatch/completion, **not** robust receipt identity or compatibility with the currently installed Desktop.

**Source adaptation on `Alis/dev`:**
- `legacy_ui_probe.mjs` reads the accessible ChatGPT Desktop main-renderer UI through the same historical Project/composer/Send/Stop semantics. It never reads raw prompt, account data, selected chat titles, project IDs, assistant messages or credentials. It reports only booleans and capped counts and **never** executes React resolver, clicks, keyboard actions, network fetches or sends.
- `legacy_ui_probe_cli.mjs` is an opt-in **read-only** Playwright/CDP probe on loopback, separate from the native transport CLI. Its command surface supports `probe` only. A UI Project badge or selected Project chat list counts as a **visual guard** but does **not** verify the true server Project/conversation ID.
- `legacy_ui_acceptance.mjs` is an **isolated, owner-approved harmless-test primitive**, NOT imported by a CLI or Scheduler. The caller must supply an acceptance ID and a durable/no-replay `persistAttempt` hook. It checks UI readiness, persists the attempt **before modifying any UI**, fills only a fixed harmless acceptance prompt and attempts exactly **one** Send click. It never falls back to Enter, alternate buttons or a retry; any result (including a successful click) stays `indeterminate` until independently observed. It is not an authorization path for any of the queued GitHub tasks, and no live acceptance has been executed.
- `scripts/test-hadalis-legacy-ui-probe.mjs` and `scripts/test-hadalis-legacy-ui-acceptance.mjs` are offline mocks included in the native fail-closed CI gate. They prove only selector/guard behavior and a single-attempt invariant, not end-to-end Desktop continuity.

**Current boundaries and next tests:**
1. Confirm *read-only* compatibility on the owner's installed Desktop by running `node automation/chat_bridge/legacy_ui_probe_cli.mjs probe` after exact-head CI safety tests PASS. The result must not contain text or IDs and will **never** authorize a send.
2. Separately obtain explicit owner approval to run **one harmless manual acceptance** in an intentionally empty managed test chat; use a fsynced private journal and preserve its indeterminate outcome until reconciled. Never run the historical multi-fallback `desktop_cli.mjs managed-submit` in the live queue.
3. Independently verify whether the installed UI or another documented supported interface can associate a clicked Send with one exact server `user_message_id`, ChatGPT Project membership and one terminal assistant receipt. Without this proof, the UI fallback may only support *assisted/manual* testing, not unattended queue execution or chat rollover.
4. Preserve the existing native adapter as an isolated unsupported source path; only an explicitly accepted, proven UI transport may eventually replace the manager's send/poll route. Restarting Scheduler or migrating the 18 pending tasks is **not part of this change**.

## Explicit exclusions

No `definition.resolve()` invocation; no native `submit`/CLI submit, DOM/click/keyboard/UI fallback, transport injection, speculative `native_adapter.mjs` modifications, scheduler start/reset, queue replay, chat rotation or attempt to choose between the seven Maps. The next engineering investigation should evaluate available **supported transport capabilities** and exact identity/receipt requirements separately from the private bundled React implementation.
