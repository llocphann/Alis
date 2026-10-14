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

## Independent diagnostic ledger

`automation/chat_bridge/transport_evidence.mjs` classifies **redacted scope evidence** into categorical blocker codes. The read-only inspector adds it as `transport_evidence`. The ledger **always** returns `status: "blocked"`, `supported: false` and `submission_authorized: false`; it is *not* a capability bridge, a resolver, an API key checker or an escape hatch. Flags copied from user input, mock fixtures or static helper matches cannot authorize submission.

Test: `node scripts/test-hadalis-transport-evidence.mjs`. A passing synthetic test means only that the diagnostic guard stays closed. It does not establish connected-app state, runtime project identity, actual Desktop responses or a working native bridge.

## Explicit exclusions

No `definition.resolve()` invocation; no native `submit`/CLI submit, DOM/click/keyboard/UI fallback, transport injection, speculative `native_adapter.mjs` modifications, scheduler start/reset, queue replay, chat rotation or attempt to choose between the seven Maps. The next engineering investigation should evaluate available **supported transport capabilities** and exact identity/receipt requirements separately from the private bundled React implementation.
