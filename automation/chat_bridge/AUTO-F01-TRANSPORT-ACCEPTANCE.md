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

## Cloudbot GitHub app mention in every task prompt (2026-10-15)

The task-code Cloudbot objective, managed prompt composer and task selector now place the owner-selected exact GitHub app link on the **first line** of generated Cloudbot messages:

```text
[$github](app://connector_76869538009648d5b282a4bb21c3d157)
```

Applies at `initial`, `continuation`, `rotation` and `Cloudbot auto-select`. Prompt composer strips an existing link (including an older GitHub mention at the start of stored prompts) before adding the standard one once, so reused task files do not accumulate mention lines. Legacy Hadalis profile prompts retain their prior `[@GitHub](plugin://github@openai-curated-remote)` link and are not migrated by this change.

**This is only a serialized user-message link**, not authentication or evidence that the ChatGPT Desktop editor resolved a rich mention or enabled the connector. Keep the native Desktop `transport_gate` **blocked** pending separate supported, authenticated server-side Project/message/response attestation; never unblock based on prompt text or icon detection. The GitHub handoff worker remains a separate owner-approved execution channel. The pending isolated `AUTO-F01` no-op job remains `PREPARING` until explicit local approval; do not switch it to `DONE` as part of prompt changes.

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

**On-device compatibility gate before staging a live GitHub job:** Since the owner may still have an older `hadalis-worker` Python process running after fetching new repo commits, always first check the actual currently running worker heartbeat **without modifying it**:

```bash
python3 scripts/AUTO-F01-github-handoff.py doctor
```

Do **not** create a live GitHub job while `worker_supports_github_handoff` is `false`: an older worker may reject the new `handoff` field and publish an `invalid` result before the new gate is loaded. `doctor` requires a recent worker heartbeat (<=30 s old) with the matching capability marker emitted by the running worker, not merely the presence of updated repository code or running systemd units. This is still not a guarantee of network access, safe execution or authenticated ChatGPT messages. If false, inspect the installed unit and upgrade plan before changing the worker; do not blindly restart the owner’s services or reset its receipts.

**Owner follow-up size blocker (2026-10-15):** The newly categorized doctor reports `worker_receipt_inventory_blocker:RECEIPT_ENTRY_SIZE_LIMIT_EXCEEDED`, `worker_receipt_inventory_complete:false`, `worker_unsettled_receipts_present:null`, and `worker_restart_preflight_clear:false`, with the original older-worker/process checks unchanged. At least one local worker receipt exceeds the old doctor metadata ceiling of 64 KiB; this does **not** establish damage or a nonterminal receipt. The worker's own durable receipts may legitimately embed action outputs and exceed 64 KiB.

On `dev`, updated `scripts/AUTO-F01-github-handoff.py` read-only receipt inventory uses `MAX_RECEIPT_INSPECT_BYTES=16 MiB` per file and `MAX_RECEIPT_TOTAL_BYTES=64 MiB` per scan. It opens each file without following symlinks, checks regular file/size, reads at most the strict limit, verifies size and mtime did not change during scanning, fully parses JSON only within those bounds, aggregates known phases, and emits *only* categorical blockers or counts (no filename, job ID, text, path or token). A huge or changing file remains **blocked**, as does a total evidence size above the doctor budget; do not assume it is safe or modify it. Synthetic tests confirm a legitimate large JSON receipt is counted safely, stale/malformed/oversized/symlinked receipts fail closed, and secret strings remain unreported. [Exact-code focused CI #38687792299](https://github.com/llocphann/Alis/actions/runs/38687792299) completed **SUCCESS** on source SHA `2648304e681954393ea8875d7eda90048485f7b2`, three focused suites PASS. Do **not** read or transmit worker receipt contents to GitHub.

After updating only a clean `dev` checkout (without touching user state), rerun `python3 scripts/AUTO-F01-github-handoff.py doctor` and report its sanitized JSON. An inventory complete with only `published` receipts may clear the *readiness preflight*, but still does **not** authorize a service restart; receive separate owner consent for a worker-only controlled restart, immediately recheck for race/work in flight, and postrestart verify the v1 handoff marker. If the next blocker is `RECEIPT_INVENTORY_TOTAL_SIZE_LIMIT_EXCEEDED` or `RECEIPT_ENTRY_SIZE_LIMIT_EXCEEDED` even at the new bounds, retain all data and inspect bounded size bands/metadata only, rather than raising memory limits indefinitely or erasing old receipts.

**Owner receipt preflight observation (2026-10-15):** A newer read-only doctor on the installed machine confirms `diagnosis:RUNNING_WORKER_OLDER_CODE_MAY_REQUIRE_CONTROLLED_RESTART`, `worker_heartbeat_fresh:true`, `worker_process_matches_checkout:true`, `worker_unit_matches_checkout:true`, `worker_service_active:true`, `worker_has_active_work_observed:false`. However, `worker_receipt_inventory_complete:false`, `worker_receipt_count_capped:null`, `worker_unsettled_receipts_present:null` and `worker_restart_preflight_clear:false`. **The current blocker is incomplete read-only inspection of old worker receipt state, not evidence of receipt corruption. No restart is permitted from this observation.** Possibilities include a legacy receipt schema, an unexpected filename, a symlink, invalid JSON, an oversized file or an I/O failure. Neither absence nor presence of unpublished execution can be inferred until the inventory is understood.

The updated read-only `python3 scripts/AUTO-F01-github-handoff.py doctor` now includes `worker_receipt_inventory_blocker` (one fixed categorical code, no file path or filename) and, when and **only when** the bounded inventory is complete, `worker_receipt_phase_counts` for five recognized phases, with `worker_receipt_count_capped`. It returns a blocker when the scan cannot be trusted and does not change receipts, services, scheduler, queue, Git history or local execution. New offline tests cover legacy/unknown phases, invalid JSON, non-object entries, unexpected extension, excessive file size and unsafe symlink; no file content or job identity is printed. **Obtain this new JSON before planning a controlled worker restart**; do not delete, rename, truncate, migrate or quarantine unexpected files without understanding their provenance. The user's earlier 18 queued tasks and reserved `AUDIO-I01` remain untouched.

**Owner second runtime observation (2026-10-15):** The upgraded doctor returned `diagnosis:RUNNING_WORKER_OLDER_CODE_MAY_REQUIRE_CONTROLLED_RESTART`, `worker_service_active:true`, `worker_unit_matches_checkout:true`, `worker_process_matches_checkout:true`, `worker_heartbeat_fresh:true`, `worker_has_active_work_observed:false`, but `worker_supports_github_handoff:false`. Thus the running process matches the intended checkout yet has not emitted the new protocol marker. The best-supported explanation is *old Python code still loaded into the process* after local source files were updated. This does **not** prove there are no unresolved local execution or publication receipts.

The doctor now additionally reports `worker_receipt_inventory_complete`, `worker_unsettled_receipts_present`, a capped receipt count and `worker_restart_preflight_clear`. This is a **read-only, bounded, fail-closed** scan of only the local worker receipt directory, checking record phases but not outputting job IDs, logs, file paths, tokens or message text. Any malformed record, symlink, nonterminal `preparing/executing/finished/publishing` receipt, active work/publisher, stale heartbeat or process-unit mismatch makes restart preflight false. A preflight of true is **not an authorization**: the doctor always emits `worker_restart_authorized:false`; the owner must separately choose whether to restart **only** `hadalis-worker.service` after verifying the result. Do not reinstall/enable all services, restart ChatGPT Desktop or Chat Bridge, erase local receipts, alter pending jobs, reset failed state or activate managed ChatGPT Scheduler.

After obtaining `worker_restart_preflight_clear:true` on a clean updated checkout, the owner may specifically approve a guarded controlled worker-only restart. Take another read-only doctor snapshot **immediately before** the actual service action to minimize race exposure. Afterward, rerun doctor; success requires `diagnosis:RUNNING_WORKER_HANDOFF_CONTRACT_OBSERVED`, `worker_heartbeat_fresh:true`, and `worker_supports_github_handoff:true`. If preflight is false, inspect categorized worker receipt state with bounded local diagnostics instead and **do not** restart. Next separate step is an owner-approved harmless GitHub job acceptance; no live job has been created or run.

**Owner runtime discrepancy, observed 2026-10-15:** The owner ran the original read-only `doctor` on the installed machine and supplied `worker_heartbeat_fresh:true`, `worker_supports_github_handoff:false`, `managed_chat_transport_ready:false`, `scheduler_submission_authorized:false`. This establishes an alive writer to the worker heartbeat **without** a recognized v1 handoff marker, not the root cause. Do not claim the service has loaded new code solely because `dev` is updated. Likely explanations are an older already-running Python process or an installed unit pointing to a different repository checkout, but those remain hypotheses until proven.

The upgraded `doctor` now reads only the installed `hadalis-worker.service` ActiveState, MainPID and WorkingDirectory, then compares the Linux process' `/proc/<pid>/cwd` and command-line script path to the active source checkout. It returns only booleans `worker_service_active`, `worker_unit_matches_checkout`, `worker_process_matches_checkout` and a categorical `diagnosis`; **no raw PIDs, paths, command arguments, usernames or tokens are returned**. A heartbeat claiming a contract is *not* accepted as verified support unless the installed service and actual process also match the checkout. The command is read-only; `worker_restart_authorized:false` and `no_services_modified:true` are explicit. When the result says `RUNNING_WORKER_OLDER_CODE_MAY_REQUIRE_CONTROLLED_RESTART`, first inspect pending execution/publishing activity before arranging a separately owner-approved controlled **worker-only** restart. When it says `INSTALLED_WORKER_SOURCE_MISMATCH_OR_UNVERIFIED` or `WORKER_PROCESS_VERSION_UNVERIFIED`, compare the installed unit/checkout locations; do not restart the wrong process. Keep all original worker receipts and 18 queued tasks intact.


**Local execution consent:** Before the worker may execute a *new opt-in job*, the owner must explicitly bind the full immutable job digest locally once:

```bash
python3 scripts/AUTO-F01-github-handoff.py status JOB-<id>
python3 scripts/AUTO-F01-github-handoff.py approve JOB-<id> --owner-approved --expected-sha256 <64-hex-from-status>
```

The `status` operation is read-only and prints the exact job SHA-256, pinned base SHA, run UUID, number and kinds of actions, without exposing private argv. The owner must review the full job contents separately and explicitly confirm that exact digest with `--expected-sha256`. `approve` validates the job, current signal and matching IDs, persists a short fsynced local `handoff-approvals/JOB-<id>.json`, and **does not execute**. Approval without the exact remote job and matching signal is rejected. Review the job's concrete actions before approving; the manifest alone is not a review of shell commands.

**Execution and fail closed:** On each already-existing bounded poll, a new opt-in job is not started and has **no execution receipt created** until all are true: control file is well formed and fresh (max lifetime 24 hours), `status=DONE`, `job_id`, `run_id`, task code, `base_sha` and exact SHA-256 of the pinned job match, and the owner’s local digest-specific approval exists. Missing, expired, malformed, overwritten, ambiguous or unapproved signals never start a new job. No automatic retry of any indeterminate execution or migration of an existing pending job ID. Existing SHA pin, action allowlist, receipts, resource leases and private diagnostics remain in force.

**Automatic cleanup:** Publication of a settled job result (`passed`, `failed`, `cancelled`) stages deletion of the **matching** `ACTIVE.json` **and matching opt-in pending job file** in the **same Git push** as `automation/results/JOB-...json`, without deleting a newer/different task’s control file or legacy job. If a server result already exists but cleanup previously failed, the worker validates its exact job/digest/status and performs cleanup only, never repeats execution. Existing private receipts remain as anti-replay tombstones; a now-unnecessary local approval file is removed by the worker's 5-minute cleanup after publication. Uncertain/nonterminal jobs retain their signal and receipt for reconciliation. An abandoned control with **no local execution receipt** is pruned automatically from the Git tip after expiry plus a 1-hour safety grace, by the **same** worker publication lane (max one periodic check every five minutes, fast-forward-only push; on concurrent changes, preserve and retry). Approval metadata for that expired, unstarted job is also removed locally. An expired handoff with a local execution receipt is **never** pruned by expiry cleanup: receipt publication/reconciliation owns it. Git history is immutable: deleting files from the latest tree does **not** erase earlier commits, so the control intentionally contains only IDs, digests, timestamps and status.

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
