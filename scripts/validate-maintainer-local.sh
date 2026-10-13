#!/usr/bin/env bash
set -uo pipefail
# Validator diagnostics can contain local paths and command output. Keep
# newly created log files private even when the caller's umask is permissive.
umask 077

repo_url="${HADALIS_VALIDATION_REPO_URL:-https://github.com/llocphann/Alis.git}"
branch="${HADALIS_VALIDATION_BRANCH:-dev}"
mode="remote"
strict_qml=0
original_args=("$@")

usage() {
    cat <<'USAGE'
Usage: bash scripts/validate-maintainer-local.sh [--current-repo] [--strict-qml]

Default mode clean-clones the configured dev branch into a temporary directory.
--current-repo  Validate a clean clone of the caller repository's exact HEAD.
--strict-qml    Require qmlformat >= 6.8 instead of allowing the parser pass to skip.
USAGE
}

while (($# > 0)); do
    case "$1" in
        --current-repo) mode="current-repo" ;;
        --strict-qml) strict_qml=1 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'FATAL: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

workspace="$(mktemp -d "${TMPDIR:-/tmp}/alis-validation.XXXXXX")"
checkout="$workspace/Alis"
log_path="${HADALIS_VALIDATION_LOG:-${TMPDIR:-/tmp}/alis-maintainer-validation-$(date +%Y%m%d-%H%M%S).log}"
if [[ "$log_path" != /* ]]; then
    log_path="$PWD/$log_path"
fi
cleanup() { rm -rf -- "$workspace"; }
trap cleanup EXIT
mkdir -p "$(dirname -- "$log_path")"
: >"$log_path"

log_line() { printf '%s\n' "$*" >>"$log_path"; }
terminal_line() { printf '%s\n' "$*"; }
log_command() {
    printf 'Command:' >>"$log_path"
    printf ' %q' "$@" >>"$log_path"
    printf '\n' >>"$log_path"
}
fatal() {
    log_line "FATAL: $1"
    terminal_line "FATAL: $1"
    terminal_line "FINAL LOG: $log_path"
    exit 2
}

log_line 'Alis maintainer local validation'
log_line "Started: $(date -Iseconds)"
log_line "Mode: $mode"
log_line "Repository: $repo_url"
log_line "Branch: $branch"
log_line "Strict QML parser: $([[ $strict_qml -eq 1 ]] && printf yes || printf no)"
printf 'Invocation: bash scripts/validate-maintainer-local.sh' >>"$log_path"
printf ' %q' "${original_args[@]}" >>"$log_path"
printf '\n' >>"$log_path"
log_line "Log: $log_path"
terminal_line 'Alis maintainer local validation'
terminal_line "Log: $log_path"

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
for tool in git bash python3 node fish make qmlformat qmlformat6; do
    if command -v "$tool" >/dev/null 2>&1; then
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

run_check() {
    local label="$1" rc output_file
    shift
    checks=$((checks + 1))
    output_file="$workspace/check-${checks}.out"
    check_marked_skip=0
    log_line ''
    log_line "---- CHECK [$checks]: $label ----"
    log_command "$@"
    log_line "Working directory: $(pwd)"
    "$@" >"$output_file" 2>&1
    rc=$?
    if (( rc == 0 && check_marked_skip == 0 )); then
        passes=$((passes + 1)); log_line 'Result: PASS'
        printf '[%02d] %-58s PASS\n' "$checks" "$label"
        return 0
    fi
    if (( rc == 0 && check_marked_skip == 1 )); then
        log_line 'Result: SKIP'
        [[ -s "$output_file" ]] && { log_line 'Output:'; cat "$output_file" >>"$log_path"; }
        printf '[%02d] %-58s SKIP\n' "$checks" "$label"
        return 0
    fi
    failures=$((failures + 1))
    failed_checks+=("$label (exit $rc)")
    classify_failure "$label"
    log_line "Result: FAIL (exit $rc)"
    log_line "BEGIN FAILURE: $label"
    log_command "$@"
    log_line "Exit code: $rc"
    log_line "Working directory: $(pwd)"
    log_line 'Output:'
    [[ -s "$output_file" ]] && cat "$output_file" >>"$log_path" || log_line '  <no output>'
    log_line "END FAILURE: $label"
    printf '[%02d] %-58s FAIL\n' "$checks" "$label"
    return 0
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
    done < <(git ls-files -z -- '*.sh' '*.install' 'setup' 'scripts/inir' '*/PKGBUILD')
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
    for candidate in qmlformat qmlformat6 /usr/lib/qt6/bin/qmlformat /usr/lib/x86_64-linux-gnu/qt6/bin/qmlformat; do
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
        (( strict_qml == 1 )) && { qml_parser_status="QML parser: FAIL (Qt $qt_version via qmlformat < required 6.8)"; return 1; }
        qml_parser_status="QML parser: SKIPPED (Qt $qt_version via qmlformat is below required 6.8)"; record_skip "QML parser pass (Qt $qt_version too old; need >= 6.8)"; return 0
    fi
    qml_parser_status="QML parser: AVAILABLE (qmlformat on Qt $qt_version; parser pass runs inside qml-check)"
}
run_qml_guards() {
    local output rc
    output="$(HADALIS_QMLFORMAT_ALLOW_UNKNOWN="$qml_parser_allow_unknown" fish scripts/qml-check.fish --all 2>&1)"; rc=$?; printf '%s\n' "$output"
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

run_check 'host tool preflight' require_host_tools
run_check 'build and baseline shell syntax' make build
run_check 'tracked shell/package syntax' tracked_shell_syntax
run_check 'tracked Python syntax' tracked_python_syntax
run_check 'tracked JSON syntax' tracked_json_syntax
run_check 'tracked JavaScript syntax' tracked_js_syntax
run_check 'tracked Fish syntax' tracked_fish_syntax
run_check 'Niri selected-fullscreen workspace regression' node scripts/test-niri-fullscreen-selection.mjs
run_check 'NotificationCenter anchor hover lease regression' node scripts/test-notification-center-hover-lease.mjs
run_check 'Abyss notification popup geometry transition regression' node scripts/test-abyss-notification-transition.mjs
run_check 'Abyss hover scene geometry diagnostic regression' node scripts/test-abyss-hover-geometry-probe.mjs
run_check 'Abyss frame activity diagnostic regression' node scripts/test-abyss-frame-activity-probe.mjs
run_check 'Shared tooltip hover/click lifecycle contract' python3 scripts/test-popup-tooltip-hover-contract.py
run_check 'Native default/custom/styled/Waffle tooltip content lifecycle' python3 scripts/test-tooltip-content-runtime.py
run_check 'Dashboard horizontal gesture and stable page order regression' node scripts/test-dashboard-page-policy.mjs
run_check 'Weekly Planner civil dates, overlap, recurrence and DST regression' node scripts/test-weekly-planner-policy.mjs
run_check 'Weekly Planner Ctrl/Shift multi-date and compatible Repeat cycles' node scripts/test-weekly-planner-multidate.mjs
run_check 'Weekly Planner multi-date single-write storage runtime' python3 scripts/test-weekly-planner-multidate-storage-runtime.py
run_check 'Multi-date Events grouping and Weekly Planner drag/resize policy' node scripts/test-event-occurrences-policy.mjs
run_check 'Weekly Planner moved Event inline Calendar focus' node scripts/test-weekly-planner-event-focus.mjs
run_check 'Events persisted data preservation without automatic migration' node scripts/test-events-no-automatic-migration.mjs
run_check 'Calendar popup three-day civil range and recurrence policy' node scripts/test-calendar-three-day-window.mjs
run_check 'Calendar counterclockwise 3-per-edge Agenda dots' node scripts/test-calendar-event-dot-layout.mjs
run_check 'Calendar popup compact event cards, hover controls and dot spacing' python3 scripts/test-calendar-popup-compact-contract.py
run_check 'Independent Agenda and Todo stores with stable Event ID edits' node scripts/test-agenda-todo-independence.mjs
run_check 'Agenda QML upcoming events and Dashboard startup compatibility' node scripts/test-agenda-upcoming-runtime-compat.mjs
run_check 'Screen Edge lock reservations and output packing' node scripts/test-abyss-module-locks.mjs
run_check 'Screen Edge multi-selection transactions' node scripts/test-abyss-multi-selection.mjs
run_check 'Screen Edge full module designs and capacity' node scripts/test-abyss-full-size-modules.mjs
run_check 'Screen Edge grab anchors and safe corners' node scripts/test-abyss-drag-corners.mjs
run_check 'Screen Edge zero-width inner corner geometry' node scripts/test-abyss-zero-corners.mjs
run_check 'Abyss mandatory structural panels and optional preferences' node scripts/test-abyss-mandatory-panels.mjs
run_check 'Quick Notes Markdown preview, formatting and attachment safety regression' node scripts/test-quick-notes-markdown-policy.mjs
run_check 'Quick Notes rail wheel sensitivity and modifier routing regression' node scripts/test-note-rail-wheel-policy.mjs
run_check 'Abyss unified content opacity migration regression' node scripts/test-abyss-content-opacity-migration.mjs
run_check 'translation catalog structure' python3 translations/tools/l10n.py audit-all
run_check 'translation source parity' python3 translations/tools/source-parity.py
while IFS= read -r -d '' test_file; do
    case "$test_file" in
        # Requires an active, clean dev checkout and publishes a report.
        # Canonical validation runs in a detached clean clone: never dispatch
        # this manual workflow as a regression test.
        scripts/test-wull-manual-perimeter.py)
            record_skip "MANUAL-DEFERRED: $test_file"
            continue ;;
    esac
    run_check "Python regression: $test_file" python3 "$test_file"
done < <(git ls-files -z -- ':(glob)**/test-*.py' 'test-*.py' | sort -z -u)
run_check 'IPC registry freshness' python3 scripts/lib/generate-ipc-registry.py --check
run_check 'documentation contracts' bash scripts/verify-docs.sh
run_check 'QML parser capability' probe_qml_parser
run_check 'QML/startup project guards' run_qml_guards
while IFS= read -r -d '' test_file; do
    case "$test_file" in test-nix-*.sh|*/test-nix-*.sh|*/nix/*) record_skip "NIX-DEFERRED: $test_file"; continue ;; esac
    run_check "shell regression: $test_file" run_shell_regression "$test_file"
done < <(git ls-files -z -- ':(glob)**/test-*.sh' 'test-*.sh' | sort -z -u)
run_check 'Make contract: prefix/path relocation' run_make_contract test-prefix-install
run_check 'Make contract: package metadata' run_make_contract test-package-metadata
run_check 'Make contract: package lifecycle hooks' run_make_contract test-package-hooks
run_check 'source tree remains clean after validation' source_tree_clean

log_line ''
log_line '========================================'
log_line 'HADALIS VALIDATION SUMMARY'
log_line "Exact SHA: $validation_sha"
log_line "Result: $([[ $failures -eq 0 ]] && printf PASS || printf FAIL)"
log_line "Checks run: $checks"
log_line "Passed: $passes"
log_line "Failed: $failures"
log_line "Skipped: ${#skipped_checks[@]}"
log_line "$qml_parser_status"
log_line 'Nix: DEFERRED / NON-BLOCKING (support retained; dedicated validation not run)'
if ((${#failed_checks[@]})); then log_line 'Failed checks:'; printf '  - %s\n' "${failed_checks[@]}" >>"$log_path"; else log_line 'Failed checks: none'; fi
if ((${#failure_groups[@]})); then log_line 'Primary failure groups:'; printf '  - %s\n' "${failure_groups[@]}" >>"$log_path"; else log_line 'Primary failure groups: none'; fi
if ((${#skipped_checks[@]})); then log_line 'Skipped checks:'; printf '  - %s\n' "${skipped_checks[@]}" >>"$log_path"; else log_line 'Skipped checks: none'; fi
log_line 'Environment-dependent / release-only checks not run by daily validation:'
printf '  - %s\n' "${environment_checks[@]}" >>"$log_path"
log_line "FINAL LOG: $log_path"
log_line '========================================'

terminal_line ''
terminal_line "Alis validation: $([[ $failures -eq 0 ]] && printf PASS || printf FAIL)"
terminal_line "SHA: $validation_sha"
terminal_line "Passed: $passes"
terminal_line "Failed: $failures"
terminal_line "Skipped: ${#skipped_checks[@]}"
terminal_line "FINAL LOG: $log_path"
terminal_line 'Send this single log file for review.'
(( failures == 0 ))
