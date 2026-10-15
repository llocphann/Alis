# AUDIO-I01 — Native EasyEffects XDG autostart guard

The owner found an active generated systemd user unit `app-com.github.wwmm.easyeffects@autostart.service` from `~/.config/autostart/com.github.wwmm.easyeffects.desktop`, with `Exec=easyeffects --hide-window --service-mode` and live `ee_soe_*` nodes missing `node.lock-quantum`. Manually terminating EasyEffects and relaunching made the playback clean. This points to a process startup difference but does not yet prove which part (missing property or timing) caused the audible crackle.

## Mechanism

The Alis-managed unit drop-in adds `After=pipewire.service wireplumber.service` and `Environment="PIPEWIRE_PROPS={ node.lock-quantum = true }"` to exactly that generated user service. systemd drop-ins are supported for generated XDG autostart services, without rewriting the owner's desktop entry. `After=` orders already participating units and does **not** guarantee they will be started or fully ready; the environment is applied to newly launched native EasyEffects. This does not set global force-quantum, change IR/EQ or routing, or add any blind process restarts.

## Enable once (no sudo)

Update Alis dev, then run:

```bash
bash ~/.config/quickshell/alis/scripts/audio/easyeffects-autostart-guard.sh enable
systemctl --user daemon-reload
systemctl --user cat 'app-com.github.wwmm.easyeffects@autostart.service'
```

Expected: the unit's printed drop-in contains `PIPEWIRE_PROPS={ node.lock-quantum = true }`. The script requires the known native `.desktop` Exec line; it refuses foreign/modified/symlink drop-ins and never edits the `.desktop`. Log out, then log back in so XDG autostart launches a **new** EasyEffects process. Confirm by `pw-dump` that `ee_soe_*` node props show `node.lock-quantum=true`, and test the exact Local Music + new-online-clip workload. A manual restart without a new login is not equivalent acceptance of the generated autostart unit.

## Revert safely

```bash
bash ~/.config/quickshell/alis/scripts/audio/easyeffects-autostart-guard.sh disable
systemctl --user daemon-reload
```

Log out and back in. The manager removes only its own exact unchanged drop-in. This does not automatically disable separately installed PipeWire `node.rules` or the older Alis-launcher guard, which must be handled independently when doing a full unguarded A/B.

Owner acceptance requires cold-login autostart with lock active and no crackle, plus no undesirable graph latency on other apps. Not validated on the owner's runtime yet.

References: https://man7.org/linux/man-pages/man8/systemd-xdg-autostart-generator.8.html and https://www.man7.org/linux/man-pages/man5/systemd.unit.5.html
