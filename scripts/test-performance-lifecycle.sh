#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'performance lifecycle guard failed: %s\n' "$1" >&2
    exit 1
}

require() {
    local file="$1" needle="$2" message="$3"
    grep -Fq -- "$needle" "$file" || fail "$message"
}

reject() {
    local file="$1" needle="$2" message="$3"
    if grep -Fq -- "$needle" "$file"; then
        fail "$message"
    fi
}

config="$repo_root/modules/common/Config.qml"
shell_qml="$repo_root/shell.qml"
defaults="$repo_root/defaults/config.json"
cava="$repo_root/services/deferred/CavaService.qml"
cava_generator="$repo_root/scripts/cava/generate_config.sh"
advanced="$repo_root/modules/settings/AdvancedConfig.qml"
waffle_themes="$repo_root/modules/waffle/settings/pages/WThemesPage.qml"
theme_service="$repo_root/services/ThemeService.qml"
media_section="$repo_root/modules/controlPanel/MediaSection.qml"
sidebar_media="$repo_root/modules/sidebarLeft/widgets/MediaPlayerWidget.qml"
crypto_widget="$repo_root/modules/sidebarLeft/widgets/CryptoWidget.qml"
it_thumbnail="$repo_root/modules/sidebarLeft/innertune/ITThumbnail.qml"
screen_edges="$repo_root/modules/screenCorners/ScreenEdges.qml"
screen_edge_fallback="$repo_root/modules/screenCorners/ScreenEdgeLegacyFallback.qml"
alt_switcher="$repo_root/modules/altSwitcher/AltSwitcher.qml"
waffle_alt="$repo_root/modules/waffle/altSwitcher/WaffleAltSwitcher.qml"
waffle_alt_content="$repo_root/modules/waffle/altSwitcher/WaffleAltSwitcherContent.qml"
workspace_thumb="$repo_root/modules/waffle/taskview/WorkspaceThumbnail.qml"
window_thumb="$repo_root/modules/waffle/taskview/WindowThumbnail.qml"
easyeffects="$repo_root/services/deferred/EasyEffects.qml"
tlp="$repo_root/services/TlpService.qml"
thinkfan="$repo_root/services/ThinkFanService.qml"
tlp_caps="$repo_root/services/TlpRuntimeCapabilities.qml"
tlp_settings="$repo_root/services/TlpSettingsService.qml"
power_profiles="$repo_root/services/PowerProfilePersistence.qml"
world_clock="$repo_root/services/WorldClock.qml"
sidebar_world_clock="$repo_root/modules/sidebarLeft/widgets/WorldClockWidget.qml"
game_mode="$repo_root/services/GameMode.qml"
directories="$repo_root/modules/common/Directories.qml"
conflict_killer="$repo_root/services/ConflictKiller.qml"
global_actions="$repo_root/services/GlobalActions.qml"
first_run="$repo_root/services/FirstRunExperience.qml"
overview_window="$repo_root/modules/overview/OverviewWindow.qml"
resource_usage="$repo_root/services/ResourceUsage.qml"
memory_pressure="$repo_root/services/MemoryPressureService.qml"
bar_resources="$repo_root/modules/bar/Resources.qml"
vertical_bar_resources="$repo_root/modules/verticalBar/Resources.qml"
recorder_status="$repo_root/services/RecorderStatus.qml"
local_music="$repo_root/services/LocalMusic.qml"
mpris_controller="$repo_root/services/MprisController.qml"
recorder_overlay_widget="$repo_root/modules/ii/overlay/recorder/Recorder.qml"
overlay_taskbar="$repo_root/modules/ii/overlay/OverlayTaskbar.qml"
overlay_floating_image="$repo_root/modules/ii/overlay/floatingImage/FloatingImage.qml"
overlay_resources="$repo_root/modules/ii/overlay/resources/Resources.qml"
waffle_widgets_content="$repo_root/modules/waffle/widgets/WidgetsContent.qml"
control_panel_media="$repo_root/modules/controlPanel/MediaSection.qml"
date_time_header="$repo_root/modules/controlPanel/DateTimeHeader.qml"
date_time_service="$repo_root/services/DateTime.qml"
clock_widget="$repo_root/modules/background/widgets/clock/ClockWidget.qml"
cookie_clock="$repo_root/modules/background/widgets/clock/CookieClock.qml"
lock_surface="$repo_root/modules/lock/LockSurface.qml"
waffle_lock="$repo_root/modules/waffle/lock/WaffleLockSurface.qml"
waffle_lock_safe="$repo_root/modules/waffle/lock/WaffleLockSurfaceSafe.qml"
weather="$repo_root/services/Weather.qml"
wallhaven_service="$repo_root/services/Wallhaven.qml"
keyboard_indicators="$repo_root/services/KeyboardIndicators.qml"
icon_theme_service="$repo_root/services/IconThemeService.qml"
icon_theme_selector="$repo_root/modules/common/widgets/IconThemeSelector.qml"
sidebar_anime="$repo_root/modules/sidebarLeft/Anime.qml"
sidebar_wallhaven="$repo_root/modules/sidebarLeft/WallhavenView.qml"
sidebar_ai="$repo_root/modules/sidebarLeft/AiChat.qml"
sidebar_quick_wallpaper="$repo_root/modules/sidebarLeft/widgets/QuickWallpaper.qml"
booru_image="$repo_root/modules/sidebarLeft/anime/BooruImage.qml"
booru_response="$repo_root/modules/sidebarLeft/anime/BooruResponse.qml"
ai_think_block="$repo_root/modules/sidebarLeft/aiChat/MessageThinkBlock.qml"
sidebar_right_tasks="$repo_root/modules/sidebarRight/todo/TaskList.qml"
sidebar_right_notifications="$repo_root/modules/sidebarRight/notifications/NotificationList.qml"
sidebar_right_media="$repo_root/modules/sidebarRight/CompactMediaPlayer.qml"
video_crossfader="$repo_root/modules/common/widgets/VideoCrossfader.qml"
media_cross_slide="$repo_root/modules/common/widgets/MediaCrossSlideImage.qml"
custom_image_widget="$repo_root/modules/background/widgets/CustomImageWidget.qml"
control_panel_wallpaper="$repo_root/modules/controlPanel/WallpaperSection.qml"
wallpaper_skew_view="$repo_root/modules/wallpaperSelector/WallpaperSkewView.qml"
dash_media="$repo_root/modules/dashboard/DashMedia.qml"
dash_welcome="$repo_root/modules/dashboard/DashWelcome.qml"
dashboard="$repo_root/modules/dashboard/Dashboard.qml"
ii_panels="$repo_root/modules/ii/ShellIiPanelsImpl.qml"
waffle_panels="$repo_root/modules/waffle/ShellWafflePanelsImpl.qml"
global_states="$repo_root/GlobalStates.qml"
wallpaper_launcher_content="$repo_root/modules/wallpaperLauncher/WallpaperLauncherContent.qml"
wallpaper_launcher="$repo_root/modules/wallpaperLauncher/WallpaperLauncher.qml"
wallpaper_coverflow="$repo_root/modules/wallpaperSelector/WallpaperCoverflow.qml"
dashboard_settings="$repo_root/modules/settings/DashboardConfig.qml"
screen_time="$repo_root/services/ScreenTime.qml"
ytmusic="$repo_root/services/YtMusic.qml"
directory_icon="$repo_root/modules/common/widgets/DirectoryIcon.qml"
sysmon_widget="$repo_root/modules/sidebarRight/sysmon/SysMonWidget.qml"
timer_service="$repo_root/services/TimerService.qml"
settings_page_host="$repo_root/modules/settings/SettingsPageHost.qml"
levendist="$repo_root/modules/common/functions/levendist.js"
emojis="$repo_root/services/deferred/Emojis.qml"
app_search="$repo_root/services/AppSearch.qml"
cliphist="$repo_root/services/deferred/Cliphist.qml"
clipboard_panel="$repo_root/modules/clipboard/ClipboardPanel.qml"
emojis_service="$repo_root/services/deferred/Emojis.qml"
loading_indicator="$repo_root/modules/common/widgets/MaterialLoadingIndicator.qml"
circular_progress="$repo_root/modules/common/widgets/CircularProgress.qml"
clipped_filled_progress="$repo_root/modules/common/widgets/ClippedFilledCircularProgress.qml"
clipped_outline_progress="$repo_root/modules/common/widgets/ClippedOutlineCircularProgress.qml"
wavy_line="$repo_root/modules/common/widgets/WavyLine.qml"
cava_wavy_line="$repo_root/modules/common/widgets/CavaWavyLine.qml"
cava_spectrum="$repo_root/modules/common/widgets/CavaSpectrum.qml"
bar_cava_visualizer="$repo_root/modules/common/widgets/BarCavaVisualizer.qml"
shell_update_indicator="$repo_root/modules/bar/ShellUpdateIndicator.qml"
shell_updates="$repo_root/services/ShellUpdates.qml"
system_updates="$repo_root/services/Updates.qml"
util_buttons="$repo_root/modules/bar/UtilButtons.qml"
waffle_system_button="$repo_root/modules/waffle/bar/SystemButton.qml"
waffle_timer_button="$repo_root/modules/waffle/bar/TimerButton.qml"
waffle_background_clock="$repo_root/modules/waffle/background/WaffleBackgroundClock.qml"
waffle_media_pane="$repo_root/modules/waffle/actionCenter/MediaPaneContent.qml"
player_base="$repo_root/modules/mediaControls/components/PlayerBase.qml"
player_progress="$repo_root/modules/mediaControls/components/PlayerProgress.qml"
bar_media="$repo_root/modules/bar/Media.qml"
vertical_bar_media="$repo_root/modules/verticalBar/VerticalMedia.qml"
volume_mixer="$repo_root/modules/ii/overlay/volumeMixer/VolumeMixer.qml"

require "$config" 'property int framerate: 30' 'Cava schema default must remain 30 fps'
require "$defaults" '"framerate": 30' 'persisted Cava default must remain 30 fps'
require "$cava" 'Config.options?.appearance?.cava?.framerate ?? 30' 'Cava runtime fallback must remain 30 fps'
require "$date_time_header" 'DateTime.clock.date' 'Control Panel date must use the shared SystemClock'
reject "$date_time_service" 'cookie?.secondHandStyle' 'Cookie second hand must not force the global DateTime clock to 1 Hz'
require "$date_time_service" 'function _refreshUptime(): void {' 'DateTime uptime refresh must remain explicit'
require "$date_time_service" 'target: clock' 'DateTime uptime must reuse the shared SystemClock'
require "$date_time_service" 'function onMinutesChanged(): void {' 'DateTime uptime must refresh from the shared minute signal'
require "$date_time_service" 'Component.onCompleted: root._refreshUptime()' 'DateTime uptime must initialize immediately without a timer'
reject "$date_time_service" 'triggeredOnStart: true' 'DateTime uptime must not own a duplicate triggered timer'
reject "$date_time_service" 'interval: 60000' 'DateTime uptime must not own a duplicate minute timer'
require "$clock_widget" 'readonly property bool cookieNeedsSeconds:' 'Background CookieClock must own its seconds demand'
require "$clock_widget" 'clockSecond: displayClock.seconds' 'Background CookieClock seconds must stay local'
require "$waffle_background_clock" '&& root.clockEnabled' 'Disabled Waffle clock must not keep a 1 Hz SystemClock'
require "$waffle_media_pane" 'triggeredOnStart: true' 'Waffle Action Center media position must prime when presented'
require "$cookie_clock" 'property int clockSecond: DateTime.clock.seconds' 'CookieClock must preserve the lock-screen fallback clock'
reject "$date_time_header" 'onTriggered: root._tick++' 'Control Panel must not restore a duplicate minute timer'
for lock_date_surface in "$lock_surface" "$waffle_lock" "$waffle_lock_safe"; do
    require "$lock_date_surface" 'Qt.formatDate(DateTime.clock.date,' 'Lock dates must use the shared SystemClock'
    reject "$lock_date_surface" 'onTriggered: dateText.text = Qt.formatDate(' 'Lock date labels must not restore private minute timers'
done
require "$cava_spectrum" 'function _curveHeadroom(top, bottom): real' 'CavaSpectrum must keep scalar edge geometry'
reject "$cava_spectrum" 'function _surfaceBounds(' 'CavaSpectrum must not allocate surface arrays per sample'
reject "$cava_spectrum" 'function _peakBounds(' 'CavaSpectrum must not allocate surface/peak arrays per sample'
reject "$cava_spectrum" 'function _applyFrequencyProfile(' 'CavaSpectrum selection/profile must stay fused'
reject "$cava_spectrum" 'primary.push([' 'CavaSpectrum wave coordinates must stay flat'
require "$cava_spectrum" 'const baseline = !ribbonMode && !lineMode ? root._baselineScratch : null' 'CavaSpectrum line mode must not build an unused baseline'
require "$cava_spectrum" 'property bool waveOutlineEnabled: true' 'CavaSpectrum must keep outline control explicit'
require "$cava_spectrum" 'if (root.waveOutlineEnabled) {' 'CavaSpectrum filled-wave outline must remain optional'
require "$repo_root/modules/bar/BarContent.qml" 'BarCavaVisualizer {' 'Bar spectrum must use the scene-graph renderer'
reject "$repo_root/modules/bar/BarContent.qml" 'threadedRendering: true' 'Bar spectrum must not restore threaded Canvas rasterization'
reject "$repo_root/modules/bar/BarContent.qml" 'CavaSpectrum {' 'Bar spectrum must not restore the full-width Canvas renderer'
reject "$bar_cava_visualizer" 'import QtQuick.Shapes' 'Bar visualizer must not restore per-frame Shape tessellation'
require "$bar_cava_visualizer" 'id: barRepeater' 'Bar visualizer bars must use scene-graph Rectangle nodes'
require "$bar_cava_visualizer" 'id: waveFillRepeater' 'Bar filled/ribbon waves must use scene-graph strips'
require "$bar_cava_visualizer" 'readonly property real connectorLength:' 'Bar filled waves must connect adjacent sample edges'
require "$bar_cava_visualizer" 'readonly property real lowerConnectorLength:' 'Bar ribbon waves must connect both sample edges'
require "$bar_cava_visualizer" 'radius: 0' 'Bar filled wave strips must not render isolated rounded spike caps'
require "$bar_cava_visualizer" 'id: waveLineRepeater' 'Bar line waves must use scene-graph segment quads'
require "$bar_cava_visualizer" 'property int waveStripCap: 72' 'Bar wave scene resolution must stay bounded'
require "$bar_cava_visualizer" 'Math.min(sourceCount, root.waveStripCap,' 'Bar wave level fan-out must honor the scene cap'
require "$repo_root/modules/bar/BarContent.qml" 'readonly property int barSpectrumWaveSampleCap: 72' 'Bar wave CAVA request must share the scene cap'
require "$repo_root/modules/bar/BarContent.qml" 'Math.min(root.barSpectrumWaveSampleCap, densityCount)' 'Bar wave CAVA payload must stay bounded'
require "$repo_root/modules/bar/BarContent.qml" 'waveStripCap: root.barSpectrumWaveSampleCap' 'Bar wave renderer and CAVA sample caps must stay aligned'
reject "$bar_cava_visualizer" 'Canvas {' 'Bar visualizer must stay off QQuickContext2D'
reject "$bar_cava_visualizer" 'PathPolyline {' 'Bar visualizer must not rebuild/tessellate a point path per audio frame'
reject "$bar_cava_visualizer" 'Qt.callLater(() => {' 'Bar CAVA frame geometry must not post one event per audio frame'
require "$bar_cava_visualizer" 'onPointsChanged: root._rebuildLevels()' 'Bar CAVA must rebuild once from the published frame'
require "$bar_cava_visualizer" 'property var _selectedScratch: []' 'Bar CAVA frame processing must reuse selection scratch'
require "$bar_cava_visualizer" 'property var _smoothScratch: []' 'Bar CAVA smoothing must reuse frame scratch'
require "$bar_cava_visualizer" 'property var _levelScratchA: []' 'Bar CAVA levels must reuse the first frame buffer'
require "$bar_cava_visualizer" 'property var _levelScratchB: []' 'Bar CAVA levels must reuse the second frame buffer'
require "$bar_cava_visualizer" 'function _nextLevelScratch(count): var' 'Bar CAVA must alternate reusable level buffers'
reject "$bar_cava_visualizer" 'new Array(count)' 'Bar CAVA must not allocate a fresh level array every frame'
require "$repo_root/modules/background/widgets/visualizer/VisualizerWidget.qml" 'waveOutlineEnabled: false' 'Desktop spectrum must skip the duplicate wave outline raster pass'
reject "$cava_spectrum" 'function _barLevels(' 'CavaSpectrum must calculate levels inside paint loops'
reject "$cava_spectrum" 'function _waveLevels(' 'CavaSpectrum must not allocate a transient level array'
require "$cava_spectrum" 'property var _selectedScratch: []' 'CavaSpectrum must reuse per-instance frame scratch'
require "$cava_spectrum" 'const primary = root._primaryScratch' 'CavaSpectrum wave paint must reuse its trace buffer'
reject "$cava_spectrum" 'new Array(selectedCount)' 'CavaSpectrum must not allocate a selection array every frame'
reject "$cava" 'const parsed = []' 'Cava parser must not allocate a second frame array'
require "$cava" 'parsed[writeIndex++] = value' 'Cava parser must compact numeric samples in place'
reject "$cava" 'const value = Number(parsed[i]) || 0' 'Cava publish must not renormalize already parsed samples'
require "$cava" 'property var points: []' 'Cava hot frames must stay as JS arrays instead of typed QML sequences'
reject "$cava" 'property list<real> points: []' 'Cava hot frames must not restore per-frame typed sequence conversion'
reject "$cava" 'property real framePeak:' 'Cava hot path must not publish an unused framePeak property every frame'
reject "$cava" 'property real frameAverage:' 'Cava hot path must not publish an unused frameAverage property every frame'
require "$cava" 'const average = sum / parsed.length' 'Cava signal detection must keep frame average local to the parser hot path'
reject "$resource_usage" 'cpuLine.slice(1).map(Number)' 'ResourceUsage CPU polling must not allocate a stats array'
reject "$resource_usage" 'stats.reduce(' 'ResourceUsage CPU polling must sum proc-stat fields directly'
require "$resource_usage" 'const total = user + nice + system + idleRaw + iowait + irq + softirq' 'ResourceUsage CPU polling must preserve all seven proc-stat fields'
reject "$resource_usage" 'textNetDev.split("\n")' 'ResourceUsage network polling must not split the full proc file into line arrays'
reject "$resource_usage" 'line.substring(separator + 1).trim().split(/\s+/)' 'ResourceUsage network polling must not allocate one fields array per interface'
reject "$resource_usage" 'textMeminfo.match(/MemTotal:' 'ResourceUsage meminfo polling must not scan the proc file separately per field'
require "$resource_usage" 'const meminfoLine = /^(MemTotal|MemAvailable|SwapTotal|SwapFree):\s+(\d+)/gm' 'ResourceUsage meminfo polling must parse required counters in one pass'
require "$resource_usage" 'switch (meminfoMatch[1])' 'ResourceUsage meminfo polling must dispatch parsed counters without extra scans'
require "$resource_usage" 'const netLine = /^\s*([^:\s]+):' 'ResourceUsage network polling must parse interface rows directly'
require "$resource_usage" 'totalRx += Number(match[2]) || 0' 'ResourceUsage network polling must preserve RX byte aggregation'
require "$resource_usage" 'totalTx += Number(match[3]) || 0' 'ResourceUsage network polling must preserve TX byte aggregation'
require "$bar_resources" 'active: !GameMode.active' 'Bar scalar resource monitoring must stay game-mode gated'
require "$repo_root/modules/bar/BarContent.qml" 'root.QsWindow.window?.visible ?? false' 'Bar spectrum Cava must release with its presentation window'
require "$player_base" 'interval: 500' 'PlayerBase MPRIS position polling must stay at the reduced 2 Hz cadence'
require "$player_base" 'triggeredOnStart: true' 'PlayerBase position polling must prime immediately when activated'
reject "$player_base" 'interval: 250' 'PlayerBase must not restore 4 Hz MPRIS position polling'
require "$player_progress" 'NumberAnimation { duration: 500; easing.type: Easing.Linear }' 'PlayerProgress interpolation must span the reduced sample cadence'
require "$cava" '? Math.min(24, root.requestedFramerate)' 'Low Power must cap Cava at 24 fps'
require "$cava_generator" 'FRAMERATE="${2:-30}"' 'Cava generator fallback must remain 30 fps'
require "$advanced" '"appearance.cava.framerate": 30' 'ii Cava reset must remain 30 fps'
require "$waffle_themes" '"appearance.cava.framerate": 30' 'Waffle Cava reset must remain 30 fps'

require "$theme_service" 'function _nextScheduleDelayMs(): int' 'scheduled themes must compute the next transition boundary directly'
require "$theme_service" 'scheduleTimer.interval = Math.max(1000, Math.round(root._nextScheduleDelayMs()))' 'scheduled themes must sleep until the next transition boundary'
require "$theme_service" 'repeat: false' 'scheduled theme transition timer must remain single-shot'
require "$theme_service" 'onScheduleDayStartChanged: scheduleRefreshTimer.restart()' 'scheduled theme timer must re-arm when the day boundary changes'
require "$theme_service" 'onScheduleNightStartChanged: scheduleRefreshTimer.restart()' 'scheduled theme timer must re-arm when the night boundary changes'
reject "$theme_service" 'interval: 60000  // Check every minute' 'scheduled themes must not poll once per minute'
require "$media_section" 'root.effectiveIsPlaying && GlobalStates.controlPanelOpen' 'Control Panel Cava must stop while playback is paused'
require "$sidebar_media" 'root.QsWindow.window?.visible ?? false' 'Sidebar media position ticker must sleep with its presentation window'
require "$sidebar_media" 'triggeredOnStart: true' 'Sidebar media position ticker must prime on reopen'
require "$bar_media" 'root.QsWindow.window?.visible ?? false' 'Bar media position ticker must sleep with its presentation window'
require "$bar_media" 'triggeredOnStart: true' 'Bar media position ticker must prime on remap'
require "$vertical_bar_media" 'root.QsWindow.window?.visible ?? false' 'Vertical Bar media ticker must sleep with its presentation window'
require "$vertical_bar_media" 'triggeredOnStart: true' 'Vertical Bar media ticker must prime on remap'
require "$volume_mixer" 'SwipeView.isCurrentItem' 'Volume Mixer media ticker must sleep outside the Music tab'
require "$volume_mixer" 'root.QsWindow.window?.visible ?? false' 'Volume Mixer media ticker must sleep with the Overlay window'
require "$volume_mixer" 'triggeredOnStart: true' 'Volume Mixer media ticker must prime when presented'
require "$sidebar_media" 'root.effectiveIsPlaying && GlobalStates.sidebarLeftOpen' 'Sidebar Cava must stop while playback is paused'
require "$sidebar_media" 'layer.enabled: root.visible && GlobalStates.sidebarLeftOpen' 'Sidebar media mask must release its FBO while the sidebar is closed'
require "$sidebar_media" 'sourceSize.width: Math.max(1, Math.ceil(card.width * root._dpr))' 'Sidebar blurred artwork decode must remain bounded to the displayed card'
require "$control_panel_media" 'layer.enabled: root.visible && GlobalStates.controlPanelOpen' 'Control Panel media masks must release their FBOs while closed'
require "$control_panel_media" 'readonly property bool positionTickerActive:' 'Control Panel must expose the position-ticker lifecycle'
require "$video_crossfader" 'readonly property bool _decoderActive: root.source !== ""' 'video wallpaper decoders must sleep while no video source is requested'
require "$video_crossfader" 'id: playerALoader' 'video wallpaper slot A must be lazy-loaded'
require "$video_crossfader" 'id: playerBLoader' 'video wallpaper slot B must be lazy-loaded'
require "$video_crossfader" 'active: root._decoderActive' 'video wallpaper decoder loaders must follow source lifecycle'
require "$video_crossfader" 'onLoaded: root._applySource()' 'video wallpaper source application must resume after lazy decoder creation'
if grep -Eq '^[[:space:]]*id:[[:space:]]+playerA[[:space:]]*$' "$video_crossfader"; then
    fail 'video wallpaper must not restore an eager slot A MediaPlayer'
fi
if grep -Eq '^[[:space:]]*id:[[:space:]]+playerB[[:space:]]*$' "$video_crossfader"; then
    fail 'video wallpaper must not restore an eager slot B MediaPlayer'
fi
require "$custom_image_widget" 'id: videoPlayerLoader' 'Custom image widget video decoders must be lazy-loaded'
require "$custom_image_widget" 'active: slot.isVideo && slot.sourcePath.length > 0' 'Custom image widget decoder must sleep for image and GIF slots'
require "$custom_image_widget" 'return videoPlayerLoader.item' 'Custom image widget playback must resolve the lazy decoder safely'
if grep -Eq '^[[:space:]]*id:[[:space:]]+videoPlayer[[:space:]]*$' "$custom_image_widget"; then
    fail 'Custom image widget must not restore an eager MediaPlayer per slot'
fi
require "$media_cross_slide" 'ClippingRectangle {' 'Media artwork rounded clipping must use scene-graph clipping'
require "$media_cross_slide" 'import Quickshell.Widgets' 'Media artwork clipping must use the Quickshell scene-graph primitive'
reject "$media_cross_slide" 'GE.OpacityMask' 'Media artwork must not allocate a permanent rounded-mask FBO'
reject "$media_cross_slide" 'layer.enabled: true' 'Media artwork root must not restore a permanent layer FBO'
require "$control_panel_media" 'running: root.positionTickerActive' 'Control Panel MPRIS position timer must sleep while closed'
require "$control_panel_media" 'triggeredOnStart: true' 'Control Panel position must refresh immediately when reopened'
require "$control_panel_media" 'sourceSize.width: Math.max(1, Math.ceil(card.width * root._dpr))' 'Control Panel blurred artwork decode must remain bounded'
require "$control_panel_media" 'mipmap: false' 'Control Panel artwork must not generate unused mipmaps'

require "$config" 'property int refreshInterval: 300' 'Crypto refresh schema default must remain five minutes'
require "$crypto_widget" 'Config.options?.sidebar?.widgets?.crypto_settings?.refreshInterval ?? 300' 'Crypto runtime fallback must remain five minutes'
require "$crypto_widget" 'readonly property bool presentationActive: GlobalStates.sidebarLeftOpen && root.visible' 'Crypto network refresh must be presentation-gated'
require "$crypto_widget" 'running: root.presentationActive && root.coins.length > 0 && Config.ready' 'Crypto periodic refresh must sleep with the sidebar'
require "$crypto_widget" 'root._cacheTimestamp = Number(cached.timestamp) || 0' 'Crypto cache freshness must survive shell restarts'
require "$crypto_widget" 'function _startNextSparkline(): void' 'Crypto sparklines must use a serialized request queue'
require "$crypto_widget" 'if (!root.presentationActive || sparklineProcess.running || root._sparklineIdx >= root.coins.length)' 'Crypto sparkline requests must not overlap or continue hidden'
require "$crypto_widget" 'sparklineTimer.restart()' 'Crypto sparkline queue must schedule bounded one-shot work'
reject "$crypto_widget" 'sparklineTimer.start()' 'Crypto sparklines must not restore the recurring timer-driven queue'

require "$it_thumbnail" 'ClippingRectangle {' 'InnerTune thumbnails must use scene-graph clipping'
reject "$it_thumbnail" 'GE.OpacityMask' 'InnerTune list thumbnails must not allocate an OpacityMask layer'
require "$it_thumbnail" 'GlobalStates.sidebarLeftOpen' 'InnerTune decorative equalizer must stop with the sidebar'

require "$screen_edges" 'updatesEnabled: mapped && !fullscreenCovered' 'Covered Screen Edge frame must suspend scenegraph updates without unmapping'
require "$screen_edges" 'updatesEnabled: mapped && workspaceOverviewEdgeSupportEnabled' 'Transparent Screen Edge reservations must sleep rendering unless top-edge hover support needs updates'
require "$screen_edges" 'readonly property bool physicalShadowActive:' 'Screen Edge must compute physical shadow activity explicitly'
require "$screen_edges" 'ScreenEdgeField {' 'Screen Edge normal path must use the analytic field painter'
require "$screen_edges" 'elevationEnabled: frameWindow.physicalShadowActive' 'Screen Edge analytic elevation must stop when physical shadow is inactive'
require "$screen_edges" 'readonly property var edgeRoot: root' 'Healthy Screen Edge path must keep one root reference for deferred fallback'
require "$screen_edges" 'readonly property var frameHost: frameWindow' 'Healthy Screen Edge path must keep one frame reference for deferred fallback'
require "$screen_edges" 'active: frameField.shaderError' 'Legacy Screen Edge painter must remain lazy and error-only'
require "$screen_edges" 'Qt.resolvedUrl("ScreenEdgeLegacyFallback.qml")' 'Legacy Screen Edge renderer must load by URL only after shader error'
reject "$screen_edges" 'readonly property real frameLeftInset: frameWindow.frameLeftInset' 'Healthy Screen Edge path must not retain legacy fallback value bindings'
reject "$screen_edges" 'readonly property color shadowColor: Qt.alpha(' 'Healthy Screen Edge path must not retain legacy shadow-color binding'
reject "$screen_edges" 'import QtQuick.Shapes' 'Healthy Screen Edge path must not import the legacy Shapes module'
reject "$screen_edges" 'import QtQuick.Effects' 'Healthy Screen Edge path must not import the legacy Effects module'
require "$screen_edge_fallback" 'readonly property var edgeRoot: parent.edgeRoot' 'Loaded Screen Edge fallback must resolve root state lazily'
require "$screen_edge_fallback" 'readonly property var frameHost: parent.frameHost' 'Loaded Screen Edge fallback must resolve frame state lazily'
require "$screen_edge_fallback" 'fillRule: ShapePath.OddEvenFill' 'External Screen Edge fallback must retain the locked odd-even frame'

require "$alt_switcher" 'cacheBuffer: root.skewExpandedWidth' 'ii skew AltSwitcher cache must stay bounded'
require "$alt_switcher" 'id: skewFocusRetryTimer' 'ii skew AltSwitcher focus must use bounded retries'
require "$alt_switcher" 'root._skewFocusRetryCount < 4' 'ii skew AltSwitcher focus retries must stay bounded'
reject "$alt_switcher" 'id: skewFocusTimer' 'ii skew AltSwitcher must not restore 10 Hz focus polling'
require "$alt_switcher" 'enabled: root.effectiveNoVisualUi && !GlobalStates.altSwitcherOpen && !GameMode.active' 'no-UI AltSwitcher snapshot refresh must stay event-driven and game-mode gated'
require "$alt_switcher" 'function onMruWindowIdsChanged() { root.rebuildNoUiSnapshot() }' 'no-UI AltSwitcher must refresh from MRU events'
require "$alt_switcher" 'function onWorkspacesChanged() { root.rebuildNoUiSnapshot() }' 'no-UI AltSwitcher must refresh from workspace events'
reject "$alt_switcher" 'id: noUiSnapshotUpdateTimer' 'no-UI AltSwitcher must not restore closed-state snapshot polling'
reject "$alt_switcher" 'cacheBuffer: root.skewExpandedWidth * 2' 'ii skew AltSwitcher must not restore the doubled preview cache'
require "$alt_switcher" 'layer.samples: Appearance.effectsEnabled ? 4 : 1' 'ii skew mask sampling must scale down with effects'
require "$alt_switcher" 'layer.enabled: root.skewCardVisible' 'ii skew mask FBO must sleep while the switcher is closed'
require "$waffle_alt" 'id: focusRetryTimer' 'Waffle AltSwitcher focus must use bounded retries'
reject "$waffle_alt" 'id: focusTimer' 'Waffle AltSwitcher must not restore 33 Hz focus polling'
require "$waffle_alt_content" 'cacheBuffer: root.skewExpandedWidth' 'Waffle skew AltSwitcher cache must stay bounded'
require "$waffle_alt_content" 'layer.samples: Looks.effectsEnabled ? 4 : 1' 'Waffle skew mask sampling must scale down with effects'
require "$waffle_alt_content" 'layer.enabled: root.cardVisible' 'Waffle skew mask FBO must sleep while the switcher is closed'

require "$workspace_thumb" 'readonly property bool wallpaperPresented:' 'TaskView must gate hidden workspace wallpaper presentation'
require "$workspace_thumb" 'sourceSize.width: Math.max(1, Math.ceil(root.thumbnailWidth * 1.5))' 'TaskView workspace wallpapers must use bounded decode size'
require "$window_thumb" 'GlobalStates.waffleTaskViewOpen && shimmerBg.visible' 'TaskView shimmer must stop when TaskView closes'
require "$window_thumb" 'mipmap: false' 'TaskView window previews must avoid unnecessary mipmap generation'
require "$window_thumb" 'sourceSize.width: Math.max(1, Math.ceil(root.thumbnailWidth * 1.5))' 'TaskView window previews must use bounded decode size'

require "$easyeffects" 'readonly property bool uiDemand:' 'EasyEffects must expose demand-aware state polling'
require "$easyeffects" 'interval: root.uiDemand ? 5000 : 30000' 'EasyEffects must use slow background verification'
require "$easyeffects" 'running: Config.ready && root.available && (root.uiDemand || root.active)' 'EasyEffects polling must sleep when inactive and hidden'

# Worker cadence/timeout guards now run against the owned Alis-Intergration workers.
# Core typed facades must not retain a second process/timer owner.
for facade in "$tlp" "$thinkfan" "$tlp_caps" "$tlp_settings"; do
    require "$facade" 'AlisIntergration.session' 'integration facade must use the selected optional session'
    reject "$facade" 'Process {' 'core facade must not retain a duplicate helper process'
    reject "$facade" 'Timer {' 'core facade must not retain duplicate background polling'
done
require "$power_profiles" 'readonly property int _tlpProbeFreshnessMs: 5 * 60 * 1000' 'tlp-pd ownership demand refresh must preserve the former five-minute freshness bound'
require "$power_profiles" 'readonly property int _tlpSafetyProbeIntervalMs: 30 * 60 * 1000' 'tlp-pd ownership idle safety probes must stay sparse'
require "$power_profiles" 'interval: root._tlpSafetyProbeIntervalMs' 'tlp-pd ownership safety timer must use the sparse cadence'
require "$power_profiles" 'Date.now() - root._lastTlpProbeAt >= root._tlpProbeFreshnessMs' 'power-profile changes must demand-refresh stale tlp-pd ownership'

require "$memory_pressure" 'path: "/proc/self/maps"' 'memory pressure monitoring must read the shell process maps directly'
require "$memory_pressure" 'blockLoading: true' 'memory pressure proc-map reads must complete before parsing the snapshot'
require "$memory_pressure" 'root._applyMapsText(mapsFile.text())' 'memory pressure monitoring must parse the direct proc-map snapshot'
reject "$memory_pressure" 'Process {' 'memory pressure monitoring must not spawn a helper process for periodic proc-map reads'
reject "$memory_pressure" '/proc/$PPID/maps' 'memory pressure monitoring must not depend on a child-process parent PID workaround'

require "$world_clock" 'id: minuteTick' 'WorldClock must tick at minute precision without a permanent 1 Hz timer'
reject "$world_clock" 'interval: 1000' 'WorldClock must not restore a 1 Hz background timer'
require "$world_clock" 'printf '\''%(%z)T\\n'\'' -1' 'WorldClock offset refresh must use one shell process with builtin timezone formatting'
reject "$world_clock" 'date +%z' 'WorldClock must not spawn one date child per timezone'
reject "$world_clock" 'environment: ({ TZ:' 'WorldClock must not restore one date process per timezone'
require "$sidebar_world_clock" 'printf '\''%s|%(' 'Sidebar World Clock must format zones with Bash builtin printf'
require "$sidebar_world_clock" 'command.push(String(tzs[i]))' 'Sidebar World Clock must pass timezone names as argv'
reject "$sidebar_world_clock" ' date '\''+' 'Sidebar World Clock must not spawn one date child per timezone'
require "$sidebar_world_clock" 'root._formatOffset(rest[1])' 'Sidebar World Clock must preserve colonized UTC offsets'
require "$game_mode" 'Math.max(10000, Math.round(configured))' 'GameMode fallback polling must remain low cadence'
require "$game_mode" 'readonly property string _stateFile: Directories.stateUserPath + "/gamemode_active"' 'GameMode state must use the shared state directory'
require "$game_mode" 'id: stateWriter' 'GameMode state persistence must stay in-process'
require "$game_mode" 'atomicWrites: true' 'GameMode state persistence must remain atomic'
require "$game_mode" 'property bool _stateWriteQueued: false' 'GameMode rapid toggles must retain last-write queueing'
reject "$game_mode" 'id: saveProcess' 'GameMode manual state writes must not spawn a shell process'
reject "$game_mode" 'Quickshell.execDetached(["/usr/bin/mkdir"' 'GameMode must not duplicate state-directory creation on startup'

require "$directories" 'Quickshell.execDetached([' 'directory bootstrap must remain asynchronous'
require "$directories" '"/usr/bin/bash", "-c"' 'directory bootstrap must consolidate startup filesystem work'
require "$directories" 'rm -rf -- \"$1\" \"$2\" \"$3\" \"$4\"' 'directory bootstrap must clean transient trees before recreation'
require "$directories" 'mkdir -p -- \"$5\" \"$6\" \"$7\" \"$8\" \"$9\" \"${10}\" \"${11}\" \"${12}\" \"${13}\" \"${14}\"' 'directory bootstrap must recreate every required state/cache directory in one batch'
directories_exec_count="$(grep -Fc 'Quickshell.execDetached([' "$directories")"
[[ "$directories_exec_count" -eq 1 ]] || fail "Directories startup must use exactly one detached bootstrap command (found $directories_exec_count)"

require "$conflict_killer" 'id: conflictProbe' 'conflict detection must use one consolidated startup probe'
require "$conflict_killer" 'for comm in /proc/[0-9]*/comm; do' 'conflict detection must inspect process names without separate pidof helpers'
require "$conflict_killer" 'mako|dunst) notifs=1 ;;' 'conflict detection must preserve notification-daemon detection'
require "$conflict_killer" 'kded6) trays=1 ;;' 'conflict detection must preserve tray-conflict detection'
reject "$conflict_killer" 'id: pidofTraysProc' 'conflict detection must not restore a dedicated tray pidof process'
reject "$conflict_killer" 'id: pidofNotifsProc' 'conflict detection must not restore a dedicated notification pidof process'

require "$shell_qml" 'root._globalActionsService = GlobalActions;' 'GlobalActions IPC singleton must remain resident at Tier 0'
require "$shell_qml" 'root._globalActionsService.refreshSetupActions();' 'setup recipe discovery must be deferred until Tier 3'
require "$global_actions" 'property bool _setupScanEnabled: false' 'GlobalActions setup discovery must start disabled'
require "$global_actions" 'function refreshSetupActions(): void {' 'GlobalActions must expose explicit deferred setup discovery'
require "$global_actions" 'if (root._setupScanEnabled)' 'setup-folder changes must not spawn the scanner before deferred initialization'
reject "$global_actions" 'Component.onCompleted: { setupScanner.running = false; setupScanner.running = true }' 'GlobalActions must not run the setup scanner during Tier 0 construction'

require "$first_run" 'id: firstRunMarker' 'first-run marker detection must use in-process file I/O'
require "$first_run" 'firstRunMarker.reload()' 'first-run load must refresh the marker directly'
require "$first_run" 'blockLoading: true' 'first-run marker reload must resolve before deciding whether to launch first-run work'
reject "$first_run" 'id: checkFirstRunProc' 'normal shell startup must not spawn a process just to test the first-run marker'
reject "$first_run" 'command: ["/usr/bin/test", "-f", root.firstRunFilePath]' 'first-run marker detection must not shell out to test -f'

require "$shell_qml" 'root._shellUpdatesService = ShellUpdates;' 'Tier 4 must retain background shell-update initialization'
require "$shell_qml" 'root._autostartService = Autostart;' 'Tier 4 must retain the Autostart IPC/file-watch service'
require "$shell_qml" 'root._calendarSyncService = CalendarSync' 'Tier 4 must retain configured calendar background sync'
require "$shell_qml" 'root._fontSyncService = FontSyncService' 'Tier 4 must retain deferred desktop font synchronization'
reject "$shell_qml" 'property var _todoService' 'Todo must remain demand-loaded instead of forced at shell startup'
reject "$shell_qml" 'property var _notepadService' 'Notepad must remain demand-loaded instead of forced at shell startup'
reject "$shell_qml" 'root._todoService = Todo;' 'Tier 4 must not force-load Todo storage'
reject "$shell_qml" 'root._notepadService = Notepad;' 'Tier 4 must not force-load Notepad storage'

tier3_block="$(sed -n '/Tier 3: T+500ms/,/Tier 4: T+1500ms/p' "$shell_qml")"
if grep -Fq 'root._fontSyncService = FontSyncService' <<<"$tier3_block"; then
    fail 'FontSyncService must not run in Tier 3 display/interaction startup'
fi
require "$overview_window" 'layer.enabled: GlobalStates.overviewOpen' 'retained Overview window masks must sleep while Overview is closed'
require "$ii_panels" 'OnDemandPanelLoader { identifier: "iiOverview"; open: GlobalStates.overviewOpen; closeGraceMs: Appearance.animation.elementMoveExit.duration + 80;' 'ii Overview must unload after its exit animation instead of using long idle retention'
reject "$ii_panels" 'identifier: "iiOverview"; open: GlobalStates.overviewOpen; retainAfterUse: true' 'ii Overview must not restore five-minute post-use residency'
require "$waffle_panels" 'import qs.modules.waffle.looks' 'Waffle panel host must resolve animation-aware close grace from shared Looks tokens'
require "$waffle_panels" 'OnDemandPanelLoader { identifier: "wActionCenter"; open: GlobalStates.waffleActionCenterOpen; closeGraceMs: Looks.transition.enabled ? Looks.transition.duration.medium + 40 : 40;' 'Waffle Action Center must unload after its real close animation plus safety grace'
reject "$waffle_panels" 'identifier: "wActionCenter"; open: GlobalStates.waffleActionCenterOpen; retainAfterUse: true' 'Waffle Action Center must not restore five-minute hidden residency'
require "$waffle_panels" 'OnDemandPanelLoader { identifier: "iiOverview"; open: GlobalStates.overviewOpen; closeGraceMs: Appearance.animation.elementMoveExit.duration + 80;' 'Waffle Overview host must unload after the same exit-aware grace as ii'
reject "$waffle_panels" 'identifier: "iiOverview"; open: GlobalStates.overviewOpen; retainAfterUse: true' 'Waffle Overview host must not restore five-minute post-use residency'
require "$global_states" 'property string wallpaperLauncherSearchText: ""' 'Wallpaper Launcher query state must survive visual-tree teardown'
python3 "$repo_root/scripts/test-wallpaper-search-state.py"
require "$wallpaper_launcher" 'interval: Math.max(220, Appearance.animation.elementMoveExit.duration + 20)' 'Wallpaper Launcher close timer must still cover the visible exit animation'
require "$wallpaper_coverflow" 'interval: Appearance.calcEffectiveDuration(450)' 'Coverflow inner loader must preserve the full exit lifecycle'
require "$resource_usage" '? Math.max(6000, root._configuredUpdateIntervalMs)' 'Low Power must slow resource sampling to at least 6 seconds'
require "$resource_usage" 'interval: root._effectiveUpdateIntervalMs' 'resource sensor timer must use the effective power-aware cadence'
require "$resource_usage" 'readonly property int _expensiveGpuUpdateIntervalMs:' 'process-backed GPU sampling must use a slower independent cadence'
require "$resource_usage" '? Math.max(15000, root._effectiveUpdateIntervalMs)' 'Low Power must throttle nvidia-smi/intel_gpu_top sampling to at least 15 seconds'
require "$bar_resources" 'ResourceUsageMonitor {' 'horizontal Bar resources must use centralized telemetry lifecycle ownership'
require "$bar_resources" 'active: !GameMode.active' 'horizontal Bar resource polling must pause in GameMode'
require "$vertical_bar_resources" 'ResourceUsageMonitor {' 'vertical Bar resources must use centralized telemetry lifecycle ownership'
require "$vertical_bar_resources" 'active: !GameMode.active' 'vertical Bar resource polling must pause in GameMode'
require "$recorder_status" '(Config.options?.performance?.lowPower ?? false) ? 30000 : 15000' 'idle recorder detection must not spawn pgrep every five seconds'
require "$recorder_status" 'interval: root.idlePollIntervalMs' 'RecorderStatus idle polling must use its power-aware cadence'
# Both Dashboard routes, hidden cadence and event refresh are exercised in
# test-local-music-demand-runtime.py against the actual QML/status process.
require "$local_music" 'running: root.enabled && !root._mpdSubscriptionActive' 'LocalMusic fallback polling must remain disabled while native MPD subscription is active'

require "$mpris_controller" 'property bool _browserCapabilitiesProbed: false' 'MPRIS browser capability probing must begin lazy'
require "$mpris_controller" 'function _ensureBrowserCapabilities(player = null): void' 'MPRIS must expose demand-driven browser capability probing'
require "$mpris_controller" 'root._ensureBrowserCapabilities(modelData)' 'browser capability probing must begin when a browser MPRIS player appears'
require "$mpris_controller" 'if ((Audio.outputAppNodes?.length ?? 0) > 0)' 'MPRIS startup metadata probing must require an application audio stream'
require "$mpris_controller" 'root._streamMetadataById = ({})' 'MPRIS must clear stale PipeWire metadata when application streams disappear'
reject "$mpris_controller" 'id: plasmaCheckDefer' 'MPRIS must not schedule an unconditional browser-capability startup probe'
reject "$mpris_controller" 'plasmaCheckDefer.start()' 'MPRIS browser capability probing must not run from startup/config readiness'
require "$recorder_status" 'property int fastDemandCount: 0' 'RecorderStatus fast polling must be explicitly demand-owned'
require "$recorder_status" 'function setFastStatusDemand(owner: string, active: bool): void' 'RecorderStatus must expose keyed demand ownership'
require "$recorder_status" 'running: Config.ready && !root.isRecording && !root.fastStatusDemand' 'RecorderStatus slow global fallback must remain active only without fast UI demand'
require "$recorder_status" 'id: fastPollTimer' 'RecorderStatus must expose a separate demand-driven fast poll'
require "$recorder_status" 'interval: 1000' 'RecorderStatus visible-UI reconciliation must use a 1 second cadence'
require "$recorder_status" '&& !quickCheckTimer.running' 'RecorderStatus demand polling must yield to bounded action quick checks'
require "$recorder_overlay_widget" 'RecorderStatus.setFastStatusDemand("ii-overlay-recorder", wanted)' 'ii Recorder widget must own fast status demand only while visible'
require "$recorder_overlay_widget" 'if (root._statusDemandRegistered)' 'ii Recorder widget must release its fast-demand lease on destruction'
require "$recorder_overlay_widget" 'running: RecorderStatus.isRecording && root.visible' 'retained ii Recorder pulse must sleep while the widget is hidden'
require "$overlay_taskbar" 'readonly property bool presentationActive:' 'retained Overlay taskbar must expose fade-aware presentation state'
require "$overlay_taskbar" 'layer.enabled: Appearance.angelEverywhere && root.presentationActive' 'Overlay taskbar mask FBO must sleep after its exit fade'
require "$overlay_taskbar" 'visible: Appearance.angelEverywhere && root.presentationActive' 'Overlay Angel wallpaper source must unload after the taskbar fade'
require "$overlay_taskbar" 'layer.enabled: Appearance.effectsEnabled && Appearance.angelEverywhere && root.presentationActive' 'Overlay Angel blur FBO must sleep while the taskbar is hidden'
require "$overlay_floating_image" 'layer.enabled: root.visible && (root.QsWindow.window?.visible ?? false)' 'retained Floating Image mask FBO must sleep while hidden'
require "$overlay_floating_image" 'playing: root.visible && (root.QsWindow.window?.visible ?? false)' 'retained Floating Image animation decoder must pause while hidden'
require "$overlay_resources" 'layer.enabled: root.visible && (root.QsWindow.window?.visible ?? false)' 'retained Overlay resource graph mask must sleep while hidden'
require "$waffle_widgets_content" 'RecorderStatus.setFastStatusDemand("waffle-widgets-recorder", wanted)' 'Waffle recorder quick action must own fast status demand only while its panel is open'
require "$weather" 'readonly property int _clockMinute: root.enabled ? DateTime.clock.minutes : -1' 'Weather live sun/moon context must reuse the shared minute clock only while enabled'
reject "$weather" 'id: clockTickTimer' 'Weather must not own a duplicate minute timer'
reject "$weather" 'interval: 60000' 'Weather must not add a private 60-second wakeup for sun/moon context'
require "$wallhaven_service" 'function _schedulePendingSearch(): void' 'Wallhaven pending search retries must use deadline scheduling'
require "$wallhaven_service" '_pendingSearchTimer.interval = Math.max(1, Math.round(due - now))' 'Wallhaven pending search timer must target the exact retry deadline'
require "$wallhaven_service" 'repeat: false' 'Wallhaven pending search retry must stay one-shot'
reject "$wallhaven_service" 'property Timer pendingSearchTimer: Timer {' 'Wallhaven must not restore the 300 ms pending-search polling timer'
reject "$wallhaven_service" 'property Timer wallhavenClock: Timer {' 'Wallhaven must not restore the dead 500 ms clock'
require "$wallhaven_service" 'function _scheduleTagCount(): void' 'Wallhaven tag-count queue must use one-shot deadline scheduling'
require "$wallhaven_service" '_tagCountTimer.interval = root._tagDelayMs()' 'Wallhaven tag-count timer must target the next allowed deadline'
require "$wallhaven_service" 'function _scheduleTagDetail(): void' 'Wallhaven tag-detail queue must use one-shot deadline scheduling'
require "$wallhaven_service" 'tagQueueTimer.interval = root._tagDelayMs()' 'Wallhaven tag-detail timer must target the next allowed deadline'
reject "$wallhaven_service" 'interval: 350' 'Wallhaven tag queues must not restore 350 ms polling'
require "$keyboard_indicators" 'readonly property int ledDiscoveryIntervalMs: root.hasKnownLedPaths' 'keyboard sysfs discovery must adapt to stable watched paths'
require "$keyboard_indicators" '? ((Config.options?.performance?.lowPower ?? false) ? 600000 : 300000)' 'stable keyboard LED paths must use sparse safety discovery'
require "$keyboard_indicators" ': ((Config.options?.performance?.lowPower ?? false) ? 120000 : 30000)' 'missing keyboard LED paths must retain responsive discovery'
require "$keyboard_indicators" 'Qt.callLater(() => root.refreshLedPaths())' 'lost watched keyboard LED paths must trigger immediate rediscovery'

require "$icon_theme_service" 'function ensureThemesLoaded(force = false)' 'icon theme enumeration must be demand-driven'
require "$icon_theme_service" 'if (root._themesLoaded && !force)' 'icon theme enumeration must be cached after first demand'
require "$icon_theme_selector" 'IconThemeService.ensureThemesLoaded()' 'icon theme selector must trigger enumeration only when opened'
require "$sidebar_anime" 'layer.enabled: root.visible && GlobalStates.sidebarLeftOpen' 'Anime list mask must sleep with the sidebar'
require "$sidebar_wallhaven" 'layer.enabled: root.visible && GlobalStates.sidebarLeftOpen' 'Wallhaven list mask must sleep with the sidebar'
require "$sidebar_ai" 'layer.enabled: root.visible && GlobalStates.sidebarLeftOpen' 'AI history mask must sleep with the sidebar'
require "$sidebar_quick_wallpaper" 'layer.enabled: root.visible && GlobalStates.sidebarLeftOpen' 'Quick Wallpaper masks must sleep with the sidebar'
require "$booru_image" 'layer.enabled: root.visible && GlobalStates.sidebarLeftOpen' 'Booru image masks must sleep with the sidebar'
require "$booru_response" 'layer.enabled: root.visible && GlobalStates.sidebarLeftOpen' 'Booru tag masks must sleep with the sidebar'
require "$ai_think_block" 'layer.enabled: root.visible && GlobalStates.sidebarLeftOpen' 'AI think-block masks must sleep with the sidebar'
require "$sidebar_right_tasks" '(GlobalStates.sidebarRightOpen || GlobalStates.dashboardOpen || GlobalStates.overviewOpen)' 'To-do list mask must remain active in right-sidebar, dashboard, and Overview hosts'
reject "$sidebar_right_notifications" 'layer.effect: OpacityMask' 'rectangular notification clipping must not allocate an OpacityMask FBO'
require "$sidebar_right_media" 'GlobalStates.sidebarRightOpen && root.visible && !root.zzzStyle' 'right-sidebar media mask must sleep while closed'
require "$sidebar_right_media" 'GlobalStates.sidebarRightOpen && root.visible && Appearance.effectsEnabled && visible' 'right-sidebar media blur must sleep while closed'
reject "$sidebar_right_media" 'CavaProcess {' 'right-sidebar media must not run duplicate Cava above the shared EQ'
reject "$sidebar_right_media" 'WaveVisualizer {' 'right-sidebar media must not render duplicate Cava above the shared EQ'
require "$control_panel_wallpaper" 'layer.enabled: root.visible && GlobalStates.controlPanelOpen' 'Control Panel wallpaper mask must sleep while closed'
require "$control_panel_wallpaper" 'mipmap: false' 'Control Panel wallpaper preview must not generate unused mipmaps'
require "$wallpaper_skew_view" 'id: videoPreviewPlayerLoader' 'Wallpaper Skew preview decoder must be lazy-loaded per current video'
require "$wallpaper_skew_view" 'active: videoPreviewOutput._shouldPlay' 'Wallpaper Skew preview decoder must sleep for cached non-current delegates'
require "$wallpaper_skew_view" 'onLoaded: if (item) item.play()' 'Wallpaper Skew preview must start playback after lazy decoder creation'
if grep -Eq '^[[:space:]]*id:[[:space:]]+videoPreviewPlayer[[:space:]]*$' "$wallpaper_skew_view"; then
    fail 'Wallpaper Skew cached delegates must not restore eager MediaPlayer instances'
fi
require "$dash_media" 'property bool presentationActive:' 'Dashboard media lifecycle must remain writable for DashboardCanvas and Overview hosts'
reject "$dash_media" 'readonly property bool presentationActive:' 'Dashboard media lifecycle must not become readonly while DashboardCanvas binds it'
reject "$dash_media" 'CavaProcess {' 'Dashboard media must not run duplicate Cava above the shared EQ'
require "$dash_media" 'visualizerPoints: []' 'Dashboard PlayerControl must not consume decorative Cava points'
require "$dash_media" 'showVisualizer: false' 'Dashboard PlayerControl decorative visualizer must remain disabled'
require "$dash_media" 'active: root.hasPlayer' 'Dashboard shared PlayerControl must stay resident so artwork/masks do not rebuild during slide presentation'
require "$dash_media" 'PlayerControl {' 'Dashboard media must reuse the canonical shared player surface'
require "$dash_welcome" 'layer.enabled: root.visible && status === Image.Ready' 'Dashboard avatar mask must stay circular through the visible exit slide and sleep once hidden'
require "$dash_welcome" 'mipmap: false' 'Dashboard avatar must not generate unused mipmaps'
require "$ii_panels" 'keepLoaded: true' 'Dashboard must remain preloaded and resident'
reject "$ii_panels" 'property bool retainAfterUse:' 'ii shared on-demand loader must not restore arbitrary post-use retention'
reject "$ii_panels" 'property int retainIdleMs:' 'ii shared on-demand loader must not restore five-minute idle retention'
reject "$ii_panels" 'property Timer retainIdle:' 'ii shared on-demand loader must not allocate a retention timer per surface'
require "$ii_panels" 'property bool used: false' 'ii Dashboard explicit first-use residency must keep its lightweight used flag'
reject "$waffle_panels" 'property bool retainAfterUse:' 'Waffle shared on-demand loader must not restore arbitrary post-use retention'
reject "$waffle_panels" 'property bool used:' 'Waffle shared on-demand loader must not keep unused first-use state'
reject "$waffle_panels" 'property int retainIdleMs:' 'Waffle shared on-demand loader must not restore five-minute idle retention'
reject "$waffle_panels" 'property Timer retainIdle:' 'Waffle shared on-demand loader must not allocate a retention timer per surface'
reject "$waffle_panels" 'retainAfterUse: true' 'Waffle panels must use finite close grace rather than post-use residency'
reject "$ii_panels" 'retainAfterUse: true' 'ii panels must use finite close grace or explicit keepLoaded semantics'
require "$dashboard" 'visible: true' 'Dashboard native layer-shell surface must remain mapped after first use'
require "$dashboard" 'updatesEnabled: root._renderUpdatesNeeded' 'Hidden Dashboard must suspend rendering without unmapping'
require "$dashboard" 'mask: dashboardInputRegion' 'Closed mapped Dashboard must expose an empty input region'
require "$dashboard" 'active: true' 'Dashboard widget tree must remain mounted while the retained surface exists'
require "$dashboard" 'visible: root._contentPresented' 'Dashboard content paint must hide only after the exit slide'
require "$dashboard" 'id: _presentationTimer' 'Dashboard reopen must paint a closed frame before entering the open slide state'
require "$dashboard" 'interval: 16' 'Dashboard slide arming must wait for a rendered frame'
require "$dashboard" 'panelTranslateY: SurfaceMotion.dashboardOffset' 'Dashboard closed state must remain a translated slide state'
require "$dashboard" 'duration: SurfaceMotion.dashboardEnterDuration' 'Dashboard entrance must use the tuned smooth slide duration'
require "$dashboard" 'easing.type: SurfaceMotion.dashboardEnterEasingType' 'Dashboard entrance must use the tuned deceleration curve'
require "$dashboard" 'duration: SurfaceMotion.dashboardExitDuration' 'Dashboard exit must use the tuned smooth slide duration'
require "$dashboard" 'easing.type: SurfaceMotion.dashboardExitEasingType' 'Dashboard exit must use the tuned acceleration curve'
reject "$dashboard" '_slideLayerActive' 'Dashboard slide must not wrap nested media effect layers in a transient whole-surface FBO'
require "$dashboard" 'presentationActive: root._contentPresented' 'Standalone Dashboard media lifecycle must remain active through the full exit slide'
require "$dashboard" 'opacity: 1' 'Dashboard entrance must not use opacity fading'
require "$dashboard" 'scale: 1' 'Dashboard entrance must not use scale animation'
reject "$dashboard" 'onTriggered: panelRoot.visible = false' 'Dashboard close must not unmap the native surface after the slide'
reject "$dashboard" 'Qt.callLater(() => { root._presentedOpen' 'Dashboard open must not race compositor mapping with a zero-delay state flip'
reject "$dashboard_settings" 'Preload Dashboard' 'Dashboard preload is always enabled and not exposed as a toggle'

require "$screen_time" 'target: CompositorService.isNiri ? NiriService : null' 'Screen Time must use Niri focus events'
require "$screen_time" 'interval: CompositorService.isNiri' 'Screen Time must keep only a coarse Niri heartbeat'
require "$ytmusic" 'id: _ipcStateProc' 'YT Music fallback must batch mpv IPC state queries'
reject "$ytmusic" 'id: _ipcQueryProc' 'YT Music must not restore separate time-position subprocess polling'
reject "$ytmusic" 'id: _ipcPauseQueryProc' 'YT Music must not restore separate pause subprocess polling'
reject "$ytmusic" 'id: _ipcEofQueryProc' 'YT Music must not restore separate EOF subprocess polling'
reject "$directory_icon" 'command: ["file", "--mime"' 'DirectoryIcon must not spawn one MIME process per item'
reject "$sysmon_widget" 'command: ["/usr/bin/cat", "/proc/net/dev"]' 'SysMon must reuse shared ResourceUsage network telemetry'
require "$sysmon_widget" 'ResourceUsage.networkRxBytesPerSec' 'SysMon network receive rate must come from ResourceUsage'
require "$sysmon_widget" 'ResourceUsage.networkTxBytesPerSec' 'SysMon network transmit rate must come from ResourceUsage'

require "$timer_service" 'SystemClock {' 'Pomodoro and countdown must share one second-aligned clock'
require "$timer_service" 'precision: SystemClock.Seconds' 'shared timer clock must use second precision'
require "$timer_service" 'function refreshSecondTimers(): void {' 'shared timer refresh fan-out must remain explicit'
require "$timer_service" 'id: stopwatchTimer' 'stopwatch must retain its independent high-frequency timer'
require "$timer_service" 'interval: 33' 'stopwatch must retain the 33 ms presentation cadence'
reject "$timer_service" 'id: pomodoroTimer' 'Pomodoro must not restore a dedicated 200 ms timer'
reject "$timer_service" 'id: countdownTimer' 'Countdown must not restore a dedicated 200 ms timer'

require "$levendist" 'function levenshteinDistance(s1, s2, rows)' 'fuzzy search must accept reusable Levenshtein rows'
require "$levendist" 'if (longS.includes(shortS)) return 1.0;' 'fuzzy search must fast-path exact substring matches'
require "$levendist" 'const rows = [new Array(lenS + 1), new Array(lenS + 1)];' 'partial fuzzy matching must reuse one row workspace'
require "$levendist" 'levenshteinDistance(shortS, sub, rows)' 'partial fuzzy matching must reuse the shared row workspace'

require "$cliphist" 'const searchLower = search.toLowerCase()' 'Clipboard sloppy search must lowercase the query once'
require "$cliphist" 'root._insertTopScored(top,' 'Clipboard bounded sloppy search must avoid full sorting'
require "$clipboard_panel" 'interval: Appearance.animationsEnabled ? SurfaceMotion.duration + 16 : 1' 'Clipboard native window must stay mapped through the full connected-surface exit'
require "$ii_panels" 'identifier: "iiClipboard"; open: GlobalStates.clipboardOpen; closeGraceMs: Appearance.animationsEnabled ? SurfaceMotion.duration + 48 : 40;' 'ii Clipboard outer loader must outlive its close animation then release'
reject "$ii_panels" 'identifier: "iiClipboard"; open: GlobalStates.clipboardOpen; retainAfterUse: true' 'ii Clipboard must not restore five-minute hidden residency'
require "$emojis_service" 'const searchLower = search.toLowerCase()' 'Emoji sloppy search must lowercase the query once'
require "$emojis_service" 'root._insertTopScored(top,' 'Emoji bounded sloppy search must avoid full sorting'
require "$emojis" 'function _ensurePreparedEntries(): var' 'Emoji fuzzy index must stay lazy'
require "$emojis" 'Fuzzy.go(search, root._ensurePreparedEntries(),' 'Emoji search must build its index only on demand'
reject "$emojis" 'readonly property var preparedEntries:' 'Emoji service must not eagerly prepare the full list'
require "$app_search" 'function _ensurePreppedNames(): var' 'AppSearch fuzzy names must stay lazy'
require "$app_search" 'function _ensurePreppedIcons(): var' 'AppSearch fuzzy icons must stay lazy'
reject "$app_search" '_cachedPreppedNames = entries.map' 'AppSearch rebuild must not fuzzy-prepare every app name'
reject "$app_search" '_cachedPreppedIcons = entries.map' 'AppSearch rebuild must not fuzzy-prepare every app icon'

require "$settings_page_host" 'const source = pages[index]?.component ?? ""' 'Settings page host must normalize the resolved page source once'
require "$settings_page_host" 'if (source.startsWith("/"))' 'Settings page host must recognize absolute local QML page paths'
require "$settings_page_host" 'return "file://" + source' 'Settings page host must expose local pages as file URLs so Qt can reuse the QML disk cache'

require "$loading_indicator" 'import QtQuick.Window' 'loading indicator must observe owning window visibility'
require "$loading_indicator" '(root.Window.window?.visible ?? true)' 'loading indicator must stop while its owning window is hidden'
require "$circular_progress" 'import QtQuick.Window' 'circular progress must observe owning window visibility'
require "$circular_progress" 'root.visible && (root.Window.window?.visible ?? true)' 'circular progress animations must sleep while hidden'
require "$clipped_filled_progress" 'root.visible && (root.Window.window?.visible ?? true)' 'filled clipped progress animation must sleep while hidden'
require "$clipped_outline_progress" 'root.visible && (root.Window.window?.visible ?? true)' 'outline clipped progress animation must sleep while hidden'
require "$wavy_line" '(root.Window.window?.visible ?? true)' 'wavy line animation must sleep with its owning window'
require "$shell_update_indicator" 'ShellUpdates.isUpdating && root.visible' 'shell update spinner must stop when the indicator is hidden'
require "$shell_update_indicator" '(root.Window.window?.visible ?? true)' 'shell update animations must sleep with the Bar window'

require "$shell_updates" 'readonly property int startupFreshnessMs: Math.min(root.checkIntervalMs, 30 * 60 * 1000)' 'shell update startup network freshness must stay bounded'
require "$shell_updates" 'path: root.lastCheckCachePath' 'shell update remote freshness must persist across shell restarts'
require "$shell_updates" 'root._startupRemoteCheckFresh()' 'shell update startup must consult remote freshness before fetching'
require "$shell_updates" 'root._startLocalComparison()' 'fresh shell update startup checks must rebuild state from local remote refs'
require "$shell_updates" 'lastCheckFile.setText(String(Math.floor(now)))' 'successful shell update fetches must persist freshness'
require "$shell_updates" 'function check(): void {' 'manual shell update check API must remain available'
require "$shell_updates" 'fetchProc.running = true' 'manual and periodic shell update checks must continue to fetch the remote'
require "$shell_updates" 'id: versionFile' 'shell update startup must read version.json in-process'
require "$shell_updates" 'id: manifestFile' 'shell update startup must read manifest metadata in-process'
require "$shell_updates" 'id: repoVersionFile' 'shell update startup must read the repo VERSION in-process'
require "$shell_updates" 'id: updateResumeFile' 'shell update startup must check for a resume marker before spawning the staleness helper'
reject "$shell_updates" 'id: loadRepoPathProc' 'shell update startup must not spawn cat for version.json'
reject "$shell_updates" 'id: manifestInfoProc' 'shell update startup must not spawn a shell pipeline for manifest metadata'
reject "$shell_updates" 'id: localVersionStartupProc' 'shell update startup must not spawn a shell helper for VERSION'

require "$system_updates" 'if (checkUpdatesProc.running) return;' 'system update checks must deduplicate the real checker process'
require "$system_updates" 'root.available = true' 'a successful system update checker spawn must establish availability'
reject "$system_updates" 'checkAvailabilityProc' 'system updates must not spawn a separate availability process'
reject "$system_updates" 'command -v checkupdates' 'system updates must not shell out solely to probe checkupdates availability'
require "$util_buttons" '(root.QsWindow.window?.visible ?? true)' 'ii Bar status pulses must sleep with the Bar window'
require "$waffle_system_button" '(root.Window.window?.visible ?? true)' 'Waffle system status pulses must sleep with the taskbar window'
require "$waffle_timer_button" '(root.Window.window?.visible ?? true)' 'Waffle timer pulse must sleep with the taskbar window'

printf 'performance lifecycle guards: ok\n'
