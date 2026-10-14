#!/usr/bin/env python3
"""Exercise session-wide Fcitx5 setup, non-destructive migration, and tray wiring."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SESSION = ROOT / "scripts/input-method/fcitx5-session.sh"
INSTALLER = ROOT / "sdata/subcmd-install/3.files.sh"


def check(value, message):
    if not value:
        raise AssertionError(message)


def fixture(directory):
    root = Path(directory)
    bin_dir = root / "bin"
    bin_dir.mkdir()
    data = root / "fcitx-data"
    data.mkdir()
    (data / "unikey.conf").write_text("[InputMethod]\nName=Unikey\n")
    (bin_dir / "fcitx5").write_text(
        '#!/bin/bash\nprintf "started\\n" >> "$MOCK_STARTED"\n')
    (bin_dir / "pgrep").write_text("#!/bin/bash\nexit 1\n")
    (bin_dir / "systemctl").write_text(
        '#!/bin/bash\n'
        'if [[ "$1 $2" == "--user show-environment" ]]; then\n'
        '  cat "$MOCK_MANAGER_ENV"\n'
        'elif [[ "$1 $2" == "--user set-environment" ]]; then\n'
        '  shift 2\n'
        '  printf "%s\\n" "$@" >> "$MOCK_SETS"\n'
        'fi\n')
    for path in bin_dir.iterdir():
        path.chmod(0o755)
    config = root / "config"
    config.mkdir()
    manager = root / "manager.env"
    manager.write_text("")
    env = os.environ.copy()
    for key in ("QT_IM_MODULE", "XMODIFIERS"):
        env.pop(key, None)
    env.update({
        "HOME": str(root),
        "XDG_CONFIG_HOME": str(config),
        "INIR_FCITX5_DATA_DIR": str(data),
        "PATH": str(bin_dir) + os.pathsep + os.environ.get("PATH", "/usr/bin:/bin"),
        "MOCK_STARTED": str(root / "started.log"),
        "MOCK_SETS": str(root / "sets.log"),
        "MOCK_MANAGER_ENV": str(manager),
    })
    return env, root


def test_initial_install_and_existing_profile():
    with tempfile.TemporaryDirectory() as directory:
        env, root = fixture(directory)
        subprocess.run(["bash", str(SESSION)], env=env, check=True)
        profile = (root / "config/fcitx5/profile").read_text()
        check("Name=keyboard-us" in profile and "Name=unikey" in profile,
              "initial profile must include EN and Unikey")
        unikey = (root / "config/fcitx5/conf/unikey.conf").read_text()
        check("[Config]" in unikey and "InputMethod=0" in unikey
              and "OutputCharset=0" in unikey, "starter must use Unicode Telex")
        check("started" in (root / "started.log").read_text(),
              "start daemon when not already running")
        settings = (root / "sets.log").read_text()
        check("QT_IM_MODULE=fcitx" in settings and "XMODIFIERS=@im=fcitx" in settings,
              "systemd must receive IME environment")
        (root / "config/fcitx5/profile").write_text("KEEP PROFILE\n")
        (root / "config/fcitx5/conf/unikey.conf").write_text("KEEP SETTINGS\n")
        (root / "bin/pgrep").write_text("#!/bin/bash\nexit 0\n")
        subprocess.run(["bash", str(SESSION)], env=env, check=True)
        check((root / "config/fcitx5/profile").read_text() == "KEEP PROFILE\n",
              "must preserve existing profile")
        check((root / "config/fcitx5/conf/unikey.conf").read_text() == "KEEP SETTINGS\n",
              "must preserve user Unikey preferences")
        check((root / "started.log").read_text().count("started") == 1,
              "must not start another running daemon")


def test_other_ime_and_uninstalled_engine():
    with tempfile.TemporaryDirectory() as directory:
        env, root = fixture(directory)
        (root / "manager.env").write_text(
            "QT_IM_MODULE=ibus\nXMODIFIERS=@im=ibus\n")
        env.update({"QT_IM_MODULE": "ibus", "XMODIFIERS": "@im=ibus"})
        subprocess.run(["bash", str(SESSION)], env=env, check=True)
        check(not (root / "sets.log").exists(),
              "must not override another configured input method")
        (root / "config/fcitx5/profile").unlink(missing_ok=True)
        (root / "fcitx-data/unikey.conf").unlink()
        subprocess.run(["bash", str(SESSION)], env=env, check=True)
        check(not (root / "config/fcitx5/profile").exists(),
              "missing engine must not create broken profile")


def test_preserved_niri_config_migration():
    source = INSTALLER.read_text()
    start = source.index("      # A pre-existing non-Fcitx IME is user-owned")
    end = source.index("      sed -i \\\n        -e 's|spawn \"bash\"", start)
    snippet = "log_info() { :; }\n" + source[start:end]
    with tempfile.TemporaryDirectory() as directory:
        env, root = fixture(directory)
        config = root / "user-config.kdl"
        startup = root / "user-startup.kdl"
        config.write_text('environment {\n    QT_IM_MODULE "ibus"\n}\n')
        startup.write_text("// user startup\n")
        env.update({
            "NIRI_ENV_TARGET": str(config),
            "NIRI_STARTUP_TARGET": str(startup),
            "ALIS_LAUNCHER_PATH": "/opt/test/alis",
        })
        for _ in range(2):
            subprocess.run(["bash", "-e", "-c", snippet], env=env, check=True)
        data = config.read_text()
        check(data.count('QT_IM_MODULE "ibus"') == 1
              and 'QT_IM_MODULE "fcitx"' not in data,
              "migration must preserve configured IME")
        check('XMODIFIERS "@im=fcitx"' not in data,
              "migration must not mix Fcitx XIM with another configured IME")
        check("input-method" not in startup.read_text(),
              "migration must not start Fcitx when another IME is selected")
        # No configured input method: provision only missing values, once.
        config.write_text('environment {\n}\n')
        startup.write_text("// user startup\n")
        for _ in range(2):
            subprocess.run(["bash", "-e", "-c", snippet], env=env, check=True)
        data = config.read_text()
        check(data.count('QT_IM_MODULE "fcitx"') == 1
              and data.count('XMODIFIERS "@im=fcitx"') == 1,
              "migration must insert both environment variables once")
        lines = startup.read_text().splitlines()
        check(lines.count('spawn-at-startup "/opt/test/alis" "input-method" "start"') == 1,
              "migration must add exactly one path-safe startup entry")


def test_native_tray():
    service = (ROOT / "services/TrayService.qml").read_text()
    ii = (ROOT / "modules/bar/SysTray.qml").read_text()
    item = (ROOT / "modules/bar/SysTrayItem.qml").read_text()
    waffle = (ROOT / "modules/waffle/bar/tray/Tray.qml").read_text()
    check("function isFcitxItem(item)" in service and
          "root.fcitxItems.concat(" in service and
          "root.fcitxItems.concat(" in ii,
          "native Fcitx SNI must appear in both visible tray groups")
    check(ii.count("TrayService.isFcitxItem(i)") == 3 and
          "!root.isFcitxItem(i)" in service,
          "must exclude Fcitx from hidden/duplicate tray items")
    check("TrayService.isFcitxItem(root.item)" in item and
          "active: root.useMonochromeIcon" in item and
          "TrayService.pinnedItems" in waffle,
          "must reuse the theme-aware native SNI renderer")


if __name__ == "__main__":
    for test in (test_initial_install_and_existing_profile,
                 test_other_ime_and_uninstalled_engine,
                 test_preserved_niri_config_migration, test_native_tray):
        test()
        print(f"{test.__name__}: PASS")
