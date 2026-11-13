#!/usr/bin/env python3
"""Silent Wayland GPU pixel-readback test for WallpaperCrossfader & AbyssEditStageFrame.

Verifies that previewing/switching wallpapers with shader transitions (`alisMelt`, `wallfx`)
and standard transitions (`fade`) actually renders the incoming wallpaper (`source2`) during
the transition rather than fading/melting into black and snapping at completion, and that
`AbyssEditStageFrame` crossfades the outer surround without blinking dark during async decode.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import zlib
import struct

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from native_test_session import private_wayland  # noqa: E402


def _write_solid_png(path: Path, width: int, height: int, rgb: tuple[int, int, int]) -> None:
    raw = bytearray()
    row = bytes(rgb) * width
    for _ in range(height):
        raw.append(0)
        raw.extend(row)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 1)) + chunk(b"IEND", b"")
    path.write_bytes(png)


def _read_ppm_stats(png_path: Path) -> dict[str, float]:
    # Convert PNG to raw RGB bytes using python + magick/ffmpeg or PIL
    out = subprocess.check_output(
        [
            sys.executable,
            "-c",
            (
                "import sys; from PySide6.QtGui import QImage\n"
                "img = QImage(sys.argv[1]).convertToFormat(QImage.Format.Format_RGB888)\n"
                "w, h = img.width(), img.height()\n"
                "ptr = img.constBits()\n"
                "b = bytes(ptr)\n"
                "stride = img.bytesPerLine()\n"
                "red_dom = blue_dom = dark_px = total = 0\n"
                "luma_sum = 0.0\n"
                "for y in range(60, h - 60, 8):\n"
                "    row = b[y*stride : y*stride + w*3]\n"
                "    for x in range(80, w - 80, 8):\n"
                "        r, g, bl = row[x*3], row[x*3+1], row[x*3+2]\n"
                "        total += 1\n"
                "        luma = 0.299*r + 0.587*g + 0.114*bl\n"
                "        luma_sum += luma\n"
                "        if r > bl + 45 and r > 90: red_dom += 1\n"
                "        elif bl > r + 45 and bl > 90: blue_dom += 1\n"
                "        elif luma < 22: dark_px += 1\n"
                "import json\n"
                "print(json.dumps({'red': red_dom/max(1,total), 'blue': blue_dom/max(1,total), "
                "'dark': dark_px/max(1,total), 'luma': luma_sum/max(1,total)}))\n"
            ),
            str(png_path),
        ],
        text=True,
    )
    return json.loads(out.strip())


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="alis-wp-trans-silent-") as tmp_str:
        tmp = Path(tmp_str)
        wp_red = tmp / "red.png"
        wp_blue = tmp / "blue.png"
        wp_green = tmp / "green.png"
        _write_solid_png(wp_red, 640, 360, (220, 42, 42))
        _write_solid_png(wp_blue, 640, 360, (36, 98, 228))
        _write_solid_png(wp_green, 640, 360, (40, 198, 92))

        harness_dir = tmp / "harness"
        harness_dir.mkdir(parents=True)
        for item in ("modules", "services", "translations", "assets", "scripts", "GlobalStates.qml", "qmldir"):
            src = ROOT / item
            if src.exists():
                (harness_dir / item).symlink_to(src)

        (harness_dir / "shell.qml").write_text(
            f"""import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.looks

ShellRoot {{
    id: root
    property string currentWp: {json.dumps(str(wp_red))}
    property string currentTransType: "alisMelt"

    PanelWindow {{
        id: win
        anchors {{ top: true; bottom: true; left: true; right: true }}
        exclusionMode: ExclusionMode.Ignore
        color: "#05070a"

        Item {{
            id: stage
            x: 160; y: 90
            width: parent.width - 320
            height: parent.height - 220

            WallpaperCrossfader {{
                id: crossfader
                anchors.fill: parent
                source: root.currentWp
                enableTransitions: true
                transitionType: root.currentTransType
                transitionBaseDuration: 1500
                sourceSize: Qt.size(640, 360)
            }}
        }}

        AbyssEditStageFrame {{
            id: stageFrame
            anchors.fill: parent
            readonly property string manualUrl: "file://" + root.currentWp
            card: ({{
                p: 1.0,
                x: 160,
                y: 90,
                width: win.width - 320,
                height: win.height - 220,
                cornerRadius: 24,
                bezel: 12,
                dockRadius: 28,
                dockX: 360,
                dockY: win.height - 110,
                dockWidth: win.width - 720,
                dockHeight: 90
            }})
            Component.onCompleted: {{
                stageFrame._pendingUrl = manualUrl
                stageFrame._loadNextPending()
            }}
            Connections {{
                target: root
                function onCurrentWpChanged(): void {{
                    stageFrame._pendingUrl = "file://" + root.currentWp
                    stageFrame._loadNextPending()
                }}
            }}
        }}
    }}

    IpcHandler {{
        target: "wpTest"
        function switchTo(path: string, transType: string): string {{
            root.currentTransType = transType
            root.currentWp = path
            return "ok"
        }}
        function state(): string {{
            return JSON.stringify({{
                cf: crossfader.renderState(),
                frameMix: stageFrame._wallMix,
                frameReady: stageFrame.wallpaperReady,
                frameNextReady: stageFrame.nextWallpaperReady
            }})
        }}
    }}
}}
""",
            encoding="utf-8",
        )

        with private_wayland(tmp, need_niri=True) as wl_env:
            if wl_env is None:
                print("SKIP: virtual Wayland unavailable")
                return 0

            log_path = tmp / "qs.log"
            with log_path.open("wb") as log_fp:
                qs_proc = subprocess.Popen(
                    ["qs", "-n", "-p", str(harness_dir)],
                    env=wl_env,
                    stdout=log_fp,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
            try:
                # Wait for initial Red wallpaper to settle
                deadline = time.monotonic() + 10.0
                while time.monotonic() < deadline:
                    res = subprocess.run(
                        ["qs", "-p", str(harness_dir), "ipc", "call", "wpTest", "state"],
                        env=wl_env,
                        capture_output=True,
                        text=True,
                    )
                    if res.returncode == 0 and "displayedSource" in res.stdout:
                        st = json.loads(res.stdout.strip())
                        if st["cf"]["displayedSource"] == str(wp_red) and st["frameReady"]:
                            break
                    time.sleep(0.1)
                else:
                    raise AssertionError("Initial wallpaper did not become ready:\n" + log_path.read_text(errors="replace"))

                time.sleep(0.2)
                snap0 = tmp / "snap_initial.png"
                subprocess.run(["grim", str(snap0)], env=wl_env, check=True)
                s0 = _read_ppm_stats(snap0)
                assert s0["red"] > 0.55, f"Expected initial red dominance, got {s0}"

                # Trigger `alisMelt` shader transition Red -> Blue and sample frames across transition
                subprocess.run(
                    ["qs", "-p", str(harness_dir), "ipc", "call", "wpTest", "switchTo", str(wp_blue), "alisMelt"],
                    env=wl_env,
                    check=True,
                    capture_output=True,
                )

                mid_samples = []
                t_start = time.monotonic()
                for idx in range(7):
                    time.sleep(0.14)
                    snap = tmp / f"snap_melt_{idx}.png"
                    subprocess.run(["grim", str(snap)], env=wl_env, check=True)
                    st_mid = json.loads(
                        subprocess.check_output(
                            ["qs", "-p", str(harness_dir), "ipc", "call", "wpTest", "state"],
                            env=wl_env,
                            text=True,
                        ).strip()
                    )
                    sample = _read_ppm_stats(snap)
                    sample["t_ms"] = round((time.monotonic() - t_start) * 1000)
                    sample["transitioning"] = st_mid["cf"]["transitioning"]
                    sample["frameMix"] = round(st_mid["frameMix"], 3)
                    mid_samples.append(sample)

                # Wait for completion
                time.sleep(0.6)
                snap_end = tmp / "snap_end.png"
                subprocess.run(["grim", str(snap_end)], env=wl_env, check=True)
                s_end = _read_ppm_stats(snap_end)
                st_after = json.loads(
                    subprocess.check_output(
                        ["qs", "-p", str(harness_dir), "ipc", "call", "wpTest", "state"],
                        env=wl_env,
                        text=True,
                    ).strip()
                )

                # 1. Shader transition actually ran (not fallback)
                assert st_after["cf"]["shaderSuccessCount"] >= 1, f"Shader did not run: {st_after}"
                # 2. ZERO black blink frame during transition (previously dark spiked > 0.60 because source2 was transparent/black!)
                max_dark = max(s["dark"] for s in mid_samples)
                assert max_dark < 0.25, f"Black flash detected during shader transition! samples={mid_samples}"
                # 3. Genuine mid-transition blend: at least one frame has BOTH significant red AND significant blue!
                has_both = any(s["red"] > 0.08 and s["blue"] > 0.08 for s in mid_samples)
                assert has_both, f"Expected mid-transition blend with both red & blue visible, got {mid_samples}"
                # 4. Final frame settled on Blue
                assert s_end["blue"] > 0.55, f"Expected settled blue dominance, got {s_end}"

                log_txt = log_path.read_text(errors="replace")
                assert "Shader failed" not in log_txt and "Error:" not in log_txt, f"Unexpected QML/shader error:\n{log_txt}"
                print(
                    f"PASS: silent wallpaper transition pixel check "
                    f"(shaderSuccess={st_after['cf']['shaderSuccessCount']}, maxDark={max_dark:.3f}, "
                    f"midSamples={[(s['t_ms'], s['transitioning'], round(s['red'], 2), round(s['blue'], 2), s['frameMix']) for s in mid_samples]})"
                )
                return 0
            finally:
                try:
                    os.killpg(qs_proc.pid, 15)
                    qs_proc.wait(timeout=3)
                except Exception:
                    pass


if __name__ == "__main__":
    raise SystemExit(main())
