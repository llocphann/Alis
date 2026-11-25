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
import math
import os
from pathlib import Path
import sys
import urllib.parse

try:
    from PIL import Image
except ImportError:
    Image = None

try:
    import numpy as np
    from materialyoucolor.dynamiccolor.material_dynamic_colors import MaterialDynamicColors
    from materialyoucolor.hct import Hct
    from materialyoucolor.quantize import QuantizeCelebi
    from materialyoucolor.scheme.scheme_content import SchemeContent
    from materialyoucolor.scheme.scheme_expressive import SchemeExpressive
    from materialyoucolor.scheme.scheme_fidelity import SchemeFidelity
    from materialyoucolor.scheme.scheme_fruit_salad import SchemeFruitSalad
    from materialyoucolor.scheme.scheme_monochrome import SchemeMonochrome
    from materialyoucolor.scheme.scheme_neutral import SchemeNeutral
    from materialyoucolor.scheme.scheme_rainbow import SchemeRainbow
    from materialyoucolor.scheme.scheme_tonal_spot import SchemeTonalSpot
    from materialyoucolor.scheme.scheme_vibrant import SchemeVibrant
    from materialyoucolor.score.score import Score

    HAVE_MATERIAL = True
except ImportError:
    HAVE_MATERIAL = False

CACHE_VERSION = 3
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


def hue_deg_to_chromatic_bucket(h_deg: float) -> str:
    h = h_deg % 360.0
    if h < 14.0 or h >= 345.0:
        return "red"
    if h < 40.0:
        return "orange"
    if h < 68.0:
        return "yellow"
    if h < 162.0:
        return "green"
    if h < 200.0:
        return "cyan"
    if h < 255.0:
        return "blue"
    if h < 295.0:
        return "purple"
    return "pink"


def hue_to_bucket(h_deg: float, s: float, v: float) -> str:
    if v < 0.10 or s < 0.14:
        return "monochrome"
    return hue_deg_to_chromatic_bucket(h_deg)


def hue_distance_deg(a: float, b: float) -> float:
    d = (a - b) % 360.0
    return min(d, 360.0 - d)


def configured_scheme_option() -> str:
    trimmed = os.environ.get("ALIS_COLOR_TAGS_SCHEME", "").strip()
    return trimmed if trimmed else "auto"


def configured_invert_hue() -> bool:
    raw = os.environ.get("ALIS_COLOR_TAGS_INVERT_HUE", "").strip().lower()
    return raw in {"1", "true", "yes", "on"}


def _calculate_optimal_size(width: int, height: int, bitmap_size: int = 128) -> tuple[int, int]:
    image_area = width * height
    bitmap_area = bitmap_size**2
    scale = math.sqrt(bitmap_area / image_area) if image_area > bitmap_area else 1.0
    return max(1, round(width * scale)), max(1, round(height * scale))


def _auto_detect_scheme(pil_image) -> str:
    if not HAVE_MATERIAL:
        return "scheme-tonal-spot"
    arr = np.array(pil_image, dtype=np.float64)
    if arr.ndim != 3 or arr.shape[2] < 3:
        return "scheme-tonal-spot"
    r_ch, g_ch, b_ch = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    rg = np.absolute(r_ch - g_ch)
    yb = np.absolute(0.5 * (r_ch + g_ch) - b_ch)
    colorfulness = float(
        np.sqrt(np.std(rg) ** 2 + np.std(yb) ** 2)
        + 0.3 * np.sqrt(np.mean(rg) ** 2 + np.mean(yb) ** 2)
    )
    r, g, b = r_ch / 255.0, g_ch / 255.0, b_ch / 255.0
    maxc = np.maximum(np.maximum(r, g), b)
    minc = np.minimum(np.minimum(r, g), b)
    s = np.where(maxc > 0, (maxc - minc) / maxc, 0.0) * 255.0
    delta = maxc - minc
    h = np.zeros_like(r)
    with np.errstate(invalid="ignore", divide="ignore"):
        mask = delta > 0
        idx = (maxc == r) & mask
        h[idx] = 30.0 * (((g[idx] - b[idx]) / delta[idx]) % 6)
        idx = (maxc == g) & mask
        h[idx] = 30.0 * ((b[idx] - r[idx]) / delta[idx] + 2)
        idx = (maxc == b) & mask
        h[idx] = 30.0 * ((r[idx] - g[idx]) / delta[idx] + 4)
    saturation = float(np.mean(s))
    hue_spread = float(np.std(h))
    if saturation < 20:
        return "scheme-monochrome"
    if colorfulness < 30:
        if saturation < 55:
            return "scheme-neutral"
        if hue_spread < 22:
            return "scheme-content"
        return "scheme-tonal-spot"
    if colorfulness < 55:
        if hue_spread < 22 and saturation < 100:
            return "scheme-content"
        return "scheme-tonal-spot"
    if colorfulness < 90:
        if saturation > 140 and hue_spread < 35:
            return "scheme-fidelity"
        if hue_spread < 30:
            return "scheme-content"
        return "scheme-tonal-spot"
    if hue_spread > 55 and saturation > 150:
        return "scheme-rainbow"
    if saturation > 160:
        return "scheme-fidelity"
    if hue_spread > 45:
        return "scheme-expressive"
    return "scheme-tonal-spot"


def _primary_theme_color(seed: int, scheme_name: str) -> int:
    scheme_cls = {
        "scheme-fruit-salad": SchemeFruitSalad,
        "scheme-expressive": SchemeExpressive,
        "scheme-monochrome": SchemeMonochrome,
        "scheme-rainbow": SchemeRainbow,
        "scheme-neutral": SchemeNeutral,
        "scheme-fidelity": SchemeFidelity,
        "scheme-content": SchemeContent,
        "scheme-vibrant": SchemeVibrant,
        "scheme-tonal-spot": SchemeTonalSpot,
    }.get(scheme_name, SchemeTonalSpot)
    hct = Hct.from_int(seed)
    try:
        scheme = scheme_cls(hct, True, 0.0, spec_version="2025")
    except TypeError:
        scheme = scheme_cls(hct, True, 0.0)
    mdc = MaterialDynamicColors()
    argb = mdc.primary.get_argb(scheme)
    if scheme_name != "scheme-monochrome":
        p_hct = Hct.from_int(argb)
        if not (70.0 <= p_hct.tone <= 85.0):
            argb = scheme.primary_palette.tone(80)
        p_hct = Hct.from_int(argb)
        if p_hct.chroma > 60.0:
            argb = Hct.from_hct(p_hct.hue, 60.0, p_hct.tone).to_int()
        elif 4.0 <= p_hct.chroma < 36.0:
            argb = Hct.from_hct(p_hct.hue, 36.0, p_hct.tone).to_int()
    return argb


def classify_filename_fallback(path: str) -> list[str]:
    lower = Path(path).stem.lower()
    return [b for b in BUCKET_ORDER if b in lower]


def find_existing_thumbnail(path: str) -> str:
    encoded = "/".join(urllib.parse.quote(part, safe="-_.~") for part in path.split("/"))
    uri = "file://" + encoded
    md5 = hashlib.md5(uri.encode("utf-8")).hexdigest() + ".png"
    for size_dir in ("normal", "large", "x-large", "xx-large"):
        candidate = THUMB_ROOT / size_dir / md5
        if candidate.is_file():
            return str(candidate)
    return path


def _valid_features(feat: object) -> bool:
    if not isinstance(feat, dict):
        return False
    return (
        isinstance(feat.get("auto"), str)
        and isinstance(feat.get("mono"), (int, float))
        and isinstance(feat.get("cw"), (int, float))
        and isinstance(feat.get("tw"), (int, float))
        and isinstance(feat.get("bw"), list) and len(feat["bw"]) == 8
        and isinstance(feat.get("hw"), list) and len(feat["hw"]) == 36
        and isinstance(feat.get("hp"), list) and len(feat["hp"]) == 36
    )


def extract_image_features(path: str) -> dict | None:
    if Image is None:
        return None
    source_path = find_existing_thumbnail(path)
    try:
        with Image.open(source_path) as raw_img:
            if raw_img.format == "GIF":
                try:
                    raw_img.seek(1)
                except EOFError:
                    pass
            try:
                raw_img.draft("RGB", (256, 256))
            except Exception:
                pass
            img = raw_img.convert("RGB")
            w, h = img.size
            opt_w, opt_h = _calculate_optimal_size(w, h, 128)
            if opt_w < w or opt_h < h:
                img = img.resize((opt_w, opt_h), Image.Resampling.BILINEAR)
            sample_raw = img.resize((32, 32), Image.Resampling.BILINEAR).tobytes()
            pixels = list(img.get_flattened_data() if hasattr(img, "get_flattened_data") else img.getdata())
    except Exception:
        return None

    if not sample_raw:
        return {
            "seed": None,
            "auto": "scheme-tonal-spot",
            "mono": 0.0,
            "cw": 0.0,
            "tw": 0.0,
            "bw": [0.0] * 8,
            "hw": [0.0] * 36,
            "hp": [0] * 36,
        }

    mono_count = 0.0
    chromatic_weight = 0.0
    total_weight = 0.0
    bucket_idx = {b: i for i, b in enumerate(BUCKET_ORDER[:8])}
    bucket_weights = [0.0] * 8
    hue_weights = [0.0] * 36
    hue_pixels = [0] * 36

    for idx in range(0, len(sample_raw) - 2, 3):
        rf = sample_raw[idx] / 255.0
        gf = sample_raw[idx + 1] / 255.0
        bf = sample_raw[idx + 2] / 255.0
        h, s, v = colorsys.rgb_to_hsv(rf, gf, bf)
        h_deg = h * 360.0
        total_weight += 1.0
        if v < 0.10 or s < 0.14:
            mono_count += 1.0
            continue
        bucket = hue_deg_to_chromatic_bucket(h_deg)
        weight = (0.5 + 0.5 * s) * (0.4 + 0.6 * min(1.0, v * 1.25))
        bucket_weights[bucket_idx[bucket]] += weight
        chromatic_weight += weight
        b = min(35, int((h_deg % 360.0) // 10.0))
        hue_weights[b] += weight
        hue_pixels[b] += 1

    if total_weight <= 0:
        return {
            "seed": None,
            "auto": "scheme-tonal-spot",
            "mono": 0.0,
            "cw": 0.0,
            "tw": 0.0,
            "bw": [0.0] * 8,
            "hw": [0.0] * 36,
            "hp": [0] * 36,
        }

    mono_ratio = mono_count / total_weight
    auto_scheme = _auto_detect_scheme(img)
    seed: int | None = None
    if HAVE_MATERIAL:
        seed = int(Score.score(QuantizeCelebi(pixels, 128))[0]) & 0xFFFFFFFF

    return {
        "seed": seed,
        "auto": auto_scheme,
        "mono": round(mono_ratio, 4),
        "cw": round(chromatic_weight, 4),
        "tw": round(total_weight, 4),
        "bw": [round(x, 4) for x in bucket_weights],
        "hw": [round(x, 4) for x in hue_weights],
        "hp": hue_pixels,
    }


def classify_from_features(
    features: dict,
    scheme_opt: str = "auto",
    invert_hue_opt: bool = False,
) -> list[str]:
    total_weight = float(features.get("tw", 0.0))
    if total_weight <= 0.0:
        return []
    chromatic_weight = float(features.get("cw", 0.0))
    mono_ratio = float(features.get("mono", 0.0))
    eff_scheme = str(features.get("auto", "scheme-tonal-spot")) if scheme_opt == "auto" else scheme_opt

    if eff_scheme == "scheme-monochrome" or chromatic_weight <= 0.01:
        return ["monochrome"]

    raw_seed = features.get("seed")
    if not HAVE_MATERIAL or raw_seed is None:
        bw = features.get("bw", [0.0] * 8)
        best_i = max((i for i in range(min(8, len(bw))) if bw[i] > 0), key=lambda i: bw[i], default=None)
        return [BUCKET_ORDER[best_i]] if best_i is not None else ["monochrome"]

    seed = int(raw_seed) & 0xFFFFFFFF
    raw_seed_hct = Hct.from_int(seed)
    if not invert_hue_opt and mono_ratio >= 0.85 and raw_seed_hct.chroma < 15.0:
        return ["monochrome"]

    if invert_hue_opt:
        seed = Hct.from_hct((raw_seed_hct.hue + 180.0) % 360.0, raw_seed_hct.chroma, raw_seed_hct.tone).to_int()

    primary_argb = _primary_theme_color(seed, eff_scheme)
    primary_hct = Hct.from_int(primary_argb)
    if primary_hct.chroma < 8.0 or (raw_seed_hct.chroma < 12.0 and mono_ratio >= 0.65):
        return ["monochrome"]

    pr = ((primary_argb >> 16) & 0xFF) / 255.0
    pg = ((primary_argb >> 8) & 0xFF) / 255.0
    pb = (primary_argb & 0xFF) / 255.0
    hp, _, _ = colorsys.rgb_to_hsv(pr, pg, pb)
    theme_hue_deg = hp * 360.0
    theme_bucket = hue_deg_to_chromatic_bucket(theme_hue_deg)

    hw = features["hw"]
    hp_counts = features["hp"]
    matched_weight = 0.0
    matched_pixels = 0.0
    for bin_idx in range(36):
        px_count = float(hp_counts[bin_idx])
        if px_count <= 0.0:
            continue
        bin_center = bin_idx * 10.0 + 5.0
        if hue_deg_to_chromatic_bucket(bin_center) == theme_bucket or hue_distance_deg(bin_center, theme_hue_deg) <= 28.0:
            matched_weight += float(hw[bin_idx])
            matched_pixels += px_count

    visual_support = matched_weight / max(1e-6, chromatic_weight)
    matched_pixel_ratio = matched_pixels / total_weight
    if visual_support >= 0.08 and matched_pixel_ratio >= 0.005:
        return [theme_bucket]

    if mono_ratio >= 0.78:
        return ["monochrome"]
    return []


def analyze_image(
    path: str,
    scheme_opt: str = "auto",
    invert_hue_opt: bool = False,
) -> list[str]:
    features = extract_image_features(path)
    if features is None:
        return classify_filename_fallback(path)
    return classify_from_features(features, scheme_opt, invert_hue_opt)


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
    visited_dirs: set[str] = set()
    for raw_root in roots:
        cleaned = raw_root.rstrip("/") or ("/" if raw_root else "")
        root_path = os.path.expanduser(cleaned)
        if not os.path.isdir(root_path):
            continue
        root_real = os.path.realpath(root_path)
        visited_dirs.add(root_real)
        for dirpath, dirnames, filenames in os.walk(root_path, followlinks=True):
            kept_dirs = []
            for dname in dirnames:
                cand_real = os.path.realpath(os.path.join(dirpath, dname))
                if cand_real not in visited_dirs:
                    visited_dirs.add(cand_real)
                    kept_dirs.append(dname)
            dirnames[:] = kept_dirs
            for name in filenames:
                if Path(name).suffix.lower() not in IMAGE_EXTS:
                    continue
                full = os.path.join(dirpath, name)
                if os.path.isfile(full) and full not in seen:
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

    scheme_opt = configured_scheme_option()
    invert_hue_opt = configured_invert_hue()
    cache = load_cache()
    result: dict[str, list[str]] = {}
    to_compute: list[tuple[str, int]] = []
    cache_dirty = False

    for path in paths:
        try:
            mtime = int(os.path.getmtime(path))
        except OSError:
            mtime = 0
        cached = cache.get(path)
        if isinstance(cached, dict) and cached.get("mtime") == mtime:
            ver = cached.get("v")
            if (
                ver in (2, CACHE_VERSION)
                and cached.get("scheme") == scheme_opt
                and bool(cached.get("invert", False)) == invert_hue_opt
                and isinstance(cached.get("colors"), list)
            ):
                result[path] = cached["colors"]
                continue
            feat = cached.get("feat")
            if mtime > 0 and ver == CACHE_VERSION and _valid_features(feat):
                colors = classify_from_features(feat, scheme_opt, invert_hue_opt)
                cached["scheme"] = scheme_opt
                cached["invert"] = invert_hue_opt
                cached["colors"] = colors
                result[path] = colors
                cache_dirty = True
                continue
        to_compute.append((path, mtime))

    if to_compute:
        def _worker(item: tuple[str, int]):
            p = item[0]
            feat = extract_image_features(p)
            cols = classify_from_features(feat, scheme_opt, invert_hue_opt) if feat is not None else classify_filename_fallback(p)
            return feat, cols

        with ThreadPoolExecutor(max_workers=min(8, max(1, len(to_compute)))) as pool:
            computed = list(pool.map(_worker, to_compute))
        for (path, mtime), (feat, colors) in zip(to_compute, computed):
            result[path] = colors
            if mtime > 0:
                entry: dict = {
                    "v": CACHE_VERSION,
                    "mtime": mtime,
                    "scheme": scheme_opt,
                    "invert": invert_hue_opt,
                    "colors": colors,
                }
                if feat is not None:
                    entry["feat"] = feat
                cache[path] = entry
                cache_dirty = True

    if cache_dirty:
        save_cache(cache)

    sys.stdout.write(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
