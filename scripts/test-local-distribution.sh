#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
runtime_root="$(cd -- "$script_dir/.." && pwd)"
launcher="${ALIS_LAUNCHER_PATH:-$runtime_root/scripts/alis}"

run_runtime=false
fast_mode=false
list_only=false
only_pattern=""
color_mode="auto"

usage() {
    cat <<'USAGE'
Usage: bash scripts/test-local-distribution.sh [options]

Options:
  --with-runtime        Include live Quickshell restart/log checks
  --fast                Skip heavier subprocess tests for rapid verification
  --list                List planned checks without executing them
  --only PATTERN        Run only checks matching PATTERN (case-insensitive)
  --color / --no-color  Force or disable ANSI styling
  -h, --help            Show this help
USAGE
}

while (($# > 0)); do
    case "$1" in
        --with-runtime) run_runtime=true ;;
        --fast) fast_mode=true ;;
        --list) list_only=true ;;
        --only)
            shift
            [[ $# -gt 0 ]] || { printf 'FATAL: --only requires a pattern\n' >&2; exit 2; }
            only_pattern="$1"
            ;;
        --only=*) only_pattern="${1#--only=}" ;;
        --color) color_mode="always" ;;
        --no-color) color_mode="never" ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if [[ "$color_mode" == "always" ]]; then
    use_color=1
elif [[ "$color_mode" == "never" || -n "${NO_COLOR:-}" ]]; then
    use_color=0
elif [[ -t 1 ]]; then
    use_color=1
else
    use_color=0
fi

if (( use_color )); then
    c_rst=$'\033[0m'; c_bold=$'\033[1m'; c_dim=$'\033[2m'
    c_pri=$'\033[36m'; c_ok=$'\033[1;32m'; c_err=$'\033[1;31m'; c_warn=$'\033[1;33m'
else
    c_rst=""; c_bold=""; c_dim=""; c_pri=""; c_ok=""; c_err=""; c_warn=""
fi

now_ms() {
    local sec nano
    IFS=. read -r sec nano <<< "$(date +%s.%N)"
    printf '%d' $(( 10#$sec * 1000 + 10#${nano:0:3} ))
}

format_ms() {
    local ms="$1"
    printf '%d.%02ds' $(( ms / 1000 )) $(( (ms % 1000) / 10 ))
}

passed=0
failed=0
skipped=0
total_checks=0
suite_t0="$(now_ms)"

run_dist_step() {
    local _step_name="$1"
    shift
    if [[ -n "$only_pattern" ]]; then
        local low_n="${_step_name,,}" low_p="${only_pattern,,}"
        [[ "$low_n" == *"$low_p"* ]] || return 0
    fi
    total_checks=$((total_checks + 1))
    if [[ "$list_only" == true ]]; then
        printf '[%02d] %s\n' "$total_checks" "$_step_name"
        return 0
    fi

    local t0 t1 dur_ms dur_str out_file rc=0
    out_file="$(mktemp)"
    t0="$(now_ms)"
    if "$@" >"$out_file" 2>&1; then
        rc=0
    else
        rc=$?
    fi
    t1="$(now_ms)"
    dur_ms=$(( t1 - t0 ))
    (( dur_ms < 0 )) && dur_ms=0
    dur_str="$(format_ms "$dur_ms")"

    if (( rc == 0 )); then
        passed=$((passed + 1))
        printf '[%02d] %-44s %bPASS%b  %b%6s%b\n' "$total_checks" "$_step_name" "$c_ok" "$c_rst" "$c_dim" "$dur_str" "$c_rst"
        rm -f "$out_file"
        return 0
    fi
    if (( rc == 77 )); then
        skipped=$((skipped + 1))
        printf '[%02d] %-44s %bSKIP%b  %b%6s%b\n' "$total_checks" "$_step_name" "$c_warn" "$c_rst" "$c_dim" "$dur_str" "$c_rst"
        rm -f "$out_file"
        return 0
    fi

    failed=$((failed + 1))
    printf '[%02d] %-44s %bFAIL%b  %b%6s%b (exit %d)\n' "$total_checks" "$_step_name" "$c_err" "$c_rst" "$c_dim" "$dur_str" "$c_rst" "$rc" >&2
    cat "$out_file" >&2
    rm -f "$out_file"
    return "$rc"
}

step_shell_syntax() {
    bash -n \
        "$runtime_root/setup" \
        "$runtime_root/scripts/alis" \
        "$runtime_root/scripts/release.sh" \
        "$runtime_root/scripts/verify-docs.sh" \
        "$runtime_root/scripts/wiki-sync.sh" \
        "$runtime_root/scripts/test-tlp-integration-lifecycle.sh" \
        "$runtime_root/scripts/test-tlp-settings-ui-guards.sh" \
        "$runtime_root/scripts/test-update-lifecycle.sh" \
        "$runtime_root/sdata/lib/"*.sh \
        "$runtime_root/sdata/subcmd-install/"*.sh \
        "$runtime_root/sdata/migrations/"*.sh
    for dist_installer in "$runtime_root"/sdata/dist-*/install-deps.sh; do
        [[ -f "$dist_installer" ]] || continue
        bash -n "$dist_installer"
    done
    python3 -m py_compile "$runtime_root/scripts/lib/alis-logs.py"
}

step_updater_source() {
    local versioning_lib="$runtime_root/sdata/lib/versioning.sh"
    local tracking_lib="$runtime_root/sdata/lib/snapshots.sh"
    grep -Fq 'GITHUB_REPO="llocphann/Alis"' "$versioning_lib" || { printf 'FAIL: updater release API does not target llocphann/Alis\n' >&2; return 1; }
    grep -Fq '[[ -z "$branch" || "$branch" == "HEAD" ]] && branch="stable"' "$versioning_lib" || { printf 'FAIL: detached updater fallback does not target the stable branch\n' >&2; return 1; }
    grep -Fq '[[ -z "$branch" || "$branch" == "HEAD" ]] && branch="stable"' "$tracking_lib" || { printf 'FAIL: remote update tracking does not target stable from detached HEAD\n' >&2; return 1; }
}

step_optional_host_lifecycle() {
    python3 "$runtime_root/scripts/test-alis-intergration-optional.py"
    python3 "$runtime_root/scripts/test-alis-intergration-install-lifecycle.py"
}

step_session_tray_ordering() {
    local service_unit="$runtime_root/assets/systemd/alis.service"
    if ! grep -qx 'Type=dbus' "$service_unit" \
            || ! grep -qx 'BusName=org.kde.StatusNotifierWatcher' "$service_unit" \
            || ! grep -qx 'Before=graphical-session.target' "$service_unit" \
            || grep -qx 'After=graphical-session.target' "$service_unit" \
            || grep -qx 'Requisite=graphical-session.target' "$service_unit"; then
        printf 'FAIL: alis.service does not gate XDG autostart on the tray watcher\n' >&2
        return 1
    fi
    if ! grep -Fq 'property var _trayService: TrayService' "$runtime_root/shell.qml"; then
        printf 'FAIL: shell startup does not instantiate the StatusNotifier watcher\n' >&2
        return 1
    fi
}

step_fresh_install_defaults() {
    python3 - "$runtime_root" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
with (root / "defaults/config.json").open(encoding="utf-8") as handle:
    config = json.load(handle)
schema = (root / "modules/common/Config.qml").read_text(encoding="utf-8")
wizard = (root / "welcome.qml").read_text(encoding="utf-8")

checks = {
    "settings rail": config["settingsUi"]["overlayStyle"] == "rail",
    "balanced profile": config["welcomeWizard"]["profile"] == "balanced",
    "Alis Alt+Tab opt-in": config["modules"]["altSwitcher"] is False,
    "dock enabled": config["dock"]["enable"] is True,
    "dock pinned": config["dock"]["pinnedOnStartup"] is True,
    "dock not hover-only": config["dock"]["hoverToReveal"] is False,
    "right sidebar full height": config["sidebar"]["collapseEmptyNotifications"] is False,
    "left sidebar full height": config["sidebar"]["collapseWidgetsTab"] is False,
    "wallhaven tab": config["sidebar"]["wallhaven"]["enable"] is True,
    "news tab": config["sidebar"]["news"]["enable"] is True,
    "controls widget": config["sidebar"]["widgets"]["controls"] is True,
    "status widget": config["sidebar"]["widgets"]["status"] is True,
}
failed = [name for name, passed in checks.items() if not passed]
if failed:
    raise SystemExit("FAIL: fresh-install defaults: " + ", ".join(failed))

schema_checks = {
    "schema settings rail": 'property string overlayStyle: "rail"' in schema,
    "schema Alis Alt+Tab opt-in": "property bool altSwitcher: false" in schema.split(
        "\n            property JsonObject modules: JsonObject {", 1)[1].split(
        "property JsonObject appearance: JsonObject {", 1)[0],
    "schema dock enabled": "property bool enable: true" in schema.split(
        "property JsonObject dock: JsonObject {", 1)[1].split(
        "property JsonObject controlPanel: JsonObject {", 1)[0],
    "schema dock pinned": "property bool pinnedOnStartup: true" in schema,
    "schema dock not hover-only": "property bool hoverToReveal: false" in schema,
    "schema right sidebar full height": "property bool collapseEmptyNotifications: false" in schema,
    "schema left sidebar full height": "property bool collapseWidgetsTab: false" in schema,
    "schema wallhaven tab": re.search(r"property JsonObject wallhaven: JsonObject \{[\s\S]{0,900}?property bool enable:\s*true", schema) is not None,
    "schema news tab": re.search(r"property JsonObject news: JsonObject \{[\s\S]{0,900}?property bool enable:\s*true", schema) is not None,
    "wizard applies initial profile": "root.applyProfile(root.selectedProfile)" in wizard,
    "wizard dock pinned": '"dock.pinnedOnStartup": true' in wizard,
    "wizard dock not hover-only": '"dock.hoverToReveal": false' in wizard,
    "wizard right sidebar full height": '"sidebar.collapseEmptyNotifications": false' in wizard,
    "wizard left sidebar full height": '"sidebar.collapseWidgetsTab": false' in wizard,
    "wizard preserves Waffle configuration": '"waffles.' not in wizard.split(
        "readonly property var profileEssentials", 1)[1].split(
        "// ─── Entry/exit animation state", 1)[0],
}
failed = [name for name, passed in schema_checks.items() if not passed]
if failed:
    raise SystemExit("FAIL: schema/wizard defaults: " + ", ".join(failed))

binds = (root / "defaults/niri/config.d/70-binds.kdl").read_text(encoding="utf-8")
if 'Alt+Tab { next-window; }' not in binds or 'Alt+Shift+Tab { previous-window; }' not in binds:
    raise SystemExit("FAIL: native Niri Alt+Tab bindings are missing")
if any(f'spawn "{launcher}" "altSwitcher"' in binds for launcher in ("alis",)):
    raise SystemExit("FAIL: fresh-install Alt+Tab invokes the shell switcher")
PY
    local arch_installer="$runtime_root/sdata/dist-arch/install-deps.sh"
    if ! grep -Fq 'pacman -T "${depends[@]}"' "$arch_installer" \
            || ! grep -Fq 'pacman -S $installflags "${missing_deps[@]}"' "$arch_installer"; then
        printf 'FAIL: Arch PKGBUILD dependencies are not filtered through the local package database\n' >&2
        return 1
    fi
    if grep -Fq 'pacman -S $installflags "${depends[@]}"' "$arch_installer"; then
        printf 'FAIL: Arch installer can still reinstall or downgrade satisfied PKGBUILD dependencies\n' >&2
        return 1
    fi
}

step_runtime_payload_manifests() {
    while IFS= read -r runtime_file; do
        [[ -n "$runtime_file" ]] || continue
        [[ -f "$runtime_root/$runtime_file" ]]
    done < "$runtime_root/sdata/runtime-root-files.txt"
    while IFS= read -r runtime_dir; do
        [[ -n "$runtime_dir" ]] || continue
        [[ -d "$runtime_root/$runtime_dir" ]]
    done < "$runtime_root/sdata/runtime-payload-dirs.txt"
    local snapshot_lib="$runtime_root/sdata/lib/snapshots.sh"
    if ! grep -Fq 'quickshell/user/desktop-items.json' "$snapshot_lib" \
            || ! grep -Fq 'desktop-items.json' "$snapshot_lib"; then
        printf 'FAIL: managed desktop items are absent from update snapshots\n' >&2
        return 1
    fi
}

step_payload_and_boundary() {
    local payload_tool="$runtime_root/sdata/lib/runtime-payload.py"
    local payload_list
    payload_list="$(mktemp)"
    python3 "$payload_tool" list --root "$runtime_root" > "$payload_list"
    if ! grep -Fq 'runtime-payload.py copy' "$runtime_root/Makefile"; then
        rm -f "$payload_list"
        printf 'FAIL: make install does not use the canonical runtime payload policy\n' >&2
        return 1
    fi

    local agent_names=(AGENTS.md CLAUDE.md CODEX.md PI.md codemap.md .mcp.json opencode.json skills-lock.json)
    local agent_dirs=(.claude .factory .opencode .codex .agents .codebase-memory .impeccable .pi-subagents)
    for name in "${agent_names[@]}"; do
        if grep -Eq "(^|/)${name//./\.}$" "$payload_list"; then
            rm -f "$payload_list"; printf 'FAIL: canonical payload leaks agent artifact: %s\n' "$name" >&2; return 1
        fi
    done
    for name in "${agent_dirs[@]}"; do
        local escaped="${name//./\.}"
        if grep -Eq "(^|/)${escaped}(/|$)" "$payload_list"; then
            rm -f "$payload_list"; printf 'FAIL: canonical payload leaks agent directory: %s\n' "$name" >&2; return 1
        fi
    done
    if grep -Eq '^scripts/test-' "$payload_list"; then
        rm -f "$payload_list"; printf 'FAIL: canonical payload leaks regression test tooling\n' >&2; return 1
    fi
    for forbidden in \
        scripts/release.sh \
        scripts/wiki-sync.sh \
        scripts/verify-docs.sh \
        scripts/qml-check.fish \
        scripts/test-local-distribution.sh \
        scripts/test-battery-charge-limit-helper.sh \
        scripts/test-thinkfan-helper.sh \
        scripts/test-tlp-integration-lifecycle.sh \
        scripts/test-tlp-settings-ui-guards.sh \
        scripts/test-update-lifecycle.sh \
        tools/; do
        if grep -Fq "$forbidden" "$payload_list"; then
            rm -f "$payload_list"; printf 'FAIL: canonical payload leaks development tooling: %s\n' "$forbidden" >&2; return 1
        fi
    done
    for consumer in \
        "$runtime_root/Makefile" \
        "$runtime_root/distro/arch/alis-shell/PKGBUILD" \
        "$runtime_root/distro/arch/alis-shell-git/PKGBUILD" \
        "$runtime_root/nix/package.nix"; do
        [[ -f "$consumer" ]] || continue
        if ! grep -Fq 'runtime-payload.py' "$consumer"; then
            rm -f "$payload_list"; printf 'FAIL: %s bypasses canonical runtime payload policy\n' "${consumer#$runtime_root/}" >&2; return 1
        fi
    done
    rm -f "$payload_list"
}

step_pkgbuild_and_versions() {
    [[ -d "$runtime_root/distro/arch" ]] || return 77
    bash -n \
        "$runtime_root/distro/arch/alis-shell/PKGBUILD" \
        "$runtime_root/distro/arch/alis-shell-git/PKGBUILD" \
        "$runtime_root/distro/arch/alis-meta/PKGBUILD"
    for pkg in alis-shell alis-meta; do
        local pkg_ver
        pkg_ver="$(grep -m1 '^pkgver=' "$runtime_root/distro/arch/$pkg/PKGBUILD" | cut -d= -f2)"
        case "$pkg_ver" in
            r*) ;;
            *) printf 'FAIL: %s pkgver=%s must be a rolling identifier (r*)\n' "$pkg" "$pkg_ver" >&2; return 1 ;;
        esac
    done
}

step_launcher_resolution() {
    ALIS_RUNTIME_DIR="$runtime_root" bash "$launcher" path >/dev/null
    ALIS_RUNTIME_DIR="$runtime_root" bash "$launcher" status --json >/dev/null
}

step_app_launch_env() {
    local shell_exec="$runtime_root/modules/common/functions/ShellExec.qml"
    local alis_launcher="$runtime_root/scripts/alis"
    if ! grep -Fq 'systemctl --user show-environment' "$shell_exec" \
            || ! grep -Fq '_manager_display="$(manager_value DISPLAY)"' "$shell_exec" \
            || ! grep -Fq 'valid_display "$DISPLAY"' "$shell_exec" \
            || ! grep -Fq 'for _x in /tmp/.X11-unix/X*' "$shell_exec"; then
        printf 'FAIL: application launches do not recover the live XWayland DISPLAY environment\n' >&2
        return 1
    fi
    if ! grep -Fq 'vars_to_import+=("DISPLAY=$DISPLAY")' "$alis_launcher" \
            || ! grep -Fq 'for _xsock in /tmp/.X11-unix/X*' "$alis_launcher" \
            || ! grep -Fq 'systemctl --user set-environment "${vars_to_import[@]}"' "$alis_launcher"; then
        printf 'FAIL: session environment does not publish the XWayland DISPLAY to the user manager\n' >&2
        return 1
    fi
}

step_ipc_registry() {
    [[ -f "$runtime_root/scripts/lib/generate-ipc-registry.py" ]] || return 77
    python3 "$runtime_root/scripts/test-ipc-registry-generator.py"
    python3 "$runtime_root/scripts/lib/generate-ipc-registry.py" --check
}

if [[ "$list_only" == false ]]; then
    printf '%bAlis Local Distribution Suite%b %b(fast=%s)%b\n' "$c_pri$c_bold" "$c_rst" "$c_dim" "$fast_mode" "$c_rst"
fi

run_dist_step "shell syntax" step_shell_syntax
run_dist_step "Alis updater source" step_updater_source
if [[ "$fast_mode" == false ]]; then
    run_dist_step "optional host lifecycle" step_optional_host_lifecycle
    run_dist_step "TLP integration lifecycle" bash "$runtime_root/scripts/test-tlp-integration-lifecycle.sh"
    run_dist_step "TLP settings UI guards" bash "$runtime_root/scripts/test-tlp-settings-ui-guards.sh"
    run_dist_step "update lifecycle regression" bash "$runtime_root/scripts/test-update-lifecycle.sh"
    run_dist_step "network lifecycle regression" bash "$runtime_root/scripts/test-network-service-lifecycle.sh"
fi
run_dist_step "session tray ordering" step_session_tray_ordering
run_dist_step "fresh install defaults" step_fresh_install_defaults
run_dist_step "runtime payload manifests" step_runtime_payload_manifests
run_dist_step "canonical runtime payload & boundary" step_payload_and_boundary
if [[ -f "$runtime_root/Makefile" && "$fast_mode" == false ]]; then
    run_dist_step "make install dry run" make -n install PREFIX=/tmp/alis-stage-test -C "$runtime_root"
    run_dist_step "optional package boundary" python3 "$runtime_root/scripts/test-alis-intergration-arch-package.py"
fi
run_dist_step "pkgbuild syntax & version consistency" step_pkgbuild_and_versions
run_dist_step "launcher resolution" step_launcher_resolution
run_dist_step "application launch environment" step_app_launch_env
run_dist_step "IPC registry generator & freshness" step_ipc_registry

if [[ "$run_runtime" == true ]]; then
    run_dist_step "runtime restart" bash -c '
        bash "$1/scripts/alis" kill >/dev/null 2>&1 || true
        sleep 1
        bash "$1/scripts/alis" run >/tmp/alis-test-local-runtime.log 2>&1 &
        sleep 3
    ' _ "$runtime_root"
    run_dist_step "runtime logs" bash "$runtime_root/scripts/alis" logs
    run_dist_step "runtime filtered errors" bash -c '
        bash "$1" logs --full | grep -iE "error|ReferenceError|TypeError|binding loop" | tail -80 || true
    ' _ "$launcher"
    run_dist_step "launcher ipc" bash "$launcher" ipc shellUpdate diagnose
fi

if [[ "$list_only" == true ]]; then
    printf 'Total checks: %d\n' "$total_checks"
    exit 0
fi

suite_t1="$(now_ms)"
total_dur_str="$(format_ms $(( suite_t1 - suite_t0 )) )"
printf '\n%bAlis distribution checks: %d PASS / %d FAIL / %d SKIP (%s)%b\n' \
    "$c_bold" "$passed" "$failed" "$skipped" "$total_dur_str" "$c_rst"
(( failed == 0 ))
