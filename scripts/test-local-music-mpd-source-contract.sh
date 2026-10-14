#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

service="$root/services/LocalMusic.qml"
mpris="$root/services/MprisController.qml"
view="$root/modules/sidebarLeft/LocalMusicView.qml"
sidebar="$root/modules/sidebarLeft/SidebarLeftContent.qml"
editor="$root/modules/common/widgets/SidebarLayoutEditor.qml"
defaults="$root/defaults/config.json"
schema="$root/modules/common/Config.qml"
registry="$root/modules/settings/SettingsPageRegistryData.qml"
migration="$root/sdata/migrations/044-local-music-mpd-state-cleanup.sh"
dispatch="$root/scripts/native-dispatch"
mpdd="$root/native/alis-mpdd/src/main.rs"
mpdd_cargo="$root/native/alis-mpdd/Cargo.toml"

grep -Fq 'libc.workspace = true' "$mpdd_cargo" \
    || fail 'alis-mpdd must retain Linux parent-death lifecycle support'
grep -Fq 'libc::PR_SET_PDEATHSIG' "$mpdd" \
    || fail 'alis-mpdd daemon/subscriber must die with their owning shell'
grep -Fq 'daemon_socket_in_use' "$mpdd" \
    || fail 'alis-mpdd must not unlink a live daemon socket'
grep -Fq 'io::ErrorKind::ConnectionRefused' "$mpdd" \
    || fail 'alis-mpdd may reclaim only a demonstrably stale socket'
grep -Fq 'readonly property string nativeDispatchPath: Directories.scriptsPath + "/native-dispatch"' "$service"     || fail 'LocalMusic must route MPD/local lyrics through native-dispatch'
grep -Fq 'root.nativeDispatchPath, "mpd", "snapshot",' "$service"     || fail 'LocalMusic snapshot must route through native-dispatch'
grep -Fq 'root.nativeDispatchPath, "mpd-daemon",' "$service"     || fail 'Rust MPD persistent daemon must remain selector-routed'
grep -Fq 'command: [root.nativeDispatchPath, "mpd-subscribe"]' "$service"     || fail 'Rust MPD idle subscription must remain selector-routed'
grep -Fq 'scripts/local_music_mpd.py' "$dispatch"     || fail 'native-dispatch must retain the Python MPD fallback'
grep -Fq 'readonly property var mprisPlayer: MprisController.mpdPlayer' "$service" || fail 'LocalMusic must use MPD MPRIS player'
grep -Fq 'MprisController.ensureMpdMprisBridge(mpdHost, mpdPort)' "$service" || fail 'LocalMusic must request MPRIS for its configured MPD endpoint'
grep -Fq 'property MprisPlayer mpdPlayer: null' "$mpris" || fail 'MprisController must expose MPD player'
grep -Fq 'org.mpris.MediaPlayer2.mpd.hadalis' "$mpris" || fail 'custom MPD endpoints need a dedicated Hadalis MPRIS instance'
grep -Fq '_mpdMprisCustomProc.command = root._mpdCustomBridgeCommand()' "$mpris" || fail 'custom MPD endpoint must launch endpoint-bound mpd-mpris'
grep -Fq 'command: ["/usr/bin/systemctl", "--user", "start", "mpd-mpris.service"]' "$mpris" || fail 'default localhost MPD must retain distro mpd-mpris service path'
# Dashboard UI behavior is covered by test-dashboard-music-runtime.py. Keep
# backend identity/protocol checks here without requiring retired Sidebar tabs.
grep -Fq 'function createPlaylist(name: string, tracks): void' "$service" || fail 'LocalMusic must support creating saved MPD playlists'
grep -Fq 'function addTracksToPlaylist(name: string, tracks): void' "$service" || fail 'LocalMusic must support adding tracks to MPD playlists'
grep -Fq 'client.command("playlistadd", playlist_name, uri)' "$root/scripts/local_music_mpd.py" || fail 'MPD helper must mutate saved playlists with playlistadd'
grep -Fq '_lyricsProc.command = [root.nativeDispatchPath, "lyrics", path]' "$service"     || fail 'LocalMusic local lyrics must route through native-dispatch'
grep -Fq 'scripts/local_music_lyrics.py' "$dispatch"     || fail 'native-dispatch must retain the Python local-lyrics fallback'
grep -Fq 'function removeQueueTrack(index: int): void' "$service" || fail 'Music Queue must expose per-track MPD removal'
grep -Fq 'function clearQueue(): void' "$service" || fail 'Music Queue must expose MPD clear'
grep -Fq '"deleteid",' "$root/scripts/local_music_mpd.py" || fail 'MPD helper must allow stable queue-id deletion'
grep -Fq '"clear",' "$root/scripts/local_music_mpd.py" || fail 'MPD helper must allow clearing the active queue'
grep -Fq 'def binary(self, name: str, uri: str)' "$root/scripts/local_music_mpd.py" || fail 'MPD helper must read binary artwork without a private player backend'
grep -Fq 'for command in ("albumart", "readpicture")' "$root/scripts/local_music_mpd.py" || fail 'Music covers must prefer MPD albumart and fall back to embedded readpicture'
grep -Fq '_populate_library_art(client, tracks)' "$root/scripts/local_music_mpd.py" || fail 'MPD library snapshot must hydrate cover art'
grep -Fq '.resolve().as_uri()' "$root/scripts/local_music_mpd.py" || fail 'local cover paths must be emitted as QML-safe file URLs'
if grep -Eq 'mpvPath|local_music_ipc|local_music_scan|--input-ipc-server' "$service"; then
    fail 'LocalMusic must not regress to a private mpv player'
fi
[[ ! -e "$root/scripts/local_music_ipc.py" ]] \
    || fail 'retired private mpv IPC helper must stay removed'
[[ ! -e "$root/scripts/local_music_scan.py" ]] \
    || fail 'retired filesystem scanner must stay removed; MPD owns the library database'
for retired_state in normalizeVolume shuffleMode repeatMode volume; do
    if sed -n '/property JsonObject music: JsonObject {/,/^                }/p' "$schema" \
        | grep -Eq "property [^ ]+ ${retired_state}:"; then
        fail "local Music schema still exposes retired mpv state: $retired_state"
    fi
    if jq -e --arg key "$retired_state" '.sidebar.music | has($key)' "$defaults" >/dev/null; then
        fail "local Music defaults still expose retired mpv state: $retired_state"
    fi
    grep -Fq ".sidebar.music.$retired_state" "$migration" \
        || fail "migration 044 does not remove retired local Music state: $retired_state"
done
if grep -Fq 'label: Translation.tr("YT Music Up Next notifications")' "$registry"; then
    fail 'retired YT Music notification settings must not remain searchable'
fi
if grep -Fq 'label: Translation.tr("YT Music fullscreen suppression")' "$registry"; then
    fail 'retired YT Music fullscreen settings must not remain searchable'
fi
printf 'PASS: Local Music is MPD-owned with MPRIS transport integration\n'
