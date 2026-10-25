#!/usr/bin/env python3
"""MUSIC-R01 regression suite: complete SongRec retirement and legacy config migration."""
import json
import os
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]

DELETED_PATHS = [
    "services/deferred/SongRec.qml",
    "scripts/musicRecognition/recognize-music.sh",
    "modules/common/models/quickToggles/MusicRecognitionToggle.qml",
    "modules/sidebarRight/quickToggles/androidStyle/AndroidMusicRecognition.qml",
]

for rel in DELETED_PATHS:
    assert not (ROOT / rel).exists(), f"Retired file still exists: {rel}"

FORBIDDEN_IN_FILES = [
    "services/deferred/qmldir",
    "modules/common/models/quickToggles/qmldir",
    "modules/sidebarRight/quickToggles/androidStyle/qmldir",
    "modules/waffle/actionCenter/toggles/ActionCenterTogglesDelegateChooser.qml",
    "modules/sidebarRight/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml",
    "modules/sidebarRight/quickToggles/AndroidQuickPanel.qml",
    "modules/overview/SearchBar.qml",
    "services/GlobalActions.qml",
    "modules/waffle/settings/pages/WModulesPage.qml",
    "modules/settings/IntegrationsConfig.qml",
    "modules/settings/SettingsPageRegistryData.qml",
    "defaults/config.json",
    "sdata/lib/doctor.sh",
    "sdata/dist-arch/install-deps.sh",
    "sdata/dist-debian/install-deps.sh",
    "nix/package.nix",
    "distro/arch/alis-meta/PKGBUILD",
    "distro/arch/alis-shell/PKGBUILD",
    "distro/arch/alis-shell-git/PKGBUILD",
    "docs/AUDIO_MEDIA.md",
    "docs/PACKAGES.md",
    "docs/SERVICES.md",
]

for rel in FORBIDDEN_IN_FILES:
    text = (ROOT / rel).read_text(encoding="utf-8")
    for token in ("SongRec", "songrec", "musicRecognition", "recognize-music", "MusicRecognitionToggle", "AndroidMusicRecognition"):
        assert token not in text, f"{rel} still contains retired token {token!r}"

QML = r"""
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.overview
import qs.modules.sidebarRight.quickToggles
import qs.modules.waffle.actionCenter.mainPage

Window {
    id: root
    visible: true
    width: 640
    height: 480

    AndroidQuickPanel {
        id: androidPanel
        width: 360
        height: 240
    }

    MainPageBodyToggles {
        id: waffleToggles
        width: 360
        height: 200
    }

    SearchBar {
        id: searchBar
    }

    TestCase {
        id: test
        when: false
        optional: true
        function check(ok, msg) {
            if (!ok) throw new Error(msg)
        }
        function run() {
            try {
                tryCompare(Config, "ready", true, 4000)
                wait(80)
                const androidList = Config.options?.sidebar?.quickToggles?.android?.toggles ?? []
                check(androidList.length === 2, "android toggles length mismatch: " + JSON.stringify(androidList))
                check(androidList[0].type === "network" && androidList[0].size === 2, "first android toggle lost order/size")
                check(androidList[1].type === "bluetooth" && androidList[1].size === 2, "second android toggle lost order/size")
                check(!androidPanel.availableToggleTypes.includes("musicRecognition"), "AndroidQuickPanel still lists musicRecognition")
                check(!androidPanel.unusedToggles.some(t => t.type === "musicRecognition"), "AndroidQuickPanel unusedToggles includes musicRecognition")

                const waffleList = Config.options?.waffles?.actionCenter?.toggles ?? []
                check(waffleList.length === 2 && waffleList[0] === "network" && waffleList[1] === "bluetooth",
                      "waffle toggles did not strip musicRecognition cleanly: " + JSON.stringify(waffleList))
                check(waffleToggles.toggles.length === 2 && !waffleToggles.toggles.includes("musicRecognition"),
                      "MainPageBodyToggles retained musicRecognition")

                check(!GlobalActions.allActions.some(a => a.id === "music-recognition"),
                      "GlobalActions still exposes music-recognition")
                check(Config.options?.media?.filterDuplicatePlayers === false,
                      "unrelated media config was altered")

                Config.flushWrites()
                wait(150)
                console.info("MUSIC_R01_RUNTIME_PASS")
            } catch (e) {
                console.error("MUSIC_R01_RUNTIME_FAIL", e.message, e.stack)
            }
            Qt.quit()
        }
    }

    Timer {
        interval: 100
        running: true
        onTriggered: test.run()
    }
}
"""

with tempfile.TemporaryDirectory(prefix="alis-music-r01-") as tmp:
    folder = Path(tmp)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations", "settings.qml", "waffleSettings.qml"]:
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "shell.qml").write_text(QML, encoding="utf-8")

    with private_wayland(folder) as env:
        if env is None:
            print("MUSIC_R01_STATIC_PASS (native session skipped)")
            raise SystemExit(0)
        conf_dir = folder / "config" / "alis"
        conf_dir.mkdir(parents=True, exist_ok=True)
        legacy_cfg = json.loads((ROOT / "defaults" / "config.json").read_text(encoding="utf-8"))
        legacy_cfg["musicRecognition"] = {"interval": 6, "timeout": 20}
        legacy_cfg["media"]["filterDuplicatePlayers"] = False
        legacy_cfg["sidebar"]["quickToggles"]["android"]["toggles"] = [
            {"type": "network", "size": 2},
            {"type": "musicRecognition", "size": 1},
            {"type": "bluetooth", "size": 2},
        ]
        legacy_cfg["waffles"]["actionCenter"]["toggles"] = [
            "network",
            "musicRecognition",
            "bluetooth",
        ]
        cfg_file = conf_dir / "config.json"
        cfg_file.write_text(json.dumps(legacy_cfg, indent=2), encoding="utf-8")

        env.update(QT_QUICK_BACKEND="software")
        res = run_qs(folder, env, timeout=30)
        out = res.stdout
        if res.returncode != 0 or "MUSIC_R01_RUNTIME_PASS" not in out or "MUSIC_R01_RUNTIME_FAIL" in out:
            print(out)
            raise SystemExit(1)

    saved = json.loads(cfg_file.read_text(encoding="utf-8"))
    assert "musicRecognition" not in saved, "musicRecognition top-level key was not removed on save"
    assert [t["type"] for t in saved["sidebar"]["quickToggles"]["android"]["toggles"]] == ["network", "bluetooth"]
    assert list(saved["waffles"]["actionCenter"]["toggles"]) == ["network", "bluetooth"]
    assert saved["media"]["filterDuplicatePlayers"] is False

print("MUSIC_R01_PASS complete retirement and legacy config migration verified")
