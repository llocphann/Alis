# Wallpaper System

Pick a wallpaper and the entire desktop follows. Colors propagate to the shell, GTK apps, terminals, Firefox, Discord, VS Code, and the SDDM login screen.

## Setting a wallpaper

**From the shell**: open the wallpaper selector (`Super+W` or through Settings) and browse your filesystem. Click a wallpaper to apply it. The color pipeline runs automatically.

**From Settings**: Appearance section lets you configure wallpaper behavior, blur, and auto-cycling.

## Liquid transition (Alis)

Choose **Liquid** under Settings → Appearance → Background → Motion.
The `alisMelt` preference uses the bundled GLSL/QSB shader. Saved
`alisMelt` preferences still use the same shader. Abyss Liquid now reveals
wallpapers with an organic, softly refracting fluid front instead of discrete
vertical columns. Its moving membrane deliberately shares the actual
Abyss Panel material: `AbyssStyle.surface`, `surfaceRaised`, `specular`,
`shadow` and `glow`, with the same surface opacity, highlight and motion
settings. Panel and Liquid therefore inherit the same live theme and effects
policy instead of independently tinting the wallpaper with a strong accent.
The soft contact refraction is limited to the front, not the entire image.

The effect's shader binary is built from `alisMelt.frag` by the
`alis-liquid-qsb-bake.yml` dev workflow. Updating only the GLSL source is
insufficient: deployed Quickshell uses the compiled `.frag.qsb` asset. Alis
keeps the old wallpaper visible until a shader frame has been presented.

If the graphics renderer is software-only, shader compilation fails, or
the compositor stalls, the Ready-slot fade fallback applies the new
wallpaper. Such a fallback **does not count as a Liquid render**.
You can disable only the shader with `ALIS_DISABLE_LIQUID_SHADER=1`.
Owner testing still needs live Niri/Quickshell, rapid changes, multiple
outputs and desktop/Overview parity.

## What happens when you set a wallpaper

```
Image selected
  |
switchwall.sh (orchestrator)
  |
generate_colors_material.py
  - Extracts dominant colors from the image
  - Generates a full Material 3 palette (50+ color tokens)
  - Writes colors.json
  |
applycolor.sh (runs per-app theming modules in parallel)
  - GTK 3/4 themes
  - Terminal configs (foot, kitty, alacritty)
  - Starship prompt
  - Fuzzel launcher
  - Firefox (pywalfox)
  - VS Code, Cursor, OpenCode (Go generators)
  - btop, lazygit, yazi
  - SDDM login theme
  - Discord/Vesktop
  |
MaterialThemeLoader (QML, watches colors.json)
  |
Appearance tokens update --> Every UI component re-renders
```

The whole pipeline takes 2-3 seconds. The shell updates immediately when colors.json changes. External apps update within a few seconds as their configs are rewritten.

## Supported formats

**Images**: jpg, jpeg, png, webp, avif, gif, bmp, tiff, jxl

**Video**: mp4, webm, mkv, avi, mov. The first frame is extracted for color generation. Video plays as a live wallpaper with optional blur.

## Multi-monitor

Each monitor can have its own wallpaper. Configure per-monitor wallpapers in Settings under Appearance > Background > Multi-monitor.

Per-monitor config includes:
- Wallpaper path
- Optional workspace range (for Niri's scrolling workspaces)
- Optional backdrop path (for supported wallpaper-backed blur/glass effects)

## Video wallpapers

Video files play as live wallpapers. First frame is automatically extracted and cached at `~/.cache/quickshell/video_thumbnails/` for color generation and thumbnail display.

Options:
- **Blur**: apply blur to the video
- **Freeze frame**: show only the first frame (saves GPU)
- **Loop**: video loops continuously

## Backdrop system

The "backdrop" is a separate wallpaper (or the main wallpaper with heavy blur) used by supported surfaces that intentionally request wallpaper-backed blur/glass presentation. It is an effect input, not a selectable Global Theme. This lets the desktop keep a sharp wallpaper while compatible translucent surfaces can render against a blurred source.

## Auto-cycling

Set an interval and Alis cycles through wallpapers in a directory automatically. Configurable per-directory with optional color regeneration on each change.

Settings -> Appearance -> Background -> Shuffle wallpapers controls:

- enable/disable automatic shuffle
- interval in minutes
- optional folder override
- whether theme colors regenerate after each shuffle

Leave the folder empty to shuffle inside the current wallpaper directory. Turn color regeneration off if you want the wallpaper to change without repainting GTK, terminals, Discord, SDDM, and the rest of the parade.

## Wallhaven integration

The left sidebar includes a Wallhaven browser. Search wallhaven.cc, preview results, and apply wallpapers directly from the shell. Supports NSFW filtering, resolution filtering, and category selection.

## Theme presets

46 built-in presets bypass the wallpaper color pipeline entirely and inject predefined color palettes. See [Theming Presets](THEMING_PRESETS.md).

When a preset is active, changing wallpapers still changes the background image but doesn't regenerate colors. Switch back to "Auto" mode in Settings to restore wallpaper-based theming.

## CLI reference

There is no `alis wallpapers` command. The real IPC target is
`wallpaperSelector` (see [docs/IPC.md](IPC.md)):

```bash
alis wallpaperSelector toggle   # Open/close the wallpaper picker grid
alis wallpaperSelector random   # Pick a random wallpaper from the current folder
```

Setting a specific wallpaper by path is done through the picker UI (or the
Wallhaven browser), not a raw CLI setter.
