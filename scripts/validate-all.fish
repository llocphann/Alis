#!/usr/bin/env fish

function usage
    printf '%s\n' \
        'Usage: fish scripts/validate-all.fish [options]' \
        '' \
        'Runs Hadalis validation from one Fish entrypoint and writes one persistent log.' \
        '' \
        'Options:' \
        '  -f, --full         Run REQUIRED LOCAL + Nix (if available) + live checks + interactive acceptance.' \
        '      --strict-qml   Require qmlformat >= 6.8 in the canonical REQUIRED LOCAL validator.' \
        '      --with-nix     Run the deferred Nix contract and flake evaluation.' \
        '      --live         Run installed/live shell identity, status, doctor, perf, and journal checks.' \
        '      --interactive  Run the release/live manual acceptance checklist.' \
        '      --log PATH     Write the single final log to PATH instead of /tmp.' \
        '  -h, --help         Show this help.' \
        '' \
        'Recommended:' \
        '  fish scripts/validate-all.fish' \
        '  fish scripts/validate-all.fish --full'
end

argparse 'h/help' 'f/full' 'strict-qml' 'with-nix' 'live' 'interactive' 'log=' -- $argv
or begin
    usage >&2
    exit 2
end

if set -q _flag_help
    usage
    exit 0
end

set -l script_dir (cd (dirname (status --current-filename)); and pwd -P)
set -l repo_root (git -C "$script_dir/.." rev-parse --show-toplevel 2>/dev/null)
if test $status -ne 0 -o -z "$repo_root"
    printf 'FATAL: validate-all.fish must run from a Hadalis Git checkout.\n' >&2
    exit 2
end

cd "$repo_root"; or exit 2

if not set -q TMPDIR
    set -g TMPDIR /tmp
end

set -g VALIDATION_WORKDIR (mktemp -d "$TMPDIR/hadalis-full-validation.XXXXXX")
if test $status -ne 0 -o -z "$VALIDATION_WORKDIR"
    printf 'FATAL: could not create validation workspace.\n' >&2
    exit 2
end

function cleanup_validation --on-event fish_exit
    if test -n "$VALIDATION_WORKDIR" -a -d "$VALIDATION_WORKDIR"
        rm -rf -- "$VALIDATION_WORKDIR"
    end
end

set -l timestamp (date +%Y%m%d-%H%M%S)
set -g VALIDATION_LOG "$TMPDIR/hadalis-full-validation-$timestamp.log"
if set -q _flag_log
    set VALIDATION_LOG $_flag_log[-1]
    if not string match -qr '^/' -- "$VALIDATION_LOG"
        set VALIDATION_LOG "$repo_root/$VALIDATION_LOG"
    end
end
mkdir -p (dirname "$VALIDATION_LOG")
printf '' > "$VALIDATION_LOG"

set -g CHECK_NO 0
set -g PASS_COUNT 0
set -g FAIL_COUNT 0
set -g SKIP_COUNT 0
set -g REQUIRED_FAILURES 0
set -g REQUESTED_FAILURES 0
set -g START_JOURNAL (date '+%Y-%m-%d %H:%M:%S')
set -g START_ISO (date --iso-8601=seconds 2>/dev/null; or date)

function log_only
    printf '%s\n' (string join ' ' -- $argv) >> "$VALIDATION_LOG"
end

function log_line
    set -l text (string join ' ' -- $argv)
    printf '%s\n' "$text"
    printf '%s\n' "$text" >> "$VALIDATION_LOG"
end

function mark_result --argument-names class label result
    switch "$result"
        case PASS
            set -g PASS_COUNT (math "$PASS_COUNT + 1")
        case FAIL
            set -g FAIL_COUNT (math "$FAIL_COUNT + 1")
            if test "$class" = REQUIRED
                set -g REQUIRED_FAILURES (math "$REQUIRED_FAILURES + 1")
            else
                set -g REQUESTED_FAILURES (math "$REQUESTED_FAILURES + 1")
            end
        case SKIP
            set -g SKIP_COUNT (math "$SKIP_COUNT + 1")
    end
    printf '[%02d] %-9s %-58s %s\n' "$CHECK_NO" "$class" "$label" "$result"
    printf '[%02d] %-9s %-58s %s\n' "$CHECK_NO" "$class" "$label" "$result" >> "$VALIDATION_LOG"
end

function run_stage
    set -l class $argv[1]
    set -l label $argv[2]
    set -l cmd $argv[3..-1]
    set -g CHECK_NO (math "$CHECK_NO + 1")
    set -l output_file "$VALIDATION_WORKDIR/check-$CHECK_NO.out"

    log_only ''
    log_only "---- CHECK [$CHECK_NO]: $class / $label ----"
    log_only "Command: "(string join ' ' -- $cmd)
    log_only "Working directory: $PWD"

    $cmd > "$output_file" 2>&1
    set -l rc $status
    if test -s "$output_file"
        cat "$output_file" >> "$VALIDATION_LOG"
    end
    log_only "Exit code: $rc"

    if test $rc -eq 0
        mark_result "$class" "$label" PASS
    else
        mark_result "$class" "$label" FAIL
    end
    return 0
end

function skip_stage --argument-names class label reason
    set -g CHECK_NO (math "$CHECK_NO + 1")
    log_only ''
    log_only "---- CHECK [$CHECK_NO]: $class / $label ----"
    log_only "Skip reason: $reason"
    mark_result "$class" "$label" SKIP
end

function fail_without_command --argument-names class label reason
    set -g CHECK_NO (math "$CHECK_NO + 1")
    log_only ''
    log_only "---- CHECK [$CHECK_NO]: $class / $label ----"
    log_only "Failure reason: $reason"
    mark_result "$class" "$label" FAIL
end

function run_canonical_validator
    set -g CHECK_NO (math "$CHECK_NO + 1")
    set -l label 'canonical clean-clone REQUIRED LOCAL matrix'
    set -l child_log "$VALIDATION_WORKDIR/required-local.log"
    set -l child_stdout "$VALIDATION_WORKDIR/required-local.stdout"
    set -l validator_cmd bash scripts/validate-maintainer-local.sh --current-repo
    if set -q _flag_strict_qml
        set -a validator_cmd --strict-qml
    end

    log_only ''
    log_only "---- CHECK [$CHECK_NO]: REQUIRED / $label ----"
    log_only "Command: HADALIS_VALIDATION_LOG=$child_log "(string join ' ' -- $validator_cmd)
    log_only "Working directory: $PWD"

    env HADALIS_VALIDATION_LOG="$child_log" $validator_cmd > "$child_stdout" 2>&1
    set -l rc $status

    log_only 'BEGIN CANONICAL VALIDATOR STDOUT'
    if test -s "$child_stdout"
        cat "$child_stdout" >> "$VALIDATION_LOG"
    end
    log_only 'END CANONICAL VALIDATOR STDOUT'
    log_only 'BEGIN CANONICAL VALIDATOR LOG'
    if test -s "$child_log"
        cat "$child_log" >> "$VALIDATION_LOG"
    else
        log_only '<canonical validator did not produce a log>'
    end
    log_only 'END CANONICAL VALIDATOR LOG'
    log_only "Exit code: $rc"

    if test $rc -eq 0
        mark_result REQUIRED "$label" PASS
    else
        mark_result REQUIRED "$label" FAIL
    end
end

function scan_runtime_journal
    set -l label 'runtime QML error scan since validation start'
    set -l journal_file "$VALIDATION_WORKDIR/alis-journal.log"
    set -l hits_file "$VALIDATION_WORKDIR/alis-journal-errors.log"

    if not type -q journalctl
        skip_stage OPTIONAL "$label" 'journalctl is unavailable'
        return
    end
    if not type -q systemctl
        skip_stage OPTIONAL "$label" 'systemctl is unavailable'
        return
    end

    systemctl --user status alis.service >/dev/null 2>&1
    set -l service_status $status
    if test $service_status -ne 0
        skip_stage OPTIONAL "$label" 'alis.service is not active under systemd --user; manual qs launches cannot be scoped safely'
        return
    end

    set -g CHECK_NO (math "$CHECK_NO + 1")
    journalctl --user -u alis.service --since "$START_JOURNAL" --no-pager > "$journal_file" 2>&1
    set -l journal_rc $status
    if test $journal_rc -ne 0
        log_only ''
        log_only "---- CHECK [$CHECK_NO]: OPTIONAL / $label ----"
        cat "$journal_file" >> "$VALIDATION_LOG"
        mark_result OPTIONAL "$label" FAIL
        return
    end

    grep -E 'Type [^ ]+ unavailable|is not a type|Cannot assign to non-existent property|ReferenceError: [A-Za-z0-9_]+ is not defined|QQmlApplicationEngine failed|Failed to load component|module .* is not installed' "$journal_file" > "$hits_file" 2>/dev/null
    set -l grep_rc $status

    log_only ''
    log_only "---- CHECK [$CHECK_NO]: OPTIONAL / $label ----"
    log_only "Journal since: $START_JOURNAL"
    if test $grep_rc -eq 0
        log_only 'High-signal QML/runtime errors:'
        cat "$hits_file" >> "$VALIDATION_LOG"
        mark_result OPTIONAL "$label" FAIL
    else
        log_only 'No high-signal QML type/property/reference errors detected.'
        mark_result OPTIONAL "$label" PASS
    end
end

function manual_check --argument-names label
    set -g CHECK_NO (math "$CHECK_NO + 1")
    while true
        read -l -P "[$CHECK_NO] MANUAL — $label [y=pass/n=fail/s=skip]: " answer
        if test $status -ne 0
            log_only ''
            log_only "---- CHECK [$CHECK_NO]: RELEASE / $label ----"
            log_only 'Input closed before a result was supplied.'
            mark_result RELEASE "$label" SKIP
            return
        end
        set answer (string lower -- (string trim -- "$answer"))
        switch "$answer"
            case y yes pass
                log_only ''
                log_only "---- CHECK [$CHECK_NO]: RELEASE / $label ----"
                log_only 'Operator result: PASS'
                mark_result RELEASE "$label" PASS
                return
            case n no fail
                log_only ''
                log_only "---- CHECK [$CHECK_NO]: RELEASE / $label ----"
                log_only 'Operator result: FAIL'
                mark_result RELEASE "$label" FAIL
                return
            case s skip na n/a
                log_only ''
                log_only "---- CHECK [$CHECK_NO]: RELEASE / $label ----"
                log_only 'Operator result: SKIP / not applicable'
                mark_result RELEASE "$label" SKIP
                return
            case '*'
                printf 'Enter y, n, or s.\n'
        end
    end
end

set -l run_nix 0
set -l run_live 0
set -l run_interactive 0
if set -q _flag_full
    set run_nix 1
    set run_live 1
    set run_interactive 1
end
if set -q _flag_with_nix
    set run_nix 1
end
if set -q _flag_live
    set run_live 1
end
if set -q _flag_interactive
    set run_interactive 1
end

set -l exact_sha (git rev-parse HEAD)
set -l branch (git branch --show-current)
set -l status_before "$VALIDATION_WORKDIR/git-status-before.txt"
git status --porcelain=v1 --untracked-files=all > "$status_before"

log_line 'Hadalis full validation (Fish orchestrator)'
log_line "Started: $START_ISO"
log_line "Repository: $repo_root"
log_line "Branch: "(test -n "$branch"; and echo "$branch"; or echo DETACHED)
log_line "Exact SHA: $exact_sha"
log_line "Mode: "(set -q _flag_full; and echo FULL; or echo REQUIRED-LOCAL)
log_line "Strict QML: "(set -q _flag_strict_qml; and echo yes; or echo no)
log_line "Nix requested: "(test $run_nix -eq 1; and echo yes; or echo no)
log_line "Live requested: "(test $run_live -eq 1; and echo yes; or echo no)
log_line "Interactive requested: "(test $run_interactive -eq 1; and echo yes; or echo no)
log_line "Persistent log: $VALIDATION_LOG"
log_only ''
log_only 'Tool versions:'
for tool in git fish bash python3 node make jq qmlformat qmlformat6 nix qs
    if type -q $tool
        set -l tool_version ($tool --version 2>&1 | head -n 1 | string collect)
        log_only "  $tool: $tool_version"
    else
        log_only "  $tool: unavailable"
    end
end

if test -s "$status_before"
    fail_without_command REQUIRED 'working tree contains no uncommitted/untracked changes' 'The canonical validator tests exact HEAD in a clean clone; uncommitted files would not be covered.'
    log_only 'Working tree status at start:'
    cat "$status_before" >> "$VALIDATION_LOG"
else
    set -g CHECK_NO (math "$CHECK_NO + 1")
    log_only ''
    log_only "---- CHECK [$CHECK_NO]: REQUIRED / working tree contains no uncommitted/untracked changes ----"
    log_only 'Working tree is clean.'
    mark_result REQUIRED 'working tree contains no uncommitted/untracked changes' PASS
end

run_canonical_validator

if test $run_nix -eq 1
    if type -q nix
        run_stage OPTIONAL 'Nix module contract' bash scripts/test-nix-module-contract.sh
        run_stage OPTIONAL 'Nix flake evaluation (no build)' nix flake check --no-build --show-trace
    else
        skip_stage OPTIONAL 'Nix validation lane' 'requested, but nix is not installed on this host'
    end
else
    skip_stage OPTIONAL 'Nix validation lane' 'deferred by default; use --with-nix or --full'
end

if test $run_live -eq 1
    set -l has_wayland 0
    if set -q NIRI_SOCKET; or set -q HYPRLAND_INSTANCE_SIGNATURE; or set -q WAYLAND_DISPLAY
        set has_wayland 1
    end

    if test $has_wayland -eq 0
        skip_stage OPTIONAL 'live shell acceptance' 'no Niri/Hyprland/Wayland session variables detected'
    else if not test -x /usr/bin/qs
        skip_stage OPTIONAL 'live shell acceptance' '/usr/bin/qs is unavailable; scripts/alis currently expects that Quickshell path'
    else
        run_stage OPTIONAL 'installed/runtime version identity' bash scripts/alis version --json
        run_stage OPTIONAL 'live shell status' bash scripts/alis status
        run_stage OPTIONAL 'live shell doctor' bash scripts/alis doctor
        run_stage OPTIONAL 'live shell performance doctor' bash scripts/alis doctor --perf
        scan_runtime_journal
    end
else
    skip_stage OPTIONAL 'live shell acceptance' 'use --live or --full while running inside the desktop session'
end

if test $run_interactive -eq 1
    if not tty -s
        skip_stage RELEASE 'interactive desktop acceptance checklist' 'stdin is not a terminal'
    else
        printf '\nInteractive acceptance starts now. Exercise each feature before answering.\n'
        set -l manual_checks \
            'Bar is visible after shell startup/restart and Settings > Bar loads without an error placeholder' \
            'Battery/resources/weather/clock/timer/update/tray popouts open from the bar, stay attached to their anchor, accept input, and retract cleanly' \
            'Media volume HUD and expanded bar media controls open, focus correctly, and close without leaving a dead input region' \
            'Taskbar window previews open from the correct task and retract without hover/focus glitches' \
            'Left sidebar opens/closes repeatedly and its tabs remain usable' \
            'Right sidebar opens/closes repeatedly and its controls remain usable' \
            'Waffle mode still provides working Overview/Search plus both sidebars' \
            'Settings navigation pages load without “This settings page could not be loaded” or blank content' \
            'Dock Panel renders, launches/focuses apps, previews windows, and survives config/settings changes' \
            'Overview/search/launcher can search and launch an application; clipboard/action prefixes behave normally' \
            'Notifications, quick controls, audio/media controls, weather, and system indicators update without visible runtime breakage' \
            'Fullscreen/focus transitions do not strand popups, sidebars, dock, or bar surfaces' \
            'Multi-monitor placement and per-output surfaces behave correctly; hotplug does not duplicate or lose shell surfaces' \
            'Fractional scaling does not expose popup connector seams, offset input masks, or misaligned anchors' \
            'Suspend/resume restores bar, dock, sidebars, services, media/audio, and input ownership' \
            'Battery/TLP/ThinkFan hardware paths behave correctly on applicable hardware, or are explicitly skipped as not applicable' \
            'Arch package build/install/uninstall was exercised in an appropriate packaging VM/chroot, or is explicitly skipped for this dev run'
        for item in $manual_checks
            manual_check "$item"
        end

        if test $run_live -eq 1
            scan_runtime_journal
        end
    end
else
    skip_stage RELEASE 'interactive desktop acceptance checklist' 'use --interactive or --full for release/live acceptance'
end

set -l status_after "$VALIDATION_WORKDIR/git-status-after.txt"
git status --porcelain=v1 --untracked-files=all > "$status_after"
run_stage REQUIRED 'validation wrapper does not mutate the source checkout' cmp -s "$status_before" "$status_after"

log_only ''
log_only 'Release-only items that cannot be truthfully automated on every developer host:'
log_only '  - real multi-monitor/hotplug/fractional-scaling compositor behavior'
log_only '  - suspend/resume behavior'
log_only '  - physical battery/TLP/ThinkFan/audio hardware behavior'
log_only '  - actual Arch package install/uninstall inside the target packaging environment'
log_only '  - GitHub release/Wiki publication credentials and hosted permissions'

set -l final_result PASS
if test $REQUIRED_FAILURES -gt 0 -o $REQUESTED_FAILURES -gt 0
    set final_result FAIL
end

log_line ''
log_line '========================================'
log_line 'HADALIS FULL VALIDATION SUMMARY'
log_line "Exact SHA: $exact_sha"
log_line "Result: $final_result"
log_line "Checks: $CHECK_NO"
log_line "Passed: $PASS_COUNT"
log_line "Failed: $FAIL_COUNT"
log_line "Skipped: $SKIP_COUNT"
log_line "Required failures: $REQUIRED_FAILURES"
log_line "Requested optional/release failures: $REQUESTED_FAILURES"
log_line "FINAL LOG: $VALIDATION_LOG"
log_line '========================================'

if test "$final_result" = FAIL
    exit 1
end
exit 0
