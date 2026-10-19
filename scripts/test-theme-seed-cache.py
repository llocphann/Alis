#!/usr/bin/env python3
"""THEME-PERF-06: isolated Rust seed cache integration and parity.

Creates tiny BMP wallpaper fixtures and a private XDG cache; never reads
owner wallpaper/config or changes theme, Quickshell, GTK, or SDDM.
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile

if len(sys.argv) != 2:
    raise SystemExit("usage: python3 scripts/test-theme-seed-cache.py /path/to/alis-theme")
BINARY = Path(sys.argv[1]).resolve()
if not BINARY.is_file():
    raise SystemExit("Rust alis-theme binary not found")
TEST_COUNT = 0


def assert_ok(value, message):
    if not value:
        raise AssertionError(message)


def bmp(path: Path, color: tuple[int, int, int]) -> None:
    # Standard-library-only, uncompressed 32x32 RGB BMP.
    width, height = 32, 32
    row_stride = width * 3
    pixels = bytearray()
    for y in range(height):
        for x in range(width):
            pixels.extend((color[2] ^ (x & 0x0f),
                           color[1] ^ (y & 0x0f), color[0]))
    image_size = len(pixels)
    header = (b"BM" + struct.pack("<IHHI", 54 + image_size, 0, 0, 54)
              + struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24,
                            0, image_size, 2835, 2835, 0, 0))
    path.write_bytes(header + pixels)


def run(binary: Path, image: Path, temp: Path, name: str,
        env: dict, *, mode="dark", scheme="auto",
        size=128, flags=(), color=None, legacy_cache=False):
    global TEST_COUNT
    TEST_COUNT += 1
    dest = temp / name
    dest.mkdir(parents=True, exist_ok=True)
    argv = [
        str(binary), "--mode", mode, "--scheme", scheme,
        "--size", str(size),
        *(["--color", color] if color else ["--path", str(image)]),
        *flags,
    ]
    values = {}
    for opt in ("json", "palette", "app-palette", "terminal", "meta", "scss"):
        extension = "scss" if opt == "scss" else "json"
        file = dest / (opt + "." + extension)
        argv.extend(("--" + opt + "-output", str(file)))
        values[opt] = file
    if legacy_cache:
        argv.extend(("--cache", str(temp / "legacy-color.txt")))
    command = subprocess.run(argv, cwd=temp, env=env, text=True,
                             capture_output=True, timeout=45)
    assert_ok(command.returncode == 0,
              "Rust cache integration generation failed; rc="
              + str(command.returncode) + " stderr="
              + command.stderr[-500:].replace(str(image), "<fixture>"))
    result = {}
    for key, file in values.items():
        assert_ok(file.is_file() and file.stat().st_size > 0,
                  "Output absent: " + key)
        result[key] = file.read_text() if key == "scss" else json.loads(file.read_text())
    return result, command.stderr


def same_output(a: dict, b: dict) -> bool:
    return all(a[key] == b[key] for key in
               ("json", "palette", "app-palette", "terminal", "scss", "meta"))


with tempfile.TemporaryDirectory(prefix="alis-theme-seed-cache-") as name:
    root = Path(name)
    image = root / "wallpaper.bmp"
    cache_dir = root / "private-cache"
    env = dict(os.environ)
    env.update({
        "HOME": str(root / "home"),
        "XDG_CACHE_HOME": str(cache_dir),
        "XDG_STATE_HOME": str(root / "state"),
        "XDG_CONFIG_HOME": str(root / "config"),
        "ALIS_THEME_PROFILE": "1",
        "ALIS_THEME_SKIP_SDDM_SYNC": "1",
    })
    bmp(image, (45, 112, 192))

    first, first_log = run(BINARY, image, root, "cold", env, legacy_cache=True)
    assert_ok("stage=seed_cache_miss" in first_log, "Cold request must miss cache")
    legacy = root / "legacy-color.txt"
    assert_ok(legacy.read_text() == first["meta"]["seed_color"],
              "Existing --cache color.txt contract must be preserved")
    cache_files = list(cache_dir.glob("alis/theme-seeds/v1-*.json"))
    assert_ok(len(cache_files) == 1, "Expected one content-addressed cache file")
    entry_128 = cache_files[0]
    assert_ok(str(image) not in cache_files[0].read_text(),
              "Cache must not store source image paths")

    warm, warm_log = run(BINARY, image, root, "warm", env)
    assert_ok("stage=seed_cache_hit" in warm_log, "Repeated wallpaper must hit cache")
    assert_ok(same_output(first, warm), "Cached palette/meta differs from cold generation")

    # Distinct output-affecting options must retain bit-for-bit parity.
    for i, (mode, scheme, flags) in enumerate((
        ("light", "auto", ()),
        ("dark", "auto", ("--invert-hue",)),
        ("dark", "auto", ("--soften",)),
        ("dark", "auto", ("--color-strength", "0.75")),
        ("dark", "auto", ("--smart",)),
        ("dark", "scheme-vibrant", ()),
    )):
        cached, cached_log = run(
            BINARY, image, root, f"cached-{i}", env,
            mode=mode, scheme=scheme, flags=flags,
        )
        bypass_env = dict(env, ALIS_THEME_SEED_CACHE="0")
        direct, direct_log = run(
            BINARY, image, root, f"direct-{i}", bypass_env,
            mode=mode, scheme=scheme, flags=flags,
        )
        assert_ok("stage=seed_cache_hit" in cached_log,
                  f"Cache not reused under {mode}/{scheme}/{flags}")
        assert_ok("stage=seed_cache_hit" not in direct_log,
                  "Explicit opt-out must bypass cache")
        assert_ok(same_output(cached, direct),
                  f"Parity mismatch under {mode}/{scheme}/{flags}")

    other_size, other_log = run(BINARY, image, root, "size-96", env, size=96)
    assert_ok("stage=seed_cache_miss" in other_log,
              "Different sample size must invalidate cache")
    assert_ok(len(list(cache_dir.glob("alis/theme-seeds/v1-*.json"))) == 2,
              "Different sizes must occupy separate cache entries")
    entry_96 = next(
        path for path in cache_dir.glob("alis/theme-seeds/v1-*.json")
        if path != entry_128
    )

    # Corrupt both entries in turn: malformed cache must fall back to decode,
    # replace itself atomically and become reusable on the next call.
    for size, entry, baseline in (
        (128, entry_128, first),
        (96, entry_96, other_size),
    ):
        entry.write_text("{invalid json")
        recovered, regen_log = run(
            BINARY, image, root, f"corruption-{size}", env, size=size
        )
        assert_ok("stage=seed_cache_miss" in regen_log,
                  f"Corrupt cache at size={size} must miss")
        assert_ok(same_output(baseline, recovered),
                  f"Corrupt cache fallback changed output at size={size}")
        _, hit_log = run(
            BINARY, image, root, f"corruption-reuse-{size}", env, size=size
        )
        assert_ok("stage=seed_cache_hit" in hit_log,
                  f"Corrupt cache did not recover at size={size}")

    # Byte-accurate invalidation even if file size and mtime were preserved.
    stat = image.stat()
    bmp(image, (187, 77, 51))
    os.utime(image, ns=(stat.st_atime_ns, stat.st_mtime_ns))
    changed, changed_log = run(BINARY, image, root, "replaced", env)
    assert_ok("stage=seed_cache_miss" in changed_log,
              "Replacing same pathname/mtime/size must invalidate cache")
    assert_ok(first["meta"]["seed_color"] != changed["meta"]["seed_color"],
              "Fixture replacement must produce a different seed")

    # Concurrent cold writers must publish valid atomic entries; no temp leaks.
    shutil.rmtree(cache_dir)
    with ThreadPoolExecutor(max_workers=4) as pool:
        calls = [
            pool.submit(run, BINARY, image, root, f"concurrent-{i}", env)
            for i in range(4)
        ]
        concurrent = [call.result(timeout=60) for call in calls]
    assert_ok(all(same_output(concurrent[0][0], item[0]) for item in concurrent),
              "Concurrent generation returned inconsistent palettes")
    assert_ok(len(list(cache_dir.glob("alis/theme-seeds/v1-*.json"))) == 1,
              "Concurrent writers should converge to one atomic entry")
    assert_ok(not list(cache_dir.glob("alis/theme-seeds/*.tmp")),
              "Concurrent cache writes leaked temporary files")

    # Bounded cache: 72 content changes at the same path -> <=64 entries.
    for index in range(72):
        bmp(image, (index * 3 % 256, (index + 91) % 256, 128))
        run(BINARY, image, root, f"evict-{index}", env)
    assert_ok(len(list(cache_dir.glob("alis/theme-seeds/v1-*.json"))) <= 64,
              "Cache exceeded 64-entry bound")
    assert_ok(not list(cache_dir.glob("alis/theme-seeds/*.tmp")),
              "Cache eviction leaked temporary files")

print(
    "THEME_PERF_06_PASS content hashing, mode/variant parity, corruption recovery, "
    f"atomic concurrency, 64-entry pruning, legacy seed contract ({TEST_COUNT} runs)"
)
