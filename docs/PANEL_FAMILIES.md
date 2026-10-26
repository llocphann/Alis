# Panel Families

Alis has three separate UI families sharing services, models and configuration: Material II (`ii`), Waffle (`waffle`) and Abyss (`abyss`). Switch at runtime with `Super+Shift+W`, Settings → Modules → Panel Style, or `alis panelFamily set abyss`.

Abyss (`abyss`) is the default; Waffle (`waffle`) is the other supported panel style. Old `ii` settings and IPC calls migrate to Abyss without resetting shared feature preferences.

## Material design baseline

Abyss inherits the shared content and token system described below. The former Material panel family is retired; its source is retained for shared feature reuse and regression comparison. Alis 1.0 exposes **Material as the only shell-wide Global Theme**. Wallpaper-derived palettes, named color presets, motion settings, and local component presentation options are independent of that Global Theme boundary.

### Global theme

| Global Theme | Contract |
|---|---|
| **Material** | Canonical ii runtime language for v1.0. Shared surfaces consume the Material palette, rounding, typography, motion and connected-surface tokens. |

`Appearance.globalStyle` is runtime-clamped to `material`. Persisted legacy Global Theme values are normalized by `ThemeService`; they are not selectable renderers and must not gain new runtime branches.

Use the canonical Material tokens for ordinary ii surfaces:

```qml
color: Appearance.colors.colLayer1
radius: Appearance.rounding.normal
font.family: Appearance.font.main
```

### Layout

- **Bar**: top or bottom of screen (horizontal), or left/right edge (vertical). Both orientations are modular and keep independent presets. Top/Bottom uses left edge, two center-side zones, a centered workspace pivot and right edge; Left/Right uses top edge, center-top, the same centered workspace pivot, center-bottom and bottom edge.
- **Sidebars**: left sidebar (AI chat, YT Music, widgets), right sidebar (toggles, calendar, tools)
- **Dock**: application dock (any of 4 edges)
- **Overview**: workspace overview with app launcher and search (`Super+Space`)
- **Settings**: overlay panel rendered on top of the current desktop

### Visual tokens

All ii components use `Appearance.*`:

```qml
color: Appearance.colors.colPrimary
radius: Appearance.rounding.normal
font.family: Appearance.font.main
```

Never hardcode colors, radii, or font sizes. The token system keeps Material palette changes, supported local appearance options, and wallpaper-derived theming consistent across the shell.

### Panels

ii loads about 25 panels through `ShellIiPanels.qml`. Some notable ones:

| Panel ID | What it is |
|----------|-----------|
| `iiBar` | Horizontal Classic Bar (top or bottom) |
| `iiVerticalBar` | Side bar (vertical mode) |
| `iiDock` | Application dock |
| `iiSidebarLeft` | Left sidebar (AI, music, widgets) |
| `iiSidebarRight` | Right sidebar (toggles, calendar, system) |
| `iiOverview` | Workspace overview + app search |
| `iiBackground` | Desktop wallpaper layer |
| `iiMediaControls` | MPRIS media player popup |
| `iiClipboard` | Clipboard history browser |

### Bar zones

The ii Bar stores separate five-zone presets for horizontal and vertical placement.

Top/Bottom uses `bar.layout`:

| Zone | Role |
|------|------|
| `left` | Left edge controls, usually sidebar button + active window/taskbar |
| `centerLeft` | Left center pill, usually resources/media |
| `center` | Fixed Workspaces pivot |
| `centerRight` | Right center pill, usually clock/util/battery |
| `right` | Right edge controls, usually sidebar button/tray/timer/update/weather |

Left/Right uses `bar.verticalLayout`:

| Zone | Role |
|------|------|
| `top` | Physical top-edge controls |
| `centerTop` | Modules immediately above Workspaces |
| `center` | Fixed Workspaces pivot at screen center |
| `centerBottom` | Modules immediately below Workspaces |
| `bottom` | Physical bottom-edge controls |

Settings -> Bar -> Bar module layout edits the preset for the active orientation. Visibility still comes from the shared `bar.modules.*` switches.

## Waffle

Windows 11 Fluent Design. Not "ii with a different skin" but a completely separate family with its own design language, interaction patterns, and density.

### Layout

- **Taskbar**: bottom of screen (Windows 11 style)
- **Start Menu**: app grid with search, pinned apps, recent files
- **Action Center**: quick settings (WiFi, Bluetooth, volume, brightness, toggles)
- **Screen Time**: optional entry in Action Center when usage tracking is enabled
- **Notification Center**: notification list with calendar
- **Settings**: standalone window (separate from ii settings)

### Visual tokens

Waffle uses `Looks.*` exclusively. Never `Appearance.*` in waffle code:

```qml
color: Looks.colors.accent
radius: Looks.rounding.medium
font.family: Looks.font.fontFamily
```

### Design differences from ii

| Aspect | ii | waffle |
|--------|-----|--------|
| Density | Spacious Material spacing | Dense Win11 information density |
| Motion | Organic, 200-500ms durations | Snappy and mechanical, 67-250ms |
| Surfaces | Layered elevation (5 layers) | 3-tier chrome (bg0/bg1/bg2) |
| Controls | Material ripple, elevation | Flat with subtle hover reveals |
| Typography | 6 font families, expressive | Single family, pragmatic sizing |

### Panels

Waffle loads about 22 panels through `ShellWafflePanels.qml`:

| Panel ID | What it is |
|----------|-----------|
| `wBar` | Bottom taskbar |
| `wStartMenu` | Start menu |
| `wActionCenter` | Quick settings panel |
| `wNotificationCenter` | Notification center + calendar |
| `wTaskView` | Task view (workspace overview) |
| `wWidgets` | Desktop widgets panel |
| `wBackground` | Desktop wallpaper layer |

Some panels are shared between families (cheatsheet, region selector, on-screen keyboard) and keep their `ii` prefix even under Waffle or Abyss. Waffle retains its own supported presentation family.

## Abyss

**Perimeter Liquid Shell.** The screen edge is the shell; panels deform inward from one continuous liquid body. Abyss is not an Abyss Island implementation.

`ShellAbyssPanels.qml` source-loads the Abyss composition. One `AbyssPerimeter` per output owns the final SDF silhouette, fill, specular rim and shadow. Bar zones, dock, sidebars, popups, notifications and OSD contribute geometry records rather than independent body painters. Palette-derived `AbyssStyle` tokens control typography, tension, material and bounded motion.

| Panel ID | Presentation |
|---|---|
| `abyssPerimeter` | Four-edge physical body and transparent reservations |
| `abyssBar` | Five zones embedded in any screen edge |
| `abyssDock` | Retractable pinned/running apps attached to any edge |
| `abyssSidebarLeft`, `abyssSidebarRight` | Output-local tools and control deformations |
| `abyssPopup` | Media, clock, resources, weather, battery and audio extrusion from the bar edge |
| `abyssNotificationPopup`, `abyssNotificationCenter` | Bounded notification swell and history |
| `abyssOnScreenDisplay` | Passive, temporary edge indicator |
| `abyssClipboard`, `abyssOverview` | Demand-loaded clipboard and launcher deformations |
| `abyssBackground` | Shared per-output wallpaper implementation |

Lock, polkit and session screens use shared implementations behind Abyss IDs. Screenshot/region selection, OSK, cheatsheet, dashboard, control panel, overlay, wallpaper selection, updates and recording indicators remain shared demand-loaded fallbacks. AI and local music reuse specialist content inside the native left body; tray menus reuse the shared tray control. Settings uses the existing standalone window with an **Abyss Style** section. These fallbacks preserve workflows while native geometry stays separately owned.

Abyss uses shared bar orientation/layout/visibility, dock placement/pins and output-list settings. `abyss.*` contains the new material, perimeter, motion and quality settings. Performance uses a static palette surface; Balanced adds static-wallpaper glass; Quality permits optional refraction and a small settle. Animated wallpapers use palette fill. Glass samples the wallpaper, not application pixels.

See [Abyss audit, checkpoints and acceptance evidence](ABYSS.md). Source/local tests do not establish hardware multi-output or desktop input acceptance.

## Switching families

`Super+Shift+W` cycles `abyss → waffle → abyss`. A specific family can be selected through the shared IPC router. Unknown persisted values fall back to `abyss`; `ii` is a compatibility alias. The transition:

1. Overlay fades in
2. Current family panels unload
3. `panelFamily` config key changes
4. New family panels load
5. Overlay fades out

`FamilyTransitionOverlay.qml` handles Material/Waffle transitions; an incoming Abyss uses its short perimeter flood. Both are input-free and have finite completion/watchdog lifecycles. Direct config changes use the same root migration/cleanup boundary. Ordinary open surfaces close on a family change; lock and polkit state is preserved. Config persists the choice for the next startup. `knownPanels` and `visitedPanelFamilies` enable new defaults once and preserve deliberately disabled panels on later visits.

## Panel loading

All families use the same readiness and enabled-panel gates. Family entry points use URL loaders so inactive visual modules stay outside the parsed tree. Ordinary panels use `PanelLoader`:

```qml
PanelLoader {
    identifier: "iiBar"
    extraCondition: !(Config.options?.bar?.vertical ?? false)
    component: Bar {}
}
```

Three conditions must all be true for a panel to load:

1. **`Config.ready`** is true (config file loaded)
2. **Identifier in `enabledPanels`** (user hasn't disabled it)
3. **`extraCondition`** passes (panel-specific logic)

Panels are split into critical and deferred composition. Sidebars, overview, clipboard and specialist content are demand-loaded after deferred readiness. Abyss content uses `AbyssBodyHost`: it paints nothing, loads only when requested, clips content to its live rectangle and releases input immediately on close while the contour retracts.

## For contributors

If you're adding a new panel:

1. Create the QML component in the appropriate module directory
2. Add the appropriate loader/geometry record in that family's critical or deferred composition
3. Add the identifier to the family policy/defaults and preserve disabled-panel migration behavior
4. If it has settings, add them to the correct Settings UI

If your change touches shared behavior (notifications, lock screen, polkit), test all three families. Keep geometry and presentation at the family boundary rather than adding family branches throughout services.
