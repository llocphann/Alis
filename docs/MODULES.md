# Modules Catalog

UI components organized by panel family. Modules handle rendering and interaction. They don't own global state, they read from services and config singletons.

## How modules load

Every visible panel is wrapped in a `PanelLoader` inside either `ShellIiPanels.qml` (Material ii) or `ShellWafflePanels.qml` (Waffle). A panel loads when:

1. `Config.ready` is true
2. Its identifier is in the `enabledPanels` config array
3. Its `extraCondition` (if any) is satisfied

Users can disable any panel from Settings without touching config files.

## Material ii Panels

### Core

| Module | Panel ID | Description |
|--------|----------|-------------|
| `bar/` | `iiBar` | Horizontal Classic Bar (top/bottom). Workspaces, clock, system indicators, tray, weather. ~35 QML files. |
| `verticalBar/` | `iiVerticalBar` | Vertical bar variant for left/right edge placement. |
| `dock/` | `iiDock` | Application dock. Supports all 4 edges (top/bottom/left/right). Scroll an icon to cycle that app's windows; `dock.notificationBadge` puts an app's pending notification count on its icon. |
| `background/` | `iiBackground` | Desktop wallpaper layer. Parallax, blur, desktop widget canvas. |

### Sidebars

| Module | Panel ID | Description |
|--------|----------|-------------|
| `sidebar/` | shared host | Physical left/right layer-shell hosts. They resolve semantic feature/system roles, own focus, masks, animations and live layout resize handles. |
| `sidebarLeft/` | `iiSidebarLeft` | Feature-role content: AI chat (Gemini/OpenAI/Ollama), local Music library/player, Wallhaven browser, anime tracker, translator, draggable widgets and World Clock. The Music tab browses MPD songs, saved playlists and queue, while transport follows the same mpd-mpris/MPRIS session used by the rest of the shell. The role can occupy either physical edge. |
| `sidebarRight/` | `iiSidebarRight` | System-role content: quick toggles, calendar with external sync, volume mixer, Bluetooth/WiFi management, pomodoro timer, todo, calculator, notepad and system monitor. Notification history and usage activity are intentionally separate. The role can occupy either physical edge. |

### Overlays

| Module | Panel ID | Description |
|--------|----------|-------------|
| `overview/` | `iiOverview` | Workspace overview with app search, calculator, and global actions. |
| `ii/` | `iiOverlay` | Notification overlays and ii-specific UI elements. |
| `clipboard/` | `iiClipboard` | Clipboard history browser with search and image preview. `Ctrl+P` pins an entry to the top of the list; pins store their own decoded copy in `clipboard.pinned`, so they outlive the cliphist history. |
| `cheatsheet/` | `iiCheatsheet` | Keybind viewer pulled from compositor config. |
| `controlPanel/` | `iiControlPanel` | Quick settings panel. |
| `dashboard/` | `iiDashboard` | Centered hub panel: welcome, clock, agenda (local events + ICS), notifications, todo, notes, media, weather, calendar, system usage, GitHub heatmap. Modular three-column layout with in-panel edit mode; configured in Settings › Dashboard. IPC target `dashboard`. |
| `mediaControls/` | `iiMediaControls` | MPRIS media player popup with multiple layout presets. |
| `wallpaperSelector/` | `iiWallpaperSelector` | Wallpaper browser with directory navigation. |
| `wallpaperLauncher/` | `iiWallpaperLauncher` | Shared compact wallpaper carousel with search, static and animated libraries, live preview and IPC navigation. |
| `sessionScreen/` | `iiSessionScreen` | Logout, reboot, shutdown, suspend screen. |

### System

| Module | Panel ID | Description |
|--------|----------|-------------|
| `notificationPopup/` | `iiNotificationPopup` | Notification toast popups. |
| `notificationCenter/` | hosted by `iiScreenCorners` | Material notification history surface. Bottom-right hover/explicit popup with grouped history, search and actions; shares the Notifications backend with transient toasts. |
| `onScreenDisplay/` | `iiOnScreenDisplay` | Volume and brightness OSD. |
| `onScreenKeyboard/` | `iiOnScreenKeyboard` | Virtual keyboard. |
| `lock/` | `iiLock` | Lock screen with PAM authentication and fingerprint support. |
| `polkit/` | `iiPolkit` | PolicyKit authentication dialog. |
| `regionSelector/` | `iiRegionSelector` | Screenshot and screen recording region selection. |
| `screenCorners/` | `iiScreenCorners` | Hot corners. |
| `tilingOverlay/` | `iiTilingOverlay` | Tiling hints overlay. |
| `shellUpdate/` | `iiShellUpdate` | Shell update notification banner. |
| `recordingOsd/` | `iiRecordingOsd` | Screen recording indicator (disabled by default). |

## Waffle Panels

### Core

| Module | Panel ID | Description |
|--------|----------|-------------|
| `waffle/bar/` | `wBar` | Bottom taskbar. Start button, pinned apps, open windows, system tray, clock. |
| `waffle/background/` | `wBackground` | Desktop wallpaper layer (waffle variant). |

### Primary Overlays

| Module | Panel ID | Description |
|--------|----------|-------------|
| `waffle/startMenu/` | `wStartMenu` | Start menu with app grid, search, pinned apps, recommendations. |
| `waffle/actionCenter/` | `wActionCenter` | Quick settings. WiFi, Bluetooth, volume, brightness, toggles, Screen Time entry point. |
| `waffle/notificationCenter/` | `wNotificationCenter` | Notification list with calendar and external event integration. |
| `waffle/taskview/` | `wTaskView` | Task view (workspace overview with window previews). |
| `waffle/widgets/` | `wWidgets` | Desktop widgets panel. |

### System

| Module | Panel ID | Description |
|--------|----------|-------------|
| `waffle/notificationPopup/` | `wNotificationPopup` | Notification popups (Fluent style). |
| `waffle/onScreenDisplay/` | `wOnScreenDisplay` | Volume/brightness OSD (Fluent style). |
| `waffle/lock/` | `wLock` | Lock screen (Fluent variant). |
| `waffle/polkit/` | `wPolkit` | PolicyKit dialog (Fluent variant). |
| `waffle/sessionScreen/` | `wSessionScreen` | Session screen (Fluent variant). |

### Design System

| Module | Description |
|--------|-------------|
| `waffle/looks/` | `Looks.qml` - complete visual token system. Colors, typography, motion, rounding. |
| `waffle/settings/` | Waffle-specific settings pages. |

## Shared Infrastructure

### modules/common/ (~203 files)

The foundation everything else builds on.

| Component | What it is |
|-----------|-----------|
| **Config.qml** | Configuration singleton. ~60 config sections. [Details](CONFIG_SYSTEM.md) |
| **Appearance.qml** | ii visual tokens. ~500 properties covering colors, rounding, typography, animation. |
| **Directories.qml** | Centralized path resolution. Config, cache, data, scripts, media directories. |
| **widgets/** | 130+ reusable widgets registered in `widgets/qmldir`. Layout, input, display, media, and specialized components. |
| **ThemePresets.qml** | 46 built-in theme presets. |
| **StylePresets.qml** | Style variant definitions. |

## Current notable modules

### Bar layout editor

The ii bar is driven by `Config.options.bar.layout`, split into five zones:

`left`, `centerLeft`, `center`, `centerRight`, `right`

The Settings page uses `BarModuleOrderEditor.qml` to reorder modules and drag available modules into zones. `workspaces` stays the centered pivot. The old `modulesLayout`, `edgeModulesLayout`, and `modulesPlacement` keys are deprecated compatibility baggage, not the runtime source of truth.

Migration `028-bar-modular-layout` exists but is disabled. The bar has a built-in classic fallback, so existing users do not need config rewrites just to update. Good. We learned.

### Screen Time

`services/ScreenTime.qml` tracks focused app/window usage for the compact Material notification-center Activity tab. Under Material ii it stays active while `iiScreenCorners` owns that popup; Waffle keeps the explicit Screen Time opt-in.

Visible surfaces:

- `modules/notificationCenter/NotificationCenterPopup.qml` — fixed, non-scrollable Activity summary beside Notifications
- `modules/waffle/actionCenter/screenTime/ScreenTimePage.qml`

The right Sidebar no longer mounts Screen Time as its own tab. The service still stores local daily JSON under the Alis state directory with daily totals, app totals, hourly buckets, and per-app hourly drill-down.

### World Clock

`modules/sidebarLeft/widgets/WorldClockWidget.qml` is a sidebar-left widget configured through `sidebar.widgets.worldClock_settings`.

If no timezones are configured, it suggests useful zones from the user's locale/system timezone. If the user configures timezones, Settings owns the explicit list and order.

### Shared panels

Some panels work under both families. They keep their `ii` prefix but load in waffle mode too:

`iiCheatsheet`, `iiOnScreenKeyboard`, `iiOverlay`, `iiOverview`, `iiRegionSelector`, `iiScreenCorners`, `iiWallpaperSelector`, `iiWallpaperLauncher`, `iiClipboard`, `iiRecordingOsd`

## For contributors

1. Read [Architecture Overview](ARCHITECTURE_OVERVIEW.md) to locate the module's place in the tree and its owning family
2. Identify which family owns the module before making visual changes
3. Use the correct token system: `Appearance.*` for ii, `Looks.*` for waffle
4. Register new panels in the appropriate panels file
5. Register new shared widgets in `modules/common/widgets/qmldir`
6. If touching shared modules, test under both families
