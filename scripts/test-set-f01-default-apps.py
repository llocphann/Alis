#!/usr/bin/env python3
"""SET-F01 regression & runtime suite: Default Applications settings with Native + Flatpak/Flathub discovery."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path

from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts" / "default_apps_helper.py"


def _write_desktop(directory: Path, filename: str, content: str) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / filename
    path.write_text(content.strip() + "\n", encoding="utf-8")
    return path


def _make_executable(directory: Path, name: str, script: str = "#!/usr/bin/env bash\nexit 0\n") -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / name
    path.write_text(script, encoding="utf-8")
    path.chmod(0o755)
    return path


def test_discovery_matrix() -> None:
    with tempfile.TemporaryDirectory(prefix="alis-set-f01-discover-") as tmp:
        root = Path(tmp)
        bin_dir = root / "bin"
        native_apps = root / "xdg" / "applications"
        user_fp_root = root / "user-flatpak"
        user_fp_apps = user_fp_root / "exports" / "share" / "applications"
        sys_fp_root = root / "system-flatpak"
        sys_fp_apps = sys_fp_root / "exports" / "share" / "applications"

        for tool in ("kitty", "firefox", "zed", "nautilus", "pavucontrol", "flatpak", "xdg-open"):
            _make_executable(bin_dir, tool)

        # Native .desktop entries (including a duplicate Firefox and a stale entry whose binary is missing)
        _write_desktop(
            native_apps,
            "kitty.desktop",
            """
            [Desktop Entry]
            Type=Application
            Name=Kitty
            Exec=kitty
            Icon=kitty
            Categories=System;TerminalEmulator;
            """,
        )
        _write_desktop(
            native_apps,
            "firefox.desktop",
            """
            [Desktop Entry]
            Type=Application
            Name=Firefox
            Exec=firefox %u
            Icon=firefox
            Categories=Network;WebBrowser;
            MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
            """,
        )
        _write_desktop(
            native_apps,
            "dev.zed.Zed.desktop",
            """
            [Desktop Entry]
            Type=Application
            Name=Zed
            Exec=zed %U
            Icon=zed
            Categories=Development;TextEditor;IDE;
            MimeType=text/plain;
            """,
        )
        _write_desktop(
            native_apps,
            "org.gnome.Nautilus.desktop",
            """
            [Desktop Entry]
            Type=Application
            Name=Files
            Exec=nautilus --new-window %U
            Icon=org.gnome.Nautilus
            Categories=System;FileTools;FileManager;
            MimeType=inode/directory;
            """,
        )
        _write_desktop(
            native_apps,
            "stale-editor.desktop",
            """
            [Desktop Entry]
            Type=Application
            Name=Stale Missing Binary Editor
            Exec=nonexistent-editor-binary-xyz %F
            Categories=Utility;TextEditor;
            MimeType=text/plain;
            """,
        )

        # User Flatpak: Firefox from Flathub + uninstalled Flatpak entry
        _write_desktop(
            user_fp_apps,
            "org.mozilla.firefox.desktop",
            """
            [Desktop Entry]
            Type=Application
            Name=Firefox
            Exec=/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=firefox --file-forwarding org.mozilla.firefox @@u %u @@
            Icon=org.mozilla.firefox
            Categories=Network;WebBrowser;
            MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
            X-Flatpak=org.mozilla.firefox
            """,
        )
        _write_desktop(
            user_fp_apps,
            "org.example.UninstalledBrowser.desktop",
            """
            [Desktop Entry]
            Type=Application
            Name=Ghost Flatpak Browser
            Exec=flatpak run org.example.UninstalledBrowser
            Categories=Network;WebBrowser;
            X-Flatpak=org.example.UninstalledBrowser
            """,
        )

        # System Flatpak: Zen Browser from custom 'fedora' remote
        _write_desktop(
            sys_fp_apps,
            "app.zen_browser.zen.desktop",
            """
            [Desktop Entry]
            Type=Application
            Name=Zen Browser
            Exec=flatpak run app.zen_browser.zen %u
            Icon=app.zen_browser.zen
            Categories=Network;WebBrowser;
            MimeType=x-scheme-handler/http;x-scheme-handler/https;
            X-Flatpak=app.zen_browser.zen
            """,
        )

        flatpak_meta = root / "flatpak-list.json"
        flatpak_meta.write_text(
            json.dumps(
                [
                    {
                        "appId": "org.mozilla.firefox",
                        "origin": "flathub",
                        "installation": "user",
                        "name": "Firefox",
                    },
                    {
                        "appId": "app.zen_browser.zen",
                        "origin": "fedora",
                        "installation": "system",
                        "name": "Zen Browser",
                    },
                ]
            ),
            encoding="utf-8",
        )

        env = os.environ.copy()
        env.update(
            {
                "ALIS_DEFAULT_APPS_PATH": str(bin_dir),
                "ALIS_DEFAULT_APPS_XDG_DIRS": str(native_apps),
                "ALIS_DEFAULT_APPS_USER_FLATPAK_DIR": str(user_fp_apps),
                "ALIS_DEFAULT_APPS_SYSTEM_FLATPAK_DIR": str(sys_fp_apps),
                "ALIS_DEFAULT_APPS_FLATPAK_LIST_JSON": str(flatpak_meta),
            }
        )

        out = subprocess.check_output([str(HELPER), "discover"], env=env, text=True)
        payload = json.loads(out)
        assert payload["toolsAvailable"]["flatpak"] is True
        apps = payload["apps"]
        by_id = {app["desktopId"]: app for app in apps}

        # Stale native & uninstalled Flatpak must be filtered out
        assert "stale-editor.desktop" not in by_id, "stale native .desktop must be ignored"
        assert "org.example.UninstalledBrowser.desktop" not in by_id, "uninstalled Flatpak must be ignored"

        # Duplicate Firefox: Native vs User Flatpak (Flathub)
        assert "firefox.desktop" in by_id
        assert "org.mozilla.firefox.desktop" in by_id
        native_ff = by_id["firefox.desktop"]
        flatpak_ff = by_id["org.mozilla.firefox.desktop"]
        assert native_ff["isFlatpak"] is False
        assert native_ff["sourceBadge"] == "Native"
        assert native_ff["exec"] == "firefox"

        assert flatpak_ff["isFlatpak"] is True
        assert flatpak_ff["origin"] == "flathub"
        assert flatpak_ff["installation"] == "user"
        assert flatpak_ff["sourceBadge"] == "Flatpak · Flathub"
        assert flatpak_ff["exec"] == "flatpak run --user org.mozilla.firefox"

        # System Flatpak with non-Flathub remote ('fedora')
        zen = by_id["app.zen_browser.zen.desktop"]
        assert zen["isFlatpak"] is True
        assert zen["origin"] == "fedora"
        assert zen["installation"] == "system"
        assert zen["sourceBadge"] == "Flatpak · fedora"
        assert zen["exec"] == "flatpak run app.zen_browser.zen"

        # Slot categorization
        assert "terminal" in by_id["kitty.desktop"]["slots"]
        assert "browser" in native_ff["slots"] and "browser" in flatpak_ff["slots"]
        assert "editor" in by_id["dev.zed.Zed.desktop"]["slots"]
        assert "fileManager" in by_id["org.gnome.Nautilus.desktop"]["slots"]

        # Empty dirs + missing Flatpak CLI tool
        empty_dir = root / "empty-apps"
        empty_dir.mkdir()
        env_no_fp = env.copy()
        env_no_fp.update(
            {
                "ALIS_DEFAULT_APPS_XDG_DIRS": str(empty_dir),
                "ALIS_DEFAULT_APPS_USER_FLATPAK_DIR": str(empty_dir),
                "ALIS_DEFAULT_APPS_SYSTEM_FLATPAK_DIR": str(empty_dir),
                "ALIS_DEFAULT_APPS_DISABLE_FLATPAK_CLI": "1",
            }
        )
        empty_payload = json.loads(subprocess.check_output([str(HELPER), "discover"], env=env_no_fp, text=True))
        assert empty_payload["toolsAvailable"]["flatpak"] is False
        assert empty_payload["apps"] == []

        # Launch resolution across native, user Flatpak, system Flatpak, custom command with spaces, and fallback
        cfg_path = root / "config.json"

        # 1. User Flatpak browser via desktopIds
        cfg_path.write_text(
            json.dumps(
                {
                    "apps": {
                        "browser": "flatpak run --user org.mozilla.firefox",
                        "desktopIds": {"browser": "flatpak:user:org.mozilla.firefox"},
                    }
                }
            ),
            encoding="utf-8",
        )
        resolved = json.loads(
            subprocess.check_output(
                [str(HELPER), "resolve-launch", "browser", str(cfg_path), "--", "https://example.com"],
                env=env,
                text=True,
            )
        )
        assert resolved["ok"] is True
        assert resolved["argv"] == ["flatpak", "run", "--user", "org.mozilla.firefox", "https://example.com"]

        # 2. Custom command with spaces and quoted args
        cfg_path.write_text(
            json.dumps(
                {
                    "apps": {
                        "editor": 'zed --new "/tmp/my file with spaces.txt"',
                        "desktopIds": {"editor": ""},
                    }
                }
            ),
            encoding="utf-8",
        )
        resolved_custom = json.loads(
            subprocess.check_output(
                [str(HELPER), "resolve-launch", "editor", str(cfg_path), "--", "/tmp/second.txt"],
                env=env,
                text=True,
            )
        )
        assert resolved_custom["ok"] is True
        assert resolved_custom["argv"] == ["zed", "--new", "/tmp/my file with spaces.txt", "/tmp/second.txt"]

        # 3. Uninstalled/stale desktopId + missing binary falls back to xdg-open / installed fallback
        cfg_path.write_text(
            json.dumps(
                {
                    "apps": {
                        "browser": "nonexistent-browser-xyz",
                        "desktopIds": {"browser": "org.example.UninstalledBrowser.desktop"},
                    }
                }
            ),
            encoding="utf-8",
        )
        resolved_fallback = json.loads(
            subprocess.check_output(
                [str(HELPER), "resolve-launch", "browser", str(cfg_path), "--", "https://alis.local"],
                env=env,
                text=True,
            )
        )
        assert resolved_fallback["ok"] is True
        assert resolved_fallback["argv"][0] in ("firefox", "xdg-open")

        # 4. launch-terminal.sh and scripts/alis with ALIS_LAUNCH_DRY_RUN=1
        xdg_cfg_dir = root / "xdg-cfg" / "alis"
        xdg_cfg_dir.mkdir(parents=True, exist_ok=True)
        (xdg_cfg_dir / "config.json").write_text(
            json.dumps(
                {
                    "apps": {
                        "terminal": "kitty",
                        "fileManager": "nautilus --new-window",
                        "desktopIds": {
                            "terminal": "native:kitty.desktop",
                            "fileManager": "native:org.gnome.Nautilus.desktop",
                        },
                    }
                }
            ),
            encoding="utf-8",
        )
        env_cli = env.copy()
        env_cli["XDG_CONFIG_HOME"] = str(root / "xdg-cfg")
        env_cli["ALIS_LAUNCH_DRY_RUN"] = "1"
        term_res = json.loads(
            subprocess.check_output(
                ["bash", str(ROOT / "scripts" / "launch-terminal.sh"), "-e", "htop"],
                env=env_cli,
                text=True,
            )
        )
        assert term_res["argv"] == ["kitty", "-e", "htop"], term_res

        files_res = json.loads(
            subprocess.check_output(
                ["bash", str(ROOT / "scripts" / "alis"), "files", "/tmp"],
                env=env_cli,
                text=True,
            )
        )
        assert files_res["argv"] == ["nautilus", "--new-window", "/tmp"], files_res


def test_manual_xdg_sync() -> None:
    with tempfile.TemporaryDirectory(prefix="alis-set-f01-xdg-") as tmp:
        root = Path(tmp)
        bin_dir = root / "bin"
        native_apps = root / "xdg" / "applications"
        state_file = root / "xdg-state.json"
        state_file.write_text(json.dumps({"default-web-browser": "firefox.desktop", "mimes": {}}), encoding="utf-8")

        _make_executable(bin_dir, "firefox")
        _make_executable(bin_dir, "nautilus")
        _make_executable(bin_dir, "zed")

        _write_desktop(
            native_apps,
            "firefox.desktop",
            "[Desktop Entry]\nType=Application\nName=Firefox\nExec=firefox\nCategories=Network;WebBrowser;\n",
        )
        _write_desktop(
            native_apps,
            "org.gnome.Nautilus.desktop",
            "[Desktop Entry]\nType=Application\nName=Files\nExec=nautilus\nCategories=System;FileManager;\n",
        )

        # Mock xdg-settings and xdg-mime that persist to state_file (with optional simulated mismatch)
        _make_executable(
            bin_dir,
            "xdg-settings",
            f"""#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
state_path = Path({json.dumps(str(state_file))})
data = json.loads(state_path.read_text())
if sys.argv[1:3] == ["get", "default-web-browser"]:
    print(data.get("default-web-browser", ""))
    sys.exit(0)
if sys.argv[1:3] == ["set", "default-web-browser"] and len(sys.argv) >= 4:
    if os.environ.get("MOCK_XDG_IGNORE_SET") != "1":
        data["default-web-browser"] = sys.argv[3]
        state_path.write_text(json.dumps(data))
    sys.exit(0)
sys.exit(1)
""",
        )
        _make_executable(
            bin_dir,
            "xdg-mime",
            f"""#!/usr/bin/env python3
import json, sys
from pathlib import Path
state_path = Path({json.dumps(str(state_file))})
data = json.loads(state_path.read_text())
if sys.argv[1:3] == ["query", "default"] and len(sys.argv) >= 4:
    print(data.get("mimes", {{}}).get(sys.argv[3], ""))
    sys.exit(0)
if sys.argv[1] == "default" and len(sys.argv) >= 4:
    desk = sys.argv[2]
    for mime in sys.argv[3:]:
        data.setdefault("mimes", {{}})[mime] = desk
    state_path.write_text(json.dumps(data))
    sys.exit(0)
sys.exit(1)
""",
        )

        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{bin_dir}:{env.get('PATH', '')}",
                "ALIS_DEFAULT_APPS_PATH": str(bin_dir),
                "ALIS_DEFAULT_APPS_XDG_DIRS": str(native_apps),
                "ALIS_DEFAULT_APPS_USER_FLATPAK_DIR": str(root / "none1"),
                "ALIS_DEFAULT_APPS_SYSTEM_FLATPAK_DIR": str(root / "none2"),
                "ALIS_DEFAULT_APPS_DISABLE_FLATPAK_CLI": "1",
            }
        )

        # 1. Invalid/uninstalled desktop ID is rejected without mutating XDG state
        bad_res = json.loads(
            subprocess.run(
                [str(HELPER), "apply-xdg", "browser", "missing-browser.desktop"],
                env=env,
                text=True,
                capture_output=True,
            ).stdout
        )
        assert bad_res["ok"] is False

        # 2. Explicit apply-xdg for browser succeeds and verifies readback
        ok_res = json.loads(
            subprocess.check_output([str(HELPER), "apply-xdg", "browser", "firefox.desktop"], env=env, text=True)
        )
        assert ok_res["ok"] is True
        assert ok_res["readback"]["effectiveDesktopId"] == "firefox.desktop"

        # 3. Simulated readback failure when xdg-settings refuses to update
        env_fail = env.copy()
        env_fail["MOCK_XDG_IGNORE_SET"] = "1"
        state_file.write_text(json.dumps({"default-web-browser": "other.desktop", "mimes": {}}), encoding="utf-8")
        fail_res = json.loads(
            subprocess.run(
                [str(HELPER), "apply-xdg", "browser", "firefox.desktop"],
                env=env_fail,
                text=True,
                capture_output=True,
            ).stdout
        )
        assert fail_res["ok"] is False
        assert "Readback mismatch" in fail_res["error"]


def test_legacy_migration_and_deeplinks() -> None:
    policy_js = (ROOT / "modules" / "common" / "PanelFamilyPolicy.js").read_text(encoding="utf-8")
    registry_qml = (ROOT / "modules" / "settings" / "SettingsPageRegistry.qml").read_text(encoding="utf-8")
    subprocess.run(
        [
            "node",
            "-e",
            policy_js
            + r"""
const assert = require('node:assert/strict');
// Legacy config with only apps.fileExplorer
const legacy = { apps: { terminal: 'foot', fileExplorer: 'thunar', browser: 'firefox' } };
const m1 = migrateDefaultApps(legacy);
assert.equal(m1['apps.fileManager'], 'thunar');
// Idempotent on second pass after applying migration
legacy.apps.fileManager = m1['apps.fileManager'];
const m2 = migrateDefaultApps(legacy);
assert.equal(Object.keys(m2).length, 0);
""",
        ],
        check=True,
    )

    # Verify legacy deep links ("compositor"/"Applications" and "modules"/"Default Terminal") route to default-apps (39)
    subprocess.run(
        [
            "node",
            "-e",
            r"""
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const source = fs.readFileSync(process.argv[1], 'utf8');
const body = source.match(/function navigateToKey\([^)]*\):\s*bool\s*\{([\s\S]*?)\n    \}/)[1];
const events = [];
const root = {
    abyssFamily: true,
    pageIndexForKey: key => ({'default-apps': 39, compositor: 12, modules: 10, integrations: 38}[key] ?? -1),
    navigateRequested: (...args) => events.push(args)
};
const policy = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[2], 'utf8').replace(/^\.pragma library\s*$/m, ''), policy);
const ctx = vm.createContext({root, FamilyPolicy: policy, Config: {options: {panelFamily: 'abyss'}}});
const navigate = vm.runInContext('(function(key, section){' + body + '})', ctx);

assert.equal(navigate('compositor', 'Applications'), true);
assert.deepEqual(events.pop(), [39, '']);
assert.equal(navigate('compositor', 'Default applications'), true);
assert.deepEqual(events.pop(), [39, '']);
assert.equal(navigate('modules', 'Terminal'), true);
assert.deepEqual(events.pop(), [39, '']);
assert.equal(navigate('modules', 'Default Terminal'), true);
assert.deepEqual(events.pop(), [39, '']);
assert.equal(navigate('compositor', 'Displays'), true);
assert.deepEqual(events.pop(), [12, 'Displays']);
""",
            str(ROOT / "modules" / "settings" / "SettingsPageRegistry.qml"),
            str(ROOT / "modules" / "common" / "PanelFamilyPolicy.js"),
        ],
        check=True,
    )


def test_quickshell_runtime_default_apps() -> None:
    with tempfile.TemporaryDirectory(prefix="alis-set-f01-runtime-") as tmp:
        folder = Path(tmp)
        bin_dir = folder / "bin"
        native_apps = folder / "xdg" / "applications"
        user_fp_apps = folder / "user-flatpak" / "exports" / "share" / "applications"

        for tool in ("kitty", "firefox", "zed", "nautilus", "flatpak"):
            _make_executable(bin_dir, tool)

        _write_desktop(
            native_apps,
            "firefox.desktop",
            "[Desktop Entry]\nType=Application\nName=Firefox\nExec=firefox %u\nCategories=Network;WebBrowser;\n",
        )
        _write_desktop(
            user_fp_apps,
            "org.mozilla.firefox.desktop",
            "[Desktop Entry]\nType=Application\nName=Firefox\nExec=flatpak run org.mozilla.firefox %u\nCategories=Network;WebBrowser;\nX-Flatpak=org.mozilla.firefox\n",
        )
        flatpak_meta = folder / "flatpak-list.json"
        flatpak_meta.write_text(
            json.dumps(
                [
                    {
                        "appId": "org.mozilla.firefox",
                        "origin": "flathub",
                        "installation": "user",
                        "name": "Firefox",
                    }
                ]
            ),
            encoding="utf-8",
        )

        for entry in [
            "modules",
            "services",
            "GlobalStates.qml",
            "qmldir",
            "assets",
            "scripts",
            "defaults",
            "translations",
            "settings.qml",
            "waffleSettings.qml",
        ]:
            (folder / entry).symlink_to(ROOT / entry)

        (folder / "shell.qml").write_text(
            """import QtQuick
import Quickshell
import qs.modules.common
import qs.services
import qs.modules.settings

Scope {
    id: root
    DefaultAppsConfig {
        id: page
        width: 920
        height: 720
    }
    Timer {
        interval: 400
        running: true
        repeat: true
        property int ticks: 0
        onTriggered: {
            ticks += 1
            if (!Config.ready || AppLauncher.discovering || AppLauncher.discoveredApps.length < 2) {
                if (ticks > 25) {
                    console.error("SET_F01_TIMEOUT", Config.ready, AppLauncher.discovering, AppLauncher.discoveredApps.length)
                    Qt.quit()
                }
                return
            }
            if (Config.options.apps.fileManager !== "thunar") {
                console.error("SET_F01_MIGRATION_FAIL", Config.options.apps.fileManager)
                Qt.quit()
                return
            }
            const browserCandidates = AppLauncher.candidatesForSlot("browser")
            const nativeApp = browserCandidates.find(c => c.desktopId === "firefox.desktop" && !c.isFlatpak)
            const flatpakApp = browserCandidates.find(c => c.desktopId === "org.mozilla.firefox.desktop" && c.isFlatpak && c.origin === "flathub")
            if (!nativeApp || !flatpakApp) {
                console.error("SET_F01_CANDIDATES_FAIL", JSON.stringify(browserCandidates))
                Qt.quit()
                return
            }
            AppLauncher.selectDiscoveredApp("browser", flatpakApp)
            AppLauncher.setCustomCommand("editor", "zed --new")
            Config.flushWrites()
            console.log("SET_F01_RUNTIME_PASS",
                Config.options.apps.browser,
                Config.options.apps.desktopIds.browser,
                Config.options.apps.editor)
            Qt.quit()
        }
    }
}
""",
            encoding="utf-8",
        )

        with private_wayland(folder) as env:
            if env is None:
                print("SET_F01_RUNTIME_SKIPPED (no private_wayland)")
                return
            conf_dir = folder / "config" / "alis"
            conf_dir.mkdir(parents=True, exist_ok=True)
            legacy_cfg = json.loads((ROOT / "defaults" / "config.json").read_text(encoding="utf-8"))
            legacy_cfg["panelFamily"] = "abyss"
            legacy_cfg["apps"] = {
                "terminal": "kitty",
                "browser": "firefox",
                "fileExplorer": "thunar",
            }
            cfg_file = conf_dir / "config.json"
            cfg_file.write_text(json.dumps(legacy_cfg, indent=2), encoding="utf-8")

            env.update(
                {
                    "QT_QUICK_BACKEND": "software",
                    "ALIS_DEFAULT_APPS_PATH": str(bin_dir),
                    "ALIS_DEFAULT_APPS_XDG_DIRS": str(native_apps),
                    "ALIS_DEFAULT_APPS_USER_FLATPAK_DIR": str(user_fp_apps),
                    "ALIS_DEFAULT_APPS_SYSTEM_FLATPAK_DIR": str(folder / "no-sys-fp"),
                    "ALIS_DEFAULT_APPS_FLATPAK_LIST_JSON": str(flatpak_meta),
                }
            )
            res = run_qs(folder, env, timeout=25)
            out = res.stdout or ""
            if res.returncode != 0 or "SET_F01_RUNTIME_PASS flatpak run --user org.mozilla.firefox flatpak:user:org.mozilla.firefox zed --new" not in out:
                print(out)
                raise SystemExit(1)

        saved = json.loads(cfg_file.read_text(encoding="utf-8"))
        assert saved["apps"]["browser"] == "flatpak run --user org.mozilla.firefox"
        assert saved["apps"]["desktopIds"]["browser"] == "flatpak:user:org.mozilla.firefox"
        assert saved["apps"]["editor"] == "zed --new"
        assert saved["apps"]["fileManager"] == "thunar"
        assert saved["apps"]["fileExplorer"] == "thunar"


def main() -> None:
    test_discovery_matrix()
    test_manual_xdg_sync()
    test_legacy_migration_and_deeplinks()
    test_quickshell_runtime_default_apps()
    print("SET_F01_PASS discovery, launch resolution, manual XDG sync, legacy migration and Quickshell runtime verified")


if __name__ == "__main__":
    main()
