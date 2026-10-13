#!/usr/bin/env python3
"""Generate a transient shell palette through the existing theme backend.

Only this bounded cache and private temporary files are written. Config, the
generated active theme, application templates and hardware are never touched.
"""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MEDIA = {".mp4", ".webm", ".mkv", ".avi", ".mov"}


def signature(path):
    try:
        info = path.stat()
        return [str(path), info.st_mtime_ns, info.st_size, info.st_ino]
    except OSError:
        return [str(path), None]


def valid_palette(value):
    return isinstance(value, dict) and all(
        isinstance(value.get(key), str) and re.fullmatch(r"#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?", value[key])
        for key in ["background", "primary", "on_surface"]
    )


def preview(path, options, cache):
    path = path.resolve(strict=True)
    thumbnail = Path(options.pop("thumbnail", ""))
    source = thumbnail if path.suffix.lower() in MEDIA | {".gif"} and thumbnail.is_file() else path
    state = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "alis"
    artifacts = [Path(__file__), ROOT / "scripts/native-dispatch", ROOT / "scripts/colors/generate_colors_material.py",
                 ROOT / "scripts/colors/terminal/scheme-base.json", state / "native-backend", state / "native-bin-dir",
                 ROOT / "native/bin/alis-theme", ROOT / "native/target/release/alis-theme"]
    if os.environ.get("ALIS_NATIVE_BIN_DIR"):
        artifacts.append(Path(os.environ["ALIS_NATIVE_BIN_DIR"]) / "alis-theme")
    else:
        try:
            artifacts.append(Path((state / "native-bin-dir").read_text().strip()) / "alis-theme")
        except OSError:
            pass
    key = hashlib.sha256(json.dumps([1, signature(path), signature(source), options,
                                    [signature(item) for item in artifacts],
                                    os.environ.get("ALIS_NATIVE_BACKEND", "")], sort_keys=True).encode()).hexdigest()
    cache.mkdir(parents=True, exist_ok=True)
    cached = cache / (key + ".json")
    try:
        result = json.loads(cached.read_text())
        if valid_palette(result):
            cached.touch()
            return result
    except (OSError, ValueError):
        pass

    with tempfile.TemporaryDirectory(prefix="palette-", dir=cache) as name:
        temporary = Path(name)
        if source == path and path.suffix.lower() in MEDIA:
            source = temporary / "frame.jpg"
            subprocess.run(["ffmpeg", "-nostdin", "-y", "-i", str(path), "-vf", "thumbnail=n=100",
                            "-frames:v", "1", "-update", "1", "-q:v", "2", str(source)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=12)
        elif source == path and path.suffix.lower() in {".gif", ".svg"}:
            source = temporary / ("frame.jpg" if path.suffix.lower() == ".gif" else "frame.png")
            subprocess.run(["magick", str(path) + "[0]", str(source)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=12)
        output = temporary / "palette.json"
        command = [str(ROOT / "scripts/native-dispatch"), "theme", "--path", str(source),
                   "--mode", options.get("mode", "dark"), "--scheme", options.get("scheme", "auto"),
                   "--termscheme", str(ROOT / "scripts/colors/terminal/scheme-base.json"), "--blend_bg_fg",
                   "--json-output", str(output)]
        for flag in ["color-strength", "term_saturation", "term_brightness", "harmony",
                     "term_bg_brightness", "harmonize_threshold", "term_fg_boost"]:
            if flag in options:
                command.extend(["--" + flag, str(options[flag])])
        for flag in ["soften", "invert-hue"]:
            if options.get(flag):
                command.append("--" + flag)
        subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, check=True, timeout=20)
        result = json.loads(output.read_text())
        if not valid_palette(result):
            raise ValueError("theme backend returned an invalid preview palette")
        # Unique private temporary output makes simultaneous shell processes safe.
        os.replace(output, cached)
    entries = []
    for entry in cache.glob("[0-9a-f]" * 64 + ".json"):
        try:
            entries.append((entry.stat().st_mtime_ns, entry))
        except FileNotFoundError:
            pass
    for _, entry in sorted(entries, reverse=True)[32:]:
        entry.unlink(missing_ok=True)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    parser.add_argument("options", help="JSON containing generation options")
    args = parser.parse_args()
    cache = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "quickshell/palette-preview"
    try:
        print(json.dumps(preview(args.path, json.loads(args.options), cache), separators=(",", ":")))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, "Wallpaper palette preview failed: " + str(error) + "\n")
