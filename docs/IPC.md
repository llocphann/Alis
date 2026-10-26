# IPC Reference

Alis exposes IPC targets you can call from Niri keybinds, scripts, or your terminal. The public command and session identity are `alis`; the retired `alis` command is unavailable.

> **Quick discovery:** `alis help` lists all targets, `alis <target> --help` shows available functions.
> Shell completions: `eval "$(alis completions bash)"` (also zsh, fish).

From terminal (for testing, or showing off):

```bash
alis <target> <function>
```

In Niri config (for actual keybinds):

```kdl
bind "Key" { spawn "alis" "<target>" "<function>"; }
```

For low-level debugging, use `alis ipc <target> <function>`.

---

## Available Targets

Alis shell actions available for scripts and keybinds.

### dev

Development navigation for loading lazy surfaces and internal views without
automating pointer or keyboard input. Destination identifiers are stable and
returned as JSON by `list`.

| Function | Description |
|----------|-------------|
| `list` | Return the destination inventory as JSON |
| `open` | Open a destination by semantic identifier |
| `close` | Close development-opened surfaces and clear the request |
| `current` | Return the current destination or `closed` |

```bash
alis dev list | jq -r '.[].id'
alis dev open sidebar-left/anime-schedule
alis dev close
alis dev audit
alis dev audit sidebar-left/ai settings/ai
alis dev audit --all --all-families
```

`alis dev audit` selects destinations related to changed area-specific files in
the current worktree. Destination arguments select an exact scope, while
`--all` requests every safe destination and `--all-families` includes both ii
and waffle. Each visited destination is closed again and new QML warnings or
errors are attributed to the destination that triggered them. Destructive
actions such as locking, recording, power commands, and wallpaper mutation are
excluded.

---


### overview

Toggle the workspace overview panel. The one with all your windows looking tiny and organized.

| Function | Description |
|----------|-------------|
| `toggle` | Open/close overview |
| `open` | Open overview |
| `close` | Close overview |
| `clipboardToggle` | Open clipboard search, or close if already open |
| `actionOpen` | Open overview in action search mode |
| `toggleReleaseInterrupt` | Clear the super-key release interrupt flag |

```kdl
bind "Mod+Space" { spawn "alis" "overview" "toggle"; }
```

---

### taskview

Compatibility entry point for task navigation. On Waffle it opens the Waffle Task View; on Abyss and legacy ii it opens the normal Overview in task-view mode.

| Function | Description |
|----------|-------------|
| `toggle` | Open/close the active family's task navigator |
| `open` | Open the active family's task navigator |
| `close` | Close the active family's task navigator |

---

### overlay

Floating tools (Super+G): notes, images, crosshair, recorder, resources and other pinnable desktop tools.

| Function | Description |
|----------|-------------|
| `toggle` | Open/close Floating tools |

```kdl
bind "Super+G" { spawn "alis" "overlay" "toggle"; }
```

---

### clipboard

Clipboard history panel. Because Ctrl+V only remembers one thing, and that's not enough for power users.

| Function | Description |
|----------|-------------|
| `toggle` | Open/close panel |
| `open` | Open panel |
| `close` | Close panel |

```kdl
bind "Super+V" repeat=false { spawn "alis" "clipboard" "toggle"; }
```

---

### altSwitcher

Alt+Tab window switcher. Works across workspaces, unlike some other implementations we won't name.

| Function | Description |
|----------|-------------|
| `toggle` | Toggle switcher |
| `open` | Open switcher |
| `close` | Close switcher |
| `next` | Focus next window |
| `previous` | Focus previous window |

```kdl
bind "Alt+Tab" { spawn "alis" "altSwitcher" "next"; }
bind "Alt+Shift+Tab" { spawn "alis" "altSwitcher" "previous"; }
```

---

### region

Region selection tools. Screenshots, OCR, recording. Draw a box, get stuff done.

| Function | Description |
|----------|-------------|
| `screenshot` | Take a rectangular region screenshot |
| `search` | Image search (Google Lens) |
| `googleLens` | Start a region capture for Google Lens |
| `ocr` | OCR text recognition |
| `record` | Record region (no audio) |
| `recordWithSound` | Record region with audio |
| `menu` | Open the unified snip menu, optionally restoring its last toolbar choice |
| `dismiss` | Close the selector overlay |
| `current` | Return the selector state (open/action/mode) as JSON |

```kdl
bind "Super+Shift+S" { spawn "alis" "region" "screenshot"; }
bind "Super+Shift+X" { spawn "alis" "region" "ocr"; }
bind "Super+Shift+A" { spawn "alis" "region" "search"; }
bind "Ctrl+Shift+S" { spawn "alis" "region" "menu"; }
```

---

### voiceSearch

Provider-neutral voice input for web search and AI dictation. Auto prefers local whisper.cpp, then connected Groq, Gemini and OpenAI speech backends. Keys stay in the system keyring and are passed to adapters through the process environment.

| Function | Description |
|----------|-------------|
| `start` | Start recording for voice web search |
| `stop` | Stop the active recording or transcription |
| `toggle` | Toggle recording |
| `refresh` | Re-detect local and connected speech backends |
| `status` | Return backend, local detection, recording and error state as JSON |

```kdl
bind "Super+Shift+V" { spawn "alis" "voiceSearch" "toggle"; }
```

---

### session

Power menu. Logout, suspend, reboot, shutdown. The "I'm done for today" buttons.

| Function | Description |
|----------|-------------|
| `toggle` | Open/close session menu |
| `open` | Show session screen |
| `close` | Hide session screen |

```kdl
bind "Super+Shift+E" { spawn "alis" "session" "toggle"; }
```

---

### lock

Lock screen. For when you need to pretend you're working.

| Function | Description |
|----------|-------------|
| `activate` | Lock the screen |
| `deactivate` | Cancel lock and mark screen unlocked |
| `status` | Return lock state (`locked`, `activating`, or `unlocked`) |
| `focus` | Refocus the lock screen input |

```kdl
bind "Super+Alt+L" allow-when-locked=true { spawn "alis" "lock" "activate"; }
```

---

### memory

Memory pressure monitoring for JSGCHeap accumulation (Qt V4 memfd leak). Notifies user when memory is high, lets them decide when to restart.

| Function | Description |
|----------|-------------|
| `stats` | Return JSON with deleted mappings count, threshold, and state |
| `collect` | Force JavaScript garbage collection |
| `restart` | Restart the shell to free accumulated memory |
| `dismiss` | Dismiss the memory warning notification |
| `reset` | Reset notification state (re-enables warnings) |

---

### cheatsheet

Keyboard shortcuts reference. For when you forget what you just configured five minutes ago.

| Function | Description |
|----------|-------------|
| `toggle` | Open/close cheatsheet |
| `open` | Show cheatsheet overlay |
| `close` | Hide cheatsheet overlay |

```kdl
bind "Super+Slash" { spawn "alis" "cheatsheet" "toggle"; }
```

---

### closeConfirm

Close window confirmation dialog. Shows a prompt before closing the focused window. Useful if you're the type who accidentally closes things and then regrets it.

| Function | Description |
|----------|-------------|
| `trigger` | Show close confirmation for focused window |
| `triggerWindow <windowId> <appId>` | Close or confirm the exact window captured by `alis close-window` |
| `triggerWindowContext <windowId> <appId> <workspaceId>` | Same exact-window request with the captured Niri workspace, used internally to preserve source-output placement |
| `close` | Dismiss the dialog without closing |

```kdl
bind "Mod+Q" repeat=false { spawn "alis" "close-window"; }
```

By default, confirmation is disabled (closes immediately). Enable it in settings or config:

```json
"closeConfirm": {
  "enabled": true
}
```

---

### settings

Open or toggle the settings window. GUI config so you don't have to edit JSON by hand.

| Function | Description |
|----------|-------------|
| `open` | Open the settings window |
| `toggle` | Toggle settings (overlay mode toggles, window mode opens) |

```kdl
bind "Super+Comma" { spawn "alis" "settings"; }
```

---

### settingsNav

Navigate the settings overlay to a specific page (same as clicking the nav rail). Opening the window itself is the `alis settings` CLI command (target `settings` above).

| Function | Description |
|----------|-------------|
| `page(index)` | Open the overlay and jump to page `index` |
| `count` | Number of settings pages |
| `current` | Current page index, or `-1` when no page is open |

```sh
alis ipc settingsNav page 5
```

---

### controlPanel

Quick settings panel. Toggles, sliders, and system controls without opening full settings.

| Function | Description |
|----------|-------------|
| `toggle` | Open/close control panel |
| `open` | Open control panel |
| `close` | Close control panel |

---

### dashboard

Centered welcome hub panel (ii family): greeting, clock, notifications, media, weather, calendar, todo, system usage and GitHub activity.

| Function | Description |
|----------|-------------|
| `toggle` | Open/close dashboard |
| `open` | Open dashboard |
| `close` | Close dashboard |

---

### sidebarLeft

Left sidebar (AI chat, apps).

| Function | Description |
|----------|-------------|
| `toggle` | Open/close left sidebar |
| `open` | Show left sidebar |
| `close` | Hide left sidebar |
| `expand` | Open the sidebar in its wide Ctrl+O layout |
| `compact` | Return the sidebar to its normal width |
| `status` | Return open, expanded and detached state as JSON |
| `detach` | Move AI chat into its Ctrl+P standalone window |
| `attach` | Return AI chat from the standalone window to the sidebar |

---

### sidebarRight

Right sidebar (quick toggles, notepad, settings).

| Function | Description |
|----------|-------------|
| `toggle` | Open/close right sidebar |
| `open` | Show right sidebar |
| `close` | Hide right sidebar |

---

### bar

Top bar visibility.

| Function | Description |
|----------|-------------|
| `toggle` | Show/hide bar |
| `open` | Show bar |
| `close` | Hide bar |

---

### globalActions

Command palette / action registry. Search and execute shell actions from scripts or keybinds.

| Function | Description |
|----------|-------------|
| `run <id>` | Execute action by ID without arguments |
| `runWithArgs <id> <args>` | Execute action by ID with an argument string |
| `list [category]` | List all actions, optionally filtered by category |
| `search <query>` | Fuzzy search actions by name/description/keywords |
| `open` | Open the overview in action mode |

Categories: `system`, `appearance`, `tools`, `media`, `settings`, `custom`.

```kdl
bind "Super+Slash" { spawn "alis" "globalActions" "open"; }
bind "Super+M" { spawn "alis" "globalActions" "run" "toggle-mute"; }
```

---

### wallpaperSelector

Wallpaper picker with grid, coverflow and compact launcher styles.

| Function | Description |
|----------|-------------|
| `toggle` | Open/close wallpaper selector |
| `open` | Open wallpaper selector |
| `close` | Close wallpaper selector |
| `openLauncher <mode>` | Open the compact launcher in `static` or `animated` mode |
| `toggleOnMonitor <name>` | Open wallpaper selector on a specific monitor |
| `random` | Pick a random wallpaper from the current folder |
| `status` | Return picker style, open surface, target monitor and selection target as JSON |

```kdl
bind "Ctrl+Alt+T" { spawn "alis" "wallpaperSelector" "toggle"; }
bind "Ctrl+Alt+A" { spawn "alis" "wallpaperSelector" "openLauncher" "animated"; }
```

---

### wallpaperLauncher

Navigation and apply controls for the compact wallpaper launcher.

| Function | Description |
|----------|-------------|
| `next` | Select the next wallpaper |
| `previous` | Select the previous wallpaper |
| `applyCurrent` | Apply the selected wallpaper and keep the launcher open |
| `status` | Return launcher mode, index, count, path, target and monitor as JSON |

Open the launcher before calling its controls:

```bash
alis wallpaperSelector openLauncher static
alis wallpaperLauncher next
alis wallpaperLauncher applyCurrent
```

---

### coverflowSelector

Wallpaper coverflow (3D card) picker.

| Function | Description |
|----------|-------------|
| `toggle` | Open/close coverflow selector |
| `open` | Open coverflow selector |
| `close` | Close coverflow selector |

---

### mediaControls

Floating media controls panel.

| Function | Description |
|----------|-------------|
| `toggle` | Open/close media controls |
| `open` | Show media controls |
| `close` | Hide media controls |

---

### osk

On-screen keyboard.

| Function | Description |
|----------|-------------|
| `toggle` | Show/hide on-screen keyboard |
| `open` | Show on-screen keyboard |
| `close` | Hide on-screen keyboard |

---

### audio

Volume and mute control.

| Function | Description |
|----------|-------------|
| `volumeUp` | Increase volume |
| `volumeDown` | Decrease volume |
| `mute` | Toggle speaker mute |
| `micMute` | Toggle microphone mute |
| `playEvent <event>` | Play a shell event sound (e.g. `notification`, `batteryLow`, `timerDone`), honoring the user's per-event override |

---

### brightness

Display brightness control.

| Function | Description |
|----------|-------------|
| `increment` | Increase brightness |
| `decrement` | Decrease brightness |
| `sleepBegin` | Mark the brightness service asleep so screen changes do not rebuild monitor state |
| `restoreAfterWake` | Resume the brightness service and restore each monitor's last-good brightness |

---

### mpris

Media player control. Automatically detects and uses YtMusic controls when active, otherwise uses the active MPRIS player.

| Function | Description |
|----------|-------------|
| `pauseAll` | Pause all players |
| `playPause` | Toggle play/pause (uses YtMusic if active) |
| `previous` | Previous track (uses YtMusic if active) |
| `next` | Next track (uses YtMusic if active) |

```kdl
bind "Ctrl+Mod+Space" { spawn "alis" "mpris" "playPause"; }
bind "Mod+Alt+N" { spawn "alis" "mpris" "next"; }
bind "Mod+Alt+P" { spawn "alis" "mpris" "previous"; }
```

---

### ytmusic

Direct YtMusic player control. Use these if you want to control YtMusic specifically, regardless of what other players are active.

| Function | Description |
|----------|-------------|
| `playPause` | Toggle YtMusic play/pause |
| `next` | Play next track in YtMusic |
| `previous` | Play previous track in YtMusic |
| `stop` | Stop YtMusic playback |

```kdl
bind "Mod+M+Space" { spawn "alis" "ytmusic" "playPause"; }
```

---

### osdVolume

On-screen volume indicator.

| Function | Description |
|----------|-------------|
| `trigger` | Show volume OSD |
| `toggle` | Toggle volume OSD |
| `hide` | Hide volume OSD |

---

### osdInput

Input-device OSD notifications. Used by keyboard/touchpad helpers to show the effective input state.

| Function | Description |
|----------|-------------|
| `touchpad <state>` | Show touchpad state (`on` or `off`) |

---

### cliphistService

Clipboard history service. The backend that makes clipboard panel work. You probably don't need to call this directly.

| Function | Description |
|----------|-------------|
| `update` | Refresh clipboard history |

---

### ai

Shared multi-provider AI service. It supports Gemini, OpenAI-compatible chat and Responses APIs, Mistral and Anthropic; live provider catalogs are normalized into capability-aware model records. Catalog visibility is separate from execution readiness, so public model lists remain browseable without pretending an API key exists. OpenCode Zen and Go resolve their current model lists and per-model API routes dynamically. Normal shell tools use typed actions and approval cards, while arbitrary commands are isolated in Advanced mode.

| Function | Description |
|----------|-------------|
| `ensureInitialized` | Force-load models, provider catalogs and API keys |
| `diagnose` | Dump current AI, catalog and tool state as JSON |
| `refreshCatalog` | Refresh every live provider model catalog |
| `catalog <query>` | Search up to 100 normalized live model records |
| `providers` | Return provider health, key state and live model counts |
| `run <text>` | Send a message or compatibility `/command` to AI chat |
| `runGet <text>` | Run an AI command and return the last response |

---

### packageSearch

Package search service. Searches pacman repos and installed packages.

| Function | Description |
|----------|-------------|
| `search <query>` | Start a package search |
| `results` | Print current search results |

---

### appCatalog

App catalog service. Browse, search, and install curated applications.

| Function | Description |
|----------|-------------|
| `refresh` | Refresh the installed-state cache |
| `search <query>` | Filter catalog entries by query |
| `install <id>` | Install app by catalog ID |
| `list` | List catalog apps with install status and descriptions |

---

### gamemode

Performance mode for gaming. Auto-detects fullscreen apps and disables animations/effects. Can also be toggled manually for those stubborn games that don't go fullscreen properly.

| Function | Description |
|----------|-------------|
| `toggle` | Toggle gamemode on/off |
| `activate` | Force enable gamemode |
| `deactivate` | Force disable gamemode |
| `status` | Print current gamemode state (e.g. `active (manual)`, `inactive (off)`) |

```kdl
bind "Super+F12" { spawn "alis" "gamemode" "toggle"; }
```

---

### panelFamily

Switch between Abyss (`abyss`, default) and Waffle (`waffle`). Historical `ii` values migrate to Abyss, preserving enabled modules and shared configuration.

| Function | Description |
|----------|-------------|
| `cycle` | Cycle to next panel family (abyss → waffle → abyss) |
| `set` | Set specific family (`"abyss"` or `"waffle"`; `"ii"` is a compatibility alias for Abyss) |

```kdl
bind "Mod+Shift+W" { spawn "alis" "panelFamily" "cycle"; }
```

---

### shellLayout

Dedicated persistent-shell layout editing and diagnostics. It is independent
from desktop widget edit mode. It moves the ii bar and dock, swaps semantic ii
sidebars between physical edges, resizes sidebar roles, and moves the Waffle
taskbar through validated operations over canonical Config keys.

| Function | Description |
|----------|-------------|
| `toggle` | Enter or leave shell edit mode |
| `open` | Enter shell edit mode on the focused output |
| `openOn` | Enter shell edit mode on a named output |
| `close` | Leave shell edit mode and clear transient selection |
| `select` | Select a surface for deterministic editing or diagnostics |
| `lift` | Select and lift a surface for placement |
| `preview` | Preview a legal slot without writing Config |
| `place` | Commit the lifted surface to a validated slot; occupied sidebar edges require the same call twice |
| `cancel` | Cancel the current lift, preview, confirmation or gesture |
| `dragStart` | Lift a surface and start a pointer-style drag |
| `dragUpdate` | Feed screen coordinates to the active drag; previews the nearest legal edge |
| `dragEnd` | Drop the dragged surface: commits the previewed edge (occupied sidebar edges swap directly) or cancels in the center |
| `reset` | Restore one surface to its default placement and supported dimensions |
| `setProperty` | Set a supported surface property (`sizeMode`, sidebar `height`, sidebar `thickness`, or dock `thickness`) |
| `handleEscape` | Apply editor Escape priority: cancel pending work, then leave edit mode |
| `status` | Return edit-session, host diagnostics and active-family surface descriptors as JSON |
| `validate` | Validate a surface and slot combination without changing Config |

```bash
alis shellLayout open
alis shellLayout lift featureSidebar
alis shellLayout preview right
alis shellLayout place right   # prepares the occupied-edge swap
alis shellLayout place right   # confirms and commits it
alis shellLayout setProperty featureSidebar sizeMode fit
alis shellLayout reset featureSidebar
alis shellLayout close
```

```kdl
bind "Super+W" { spawn "alis" "shellLayout" "toggle"; }
```

---

### shellUpdate

Shell update checker. Monitors the git repo for new commits and shows an update overlay.

| Function | Description |
|----------|-------------|
| `toggle` | Open/close update overlay |
| `open` | Open update overlay |
| `close` | Close update overlay |
| `check` | Check for updates now |
| `performUpdate` | Run the update |
| `dismiss` | Dismiss update notification |
| `undismiss` | Un-dismiss update notification |
| `diagnose` | Dump update state as JSON |

---

### notificationCenter

Family-aware notification history surface. On Material ii this opens the standalone bottom-right Notification Center; on Waffle it routes to the native Waffle notification center. The CLI alias is `notification-center`.

| Function | Description |
|----------|-------------|
| `toggle` | Open/close notification history |
| `open` | Open notification history |
| `close` | Close notification history |
| `status` | Return family, open state and resolved output as JSON |

---

### notifications

Notification management.

| Function | Description |
|----------|-------------|
| `test` | Send test notifications |
| `clearAll` | Dismiss all notifications |
| `toggleSilent` | Toggle Do Not Disturb mode |

---

### minimize

Window minimization (Niri workaround - moves windows to hidden workspace).

| Function | Description |
|----------|-------------|
| `minimize` | Minimize focused window |
| `minimizeId` | Minimize a window by Niri window ID |
| `restore` | Restore a minimized window by ID |
| `restoreOriginal` | Restore a minimized window to the workspace it came from |

---

### tiling

Tiling layout overlay. Pick or cycle through tiling presets for the current workspace.

| Function | Description |
|----------|-------------|
| `toggle` | Open/close tiling picker |
| `open` | Open tiling picker |
| `hide` | Close picker and OSD |
| `cycle` | Cycle to next tiling preset (shows OSD) |
| `showOsd` | Flash the current tiling preset OSD |
| `promote` | Promote focused window to master position |

---

### keyboard

Keyboard layout switching (Niri only). Cycles through configured keyboard layouts and queries layout info.

| Function | Description |
|----------|-------------|
| `switchLayout` | Switch to next keyboard layout |
| `switchLayoutPrevious` | Switch to previous keyboard layout |
| `getCurrentLayout` | Get the current layout name |
| `getLayouts` | Get all configured layout names (JSON array) |

```kdl
bind "Mod+Alt+K" { spawn "alis" "keyboard" "switchLayout"; }
```

---

### zoom

Screen zoom. Accessibility feature, or for reading tiny UI without pretending your monitor is the problem.

| Function | Description |
|----------|-------------|
| `zoomIn` | Increase compositor zoom |
| `zoomOut` | Decrease compositor zoom |

---

### osd

Shared on-screen display router for the active family. Material, Waffle and Abyss consume internal signals; only the root registers this target.

| Function | Description |
|----------|-------------|
| `trigger` | Show the active family's volume indicator |

Dismiss the active volume indicator through `osdVolume.hide`. The root `osd` router only exposes `trigger`.

---

### abyss

Edit the Abyss module layout on the focused output. The editor uses a draft:
Done saves its changes; Cancel or Escape restores the saved layout.
These methods apply while Abyss is active.

| Function | Description |
|----------|-------------|
| `editLayout` | Open the Abyss module editor on the focused output |
| `cancelEdit` | Cancel editing and restore the saved layout |

```bash
alis abyss editLayout
alis abyss cancelEdit
```

---


### abyssHostProbe

Diagnostic-only IPC in the Abyss critical host. A one-shot
`remountPerimeter` destroys and recreates only the **production
AbyssPerimeter.qml** LazyLoader subtree after 450 ms. It does **not**
switch Waffle/Abyss, rewrite configuration, or restart the shell.
Use only to isolate cold-boot native pointer delivery failures; there
may be a short visual interruption.

| Function | Description |
|----------|-------------|
| `status` | Report production perimeter Loader state |
| `remountPerimeter` | Destroy/recreate only AbyssPerimeter, diagnostic only |

```bash
alis abyssHostProbe status
alis abyssHostProbe remountPerimeter
```

---

### dashboardEscProbe

Read-only per-output Dashboard Escape ownership diagnostic. This inspection does not cancel edits, change focus, close surfaces, or install a timer.

| Function | Description |
|----------|-------------|
| `snapshot` | Return timestamp, active panel family and per-output Dashboard Escape state as JSON |

---

### abyssHoverProbe

Read-only diagnostic snapshots of **production Abyss Screen Edge hover**
during cold start and after Waffle → Abyss. Contains module geometry,
input regions and boolean popup/field lifecycle state. Does not move
the pointer, toggle surfaces or change configuration. Loaded only when
the Abyss critical host is active. For support investigations only.

| Function | Description |
|----------|-------------|
| `snapshot` | Return the current per-output hover, input region and popup lifecycle state as JSON |
| `startFrames` | Explicitly start per-output Qt frameSwapped wall-clock sampling, capped at 600 intervals, with bounded motion and timer-heartbeat records. Disabled before this call; not compositor presentation or GPU timing. |
| `stopFrames` | Stop the requested frame/timer sampling and return per-output counts, interval percentiles and bounded event records as JSON. Zero samples are unavailable evidence, not a successful performance measurement. |
| `refreshMask` | **One-shot experiment**: emit Region.changed for the current input regions, without remount or family switch. Only runs in normal Abyss idle, otherwise skipped. This tests whether resubmitting the shaped input mask restores pointer hover; it is not an automatic startup fix. |
| `swapMask` | Toggle the normal input mask between the original shaped Region and an equivalent Region wrapper. Calling again restores the original identity; no full-output input interception. |
| `remapWindow` | Briefly unmap/remap only the Abyss perimeter window (260 ms), preserving panel family and settings; visible flicker is possible. Diagnostic only. |

```bash
alis abyssHoverProbe snapshot
# Use scripts/collect-abyss-hover-frames.sh for a bounded, source-checked capture.
# When invoking the sampler directly, finish it explicitly:
alis abyssHoverProbe startFrames
alis abyssHoverProbe stopFrames
# Only for guided debugging, before the Waffle workaround:
alis abyssHoverProbe refreshMask
alis abyssHoverProbe swapMask
alis abyssHoverProbe remapWindow
```

---

### aqua

Optional Alis-Companion Companion chat and diagnostics. The compatibility target remains available when the package is absent. `chat`
toggles the speech editor and requests keyboard focus on the permitted output.
`status` reports bounded visibility, bridge, field/scene and placement state
without changing preferences. Super + Alt + Comma opens or closes chat; Enter
sends and Escape closes it.

| Function | Description |
|----------|-------------|
| `chat` | Toggle the Companion chat editor (Super+Alt+Comma) |
| `status` | Return bounded JSON explaining Companion visibility and placement on each output |

```bash
alis aqua status
```

---

### alisCompanion

Manage discovery of the separately installed [Alis-Companion](https://github.com/llocphann/Alis-Companion) package. Refresh unloads the current Companion session, rechecks the compatible local package and reloads it only if enabled. It never installs a package, changes preferences or loads a model.

| Function | Description |
|----------|-------------|
| `refresh` | Recheck the optional package after installation, update or removal |
| `status` | Report optional installation and Companion runtime status |

```bash
alis ipc alis-companion refresh
alis ipc alis-companion status
```

---

### integrations

Alis-Intergration: optional TLP, Thinkfan and Obsidian package discovery. Integration selections
remain under Settings → Integrations; discovery does not install or enable a
package.

| Function | Description |
|----------|-------------|
| `refresh` | Recheck the installed Alis-Intergration package identity and reload selected integrations |
| `status` | Return package availability, enabled state, diagnostic, version, source SHA and selected integration states as JSON |

---

### alis-intergration

Legacy API 1 alias for `integrations`; both targets use the same package, settings and worker owner.

| Function | Description |
|----------|-------------|
| `refresh` | Recheck Alis-Intergration through the preserved alias |
| `status` | Return the same Integration status JSON |

---

### perfProbe

Opt-in, bounded QML/JS runtime performance probe (`PERF-F01`). Zero idle overhead when inactive; started only by explicit user or CLI request (`alis debug perf`).

| Function | Description |
|----------|-------------|
| `start(optionsJson)` | Start a bounded QML/JS performance probe session with explicit duration and sample caps |
| `status` | Return current probe session status, sample counts, and active surface snapshot as JSON |
| `stop` | Stop the active probe session and return frame timing, event-loop heartbeat, and span records as JSON |
| `cancel` | Abort the active probe session and discard buffered samples |
| `snapshot` | Return a one-shot point-in-time shell architecture and active surface inventory snapshot as JSON |
| `recordSpan(moduleId, spanName, durationMs)` | Record a bounded instrumented lifecycle or interaction span while a probe session is active |

```bash
alis perfProbe snapshot
alis debug perf start --duration 10
```

---

## Waffle-Specific Targets

These targets only work when using the Waffle (Windows 11) panel style.

### search

Waffle start menu / search.

| Function | Description |
|----------|-------------|
| `toggle` | Open/close start menu |
| `open` | Open start menu |
| `close` | Close start menu |

---

### wactionCenter

Waffle action center (quick settings).

| Function | Description |
|----------|-------------|
| `toggle` | Open/close action center |
| `open` | Open action center |
| `close` | Close action center |

---

### wnotificationCenter

Waffle notification center.

| Function | Description |
|----------|-------------|
| `toggle` | Open/close notification center |
| `open` | Open notification center |
| `close` | Close notification center |

---

### wwidgets

Waffle widgets panel.

| Function | Description |
|----------|-------------|
| `toggle` | Open/close widgets |
| `open` | Open widgets |
| `close` | Close widgets |

---

### wbar

Waffle taskbar visibility.

| Function | Description |
|----------|-------------|
| `toggle` | Show/hide taskbar |
| `open` | Show taskbar |
| `close` | Hide taskbar |

---

### waffleAltSwitcher

Waffle Alt+Tab window switcher. Separate from the ii `altSwitcher`, supports quick-switch (first tab switches instantly, second opens UI) and no-visual-UI mode.

| Function | Description |
|----------|-------------|
| `open` | Open switcher |
| `close` | Close switcher |
| `toggle` | Toggle switcher |
| `next` | Focus next window |
| `previous` | Focus previous window |

---

### background

Desktop background and widget controls.

| Function | Description |
|----------|-------------|
| `toggleEditMode` | Toggle widget edit mode (drag, resize, configure desktop widgets) |
| `setEditMode enabled` | Set widget edit mode explicitly |
| `editState` | Report the active selection, physical panel insets, full desktop work area and panel-aware zone work area for each output |
| `desktopItemsState` | Report desktop-item persistence, availability, item count, validation errors and undo state |
| `wallpaperState` | Report configured/displayed wallpaper, pending texture frames and renderer state for each output |
| `focusWidget widgetName openControls` | Select a desktop widget and optionally open its quick controls |
| `promoteWidget widgetName` | Move a desktop widget to the top of the persistent layer order |
| `resetLayerOrder` | Reset desktop widgets to their built-in stacking order |
| `setWidgetEnabled widgetName enabled` | Enable or disable a built-in desktop widget |
| `clockDebugState` | Report clock palette, renderer and quick-control geometry diagnostics |
| `clockDebugSetMode digital\|cookie adaptToWallpaper` | Temporarily select a diagnostic clock mode |
| `clockDebugSetRegion color brightness spread` | Inject a temporary wallpaper-region sample |
| `clockDebugSetLayout x y quickControlsOpen` | Probe quick-control geometry at a hypothetical clock position without moving the widget |
| `clockDebugRestore` | Restore the config captured by clock diagnostics |

The mutating diagnostic functions require the supervised shell to be loaded
with `ALIS_REGION_DEBUG=1`. They snapshot the clock's relevant config on first
use; always finish a diagnostic run with `clockDebugRestore` before removing
the environment flag.

```kdl
bind "Super+W" { spawn "alis" "background" "toggleEditMode"; }
```

---

### customWidgets

Custom widget management. Create, list, reload, and remove user-installed widgets from `~/.config/alis/widgets/`.

| Function | Description |
|----------|-------------|
| `reload` | Re-scan widgets directory and reload all custom widgets |
| `list` | List all discovered custom widgets (JSON output) |
| `create` | Create a new widget scaffold in the widgets directory |
| `remove` | Remove a custom widget by ID |

---

### widgetpower

Desktop-widget power management (pauses widget rendering on game mode, fullscreen, present windows, or edit mode). Service: `services/WidgetPowerManager.qml`.

| Function | Description |
|----------|-------------|
| `status` | Returns JSON: `enabled`, `widgetsActive`, and the active `triggers` (gameMode, fullscreen, windowsPresent, editMode) |

---

### recordingOsd

Screen recording floating pill OSD. Shows elapsed time and stop button during active recording.

| Function | Description |
|----------|-------------|
| `toggle` | Stop the current recording (if active) |
| `show` | Reveal the recording OSD pill |
| `hide` | Collapse/hide the recording OSD pill |

---

### autostart

Niri login autostart manager. Reads and writes the managed section of
`~/.config/niri/config.d/50-startup.kdl` (delimited by `// >>> alis-managed-autostart >>>` /
`// <<< alis-managed-autostart <<<`). Base Alis lines and any hand-written
`spawn-at-startup` lines outside the markers are preserved verbatim; toggling an
entry comments the line out instead of deleting it. Safe no-op on non-Niri
compositors (the page shows a guard instead).

| Function | Description |
|----------|-------------|
| `status` | Return `niri\|<path>\|<managedCount>\|<externalCount>\|<state>` |
| `addApp <desktopId>` | Append a managed `gtk-launch <desktopId>` entry |
| `addCommand <cmd>` | Append a managed `spawn-sh-at-startup` shell line |
| `removeLast` | Remove the last managed entry |
| `reload` | Force re-read the startup file |

The Settings UI (ii: AutostartConfig, waffle: WAutostartPage) is the primary
interface; these IPC calls exist for scripts/keybinds. Apps the user already
launches via hand-written lines outside the markers are detected and shown as
"External" (read-only) in the list.

---

## Standalone Commands

These are top-level `alis` commands that work directly, without going through IPC.

### colorpicker

Launch `hyprpicker` to pick a color from anywhere on the screen. The hex value is copied to the clipboard (`-a` flag).

```kdl
bind "Super+Shift+C" { spawn "alis" "colorpicker"; }
```

Requires `hyprpicker` installed.
