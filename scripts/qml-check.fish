#!/usr/bin/env fish
# QML validation for Alis. Syntax/startup-critical failures are fatal;
# style heuristics remain warnings so existing code is not blocked.

set -l project_root (realpath (dirname (status filename))/..)
set -l scan_root $project_root
set -l scan_all 0
set -l positional

set -l i 1
while test $i -le (count $argv)
    switch $argv[$i]
        case --all
            set scan_all 1
        case --root
            set i (math $i + 1)
            if test $i -gt (count $argv)
                echo "qml-check: --root requires a path" >&2
                exit 2
            end
            set scan_root (realpath $argv[$i])
        case '*'
            set -a positional $argv[$i]
    end
    set i (math $i + 1)
end

if not test -d $scan_root
    echo "qml-check: root not found: $scan_root" >&2
    exit 2
end

set -l parser ""
for candidate in qmlformat6 /usr/lib/qt6/bin/qmlformat /usr/lib/x86_64-linux-gnu/qt6/bin/qmlformat qmlformat
    if string match -q '/*' $candidate
        if test -x $candidate
            set parser $candidate
            break
        end
    else if type -q $candidate
        set parser $candidate
        break
    end
end

# Ubuntu 24.04 ships Qt 6.4, which rejects valid modern syntax used by
# current Alis/Quickshell QML. qmlformat may report its own tool version
# (for example "qmlformat 1.0"), so resolve the Qt runtime version separately.
# Treat Qt < 6.8 as unavailable instead of producing false startup failures.
set -l parser_skip_reason ""
set -l parser_unknown_direct 0
if test -n "$parser"
    set -l parser_qt_version (bash "$project_root/scripts/lib/qml-parser-qt-version.sh" "$parser" 2>/dev/null | head -1)
    if test -z "$parser_qt_version"
        if test "$ALIS_QMLFORMAT_ALLOW_UNKNOWN" = "1"
            set parser_unknown_direct 1
        else
            set parser_skip_reason "qmlformat Qt version could not be determined"
            set parser ""
        end
    else
        set -l parts (string split . $parser_qt_version)
        set -l version_key (math "$parts[1] * 100 + $parts[2]")
        if test $version_key -lt 608
            set parser_skip_reason "Qt $parser_qt_version is too old for project syntax"
            set parser ""
        end
    end
end

set -l qml_files
if test (count $positional) -gt 0
    for file in $positional
        if test -f $file
            set -a qml_files (realpath $file)
        else if test -f $scan_root/$file
            set -a qml_files (realpath $scan_root/$file)
        else
            echo "qml-check: file not found: $file" >&2
            exit 2
        end
    end
else if test $scan_all -eq 1
    set qml_files (find $scan_root -type f -name '*.qml' \
        -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' | sort)
else
    set qml_files (find $scan_root -type f -name '*.qml' -mmin -5 \
        -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' | head -10)
end

if test (count $qml_files) -eq 0
    exit 0
end

set -l fatal_errors 0
set -l warnings 0

for file in $qml_files
    set -l basename (string replace "$scan_root/" "" $file)

    # Parse without writing source. The helper distinguishes Qt formatter
    # round-trip failures from syntax errors using structured Qt diagnostics.
    if test -n "$parser"
        if not python3 "$project_root/scripts/lib/qml-syntax-check.py" "$parser" "$file"
            echo "ERROR: $basename: QML parser rejected the file" >&2
            set fatal_errors (math $fatal_errors + 1)
        end
    end

    # Quickshell's Singleton type is not a QtQuick type. Accept both modern
    # semicolon-free imports and the older `import Quickshell;` spelling.
    if grep -qE '^[[:space:]]*Singleton[[:space:]]*\{' $file 2>/dev/null
        if not grep -qE '^[[:space:]]*import[[:space:]]+Quickshell([[:space:];]|$)' $file 2>/dev/null
            echo "ERROR: $basename: Singleton requires 'import Quickshell'" >&2
            set fatal_errors (math $fatal_errors + 1)
        end
    end

    # Advisory checks. Keep these non-fatal because the repository still has
    # intentional legacy patterns that should be cleaned independently.
    if grep -qE 'Config\.options\.[a-zA-Z]+\.[a-zA-Z]+[^?]' $file 2>/dev/null
        if not grep -qE 'Config\.options\?\.' $file 2>/dev/null
            echo "WARN: $basename: Config access may need optional chaining (?.)"
            set warnings (math $warnings + 1)
        end
    end

    if grep -qE 'color:[[:space:]]*"#[0-9a-fA-F]{6}"' $file 2>/dev/null
        echo "WARN: $basename: hardcoded color found"
        set warnings (math $warnings + 1)
    end

    if grep -qE 'function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*\([^)]*\)[[:space:]]*\{' $file 2>/dev/null
        if grep -qE 'IpcHandler' $file 2>/dev/null
            if not grep -qE 'function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*\([^)]*\):[[:space:]]*[A-Za-z_]+' $file 2>/dev/null
                echo "WARN: $basename: IPC function may need a return type annotation"
                set warnings (math $warnings + 1)
            end
        end
    end
end

# Resolve local qs.* imports even when qmlformat is unavailable or too old.
# This also runs against staged payload roots, catching mixed installs that keep
# QML consumers after the module they import has been retired.
if test $scan_all -eq 1
    set -l qml_local_module_contract "$project_root/scripts/test-qml-local-module-contract.sh"
    if not bash "$qml_local_module_contract" "$scan_root"
        echo "ERROR: local QML module/type resolution contract failed" >&2
        set fatal_errors (math $fatal_errors + 1)
    end
end

# Project-wide architectural startup guards run only in the full-tree CI mode.
if test $scan_all -eq 1; and test "$scan_root" = "$project_root"
    set -l perimeter_contract "$project_root/scripts/test-perimeter-contracts.sh"
    if not bash "$perimeter_contract"
        echo "ERROR: Connected Perimeter cutover contract failed" >&2
        set fatal_errors (math $fatal_errors + 1)
    end

    set -l perimeter_route_contract "$project_root/scripts/test-perimeter-route-contracts.sh"
    if not bash "$perimeter_route_contract"
        echo "ERROR: Connected Perimeter route contract failed" >&2
        set fatal_errors (math $fatal_errors + 1)
    end

    set -l perimeter_settings_contract "$project_root/scripts/test-perimeter-settings-contracts.sh"
    if not bash "$perimeter_settings_contract"
        echo "ERROR: Connected Perimeter settings contract failed" >&2
        set fatal_errors (math $fatal_errors + 1)
    end

    set -l perimeter_family_contract "$project_root/scripts/test-perimeter-family-contracts.sh"
    if not bash "$perimeter_family_contract"
        echo "ERROR: Connected Perimeter family contract failed" >&2
        set fatal_errors (math $fatal_errors + 1)
    end

    set -l perimeter_source_contract "$project_root/scripts/test-perimeter-source-contracts.sh"
    if not bash "$perimeter_source_contract"
        echo "ERROR: Connected Perimeter source integrity contract failed" >&2
        set fatal_errors (math $fatal_errors + 1)
    end

    set -l perimeter_compatibility_placement_contract "$project_root/scripts/test-perimeter-compatibility-placement-contract.sh"
    if not bash "$perimeter_compatibility_placement_contract"
        echo "ERROR: Connected Perimeter compatibility placement contract failed" >&2
        set fatal_errors (math $fatal_errors + 1)
    end

    set -l equalizer_boundary_contract "$project_root/scripts/test-equalizer-boundary-contract.sh"
    if not bash "$equalizer_boundary_contract"
        echo "ERROR: Equalizer architecture boundary contract failed" >&2
        set fatal_errors (math $fatal_errors + 1)
    end
end

if test -z "$parser"
    if test -n "$parser_skip_reason"
        echo "qml-check: $parser_skip_reason; parser pass skipped" >&2
    else
        echo "qml-check: qmlformat unavailable; startup guards ran, parser pass skipped" >&2
    end
else if test $parser_unknown_direct -eq 1
    echo "qml-check: qmlformat Qt version unknown; parser capability evaluated directly against project QML" >&2
end

if test $fatal_errors -gt 0
    echo "qml-check: $fatal_errors fatal issue(s), $warnings warning(s)" >&2
    exit 1
end

if test $warnings -gt 0
    echo "qml-check: no fatal issues; $warnings warning(s)"
end

exit 0
