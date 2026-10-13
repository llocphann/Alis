# Config System

How configuration works in Hadalis/iNiR, from the user's perspective and from the code side.

## For users

Everything is configurable through the graphical Settings UI. Open it with `Super+,` or `inir settings`. You should never need to edit the config file by hand.

After required migration 019 has been applied, the canonical config file is:

```
~/.config/inir/config.json
```

The live QML compatibility path is still `~/.config/illogical-impulse/config.json`. When only the legacy directory exists, migration 019 moves it to `~/.config/inir` and replaces the legacy path with a symlink to the canonical directory. If both real directories exist, or the legacy path is a foreign symlink or another unexpected object, the migration fails closed and preserves the existing state so the user can reconcile it manually before rerunning `inir migrate`. This keeps the current QML path and maintenance tooling on the same data without silently overwriting ambiguous user state.

Repo-managed `./setup install` and update flows apply required migrations automatically. Package managers and manual `make install` deliberately do not mutate arbitrary user home directories, so each affected user should run `inir migrate` before first launch (and after an upgrade when migrations are pending). Until migration 019 has run for that user, the QML compatibility path may still be a real legacy directory rather than a symlink. Do not run another user's config migration as root.

This compatibility layout is part of the in-progress namespace cutover. Do not remove the legacy QML path or its migration support until the runtime itself has moved off `illogical-impulse` and that cutover has been validated.

### Optional Alis directory aliases

The optional migration `061-alis-namespace-alias` can create `alis` symlinks to already existing `inir` directories under the user's XDG config, cache, data and state homes. It **does not rename or copy** any directory: the current live runtime, migration registry, and saved preferences continue using their original paths. Run `alis migrate` and explicitly accept the optional migration after checking its preview. Fresh installs lacking those directories are left untouched. If a destination is already a real file/directory or an unrelated symlink, including an existing `~/.cache/alis`, migration 061 skips that one destination, preserving its contents. It may still create aliases at the other independent free XDG roots without overwriting user-owned files.

To reverse the optional alias, verify that the affected `alis` path is a symlink to `inir`, then remove only the symlink—not the directory it points to. Do not use recursive deletion. A full `inir` → `alis` primary-directory conversion must wait for a coordinated ShellId/service/runtime migration and owner verification.

Changes you make in the file are picked up automatically within 50ms. No restart needed.

### Fresh-install profile

A new configuration starts deliberately quiet. Settings opens in Focused mode, the left sidebar contains one curated Widgets tab, and the right sidebar starts with connectivity, sliders, notification-policy controls, and four daily tools: Calendar, To Do, Calculator, and System Monitor. Notification history itself lives in the standalone bottom-right Notification Center. Weather, desktop widgets, notification sounds, news feeds, wallpaper search, AI, and anime integrations stay off until you enable them.

The Welcome wizard exposes only choices that materially affect the first session. Advanced styles, additional sidebar tabs, and specialized modules remain available in the full Settings view.

## For contributors

### Panel family and Abyss

`panelFamily` accepts `ii` (default), `waffle` and `abyss`. Unknown values normalize to `ii`. Select it in Settings → Modules → Panel Style or with `inir panelFamily set abyss`; switching preserves disabled panels using `knownPanels` and `visitedPanelFamilies` rather than replacing `enabledPanels` on every visit.

Settings → Modules → **Abyss Style** groups Performance, Surface, Motion, Refraction & Glass, Perimeter, Bar & Dock, and Panels. The `abyss.*` namespace contains `quality`, `surface.opacity/tension/softness`, `motion.intensity`, `perimeter.thickness/radius/visibleInFullscreen`, and `effects.blur/refraction/glow/surfaceHighlight`. Sensible defaults live in both the typed schema and `defaults/config.json`.

Abyss reuses `bar.vertical/bottom`, orientation-specific module layouts and visibility, `dock.position/height/pins`, and each feature's `screenList`. An empty output list means all connected outputs; stale selections safely fall back to connected outputs. Persistent pinned docks reserve depth, hover docks do not. Fullscreen releases reservations by default. Global reduced motion and effects gating still apply.

Performance omits the wallpaper texture, refraction, glow and shadow. Balanced permits static-wallpaper blur; Quality permits enabled refraction and a restrained settle. Glass follows static wallpaper only; GIF/video or a missing image uses the palette surface. It does not blur application contents.

### The sync rule

Adding a new config key requires updating four things together in one commit:

1. **`modules/common/Config.qml`** - declare the schema property with its type and default
2. **`defaults/config.json`** - add the matching key for fresh installs
3. **Consumer code** - the QML that reads or writes the key
4. **Settings UI** - if the key is user-facing (most are)

Skip any of these and something breaks silently. The most common mistake is skipping Config.qml, which means `Config.options?.your?.key` resolves to `undefined` even though the key exists in defaults.

### Reading config

Always null-safe, always with a fallback:

```qml
// Standard pattern
readonly property bool enabled: Config.options?.bar?.autoHide?.enable ?? false
readonly property int interval: Config.options?.weather?.interval ?? 15

// Also fine (optional chaining is harmless even when the path exists)
readonly property string city: Config.options?.weather?.city ?? ""
```

Config properties are available after `Config.ready` becomes true. Everything that depends on config should gate on this.

### Writing config

There is exactly one way to write config that actually persists:

```qml
// This works
Config.setNestedValue("bar.autoHide.enable", true)

// This does NOT work (silently fails to persist)
Config.options.bar.autoHide.enable = true
```

The direct assignment updates the in-memory QML property but never writes to disk. This is the number one source of config bugs. If you see `Config.options.x.y = z` anywhere, it's a bug.

### Schema

`Config.qml` is a large singleton that defines every config section as typed QML properties. Example:

```qml
readonly property QtObject bar: QtObject {
    readonly property bool vertical: root._config?.bar?.vertical ?? false
    readonly property QtObject autoHide: QtObject {
        readonly property bool enable: root._config?.bar?.autoHide?.enable ?? false
        readonly property int showDelay: root._config?.bar?.autoHide?.showDelay ?? 300
    }
}
```

The schema serves three purposes:

1. **Type safety**: properties are typed (`bool`, `int`, `string`, `list`), not `var`
2. **Default values**: the `?? fallback` provides a runtime default even if the key is missing
3. **Documentation**: the schema IS the config reference

### Defaults

`defaults/config.json` provides the starting config for fresh installs. It covers ~60 top-level sections.

The defaults file and Config.qml can have different fallback values by design. The defaults file is what gets written to disk on first install. The schema fallbacks are what the code uses if a key is missing at runtime.

### Hot-reload

Config uses Quickshell's `FileView` with `watchChanges: true`. External edits (from a text editor, a script, whatever) are detected and applied within 50ms. Both reads and writes are debounced at 50ms.

### The configChanged signal

`setNestedValue` emits `Config.configChanged()` **immediately**, in the same call, before the debounced 50 ms disk write actually happens. So the signal reflects the new in-memory value, not a confirmed write to disk. Components that need to react to config changes (beyond just re-reading a property) can connect to this signal.

## Config sections

The ~60 top-level sections, roughly grouped:

**Shell structure**: `panelFamily`, `enabledPanels`, `bar`, `dock`, `sidebar`

**Appearance**: `appearance` (colors, rounding, style, animations), `background` (wallpaper, blur, widgets)

**Services**: `weather`, `ai`, `calendar`, `search`, `updates`

**System**: `battery`, `performance`, `lock`, `session`, `idle`

**Features**: `notifications`, `clipboard`, `screenRecord`, `nightLight`, `gameMode`

**Waffle-specific**: `waffles` (the entire waffle family config namespace)

The full schema is `modules/common/Config.qml`. The full defaults are `defaults/config.json`.

## Common keys people actually ask about

### Per-window app identity

Some applications give every window the same compositor `app_id`, even when
the windows represent separate desktop applications (browser PWAs are a
common example). `windows.appIdentityRules` can map those windows to the
desktop entry that should own them:

```json
{
  "windows": {
    "appIdentityRules": [
      {
        "appIdRegex": "^browser$",
        "titleRegex": "^Example PWA(?: |$)",
        "desktopId": "example-pwa"
      }
    ]
  }
}
```

Rules are case-insensitive, the first matching rule wins, and at least one of
`appIdRegex` or `titleRegex` is required. Malformed rules are ignored. The
setting is empty by default and is intentionally advanced: the compositor
does not expose enough metadata to distinguish every PWA from a normal tab
automatically. `desktopId` should match an installed `.desktop` entry so the
matching icon, name, launcher, and taskbar grouping are used.

### Bar layout

The modular ii Bar stores two independent placement presets:

- `bar.layout` for Top/Bottom: `left`, `centerLeft`, `center`, `centerRight`, `right`
- `bar.verticalLayout` for Left/Right: `top`, `centerTop`, `center`, `centerBottom`, `bottom`

In both presets, `center` is reserved for Workspaces and remains the physical pivot. Horizontal flexible spacers use `bar.layout.spacerWidth`; vertical flexible spacers use `bar.verticalLayout.spacerHeight`. Each preset has its own `spacerMode`.

Module visibility is intentionally shared through `bar.modules.*`, so switching orientation changes placement without creating a second enable/disable state. Use Settings -> Bar -> Bar module layout unless you are debugging. The editor writes through `Config.setNestedValue`, so changes persist. `bar.verticalLayout` is an additive schema key with defaults, so existing configs do not need a migration.

The old `bar.modulesLayout`, `bar.edgeModulesLayout`, and `bar.modulesPlacement` keys are legacy compatibility only.

`bar.height` and `bar.opacity` control the bar size and background fill. They do not resize every widget independently; components still use the normal `Appearance` sizing tokens.

### Live shell layout

Settings -> Shell Layout and `inir shellLayout` use the same controller as the
live desktop editor. Existing canonical keys remain authoritative:

- ii bar: `bar.vertical` plus `bar.bottom`
- ii dock: `dock.position`
- Waffle taskbar: `waffles.bar.bottom`

Semantic ii sidebar roles use:

- `sidebar.shellLayout.feature.slot`
- `sidebar.shellLayout.feature.sizeMode`
- `sidebar.shellLayout.feature.customHeight`
- `sidebar.shellLayout.feature.width`
- the matching `sidebar.shellLayout.system.*` keys

`feature` is the AI, media, tools and Widgets role historically opened by the
`sidebarLeft` IPC target. `system` is the quick controls, notification-policy
and utility role historically opened by `sidebarRight`; notification history
itself belongs to the standalone bottom-right Notification Center. Their IPC
meaning does not change when the roles swap physical edges.

Desktop widgets keep their original free/zone editor and independent
`widgetEditMode`. Persistent layer-shell surfaces use the separate Shell Layout
editor and move between advertised edge slots. For Abyss, the desktop context
menu's **Edit shell layout** action intentionally enters the same output-local
live Abyss Edge editor as the Settings header's **Edit Abyss layout** button.
Other families continue through the shared Shell Layout controller from the
desktop context menu, Settings -> Shell Layout, or `inir shellLayout open`.
The editor HUD stays above the edited panels and does not reuse the widget
canvas or toolbar. Drag any highlighted surface toward a screen edge: legal
edges light up as full strips, a chip follows the pointer with the drop
result, and releasing on a strip commits the move. Dropping a surface on an
occupied edge performs an atomic swap: sidebars exchange sides, and the ii
bar and dock exchange edges the same way. Releasing in the center of the
screen cancels. The click flow remains for keyboard and scripting: select a
surface, choose Move, then activate an edge strip, where occupied edges still
ask for a second confirming activation. Resize handles preview locally with a
live dimension readout and persist when released; sidebars resize height and
width, and the dock resizes its thickness through `dock.height`.

Bar corner controls are spatial: the bar's left corner and left area open
whatever sidebar currently occupies the left edge, and the right-side
controls open the right-edge panel, even after a swap. Feature-specific
triggers keep opening their own semantic content.

Escape cancels the current resize, lift, preview or swap confirmation first. A
second Escape leaves shell edit mode. Done leaves the mode after already
committed changes; there is no hidden Save step or whole-session rollback.

Bar, dock, taskbar and floating media controls follow each surface's existing
`screenList` semantics. Every selected output gets its own surface; an empty
list means all connected outputs. A position change applies to every enabled
output for that surface. Desktop-widget placement remains owned by its
separate editor. Each output
inherits the global widget configuration and stores only its local visibility,
position, size and lock overrides in `background.widgets.outputOverrides`.
Dragging, resizing or toggling a widget on one desktop therefore does not move
or hide its peer on another output. Settings -> Monitors shows connected and
saved-disconnected outputs, with per-widget reset and whole-output reset.

When a new output appears or its logical resolution changes, iNiR initializes
missing free-placement coordinates against that output's panel-safe work area
and separates unlocked collisions. Widget content and visual options remain
global unless the corresponding control is explicitly output-local. The Shell
Layout HUD and Settings page still show the broader mutation scope for panel
surfaces; per-output geometry profiles are not used for bar, dock, taskbar or
sidebar placement.

Managed desktop references use the same `background.widgets.editGrid` size and
snap switch as built-in widgets. Drops, drags and monitor moves choose the
nearest free grid cell inside the panel-safe work area, so references remain
aligned without overlapping another reference. Locked references keep their
saved position.

Valid sidebar slots are `left` and `right`. Both roles must occupy different
slots, so moving one onto the other performs an atomic swap. Valid size modes
are `full`, `fit` and `custom`. Fit uses the active role content: finite feature
tabs can contract while unbounded tabs return to full height.

These keys are append-only additions. Existing configs without them retain the
historical feature-left and system-right layout, so no migration script is
needed. `collapseWidgetsTab` remains the legacy feature-sidebar fit option.
`collapseEmptyNotifications` is retained only for old-config compatibility;
notification history no longer lives in the system sidebar.

### Right sidebar header

`sidebar.right.headerStyle` selects the system section shown at the top of the right sidebar:

- `profile`: avatar, account identity, uptime, actions and optional banner media
- `classic`: the compact uptime and action row

For the profile style, `sidebar.right.headerBanner` accepts `wallpaper`, `custom`, `solid` or `none`. `sidebar.right.headerBannerPath` stores the local image, GIF or video path used by `custom`. Wallpaper and animated media playback follow the sidebar's active screen and visibility.

### Right sidebar widgets

`sidebar.right.enabledWidgets` controls the widgets shown in the right sidebar bottom group and compact sidebar.

Known ids include:

`calendar`, `events`, `todo`, `notepad`, `calculator`, `sysmon`, `weather`, `timer`

### Screen Time

`sidebar.screenTime` remains the historical configuration namespace:

- `enable`: explicit opt-in used by Waffle Screen Time
- `pollIntervalSeconds`: focused-window sampling interval
- `retentionDays`: how long local daily JSON is kept

Material ii no longer exposes Screen Time as a right-Sidebar widget. Its bottom-right notification-center **Activity** tab owns the compact usage summary and automatically keeps tracking active while `iiScreenCorners` is enabled. Screen Time is local-only and records app ids/names and seconds, not window titles.

### World Clock

`sidebar.widgets.worldClock_settings`:

- `timezones`: explicit IANA timezone ids, e.g. `Europe/London`
- `showSeconds`
- `use24Hour`
- `showDate`
- `highlightLocal`

Empty `timezones` means the widget can show suggestions based on local timezone/region. Once you add zones in Settings, that explicit list wins.

### Wallpaper shuffle

`background.autoWallpaper`:

- `enable`
- `intervalMinutes`
- `generateColors`
- `folder`

If `folder` is empty, shuffle uses the current wallpaper directory. If `generateColors` is off, only the image changes; the shell keeps the current palette.

## Settings UI

Users interact with config exclusively through Settings:

- **Material ii**: `Super+,` opens an overlay settings panel (lives in `modules/settings/`)
- **Waffle**: `Super+,` opens a standalone settings window (lives in `modules/waffle/settings/`)

Both families have their own settings implementations but write to the same config.json. When a config key affects both families, both settings UIs need updating.

## Migrations

When a config key is renamed, restructured, or its semantics change in a way that affects existing users, a migration handles the transition. Migrations live in `sdata/migrations/` as numbered bash scripts.

Most config additions don't need migrations. A new key with a default just appears in the schema and existing users get the default value. Migrations are only for breaking changes to existing keys.
