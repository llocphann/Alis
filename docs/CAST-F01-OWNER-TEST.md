# CAST-F01 — Owner acceptance: Classroom Project & Cast

Implementation branch: `feature/CAST-F01-project-cast`; Draft PR: https://github.com/llocphann/Alis/pull/122; Issue: https://github.com/llocphann/Alis/issues/121.

This feature must **not** be merged/marked Owner verified based only on CI. No system or local Owner configuration should be modified by the test automation. Screenshots, logs and TV identifiers should remain private unless explicitly approved.

## Before connecting a TV

1. Install/run the CAST-F01 branch in an isolated approved Alis profile; do **not** replace the Owner's production Quickshell while teaching.
2. Read-only capabilities check: `python3 scripts/CAST-F01-capability-probe.py`. Review `installed`, `niri_outputs`, user portal/PipeWire services, Wi-Fi P2P/encoders. `NOT_TESTED` is not PASS.
3. In Utilities → Display Mode → Wireless TV, click **Scan TVs**. If scan reports a missing daemon, the installed build may only have the GTK app; **Open app** is the supported fallback. Do not silently install an AUR package, change NetworkManager from iwd to wpa_supplicant, modify firewall, or restart services.
4. For native backend validation, GNOME Network Displays **0.98+** with daemon/stream components is required; its upstream D-Bus interface is `org.gnome.NetworkDisplays.Manager`. The GNOME service can launch the system ScreenCast permissions picker; choose the window/monitor to share. Alis must not bypass it.

## Before trying the wireless UI: verify the scan path

Run these only in the **Owner-approved isolated CAST-F01 test session**, not during a class:

```bash
python3 scripts/CAST-F01-network-displays.py scan
busctl --user --json=short get-property \
  org.gnome.NetworkDisplays.Manager \
  /org/gnome/NetworkDisplays/Manager \
  org.gnome.NetworkDisplays.Manager Displays
```

Expected Python JSON: `ok: true`, `backend: true`, `streamReady: true`, plus a `displays` array containing the **actual TV** when it is discoverable. `ok: true` with `displays: []` means the D-Bus call worked but **no receiver was discovered**; it is **not** a proven successful TV scan. `streamReady: false` means daemon discovery works but the upstream native stream helper required for Connect is missing at `/usr/libexec/gnome-network-displays-stream`. Verify both `gnome-network-displays-daemon` and that installed executable exist before testing Connect. Scan from Alis now performs up to five bounded discovery attempts (not endless background polling).

The direct busctl command is a diagnostic cross-check, not an installation step. If the TV appears in busctl but not in the bridge output, report **parser bug**. If it appears in the bridge but not the Alis selector, report **QML UI state bug**. If both return no TVs, the issue may be **receiver mode, Wi-Fi P2P, Avahi/mDNS, NetworkManager, AP isolation or codecs**. Do not change the Wi-Fi backend or disable firewalls simply to make the test pass. In particular, GStreamer codecs affect connecting/streaming, but may not explain why a receiver is absent from discovery.

**This procedure distinguishes working software enumeration from actual discovery over a real classroom network. Neither mocked CI tests nor presence of a running D-Bus manager can guarantee a TV will be found on every network.**

## Wired HDMI / video-capable USB-C

- Connect TV and confirm make/model/connector displays without confusing it with another monitor or serial. Plain data-only USB-C cannot be expected to output video.
- Test **Extend**, **Mirror**, **Second screen only**, **Primary only** with both 1080p/4K TV profiles if available. Check slides, video motion, cursor, fractional scaling and the presenter-note window while focus is elsewhere.
- Test HDMI/DP audio selection: new video and an **already-playing** video; ensure volume/mute behave and physical TV produces sound. `wpctl set-default` alone does not move every previously routed app stream.
- In Alis-managed TV-only, unplug external cable: laptop screen must return and refresh (moving content), not simply become a logically active but black output. Repeat with physical TV power cycle and, if supported, suspend/resume.
- Manually select another sound device during TV session. Ending projection **must not** override that manual choice. If EasyEffects is default, no silent automatic DSP bypass or EQ reset is allowed.

## Wireless Miracast / Chromecast

- Put actual TV in its Miracast/Screen Mirroring or Chromecast receiving mode. Click **Scan TVs**. Confirm the exact TV name/protocol from discovery, not a fabricated device.
- Click the TV, **Connect**, and grant consent in the system screen/window chooser. The UI must distinguish **connecting** from **systemd stream running**. A launched unit is **not proof** that the TV is displaying frames.
- Confirm changing slides and actual moving video on the TV; play audio and confirm sound comes from the TV. Test a media app opened **before** connection and another opened **after**; note separately if manual stream re-routing is still needed.
- Hit **Disconnect** and confirm both picture and sound stop on TV, no orphan streaming unit remains and previous speaker returns unless another output was manually selected. Test rapidly disconnecting during the connecting phase; retry Disconnect when backend reports failure.
- Repeat at least 3 sessions and a 30-minute class-length test; verify Wi-Fi Internet works during Miracast P2P. On classroom/guest Wi-Fi test whether Chromecast is visible (AP/client isolation and mDNS can block discovery). Do not change networking policy to make one TV appear.
- Test missing daemon (native Scan yields a clear error but GTK **Open app** remains available), no TV found, TV sleeping/missing, cancelled screencast permission dialog, unsupported codec and stream exit.

## Source / CI checks

```bash
python3 scripts/test-CAST-F01-display-stage.py
python3 scripts/test-CAST-F01-audio-stage.py
python3 scripts/test-CAST-F01-wireless-stage.py
python3 scripts/test-CAST-F01-capabilities.py
python3 scripts/test-abyss-display-mode.py
python3 scripts/test-UTIL-F01-source-delivery.py
```

This covers source and mocked D-Bus behavior, not installed GPU/network hardware or QML rendering. If entire-repo CI fails for unrelated existing tests, record separate issues and **do not** assert global PASS.

## Acceptance record (Owner fills after tests)

- Tested niri/Quickshell/PipeWire/GNOME Network Displays versions, GPU and actual TV model:
- HDMI/USB-C modes, true picture on TV and internal fallback: PASS / FAIL / NOT TESTED
- Wired TV audio and previous speaker restore: PASS / FAIL / NOT TESTED
- Native TV discovery and identified protocol: PASS / FAIL / NOT TESTED
- Wireless picture + TV audio + disconnect/reconnect: PASS / FAIL / NOT TESTED
- 30-minute class trial, Internet concurrent, EasyEffects, presenter privacy: PASS / FAIL / NOT TESTED
- Logs/evidence reference (sanitized):
- Owner approval to move Draft PR into review: YES / NO

**Never infer Owner verification from code completion.**
