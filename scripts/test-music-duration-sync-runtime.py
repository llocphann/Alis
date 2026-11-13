#!/usr/bin/env python3
"""Regression tests for music duration resolution, track-switch anti-staleness, and lyrics position sync."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile

from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]


def test_python_mpd_duration_and_stop_fallback() -> None:
    spec = importlib.util.spec_from_file_location("local_music_mpd", ROOT / "scripts/local_music_mpd.py")
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    assert mod._duration_number({"duration": "198.545"}) == 198.545
    assert mod._duration_number({"time": "113:199"}) == 199.0
    assert mod._duration_number({"time": "42"}) == 42.0
    assert mod._duration_number({"duration": "0", "time": "0:245"}) == 245.0

    class FakeMpdClient:
        def command(self, name, *args):
            if name == "status":
                return ["state: stop", "song: 1", "songid: 22", "volume: 80"]
            if name == "currentsong":
                return []
            if name == "playlistinfo":
                return [
                    "file: a.flac", "Title: Lạc", "Artist: Ha Anh Tuan", "Duration: 286.0",
                    "file: b.flac", "Title: Hồn Lỡ Sa Vào", "Artist: Binz", "Duration: 198.545",
                ]
            return []

    payload = mod._status_payload(FakeMpdClient(), "")
    assert payload["current"] is not None, "stopped MPD status should still resolve current from playlistinfo"
    assert payload["current"]["title"] == "Hồn Lỡ Sa Vào", payload["current"]
    assert payload["current"]["duration"] == 198.545, payload["current"]
    assert abs(float(payload["status"]["duration"]) - 198.545) < 0.001, payload["status"]


def test_qml_duration_and_transition_runtime() -> None:
    with tempfile.TemporaryDirectory(prefix="alis-music-duration-sync-") as name:
        shell = Path(name)

        def write(rel: str, text: str) -> None:
            target = shell / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)

        write("qmldir", "module qs\nsingleton GlobalStates 1.0 GlobalStates.qml\nsingleton Translation 1.0 Translation.qml\n")
        write("GlobalStates.qml", '''pragma Singleton
import QtQuick
QtObject {
    property bool dashboardOpen: false
    property bool overviewOpen: false
    property string overviewMode: "dashboard"
    property int dashboardPage: 1
    property bool sidebarLeftOpen: false
    property bool screenLocked: false
}
''')
        write("Translation.qml", '''pragma Singleton
import QtQuick
QtObject {
    function tr(s) { return String(s ?? "") }
}
''')
        write("services/qmldir", '''module qs.services
singleton LocalMusic 1.0 LocalMusic.qml
singleton MprisController 1.0 MprisController.qml
singleton Audio 1.0 Audio.qml
singleton CompositorService 1.0 CompositorService.qml
singleton NiriService 1.0 NiriService.qml
''')
        write("services/Audio.qml", "pragma Singleton\nimport QtQuick\nQtObject { property var outputAppNodes: [] }\n")
        write("services/CompositorService.qml", "pragma Singleton\nimport QtQuick\nQtObject { property bool isNiri: false }\n")
        write("services/NiriService.qml", "pragma Singleton\nimport QtQuick\nQtObject { property var windows: []; property var activeWindow: null }\n")

        local_src = (ROOT / "services/LocalMusic.qml").read_text()
        mpris_src = (ROOT / "services/MprisController.qml").read_text()
        # Test-only typing relaxation so mock QML players can be passed to mpdPlayer without live D-Bus.
        mpris_src = mpris_src.replace("property MprisPlayer mpdPlayer: null", "property var mpdPlayer: null")
        write("services/LocalMusic.qml", local_src)
        write("services/MprisController.qml", mpris_src)

        write("modules/common/qmldir", '''module qs.modules.common
singleton Config 1.0 Config.qml
singleton Directories 1.0 Directories.qml
singleton AppSearch 1.0 AppSearch.qml
''')
        write("modules/common/Config.qml", '''pragma Singleton
import QtQuick
QtObject {
    signal configChanged()
    property bool ready: true
    property var options: ({
        dashboard: { music: { enable: true } },
        sidebar: { music: { mpdHost: "fixture.invalid", mpdPort: 6600, libraryFolder: "" } },
        music: { mprisPriorities: [] }
    })
}
''')
        write("modules/common/Directories.qml", '''pragma Singleton
import QtQuick
import Quickshell
QtObject {
    readonly property string scriptsPath: Quickshell.env("FIXTURE_ROOT") + "/bin"
    readonly property string stateUserPath: Quickshell.env("FIXTURE_ROOT") + "/state"
    readonly property string music: Quickshell.env("FIXTURE_ROOT") + "/music"
}
''')
        write("modules/common/AppSearch.qml", '''pragma Singleton
import QtQuick
QtObject {
    function lookupDesktopEntry(_) { return null }
    function guessIcon(_) { return "" }
    function iconExists(_) { return false }
}
''')
        write("modules/common/functions/qmldir", '''module qs.modules.common.functions
singleton FileUtils 1.0 FileUtils.qml
singleton StringUtils 1.0 StringUtils.qml
''')
        write("modules/common/functions/FileUtils.qml", r'''pragma Singleton
import QtQuick
QtObject { function trimFileProtocol(value) { return String(value ?? "").replace(/^file:\/\//, "") } }
''')
        write("modules/common/functions/StringUtils.qml", (ROOT / "modules/common/functions/StringUtils.qml").read_text())

        write("bin/native-dispatch", r'''#!/usr/bin/python3
import json, sys
if sys.argv[1:] == ["backend-info"]:
    print("mode=python\nalis-mpdd=missing")
else:
    print(json.dumps({"connected": True, "tracks": [], "queue": [], "playlists": [], "status": {"state": "stop"}}))
''')
        (shell / "bin/native-dispatch").chmod(0o755)
        (shell / "state").mkdir()
        (shell / "music").mkdir()

        write("shell.qml", '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.services

ShellRoot {
    id: root
    TestCase {
        id: test
        name: "MusicDurationSyncRuntime"
        when: false
        optional: true

        function check(cond, msg) {
            if (!cond)
                throw new Error(msg)
        }

        function _makePlayer(dbusName, title, artist, url, len, pos, playing) {
            return Qt.createQmlObject(`
                import QtQuick
                QtObject {
                    property string dbusName: ${JSON.stringify(dbusName)}
                    property string identity: ${JSON.stringify(dbusName)}
                    property int uniqueId: 1
                    property string trackTitle: ${JSON.stringify(title)}
                    property string trackArtist: ${JSON.stringify(artist)}
                    property string trackAlbum: ""
                    property string trackArtUrl: ""
                    property var metadata: ({"xesam:url": ${JSON.stringify(url)}})
                    property bool lengthSupported: ${len > 0 ? "true" : "false"}
                    property real length: ${len}
                    property real position: ${pos}
                    property bool isPlaying: ${playing ? "true" : "false"}
                    property bool canSeek: true
                    property bool canTogglePlaying: false
                    property bool canGoNext: false
                    property bool canGoPrevious: false
                    function togglePlaying() {}
                    function seek(_) {}
                }
            `, root)
        }

        function runChecks() {
            try {
                // 1. Cold boot in pause/stop while mpd-mpris reports 0 length & 0 position
                const mpdMock = _makePlayer(
                    "org.mpris.MediaPlayer2.mpd",
                    "Hồn Lỡ Sa Vào",
                    "Binz",
                    "file:///music/Binz/hon-lo-sa-vao.flac",
                    0,
                    0,
                    false
                )
                // Ensure LocalMusic singleton initializes before binding mock mpdPlayer.
                check(LocalMusic.enabled, "LocalMusic fixture not enabled")
                MprisController.mpdPlayer = mpdMock
                check(MprisController.mpdPlayer === mpdMock, "Failed to assign mpdMock")

                LocalMusic._applyPayload({
                    connected: true,
                    status: { state: "pause", song: 0, songid: 10, elapsed: 83.4, duration: 198.545, volume: 80 },
                    queue: [
                        { uri: "Binz/hon-lo-sa-vao.flac", path: "/music/Binz/hon-lo-sa-vao.flac", title: "Hồn Lỡ Sa Vào", artist: "Binz", album: "Dan Ca", art: "", duration: 198.545 },
                        { uri: "HaAnhTuan/lac.flac", path: "/music/HaAnhTuan/lac.flac", title: "Lạc", artist: "Ha Anh Tuan", album: "Fragile", art: "", duration: 286.0 },
                        { uri: "Unknown/nodur.flac", path: "/music/Unknown/nodur.flac", title: "NoDur", artist: "X", album: "", art: "", duration: 0 }
                    ],
                    current: { uri: "Binz/hon-lo-sa-vao.flac", path: "/music/Binz/hon-lo-sa-vao.flac", title: "Hồn Lỡ Sa Vào", artist: "Binz", album: "Dan Ca", art: "", duration: 198.545 }
                }, false)

                check(Math.abs(LocalMusic.currentDuration - 198.545) < 0.01, "Cold boot paused duration lost: " + LocalMusic.currentDuration)
                check(Math.abs(LocalMusic.lyricsPosition - 83.4) < 0.1, "Cold boot paused lyrics position lost: " + LocalMusic.lyricsPosition)
                const effLen1 = MprisController.effectiveLengthForPlayer(mpdMock)
                check(Math.abs(effLen1 - 198.545) < 0.01, "effectiveLengthForPlayer ignored LocalMusic duration: effLen1=" + effLen1 + " same=" + (MprisController.mpdPlayer === mpdMock) + " localDur=" + LocalMusic.currentDuration)
                check(Math.abs(MprisController.effectivePositionForPlayer(mpdMock) - 83.4) < 0.1, "effectivePositionForPlayer ignored LocalMusic position")

                // 2. Switch to Track B ("Lạc", 286s) while mpd-mpris lags on Track A ("Hồn Lỡ Sa Vào", 198.545s, pos 190s)
                mpdMock.trackTitle = "Hồn Lỡ Sa Vào"
                mpdMock.metadata = ({ "xesam:url": "file:///music/Binz/hon-lo-sa-vao.flac" })
                mpdMock.lengthSupported = true
                mpdMock.length = 198.545
                mpdMock.position = 190.0

                LocalMusic.jumpTo(1)
                check(LocalMusic.currentTitle === "Lạc", "jumpTo did not set currentTitle")
                check(Math.abs(LocalMusic.currentDuration - 286.0) < 0.01, "jumpTo should apply Track B duration immediately")
                check(LocalMusic.lyricsPosition === 0, "lagging mpd-mpris position leaked into lyricsPosition after jumpTo: " + LocalMusic.lyricsPosition)
                check(!LocalMusic.mprisMatchesCurrentTrack(), "mprisMatchesCurrentTrack should reject lagging old mpd-mpris track")
                check(Math.abs(MprisController.effectiveLengthForPlayer(mpdMock) - 286.0) < 0.01, "effectiveLengthForPlayer leaked stale mpdPlayer.length")
                check(MprisController.effectivePositionForPlayer(mpdMock) === 0, "effectivePositionForPlayer leaked stale mpdPlayer.position")

                // 3. Switch to Track C with unknown duration (0): must NEVER inherit previous track's 286s!
                LocalMusic.jumpTo(2)
                check(LocalMusic.currentTitle === "NoDur", "jumpTo(2) did not set NoDur")
                check(LocalMusic.currentDuration === 0, "unknown-duration track inherited previous track duration: " + LocalMusic.currentDuration)
                check(MprisController.effectiveLengthForPlayer(mpdMock) === 0, "unknown-duration track returned lagging mpdPlayer.length")

                // 4. External player transition must NOT poison _resolvedTrackLengths cache with Song A's length
                const extPlayer = _makePlayer(
                    "org.mpris.MediaPlayer2.spotify",
                    "Song A",
                    "Artist A",
                    "https://open.spotify.com/track/aaa",
                    286.0,
                    280.0,
                    true
                )
                MprisController._markPlayerTrackTransition(extPlayer)
                MprisController._rememberPlayerLength(extPlayer)
                check(Math.abs(MprisController.effectiveLengthForPlayer(extPlayer) - 286.0) < 0.01, "extPlayer initial length failed")

                // Song title & url change to Song B while player.length still holds stale 286.0 & position 280.0
                extPlayer.trackTitle = "Song B"
                extPlayer.trackArtist = "Artist B"
                extPlayer.metadata = ({ "xesam:url": "https://open.spotify.com/track/bbb" })
                MprisController._markPlayerTrackTransition(extPlayer)
                MprisController._rememberPlayerLength(extPlayer)

                check(MprisController.effectiveLengthForPlayer(extPlayer) === 0, "stale transition length poisoned or bypassed guard: " + MprisController.effectiveLengthForPlayer(extPlayer))
                check(MprisController.effectivePositionForPlayer(extPlayer) === 0, "stale end-of-track position leaked across transition: " + MprisController.effectivePositionForPlayer(extPlayer))

                // Length updates cleanly to Song B's real 198.5s
                extPlayer.length = 198.5
                extPlayer.position = 1.2
                MprisController._clearPlayerTransitionState(extPlayer)
                MprisController._rememberPlayerLength(extPlayer)
                check(Math.abs(MprisController.effectiveLengthForPlayer(extPlayer) - 198.5) < 0.01, "real updated length was rejected")
                check(Math.abs(MprisController.effectivePositionForPlayer(extPlayer) - 1.2) < 0.01, "real updated position was rejected")

                console.info("MUSIC_DURATION_SYNC_QML_PASS")
            } catch (e) {
                console.error("MUSIC_DURATION_SYNC_QML_FAIL", e.message, e.stack)
            }
            Qt.quit()
        }
    }
    Timer {
        interval: 100
        running: true
        onTriggered: test.runChecks()
    }
}
''')
        env = dict(os.environ)
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("DISPLAY", None)
        env.update(FIXTURE_ROOT=str(shell), QT_QPA_PLATFORM="offscreen")
        result = run_qs(shell, env, timeout=20)
        if result.returncode or "MUSIC_DURATION_SYNC_QML_PASS" not in result.stdout or any(
            err in result.stdout
            for err in ["FAIL!", "TypeError:", "ReferenceError:", "Binding loop", "Cannot assign"]
        ):
            print(result.stdout)
            if result.stderr:
                print(result.stderr, file=sys.stderr)
            raise SystemExit(1)


if __name__ == "__main__":
    test_python_mpd_duration_and_stop_fallback()
    test_qml_duration_and_transition_runtime()
    print("MUSIC_DURATION_SYNC_PASS python-mpd + cold-boot-pause + track-switch + mpris-anti-poisoning")
