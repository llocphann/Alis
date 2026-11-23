#!/usr/bin/env bash
set -uo pipefail
# Validator diagnostics can contain local paths and command output. Keep
# newly created log files private even when the caller's umask is permissive.
umask 077

repo_url="${ALIS_VALIDATION_REPO_URL:-https://github.com/llocphann/Alis.git}"
branch="${ALIS_VALIDATION_BRANCH:-dev}"
mode="remote"
strict_qml=0
fast_mode=0
list_only=0
fail_fast=0
group_filter="all"
only_pattern=""
json_path=""
color_mode="auto"
original_args=("$@")

usage() {
    cat <<'USAGE'
Usage: bash scripts/validate-maintainer-local.sh [options]

Default mode clean-clones the configured dev branch into a temporary directory.

Options:
  --current-repo         Validate a clean clone of the caller repository's exact HEAD
  --strict-qml           Require qmlformat >= 6.8 instead of allowing the parser pass to skip
  --fast                 Skip slow GUI/Wayland/packaging-stage runtime checks
  --group GROUP          Run only one group: all|syntax|unit|python|shell|qml|docs|make
  --only PATTERN         Run only checks whose label or command matches PATTERN (case-insensitive)
  --list                 List planned checks without executing them
  --fail-fast            Stop immediately on the first failing check
  --json PATH            Write structured JSON validation report to PATH
  --color / --no-color   Force or disable ANSI terminal styling
  -h, --help             Show this help
USAGE
}

while (($# > 0)); do
    case "$1" in
        --current-repo) mode="current-repo" ;;
        --strict-qml) strict_qml=1 ;;
        --fast) fast_mode=1 ;;
        --list) list_only=1 ;;
        --fail-fast) fail_fast=1 ;;
        --group)
            shift
            [[ $# -gt 0 ]] || { printf 'FATAL: --group requires a value\n' >&2; exit 2; }
            group_filter="$1"
            ;;
        --group=*) group_filter="${1#--group=}" ;;
        --only)
            shift
            [[ $# -gt 0 ]] || { printf 'FATAL: --only requires a pattern\n' >&2; exit 2; }
            only_pattern="$1"
            ;;
        --only=*) only_pattern="${1#--only=}" ;;
        --json)
            shift
            [[ $# -gt 0 ]] || { printf 'FATAL: --json requires a path\n' >&2; exit 2; }
            json_path="$1"
            ;;
        --json=*) json_path="${1#--json=}" ;;
        --color) color_mode="always" ;;
        --no-color) color_mode="never" ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'FATAL: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

case "$group_filter" in
    all|syntax|unit|python|shell|qml|docs|make) ;;
    *) printf 'FATAL: invalid --group "%s" (expected all|syntax|unit|python|shell|qml|docs|make)\n' "$group_filter" >&2; exit 2 ;;
esac

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
    c_pri=$'\033[36m'; c_ok=$'\033[1;32m'; c_err=$'\033[1;31m'; c_warn=$'\033[1;33m'; c_hdr=$'\033[1;36m'
else
    c_rst=""; c_bold=""; c_dim=""; c_pri=""; c_ok=""; c_err=""; c_warn=""; c_hdr=""
fi

workspace="$(mktemp -d "${TMPDIR:-/tmp}/alis-validation.XXXXXX")"
checkout="$workspace/Alis"
log_path="${ALIS_VALIDATION_LOG:-${TMPDIR:-/tmp}/alis-maintainer-validation-$(date +%Y%m%d-%H%M%S).log}"
if [[ "$log_path" != /* ]]; then
    log_path="$PWD/$log_path"
fi
if [[ -n "$json_path" && "$json_path" != /* ]]; then
    json_path="$PWD/$json_path"
fi
cleanup() { rm -rf -- "$workspace"; }
trap cleanup EXIT
mkdir -p "$(dirname -- "$log_path")"
: >"$log_path"

# Enforce silent zero-focus execution unless explicitly overridden.
if [[ "${ALIS_KEEP_DISPLAY:-0}" != "1" ]]; then
    unset WAYLAND_DISPLAY DISPLAY
fi
export QT_QPA_PLATFORM=offscreen
export PYTHONDONTWRITEBYTECODE=1

log_line() { printf '%s\n' "$*" >>"$log_path"; }
terminal_line() { printf '%s\n' "$*"; }
log_command() {
    printf 'Command:' >>"$log_path"
    printf ' %q' "$@" >>"$log_path"
    printf '\n' >>"$log_path"
}
fatal() {
    log_line "FATAL: $1"
    terminal_line "${c_err}FATAL:${c_rst} $1"
    terminal_line "FINAL LOG: $log_path"
    exit 2
}

now_ms() {
    local sec nano
    IFS=. read -r sec nano <<< "$(date +%s.%N)"
    printf '%d' $(( 10#$sec * 1000 + 10#${nano:0:3} ))
}

format_ms() {
    local ms="$1"
    printf '%d.%02ds' $(( ms / 1000 )) $(( (ms % 1000) / 10 ))
}

log_line 'Alis maintainer local validation'
log_line "Started: $(date -Iseconds)"
log_line "Mode: $mode"
log_line "Repository: $repo_url"
log_line "Branch: $branch"
log_line "Fast mode: $([[ $fast_mode -eq 1 ]] && printf yes || printf no)"
log_line "Group filter: $group_filter"
[[ -n "$only_pattern" ]] && log_line "Only pattern: $only_pattern"
log_line "Strict QML parser: $([[ $strict_qml -eq 1 ]] && printf yes || printf no)"
printf 'Invocation: bash scripts/validate-maintainer-local.sh' >>"$log_path"
printf ' %q' "${original_args[@]}" >>"$log_path"
printf '\n' >>"$log_path"
log_line "Log: $log_path"

if [[ "$mode" == "current-repo" ]]; then
    source_repo="$(git rev-parse --show-toplevel 2>/dev/null)" || fatal '--current-repo requires a Git working tree'
    source_sha="$(git -C "$source_repo" rev-parse HEAD)" || fatal 'could not resolve caller HEAD'
    git clone --quiet --no-local "$source_repo" "$checkout" >>"$log_path" 2>&1 || fatal 'clean local clone failed'
    git -C "$checkout" checkout --quiet --detach "$source_sha" >>"$log_path" 2>&1 || fatal "failed to detach clean clone at $source_sha"
else
    git clone --quiet --single-branch --branch "$branch" "$repo_url" "$checkout" >>"$log_path" 2>&1 || fatal 'clean clone failed'
fi

cd "$checkout" || fatal 'could not enter clean checkout'
validation_sha="$(git rev-parse HEAD)"
short_sha="${validation_sha:0:9}"

terminal_line "${c_hdr}╭──────────────────────────────────────────────────────────────────────────────╮${c_rst}"
terminal_line "${c_hdr}│${c_rst} ${c_bold}ALIS MAINTAINER VALIDATION${c_rst}  ${c_dim}mode=$mode  sha=$short_sha  fast=$fast_mode  group=$group_filter${c_rst}"
terminal_line "${c_hdr}│${c_rst} ${c_dim}Log: $log_path${c_rst}"
terminal_line "${c_hdr}╰──────────────────────────────────────────────────────────────────────────────╯${c_rst}"

log_line "Exact SHA: $validation_sha"
log_line "Validator commit: $validation_sha"
log_line "Hostname: $(hostname 2>/dev/null || printf unavailable)"
log_line "Kernel: $(uname -srmo 2>/dev/null || uname -a 2>/dev/null || printf unavailable)"
if [[ -r /etc/os-release ]]; then
    log_line "OS: $(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | head -n1 | tr -d '"')"
else
    log_line 'OS: unavailable'
fi
log_line 'Initial git status:'
if [[ -n "$(git status --short --untracked-files=all)" ]]; then
    git status --short --untracked-files=all >>"$log_path"
else
    log_line '  clean'
fi
log_line 'Tool versions:'
for tool in git bash python3 node fish make qmlformat6 /usr/lib/qt6/bin/qmlformat qmlformat; do
    if command -v "$tool" >/dev/null 2>&1; then
        log_line "  $tool: $($tool --version 2>&1 | head -n1)"
    elif [[ -x "$tool" ]]; then
        log_line "  $tool: $($tool --version 2>&1 | head -n1)"
    else
        log_line "  $tool: unavailable"
    fi
done
log_line 'Nix lane: deferred/non-blocking; dedicated Nix validation is intentionally skipped.'

checks=0
passes=0
failures=0
failed_checks=()
skipped_checks=()
failure_groups=()
check_marked_skip=0
qml_parser_status='QML parser: UNKNOWN (probe did not run)'
qml_parser_allow_unknown=0
last_printed_group=""
declare -A executed_py_tests=()
declare -a timing_records=()
json_records_file="$workspace/checks.jsonl"
: >"$json_records_file"

environment_checks=(
    'actual Arch package build/install on a package-build host'
    'live Niri/Quickshell desktop acceptance'
    'multi-monitor/hotplug/suspend-resume/fractional-scaling/focus/fullscreen acceptance'
    'live audio/hardware behavior that requires the real desktop session'
    'GitHub release publication, Wiki remote access, and hosted release permissions'
)

add_failure_group() {
    local group="$1" existing
    for existing in "${failure_groups[@]:-}"; do [[ "$existing" == "$group" ]] && return 0; done
    failure_groups+=("$group")
}
classify_failure() {
    case "$1" in
        *translation*|*documentation*) add_failure_group 'translations / documentation drift' ;;
        *QML*|*qml*|*perimeter*|*Perimeter*) add_failure_group 'QML / module resolution / Connected Perimeter' ;;
        *install*|*relocation*|*package*) add_failure_group 'install / relocation / packaging' ;;
        *lifecycle*|*service*) add_failure_group 'service lifecycle / timeout / recovery' ;;
        *syntax*) add_failure_group 'tracked source syntax' ;;
        *) add_failure_group 'other regression contracts' ;;
    esac
}
record_skip() { skipped_checks+=("$1"); check_marked_skip=1; }

is_heavy_runtime_check() {
    local label="$1" cmd_str="$2"
    [[ "$cmd_str" == *"-runtime.py"* || "$cmd_str" == *"-runtime.sh"* ]] && return 0
    [[ "$cmd_str" == *"test-set-f01-default-apps.py"* || "$cmd_str" == *"test-make-install-lifecycle.sh"* || "$cmd_str" == *"test-prefix-install"* ]] && return 0
    [[ "$label" == Native* || "$label" == "Make contract: prefix/path relocation" ]] && return 0
    if [[ "$cmd_str" =~ scripts/test-[A-Za-z0-9_.-]+\.(py|sh) ]]; then
        local script_file="${BASH_REMATCH[0]}"
        if [[ -f "$script_file" ]] && grep -qE 'native_test_session|private_wayland|run_qs|dbus-run-session|make -s install' "$script_file" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

matches_filters() {
    local group="$1" label="$2" cmd_str="$3"
    if [[ "$group_filter" != "all" && "$group_filter" != "$group" ]]; then
        return 1
    fi
    if [[ -n "$only_pattern" ]]; then
        local low_label="${label,,}" low_cmd="${cmd_str,,}" low_pat="${only_pattern,,}"
        [[ "$low_label" == *"$low_pat"* || "$low_cmd" == *"$low_pat"* ]] || return 1
    fi
    if (( fast_mode == 1 )) && is_heavy_runtime_check "$label" "$cmd_str"; then
        return 1
    fi
    return 0
}

record_json_check() {
    [[ -n "$json_path" ]] || return 0
    local group="$1" label="$2" status="$3" rc="$4" dur_ms="$5"
    python3 - "$json_records_file" "$group" "$label" "$status" "$rc" "$dur_ms" <<'PY'
import json, sys
out_path, group, label, status, rc, dur_ms = sys.argv[1:]
with open(out_path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps({
        "group": group,
        "name": label,
        "status": status,
        "exit_code": int(rc),
        "duration_ms": int(dur_ms),
    }) + "\n")
PY
}

run_check_group() {
    local group="$1" label="$2"
    shift 2
    local cmd_str="$*"

    # Track explicit python scripts even if skipped by --fast so trailing
    # discovery never re-runs explicit entries.
    local arg
    for arg in "$@"; do
        if [[ "$arg" == scripts/test-*.py || "$arg" == */test-*.py ]]; then
            executed_py_tests["$arg"]=1
        fi
    done

    matches_filters "$group" "$label" "$cmd_str" || return 0

    if (( list_only == 1 )); then
        checks=$((checks + 1))
        printf '[%03d] %-8s %s  (%s)\n' "$checks" "$group" "$label" "$cmd_str"
        return 0
    fi

    if [[ "$group" != "$last_printed_group" ]]; then
        last_printed_group="$group"
        printf '\n%b── %s ────────────────────────────────────────────────────────────%b\n' "$c_pri" "${group^^}" "$c_rst"
    fi

    local rc output_file t0 t1 dur_ms dur_str
    checks=$((checks + 1))
    output_file="$workspace/check-${checks}.out"
    check_marked_skip=0
    log_line ''
    log_line "---- CHECK [$checks] ($group): $label ----"
    log_command "$@"
    log_line "Working directory: $(pwd)"
    t0="$(now_ms)"
    "$@" >"$output_file" 2>&1
    rc=$?
    t1="$(now_ms)"
    dur_ms=$(( t1 - t0 ))
    (( dur_ms < 0 )) && dur_ms=0
    dur_str="$(format_ms "$dur_ms")"
    timing_records+=("$(printf '%09d\t%s\t%s' "$dur_ms" "$group" "$label")")

    local disp_label="$label"
    if (( ${#disp_label} > 56 )); then
        disp_label="${disp_label:0:53}..."
    fi
    local dur_col="$c_dim"
    (( dur_ms >= 5000 )) && dur_col="$c_warn"

    if (( rc == 0 && check_marked_skip == 0 )); then
        passes=$((passes + 1))
        log_line "Result: PASS ($dur_str)"
        record_json_check "$group" "$label" "PASS" "$rc" "$dur_ms"
        printf '[%03d] %-56s %bPASS%b  %b%6s%b\n' "$checks" "$disp_label" "$c_ok" "$c_rst" "$dur_col" "$dur_str" "$c_rst"
        return 0
    fi
    if (( (rc == 0 && check_marked_skip == 1) || rc == 77 )); then
        (( rc == 77 )) && record_skip "$label"
        log_line "Result: SKIP ($dur_str)"
        [[ -s "$output_file" ]] && { log_line 'Output:'; cat "$output_file" >>"$log_path"; }
        record_json_check "$group" "$label" "SKIP" "$rc" "$dur_ms"
        printf '[%03d] %-56s %bSKIP%b  %b%6s%b\n' "$checks" "$disp_label" "$c_warn" "$c_rst" "$dur_col" "$dur_str" "$c_rst"
        return 0
    fi

    failures=$((failures + 1))
    failed_checks+=("$label (exit $rc)")
    classify_failure "$label"
    log_line "Result: FAIL (exit $rc, $dur_str)"
    log_line "BEGIN FAILURE: $label"
    log_command "$@"
    log_line "Exit code: $rc"
    log_line "Working directory: $(pwd)"
    log_line 'Output:'
    [[ -s "$output_file" ]] && cat "$output_file" >>"$log_path" || log_line '  <no output>'
    log_line "END FAILURE: $label"
    record_json_check "$group" "$label" "FAIL" "$rc" "$dur_ms"
    printf '[%03d] %-56s %bFAIL%b  %b%6s%b (exit %d)\n' "$checks" "$disp_label" "$c_err" "$c_rst" "$dur_col" "$dur_str" "$c_rst" "$rc"
    if [[ -s "$output_file" ]]; then
        grep -v '^[[:space:]]*$' "$output_file" | tail -n 6 | sed "s/^/      ${c_dim}│${c_rst} /"
    fi
    if (( fail_fast == 1 )); then
        return 99
    fi
    return 0
}

run_check() {
    run_check_group "unit" "$@"
}

require_host_tools() {
    local tool missing=0
    for tool in git bash sh python3 make grep sed awk find sort fish node jq rsync cmp sha256sum realpath head cut tr; do
        command -v "$tool" >/dev/null 2>&1 || { printf 'missing required host tool: %s\n' "$tool" >&2; missing=1; }
    done
    return "$missing"
}

shell_interpreter_for() {
    local first_line
    first_line="$(head -n1 "$1" 2>/dev/null || true)"
    if [[ "$first_line" =~ (^|/)(sh)([[:space:]]|$) ]] && [[ "$first_line" != *bash* ]]; then printf sh; else printf bash; fi
}

check_shell_syntax_file() {
    local file="$1" interpreter marker tmp
    interpreter="$(shell_interpreter_for "$file")"
    marker="$(grep -n -m1 '^### DATA ###$' "$file" | cut -d: -f1 || true)"
    if [[ -z "$marker" ]]; then
        "$interpreter" -n "$file"
        return
    fi
    if ! head -n "$((marker - 1))" "$file" | grep -Eq '^[[:space:]]*exit([[:space:]]|$)'; then
        printf '%s: embedded data marker is not guarded by an exit in executable prefix\n' "$file" >&2
        return 1
    fi
    tmp="$(mktemp "$workspace/shell-prefix.XXXXXX")"
    head -n "$((marker - 1))" "$file" >"$tmp"
    "$interpreter" -n "$tmp"
}

tracked_shell_syntax() {
    local file failed=0 mixed=0
    while IFS= read -r -d '' file; do
        [[ -f "$file" ]] || continue
        grep -q '^### DATA ###$' "$file" && mixed=$((mixed + 1))
        check_shell_syntax_file "$file" || failed=1
    done < <(git ls-files -z -- '*.sh' '*.install' 'setup' 'scripts/alis' '*/PKGBUILD')
    printf 'Embedded-data shell files checked by executable prefix: %d\n' "$mixed"
    return "$failed"
}

tracked_python_syntax() {
    python3 - <<'PY'
from pathlib import Path
import subprocess
raw = subprocess.check_output(["git", "ls-files", "-z", "--", "*.py"])
for name in raw.decode().split("\0"):
    if name: compile(Path(name).read_text(encoding="utf-8"), name, "exec")
PY
}
tracked_json_syntax() {
    python3 - <<'PY'
from pathlib import Path
import json, subprocess
raw = subprocess.check_output(["git", "ls-files", "-z", "--", "*.json"])
for name in raw.decode().split("\0"):
    if name: json.loads(Path(name).read_text(encoding="utf-8"))
PY
}
tracked_js_syntax() {
    local file failed=0 node_count=0 qml_js_count=0
    while IFS= read -r -d '' file; do
        if grep -Eq '^[[:space:]]*\.(pragma|import)([[:space:]]|$)' "$file"; then
            qml_js_count=$((qml_js_count + 1)); continue
        fi
        node_count=$((node_count + 1)); node --check "$file" || failed=1
    done < <(git ls-files -z -- '*.js')
    printf 'Node/plain JavaScript checked: %d; QML JavaScript delegated to QML guards: %d\n' "$node_count" "$qml_js_count"
    return "$failed"
}
tracked_fish_syntax() {
    local file failed=0
    while IFS= read -r -d '' file; do fish -n "$file" || failed=1; done < <(git ls-files -z -- '*.fish')
    return "$failed"
}
run_shell_regression() {
    local file="$1" interpreter
    interpreter="$(shell_interpreter_for "$file")"
    "$interpreter" "$file"
}

probe_qml_parser() {
    local parser='' candidate qt_version major minor
    for candidate in qmlformat6 /usr/lib/qt6/bin/qmlformat /usr/lib/x86_64-linux-gnu/qt6/bin/qmlformat qmlformat; do
        if [[ "$candidate" == /* ]]; then [[ -x "$candidate" ]] && { parser="$candidate"; break; }
        elif command -v "$candidate" >/dev/null 2>&1; then parser="$(command -v "$candidate")"; break
        fi
    done
    if [[ -z "$parser" ]]; then
        (( strict_qml == 1 )) && { qml_parser_status='QML parser: FAIL (qmlformat unavailable; strict mode requires Qt >= 6.8)'; return 1; }
        qml_parser_status='QML parser: SKIPPED (qmlformat unavailable)'; record_skip 'QML parser pass (qmlformat unavailable)'; return 0
    fi
    qt_version="$(bash scripts/lib/qml-parser-qt-version.sh "$parser" 2>/dev/null || true)"
    if [[ -z "$qt_version" ]]; then
        if (( strict_qml == 1 )); then
            qml_parser_allow_unknown=1
            qml_parser_status="QML parser: AVAILABLE ($parser; Qt version unknown, strict direct project parse required)"
            return 0
        fi
        qml_parser_status="QML parser: SKIPPED ($parser; Qt version unknown)"; record_skip "QML parser pass ($parser Qt version could not be determined)"; return 0
    fi
    IFS=. read -r major minor _ <<<"$qt_version"
    if (( major * 100 + minor < 608 )); then
        (( strict_qml == 1 )) && { qml_parser_status="QML parser: FAIL (Qt $qt_version via $parser < required 6.8)"; return 1; }
        qml_parser_status="QML parser: SKIPPED (Qt $qt_version via $parser is below required 6.8)"; record_skip "QML parser pass (Qt $qt_version too old; need >= 6.8)"; return 0
    fi
    qml_parser_status="QML parser: AVAILABLE ($parser on Qt $qt_version; parser pass runs inside qml-check)"
}
run_qml_guards() {
    local output rc
    output="$(ALIS_QMLFORMAT_ALLOW_UNKNOWN="$qml_parser_allow_unknown" fish scripts/qml-check.fish --all 2>&1)"; rc=$?; printf '%s\n' "$output"
    if [[ "$qml_parser_status" == 'QML parser: AVAILABLE '* ]]; then
        if grep -Fq 'QML parser rejected the file' <<<"$output"; then qml_parser_status="${qml_parser_status/AVAILABLE/FAIL}"; else qml_parser_status="${qml_parser_status/AVAILABLE/PASS}"; fi
    fi
    return "$rc"
}
run_make_contract() {
    bash -o errexit -o nounset -o pipefail -c 'make "$1" SHELL=/bin/bash .SHELLFLAGS="-eu -o pipefail -c"' _ "$1"
}
source_tree_clean() {
    git diff --exit-code -- . || return 1
    [[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || { printf 'validation mutated the clean clone:\n' >&2; git status --short --untracked-files=all >&2; return 1; }
}

run_suite() {
    local suite_start_ms
    suite_start_ms="$(now_ms)"

    run_check_group syntax 'host tool preflight' require_host_tools || return $?
    run_check_group syntax 'build and baseline shell syntax' make build || return $?
    run_check_group syntax 'tracked shell/package syntax' tracked_shell_syntax || return $?
    run_check_group syntax 'tracked Python syntax' tracked_python_syntax || return $?
    run_check_group syntax 'tracked JSON syntax' tracked_json_syntax || return $?
    run_check_group syntax 'tracked JavaScript syntax' tracked_js_syntax || return $?
    run_check_group syntax 'tracked Fish syntax' tracked_fish_syntax || return $?

    run_check_group unit 'Monitor arrangement fit, zoom and drag-coordinate regression' node scripts/test-monitor-arrangement-viewport.mjs || return $?
    run_check_group unit 'Retired IME integration source guard' python3 scripts/test-input-method-decoupling.py || return $?
    run_check_group unit 'Niri selected-fullscreen workspace regression' node scripts/test-niri-fullscreen-selection.mjs || return $?
    run_check_group unit 'NotificationCenter anchor hover lease regression' node scripts/test-notification-center-hover-lease.mjs || return $?
    run_check_group unit 'Abyss notification popup geometry transition regression' node scripts/test-abyss-notification-transition.mjs || return $?
    run_check_group unit 'Abyss Notification closing content snapshot regression' node scripts/test-abyss-notification-closing-snapshot.mjs || return $?
    run_check_group unit 'Notification closing frame/model fast path regression' node scripts/test-notification-close-fastpath.mjs || return $?
    run_check_group unit 'Recording/Notification stable allocator priority' node scripts/test-abyss-recording-notification-placement.mjs || return $?
    run_check_group unit 'Recording-fixed Notification Pyramid visual origin' node scripts/test-abyss-recording-pyramid-anchor.mjs || return $?
    run_check_group unit 'Sidebar/Edgebar vacancy follows open order' python3 scripts/test-abyss-vacancy-open-order.py || return $?
    run_check_group unit 'Native Sidebar/Edgebar content expansion and close' python3 scripts/test-abyss-vacancy-open-order-runtime.py || return $?
    run_check_group unit 'Default apps including Local Music selection and desktop URI launch' python3 scripts/test-set-f01-default-apps.py || return $?
    run_check_group unit 'Local Music real Process queue and external paths' python3 scripts/test-local-music-mutation-runtime.py || return $?
    run_check_group unit 'Local Music actual CLI typed IPC JSON transport' python3 scripts/test-local-music-ipc-runtime.py || return $?
    run_check_group unit 'Abyss disabled Waves mass-update regression' node scripts/test-abyss-wave-idle-policy.mjs || return $?
    run_check_group unit 'Abyss hover scene geometry diagnostic regression' node scripts/test-abyss-hover-geometry-probe.mjs || return $?
    run_check_group unit 'Abyss frame activity diagnostic regression' node scripts/test-abyss-frame-activity-probe.mjs || return $?
    run_check_group unit 'Shared tooltip hover/click lifecycle contract' python3 scripts/test-popup-tooltip-hover-contract.py || return $?
    run_check_group unit 'Native default/custom/styled/Waffle tooltip content lifecycle' python3 scripts/test-tooltip-content-runtime.py || return $?
    run_check_group unit 'Native static Panel reveal without content resizing' python3 scripts/test-abyss-panel-content-size-runtime.py || return $?
    run_check_group unit 'Native dynamic Toast/OSD/Utility and reparented form reveal' python3 scripts/test-abyss-dynamic-content-size-runtime.py || return $?
    run_check_group unit 'Native shared-field optimized/unoptimized exact GPU parity' python3 scripts/test-abyss-field-support-runtime.py || return $?
    run_check_group unit 'Native shared-field transparent-interior exact GPU parity' python3 scripts/test-abyss-transparent-interior-runtime.py || return $?
    run_check_group unit 'Native shared-field fractional light transparent-interior exact GPU parity' python3 scripts/test-abyss-transparent-interior-runtime.py --light --scale 1.5 || return $?
    run_check_group unit 'Native shared-field fractional light/mask exact GPU parity' python3 scripts/test-abyss-field-support-runtime.py --light --scale 1.5 || return $?
    run_check_group unit 'Native generic Popup delayed-loader reveal and cancellation' python3 scripts/test-abyss-generic-reveal-readiness-runtime.py || return $?
    run_check_group unit 'Native Dashboard/Overview content-ready reveal, reversal and warm expiry' python3 scripts/test-abyss-body-reveal-readiness-runtime.py || return $?
    run_check_group unit 'Dashboard horizontal gesture and stable page order regression' node scripts/test-dashboard-page-policy.mjs || return $?
    run_check_group unit 'Weekly Planner event drag and both resize handles (regression guard)' python3 scripts/test-weekly-planner-pointer-contract.py || return $?
    run_check_group unit 'Native Weekly Planner pointer move, top/bottom resize and isolated calendar fixture' python3 scripts/test-weekly-planner-runtime.py || return $?
    run_check_group unit 'Weekly Planner selected/batch gestures and stored event safeguards' python3 scripts/test-weekly-planner-multi-selection-contract.py || return $?
    run_check_group unit 'Legacy Weekly Planner saved recurring event compatibility and instance safety' node scripts/test-weekly-planner-legacy-recurrence.mjs || return $?
    run_check_group unit 'Weekly Planner legacy multi-date gestures, isolated preview identity and persistence parity' node scripts/test-weekly-planner-multidate-gestures.mjs || return $?
    run_check_group unit 'Weekly Planner deterministic theme-gradient Event palette and unaffected gestures' node scripts/test-weekly-planner-event-palette.mjs || return $?
    run_check_group unit 'Weekly Planner stable high-resolution identity colors preserve saved Event data' node scripts/test-weekly-planner-visual-identity.mjs || return $?
    run_check_group unit 'Native Weekly Planner multi-date gestures, isolated preview and real storage restart' python3 scripts/test-weekly-planner-multidate-gestures-runtime.py || return $?
    run_check_group unit 'Edited legacy Weekly Planner rollover, denied save/retry and restart parity' python3 scripts/test-weekly-planner-edited-rollover-runtime.py || return $?
    run_check_group unit 'Weekly Planner civil dates, overlap, recurrence and DST regression' node scripts/test-weekly-planner-policy.mjs || return $?
    run_check_group unit 'Weekly Planner notified schedule rollover and retained history' node scripts/test-weekly-planner-recurring-rollover.mjs || return $?
    run_check_group unit 'Weekly Planner Ctrl/Shift multi-date and compatible Repeat cycles' node scripts/test-weekly-planner-multidate.mjs || return $?
    run_check_group unit 'Weekly Planner multi-date single-write storage runtime' python3 scripts/test-weekly-planner-multidate-storage-runtime.py || return $?
    run_check_group unit 'Multi-date Events grouping and Weekly Planner drag/resize policy' node scripts/test-event-occurrences-policy.mjs || return $?
    run_check_group unit 'Weekly Planner moved Event inline Calendar focus' node scripts/test-weekly-planner-event-focus.mjs || return $?
    run_check_group unit 'Weekly Planner editor cycle selection excludes saved recurrence history' node scripts/test-weekly-planner-editor-cycle.mjs || return $?
    run_check_group unit 'Weekly Planner recurring instance selection and atomic mixed groups' node scripts/test-weekly-planner-recurring-selection.mjs || return $?
    run_check_group unit 'Weekly Planner future-only branch clocks, legacy history and recurrence cutovers' node scripts/test-weekly-planner-future-schedule.mjs || return $?
    run_check_group unit 'Native Weekly Planner editor cycle highlights, draft and stored restart' python3 scripts/test-weekly-planner-editor-cycle-runtime.py || return $?
    run_check_group unit 'Native Weekly Planner editor-grid selection, clean cards and distinct colors' python3 scripts/test-weekly-planner-editor-visuals-runtime.py || return $?
    run_check_group unit 'Events persisted data preservation without automatic migration' node scripts/test-events-no-automatic-migration.mjs || return $?
    run_check_group unit 'Calendar popup three-day civil range and recurrence policy' node scripts/test-calendar-three-day-window.mjs || return $?
    run_check_group unit 'Calendar counterclockwise 3-per-edge Agenda dots' node scripts/test-calendar-event-dot-layout.mjs || return $?
    run_check_group unit 'Calendar popup compact event cards, hover controls and dot spacing' python3 scripts/test-calendar-popup-compact-contract.py || return $?
    run_check_group unit 'Independent Agenda and Todo stores with stable Event ID edits' node scripts/test-agenda-todo-independence.mjs || return $?
    run_check_group unit 'Agenda QML upcoming events and Dashboard startup compatibility' node scripts/test-agenda-upcoming-runtime-compat.mjs || return $?
    run_check_group unit 'Screen Edge lock reservations and output packing' node scripts/test-abyss-module-locks.mjs || return $?
    run_check_group unit 'Screen Edge multi-selection transactions' node scripts/test-abyss-multi-selection.mjs || return $?
    run_check_group unit 'Screen Edge full module designs and capacity' node scripts/test-abyss-full-size-modules.mjs || return $?
    run_check_group unit 'Screen Edge grab anchors and safe corners' node scripts/test-abyss-drag-corners.mjs || return $?
    run_check_group unit 'Screen Edge zero-width inner corner geometry' node scripts/test-abyss-zero-corners.mjs || return $?
    run_check_group unit 'Abyss mandatory structural panels and optional preferences' node scripts/test-abyss-mandatory-panels.mjs || return $?
    run_check_group unit 'Quick Notes Markdown preview, formatting and attachment safety regression' node scripts/test-quick-notes-markdown-policy.mjs || return $?
    run_check_group unit 'Quick Notes rail wheel sensitivity and modifier routing regression' node scripts/test-note-rail-wheel-policy.mjs || return $?
    run_check_group unit 'Abyss unified content opacity migration regression' node scripts/test-abyss-content-opacity-migration.mjs || return $?

    run_check_group docs 'translation catalog structure' python3 translations/tools/l10n.py audit-all || return $?
    run_check_group docs 'translation source parity' python3 translations/tools/source-parity.py || return $?
    run_check_group docs 'IPC registry freshness' python3 scripts/lib/generate-ipc-registry.py --check || return $?
    run_check_group docs 'documentation contracts' bash scripts/verify-docs.sh || return $?

    while IFS= read -r -d '' test_file; do
        # Never re-run tests already dispatched explicitly above.
        [[ -n "${executed_py_tests[$test_file]+_}" ]] && continue
        case "$test_file" in
            scripts/test-aqua-manual-perimeter.py)
                matches_filters python "Python regression: $test_file" "$test_file" || continue
                record_skip "MANUAL-DEFERRED: $test_file"
                continue ;;
        esac
        run_check_group python "Python regression: $test_file" python3 "$test_file" || return $?
    done < <(git ls-files -z -- ':(glob)**/test-*.py' 'test-*.py' | sort -z -u)

    run_check_group qml 'QML parser capability' probe_qml_parser || return $?
    run_check_group qml 'QML/startup project guards' run_qml_guards || return $?

    while IFS= read -r -d '' test_file; do
        case "$test_file" in
            test-nix-*.sh|*/test-nix-*.sh|*/nix/*)
                matches_filters shell "shell regression: $test_file" "$test_file" || continue
                record_skip "NIX-DEFERRED: $test_file"
                continue ;;
        esac
        run_check_group shell "shell regression: $test_file" run_shell_regression "$test_file" || return $?
    done < <(git ls-files -z -- ':(glob)**/test-*.sh' 'test-*.sh' | sort -z -u)

    run_check_group make 'Make contract: prefix/path relocation' run_make_contract test-prefix-install || return $?
    run_check_group make 'Make contract: package metadata' run_make_contract test-package-metadata || return $?
    run_check_group make 'Make contract: package lifecycle hooks' run_make_contract test-package-hooks || return $?
    run_check_group syntax 'source tree remains clean after validation' source_tree_clean || return $?
    return 0
}

suite_t0="$(now_ms)"
run_suite || true
suite_t1="$(now_ms)"
total_dur_str="$(format_ms $(( suite_t1 - suite_t0 )) )"

if (( list_only == 1 )); then
    printf 'Total planned checks: %d\n' "$checks"
    exit 0
fi

log_line ''
log_line '========================================'
log_line 'ALIS VALIDATION SUMMARY'
log_line "Exact SHA: $validation_sha"
log_line "Result: $([[ $failures -eq 0 ]] && printf PASS || printf FAIL)"
log_line "Checks run: $checks"
log_line "Passed: $passes"
log_line "Failed: $failures"
log_line "Skipped: ${#skipped_checks[@]}"
log_line "Elapsed: $total_dur_str"
log_line "$qml_parser_status"
log_line 'Nix: DEFERRED / NON-BLOCKING (support retained; dedicated validation not run)'
if ((${#failed_checks[@]})); then log_line 'Failed checks:'; printf '  - %s\n' "${failed_checks[@]}" >>"$log_path"; else log_line 'Failed checks: none'; fi
if ((${#failure_groups[@]})); then log_line 'Primary failure groups:'; printf '  - %s\n' "${failure_groups[@]}" >>"$log_path"; else log_line 'Primary failure groups: none'; fi
if ((${#skipped_checks[@]})); then log_line 'Skipped checks:'; printf '  - %s\n' "${skipped_checks[@]}" >>"$log_path"; else log_line 'Skipped checks: none'; fi
log_line 'Environment-dependent / release-only checks not run by daily validation:'
printf '  - %s\n' "${environment_checks[@]}" >>"$log_path"
log_line "FINAL LOG: $log_path"
log_line '========================================'

if [[ -n "$json_path" ]]; then
    mkdir -p "$(dirname -- "$json_path")"
    python3 - "$json_path" "$json_records_file" "$validation_sha" "$passes" "$failures" "${#skipped_checks[@]}" "$(( suite_t1 - suite_t0 ))" "$qml_parser_status" <<'PY'
import json, sys
out_file, jsonl_file, sha, p, f, s, dur, qml = sys.argv[1:]
rows = [json.loads(line) for line in open(jsonl_file, encoding="utf-8") if line.strip()]
payload = {
    "sha": sha,
    "result": "PASS" if int(f) == 0 else "FAIL",
    "duration_ms": int(dur),
    "counts": {"passed": int(p), "failed": int(f), "skipped": int(s), "total": len(rows)},
    "qml_parser": qml,
    "checks": rows,
}
with open(out_file, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2)
PY
fi

res_badge="${c_ok}PASS${c_rst}"
(( failures > 0 )) && res_badge="${c_err}FAIL${c_rst}"
printf '\n%b╭──────────────────────────────────────────────────────────────────────────────╮%b\n' "$c_hdr" "$c_rst"
printf '%b│%b %bAlis Validation:%b %b  %bSHA=%s  Elapsed=%s%b\n' "$c_hdr" "$c_rst" "$c_bold" "$c_rst" "$res_badge" "$c_dim" "$short_sha" "$total_dur_str" "$c_rst"
printf '%b│%b %b%d PASS%b  /  %b%d FAIL%b  /  %b%d SKIP%b   (%d checks)\n' "$c_hdr" "$c_rst" "$c_ok" "$passes" "$c_rst" "$([[ $failures -gt 0 ]] && printf '%s' "$c_err" || printf '%s' "$c_dim")" "$failures" "$c_rst" "$c_warn" "${#skipped_checks[@]}" "$c_rst" "$checks"
printf '%b│%b %s\n' "$c_hdr" "$c_rst" "$qml_parser_status"
if (( ${#timing_records[@]} > 0 )); then
    printf '%b│%b %bSlowest checks:%b\n' "$c_hdr" "$c_rst" "$c_dim" "$c_rst"
    while IFS=$'\t' read -r ms_pad grp lbl; do
        printf '%b│%b   %6s  %-8s %s\n' "$c_hdr" "$c_rst" "$(format_ms "$((10#$ms_pad))")" "$grp" "$lbl"
    done < <(printf '%s\n' "${timing_records[@]}" | LC_ALL=C sort -r | head -n 5)
fi
if (( ${#failed_checks[@]} > 0 )); then
    printf '%b│%b %bFailed:%b\n' "$c_hdr" "$c_rst" "$c_err" "$c_rst"
    for item in "${failed_checks[@]}"; do
        printf '%b│%b   ✖ %s\n' "$c_hdr" "$c_rst" "$item"
    done
fi
printf '%b│%b FINAL LOG: %s\n' "$c_hdr" "$c_rst" "$log_path"
[[ -n "$json_path" ]] && printf '%b│%b JSON REPORT: %s\n' "$c_hdr" "$c_rst" "$json_path"
printf '%b╰──────────────────────────────────────────────────────────────────────────────╯%b\n' "$c_hdr" "$c_rst"
(( failures == 0 ))
