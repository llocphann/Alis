#!/usr/bin/env python3
"""Silent end-to-end verification of Quickshell Polkit fixes and Group 1 & 2 native replacements."""
from __future__ import annotations

import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
DISPATCH = ROOT / "scripts/native-dispatch"


def make_png(width: int, height: int, rgba_fn) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            rows.extend(rgba_fn(x, y))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(rows))) + chunk(b"IEND", b"")


def make_minimal_gif() -> bytes:
    # Valid 1x1 red GIF89a
    return (
        b"GIF89a\x01\x00\x01\x00\x80\x00\x00"
        b"\xff\x00\x00\x00\x00\x00"
        b",\x00\x00\x00\x00\x01\x00\x01\x00\x00"
        b"\x02\x02D\x01\x00;"
    )


def run_nd(args: list[str], env: dict[str, str], stdin_bytes: bytes | None = None, check: bool = True) -> subprocess.CompletedProcess[bytes]:
    res = subprocess.run(
        [str(DISPATCH), *args],
        input=stdin_bytes,
        env=env,
        capture_output=True,
        timeout=30,
    )
    if check and res.returncode != 0:
        raise AssertionError(f"native-dispatch {args} failed ({res.returncode}):\nSTDOUT: {res.stdout!r}\nSTDERR: {res.stderr!r}")
    return res


def test_polkit_contracts() -> None:
    impl = (ROOT / "services/PolkitServiceImpl.qml").read_text(encoding="utf-8")
    svc = (ROOT / "services/PolkitService.qml").read_text(encoding="utf-8")
    polkit_win = (ROOT / "modules/polkit/Polkit.qml").read_text(encoding="utf-8")
    polkit_content = (ROOT / "modules/polkit/PolkitContent.qml").read_text(encoding="utf-8")
    w_content = (ROOT / "modules/waffle/polkit/WPolkitContent.qml").read_text(encoding="utf-8")
    w_panels = (ROOT / "modules/waffle/ShellWafflePanelsImpl.qml").read_text(encoding="utf-8")
    startup = (ROOT / "defaults/niri/config.d/50-startup.kdl").read_text(encoding="utf-8")

    assert "flow?.isResponseRequired" in impl, "PolkitServiceImpl must bind interactionAvailable to flow.isResponseRequired"
    assert "function selectIdentity(" in impl, "PolkitServiceImpl must support selectIdentity"
    assert "agent?.isRegistered" in svc, "PolkitService.available must verify agent.isRegistered"
    for proc_name in ("polkit-mate-authentication-agent-1", "lxpolkit"):
        assert proc_name in svc, f"PolkitService pidof check missing {proc_name}"
    for prop in ("supplementaryMessage", "supplementaryIsError", "identities", "selectedIdentity", "selectIdentity"):
        assert prop in svc, f"PolkitService missing {prop}"

    assert "Variants {" not in polkit_win, "Polkit.qml must not open Exclusive focus PanelWindows on every monitor simultaneously"
    assert "GlobalStates.focusedScreen" in polkit_win, "Polkit.qml must target focusedScreen"
    assert "PolkitService.available && PolkitService.active" in polkit_win, "Polkit.qml must gate on PolkitService.available"

    assert "onDismiss: PolkitService.cancel()" in polkit_content, "PolkitContent must wire WindowDialog onDismiss to PolkitService.cancel()"
    assert "inputField.forceActiveFocus()" in polkit_content, "PolkitContent must focus inputField"
    assert "PolkitService.supplementaryMessage" in polkit_content, "PolkitContent must render supplementaryMessage"
    assert "PolkitService.selectIdentity" in polkit_content, "PolkitContent must support identity selection"

    assert "PolkitService.supplementaryMessage" in w_content, "WPolkitContent must render supplementaryMessage"
    assert "PolkitService.selectIdentity" in w_content, "WPolkitContent must support identity selection"
    assert "WafflePolkitModule.WafflePolkit" in w_panels, "ShellWafflePanelsImpl must wire WafflePolkit"

    for line in startup.splitlines():
        s = line.strip()
        if not s.startswith("//") and "polkit-gnome-authentication-agent-1" in s:
            raise AssertionError("50-startup.kdl must not auto-start external polkit-gnome agent by default")
    print("PASS: Quickshell Polkit contracts verified")


def test_kf6_fonts_and_shaders() -> None:
    for root_dir in (ROOT / "modules", ROOT / "services"):
        for qml in root_dir.rglob("*.qml"):
            txt = qml.read_text(encoding="utf-8", errors="ignore")
            assert "org.kde.kirigami" not in txt, f"KF6 kirigami import leaked in {qml}"
            assert "org.kde.syntaxhighlighting" not in txt, f"KF6 syntaxhighlighting import leaked in {qml}"

    qsb = ROOT / "modules/common/widgets/wallpaperTransitions/alisTransitions.frag.qsb"
    assert qsb.is_file() and qsb.stat().st_size > 200, "compiled alisTransitions.frag.qsb missing or empty"

    appearance = (ROOT / "modules/common/Appearance.qml").read_text(encoding="utf-8")
    for font_rel in (
        "assets/fonts/MaterialSymbolsRounded.ttf",
        "assets/fonts/RobotoFlex-VF.ttf",
        "assets/fonts/Rubik-VF.ttf",
        "assets/fonts/Twemoji.ttf",
    ):
        f = ROOT / font_rel
        assert f.is_file() and f.stat().st_size > 10000, f"bundled font missing: {font_rel}"
        assert font_rel in appearance, f"Appearance.qml missing FontLoader for {font_rel}"
    for subdir in ("Gabarito", "ReadexPro", "Oxanium"):
        ttfs = list((ROOT / "assets/fonts" / subdir).glob("*.ttf"))
        assert ttfs, f"bundled font family missing in assets/fonts/{subdir}"
    print("PASS: zero KF6 QML imports, compiled wallpaper shader QSB, and all 7 bundled font families verified")


def test_native_cli_e2e() -> None:
    with tempfile.TemporaryDirectory(prefix="alis-native-e2e-") as td:
        tmp = Path(td)
        env = dict(os.environ)
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("DISPLAY", None)
        env["XDG_CONFIG_HOME"] = str(tmp / "config")
        env["XDG_CACHE_HOME"] = str(tmp / "cache")
        env["XDG_STATE_HOME"] = str(tmp / "state")
        env["XDG_DATA_HOME"] = str(tmp / "data")
        env["ALIS_CLIPBOARD_STORE_DIR"] = str(tmp / "clipstore")

        # 1. Native clipboard store: text, HTML stripping, dedup, image PNG, decode, delete, wipe, edge cases
        run_nd(["clipboard", "store"], env, stdin_bytes=b"hello world")
        run_nd(["clipboard", "store"], env, stdin_bytes=b"   \n\t  ")  # whitespace skipped
        run_nd(["clipboard", "store"], env, stdin_bytes=b'<meta http-equiv="content-type" content="text/html; charset=utf-8"><b>Rich</b> text')
        run_nd(["clipboard", "store"], env, stdin_bytes=b"hello world")  # dedup -> moves to top
        png_bytes = make_png(32, 24, lambda x, y: (240, 60, 40, 255))
        run_nd(["clipboard", "store", "--mime", "image/png"], env, stdin_bytes=png_bytes)

        listed = run_nd(["clipboard", "list", "--limit", "10"], env).stdout.decode("utf-8").splitlines()
        assert len(listed) == 3, f"expected 3 deduped rows (png, hello world, Rich text), got {listed}"
        assert "[[ binary data" in listed[0] and "png 32x24 ]]" in listed[0], listed[0]
        assert listed[1].endswith("\thello world"), listed[1]
        assert listed[2].endswith("\tRich text"), listed[2]

        img_id = listed[0].split("\t", 1)[0]
        text_id = listed[1].split("\t", 1)[0]
        assert run_nd(["clipboard", "decode", img_id], env).stdout == png_bytes
        assert run_nd(["clipboard", "decode", text_id], env).stdout == b"hello world"
        # Invalid ID must fail cleanly
        bad_dec = run_nd(["clipboard", "decode", "999999"], env, check=False)
        assert bad_dec.returncode != 0

        run_nd(["clipboard", "delete", text_id], env)
        after_del = run_nd(["clipboard", "list"], env).stdout.decode("utf-8").splitlines()
        assert len(after_del) == 2 and all(not r.startswith(f"{text_id}\t") for r in after_del), after_del

        run_nd(["clipboard", "wipe"], env)
        assert run_nd(["clipboard", "list"], env).stdout.decode("utf-8").strip() == ""
        print("PASS: native clipboard store/list/decode/delete/wipe/dedup/HTML-strip/PNG-meta")

        # 2. Image ops (identify, crop to file & stdout, resize incl. mktemp no-ext, first-frame GIF, luma, convert, to-pdf)
        wall_dir = tmp / "walls"
        wall_dir.mkdir()
        color_png = wall_dir / "sample.png"
        color_png.write_bytes(make_png(120, 80, lambda x, y: (220, 30, 30, 255) if x < 60 else (30, 120, 220, 255)))
        white_png = wall_dir / "white.png"
        white_png.write_bytes(make_png(32, 32, lambda x, y: (255, 255, 255, 255)))
        black_png = wall_dir / "black.png"
        black_png.write_bytes(make_png(32, 32, lambda x, y: (0, 0, 0, 255)))
        gif_path = wall_dir / "anim.gif"
        gif_path.write_bytes(make_minimal_gif())

        ident = run_nd(["image", "identify", str(color_png)], env).stdout.decode().strip()
        assert ident == "120 80", ident

        cropped_file = tmp / "cropped.png"
        run_nd(["image", "crop", str(color_png), "40x30+10+10", str(cropped_file)], env)
        assert run_nd(["image", "identify", str(cropped_file)], env).stdout.decode().strip() == "40 30"

        cropped_stdout = run_nd(["image", "crop", str(color_png), "20x15+0+0", "-"], env).stdout
        assert cropped_stdout.startswith(b"\x89PNG\r\n\x1a\n")

        # Resize to extensionless mktemp-style path (like Wallpapers.qml!)
        resized_tmp = tmp / "thumb.png.AbCdEf"
        run_nd(["image", "resize", str(color_png), "64x64", str(resized_tmp)], env)
        assert run_nd(["image", "identify", str(resized_tmp)], env).stdout.decode().strip() == "64 43"

        resized_jpg = tmp / "small.jpg"
        run_nd(["image", "resize", str(color_png), "50x", str(resized_jpg), "--quality", "50"], env)
        assert resized_jpg.read_bytes().startswith(b"\xff\xd8\xff")

        gif_frame = tmp / "gif_frame.png"
        run_nd(["image", "first-frame", str(gif_path), str(gif_frame)], env)
        assert run_nd(["image", "identify", str(gif_frame)], env).stdout.decode().strip() == "1 1"

        w_luma = float(run_nd(["image", "luma", str(white_png)], env).stdout.decode().strip())
        b_luma = float(run_nd(["image", "luma", str(black_png)], env).stdout.decode().strip())
        w_pct = float(run_nd(["image", "luma", str(white_png), "--percent"], env).stdout.decode().strip())
        assert w_luma > 0.99 and b_luma < 0.01 and w_pct > 99.0, (w_luma, b_luma, w_pct)

        red_png = wall_dir / "red.png"
        red_png.write_bytes(make_png(16, 16, lambda x, y: (255, 0, 0, 255)))
        green_png = wall_dir / "green.png"
        green_png.write_bytes(make_png(16, 16, lambda x, y: (0, 255, 0, 255)))
        r_h, r_s, r_l = [float(x) for x in run_nd(["image", "hsl", str(red_png)], env).stdout.decode().strip().split()]
        g_h, g_s, g_l = [float(x) for x in run_nd(["image", "hsl", str(green_png)], env).stdout.decode().strip().split()]
        w_h, w_s, w_l = [float(x) for x in run_nd(["image", "hsl", str(white_png)], env).stdout.decode().strip().split()]
        assert abs(r_h - 0.0) < 0.1 and abs(r_s - 1.0) < 0.01 and abs(r_l - 0.5) < 0.01, (r_h, r_s, r_l)
        assert abs(g_h - 120.0) < 0.1 and abs(g_s - 1.0) < 0.01 and abs(g_l - 0.5) < 0.01, (g_h, g_s, g_l)
        assert w_s < 0.01 and w_l > 0.99, (w_h, w_s, w_l)

        pdf_out = tmp / "merged.pdf"
        run_nd(["image", "to-pdf", str(pdf_out), str(color_png), str(white_png)], env)
        pdf_data = pdf_out.read_bytes()
        assert pdf_data.startswith(b"%PDF-1.4") and b"%%EOF" in pdf_data and b"/Count 2" in pdf_data
        print("PASS: native image ops (identify, crop, resize incl. extensionless tmp, first-frame, luma, hsl, to-pdf)")

        # 3. Thumbgen, find-regions, cover-colors
        run_nd(["thumbgen", "-d", str(wall_dir), "-s", "normal", "-w", "2"], env)
        thumbs = list((tmp / "cache/thumbnails/normal").glob("*.png"))
        assert len(thumbs) >= 3, f"expected >= 3 generated thumbnails, got {thumbs}"

        reg_png = tmp / "regions.png"
        reg_png.write_bytes(make_png(200, 160, lambda x, y: (240, 200, 40, 255) if (20 <= x <= 90 and 20 <= y <= 100) else (20, 20, 30, 255)))
        reg_out = json.loads(run_nd(["find-regions", "--image", str(reg_png), "--max-width", "180", "--max-height", "150"], env).stdout.decode())
        assert isinstance(reg_out, list), reg_out

        cover_json_file = tmp / "cover-colors.json"
        cover_raw = run_nd(["cover-colors", str(color_png), "3", str(cover_json_file)], env).stdout.decode().strip()
        cover_out = json.loads(cover_raw)
        assert isinstance(cover_out, list) and len(cover_out) >= 2 and all(c.startswith("#") and len(c) == 7 for c in cover_out), cover_out
        assert json.loads(cover_json_file.read_text(encoding="utf-8")) == cover_out
        print("PASS: native thumbgen, find-regions, cover-colors")

        # 4. Gowall native replacement
        themes_txt = run_nd(["gowall", "list"], env).stdout.decode()
        assert "catppuccin" in themes_txt.lower(), themes_txt[:200]
        gw_out = tmp / "gowall_catppuccin.png"
        run_nd(["gowall", "convert", str(color_png), "-t", "catppuccin", "--output", str(gw_out)], env)
        assert gw_out.is_file() and gw_out.read_bytes().startswith(b"\x89PNG")
        gw_inv = tmp / "gowall_inv.png"
        run_nd(["gowall", "invert", str(color_png), "--output", str(gw_inv)], env)
        assert gw_inv.is_file()
        gw_pix = tmp / "gowall_pix.png"
        run_nd(["gowall", "pixelate", str(color_png), "-s", "8", "--output", str(gw_pix)], env)
        assert gw_pix.is_file()
        gw_ext = run_nd(["gowall", "extract", str(color_png), "-c", "4"], env).stdout.decode()
        assert "#" in gw_ext, gw_ext
        print("PASS: native gowall (list, convert, invert, pixelate, extract)")

        # 5. Desktop INI config writers (replacing kwriteconfig6) + headless file-dialog guard
        cfg_dir = tmp / "config"
        cfg_dir.mkdir(parents=True, exist_ok=True)
        (cfg_dir / "kdeglobals").write_text("[General]\n# keep comment\nColorScheme=BreezeDark\n", encoding="utf-8")
        run_nd(["desktop-icons", "Papirus-Dark"], env)
        kde_txt = (cfg_dir / "kdeglobals").read_text(encoding="utf-8")
        assert "# keep comment" in kde_txt and "ColorScheme=BreezeDark" in kde_txt and "Theme=Papirus-Dark" in kde_txt, kde_txt

        run_nd(["desktop-fonts", "Roboto Flex", "JetBrainsMono Nerd Font", "11"], env)
        kde_txt2 = (cfg_dir / "kdeglobals").read_text(encoding="utf-8")
        assert "font=Roboto Flex,11," in kde_txt2 and "fixed=JetBrainsMono Nerd Font,11," in kde_txt2, kde_txt2

        run_nd(["desktop-kdeconfig", "--file", "kdeglobals", "--group", "KDE", "--key", "widgetStyle", "Darkly"], env)
        assert "widgetStyle=Darkly" in (cfg_dir / "kdeglobals").read_text(encoding="utf-8")

        fd_res = run_nd(["file-dialog", "--title", "Headless"], env, check=False)
        assert fd_res.returncode != 0, "headless file-dialog must fail cleanly without hanging"

        # 6. Calc & Translate list-languages
        calc_out = run_nd(["calc", "2 + 3 * 4"], env).stdout.decode().strip()
        assert calc_out == "14", calc_out
        langs = run_nd(["translate", "--list-languages"], env).stdout.decode()
        assert "en" in langs and "vi" in langs
        print("PASS: native desktop INI writers (icons, fonts, kdeconfig), headless file-dialog guard, calc & translate")

        # 7. Makefile install-fonts & uninstall-fonts staging check
        stage = tmp / "stage"
        subprocess.run(["make", "-s", "install-fonts", f"DESTDIR={stage}", "PREFIX=/opt/alis"], cwd=ROOT, check=True)
        installed_fonts = list((stage / "opt/alis/share/fonts/alis").rglob("*.ttf"))
        assert len(installed_fonts) >= 7, f"expected >= 7 bundled fonts installed, got {len(installed_fonts)}"
        subprocess.run(["make", "-s", "uninstall-fonts", f"DESTDIR={stage}", "PREFIX=/opt/alis"], cwd=ROOT, check=True)
        assert not (stage / "opt/alis/share/fonts/alis").exists()
        print(f"PASS: Makefile install-fonts / uninstall-fonts ({len(installed_fonts)} font files)")


def _build_filtered_path(dest_dir: Path, exclude: set[str]) -> str:
    """Create a PATH directory with symlinks to standard system binaries except excluded ones."""
    dest_dir.mkdir(parents=True, exist_ok=True)
    seen: set[str] = set()
    for base in os.environ.get("PATH", "/usr/bin:/bin").split(os.pathsep):
        bpath = Path(base)
        if not bpath.is_dir():
            continue
        for entry in bpath.iterdir():
            name = entry.name
            if name in exclude or name in seen:
                continue
            if entry.is_file() and os.access(entry, os.X_OK):
                try:
                    (dest_dir / name).symlink_to(entry)
                    seen.add(name)
                except OSError:
                    pass
    return str(dest_dir)


def test_config_skew_dispatch_emoji_and_no_jq() -> None:
    # 1. Config.qml default wallpaper backend provider must match defaults/config.json ("internal")
    cfg_qml = (ROOT / "modules/common/Config.qml").read_text(encoding="utf-8")
    cfg_json = json.loads((ROOT / "defaults/config.json").read_text(encoding="utf-8"))
    assert cfg_json["background"]["backend"]["provider"] == "internal"
    assert 'property string provider: "internal"' in cfg_qml, "Config.qml must default backend.provider to internal"
    assert 'property string provider: "awww"' not in cfg_qml, "Config.qml must not default backend.provider to awww"
    wallpapers_qml = (ROOT / "services/Wallpapers.qml").read_text(encoding="utf-8")
    assert "readonly property string backendProvider: AwwwBackend.provider" in wallpapers_qml
    assert "readonly property bool awwwBackendEnabled: AwwwBackend.enabled" in wallpapers_qml

    # 2. WallpaperSkewView.qml must prefer native-dispatch image hsl over ImageMagick convert
    skew_qml = (ROOT / "modules/wallpaperSelector/WallpaperSkewView.qml").read_text(encoding="utf-8")
    assert 'Quickshell.shellPath("scripts/native-dispatch")' in skew_qml
    assert 'image hsl' in skew_qml
    assert 'command -v convert' in skew_qml

    with tempfile.TemporaryDirectory(prefix="alis-no-jq-e2e-") as td:
        tmp = Path(td)
        no_jq_path = _build_filtered_path(tmp / "clean-bin", {"jq", "fuzzel", "wofi", "rofi", "convert", "magick"})
        env = dict(os.environ)
        env["PATH"] = no_jq_path
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("DISPLAY", None)
        env.pop("ALIS_NATIVE_BIN_DIR", None)
        env["HOME"] = str(tmp / "home")
        env["XDG_CONFIG_HOME"] = str(tmp / "config")
        env["XDG_CACHE_HOME"] = str(tmp / "cache")
        env["XDG_STATE_HOME"] = str(tmp / "state")
        env["XDG_DATA_HOME"] = str(tmp / "data")
        (tmp / "home").mkdir(parents=True, exist_ok=True)
        (tmp / "config/alis").mkdir(parents=True, exist_ok=True)
        (tmp / "config/alis/config.json").write_text(
            json.dumps({
                "appearance": {
                    "theme": "auto",
                    "palette": {"type": "scheme-tonal-spot"},
                    "wallpaperTheming": {
                        "enableAppsAndShell": True,
                        "enableQtApps": True,
                        "enableTerminal": True,
                        "enableCava": True,
                        "enableVSCode": False,
                        "enableNeovim": False,
                        "enableOpenCode": False,
                        "enableCodex": False,
                        "enableClaude": False,
                        "enableVesktop": False,
                    },
                    "cava": {
                        "colorSource": "vibrant",
                        "gradientCount": 3,
                        "bars": 32,
                        "stereo": False,
                    },
                },
                "background": {"wallpaperPath": ""},
            }),
            encoding="utf-8",
        )
        # Ensure stub `cava` exists in clean-bin so 90-cava.sh exercises full generation
        cava_stub = tmp / "clean-bin/cava"
        if not cava_stub.exists():
            cava_stub.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            cava_stub.chmod(0o755)

        # Verify jq/fuzzel are truly absent from filtered PATH
        assert subprocess.run(["bash", "-c", "command -v jq"], env=env, capture_output=True).returncode != 0
        assert subprocess.run(["bash", "-c", "command -v fuzzel"], env=env, capture_output=True).returncode != 0

        # 3. Run switchwall.sh WITHOUT jq in PATH
        sw = subprocess.run(
            ["bash", str(ROOT / "scripts/colors/switchwall.sh"), "--color", "#3366cc", "--mode", "dark", "--noswitch"],
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert sw.returncode == 0, f"switchwall.sh failed without jq ({sw.returncode}):\nSTDOUT:{sw.stdout}\nSTDERR:{sw.stderr}"
        gen_dir = tmp / "state/quickshell/user/generated"
        for req_file in ("colors.json", "app-palette.json", "palette.json", "terminal.json", "material_colors.scss", "chromium.theme", "theme-generation-ready.txt"):
            assert (gen_dir / req_file).is_file() and (gen_dir / req_file).stat().st_size > 0, f"missing {req_file} after no-jq switchwall.sh"
        updated_cfg = json.loads((tmp / "config/alis/config.json").read_text(encoding="utf-8"))
        assert updated_cfg["appearance"]["palette"]["accentColor"] == "#3366cc", updated_cfg

        # 4. Run color modules WITHOUT jq in PATH: 90-cava.sh, 10-terminals.sh, 30-editors.sh, apply-gtk-theme.sh
        cava_run = subprocess.run(
            ["bash", str(ROOT / "scripts/colors/modules/90-cava.sh")],
            env=env,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert cava_run.returncode == 0, f"90-cava.sh failed without jq: {cava_run.stderr}"
        cava_cfg = (tmp / "config/cava/config").read_text(encoding="utf-8")
        assert "gradient_color_1 = '#" in cava_cfg, cava_cfg
        assert "gradient_color_3 = '#" in cava_cfg, cava_cfg
        assert "gradient_color_4" not in cava_cfg, cava_cfg
        assert "bars = 32" in cava_cfg and "channels = mono" in cava_cfg, cava_cfg

        term_run = subprocess.run(
            ["bash", str(ROOT / "scripts/colors/modules/10-terminals.sh")],
            env=env,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert term_run.returncode == 0, f"10-terminals.sh failed without jq: {term_run.stderr}"
        assert (gen_dir / "terminal/sequences.txt").is_file()

        ed_run = subprocess.run(
            ["bash", str(ROOT / "scripts/colors/modules/30-editors.sh")],
            env=env,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert ed_run.returncode == 0, f"30-editors.sh failed without jq: {ed_run.stderr}"

        gtk_run = subprocess.run(
            ["bash", str(ROOT / "scripts/colors/apply-gtk-theme.sh")],
            env=env,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert gtk_run.returncode == 0, f"apply-gtk-theme.sh failed without jq: {gtk_run.stderr}"
        assert (tmp / "config/kdeglobals").is_file(), "apply-gtk-theme.sh did not write kdeglobals without jq"

        # 5. Exercise 70-steam.sh, 80-pear-desktop.sh, apply-spicetify-theme.sh helpers without jq
        def run_script_fn(script_path: Path, body: str) -> subprocess.CompletedProcess[str]:
            # Load the real script verbatim (minus the trailing `main "$@"`) via a wrapper in the same directory-relative context
            wrapper = (
                f'BASH_SOURCE_ORIG="{script_path}"\n'
                f'eval "$(sed \'s|${{BASH_SOURCE\\[0\\]}}|{script_path}|g; /^main "\\$@"$/d\' "{script_path}")"\n'
                f'{body}\n'
            )
            return subprocess.run(["bash", "-c", wrapper], env=env, capture_output=True, text=True, timeout=20)

        steam_fn = run_script_fn(
            ROOT / "scripts/colors/modules/70-steam.sh",
            'generate_millennium_css_from_colors_json && printf "APPEAR=%s\\n" "$(millennium_material_appearance)"',
        )
        assert steam_fn.returncode == 0 and "--md-sys-color-primary: rgb(" in steam_fn.stdout and "APPEAR=Dark" in steam_fn.stdout, (steam_fn.stdout, steam_fn.stderr)

        pear_fn = run_script_fn(
            ROOT / "scripts/colors/modules/80-pear-desktop.sh",
            (
                f'PEAR_CONFIG_DIR="{tmp}/pear"; mkdir -p "$PEAR_CONFIG_DIR"; '
                f'PEAR_CONFIG_FILE="$PEAR_CONFIG_DIR/config.json"; '
                f'out="$(generate_css_from_colors_json)"; '
                f'[[ "$out" == *"--ctp-text: #"* ]]; '
                f'register_theme_in_config "{tmp}/pear/theme.css"; '
                f'cat "$PEAR_CONFIG_FILE"'
            ),
        )
        assert pear_fn.returncode == 0 and f"{tmp}/pear/theme.css" in pear_fn.stdout, (pear_fn.stdout, pear_fn.stderr)

        spice_fn = run_script_fn(
            ROOT / "scripts/colors/apply-spicetify-theme.sh",
            'read_colors && printf "%s|%s\\n" "${COLORS[primary]}" "${COLORS[surface]}"',
        )
        assert spice_fn.returncode == 0 and spice_fn.stdout.strip().startswith("#"), (spice_fn.stdout, spice_fn.stderr)

        # 6. native-dispatch: stale native-bin-dir upgrade, exit-2 fallback, accurate usage line
        usage_res = subprocess.run([str(DISPATCH)], env=env, capture_output=True, text=True, timeout=10)
        assert usage_res.returncode == 64
        for expected_cmd in ("image", "clipboard", "audio-spectrum", "mic-meter", "mpd-mpris", "gowall", "thumbgen", "desktop-fonts"):
            assert expected_cmd in usage_res.stderr, f"usage missing {expected_cmd}: {usage_res.stderr}"
        assert "companion" not in usage_res.stderr, f"usage still lists removed companion: {usage_res.stderr}"

        # Stale older binary dir in $STATE_DIR/native-bin-dir must auto-upgrade to newer DEFAULT_BIN_DIR
        stale_dir = tmp / "stale-bin"
        stale_dir.mkdir()
        stale_bin = stale_dir / "alis-native"
        stale_bin.write_text("#!/usr/bin/env bash\nexit 2\n", encoding="utf-8")
        stale_bin.chmod(0o755)
        os.utime(stale_bin, (946684800, 946684800))  # year 2000 -> older than repo binary
        (tmp / "state/alis").mkdir(parents=True, exist_ok=True)
        (tmp / "state/alis/native-bin-dir").write_text(str(stale_dir) + "\n", encoding="utf-8")
        info = run_nd(["backend-info"], env).stdout.decode()
        assert f"bin_dir={ROOT / 'native/bin'}" in info, f"stale native-bin-dir was not upgraded: {info}"
        assert run_nd(["calc", "6 * 7"], env).stdout.decode().strip() == "42"

        # Even if stale dir has newer mtime on all 4 stubs, clap exit-2 AND Round-1 exit-1
        # unknown-subcommand errors fall back cleanly to DEFAULT_BIN_DIR without leaking stderr.
        future_dir = tmp / "future-stale-bin"
        future_dir.mkdir()
        for bname in ("alis-native", "alis-theme", "alis-inputd", "alis-mpdd"):
            stub = future_dir / bname
            if bname == "alis-theme":
                stub.write_text(
                    "#!/usr/bin/env bash\n"
                    'if [[ "${1:-}" == "--image" && "${2:-}" == "hsl" ]]; then\n'
                    '  echo "Error: unknown --image subcommand: hsl" >&2; exit 1\n'
                    "fi\n"
                    'echo "error: unrecognized subcommand" >&2; exit 2\n',
                    encoding="utf-8",
                )
            elif bname == "alis-native":
                stub.write_text(
                    "#!/usr/bin/env bash\n"
                    'if [[ "${1:-}" == "idle" ]]; then exec sleep 30; fi\n'
                    'echo "error: unrecognized subcommand" >&2; exit 2\n',
                    encoding="utf-8",
                )
            else:
                stub.write_text('#!/usr/bin/env bash\necho "error: unrecognized subcommand" >&2; exit 2\n', encoding="utf-8")
            stub.chmod(0o755)
            os.utime(stub, (4102444800, 4102444800))  # year 2100
        (tmp / "state/alis/native-bin-dir").write_text(str(future_dir) + "\n", encoding="utf-8")
        ident_fb = run_nd(["image", "identify", str(ROOT / "assets/fonts/MaterialSymbolsRounded.ttf")], env, check=False)
        # Should reach real alis-theme (not exit 2 from stub)
        assert ident_fb.returncode != 2, "exit-2 subcommand fallback to DEFAULT_BIN_DIR did not trigger"
        hsl_png = tmp / "-dash-fb.png"
        hsl_png.write_bytes(make_png(8, 8, lambda x, y: (255, 0, 0, 0) if x < 4 else (0, 0, 255, 255)))
        hsl_proc = subprocess.run(
            [str(DISPATCH), "image", "hsl", hsl_png.name],
            cwd=str(tmp),
            env=env,
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert hsl_proc.returncode == 0, f"fallback image hsl failed: {hsl_proc.stderr}"
        assert hsl_proc.stdout.strip().startswith("240."), f"expected blue alpha-weighted HSL: {hsl_proc.stdout}"
        assert "unknown --image subcommand" not in hsl_proc.stderr, f"stale stderr leaked: {hsl_proc.stderr}"

        aud_proc = subprocess.run(
            [str(DISPATCH), "audio-spectrum", "--help"],
            env=env,
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert aud_proc.returncode == 0 and "unrecognized" not in aud_proc.stderr, (aud_proc.returncode, aud_proc.stderr)

        # Daemon launched via non-default BIN_DIR must not orphan child processes on SIGTERM
        import time as _time
        daemon_p = subprocess.Popen([str(DISPATCH), "idle"], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        _time.sleep(0.8)
        child_pids = subprocess.run(["pgrep", "-P", str(daemon_p.pid)], capture_output=True, text=True).stdout.split()
        daemon_p.terminate()
        daemon_p.wait(timeout=3)
        _time.sleep(0.2)
        orphans = [pid for pid in child_pids if Path(f"/proc/{pid}").exists()]
        assert not orphans, f"SIGTERM left orphaned daemon children: {orphans}"

        # 7. emoji-data.sh without fuzzel/wofi/rofi fails cleanly and never hangs on Wayland without running shell
        for extra_env in ({}, {"WAYLAND_DISPLAY": "wayland-nonexistent-test", "XDG_RUNTIME_DIR": str(tmp / "rt")}):
            e_env = dict(env)
            e_env.update(extra_env)
            if "XDG_RUNTIME_DIR" in extra_env:
                Path(extra_env["XDG_RUNTIME_DIR"]).mkdir(parents=True, exist_ok=True)
            emoji_res = subprocess.run(
                ["bash", str(ROOT / "scripts/emoji/emoji-data.sh"), "copy"],
                env=e_env,
                capture_output=True,
                text=True,
                timeout=3,
            )
            assert emoji_res.returncode == 1, (extra_env, emoji_res.returncode, emoji_res.stderr)
            assert "No external dmenu picker found" in emoji_res.stderr, emoji_res.stderr
            assert "command not found" not in emoji_res.stderr, emoji_res.stderr
        assert "### DATA ###" in (ROOT / "scripts/emoji/emoji-data.sh").read_text(encoding="utf-8")
        print("PASS: Config.qml provider=internal, WallpaperSkewView native hsl, full no-jq color pipeline, stale native-bin-dir fallback, and fuzzel-free emoji-data.sh")


if __name__ == "__main__":
    test_polkit_contracts()
    test_kf6_fonts_and_shaders()
    test_native_cli_e2e()
    test_config_skew_dispatch_emoji_and_no_jq()
    print("ALL POLKIT & NATIVE REPLACEMENT E2E CHECKS PASSED")
