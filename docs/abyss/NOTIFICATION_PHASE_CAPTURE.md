# Alis notification / recording phase measurements

**Canonical Issues:** [NOTIF-I01](https://github.com/llocphann/Alis/issues/71) and [NOTIF-I02](https://github.com/llocphann/Alis/issues/74).
**Status:** diagnostic collector delivered; no user hardware frame trace, root-cause
diagnosis, or Owner Verified acceptance. **Target branch:** `dev`; never `stable`.

## Why a separate phase collector exists

The existing `collect-abyss-hover-frames.sh` records frame intervals and
hover snapshots in different phases. That is useful for observing a bridge,
but it cannot correlate a specific Recording start/stop with the same
frame interval. The new collector invokes the existing opt-in
`abyssHoverProbe.startFrames` and collects timestamped
`abyssHoverProbe.snapshot` observations *during the same bounded event*.
The source now exposes read-only height and state measurements for the
transient Notification banner through `AbyssPerimeter.qml` and
`AbyssNotificationsContent.qml`.

The collector does not start/stop Recording, make notifications, capture
audio, draw screenshots or alter Settings. It operates only on the running
`alis` shell explicitly selected, requires clean checkout **and installed
QML parity**, and refuses to silently inspect another Quickshell config.

## Local bot commands (run on the installed Niri machine)

Make sure the actual installed Quickshell config matches this clean
`Alis/dev` checkout first. Then reproduce each case separately:

```bash
python3 scripts/collect-abyss-notification-frames.py \
  --config "$HOME/.config/quickshell/alis" --phase record-start

# Recording must already be active during the initial baseline:
python3 scripts/collect-abyss-notification-frames.py \
  --config "$HOME/.config/quickshell/alis" --phase record-stop

# Notification Center must initially be closed:
python3 scripts/collect-abyss-notification-frames.py \
  --config "$HOME/.config/quickshell/alis" --phase edge-hover
```

Each command collects a short baseline and then prints **EVENT WINDOW**.
Trigger the named action during that window; the command does not perform
any action itself. For `toast-close`, a new ordinary notification may stay
visible for seven seconds or longer: sending it at EVENT WINDOW is not proof
that it closed within a three-second capture. Dismiss it during the event
window or set up a naturally timed close before measuring; do not change
user notification settings automatically. Run cold/warm variants and consider repeating with and
without a recent notification. `--seconds` is bounded to 2–8 and
`--interval` to 0.15–1 second.

The result file is `notification-presentation.json` under a new private
`/tmp/alis-notification-phase-*` directory unless `--output-dir` is supplied.
Only that **sanitized JSON** should be shared. Each output name is hashed;
no notification body, saved path, window title, image, clipboard contents,
audio samples, or screenshot pixels are serialized.

## Read the result strictly

- `BLOCKED`: no qualified installed instance, dirty checkout, mismatched
  source bytes, missing IPC/field, or other diagnostic failure. When
  `failureCode` is `STALE_RUNTIME`, installed files match the checkout but
  the live Quickshell IPC does not expose `notificationFrameLimit: 160`
  and the notification-frame schema. The collector stops any probe armed
  during the failed handshake. A deployed `alis` runtime without `.git`
  normally disables hot reload through `ALIS_DISABLE_HOT_RELOAD=1`; a
  byte-matching file does not establish runtime identity. Do not assume the
  bug is absent or automatically restart the Owner shell.
- `INCOMPLETE_TRACE`: the baseline or event trace hit its 600 swap-interval
  cap, the 160 active-notification frame limit (dropped samples), or the
  160-tick heartbeat history bound. The sanitized `exhausted`,
  `notificationFramesDropped` and `heartbeatHistoryExhausted` fields explain
  which limit was reached. Do not interpret an unobserved or partially observed
  transition as full-window evidence; shorten the capture or narrow the
  reproduced event.
- `EVENT_NOT_OBSERVED`: there was no qualifying state transition on the
  same output in the event phase. A static open Center or an unrelated
  notification does not count as success.
- `NO_FRAME_SAMPLES`: event observed but no swap intervals returned. This
  cannot support an FPS conclusion.
- `CAPTURED`: transition and at least one swap interval captured *without
  a detected buffer limit*. The
  **existence** of a trace is not evidence that lag is fixed.

Compare `baseline.frames` and `event.frames` for p50/p95/p99 and
`over33ms`, heartbeat delays, and the `slow` timestamps. Align these
with the `event.snapshots` timestamp/height/edge/open flags. Repeated,
paired comparisons are needed because idle frame gaps and interleaved
IPC snapshots can perturb frame timings. The instrumentation is an
observer, not an external compositor GPU profiler.

Do not attribute stutter to geometry, Qt event loop, QSB/RHI or
`wf-recorder` solely from one gap. If an actual running-session defect is
identified, attach exact SHA, timestamped phase correlation and the
smallest reproducible case before changing animations or allocator state.

## Verification receipts

- Commit `7579addcdbe18c46171669af8e9edfe99d9ff0c8`: opt-in read-only
  presentation snapshot and finite collector.
- Commit `f25b0dd19c414055fba5264decb0097fdcf42b81`: require actual
  phase transitions and present samples to report a captured event.
- Commit `895603ff780ee2d829e8a4ed073040fdbe83fcf7`:
  [focused GitHub workflow PASS](https://github.com/llocphann/Alis/actions/runs/38234196986)
  for Python syntax, source-phase contracts and notification regressions.
  This is not a native Niri or Owner Verified result.
