# AUDIO-I01: native EasyEffects quantum stability mitigation

**Status: provisionally effective on the owner's native EasyEffects 8.3.0.**
The owner reported `node.lock-quantum=true`, stable `pw-top` QUANT, and **no audible "tẹt"**
when switching online clips while uninterrupted Local Music continued, in an
approved live manual A/B. This is a real listening acceptance of that trial,
not proof of the underlying Convolver reset mechanism or broad compatibility.
Track: [AUDIO-I01](https://github.com/llocphann/Alis/issues/81).

## Why

The owner's earlier 45-second listening-confirmed crackle capture had browser
stream churn and physical-driver QUANT `1024 ↔ 2048`, while ERR deltas stayed 0.
No individual audible-click timestamps were collected. In EasyEffects 8.3.0,
[`PluginBase::on_process`](https://github.com/wwmm/easyeffects/blob/v8.3.0/src/plugin_base.cpp#L64-L103)
calls `setup()` if rate or callback buffer size changes, while
[`Convolver::setup`](https://github.com/wwmm/easyeffects/blob/v8.3.0/src/convolver.cpp#L250-L304)
temporarily marks the convolver not-ready and reinitializes zita. During
initialization, [`process()`](https://github.com/wwmm/easyeffects/blob/v8.3.0/src/convolver.cpp#L307-L339)
passes through unprocessed input. The maintainer discussed the problem in
[EasyEffects #4579](https://github.com/wwmm/easyeffects/issues/4579).
**The owner's actual reset/ready transitions have not been traced directly.**

PipeWire [`node.lock-quantum`](https://docs.pipewire.org/page_man_pipewire-props_7.html)
inhibits *automatic* changes of graph quantum while an affected node is
active; forced changes are still possible. PipeWire 1.6.9
[`pw_filter_connect()`](https://github.com/PipeWire/pipewire/blob/1.6.9/src/pipewire/filter.c)
reads the child process's `PIPEWIRE_PROPS` when creating filter nodes.

## Default behavior on Alis dev

- When Alis itself **starts a new native EasyEffects process**, it now uses
  `scripts/audio/easyeffects-quantum-guard.sh` **by default**, passing
  `PIPEWIRE_PROPS='{ node.lock-quantum = true }'` to the child only.
- No existing EasyEffects instance is restarted, no global PipeWire metadata
  (including `clock.force-quantum`) is written, and no EasyEffects preset,
  impulse response, gain, device route or system volume is modified.
- Flatpak EasyEffects startup is unchanged. Native EasyEffects started
  independently of Alis also remains independent of this launcher.
- An existing `PIPEWIRE_PROPS`, `PIPEWIRE_QUANTUM`, or `PIPEWIRE_LATENCY`
  environment setting (including an explicitly empty value) **takes priority**:
  Alis does not inject a lock and still launches EasyEffects normally, with a
  warning. It never overwrites or merges unrecognized owner properties.
- **Opt out:** set `ALIS_AUDIO_I01_LOCK_QUANTUM=0` in the **Quickshell process
  startup environment** before launching Alis. The Alis native launcher
  then uses the original `easyeffects --service-mode` command directly.
  Exporting this variable in an unrelated terminal will not change an
  already running Quickshell process.
- The guard script itself honors `ALIS_AUDIO_I01_LOCK_QUANTUM=0` when called
  directly. Any setting change only takes effect for *newly created filters*.

## Validation and rollback

1. Restart only EasyEffects via the native Alis toggle (after it fully exits).
   Verify `pw-dump` shows `node.lock-quantum=true` on newly started
   `ee_soe_*` filters; if the property is absent, the test is invalid.
2. Play the same unchanged Local Music track while repeatedly starting new
   Facebook/YouTube/other online clips. Confirm hearing, `pw-top` quantum and
   ERR deltas; repeat after normal logout/reboot and compare browser types.
3. Verify the popup/sidebar/dashboard audio regression, other applications'
   playback, and whether added graph-lock latency affects interactive apps.
4. For an adverse result, stop EasyEffects cleanly; opt out as above, restart
   Alis/Quickshell without the feature and start EasyEffects normally.
   Verify `node.lock-quantum` no longer appears on the new filter nodes.
   If needed, revert only this AUDIO-I01 commit in `dev` after checking its
   exact changed paths; never reset concurrent work or modify `stable`.
5. Do not close the issue until integrated Alis toggle/restart and sustained
   owner listening regression have passed; no assumption of zero artifacts
   outside the tested conditions.

**Limitations:** The property affects scheduling for the connected audio
graph, not merely Convolver. It can influence latency for other software.
It is a mitigation of observed runtime behavior, not a source patch to
EasyEffects' zita-convolver internals.
