# AUDIO-I01: optional native EasyEffects quantum-lock comparison

**Status: experimental diagnostic, NOT a confirmed fix.** This probe is opt-in
and defaults to OFF. It is for [AUDIO-I01](https://github.com/llocphann/Alis/issues/81):
short audio pops on starting NEW online clips while Local Music continues playing.
The earlier popup/sidebar/dashboard symptom has separate owner-verified resolution.

## Why this experiment exists

The owner observed browser nodes attaching/detaching and physical-driver
quantum switching `1024 ↔ 2048` during the same 45-second listening-confirmed
pop reproduction. Driver ERR deltas were zero; timestamps of individual pops
were not recorded. **That does not prove the quantum changes caused the pops.**

In EasyEffects 8.3.0,
[`PluginBase::on_process`](https://github.com/wwmm/easyeffects/blob/v8.3.0/src/plugin_base.cpp#L64-L103)
calls plugin `setup()` on changes to callback buffer size or rate.
[`Convolver::setup`](https://github.com/wwmm/easyeffects/blob/v8.3.0/src/convolver.cpp#L250-L304)
marks itself not-ready and asynchronously initializes zita;
[`process()`](https://github.com/wwmm/easyeffects/blob/v8.3.0/src/convolver.cpp#L307-L339)
temporarily copies unprocessed input while not ready. This is a *candidate
discontinuity mechanism*, not a measured reset in the owner's process.
The upstream [Convolver latency issue](https://github.com/wwmm/easyeffects/issues/4579)
describes this behavior.

PipeWire documents `node.lock-quantum = true` as preventing **automatic**
quantum changes while the node is active. Forced changes are still possible.
[PipeWire scheduling properties](https://docs.pipewire.org/page_man_pipewire-props_7.html).
The PipeWire 1.6.9
[`pw_filter_connect()` path](https://github.com/PipeWire/pipewire/blob/1.6.9/src/pipewire/filter.c)
reads `PIPEWIRE_PROPS` into each filter's node properties, so the probe
uses only the native EasyEffects child process environment. It does **not**
write `clock.force-quantum`, set global PipeWire metadata, change the
selected DSP preset, IR, EQ, or volume.

## Safety and activation

- Default Alis native and Flatpak EasyEffects launch behavior is unchanged.
- Only native EasyEffects started via the **Alis toggle** with
  `ALIS_AUDIO_I01_LOCK_QUANTUM=1` inherited by the **running Quickshell process**
  uses `scripts/audio/easyeffects-quantum-guard.sh`.
  The flag needs to be set **before launching Quickshell**; exporting it in a
  separate terminal does not update an already running Quickshell process.
- Alternatively, after voluntarily exiting any already-running native
  EasyEffects process, an owner may launch it directly from a **dev checkout**:
  ```bash
  ALIS_AUDIO_I01_LOCK_QUANTUM=1 bash scripts/audio/easyeffects-quantum-guard.sh easyeffects --service-mode
  ```
  Do not execute this while another EasyEffects service is running: a second
  launcher may connect to the existing daemon, so the new property will not
  necessarily be applied.
- If any `PIPEWIRE_PROPS`, `PIPEWIRE_QUANTUM`, or `PIPEWIRE_LATENCY`
  variable is explicitly inherited (including an empty value), the opt-in
  wrapper exits 78 **without starting** the process; owner settings are
  neither merged nor overwritten. It never stops another process.
- The property affects scheduling for the graph connected to EasyEffects
  while filters are active. That is **not** an isolated Convolver parameter;
  a locked quantum may change latency/behavior for other applications.
  No auto-deploy, auto-restart, or unattended production enablement is safe.

## Controlled owner A/B/A and rollback

1. With the original preset (`DolbyMusic`, original gains, original routing),
   first document audible pops while switching NEW online clips during
   uninterrupted playback of the same Local Music track.
2. **Only with the owner's explicit approval**, fully exit EasyEffects;
   restart the native version with the opt-in guard, observe whether the
   active Convolver filter node has `node.lock-quantum=true` in `pw-dump`.
   If not, the experiment is invalid.
3. Repeat the same clip-switch comparison, log owner listening and actual
   driver `pw-top` quantum and ERR deltas. No change in reported behavior
   means no cure. A reduction alone still requires volume-matched replication.
4. **Restore:** fully exit only the opted-in EasyEffects process, unset
   `ALIS_AUDIO_I01_LOCK_QUANTUM` in the startup environment, and launch
   native EasyEffects normally. Verify original plugin/IR/gain/bypass settings
   and `node.lock-quantum` absent on newly created filters. If it was enabled
   through the Alis toggle, a restart of Quickshell without the flag is
   required before comparing the non-opt-in launch.
5. Validate popup/sidebar/dashboard as a regression and retest Local Music +
   online overlap before declaring any fix. Stop immediately if audio routing
   or playback becomes unstable.

**Limitations:** Requires actual native EasyEffects process creation. It does
not retrofit filters on an existing process, does not affect Flatpak, and does
not fix EasyEffects' internal zita implementation. Instrumented reset/ready
events in EasyEffects or matched audible click markers are still required
before attributing the artifact to buffer reinitialization.
