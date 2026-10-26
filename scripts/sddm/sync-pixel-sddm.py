#!/usr/bin/env python3
"""Sync ii-pixel SDDM theme colors with current Material You palette.

Reads generated colors from Alis's generated palette and updates
the ii-pixel theme.conf with matching colors.
Reads wallpaper path from Alis state and updates background image.

Note: install-pixel-sddm.sh transfers ownership of the theme directory to
the current user at install time, so no sudo/polkit is required here.
"""

import filecmp
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile

THEME_NAME = "ii-pixel"
THEME_DIR = f"/usr/share/sddm/themes/{THEME_NAME}"
THEME_CONF = os.path.join(THEME_DIR, "theme.conf")
ASSETS_DIR = os.path.join(THEME_DIR, "assets")

# Canonical template structure — restored when theme.conf is corrupted.
# Only the structural/metadata lines; color keys are appended by update_theme_conf().
THEME_CONF_TEMPLATE = """\
[SddmTheme]
Name=ii-pixel
Description=Alis SDDM login screen — Material You dynamic colors
Type=sddm-theme
Author=Alis project
Version=1.0
Website=https://github.com/snowarch/Alis
Screenshot=
MainScript=Main.qml
ConfigFile=theme.conf

[General]
background=assets/background.png
defaultBackground=assets/default-background.svg
blurRadius=50

# Alis Material You colors — updated automatically by sync-pixel-sddm.py on wallpaper change"""

# When invoked via `sudo`, resolve paths against the real user's home,
# not root's home — SUDO_USER contains the original username.
_sudo_user = os.environ.get("SUDO_USER", "")
if _sudo_user:
    import pwd

    _real_home = pwd.getpwnam(_sudo_user).pw_dir
else:
    _real_home = os.path.expanduser("~")

STATE_DIR = os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.join(_real_home, ".local", "state"),
    "quickshell",
)
APP_PALETTE_JSON = os.path.join(STATE_DIR, "user", "generated", "app-palette.json")
PALETTE_JSON = os.path.join(STATE_DIR, "user", "generated", "palette.json")
COLORS_JSON = os.path.join(STATE_DIR, "user", "generated", "colors.json")

CONFIG_JSON = os.path.join(
    os.environ.get("XDG_CONFIG_HOME") or os.path.join(_real_home, ".config"),
    "alis",
    "config.json",
)


def read_colors():
    """Read Material You colors from Alis's generated palette.

    Handles both output formats:
    - Flat:   { "primary": "#...", "on_primary": "#...", ... }   (current contract)
    - Nested: { "colors": { "dark": { "primary": "#...", ... } } }
    """
    source = next(
        (
            path
            for path in (APP_PALETTE_JSON, PALETTE_JSON, COLORS_JSON)
            if os.path.isfile(path)
        ),
        None,
    )
    if source is None:
        print(f"[sddm-pixel] generated palette not found: {APP_PALETTE_JSON}")
        return None
    with open(source) as f:
        data = json.load(f)

    # Try nested format first, then fall back to flat
    dark = data.get("colors", {}).get("dark", {})
    if not dark:
        # Flat format: keys are directly on the root object
        if "primary" in data or "on_surface" in data:
            dark = data
        else:
            print("[sddm-pixel] No dark colors in generated palette")
            return None

    return {
        "primaryColor": dark.get("app_accent") or dark.get("primary", "#cba6f7"),
        "onPrimaryColor": dark.get("app_on_accent") or dark.get("on_primary", "#1e1e2e"),
        "surfaceColor": dark.get("app_background") or dark.get("surface", "#1e1e2e"),
        "surfaceContainerColor": dark.get("app_surface")
        or dark.get("surface_container", "#181825"),
        "onSurfaceColor": dark.get("app_foreground") or dark.get("on_surface", "#cdd6f4"),
        "onSurfaceVariantColor": dark.get("app_subtext")
        or dark.get("on_surface_variant", "#9399b2"),
        "backgroundColor": dark.get("app_background") or dark.get("background", "#1e1e2e"),
        "errorColor": dark.get("error", "#f38ba8"),
    }


def read_wallpaper():
    """Read current wallpaper path from Alis config.json."""
    if not os.path.isfile(CONFIG_JSON):
        return None
    try:
        with open(CONFIG_JSON) as f:
            config = json.load(f)

        panel_family = config.get("panelFamily", "ii")
        background = config.get("background", {}) or {}
        waffles = config.get("waffles", {}) or {}
        waffles_background = waffles.get("background", {}) or {}

        main_path = background.get("wallpaperPath", "")
        if panel_family == "waffle":
            use_main = waffles_background.get("useMainWallpaper", True)
            waffle_path = waffles_background.get("wallpaperPath", "")
            path = main_path if use_main else (waffle_path or main_path)
        else:
            path = main_path

        if path and path.startswith("file://"):
            path = path[7:]
        return path if path and os.path.isfile(path) else None
    except Exception:
        return None


def read_material_shape_chars():
    """Mirror lockscreen password behavior flag into SDDM theme config."""
    if not os.path.isfile(CONFIG_JSON):
        return "false"
    try:
        with open(CONFIG_JSON) as f:
            config = json.load(f)
        val = (config.get("lock", {}) or {}).get("materialShapeChars", False)
        return "true" if bool(val) else "false"
    except Exception:
        return "false"


def update_theme_conf(colors):
    """Update ii-pixel theme.conf [General] section with new colors.

    Self-heals corrupted files: if the [General] section or
    ``background=`` key are missing, the canonical template structure
    is restored before applying color values.
    """
    if not os.path.isfile(THEME_CONF):
        print(f"[sddm-pixel] theme.conf not found: {THEME_CONF}")
        return False

    with open(THEME_CONF) as f:
        original_content = f.read()
    lines = original_content.split("\n")

    # Detect corruption: [General] or the background= directive missing.
    has_general = any("[General]" in l for l in lines)
    has_background = any(l.strip().startswith("background=") for l in lines)
    if not has_general or not has_background:
        print(
            "[sddm-pixel] theme.conf missing structural elements — restoring template"
        )
        lines = THEME_CONF_TEMPLATE.split("\n")

    remaining = dict(colors)
    remaining["materialShapeChars"] = read_material_shape_chars()
    new_lines = []
    for line in lines:
        stripped = line.strip()
        matched = False
        for key, value in remaining.items():
            if stripped.startswith(f"{key}="):
                new_lines.append(f"{key}={value}")
                remaining.pop(key)
                matched = True
                break
        if not matched:
            new_lines.append(line)
    for key, value in remaining.items():
        new_lines.append(f"{key}={value}")
    content = "\n".join(new_lines)
    if content == original_content:
        return True

    try:
        with open(THEME_CONF, "w") as f:
            f.write(content)
        return True
    except PermissionError:
        print(f"[sddm-pixel] Permission denied writing {THEME_CONF}.")
        print(f"[sddm-pixel] Re-run install-pixel-sddm.sh to fix ownership.")
        return False
    except OSError as e:
        print(f"[sddm-pixel] Error writing theme.conf: {e}")
        return False


def update_avatar():
    """Copy user avatar to a world-readable theme asset for SDDM.

    This avoids permission issues when reading ~/.face from the sddm user.
    Source order matches lockscreen intent:
      1) ~/.face
      2) ~/.face.icon
      3) /var/lib/AccountsService/icons/<user>
    """
    if not os.path.isdir(ASSETS_DIR):
        try:
            os.makedirs(ASSETS_DIR, exist_ok=True)
        except Exception:
            return False

    username = _sudo_user or os.environ.get("USER", "")
    candidates = [
        os.path.join(_real_home, ".face"),
        os.path.join(_real_home, ".face.icon"),
    ]
    if username:
        candidates.append(f"/var/lib/AccountsService/icons/{username}")

    src = next((p for p in candidates if p and os.path.isfile(p)), None)
    if not src:
        return False

    dst = os.path.join(ASSETS_DIR, "user-face.png")
    try:
        if os.path.isfile(dst) and filecmp.cmp(src, dst, shallow=True):
            os.chmod(dst, 0o644)
            return True
        shutil.copy2(src, dst)
        os.chmod(dst, 0o644)
        print(f"[sddm-pixel] Avatar updated: {os.path.basename(src)}")
        return True
    except Exception as e:
        print(f"[sddm-pixel] Avatar sync failed: {e}")
        return False


VIDEO_EXTENSIONS = {".mp4", ".mkv", ".webm", ".avi", ".mov", ".gif", ".webp"}


def extract_video_frame(video_path, dest_png):
    """Use ffmpeg to extract the first frame of a video as PNG. Returns tmp path on success, None on failure."""
    if not shutil.which("ffmpeg"):
        print("[sddm-pixel] ffmpeg not found — cannot extract video frame")
        return None
    tmp = os.path.join("/tmp", f"sddm-pixel-frame-{os.getpid()}.tmp.png")
    try:
        proc = subprocess.run(
            [
                "ffmpeg",
                "-y",
                "-i",
                video_path,
                "-vframes",
                "1",
                "-update",
                "1",
                "-f",
                "image2",
                tmp,
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=15,
        )
        if proc.returncode == 0 and os.path.isfile(tmp):
            return tmp
        print(
            f"[sddm-pixel] ffmpeg frame extraction failed for {os.path.basename(video_path)}"
        )
        return None
    except Exception as e:
        print(f"[sddm-pixel] ffmpeg error: {e}")
        return None


def _published_background_ready(path):
    """The greeter cannot read a private source's inherited 0600 mode."""
    try:
        info = os.lstat(path)
        return stat.S_ISREG(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o644
    except OSError:
        return False


def _publish_background(src, dest):
    """Publish a complete, greeter-readable copy without changing the source."""
    fd, staging = tempfile.mkstemp(prefix=".alis-background-", suffix=".png", dir=ASSETS_DIR)
    os.close(fd)
    try:
        shutil.copy2(src, staging)
        with open(staging, "rb") as image:
            os.fchmod(image.fileno(), 0o644)
            os.fsync(image.fileno())
        # Replacing a legacy symlink publishes a new managed asset; never chmod
        # or truncate the user's private wallpaper through that symlink.
        os.replace(staging, dest)
        directory = os.open(ASSETS_DIR, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(staging):
            os.unlink(staging)


def update_background(wallpaper_path):
    """Copy current wallpaper (or its first video frame) to theme assets/background.png."""
    if not wallpaper_path:
        return False
    try:
        if os.path.islink(ASSETS_DIR):
            print("[sddm-pixel] Refusing a symlinked managed assets directory")
            return False
        os.makedirs(ASSETS_DIR, exist_ok=True)
        # A restrictive session umask must not make the managed greeter assets
        # directory inaccessible to SDDM. No source directory is changed.
        if stat.S_IMODE(os.stat(ASSETS_DIR).st_mode) != 0o755:
            os.chmod(ASSETS_DIR, 0o755)
    except OSError:
        print(f"[sddm-pixel] Cannot prepare greeter assets in {ASSETS_DIR}.")
        return False

    bg_dest = os.path.join(ASSETS_DIR, "background.png")
    ext = os.path.splitext(wallpaper_path)[1].lower()
    src = wallpaper_path
    video_stamp_path = os.path.join(ASSETS_DIR, ".alis-background-source.json")
    video_stamp = None

    if ext in VIDEO_EXTENSIONS:
        try:
            source_stat = os.stat(wallpaper_path)
            video_stamp = json.dumps(
                {
                    "path": os.path.realpath(wallpaper_path),
                    "size": source_stat.st_size,
                    "mtime_ns": source_stat.st_mtime_ns,
                },
                sort_keys=True,
            )
            if os.path.isfile(bg_dest) and os.path.isfile(video_stamp_path):
                with open(video_stamp_path) as f:
                    if f.read() == video_stamp:
                        if not _published_background_ready(bg_dest):
                            _publish_background(bg_dest, bg_dest)
                        return True
        except OSError:
            video_stamp = None

        tmp_frame = extract_video_frame(wallpaper_path, bg_dest)
        if tmp_frame is None:
            print("[sddm-pixel] Keeping existing background (video, no ffmpeg)")
            return False
        src = tmp_frame
    elif _published_background_ready(bg_dest):
        try:
            if filecmp.cmp(wallpaper_path, bg_dest, shallow=True):
                # copy2 preserves size and mtime; no rewrite on unchanged sync.
                return True
        except OSError:
            print("[sddm-pixel] Wallpaper unavailable; keeping the existing background")
            return False

    try:
        _publish_background(src, bg_dest)
        if ext in VIDEO_EXTENSIONS and os.path.isfile(src):
            os.unlink(src)
        if video_stamp is not None:
            stamp_tmp = f"{video_stamp_path}.tmp-{os.getpid()}"
            try:
                with open(stamp_tmp, "w") as f:
                    f.write(video_stamp)
                os.replace(stamp_tmp, video_stamp_path)
            except OSError:
                try:
                    os.unlink(stamp_tmp)
                except OSError:
                    pass
        print(f"[sddm-pixel] Background updated: {os.path.basename(wallpaper_path)}")
        return True
    except PermissionError:
        print(f"[sddm-pixel] Permission denied writing to {ASSETS_DIR}.")
        print(f"[sddm-pixel] Re-run install-pixel-sddm.sh to fix ownership.")
        if ext in VIDEO_EXTENSIONS and os.path.isfile(src):
            os.unlink(src)
        return False
    except Exception as e:
        print(f"[sddm-pixel] Error updating background: {e}")
        if ext in VIDEO_EXTENSIONS and os.path.isfile(src):
            os.unlink(src)
        return False


def main():
    if not os.path.isdir(THEME_DIR):
        print(
            f"[sddm-pixel] Theme not installed at {THEME_DIR}. Run install-pixel-sddm.sh first."
        )
        return

    colors = read_colors()
    if colors:
        if update_theme_conf(colors):
            print(f"[sddm-pixel] Colors synced (primary: {colors['primaryColor']})")
        else:
            print("[sddm-pixel] Color sync failed")
    else:
        print("[sddm-pixel] No colors available, skipping color sync")

    wallpaper = read_wallpaper()
    if wallpaper:
        update_background(wallpaper)
    else:
        print("[sddm-pixel] No wallpaper path found, keeping existing background")

    update_avatar()


if __name__ == "__main__":
    main()
