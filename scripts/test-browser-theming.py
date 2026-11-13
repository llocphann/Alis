#!/usr/bin/env python3
"""Isolated regression test for apply-browser-themes.py across Zen, Brave, Vivaldi, Chromium, and Firefox."""

import json
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "colors" / "apply-browser-themes.py"
BRIDGE = ROOT / "scripts" / "colors" / "alis-browser-theme-bridge.py"


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="alis-browser-theme-test-") as tmp:
        base = Path(tmp)
        home = base / "home"
        etc = base / "etc"
        state = base / "state" / "quickshell"
        gen = state / "user" / "generated"
        gen.mkdir(parents=True)

        # 1. Seed palette
        (gen / "app-palette.json").write_text(json.dumps({
            "app_background": "#150e0e",
            "app_surface": "#1a1110",
            "app_surface_elevated": "#221716",
            "app_surface_popup": "#291d1b",
            "app_surface_hover": "#382b2a",
            "app_foreground": "#f9e0dd",
            "app_subtext": "#94817f",
            "app_accent": "#ffb4ac",
            "app_on_accent": "#61332f",
            "app_accent_container": "#764540",
            "app_border_subtle": "#554442",
            "app_selection": "#6d4c49",
            "primary": "#ffb4ac",
            "primary_container": "#764540",
        }), encoding="utf-8")
        (gen / "theme-meta.json").write_text(json.dumps({"mode": "dark"}), encoding="utf-8")
        (gen / "color.txt").write_text("#ff6b35\n", encoding="utf-8")

        # 2. Zen Browser native + Flatpak with pre-existing userChrome.css
        zen_native = home / ".config/zen/67nr7erf.Default (release)"
        zen_native.mkdir(parents=True)
        (home / ".config/zen/profiles.ini").write_text(
            "[Profile0]\nName=Default (release)\nIsRelative=1\nPath=67nr7erf.Default (release)\nDefault=1\n",
            encoding="utf-8",
        )
        zen_flatpak = home / ".var/app/app.zen_browser.zen/.zen/8nwurn3x.Default (release)"
        (zen_flatpak / "chrome").mkdir(parents=True)
        (home / ".var/app/app.zen_browser.zen/.zen/profiles.ini").write_text(
            "[Profile0]\nName=Default (release)\nIsRelative=1\nPath=8nwurn3x.Default (release)\nDefault=1\n",
            encoding="utf-8",
        )
        original_chrome_css = "toolbox#navigator-toolbox.chrome-block {\n    min-width: 0 !important;\n}\n"
        (zen_flatpak / "chrome/userChrome.css").write_text(original_chrome_css, encoding="utf-8")

        # 3. Vivaldi with pre-existing custom user theme
        viv_prefs = home / ".config/vivaldi/Default/Preferences"
        viv_prefs.parent.mkdir(parents=True)
        viv_prefs.write_text(json.dumps({
            "vivaldi": {
                "theme": {"schedule": {"o_s": {"dark": "Vivaldi2", "light": "custom-teal-id"}}},
                "themes": {
                    "user": [{"id": "custom-teal-id", "name": "Dark Teal V", "colorBg": "#0c1113"}]
                },
            }
        }), encoding="utf-8")

        # 4. Brave without writable /etc/brave/policies/managed + Chromium with writable policy dir
        brave_prefs = home / ".config/BraveSoftware/Brave-Browser/Default/Preferences"
        brave_prefs.parent.mkdir(parents=True)
        brave_prefs.write_text(json.dumps({"profile": {"name": "Main"}}), encoding="utf-8")

        chrom_prefs = home / ".config/chromium/Default/Preferences"
        chrom_prefs.parent.mkdir(parents=True)
        chrom_prefs.write_text(json.dumps({"profile": {"name": "Main"}}), encoding="utf-8")
        (etc / "chromium/policies/managed").mkdir(parents=True)

        # Run apply twice (idempotency check)
        for _ in range(2):
            subprocess.run(
                [sys.executable, str(SCRIPT), "--home-dir", str(home), "--etc-dir", str(etc), "--state-dir", str(state), "--no-live-refresh"],
                check=True,
            )

        # Verify Zen native & Flatpak (both cold-boot fallback and live LWT bridge)
        for zdir in (zen_native, zen_flatpak):
            assert (zdir / "chrome/alis-theme.css").is_file(), f"missing alis-theme.css in {zdir}"
            tcss = (zdir / "chrome/alis-theme.css").read_text()
            assert ":root:not([lwtheme])" in tcss
            assert ":root[lwtheme]" in tcss
            assert ":root[lwtheme] .zen-browser-generic-background" in tcss
            assert "--zen-primary-color: #ffb4ac !important;" in tcss
            assert "--zen-primary-color: var(--lwt-tab-line-color) !important;" in tcss
            # Guarantee zero CSS custom-property cycles in :root[lwtheme]
            import re as _re
            lw_section = tcss.split(":root[lwtheme],", 1)[1].split("}", 1)[0]
            lhs_vars = set(_re.findall(r"(--[a-zA-Z0-9-]+)\s*:", lw_section))
            rhs_vars = set(_re.findall(r"var\((--[a-zA-Z0-9-]+)", lw_section))
            assert lhs_vars.isdisjoint(rhs_vars), f"CSS custom property cycle risk: {lhs_vars & rhs_vars}"
            uc = (zdir / "chrome/userChrome.css").read_text()
            assert uc.startswith('@import "alis-theme.css";'), f"import not at top in {zdir}: {uc}"
            assert uc.count("alis-theme.css") == 1, "duplicate @import on repeated run"
            ujs = (zdir / "user.js").read_text()
            assert 'toolkit.legacyUserProfileCustomizations.stylesheets", true' in ujs
            assert 'zen.theme.disable-lightweight", false' in ujs
        assert "toolbox#navigator-toolbox.chrome-block" in (zen_flatpak / "chrome/userChrome.css").read_text()

        # Verify XPI archive & live payload JSON
        xpi_path = gen / "alis-browser-theme.xpi"
        assert xpi_path.is_file(), "missing packaged alis-browser-theme.xpi"
        with zipfile.ZipFile(xpi_path, "r") as zf:
            names = set(zf.namelist())
            assert {"manifest.json", "background.js", "icon.svg"}.issubset(names), f"incomplete xpi: {names}"
            ext_manifest = json.loads(zf.read("manifest.json").decode("utf-8"))
            assert ext_manifest["browser_specific_settings"]["gecko"]["id"] == "alis-browser-theme@alis.local"
        live_json = json.loads((gen / "browser-live-theme.json").read_text())
        assert live_json["enabled"] is True
        assert live_json["gecko_theme"]["colors"]["tab_line"] == "#ffb4ac"
        assert live_json["gecko_theme"]["properties"]["color_scheme"] == "dark"

        # Verify Vivaldi
        vd = json.loads(viv_prefs.read_text())
        v_users = vd["vivaldi"]["themes"]["user"]
        assert len(v_users) == 2, f"expected user theme + Alis Auto, got {v_users}"
        assert any(t["id"] == "custom-teal-id" and t["name"] == "Dark Teal V" for t in v_users)
        assert any(t["id"] == "alis-0000-4000-8000-000000000001" and t["colorHighlightBg"] == "#ffb4ac" for t in v_users)
        assert vd["vivaldi"]["theme"]["schedule"]["o_s"]["dark"] == "alis-0000-4000-8000-000000000001"

        # Verify Brave got direct user_color2 fallback (since /etc/brave is not writable)
        bd = json.loads(brave_prefs.read_text())
        assert "user_color2" in bd["browser"]["theme"]
        assert bd["browser"]["theme"]["color_scheme2"] == 2
        assert bd["profile"]["name"] == "Main"

        # Verify Chromium got managed policy file (since etc/chromium/policies/managed IS writable)
        pol = json.loads((etc / "chromium/policies/managed/ii-theme.json").read_text())
        assert pol["BrowserThemeColor"] == "#ff6b35"
        cd = json.loads(chrom_prefs.read_text())
        assert "user_color2" not in cd["browser"]["theme"]

        # Verify live SSE bridge broadcast + XPI endpoint + --disable reset
        port_file = base / "bridge.port"
        bridge_proc = subprocess.Popen(
            [sys.executable, str(BRIDGE), "--state-dir", str(state), "--port", "0", "--port-file", str(port_file), "--no-lock"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            for _ in range(40):
                if port_file.is_file() and port_file.read_text().strip():
                    break
                time.sleep(0.05)
            port = int(port_file.read_text().strip())

            # Check /alis-browser-theme.xpi and /install HTTP endpoints
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/alis-browser-theme.xpi", timeout=2) as r:
                assert r.status == 200
                assert "application/x-xpinstall" in r.headers.get("Content-Type", "")
                assert len(r.read()) > 500
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/install", timeout=2) as r:
                assert r.status == 200
                assert b"alis-browser-theme.xpi" in r.read()

            received_events: list[dict] = []
            stop_sse = threading.Event()

            def sse_reader() -> None:
                with urllib.request.urlopen(f"http://127.0.0.1:{port}/events", timeout=5) as stream:
                    while not stop_sse.is_set():
                        line = stream.readline().decode("utf-8")
                        if not line:
                            break
                        if line.startswith("data: "):
                            received_events.append(json.loads(line[6:].strip()))
                            if len(received_events) >= 3:
                                break

            t = threading.Thread(target=sse_reader, daemon=True)
            t.start()
            for _ in range(40):
                if len(received_events) >= 1:
                    break
                time.sleep(0.03)
            assert len(received_events) >= 1, "SSE initial frame did not arrive"
            assert received_events[0]["gecko_theme"]["colors"]["tab_line"] == "#ffb4ac"

            # Change palette to Light Teal and apply with live refresh against bridge port
            (gen / "app-palette.json").write_text(json.dumps({
                "app_background": "#f2f8f9",
                "app_surface": "#e6f1f3",
                "app_surface_elevated": "#dcebef",
                "app_surface_popup": "#d2e5ea",
                "app_surface_hover": "#c7dfe5",
                "app_foreground": "#102226",
                "app_subtext": "#3f565b",
                "app_accent": "#006876",
                "app_on_accent": "#ffffff",
                "app_accent_container": "#a1efff",
                "app_border_subtle": "#b6cdd2",
                "app_selection": "#a1efff",
                "primary": "#006876",
                "primary_container": "#a1efff",
            }), encoding="utf-8")
            (gen / "theme-meta.json").write_text(json.dumps({"mode": "light"}), encoding="utf-8")

            subprocess.run(
                [sys.executable, str(SCRIPT), "--home-dir", str(home), "--etc-dir", str(etc), "--state-dir", str(state), "--bridge-port", str(port)],
                check=True,
            )
            for _ in range(40):
                if len(received_events) >= 2:
                    break
                time.sleep(0.03)
            assert len(received_events) >= 2, "Live SSE update did not arrive"
            assert received_events[1]["enabled"] is True
            assert received_events[1]["gecko_theme"]["colors"]["tab_line"] == "#006876"
            assert received_events[1]["gecko_theme"]["properties"]["color_scheme"] == "light"

            # Verify --disable rollback restores pre-existing user files/themes cleanly AND broadcasts enabled=false
            subprocess.run(
                [sys.executable, str(SCRIPT), "--disable", "--home-dir", str(home), "--etc-dir", str(etc), "--state-dir", str(state), "--bridge-port", str(port)],
                check=True,
            )
            for _ in range(40):
                if len(received_events) >= 3:
                    break
                time.sleep(0.03)
            assert len(received_events) >= 3, "Live SSE disable event did not arrive"
            assert received_events[2]["enabled"] is False
            stop_sse.set()
        finally:
            bridge_proc.terminate()
            bridge_proc.wait(timeout=3)
        vd_after = json.loads(viv_prefs.read_text())
        assert vd_after["vivaldi"]["theme"]["schedule"]["o_s"]["dark"] == "Vivaldi2"
        assert vd_after["vivaldi"]["theme"]["schedule"]["o_s"]["light"] == "custom-teal-id"
        assert len(vd_after["vivaldi"]["themes"]["user"]) == 1
        assert vd_after["vivaldi"]["themes"]["user"][0]["id"] == "custom-teal-id"
        assert "toolbox#navigator-toolbox.chrome-block" in (zen_flatpak / "chrome/userChrome.css").read_text()
        assert "alis-theme.css" not in (zen_flatpak / "chrome/userChrome.css").read_text()
        assert not (zen_flatpak / "chrome/alis-theme.css").exists()

    print("BROWSER_THEMING_TEST=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
