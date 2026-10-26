#!/usr/bin/env python3
"""Compute and cache dominant theme color buckets for wallpapers.

Buckets:
- red, orange, yellow, green, cyan, blue, purple, pink, monochrome

Reads newline-separated file paths from stdin (or CLI arguments) and prints a
JSON object mapping each path to its list of matching color bucket IDs.
"""
from __future__ import annotations

import colorsys
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import sys
import urllib.parse

try:
    from PIL import Image
except ImportError:
    Image = None

XDG_CACHE = Path(os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache"))
CACHE_PATH = XDG_CACHE / "alis" / "wallpaper-color-tags.json"
THUMB_ROOT = XDG_CACHE / "thumbnails"

BUCKET_ORDER = (
    "red",
    "orange",
    "yellow",
    "green",
    "cyan",
    "blue",
    "purple",
    "pink",
    "monochrome",
)


def hue_to_bucket(h_deg: float, s: float, v: float) -> str:
    if v < 0.10 or s < 0.14:
        return "monochrome"
    if h_deg < 14 or h_deg >= 345:
        return "red"
    if h_deg < 42:
        return "orange"
    if h_deg < 68:
        return "yellow"
    if h_deg < 162:
        return "green"
    if h_deg < 200:
        return "cyan"
    if h_deg < 255:
        return "blue"
    if h_deg < 295:
        return "purple"
    return "pink"


def classify_filename_fallback(path: str) -> list[str]:
    lower = Path(path).stem.lower()
    return [b for b in BUCKET_ORDER if b in lower]


def find_existing_thumbnail(path: str) -> str:
    encoded = "/".join(urllib.parse.quote(part, safe="") for part in path.split("/"))
    uri = "file://" + encoded
    md5 = hashlib.md5(uri.encode("utf-8")).hexdigest() + ".png"
    for size_dir in ("normal", "large", "x-large"):
        candidate = THUMB_ROOT / size_dir / md5
        if candidate.is_file():
            return str(candidate)
    return path


def analyze_image(path: str) -> list[str]:
    if Image is None:
        return classify_filename_fallback(path)
    source_path = find_existing_thumbnail(path)
    try:
        with Image.open(source_path) as img:
            try:
                img.draft("RGB", (64, 64))
            except Exception:
                pass
            small = img.convert("RGB").resize((16, 16))
            raw = small.tobytes()
    except Exception:
        return classify_filename_fallback(path)

    if not raw:
        return []

    counts: dict[str, float] = {b: 0.0 for b in BUCKET_ORDER}
    chromatic_weight = 0.0
    total_weight = 0.0

    for idx in range(0, len(raw) - 2, 3):
        rf = raw[idx] / 255.0
        gf = raw[idx + 1] / 255.0
        bf = raw[idx + 2] / 255.0
        h, s, v = colorsys.rgb_to_hsv(rf, gf, bf)
        h_deg = h * 360.0
        total_weight += 1.0
        if v < 0.10 or s < 0.14:
            counts["monochrome"] += 1.0
            continue
        bucket = hue_to_bucket(h_deg, s, v)
        weight = (0.5 + 0.5 * s) * (0.4 + 0.6 * min(1.0, v * 1.25))
        counts[bucket] += weight
        chromatic_weight += weight

    if total_weight <= 0:
        return []

    mono_ratio = counts["monochrome"] / total_weight
    if chromatic_weight <= 0.01 or mono_ratio >= 0.78:
        return ["monochrome"]

    chromatic_buckets = [
        (bucket, counts[bucket] / chromatic_weight)
        for bucket in BUCKET_ORDER
        if bucket != "monochrome" and counts[bucket] > 0
    ]
    chromatic_buckets.sort(key=lambda item: item[1], reverse=True)

    tags: list[str] = []
    if chromatic_buckets:
        tags.append(chromatic_buckets[0][0])
        for bucket, share in chromatic_buckets[1:3]:
            if share >= 0.22:
                tags.append(bucket)
    if mono_ratio >= 0.58 and "monochrome" not in tags:
        tags.append("monochrome")

    return tags


def load_cache() -> dict[str, dict]:
    try:
        if CACHE_PATH.is_file():
            data = json.loads(CACHE_PATH.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                return data
    except Exception:
        pass
    return {}


def save_cache(cache: dict[str, dict]) -> None:
    try:
        CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
        tmp = CACHE_PATH.with_suffix(".tmp")
        tmp.write_text(json.dumps(cache, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        os.replace(tmp, CACHE_PATH)
    except OSError:
        pass


IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".avif", ".bmp", ".gif"}


def collect_from_roots(roots: list[str]) -> list[str]:
    found: list[str] = []
    seen: set[str] = set()
    for root in roots:
        root_path = Path(os.path.expanduser(root))
        if not root_path.is_dir():
            continue
        for dirpath, _dirnames, filenames in os.walk(root_path):
            for name in filenames:
                if Path(name).suffix.lower() not in IMAGE_EXTS:
                    continue
                full = os.path.join(dirpath, name)
                if full not in seen:
                    seen.add(full)
                    found.append(full)
    return found


def main() -> int:
    raw_args = [arg.strip() for arg in sys.argv[1:] if arg.strip()]
    if raw_args and raw_args[0] == "--roots":
        paths = collect_from_roots(raw_args[1:])
    else:
        paths = raw_args
        if not paths and not sys.stdin.isatty():
            paths = [line.strip() for line in sys.stdin.read().splitlines() if line.strip()]

    cache = load_cache()
    result: dict[str, list[str]] = {}
    to_compute: list[tuple[str, int]] = []

    for path in paths:
        try:
            mtime = int(os.path.getmtime(path))
        except OSError:
            mtime = 0
        cached = cache.get(path)
        if (
            isinstance(cached, dict)
            and cached.get("mtime") == mtime
            and isinstance(cached.get("colors"), list)
        ):
            result[path] = cached["colors"]
        else:
            to_compute.append((path, mtime))

    if to_compute:
        with ThreadPoolExecutor(max_workers=min(8, max(1, len(to_compute)))) as pool:
            computed = list(pool.map(lambda item: analyze_image(item[0]), to_compute))
        for (path, mtime), colors in zip(to_compute, computed):
            result[path] = colors
            if mtime > 0:
                cache[path] = {"mtime": mtime, "colors": colors}
        save_cache(cache)

    sys.stdout.write(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
