#!/usr/bin/env python3
"""Regression contract for unified media controls, CAVA and sidebar edge reveal."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def require(source: str, token: str, message: str) -> None:
    if token not in source:
        raise SystemExit(message)


def forbid(source: str, token: str, message: str) -> None:
    if token in source:
        raise SystemExit(message)


sidebar = read("modules/sidebar/SidebarHost.qml")
mpris = read("services/MprisController.qml")
local_service = read("services/LocalMusic.qml")
local_view = read("modules/sidebarLeft/LocalMusicView.qml")
player = read("modules/mediaControls/PlayerControl.qml")
player_base = read("modules/mediaControls/components/PlayerBase.qml")
player_progress = read("modules/mediaControls/components/PlayerProgress.qml")
string_utils = read("modules/common/functions/StringUtils.qml")
compact = read("modules/sidebarRight/CompactMediaPlayer.qml")
compact_sidebar = read("modules/sidebarRight/CompactSidebarRightContent.qml")
dash = read("modules/dashboard/DashMedia.qml")
control_panel = read("modules/controlPanel/MediaSection.qml")
left_widget = read("modules/sidebarLeft/widgets/MediaPlayerWidget.qml")

for token in (
    "readonly property int screenEdgeHoverWidth:",
    "Config.options?.appearance?.screenEdge?.width ?? 10",
    "readonly property int edgeOpenWidth: Math.max(",
    "screenEdgeHoverWidth,",
):
    require(sidebar, token, f"Sidebar Screen Edge hover contract missing: {token}")

for token in (
    "function loopSupportedForPlayer(player): bool",
    "function cycleLoopForPlayer(player): bool",
    "function shuffleSupportedForPlayer(player): bool",
    "function toggleShuffleForPlayer(player): bool",
):
    require(mpris, token, f"Player-scoped media option contract missing: {token}")

for token in (
    "function _isYtMusicOptionTarget(player): bool",
    "if (YtMusic.repeatMode === 1) return MprisLoopState.Track;",
    "if (YtMusic.repeatMode === 2) return MprisLoopState.Playlist;",
    "function loopActiveForPlayer(player): bool",
    "function loopTrackForPlayer(player): bool",
    "next = MprisLoopState.Track;",
    "next = MprisLoopState.Playlist;",
    "YtMusic.shuffleMode = shuffle;",
):
    require(mpris, token, f"Repeat/shuffle backend routing contract missing: {token}")

for token in (
    "property var playbackAdapter: null",
    "readonly property bool effectiveShuffleSupported:",
    "readonly property bool effectiveRepeatSupported:",
    'text: "shuffle"',
    'text: root.effectiveRepeatOne ? "repeat_one" : "repeat"',
    "WaveVisualizer {",
):
    require(player, token, f"PlayerControl unified media contract missing: {token}")

# MPRIS metadata and Position can update independently during a track change.
# Shared media surfaces must never render an elapsed timestamp beyond the new
# duration; a clearly stale previous-track position resets to zero until the
# next valid Position sample arrives.
for token in (
    "function boundedMediaPosition(position, duration)",
    "return current - total <= 2 ? total : 0;",
):
    require(string_utils, token, f"Media timeline normalization missing: {token}")
for source, name in (
    (player, "PlayerControl"),
    (player_base, "PlayerBase"),
):
    require(
        source,
        "StringUtils.boundedMediaPosition(",
        f"{name} must normalize stale cross-track MPRIS position.",
    )
require(
    player_progress,
    "readonly property real boundedPosition: StringUtils.boundedMediaPosition(",
    "PlayerProgress must bound raw caller position before rendering progress.",
)

for token in (
    "property int resumeIndex: -1",
    'if (!playing && mpdState === "stop")',
    '_sendMpd("play", [index])',
    'function stop(): void {',
):
    require(local_service, token, f"LocalMusic stop/resume contract missing: {token}")

for token in (
    "id: localMusicPlayerAdapter",
    "playbackAdapter: localMusicPlayerAdapter",
    "visible: LocalMusic.hasCurrentTrack",
    "active: root.visible && GlobalStates.sidebarLeftOpen",
    "&& LocalMusic.playing",
    'tip: Translation.tr("Play selection")',
    'tip: Translation.tr("Add to queue")',
    "configuration: StyledSlider.Configuration.XS",
    "Layout.preferredWidth: 100",
):
    require(local_view, token, f"LocalMusic UI recovery contract missing: {token}")
forbid(
    local_view,
    'symbol: LocalMusic.shuffleMode ? "shuffle_on" : "shuffle"',
    "LocalMusic must not duplicate Shuffle below PlayerControl.",
)
forbid(
    local_view,
    "symbol: LocalMusic.repeatMode === 1",
    "LocalMusic must not duplicate Repeat below PlayerControl.",
)

# Dashboard and compact right-sidebar cards sit immediately above their shared
# EQ/DSP surface. They must not run a second decorative CAVA analyzer.
for source, name in (
    (compact, "Compact right sidebar"),
    (dash, "Dashboard"),
):
    forbid(source, "CavaProcess {", f"{name} must not run duplicate CAVA.")
    forbid(source, "WaveVisualizer {", f"{name} must not render a decorative CAVA wave.")

forbid(
    compact,
    "GlobalStates.mediaControlsOpen",
    "Compact right-sidebar media must not launch the standalone MediaControls surface.",
)
forbid(
    compact,
    "playerInfoMA",
    "Compact right-sidebar metadata must not keep the retired expansion hit target.",
)

forbid(
    compact_sidebar,
    'headerText: Translation.tr("Controls")',
    "Compact Sidebar Right must not duplicate the Controls heading inside its content.",
)
forbid(
    compact_sidebar,
    "id: controlsVScroll",
    "Compact Sidebar Right must not reserve width for a visible controls scrollbar.",
)
require(
    compact_sidebar,
    'icon: root.layoutEditMode ? "check" : "reorder"',
    "Compact Sidebar Right reorder action must live in the lower left action rail.",
)
if compact_sidebar.count("policy: ScrollBar.AlwaysOff") < 2:
    raise SystemExit("Compact Sidebar Right must hide its visible vertical scrollbars.")

for token in (
    "MprisController.shuffleSupportedForPlayer(playerBase.player)",
    "MprisController.shuffleForPlayer(playerBase.player)",
    "MprisController.toggleShuffleForPlayer(playerBase.player)",
    "MprisController.loopSupportedForPlayer(playerBase.player)",
    "MprisController.loopActiveForPlayer(playerBase.player)",
    "MprisController.loopTrackForPlayer(playerBase.player)",
    "MprisController.cycleLoopForPlayer(playerBase.player)",
    'tooltipText: Translation.tr("Shuffle")',
    'tooltipText: Translation.tr("Repeat")',
):
    require(compact, token, f"Compact right-sidebar transport parity missing: {token}")

for token in (
    "PlayerControl {",
    "visualizerPoints: []",
    "showVisualizer: false",
):
    require(dash, token, f"Dashboard duplicate-visualizer suppression missing: {token}")

for source, name in (
    (control_panel, "Control Panel"),
    (left_widget, "Left Sidebar widget"),
):
    require(source, "toggleShuffleForPlayer", f"{name} media must expose Shuffle.")
    require(source, "cycleLoopForPlayer", f"{name} media must expose Repeat.")

for source, name in (
    (player, "PlayerControl"),
    (compact, "Compact right sidebar"),
    (control_panel, "Control Panel"),
    (left_widget, "Left Sidebar widget"),
):
    forbid(
        source,
        "loopState === 2",
        f"{name} must not treat MPRIS Playlist as repeat-one.",
    )

styled_slider = read("modules/common/widgets/StyledSlider.qml")
bar_media_item = read("modules/mediaControls/BarMediaPlayerItem.qml")
lock_media_widget = read("modules/lock/LockMediaWidget.qml")
ytmusic_card = read("modules/sidebarLeft/widgets/YtMusicPlayerCard.qml")
it_player = read("modules/sidebarLeft/innertune/ITPlayer.qml")
mpdd_source = read("native/alis-mpdd/src/main.rs")

for token in (
    "function validMediaDuration(duration)",
    "const total = root.validMediaDuration(duration);",
):
    require(string_utils, token, f"StringUtils duration normalization missing: {token}")

for token in (
    "property real liveValue: NaN",
    "signal seekCommitted(real value)",
    "restoreMode: Binding.RestoreBindingOrValue",
    "useParentHover: false",
    "externalHoverState: root.pressed",
):
    require(styled_slider, token, f"StyledSlider non-breaking liveValue binding contract missing: {token}")

for source, name in (
    (player_progress, "PlayerProgress"),
    (player, "PlayerControl"),
    (left_widget, "MediaPlayerWidget"),
    (control_panel, "MediaSection"),
    (bar_media_item, "BarMediaPlayerItem"),
    (lock_media_widget, "LockMediaWidget"),
    (ytmusic_card, "YtMusicPlayerCard"),
    (it_player, "ITPlayer"),
):
    require(source, "liveValue:", f"{name} duration slider must bind liveValue so C++ setValue does not break updates.")
    require(source, "tooltipContent: StringUtils.friendlyTimeForSeconds(", f"{name} duration slider must display formatted media time in tooltip.")
    require(source, "onSeekCommitted:", f"{name} duration slider must commit seek on release/wheel.")

require(lock_media_widget, "import qs", "LockMediaWidget must import qs for GlobalStates.")
require(local_service, "property real _lastMpdPositionSampleMs: 0", "LocalMusic must track fresh MPD sample timestamps without snapping back after 8s.")
require(mpdd_source, "if had_cached && !err.to_string().starts_with(\"ACK \")", "alis-mpdd must reconnect and retry once when a cached MPD socket times out.")

for token in (
    "function effectiveLengthForPlayer(player): real",
    "function _resolveExternalDurationForPlayer(player): void",
    "function _syncBrowserPlayerPositionAndLength(player): void",
):
    require(mpris, token, f"MprisController browser duration/position resolution missing: {token}")

for source, name in (
    (player_base, "PlayerBase"),
    (player, "PlayerControl"),
    (left_widget, "MediaPlayerWidget"),
    (control_panel, "MediaSection"),
    (bar_media_item, "BarMediaPlayerItem"),
    (lock_media_widget, "LockMediaWidget"),
):
    require(source, "lengthSupported", f"{name} must guard player.length with player.lengthSupported.")
    require(source, "MprisController.effectiveLengthForPlayer(", f"{name} must fall back to MprisController.effectiveLengthForPlayer when lengthSupported is false.")

print("Unified media controls/CAVA + sidebar edge reveal contract: OK")
