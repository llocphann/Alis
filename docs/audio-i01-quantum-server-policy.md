# AUDIO-I01: independent EasyEffects quantum lock for every launch path

**Status: owner-positive manual PipeWireProps A/B; universal server policy requires a new owner live test.**

## Background

With native EasyEffects 8.3.0 the owner experienced a single brief glitch while switching online clips with Local Music continuously playing. A manually guarded EasyEffects process reported `node.lock-quantum=true`, stable quantum, and no audible pops. The later Alis-only launch integration did not cover pre-existing daemons, XDG autostart, terminal launches, and external desktop launchers; a crackling process was observed with every `ee_soe_*` node missing the lock. Do not claim a proven Convolver defect or a fix before the integrated test.

PipeWire supports server-side `node.rules` in `pipewire.conf.d`; rules apply when nodes are created or their properties are updated, **regardless of which client command started them**. The rule here matches only `node.name = ~ee_soe_.*` (EasyEffects output filter nodes), adding `node.lock-quantum = true`. The scheduling graph containing these nodes can still affect latency of other clients. This is **not** `clock.force-quantum`, nor a fixed 1024/2048 setting.

References: [PipeWire server node.rules](https://github.com/PipeWire/pipewire/blob/master/doc/dox/config/pipewire.conf.5.md) and [PipeWire scheduling property](https://docs.pipewire.org/page_man_pipewire-props_7.html).

## Install once, as the affected desktop user (no sudo)

After updating Alis dev, run:

```bash
bash ~/.config/quickshell/alis/scripts/audio/easyeffects-quantum-policy.sh enable
```

This safely installs the bundled fragment at `${XDG_CONFIG_HOME:-$HOME/.config}/pipewire/pipewire.conf.d/90-alis-easyeffects-quantum.conf`. Existing non-identical files and symlinks are **preserved and cause a fail-closed refusal**. The script never starts, stops, or restarts PipeWire/EasyEffects. No privileged writes. To make the new PipeWire server rule effective, log out of the affected desktop session and log back in (or follow a controlled audio-service restart procedure); merely restarting Alis or EasyEffects **does not reload the PipeWire daemon configuration**.

Then start EasyEffects by **any means** (Alis toggle, desktop launcher, terminal, or autostart), and confirm:

```bash
pw-dump | jq -r '.[] | select(.type == "PipeWire:Interface:Node") | .info.props | select((."node.name" // "") | startswith("ee_soe_")) | [."node.name", (."node.lock-quantum" // "ABSENT")] | @tsv'
```

Expected: `true` for every active `ee_soe_*` filter node. Keep the same Local Music track playing and switch new online clips rapidly for 45 seconds, then review audible artifacts, QUANT and ERR in `pw-top`. Repeat after a normal login and check other audio apps and interactive latency before closing AUDIO-I01.

## Opt out or roll back

```bash
bash ~/.config/quickshell/alis/scripts/audio/easyeffects-quantum-policy.sh status
bash ~/.config/quickshell/alis/scripts/audio/easyeffects-quantum-policy.sh disable
```

**Log out and in again** after disabling the policy. The management script removes only an exact byte-for-byte match of its shipped rule and refuses to delete modified/foreign files. To test without *either* the server rule or Alis child-only guard, also set `ALIS_AUDIO_I01_LOCK_QUANTUM=0` before starting the Quickshell process. That older environment flag does **not** disable the server rule by itself.

Package-manager installations intentionally do not mutate per-user PipeWire configuration on upgrade; the explicit enable command is required once. The bundled Alis toggle-specific guard remains available until the server policy passes real playback acceptance and is no longer needed. No change to DSP presets, IR, gain, volume, device route, or global clock metadata is performed.

Run the isolated, no-PipeWire regression with `bash scripts/test-audio-i01-quantum-policy.sh`.
