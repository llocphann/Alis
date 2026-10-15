# AUTO-F01 — Native transport acceptance and fail-closed decision

Status: **UI SMOKE ACCEPTED; MANAGED TRANSPORT BLOCKED** — one owner-approved harmless UI click visibly produced a response, but server-attested Project/conversation/message identity and durable receipt are unverified. Scheduler submission remains unauthorized.
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
- `legacy_ui_acceptance.mjs` is an **isolated, owner-approved harmless-test primitive**, NOT imported by a CLI or Scheduler. The caller must supply an acceptance ID and a durable/no-replay `persistAttempt` hook. `legacy_ui_journal.mjs` supplies one such local, private, fsynced write-ahead journal with atomic no-replay file creation (`wx`), bounded metadata and no prompt body. It checks UI readiness, persists the attempt **before modifying any UI**, fills only a fixed harmless acceptance prompt and attempts exactly **one** Send click. It never falls back to Enter, alternate buttons or a retry; any result (including a successful click) stays `indeterminate` until independently observed. It is not an authorization path for any of the queued GitHub tasks, and no live acceptance has been executed.
- `legacy_ui_acceptance_cli.mjs` is a **separate owner-approval-only CLI**, requiring an exact `--owner-approved` flag plus a UUID. It accepts no arbitrary prompt, task code, Project ID or queue action. Even after a harmless Send click it exits nonzero with `indeterminate`, and trying the same UUID again is blocked by the fsynced journal. **It has not been run against a real Desktop and must not be invoked without separate owner approval for the harmless acceptance test.**
- `scripts/test-hadalis-legacy-ui-probe.mjs` and `scripts/test-hadalis-legacy-ui-acceptance.mjs` are offline mocks included in the native fail-closed CI gate. They prove only selector/guard behavior, refusal of implicit acceptance, no token leakage and the single-attempt invariant, not end-to-end Desktop continuity.

**Read-only installed-Desktop observation (owner, 2026-10-15):** The first live UI probe returned `renderer_matches:true`, one visible empty enabled composer, one visible `Chats in Automatic Alis` list, **no selected Project chat**, **no visible Project badge**, **no Send control**, and no active Stop button. This proves the legacy CDP renderer and accessibility querying worked; it does *not* prove that the generic editor is currently scoped to `Automatic Alis`. Absence of Send on an empty editor may be normal in newer builds. Do not click Send or auto-navigate based on this snapshot.

The read-only probe now separately counts a composer with the **exact accessible name** `New chat in Automatic Alis`. Only that exact scoped label (or the preexisting unique badge/selected-chat guard) can establish visual Project context; an open sidebar alone cannot. When an empty uniquely scoped Project composer hides Send, the report has `read_only_project_entry_ready:true` and a categorical `SEND_ABSENT_ON_EMPTY_PROJECT_COMPOSER` observation while `observation_ready:false`, `submission_authorized:false`, and all server identity/receipt proofs remain false. This is not permission for a harmless test or live queued task send. No UI actions are performed by the probe.

**Owner-provided Desktop screenshot (2026-10-15):** The visible application is already on the **`Automatic Alis` Project landing page**, with `Automatic Alis` selected in sidebar and shown as a large central title, a composer bar containing a visual Project chip and `New chat in Automatic Alis` label, and `No chats yet` / `Chats in Automatic Alis will live here` empty-state text. A green up-arrow send-shaped control is visible at the right of the composer even though the text editor is empty. The accessibility report nevertheless showed **two** main regions, **zero semantic Project headings**, **one generic accessible textbox**, **zero controls exactly named `Send`**, **zero selected chat**, and an available Project new-chat action. This combination reveals **accessibility-selector mismatches**: the visual title need not be ARIA `heading`, the Project composer label need not be the editable textbox's accessible name, and the send-shaped icon need not have accessible name exactly `Send`. **Do not equate zero selected chats with wrong Project on an empty Project landing.**

[`legacy_ui_probe.mjs`](./legacy_ui_probe.mjs) now counts **fixed, exact text** (the intended Project label, `No chats yet`, and `New chat in <Project>`) *inside accessible main regions* separately from semantic heading and textbox-name matches. It produces bounded counts, `project_landing_visual_evidence` and `project_composer_visual_label_observed`. A corroborated landing is **visual context only**; it does not promote `project_view_visible`, `observation_ready`, `project_identity_verified`, `submission_authorized` or Scheduler activation. The send-shaped control remains unverified; do **not** guess its selector or click it based on the screenshot. Test fixtures model this exact empty landing and preserve all no-send invariants.

**Owner's installed Project landing recheck (2026-10-15, later):** The read-only snapshot now conclusively identifies the expected **visual Project landing controls**: one exact Project-scoped editable textbox (`project_scoped_composer_count_capped:1`), one exact Project badge, one Project heading, two literal Project labels inside two visible `main` regions, the `No chats yet` empty state, zero selected conversation, **one visible Send control with `send_disabled:true`**, and zero Stop. `project_landing_visual_evidence:"project-empty-landing-corroborated"` and `project_view_visible:true`. This corrects the earlier uncertain accessibility matches: the Desktop's accessible UI appears to have stabilized on the Project landing, and `Send` exists but is *disabled because the editor is blank*. Two main regions and the missing separate composer-visual text node no longer need to be used as a reason to assume navigation failed.

[`legacy_ui_probe.mjs`](./legacy_ui_probe.mjs) classifies **one disabled Send button on exactly one empty Project-scoped composer** as `SEND_DISABLED_ON_EMPTY_PROJECT_COMPOSER` and `send_control_state:"disabled-on-empty-project-composer"`, with `read_only_project_entry_ready:true`. Importantly, **`observation_ready:false` remains unchanged** because no Send is enabled, and every authenticated Project/conversation/receipt claim, `submission_authorized`, `scheduler_activation_authorized`, and production task support remain false. This status only means read-only UI entry observation is healthy, **not that any prompt has been sent or may be sent automatically**. A null/unknown disabled state, duplicate controls, nonempty draft, or active Stop do not qualify.

**Harmless one-shot acceptance staging (now separately smoke-tested once on owner's Desktop; original design retained):** An empty Project editor cannot have an enabled Send button before text is filled. The isolated `legacy_ui_acceptance.mjs` (owner-approved only; not imported by Scheduler) now requires the stricter `read_only_project_entry_ready:true` preflight **plus** a unique exact Project badge, exact Project-scoped composer, visible target Project list and empty Project landing in main content, one **disabled** Send and zero selected chat. It fsyncs the immutable no-replay acceptance ID before writing the fixed harmless prompt, then immediately **re-observes** the exact Project, editor and Send control. It also compares the editor's content to the exact fixed harmless acceptance prompt **inside the renderer**, returning only a boolean: an unrelated or concurrently replaced draft must never be sent. Only if Project context remains uniquely consistent, the draft matches precisely, no generation is running and Send is uniquely **enabled** does it issue a **single** semantic click. If any post-fill check is inconclusive, it **does not click** and the attempted ID remains indeterminate/quarantined. No Enter/keyboard fallback, no retry, no queue dispatch, no durable server receipt claim. Mock tests exercise the normal disabled-to-enabled UI transition, journal failure, duplicate ID, failed fill/click and post-fill Send remaining disabled. The owner subsequently granted approval and executed the single harmless acceptance; see the live acceptance evidence section.

**Current boundaries and next tests:**
1. Confirm *read-only* compatibility on the owner's installed Desktop by running `node automation/chat_bridge/legacy_ui_probe_cli.mjs probe` after exact-head CI safety tests PASS. The result must not contain text or IDs and will **never** authorize a send.
2. Separately obtain explicit owner approval to run **one harmless manual acceptance** in an intentionally empty managed test chat; use a fsynced private journal and preserve its indeterminate outcome until reconciled. Never run the historical multi-fallback `desktop_cli.mjs managed-submit` in the live queue.
3. Independently verify whether the installed UI or another documented supported interface can associate a clicked Send with one exact server `user_message_id`, ChatGPT Project membership and one terminal assistant receipt. Without this proof, the UI fallback may only support *assisted/manual* testing, not unattended queue execution or chat rollover.
4. Preserve the existing native adapter as an isolated unsupported source path; only an explicitly accepted, proven UI transport may eventually replace the manager's send/poll route. Restarting Scheduler or migrating the 18 pending tasks is **not part of this change**.

## Explicit exclusions

No `definition.resolve()` invocation; no native `submit`/CLI submit, DOM/click/keyboard/UI fallback, transport injection, speculative `native_adapter.mjs` modifications, scheduler start/reset, queue replay, chat rotation or attempt to choose between the seven Maps. The next engineering investigation should evaluate available **supported transport capabilities** and exact identity/receipt requirements separately from the private bundled React implementation.


## Owner live harmless acceptance evidence (2026-10-15)

**Observed via owner-supplied screenshot and terminal result (no direct GitHub-side Desktop session access):**
- The owner ran `node automation/chat_bridge/legacy_ui_acceptance_cli.mjs --owner-approved <fresh-uuid>` **once** on their installed desktop after an empty, uniquely scoped `Automatic Alis` Project preflight.
- The CLI reported `{"purpose":"owner-only-harmless-ui-acceptance","status":"indeterminate","code":"SINGLE_UI_CLICK_ISSUED_OBSERVE_ONLY","submission_authorized":false}`. This attests a **single local Send click attempt**, not a server acknowledgment.
- In the supplied Desktop screenshot, the outgoing fixed `AUTO-F01 UI transport acceptance test only ... HADALIS_LOOP:DONE` prompt is visible, followed by one assistant reply `HADALIS_LOOP:DONE`. This is **direct visual evidence that the installed UI/CDP one-shot path can render a sent user prompt and corresponding assistant reply**. The screenshot shows no obvious duplicate test message; it cannot prove there were no other sends outside the frame.
- This is **UI-level smoke PASS only**, **not** authenticated Project membership, conversation/user-message IDs, successful terminal receipt, durable restart/recovery or unattended AUTO-R01 readiness. Treat the CLI's `indeterminate` status as truthful until separately reconciled. **Do not** auto-upgrade a UI screenshot into an accepted manager receipt or forge/reconstruct IDs.
- One-shot owner permission is exhausted. Do **not** repeat the acceptance with a fresh ID to improve certainty; first collect distinct, read-only, supported identity evidence. Keep the local write-ahead journal intact, preserve all 18 queued tasks, reserved `AUDIO-I01`, all pending/uncertain receipts and existing profiles. No Scheduler start, chat rotation, or task prompt send.

**Next engineering gate:** Evaluate only documented, authenticated, read-only Project/conversation/turn identity facilities available in the installed Desktop. Prove exact Project membership, message IDs, association of user turn with final assistant response, and durable receipt semantics **before** considering a production transport adaptation. Existing `native_adapter.mjs` relies on unsupported renderer-internal binding and should not be invoked just to discover these identities. If no supported interface exists, retain UI transport as manual/assisted acceptance only and report `BLOCKED: VERIFIED_IDENTITY_INTERFACE_UNAVAILABLE` rather than expanding the single test to queued work.

## Read-only post-send observation (no replay, 2026-10-15)

The owner already completed the **one** approved harmless send and received the requested visible reply. For future *observation* of that **existing** chat (not an empty Project landing), the read-only Playwright CLI now exposes a separate mode:

```bash
node automation/chat_bridge/legacy_ui_probe_cli.mjs observe-acceptance
```

This mode checks only the fixed harmless request string and the fixed `HADALIS_LOOP:DONE` reply, using exact text matching and bounded **visible** counts. It returns no raw message body, Project ID, conversation ID, user-message ID, private draft, URL or credential. `ONE_VISIBLE_HARMLESS_PAIR_NOT_ATTESTED` means exactly one of each fixed text is visible in the renderer **at observation time**; it cannot establish server provenance, message ancestry, response completion, or authenticated membership. `HARMLESS_PAIR_NOT_VISIBLE_OR_INCOMPLETE` can reflect scrolling/virtualization or other UI layout changes, not necessarily delivery failure. Multiple matches remain ambiguous. The same CLI refuses unknown modes including `submit`; this observation is never a permission to click, resend, accept a receipt or enable Scheduler.

Synthetic tests exercise matching/missing/duplicate pairs, spoofed UI Project context, command rejection, loopback-only CDP, fake renderer and output redaction. This is a **reproducible read-only follow-up to the owner screenshot**, not the missing documented provider identity/receipt interface. Do not rerun the one-shot acceptance, rotate a chat or modify the existing 18-task queue.

**Owner follow-up observed on installed Desktop (2026-10-15):** The owner ran the `observe-acceptance` read-only CLI against the already-existing chat. Its categorical JSON reported `visual_pair_status:"ONE_VISIBLE_HARMLESS_PAIR_NOT_ATTESTED"`, `request_visible_count_capped:1`, `reply_visible_count_capped:1`, `visual_project_guard_observed:true`, `status:"read-only"`; server Project/conversation/user-message verification, final receipt and Scheduler authorization all remained `false`. This corroborates the prior screenshot with a separate **no-send** renderer observation. It is not a server receipt and must not be used to adopt/acknowledge the test as a managed task. The owner also pasted the proposed `systemctl --user show` loop **without any service-state output**; there is currently **no on-device service health conclusion** or startup proof. Await only the actual `LoadState`, `ActiveState`, `SubState`, `Result`, `ExecMainStatus`, and `NRestarts` lines for `hadalis-chatgpt`, `hadalis-chat-bridge`, and `hadalis-worker`. No service restart/start/reset is required for this diagnostic.

## Alternative GitHub DONE handoff — deterministic local jobs (2026-10-15)

**Purpose and limits.** The owner proposed avoiding undocumented ChatGPT Desktop server receipt IDs by letting Cloud GPT and Localbot communicate through **GitHub as an explicit coordination channel**. This is a separate, opt-in deterministic-job transport; it does **not** attest ChatGPT Project/conversation/message IDs, replace the user-facing ChatGPT reasoning agent, authorize existing 18 queued tasks or unlock native Desktop Scheduler. Never call this an authenticated ChatGPT Desktop receipt.

**One reusable ephemeral remote control file:** `automation/handoff/ACTIVE.json` on `Alis/dev`, only created when there is an approved handoff to prepare. No per-poll log files, no repeated prompts or script scattered across the repo. It is overwritten on material state changes, **not** on each polling interval. The immutable SHA-pinned job remains in the pre-existing `automation/queue/pending/JOB-...json`; public result goes to the existing `automation/results/JOB-...json`. The existing `hadalis-worker` already fetches `origin/dev` every 10 seconds by default (`HADALIS_WORKER_POLL_SECONDS`), so there is no second daemon/timer.

**Exact JSON contract for the control file** (illustrative; do NOT publish placeholders or use this as a live job):

```json
{
  "schema": "alis.github-handoff.v1",
  "task_code": "AUTO-F01",
  "run_id": "10000000-0000-4000-8000-000000000001",
  "job_id": "JOB-AUTO-F01-demo",
  "base_sha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "job_sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "status": "PREPARING",
  "updated_unix": 1792036800,
  "expires_unix": 1792040400
}
```

A matching new worker job opts into this protocol using `"handoff":{"task_code":"AUTO-F01","run_id":"<same UUID>"}`. Cloud GPT must first fully author the pinned job file, check its exact UTF-8 SHA-256, and publish/update only the same control file from `PREPARING` to `DONE` **after** it has completed preparing and reviewing that job. **`DONE` means the *handoff is ready for a separate authorized local execution*, NOT that the Issue or assistant response is finished.** Do not put a ChatGPT token, prompt body, private logs, shell commands or runtime state in the control file.

**Local execution consent:** Before the worker may execute a *new opt-in job*, the owner must explicitly bind the full immutable job digest locally once:

```bash
python3 scripts/AUTO-F01-github-handoff.py status JOB-<id>
python3 scripts/AUTO-F01-github-handoff.py approve JOB-<id> --owner-approved
```

The `status` operation is read-only. `approve` validates the job, current signal and matching IDs, persists a short fsynced local `handoff-approvals/JOB-<id>.json`, and **does not execute**. Approval without the exact remote job and matching signal is rejected. Review the job's concrete actions before approving; the manifest alone is not a review of shell commands.

**Execution and fail closed:** On each already-existing bounded poll, a new opt-in job is not started and has **no execution receipt created** until all are true: control file is well formed and fresh (max lifetime 24 hours), `status=DONE`, `job_id`, `run_id`, task code, `base_sha` and exact SHA-256 of the pinned job match, and the owner’s local digest-specific approval exists. Missing, expired, malformed, overwritten, ambiguous or unapproved signals never start a new job. No automatic retry of any indeterminate execution or migration of an existing pending job ID. Existing SHA pin, action allowlist, receipts, resource leases and private diagnostics remain in force.

**Automatic cleanup:** Successful *publication* of a settled job result (`passed`, `failed`, `cancelled`) stages deletion of the **matching** `ACTIVE.json` in the **same Git push** as `automation/results/JOB-...json`, without deleting a newer/different task’s control file. Existing private receipts remain as anti-replay tombstones; a now-unnecessary local approval file is removed on the worker's next periodic 5-minute cleanup after publication. Uncertain/nonterminal jobs retain their signal and receipt for reconciliation. Git history is immutable: deleting a file from the latest tree does **not** erase earlier commits, so the manifest intentionally contains only IDs, digests, timestamps and status.

**Production distinction:** This opt-in GitHub job protocol is a candidate production path for **deterministic local commands after explicit approval** and CI/live acceptance. It does NOT autonomously give ChatGPT a background runtime that writes status updates every few seconds; Cloud GPT only writes when actually invoked or scheduled. ChatGPT's Project ID is unnecessary for this *separate* GitHub job channel, but still required for native ChatGPT Desktop auto-chat scheduling/rotation. Keep AUTO-F01's native transport gate blocked until those different guarantees are proven.

## Owner systemd snapshots and restart-window gate (2026-10-15)

Owner-provided read-only `systemctl --user show` confirms **all three units currently loaded/active/running, Result=success, ExecMainStatus=0**:

| Unit | NRestarts (cumulative, as observed) |
| --- | ---: |
| `hadalis-chatgpt.service` | 8734 |
| `hadalis-chat-bridge.service` | 8732 |
| `hadalis-worker.service` | 8731 |

The near-equal large counters justify investigating possible historic or current restart storms, but **do not prove a currently recurring failure**. No `InvocationID`, `MainPID`, active-since timestamp, restart rate, journal trace or on-device error code across time has been received. Do not infer a common crash cause from counter similarity alone; `Result=success` means only the reported current state, not zero prior failures. The unit templates in `scripts/install-hadalis-automation.py` specify `Restart=on-failure`, `RestartSec=3`; the installed unit properties have not been independently compared with these templates.

Read-only, bounded **12-second** two-snapshot sample (from a clean updated `dev` checkout):

```bash
python3 scripts/AUTO-F01-service-probe.py probe
```

The script reads fixed `systemctl --user show` properties of only the three units, reports `restart_count_before`, `restart_count_after`, `restart_delta`, redacted state flags, and whether the process/invocation changed. It does **not** return PID/InvocationID values, service environment, secret tokens, journal text or full unit configuration. It does **not** start/restart/stop units or interact with Desktop, Scheduler, receipts, chat, queue or Github. Interpret `NO_RESTART_DETECTED_IN_SAMPLE` as stable **only within the sampled interval**, `RESTARTS_OBSERVED_IN_WINDOW` as concrete evidence of fresh restarts, and `COUNTER_RESET_OR_UNIT_REPLACED` / `PROCESS_OR_INVOCATION_CHANGED_UNCOUNTED` as requiring targeted inspection. `SAMPLE_UNAVAILABLE_OR_INCOMPLETE` means no diagnosis is supported.

If fresh restarts are observed, preserve original invocation/receipt evidence and collect only **bounded redacted** unit diagnostics locally before changing service policy. No blind `systemctl restart`, `reset-failed`, state deletion, backoff adjustment or Scheduler activation is justified by the cumulative counters. Project/conversation/message/terminal-receipt authorization remains BLOCKED independently of systemd health.

**Owner follow-up restart-window result (2026-10-15, actual installed systemd):** The owner ran the read-only probe with a 12-second window. All three `LoadState=loaded`, `ActiveState=active`, `SubState=running`, `Result=success`, `exit_code_zero=true`; the before/after cumulative restart counters were `8734 -> 8734` (ChatGPT host), `8732 -> 8732` (Chat Bridge), and `8731 -> 8731` (Worker), respectively. For each, `restart_delta=0`, `process_changed=false`, `invocation_changed=false`, `diagnosis="NO_RESTART_DETECTED_IN_SAMPLE"`. This is direct **12-second runtime stability evidence** and closes the immediate suspected *currently repeating* restart-loop diagnostic; it does not establish service uptime since initial start, future stability or why the historical counters are high. Do **not** restart/tune systemd on this evidence. `chat_project_verified=false`, `server_receipt_verified=false`, and `scheduler_submission_authorized=false` are correct and unchanged. **Service process health is no longer the observed blocker**; supported server-authenticated ChatGPT Project/conversation/user-message/terminal receipt remains the sole known transport-acceptance blocker. Do not ask the owner to repeat the same probe without new symptoms.


## Historical owner-approved single-shot acceptance runbook (already executed; DO NOT rerun)

The owner approved **one fixed harmless acceptance** in the ChatGPT conversation. This authorizes only the isolated manual test described below; it does **not** authorize starting the Automation scheduler, sending any of the 18 queued tasks, or replaying an uncertain attempt. GitHub-side changes cannot reach or inspect the owner's live Desktop process. The owner subsequently ran the single approved test on the installed Desktop, as documented above. The original runbook remains for audit only: **its permission is exhausted, and these commands must not be run again without distinct approval and a new test plan.**

**Preflight on the owner's machine:** Use a clean `Alis/dev` checkout updated by an ordinary fast-forward after checking for concurrent local work. Never force-reset or delete worktrees, task state, journals, receipts or queues. Confirm Desktop is open to the **empty** new-chat page in the existing Project `Automatic Alis`, with no user draft.

```bash
# From a clean Alis/dev checkout with the current code already installed:
git branch --show-current
git rev-parse HEAD
git status --porcelain
node automation/chat_bridge/legacy_ui_probe_cli.mjs probe
```

Only continue if the probe confirms `read_only_project_entry_ready:true`, exactly one Project-scoped composer, one Project badge, one disabled Send, no Stop, an empty draft, and the corroborated empty Project landing. If it does not, **stop without sending**, do not work around the guards.

**Historical command used for the one already-completed owner-approved test — DO NOT RUN AGAIN** (shown for audit, not as an action):

```bash
acceptance_id="$(node -p 'require("node:crypto").randomUUID()')"
node automation/chat_bridge/legacy_ui_acceptance_cli.mjs --owner-approved "$acceptance_id"
```

This CLI accepts no custom prompt or task code. Its only prompt asks for `HADALIS_LOOP:DONE` without using tools/connectors. It journals the UUID durably before any editor mutation, verifies the exact fixed draft, and may issue at most one Send click. **A nonzero exit and `status:"indeterminate"` are expected even when a click is issued.** A code such as `SINGLE_UI_CLICK_ISSUED_OBSERVE_ONLY` records a local action attempt, not authenticated server delivery or a completed assistant response. `POST_FILL_*_NO_SEND` and `HARMLESS_DRAFT_MISMATCH_NO_SEND` are no-send but still must not be retried under the same or a new UUID without a new explicit decision.

Afterward, visually inspect the target Project/chat once and report **only** the categorical CLI result and whether a single harmless response appeared. Do not share private chat contents or journal details. Do not run this command in GitHub Actions, a cloud container, or a second desktop session: it must connect to the owner's existing local ChatGPT Desktop. Production Scheduler/queue activation remains blocked until separate server-verified Project, conversation, user-message and terminal receipt identities are available.
