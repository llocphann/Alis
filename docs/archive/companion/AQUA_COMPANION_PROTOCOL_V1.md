> Historical snapshot archived on 2026-10-10 from Alis `8b2ed6f0a1fccddade206f0060ed19d19337a5da`. This document does not assign active work or prove that pending acceptance is complete. Use [the current categorized tasks](../../../to-do/README.md).

> Companion implementation and remaining product tasks belong to [Alis-Companion](https://github.com/llocphann/Alis-Companion). Original Alis receipts keep their original scope.

# Aqua companion protocol v1

Transport candidate: newline-delimited JSON over one long-lived stdio child process. This contract is intentionally small enough to validate before production integration.

Daemon -> QML state message:

```json
{"v":1,"seq":1,"type":"state","visibility":"present","mood":"calm","activity":"idle","energy":0.35,"gaze":[0.0,0.0],"body":{"squash":0.0,"stretch":0.0,"lean":0.0,"tip":0.0,"ripple":0.0},"face":{"eye":1.0,"mouth":0.15},"pulse":0.0}
```

QML -> daemon semantic event:

```json
{"v":1,"seq":1,"type":"event","event":"hover","active":true}
```

Rules: one JSON object per line; `v` and monotonic `seq` required; messages are semantic state/events only, never frames or pixels; unknown fields are ignored; unknown versions/types are rejected; malformed or oversized input must not terminate the daemon; hidden state must not require periodic QML updates.

## Sparse walking suggestions

State messages additionally carry `travel_id` (initially zero) and
`travel_target` (initially 0.5). A new positive ID requests one destination;
the target is a finite fraction in 0..1. Rust chooses these sparsely during
an already scheduled visible-idle action, with no extra timer or frame stream.
Hover, tasks and explicit hide cancel the idle schedule; hide resets the ID.

QML accepts safe integer IDs monotonically, ignores missing fields from an
older daemon, and maps each new target into the current verified free Bar
interval. The host validates every intermediate position, applies local
Blender-authored gait curves and owns interpolation. An unavailable safe path
does not move Aqua. Stable panel/popup relocation is owned by the existing
surface host, independently of a daemon destination suggestion.

## Personality and appearance preferences

The single bridge sends preferences before the first `show`, again after a
restart handshake, and when the corresponding settings change:

```json
{"v":1,"seq":2,"type":"preferences","personality":"calm","appearance_frequency":"occasional"}
```

`personality` accepts `calm`, `balanced` or `energetic`; `appearance_frequency`
accepts `always`, `frequent`, `occasional` or `rare`. Unknown values, versions
and non-monotonic sequences are rejected without consuming a sequence number.
State messages acknowledge both preference fields. Defaults are `balanced`
and `always`, preserving the previous behavior until configured.

Calm/energetic scale reaction energy and targets by 0.55/1.35. Idle deadlines
are non-uniform: 9–16 seconds, 6–11 seconds and 3–6 seconds respectively.
Energetic uses the excited expression for positive reactions. Targets remain
bounded and each new reaction begins with neutral body/face targets.

Scheduled visits last 20 seconds. Their start periods are 1, 3 or 10 minutes;
interaction extends a visit, hovering holds it, and a waiting task holds it
until semantic completion. The presence deadline is independent of blink and
reaction deadlines. Between visits, there is only one future arrival deadline
and no autonomous state stream. An explicit shell `hide` clears both clocks
and the permission to appear; changing preferences or sending a model intent
cannot revive that host. Sleep remains peeking until a wake event. A preference
change can preempt a temporary model overlay while preserving its waiting-task
baseline. Rendering quality is a local QML setting and never drives a frame IPC
stream or a second daemon.

## Optional local-model intent adapter

The planned AI connection defaults to **Local LLM**, with no automatic cloud fallback. Provider settings, conversation UI and inference lifecycle are future work described in the [reference design](AQUA_REFERENCE_DESIGN.md#planned-ai-connection--local-llm-by-default). This existing intent contract carries reactions, not conversation requests or model credentials.

State messages additionally include `expression`: `idle`, `happy`, `excited`, `thinking`, `working`, `surprised`, `sleepy`, `sad`, or `alert`. Older QML clients ignore it; newer QML clients derive it from mood/activity when talking to an older daemon.

A future small local model may suggest one bounded semantic reaction:

```json
{"v":1,"seq":2,"type":"intent","expression":"thinking","intensity":0.45,"ttl_ms":1600}
```

The adapter calls `CompanionBridge.sendIntent(expression, intensity, ttlMs)` on the existing single stdio bridge. The model must not create another writer/daemon or supply protocol sequence numbers. Intensity is a finite number in 0..1; TTL is an integer in 250..10000 ms. Invalid records do not consume sequence numbers. Hidden hosts ignore intents and schedule no work. Repeated intents replace the temporary reaction while preserving the original state. Expiry restores that state, including an ongoing task; shell events preempt the overlay. Rust owns deadlines, QML owns interpolation.

No model, inference runtime, conversation history, network endpoint, or command/tool execution is installed by this change. The eventual adapter runs inference only for an explicit conversation or meaningful event, validates structured output, and forwards this vocabulary. Model size and CPU/RAM budgets must be measured on the target machine before choosing a model.
