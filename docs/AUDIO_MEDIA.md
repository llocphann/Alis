# Audio and Media

How audio control and media player integration work in Alis.

## Audio

### PipeWire integration

Alis controls audio through PipeWire via the Quickshell PipeWire module and `wpctl` (WirePlumber's CLI). This means it works with PipeWire out of the box, no PulseAudio compatibility layer needed.

### Volume control

Keybinds and OSD handle the basics:

| Key | Action |
|-----|--------|
| Volume Up / Down | Adjust default sink volume |
| Mute | Toggle default sink mute |
| Mic Mute | Toggle default source mute |

The OSD (on-screen display) appears for volume and brightness changes, showing the current level with an animated bar. IPC volume/mute requests also wake the OSD when a hardware/device-route change is not reflected by the Quickshell PipeWire node. After Alis volume writes, a debounced `wpctl get-volume` read-back feeds the OSD without changing the selected audio output.

### Per-app mixer

The right sidebar (ii) and action center (waffle) include a per-app volume mixer. Each app that's outputting audio appears with its own volume slider. You can mute individual apps or adjust their volume independently.

### EasyEffects

If EasyEffects is installed, Alis detects its virtual sink and attempts to control the physical sink behind it using directed PipeWire links or an exact EasyEffects output-device name. If the route is ambiguous, it does not guess a hardware sink. A toggle in the right sidebar/action center lets you enable/disable EasyEffects.

**Recommended routing:** EasyEffects upstream advises leaving the actual hardware device (for example, ALC257 Analog when it really drives the speakers) as the system default, and letting EasyEffects route application streams through its effects pipeline. Do not forcibly set `easyeffects_sink` as the system default just to obtain audio. Alis still supports a pre-existing virtual default without silently changing it. EasyEffects must point to a working physical output; Alis cannot repair a missing ALSA profile, disconnected port, hardware mute or incorrectly routed stream by changing the OSD.

**Read-only diagnosis when speakers are silent or IPC OSD is missing:**
```sh
wpctl status
pactl get-default-sink
pactl list short sinks
pactl list short sink-inputs
wpctl get-volume @DEFAULT_AUDIO_SINK@
pw-link -l
```

Compare the active application stream and EasyEffects output links with the physical playback node. Check the selected ALC257 profile, port (Speakers vs Headphones) and mute in `pavucontrol` or `wpctl`. Switching defaults changes where **new** streams auto-connect; inspect current streams separately. No automatic hardware fallback is performed because selecting the wrong port could silence a working route.

References: [EasyEffects upstream routing warning](https://github.com/wwmm/easyeffects#warning), [WirePlumber wpctl documentation](https://pipewire.pages.freedesktop.org/wireplumber/man/wpctl.html).

The Equalizer Phase 1 capability is disabled by default and is separate from normal Media playback. EasyEffects is its first optional backend, while `socat` is used only as an optional transport to the local EasyEffects control socket. If either the backend or transport is unavailable, the Equalizer capability remains unavailable and playback continues normally.

Native EasyEffects and Flatpak installations can be detected at runtime. Package-managed installs therefore do not need to hard-depend on EasyEffects or `socat`; users who want the Equalizer controls can install or opt into those components separately.

### IPC

```bash
alis audio volumeUp         # Increase volume
alis audio volumeDown       # Decrease volume
alis audio mute             # Toggle output mute
alis audio micMute          # Toggle mic mute
```

## Media players

### MPRIS support

Alis picks up any MPRIS-compatible media player automatically. Spotify, Firefox, mpv, VLC, Celluloid, Amberol, whatever speaks MPRIS shows up in the media controls.

The media player widget appears in:
- The bar (compact now-playing indicator)
- Media controls popup (`iiMediaControls`)
- Right sidebar
- Waffle action center

### MPD and rmpc

`rmpc` is an MPD client; neither it nor MPD exposes MPRIS by itself. Alis therefore keeps Media on its normal MPRIS boundary and uses `mpd-mpris` as the bridge. Arch audio/full-experience packages include `mpd-mpris`; existing repo-managed Arch installs receive it through required migration `042-mpd-mpris-bridge` on `alis update`/migration. Its default user service connects to MPD on `localhost:6600`.

Alis probes for the `mpd-mpris` binary and watches the MPD/PipeWire session. For the normal local endpoint (`localhost/127.0.0.1:6600`) it starts the distro-provided `mpd-mpris.service` when needed. If Left Sidebar Music is configured for another host, port, or Unix socket, Alis launches a shell-owned `mpd-mpris` instance named `org.mpris.MediaPlayer2.mpd.alis` with that exact endpoint instead of reusing an unrelated default bridge. The bridge then appears through the same Quickshell MPRIS service as every other player, so the Bar, Media popup and Sidebars observe one playback session. If the bridge binary/service is unavailable, MPD protocol playback remains usable and only MPRIS-wide shell integration is reduced.

NixOS/Home Manager users can still manage their normal MPD/MPRIS services through `services.mpd-mpris`; Alis does not overwrite those unit definitions.

### Player prioritization

When multiple players are active, Alis picks the most relevant one:

1. A player that's currently playing beats one that's paused
2. The user's manually selected ("tracked") player beats auto-detection
3. If nothing is playing, the last active player stays visible

### Local Music

The left sidebar **Music** tab is a frontend for the user's MPD library. MPD owns the database, saved playlists and active queue; Alis does not create a second player process. The default endpoint is `127.0.0.1:6600`, configurable in Settings. The optional local folder field is only a path override for resolving cover files when MPD cannot report `music_directory`.

Songs come from MPD `listallinfo`; saved MPD playlists, folder collections and the live MPD queue are selectable directly in the sidebar. Double-clicking a song appends that database URI to the existing MPD queue with `addid` and immediately starts the exact appended entry with `playid`, so existing queued tracks are preserved. Queue rows can be removed individually through MPD `deleteid`, and the Queue view exposes a Clear action backed by MPD `clear`. Starting a collection still replaces the MPD queue with that collection. Database refresh calls MPD `update`.

Normal transport integration uses the endpoint-matched `mpd-mpris` bridge: play/pause, previous/next, seeking, volume and shuffle prefer the MPD MPRIS player exposed through `MprisController`. Direct MPD commands are only a graceful fallback or are used for MPD-only operations such as queue replacement/database update. Bar, Media Popup and other media surfaces therefore observe the same session.

The sidebar now-playing surface reuses the same `PlayerControl` component as the Bar Media popup for artwork, progress and transport controls. `PlayerControl` still supports its optional CAVA wave for owners that need it, but the Bar Media popup disables that decorative wave because its EQ DSP panel already provides the live analyzer. Songs, Playlists and Queue are explicit scrollable views; Songs/Queue use compact 50 px rows, the Queue has per-track remove plus Clear controls, and the Songs search field is height-capped so it cannot consume the library viewport. Song rows resolve folder covers first; when no local cover file exists, the MPD helper reads `albumart` (then `readpicture` for embedded art), caches one image per album/folder under the user cache directory, and exposes it to QML as a `file://` URL.

The **Lyrics** tab is local-only. For the current MPD track, Alis looks beside the resolved audio path for same-name `.lrc` (preferred) or `.txt` sidecars. Timed LRC lines follow MPRIS/MPD playback position; unsynchronized text remains manually scrollable. This tab performs no network lyric lookup.

The historical `YtMusic` source remains only as compatibility code and is no longer routed from the Left Sidebar or its Settings UI.

### Media controls layouts

The media controls popup has multiple layout presets you can choose from in Settings. Different presets show different arrangements of album art, controls, and track info.

