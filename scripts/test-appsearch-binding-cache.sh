#!/usr/bin/env bash
# A real QML binding must be able to build the lazy fuzzy icon/name indices.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null;then printf 'SKIP: AppSearch binding cache (Quickshell unavailable)\n';exit 0;fi
search_test_root="$(mktemp -d)"
trap 'rm -rf -- "$search_test_root"' EXIT
for entry in modules services GlobalStates.qml qmldir assets scripts defaults translations;do ln -s "$repo_root/$entry" "$search_test_root/$entry";done
mkdir -p "$search_test_root/config/illogical-impulse"
cp "$repo_root/defaults/config.json" "$search_test_root/config/illogical-impulse/config.json"
cat > "$search_test_root/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.services
ShellRoot {
    id:root;property int step:0;property bool finished:false
    property string query:"alis-nonexistent-binding-fixture"
    readonly property string guessedIcon:AppSearch.guessIcon(query)
    function check(ok,message): bool { if(ok)return true;console.error("SEARCH_CACHE_FAIL",message);finished=true;return false }
    Timer {
        interval:150;running:!root.finished;repeat:true
        onTriggered: {
            if(root.step===2) {
                if(!root.check(root.guessedIcon.length>0 && AppSearch._lazyPrepared.iconsRevision===AppSearch._cacheRevision,"binding builds lazy icon index")) return
                const first=AppSearch._ensurePreppedIcons()
                if(!root.check(AppSearch._ensurePreppedIcons()===first,"same revision reuses one prepared index")) return
                AppSearch._cacheRevision++
                const second=AppSearch._ensurePreppedIcons()
                if(!root.check(second!==first,"changed revision builds a fresh index")) return
                root.query+="-updated"
            } else if(root.step===4) {
                if(!root.check(AppSearch._preppedIconsRevision===AppSearch._cacheRevision && AppSearch.preppedIcons===AppSearch._lazyPrepared.icons,"deferred publication follows the current revision")) return
                console.info("SEARCH_CACHE_PASS");root.finished=true
            }
            root.step++
        }
    }
}
QML
status=0
env -u QS_CONFIG_PATH -u QS_CONFIG_NAME -u QS_MANIFEST QT_QPA_PLATFORM=offscreen XDG_CONFIG_HOME="$search_test_root/config" XDG_STATE_HOME="$search_test_root/state" XDG_CACHE_HOME="$search_test_root/cache" timeout 4s qs -p "$search_test_root" --no-color > "$search_test_root/runtime.log" 2>&1 || status=$?
if [[ "$status" != 124 ]] || ! rg -q SEARCH_CACHE_PASS "$search_test_root/runtime.log" || rg -q 'SEARCH_CACHE_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign' "$search_test_root/runtime.log";then cat "$search_test_root/runtime.log";exit 1;fi
printf 'PASS: lazy search indices are safe in QML bindings, reused per revision and published without stale races\n'
