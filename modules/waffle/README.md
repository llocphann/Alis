# Waffle Panel Family

Windows 11-inspired Fluent desktop family built in Quickshell QML alongside Alis's primary **Abyss** family.

## Switching at Runtime

- Press **`Super+Shift+W`** to cycle panel families (`abyss` ↔ `waffle`), or run:
  ```bash
  alis panelFamily cycle
  ```
- Panel family visual tokens live in `modules/waffle/looks/Looks.qml`, completely isolated from `Appearance.*` / `AbyssStyle.*`.

## Live Surfaces

- **Taskbar (`bar/`)**: Centered Windows-style bottom taskbar with pinned/running apps, workspace indicator, system tray, clock, and media controls.
- **Start Menu (`startMenu/`)**: Start-Menu-sized unified Launcher + Dashboard with app search, pinned apps, and widgets.
- **Action Center (`actionCenter/`)**: Quick toggles, volume/brightness sliders, power profiles, and optional TLP/ThinkFan controls.
- **Notification Center (`notificationCenter/`)**: Grouped notification history with search, quiet hours, and calendar.
- **Waffle Settings (`settings/` + `waffleSettings.qml`)**: Standalone Win11-style settings window with parity for Appearance, Background, Taskbar, Sidebars, System, and Integrations.
