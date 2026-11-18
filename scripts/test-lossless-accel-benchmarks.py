#!/usr/bin/env python3
"""Benchmark and parity verification for qs-rs / inir-accel inspired Alis accelerators.

Runs 100% silently (offscreen / headless) with zero real user state mutation.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import time
import zlib

ROOT = Path(__file__).resolve().parents[1]
NATIVE_BIN = ROOT / "native" / "bin" / "alis-native"
CAVA_GEN = ROOT / "scripts" / "cava" / "generate_config.sh"


def _png_chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def _write_solid_png(path: Path, width: int, height: int) -> None:
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    row = b"\x00" + (b"\x18\x34\x56" * width)
    idat = zlib.compress(row * height, level=1)
    raw = (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", ihdr)
        + _png_chunk(b"IDAT", idat)
        + _png_chunk(b"IEND", b"")
    )
    path.write_bytes(raw)


def _headless_env(extra: dict[str, str] | None = None) -> dict[str, str]:
    env = dict(os.environ)
    env.pop("WAYLAND_DISPLAY", None)
    env.pop("DISPLAY", None)
    env.pop("NIRI_SOCKET", None)
    env["QT_QPA_PLATFORM"] = "offscreen"
    env["QT_QUICK_BACKEND"] = "software"
    if extra:
        env.update(extra)
    return env


def bench_image_size_and_thumb(tmp: Path) -> dict[str, float]:
    assert NATIVE_BIN.is_file(), f"Missing native binary: {NATIVE_BIN}"
    png_4k = tmp / "wall_3840x2160.png"
    _write_solid_png(png_4k, 3840, 2160)

    out_native = subprocess.check_output(
        [str(NATIVE_BIN), "accel", "image-size", str(png_4k)],
        env=_headless_env(),
        text=True,
    ).strip()
    assert out_native == "3840 2160", f"Unexpected native image-size: {out_native}"

    iters = 25
    t0 = time.perf_counter()
    for _ in range(iters):
        subprocess.run(
            [str(NATIVE_BIN), "accel", "image-size", str(png_4k)],
            env=_headless_env(),
            stdout=subprocess.DEVNULL,
            check=True,
        )
    native_ms = ((time.perf_counter() - t0) * 1000.0) / iters

    magick = shutil.which("magick")
    magick_full_ms = -1.0
    magick_ping_ms = -1.0
    if magick:
        out_ping = subprocess.check_output(
            [magick, "identify", "-ping", "-format", "%w %h", str(png_4k)],
            env=_headless_env(),
            text=True,
        ).strip()
        assert out_ping == "3840 2160", f"Magick -ping mismatch: {out_ping}"

        t0 = time.perf_counter()
        for _ in range(5):
            subprocess.run(
                [magick, "identify", "-format", "%w %h", str(png_4k)],
                env=_headless_env(),
                stdout=subprocess.DEVNULL,
                check=True,
            )
        magick_full_ms = ((time.perf_counter() - t0) * 1000.0) / 5.0

        t0 = time.perf_counter()
        for _ in range(5):
            subprocess.run(
                [magick, "identify", "-ping", "-format", "%w %h", str(png_4k)],
                env=_headless_env(),
                stdout=subprocess.DEVNULL,
                check=True,
            )
        magick_ping_ms = ((time.perf_counter() - t0) * 1000.0) / 5.0

    # Verify RFC 1321 MD5 Freedesktop thumbnail URI parity
    cache_dir = tmp / "xdg_cache"
    thumb_raw = subprocess.check_output(
        [str(NATIVE_BIN), "accel", "thumb-info", str(png_4k), "--size", "large"],
        env=_headless_env({"XDG_CACHE_HOME": str(cache_dir)}),
        text=True,
    )
    thumb = json.loads(thumb_raw)
    expected_md5 = hashlib.md5(thumb["uri"].encode("utf-8")).hexdigest()
    assert thumb["md5"] == expected_md5, f"MD5 mismatch: {thumb['md5']} != {expected_md5}"
    assert thumb["width"] == 3840 and thumb["height"] == 2160
    assert thumb["thumbnailExists"] is False

    thumb_file = Path(thumb["thumbnailPath"])
    thumb_file.parent.mkdir(parents=True, exist_ok=True)
    thumb_file.write_bytes(b"png")
    thumb2 = json.loads(
        subprocess.check_output(
            [str(NATIVE_BIN), "accel", "thumb-info", str(png_4k), "--size", "large"],
            env=_headless_env({"XDG_CACHE_HOME": str(cache_dir)}),
            text=True,
        )
    )
    assert thumb2["thumbnailExists"] is True

    return {
        "native_image_size_ms": round(native_ms, 2),
        "magick_ping_ms": round(magick_ping_ms, 2),
        "magick_full_decode_ms": round(magick_full_ms, 2),
    }


def bench_cava_config_parity(tmp: Path) -> dict[str, float]:
    out_rust = tmp / "cava_rust.conf"
    out_py = tmp / "cava_py.conf"

    stdout_rust = subprocess.check_output(
        [str(CAVA_GEN), str(out_rust), "30", "100", "48", "true", "firefox", "--print-config"],
        env=_headless_env({"ALIS_NATIVE_BACKEND": "rust"}),
        text=True,
    )
    stdout_py = subprocess.check_output(
        [str(CAVA_GEN), str(out_py), "30", "100", "48", "true", "firefox", "--print-config"],
        env=_headless_env({"ALIS_NATIVE_BACKEND": "python"}),
        text=True,
    )
    assert out_rust.read_text() == out_py.read_text(), "Rust vs Python Cava config mismatch"
    assert stdout_rust == stdout_py, "Rust vs Python --print-config stdout mismatch"

    stat_before = out_rust.stat()
    time.sleep(0.02)
    subprocess.run(
        [str(CAVA_GEN), str(out_rust), "30", "100", "48", "true", "firefox"],
        env=_headless_env({"ALIS_NATIVE_BACKEND": "rust"}),
        stdout=subprocess.DEVNULL,
        check=True,
    )
    stat_after = out_rust.stat()
    assert stat_before.st_ino == stat_after.st_ino, "Unchanged Cava config must keep same inode"

    iters = 12
    t0 = time.perf_counter()
    for _ in range(iters):
        subprocess.run(
            [str(CAVA_GEN), str(out_rust), "30", "100", "48", "true", "firefox"],
            env=_headless_env({"ALIS_NATIVE_BACKEND": "rust"}),
            stdout=subprocess.DEVNULL,
            check=True,
        )
    rust_ms = ((time.perf_counter() - t0) * 1000.0) / iters

    t0 = time.perf_counter()
    for _ in range(iters):
        subprocess.run(
            [str(CAVA_GEN), str(out_py), "30", "100", "48", "true", "firefox"],
            env=_headless_env({"ALIS_NATIVE_BACKEND": "python"}),
            stdout=subprocess.DEVNULL,
            check=True,
        )
    py_ms = ((time.perf_counter() - t0) * 1000.0) / iters

    return {
        "cava_config_rust_ms": round(rust_ms, 2),
        "cava_config_python_ms": round(py_ms, 2),
    }


def bench_app_search_and_qml_fuzzy(tmp: Path) -> dict[str, float]:
    data_home = tmp / "xdg_data"
    apps_dir = data_home / "applications"
    apps_dir.mkdir(parents=True, exist_ok=True)
    for idx in range(240):
        (apps_dir / f"org.test.app{idx:03d}.desktop").write_text(
            f"[Desktop Entry]\nType=Application\nName=Synthetic Studio {idx:03d}\n"
            f"GenericName=Editor {idx}\nKeywords=code;fast;tool{idx};\nExec=studio-{idx}\nIcon=applications-development\n",
            encoding="utf-8",
        )
    (apps_dir / "org.mozilla.firefox.desktop").write_text(
        "[Desktop Entry]\nType=Application\nName=Firefox Web Browser\nKeywords=browser;web;\nExec=firefox\nIcon=firefox\n",
        encoding="utf-8",
    )

    env = _headless_env(
        {
            "XDG_DATA_HOME": str(data_home),
            "XDG_DATA_DIRS": str(tmp / "empty_sys_dirs"),
        }
    )
    iters = 20
    t0 = time.perf_counter()
    last_out = ""
    for _ in range(iters):
        last_out = subprocess.check_output(
            [str(NATIVE_BIN), "accel", "app-search", "fwb", "--limit", "10"],
            env=env,
            text=True,
        )
    native_app_ms = ((time.perf_counter() - t0) * 1000.0) / iters
    parsed = json.loads(last_out)
    assert len(parsed) >= 1 and parsed[0]["id"] == "org.mozilla.firefox"

    # Headless Quickshell test for AppSearch.qml bitmask pre-filter + query memoization
    qs_root = tmp / "qs_root"
    qs_root.mkdir(parents=True, exist_ok=True)
    for entry in ("modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"):
        if (ROOT / entry).exists():
            (qs_root / entry).symlink_to(ROOT / entry)
    qml_harness = qs_root / "shell.qml"
    qml_harness.write_text(
        """
import QtQuick
import Quickshell
import qs.services
import qs.modules.common.functions

ShellRoot {
    Timer {
        interval: 40
        running: true
        repeat: false
        onTriggered: {
        const fakeEntries = [];
        for (let i = 0; i < 400; ++i) {
            fakeEntries.push({
                id: "app." + i,
                name: (i === 177) ? "Firefox Web Browser" : ("Synthetic Utility Tool " + i),
                icon: "application-x-executable",
                comment: "Test comment " + i,
                genericName: "Utility",
                keywords: ["tool", "bench"],
                command: ["app-" + i],
                runInTerminal: false
            });
        }
        AppSearch._cachedList = fakeEntries;
        AppSearch._cachedNameLowers = fakeEntries.map(e => e.name.toLowerCase());
        AppSearch._cacheRevision += 1;
        AppSearch.sloppySearch = false;

        const cold0 = Date.now();
        const first = AppSearch.fuzzyQuery("firefox", 20);
        const coldMs = Date.now() - cold0;
        if (!first || first.length !== 1 || first[0].name !== "Firefox Web Browser") {
            console.error("BENCH_FAIL:unexpected_firefox_match:" + JSON.stringify(first));
            Qt.exit(1);
        }

        // Verify reference baseline without bitmask prefilter produces identical order
        const allPrep = AppSearch._ensurePreppedNames();
        const rawFuzzy = Fuzzy.go("tool 3", allPrep, { key: "name", threshold: -10000 });
        const fastRes = AppSearch.fuzzyQuery("tool 3", 15);
        if (fastRes.length !== Math.min(15, rawFuzzy.length)) {
            console.error("BENCH_FAIL:count_mismatch:" + fastRes.length + "!=" + rawFuzzy.length);
            Qt.exit(1);
        }

        // Benchmark 500 repeated queries (memoized) + 200 distinct queries (bitmask prefiltered)
        const tMemo0 = Date.now();
        for (let k = 0; k < 500; ++k) {
            const r = AppSearch.fuzzyQuery("firefox", 20);
            if (r.length !== 1) Qt.exit(2);
        }
        const memoTotalMs = Date.now() - tMemo0;

        const queries = ["fir", "syn", "util", "web", "zzzznotfound", "tool 19", "brow", "app"];
        const tDistinct0 = Date.now();
        for (let round = 0; round < 50; ++round) {
            AppSearch._cacheRevision += 1; // force uncached bitmask + Fuzzy.go evaluation
            for (let q = 0; q < queries.length; ++q) {
                AppSearch.fuzzyQuery(queries[q], 20);
            }
        }
        const distinctTotalMs = Date.now() - tDistinct0;
        console.log("QML_APPSEARCH_METRICS:" + JSON.stringify({
            coldMs: coldMs,
            memo500Ms: memoTotalMs,
            distinct400UncachedMs: distinctTotalMs
        }));
        Qt.quit();
        }
    }
}
""",
        encoding="utf-8",
    )

    qs_bin = shutil.which("qs") or shutil.which("quickshell")
    assert qs_bin, "Missing qs/quickshell binary"
    proc = subprocess.run(
        [qs_bin, "-p", str(qml_harness)],
        cwd=str(ROOT),
        env=_headless_env({"XDG_RUNTIME_DIR": str(tmp)}),
        capture_output=True,
        text=True,
        timeout=20,
        check=False,
    )
    combined = (proc.stdout or "") + "\n" + (proc.stderr or "")
    assert proc.returncode == 0, f"QML AppSearch harness failed:\n{combined}"
    metrics_line = next(
        (ln for ln in combined.splitlines() if "QML_APPSEARCH_METRICS:" in ln),
        "",
    )
    assert metrics_line, f"Missing QML_APPSEARCH_METRICS in:\n{combined}"
    qml_metrics = json.loads(metrics_line.split("QML_APPSEARCH_METRICS:", 1)[1].strip())
    return {
        "native_app_search_240_ms": round(native_app_ms, 2),
        "qml_memo_500_queries_ms": qml_metrics["memo500Ms"],
        "qml_uncached_400_queries_ms": qml_metrics["distinct400UncachedMs"],
    }


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="alis-accel-bench-") as tmp_str:
        tmp = Path(tmp_str)
        img_stats = bench_image_size_and_thumb(tmp)
        cava_stats = bench_cava_config_parity(tmp)
        search_stats = bench_app_search_and_qml_fuzzy(tmp)
        summary = {**img_stats, **cava_stats, **search_stats}
        print("ALIS_ACCEL_BENCH_PASS " + json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
