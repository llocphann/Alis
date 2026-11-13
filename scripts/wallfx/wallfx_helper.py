#!/usr/bin/env python3
"""wallfx_helper.py — Favourite-only Pocket-Dots (`perfil` / `contagio`) map helper for Alis.

Ported and adapted from diegoMalagrida/pocket-dots (`~/.local/bin/wallfx`):
- `contagio` (mode 0): 480x270 organic Dijkstra spread maps + smooth 16-bit glow maps,
  implemented in pure Python + Pillow (no numpy/opencv required for spread maps).
- `perfil` (mode 1): BiRefNet character silhouette cutout + signed distance field +
  dual-pen top-down contour stroke + roughened outward shockwave surface.
  Per user requirement, `wallfx` transitions and AI cutout baking apply **ONLY**
  to Favourite Wallpapers (`favourites.json`), never scanning all ~3,000 wallpapers.
"""
from __future__ import annotations

import hashlib
import heapq
import json
import math
import os
import random
import subprocess
import sys
from pathlib import Path

HOME = os.path.expanduser("~")
XDG_CACHE = os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache")
XDG_DATA = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")
XDG_STATE = os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state")

CACHE_DIR = os.environ.get("ALIS_WALLFX_CACHE_DIR") or os.path.join(XDG_CACHE, "alis", "wallfx")
VENV_DIR = os.environ.get("ALIS_WALLFX_VENV_DIR") or os.path.join(XDG_DATA, "alis", "wallfx-venv")
VENV_PY = os.path.join(VENV_DIR, "venv", "bin", "python")
DEFAULT_FAVOURITES = os.path.join(XDG_STATE, "quickshell", "user", "wallpaper-selector", "favourites.json")

GW, GH = 240, 135
POOL = 8
FIELD_MAX = 1280
SD_RANGE = 16.0
WIDE = 48.0
STATIC_EXTS = (".jpg", ".jpeg", ".png", ".webp", ".bmp")


def _ai_available() -> bool:
    if os.environ.get("ALIS_WALLFX_MOCK_MASK"):
        return True
    return os.path.isfile(VENV_PY) and os.access(VENV_PY, os.X_OK)


def _reexec_in_venv_if_needed() -> None:
    if os.environ.get("ALIS_WALLFX_MOCK_MASK"):
        return
    if os.path.abspath(sys.executable) != os.path.abspath(VENV_PY) and _ai_available():
        os.execv(VENV_PY, [VENV_PY, os.path.abspath(__file__), *sys.argv[1:]])


def _key_for_image(img_path: str) -> str:
    real = os.path.realpath(img_path)
    st = os.stat(real)
    raw = f"{real}|{st.st_size}|{int(st.st_mtime)}".encode("utf-8", errors="surrogateescape")
    return hashlib.sha1(raw).hexdigest()[:16]


def load_favourites(fav_path: str | None = None) -> dict[str, bool]:
    target = fav_path or DEFAULT_FAVOURITES
    try:
        with open(target, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(data, dict):
            return {str(k): bool(v) for k, v in data.items() if v}
    except (OSError, ValueError):
        pass
    return {}


def is_favourite_image(img_path: str, fav_db: dict[str, bool]) -> bool:
    if not img_path or not fav_db:
        return False
    clean = img_path[7:] if img_path.startswith("file://") else img_path
    real = os.path.realpath(clean) if os.path.exists(clean) else clean
    base = os.path.basename(clean)
    return bool(fav_db.get(clean) or fav_db.get(real) or fav_db.get(base))


# ───────────────────────────── pure-Python + PIL contagion ─────────────────────────────

def _value_noise_2d(rng: random.Random, w: int, h: int, scale: float) -> list[float]:
    nx = int(w / scale) + 3
    ny = int(h / scale) + 3
    lat = [rng.random() for _ in range(nx * ny)]

    x_idx = [0] * w
    x_frac = [0.0] * w
    for x in range(w):
        u = x / scale
        ix = int(u)
        f = u - ix
        x_idx[x] = ix
        x_frac[x] = f * f * (3.0 - 2.0 * f)

    out = [0.0] * (w * h)
    pos = 0
    for y in range(h):
        v = y / scale
        iy = int(v)
        fy = v - iy
        fy = fy * fy * (3.0 - 2.0 * fy)
        omy = 1.0 - fy
        row0 = iy * nx
        row1 = (iy + 1) * nx
        for x in range(w):
            ix = x_idx[x]
            fx = x_frac[x]
            omx = 1.0 - fx
            top = lat[row0 + ix] * omx + lat[row0 + ix + 1] * fx
            bot = lat[row1 + ix] * omx + lat[row1 + ix + 1] * fx
            out[pos] = top * omy + bot * fy
            pos += 1
    return out


def _dijkstra_arrival(cost: list[float], seeds: list[tuple[int, float]], w: int, h: int) -> list[float]:
    inf = float("inf")
    arrival = [inf] * (w * h)
    heap: list[tuple[float, int]] = []
    for idx, t0 in seeds:
        if 0 <= idx < w * h and t0 < arrival[idx]:
            arrival[idx] = t0
            heap.append((t0, idx))
    heapq.heapify(heap)
    steps = (
        (-1, 0, 1.0), (1, 0, 1.0), (0, -1, 1.0), (0, 1, 1.0),
        (-1, -1, 1.4142), (1, -1, 1.4142), (-1, 1, 1.4142), (1, 1, 1.4142),
    )
    heappop = heapq.heappop
    heappush = heapq.heappush
    while heap:
        t, i = heappop(heap)
        if t != arrival[i]:
            continue
        x = i % w
        y = i // w
        ci = cost[i]
        for dx, dy, dist in steps:
            nx = x + dx
            ny = y + dy
            if 0 <= nx < w and 0 <= ny < h:
                j = ny * w + nx
                cand = t + (ci + cost[j]) * 0.5 * dist
                if cand < arrival[j]:
                    arrival[j] = cand
                    heappush(heap, (cand, j))
    return arrival


def _write_contagion_pair(path: str, liso: str, seed: int) -> None:
    from PIL import Image, ImageFilter

    w, h = GW * 2, GH * 2  # 480 x 270
    rng = random.Random(seed)
    n1 = _value_noise_2d(rng, w, h, rng.uniform(18.0, 65.0))
    n2 = _value_noise_2d(rng, w, h, rng.uniform(7.0, 20.0))
    n3 = _value_noise_2d(rng, w, h, rng.uniform(2.0, 6.0))
    sharp = rng.uniform(5.0, 9.0)
    grain = rng.uniform(0.15, 0.65)
    exp = math.exp
    rand = rng.random
    total = w * h
    cost = [
        0.12 + exp(sharp * (0.52 * n1[i] + 0.30 * n2[i] + 0.18 * n3[i] - 0.5)) + grain * rand()
        for i in range(total)
    ]
    seeds: list[tuple[int, float]] = []
    max_delay = (total ** 0.5) * 0.12
    for _ in range(rng.randint(6, 12)):
        sx = int(rng.uniform(0.06, 0.94) * w)
        sy = int(rng.uniform(0.08, 0.92) * h)
        seeds.append((sy * w + sx, rng.uniform(0.0, max_delay)))

    arrival = _dijkstra_arrival(cost, seeds, w, h)
    order = sorted(range(total), key=arrival.__getitem__)
    ranked = [0] * total
    denom = max(1, total - 1)
    for rank_idx, cell_idx in enumerate(order):
        ranked[cell_idx] = int(rank_idx * 65535 // denom)

    # Map 1 (`path`): R = high byte, G = low byte, B = 0
    field_bytes = bytearray(total * 3)
    # Grayscale proxy for Gaussian blur -> smooth 16-bit surface (`liso`: G = high, B = low)
    hi_bytes = bytearray(total)
    lo_bytes = bytearray(total)
    p = 0
    for idx, q in enumerate(ranked):
        hi = (q >> 8) & 255
        lo = q & 255
        field_bytes[p] = hi
        field_bytes[p + 1] = lo
        hi_bytes[idx] = hi
        lo_bytes[idx] = lo
        p += 3

    os.makedirs(os.path.dirname(path), exist_ok=True)
    field_img = Image.frombytes("RGB", (w, h), bytes(field_bytes))

    # Upscale 16-bit scalar via two blurred 8-bit planes to preserve smooth 16-bit gradient
    hi_blur = Image.frombytes("L", (w, h), bytes(hi_bytes)).filter(ImageFilter.GaussianBlur(radius=2.5)).tobytes()
    lo_blur = Image.frombytes("L", (w, h), bytes(lo_bytes)).filter(ImageFilter.GaussianBlur(radius=2.5)).tobytes()
    liso_bytes = bytearray(total * 3)
    lp = 0
    for idx in range(total):
        val = min(65535, max(0, hi_blur[idx] * 256 + lo_blur[idx]))
        liso_bytes[lp + 1] = (val >> 8) & 255
        liso_bytes[lp + 2] = val & 255
        lp += 3
    liso_img = Image.frombytes("RGB", (w, h), bytes(liso_bytes))

    pid = os.getpid()
    for dest, im in ((path, field_img), (liso, liso_img)):
        tmp = f"{dest}.{pid}.tmp.png"
        im.save(tmp, format="PNG")
        os.replace(tmp, dest)


def ensure_one_spread(slot: int | None = None) -> tuple[str, str]:
    spread_dir = os.path.join(CACHE_DIR, "spread")
    os.makedirs(spread_dir, exist_ok=True)
    k = random.randrange(POOL) if slot is None else (slot % POOL)
    path = os.path.join(spread_dir, f"spread-{k}.png")
    liso = os.path.join(spread_dir, f"spread-{k}-liso.png")
    if not (os.path.isfile(path) and os.path.isfile(liso)):
        _write_contagion_pair(path, liso, random.randrange(1 << 30))
    return path, liso


def ensure_spread_pool(count: int = 3) -> list[tuple[str, str]]:
    out = []
    for k in range(min(POOL, max(1, count))):
        out.append(ensure_one_spread(k))
    return out


# ───────────────────────────── outline (`perfil`) baking ─────────────────────────────

_rembg_session = None


def _cutout_mask(im):
    global _rembg_session
    mock_mask = os.environ.get("ALIS_WALLFX_MOCK_MASK", "")
    if mock_mask and os.path.isfile(mock_mask):
        from PIL import Image
        return Image.open(mock_mask).convert("L").resize(im.size)

    os.environ.setdefault("U2NET_HOME", os.path.join(VENV_DIR, "models"))
    from rembg import new_session, remove

    if _rembg_session is None:
        ov_cache = os.path.join(CACHE_DIR, "ov")
        os.makedirs(ov_cache, exist_ok=True)
        try:
            _rembg_session = new_session(
                "birefnet-general-lite",
                providers=[
                    ("OpenVINOExecutionProvider", {"device_type": "GPU", "cache_dir": ov_cache}),
                    "CPUExecutionProvider",
                ],
            )
        except Exception:
            _rembg_session = new_session("birefnet-general-lite", providers=["CPUExecutionProvider"])
    return remove(im, session=_rembg_session, only_mask=True)


def _bake_perfil_pure_or_cv2(img_path: str, force: bool = False) -> tuple[str, str] | None:
    if not os.path.isfile(img_path) or not img_path.lower().endswith(STATIC_EXTS):
        return None

    perfil_dir = os.path.join(CACHE_DIR, "perfil")
    os.makedirs(perfil_dir, exist_ok=True)
    key = _key_for_image(img_path)
    base = os.path.join(perfil_dir, key)
    meta_path = base + ".json"
    campo_path = base + "-campo.png"
    linea_path = base + "-linea.png"

    if not force and os.path.isfile(meta_path):
        try:
            meta = json.loads(Path(meta_path).read_text(encoding="utf-8"))
            if not meta.get("ok"):
                return None
            if os.path.isfile(campo_path) and os.path.isfile(linea_path):
                return campo_path, linea_path
        except Exception:
            pass

    import fcntl
    lock_fh = open(base + ".lock", "w", encoding="utf-8")
    fcntl.flock(lock_fh, fcntl.LOCK_EX)
    try:
        if not force and os.path.isfile(meta_path):
            try:
                meta = json.loads(Path(meta_path).read_text(encoding="utf-8"))
                if not meta.get("ok"):
                    return None
                if os.path.isfile(campo_path) and os.path.isfile(linea_path):
                    return campo_path, linea_path
            except Exception:
                pass

        from PIL import Image, ImageFilter

        im = Image.open(img_path).convert("RGB")
        im.thumbnail((FIELD_MAX, FIELD_MAX))
        mask_path = base + "-mascara.png"
        if os.path.isfile(mask_path) and not force:
            mask_img = Image.open(mask_path).convert("L")
        else:
            mask_img = _cutout_mask(im).convert("L")
            mask_img.save(mask_path)

        try:
            import cv2
            import numpy as np

            m = np.asarray(mask_img.resize(im.size), np.float32) / 255.0
            h, w = m.shape
            b = (m > 0.5).astype(np.uint8)
            n, lab, stats, _ = cv2.connectedComponentsWithStats(b, connectivity=8)
            keep = np.zeros(n, bool)
            keep[1:] = stats[1:, cv2.CC_STAT_AREA] >= 0.002 * w * h
            b = keep[lab].astype(np.uint8)
            cover = float(b.mean())
            unsure = float(((m > 0.1) & (m < 0.9)).mean())
            ok = 0.008 <= cover <= 0.72 and unsure <= 0.06
            meta = {"img": img_path, "ok": ok, "cover": round(cover, 3), "unsure": round(unsure, 3), "w": w, "h": h}
            if not ok:
                Path(meta_path).write_text(json.dumps(meta), encoding="utf-8")
                return None

            din = cv2.distanceTransform(b, cv2.DIST_L2, 5)
            dout = cv2.distanceTransform(1 - b, cv2.DIST_L2, 5)
            sd = dout - din
            inner = np.clip(din / max(float(np.percentile(din[b > 0], 99)), 1.0), 0, 1)

            rng = np.random.default_rng(int(key[:8], 16))
            nx1, ny1 = int(w / (w / 9.0)) + 3, int(h / (w / 9.0)) + 3
            # Value noise via numpy
            def _np_noise(scale: float):
                nx, ny = int(w / scale) + 3, int(h / scale) + 3
                lat = rng.random((ny, nx))
                xs = np.arange(w) / scale
                ys = np.arange(h) / scale
                ix, iy = xs.astype(int), ys.astype(int)
                fx, fy = xs - ix, ys - iy
                fx = fx * fx * (3 - 2 * fx)
                fy = fy * fy * (3 - 2 * fy)
                top = lat[iy][:, ix] * (1 - fx) + lat[iy][:, ix + 1] * fx
                bot = lat[iy + 1][:, ix] * (1 - fx) + lat[iy + 1][:, ix + 1] * fx
                return top * (1 - fy)[:, None] + bot * fy[:, None]

            noise = 0.6 * _np_noise(max(2.0, w / 9.0)) + 0.4 * _np_noise(max(2.0, w / 28.0))
            warped = dout * (0.75 + 0.5 * noise) + noise * 0.08 * max(w, h)
            outside = b == 0
            order = np.zeros((h, w), np.float32)
            vals = warped[outside]
            if vals.size > 0:
                r = np.empty(vals.size)
                r[np.argsort(vals, kind="stable")] = np.arange(vals.size)
                order[outside] = r / max(vals.size - 1, 1)

            edge = np.zeros((h, w), np.uint8)
            param_at = np.zeros((h, w), np.float32)
            contours, _ = cv2.findContours(b, cv2.RETR_LIST, cv2.CHAIN_APPROX_NONE)
            for c in contours:
                if len(c) < 40 or abs(cv2.contourArea(c)) < 0.0008 * w * h:
                    continue
                c = c[:, 0, :]
                seg = np.sqrt((np.diff(c, axis=0, append=c[:1]) ** 2).sum(1))
                s = np.concatenate([[0], np.cumsum(seg)[:-1]])
                L = s[-1] + seg[-1]
                s = (s - s[np.argmin(c[:, 1])]) % L
                p = np.minimum(s, L - s) / max(L / 2.0, 1e-4)
                p[(c[:, 0] <= 1) | (c[:, 0] >= w - 2) | (c[:, 1] <= 1) | (c[:, 1] >= h - 2)] = -1
                edge[c[:, 1], c[:, 0]] = 1
                param_at[c[:, 1], c[:, 0]] = p

            line = np.zeros((h, w), np.uint8)
            if edge.any():
                _, labels = cv2.distanceTransformWithLabels(1 - edge, cv2.DIST_L2, 5, labelType=cv2.DIST_LABEL_PIXEL)
                ys, xs = np.nonzero(edge)
                table = np.concatenate([[0], param_at[ys, xs]])
                near = np.abs(sd) < SD_RANGE
                v = table[labels[near]]
                line[near] = np.where(v < 0, 0, np.clip(v * 255, 1, 255)).astype(np.uint8)

            rgb = np.zeros((h, w, 3), np.uint8)
            rgb[..., 0] = np.clip(dout / WIDE * 255, 0, 255)
            rgb[..., 1] = np.clip(inner * 255, 0, 255)
            rgb[..., 2] = np.clip((sd + SD_RANGE) / (2 * SD_RANGE) * 255, 0, 255)

            smooth = cv2.GaussianBlur(order.astype(np.float32), (0, 0), 4.0)
            q = np.clip(smooth * 65535.0 + 0.5, 0, 65535).astype(np.uint16)
            linea = np.zeros((h, w, 3), np.uint8)
            linea[..., 0] = line
            linea[..., 1] = q >> 8
            linea[..., 2] = q & 255

            pid = os.getpid()
            for dest, arr in ((campo_path, rgb), (linea_path, linea)):
                tmp = f"{dest}.{pid}.tmp.png"
                Image.fromarray(arr, "RGB").save(tmp)
                os.replace(tmp, dest)
            Path(meta_path).write_text(json.dumps(meta), encoding="utf-8")
            return campo_path, linea_path
        except ImportError:
            # Pure-Pillow fallback when ALIS_WALLFX_MOCK_MASK is used in system python without cv2/numpy
            if not os.environ.get("ALIS_WALLFX_MOCK_MASK"):
                return None
            resized = mask_img.resize(im.size)
            w, h = resized.size
            raw_m = resized.tobytes()
            fg_count = sum(1 for px in raw_m if px > 127)
            cover = fg_count / max(1, w * h)
            ok = 0.008 <= cover <= 0.72
            meta = {"img": img_path, "ok": ok, "cover": round(cover, 3), "unsure": 0.0, "w": w, "h": h}
            if not ok:
                Path(meta_path).write_text(json.dumps(meta), encoding="utf-8")
                return None
            blurred = resized.filter(ImageFilter.GaussianBlur(radius=6.0)).tobytes()
            campo_bytes = bytearray(w * h * 3)
            linea_bytes = bytearray(w * h * 3)
            for idx in range(w * h):
                inside_v = raw_m[idx]
                blur_v = blurred[idx]
                sd_norm = int(max(0, min(255, 128 + (128 - blur_v))))
                campo_bytes[idx * 3] = 255 - blur_v
                campo_bytes[idx * 3 + 1] = inside_v
                campo_bytes[idx * 3 + 2] = sd_norm
                y_ratio = int(((idx // w) / max(1, h - 1)) * 254) + 1
                linea_bytes[idx * 3] = y_ratio if 24 < blur_v < 232 else 0
                out_q = int(((255 - blur_v) / 255.0) * 65535)
                linea_bytes[idx * 3 + 1] = (out_q >> 8) & 255
                linea_bytes[idx * 3 + 2] = out_q & 255
            Image.frombytes("RGB", (w, h), bytes(campo_bytes)).save(campo_path)
            Image.frombytes("RGB", (w, h), bytes(linea_bytes)).save(linea_path)
            Path(meta_path).write_text(json.dumps(meta), encoding="utf-8")
            return campo_path, linea_path
    finally:
        lock_fh.close()


def _spawn_background_bake(img_path: str) -> None:
    if not _ai_available() or os.environ.get("ALIS_WALLFX_NO_BG_SPAWN") == "1":
        return
    py = VENV_PY if os.path.isfile(VENV_PY) else sys.executable
    try:
        subprocess.Popen(
            ["/usr/bin/nice", "-n", "19", py, os.path.abspath(__file__), "bake", img_path],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        pass


def resolve_for_wallpaper(img_path: str, fav_override: bool | None = None, fav_file: str | None = None) -> dict:
    clean = img_path[7:] if img_path.startswith("file://") else img_path
    if not clean or not os.path.isfile(clean) or not clean.lower().endswith(STATIC_EXTS):
        return {"eligible": False, "reason": "unsupported"}

    if fav_override is None:
        fav_db = load_favourites(fav_file)
        is_fav = is_favourite_image(clean, fav_db)
    else:
        is_fav = fav_override

    if not is_fav:
        return {"eligible": False, "reason": "not_favourite"}

    perfil_dir = os.path.join(CACHE_DIR, "perfil")
    key = _key_for_image(clean)
    base = os.path.join(perfil_dir, key)
    meta_path = base + ".json"
    campo_path = base + "-campo.png"
    linea_path = base + "-linea.png"

    meta = None
    if os.path.isfile(meta_path):
        try:
            meta = json.loads(Path(meta_path).read_text(encoding="utf-8"))
        except Exception:
            meta = None

    if meta is not None and meta.get("ok") and os.path.isfile(campo_path) and os.path.isfile(linea_path):
        return {
            "eligible": True,
            "mode": "perfil",
            "modeId": 1,
            "field": campo_path,
            "line": linea_path,
            "glow": 1.0,
            "lineW": 2.2,
            "sdRange": SD_RANGE,
            "baked": True,
        }

    needs_bake = meta is None and _ai_available()
    if needs_bake:
        _spawn_background_bake(clean)

    spread_field, spread_line = ensure_one_spread()
    return {
        "eligible": True,
        "mode": "contagio",
        "modeId": 0,
        "field": spread_field,
        "line": spread_line,
        "glow": 1.0,
        "lineW": 2.2,
        "sdRange": SD_RANGE,
        "baked": meta is not None,
        "bakingQueued": needs_bake,
    }


def bake_favourites_only(fav_file: str | None = None, wallpapers_root: str | None = None) -> dict:
    fav_db = load_favourites(fav_file)
    candidates: list[str] = []
    seen: set[str] = set()

    for key in fav_db:
        if os.path.isabs(key) and os.path.isfile(key) and key.lower().endswith(STATIC_EXTS):
            real = os.path.realpath(key)
            if real not in seen:
                seen.add(real)
                candidates.append(real)

    # Resolve legacy basename-only favourite entries inside wallpapers_root if provided
    unresolved_basenames = {
        k for k in fav_db if not os.path.isabs(k) and k.lower().endswith(STATIC_EXTS)
    }
    if unresolved_basenames and wallpapers_root and os.path.isdir(wallpapers_root):
        for dirpath, _, filenames in os.walk(wallpapers_root):
            for fn in filenames:
                if fn in unresolved_basenames:
                    full = os.path.realpath(os.path.join(dirpath, fn))
                    if full not in seen:
                        seen.add(full)
                        candidates.append(full)

    ensure_spread_pool(3)
    baked_ok = 0
    baked_contagio = 0
    for path in candidates:
        res = _bake_perfil_pure_or_cv2(path)
        if res:
            baked_ok += 1
        else:
            baked_contagio += 1

    return {
        "favouritesTotal": len(candidates),
        "perfilReady": baked_ok,
        "contagioFallback": baked_contagio,
        "aiAvailable": _ai_available(),
    }


def get_status() -> dict:
    spread_dir = os.path.join(CACHE_DIR, "spread")
    perfil_dir = os.path.join(CACHE_DIR, "perfil")
    spread_count = 0
    if os.path.isdir(spread_dir):
        spread_count = sum(
            1 for k in range(POOL)
            if os.path.isfile(os.path.join(spread_dir, f"spread-{k}.png"))
            and os.path.isfile(os.path.join(spread_dir, f"spread-{k}-liso.png"))
        )
    perfil_count = 0
    if os.path.isdir(perfil_dir):
        for fn in os.listdir(perfil_dir):
            if fn.endswith("-campo.png"):
                perfil_count += 1
    return {
        "aiAvailable": _ai_available(),
        "venvPython": VENV_PY,
        "cacheDir": CACHE_DIR,
        "spreadReady": spread_count,
        "perfilCached": perfil_count,
    }


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd = argv[0]
    rest = argv[1:]
    if cmd == "status":
        print(json.dumps(get_status()))
        return 0
    if cmd == "ensure-spread":
        cnt = int(rest[0]) if rest else 4
        pairs = ensure_spread_pool(cnt)
        print(json.dumps({"ok": True, "count": len(pairs), "first": pairs[0] if pairs else []}))
        return 0
    if cmd == "resolve":
        if not rest:
            print(json.dumps({"eligible": False, "reason": "missing_path"}))
            return 1
        img = rest[0]
        fav_override = None
        fav_file = None
        i = 1
        while i < len(rest):
            if rest[i] == "--favourite" and i + 1 < len(rest):
                fav_override = rest[i + 1] in ("1", "true", "yes")
                i += 2
            elif rest[i] == "--favourites-file" and i + 1 < len(rest):
                fav_file = rest[i + 1]
                i += 2
            else:
                i += 1
        print(json.dumps(resolve_for_wallpaper(img, fav_override=fav_override, fav_file=fav_file)))
        return 0
    if cmd == "bake":
        if not rest:
            return 1
        _reexec_in_venv_if_needed()
        res = _bake_perfil_pure_or_cv2(rest[0], force="--force" in rest)
        print(json.dumps({"ok": bool(res), "paths": list(res) if res else []}))
        return 0 if res else 1
    if cmd == "bake-favourites":
        _reexec_in_venv_if_needed()
        fav_file = rest[0] if len(rest) >= 1 and rest[0] else None
        wall_root = rest[1] if len(rest) >= 2 and rest[1] else None
        print(json.dumps(bake_favourites_only(fav_file=fav_file, wallpapers_root=wall_root)))
        return 0
    print(json.dumps({"error": f"unknown command: {cmd}"}), file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
