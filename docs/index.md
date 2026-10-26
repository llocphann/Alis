# Alis

A complete desktop shell for Niri, built with Quickshell and QML.

It provides the bar, dock, sidebars, notifications, settings, wallpapers, overview, lock screen, IPC and theming in one shell. Niri is the supported compositor. Hyprland support is secondary.

## Start here

- [Install](INSTALL)
- [Setup, updates and rollback](SETUP)
- [Keybinds](KEYBINDS)
- [IPC reference](IPC)
- [Panel families](PANEL_FAMILIES)
- [Configuration](CONFIG_SYSTEM)
- [Known limitations](LIMITATIONS)
- [Managed desktop items](DESKTOP_ITEMS)

## Common commands

```bash
alis run
alis restart
alis settings
alis logs
alis doctor
alis update
```

## Branches

`stable` is the stable branch used by installations and updates.

`dev` is where development happens. It may be ahead by a lot. That is the point.

## Runtime shape

```text
Niri
  -> Quickshell
  -> shell.qml
  -> shared config and services
  -> ii or Waffle
  -> panels, overlays and widgets
```

The shell is configurable through Settings and `config.json`. Persistent writes go through the config service; editing QML is not part of normal use.

## Reference

| Area | Page |
|---|---|
| Installation and packages | [Install](INSTALL), [Packages](PACKAGES) |
| Runtime and architecture | [Runtime](RUNTIME), [Architecture](ARCHITECTURE_OVERVIEW) |
| Services and modules | [Services](SERVICES), [Modules](MODULES) |
| Wallpapers and theming | [Wallpaper](WALLPAPER), [Theming](THEMING_ARCHITECTURE) |
| Desktop references | [Managed desktop items](DESKTOP_ITEMS) |
| Compositor support | [Compositors](COMPOSITORS) |
| Performance | [Optimization research](optimization/STRICT_LOSSLESS_GPU_RAM_CPU_AUDIT.md) |

## Development tasks

Use [the documentation index](README.md) for current technical references and
[the chatbot task entry](../to-do/README.md) for active work, ordered
Issues/bugs → Rework/optimization → New features. Older plans/checkpoints live
in [the archive](archive/README.md), with unresolved acceptance carried forward.

If the wiki disagrees with the current shell, the shell wins. Then the wiki gets fixed.
