#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dispatch="$root/scripts/native-dispatch"
harness="$root/scripts/native-cutover-benchmark.sh"

[[ -x "$dispatch" ]] || fail 'native-dispatch must be executable'
[[ -x "$harness" ]] || fail 'native cutover harness must be executable'

for token in     'input-lock)'     'input-keys)'     'niri)'     'clipboard-store)'     'mpd)'     'mpd-daemon)'     'mpd-subscribe)'     'lyrics)'     'theme)'     'theme-preview)'     'least-busy-region)'     'scan-plugins)'     'telemetry)'     'desktop-icons)'
do
    grep -Fq "$token" "$dispatch"         || fail "native-dispatch missing route: $token"
done

grep -Fq 'command: [root.nativeDispatchPath, "input-lock", "--once"]'     "$root/services/KeyboardIndicators.qml"     || fail 'KeyboardIndicators probe must route through native-dispatch'
grep -Fq 'command: [root.nativeDispatchPath, "input-lock"]'     "$root/services/KeyboardIndicators.qml"     || fail 'KeyboardIndicators monitor must route through native-dispatch'
grep -Fq 'command: [root.nativeDispatchPath, "input-keys"]'     "$root/modules/onScreenKeyboard/PhysicalKeyboardFeedback.qml"     || fail 'OSK physical keyboard feedback must route through native-dispatch'
grep -Fq 'root.nativeDispatchPath, "mpd",'     "$root/services/LocalMusic.qml"     || fail 'LocalMusic MPD operations must route through native-dispatch'
grep -Fq 'root.nativeDispatchPath, "mpd-daemon",'     "$root/services/LocalMusic.qml"     || fail 'LocalMusic persistent MPD daemon must route through native-dispatch'
grep -Fq 'root.nativeDispatchPath, "mpd-subscribe"'     "$root/services/LocalMusic.qml"     || fail 'LocalMusic MPD idle subscription must route through native-dispatch'
grep -Fq 'root.nativeDispatchPath, "lyrics", path'     "$root/services/LocalMusic.qml"     || fail 'LocalMusic lyrics must route through native-dispatch'
grep -Fq 'root.nativeDispatchPath, "niri",'     "$root/modules/settings/NiriConfig.qml"     || fail 'Niri settings must route through native-dispatch'
grep -Fq 'root.nativeDispatchPath, "niri", "get-binds"'     "$root/services/deferred/NiriKeybinds.qml"     || fail 'Niri enriched keybind loader must route through native-dispatch'
grep -Fq '_applyLegacyFromEnriched'     "$root/services/deferred/NiriKeybinds.qml"     || fail 'Niri cheatsheet must derive from the selector-backed get-binds result before legacy fallback'
grep -Fq '"niri",' "$root/services/NiriService.qml"     || fail 'NiriService hot-corner query must route through native-dispatch'
grep -Fq '"niri",' "$root/services/Wallpapers.qml"     || fail 'Wallpaper Niri shadow sync must route through native-dispatch'
grep -Fq 'root.nativeDispatchPath, "niri", "persist-layout"'     "$root/modules/settings/MonitorVisibilityConfig.qml"     || fail 'monitor layout persistence must route through native-dispatch'
grep -Fq "native-dispatch' clipboard-store --filter"     "$root/services/deferred/Cliphist.qml"     || fail 'Cliphist decode filter must route through native-dispatch'
grep -Fq 'native-dispatch clipboard-store'     "$root/defaults/niri/config.d/50-startup.kdl"     || fail 'default Niri clipboard watcher must route through native-dispatch'
grep -Fq 'native-dispatch clipboard-store'     "$root/sdata/migrations/049-native-clipboard-selector.sh"     || fail 'existing clipboard watchers must migrate through native-dispatch'
grep -Fq '"$SCRIPT_DIR/../native-dispatch" theme'     "$root/scripts/colors/switchwall.sh"     || fail 'theme pipeline must route through native-dispatch'
grep -Fq 'nativeIconSyncProc' "$root/services/IconThemeService.qml"     || fail 'IconThemeService must expose native sync test path'
grep -Fq 'nativeBackendStatePath' "$root/services/IconThemeService.qml"     || fail 'IconThemeService must honor persistent trial selector state after reboot'
grep -Fq '/alis-inputd([[:space:]]|$)' "$root/scripts/alis"     || fail 'shell restart cleanup must recognize Rust input daemon'

# The trial cutover harness must remain reversible. The live qualification loop
# alternates order to reduce warm-cache bias, so assert the semantic Rust path
# instead of requiring the old one-shot literal `measure_service_mode rust`.
grep -Fq 'order=(python rust)' "$harness"     || fail 'cutover harness must include Rust in odd live A/B rounds'
grep -Fq 'order=(rust python)' "$harness"     || fail 'cutover harness must include Rust in even live A/B rounds'
grep -Fq 'measure_service_mode "$mode" "$round"' "$harness"     || fail 'cutover harness must measure each selected backend in every live A/B round'
grep -Fq 'set_runtime_backend rust' "$harness"     || fail 'cutover harness must explicitly restore Rust test mode after alternating A/B'
grep -Fq 'ALIS_NATIVE_BACKEND=python' "$harness"     || fail 'cutover harness must provide Python rollback'
grep -Fq 'BACKEND_STATE_FILE="$STATE_DIR/native-backend"' "$harness"     || fail 'cutover harness must persist selector state for Niri-spawned helpers'
grep -Fq 'MODE_FILE="$STATE_DIR/native-backend"' "$dispatch"     || fail 'native-dispatch must read persistent selector state when env is absent'
grep -Fq 'BIN_DIR_FILE="$STATE_DIR/native-bin-dir"' "$dispatch"     || fail 'native-dispatch must read persistent native binary path for Niri-spawned helpers'
grep -Fq 'MODE="${MODE:-rust}"' "$dispatch"     || fail 'native-dispatch production default must be Rust'
grep -Fq 'DEFAULT_BIN_DIR="$ROOT_DIR/native/bin"' "$dispatch"     || fail 'native-dispatch must prefer packaged native binaries'
grep -Fq -- '--restore' "$harness"     || fail 'cutover harness must expose --restore'

# Python remains the explicit emergency fallback after production cutover.
for fallback in     scripts/daemon/keyboard_lock_state_daemon.py     scripts/daemon/osk_physical_key_daemon.py     scripts/local_music_mpd.py     scripts/niri-config.py     scripts/clipboard-store.py     scripts/colors/generate_colors_material.py     scripts/colors/preview-palette.py     scripts/images/least_busy_region.py     scripts/scan-plugins.py
do
    [[ -f "$root/$fallback" ]] || fail "Python fallback missing: $fallback"
done

printf 'PASS: native runtime selector is wired and reversible\n'
