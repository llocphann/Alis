#!/usr/bin/env bash
set -euo pipefail

parser="${1:-}"
[[ -n "$parser" ]] || { printf 'usage: %s <qmlformat-path>\n' "$0" >&2; exit 2; }

resolve_cmd() {
    local candidate="$1"
    if [[ "$candidate" == /* ]]; then
        [[ -x "$candidate" ]] && printf '%s\n' "$candidate"
    else
        command -v "$candidate" 2>/dev/null || true
    fi
    return 0
}

extract_version() {
    grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1
}

parser_invocation_path="$(resolve_cmd "$parser")"
[[ -n "$parser_invocation_path" ]] || exit 1
parser_path="$(realpath "$parser_invocation_path" 2>/dev/null || printf '%s\n' "$parser_invocation_path")"
parser_dir="$(cd -- "$(dirname -- "$parser_path")" && pwd -P)"
system_fallbacks="${ALIS_QML_VERSION_SYSTEM_FALLBACKS:-1}"

# qmlformat's own --version may be the formatter's tool version (for example
# "qmlformat 1.0"), not the Qt runtime version. Prefer Qt installation tools.
for candidate in \
    "$parser_dir/qtpaths6" "$parser_dir/qtpaths" \
    qtpaths6 qtpaths
do
    resolved="$(resolve_cmd "$candidate")"
    [[ -n "$resolved" ]] || continue
    version="$("$resolved" --qt-version 2>/dev/null | extract_version || true)"
    if [[ -n "$version" ]]; then
        printf '%s\n' "$version"
        exit 0
    fi
done

for candidate in \
    "$parser_dir/qmake6" "$parser_dir/qmake" \
    qmake6 qmake
do
    resolved="$(resolve_cmd "$candidate")"
    [[ -n "$resolved" ]] || continue
    version="$("$resolved" -query QT_VERSION 2>/dev/null | extract_version || true)"
    if [[ -n "$version" ]]; then
        printf '%s\n' "$version"
        exit 0
    fi
done

# Some distributions report the Qt version directly from qmlformat. Accept that
# only when it looks like a Qt major version, never a tool-local 1.x version.
version="$("$parser_path" --version 2>&1 | extract_version || true)"
if [[ -n "$version" ]]; then
    major="${version%%.*}"
    if (( major >= 5 )); then
        printf '%s\n' "$version"
        exit 0
    fi
fi

# qml ships with Qt Declarative alongside qmlformat on common Qt 6 installs.
# First probe sibling runtimes from the same Qt installation. System-wide
# fallbacks can be disabled by the detector regression test to keep it hermetic.
for candidate in "$parser_dir/qml6" "$parser_dir/qml"
do
    resolved="$(resolve_cmd "$candidate")"
    [[ -n "$resolved" ]] || continue
    version="$("$resolved" --version 2>&1 | extract_version || true)"
    [[ -n "$version" ]] || continue
    major="${version%%.*}"
    if (( major >= 5 )); then
        printf '%s\n' "$version"
        exit 0
    fi
done

if [[ "$system_fallbacks" != "0" ]]; then
    for candidate in /usr/lib/qt6/bin/qml /usr/lib/x86_64-linux-gnu/qt6/bin/qml qml6 qml
    do
        resolved="$(resolve_cmd "$candidate")"
        [[ -n "$resolved" ]] || continue
        version="$("$resolved" --version 2>&1 | extract_version || true)"
        [[ -n "$version" ]] || continue
        major="${version%%.*}"
        if (( major >= 5 )); then
            printf '%s\n' "$version"
            exit 0
        fi
    done
fi

# Arch packages qmlformat with the Qt Declarative package. Query ownership using
# the path the shell actually invoked: package databases may own /usr/bin/qmlformat
# while its canonical symlink target is not separately tracked.
pacman_path="$(resolve_cmd "$parser_dir/pacman")"
if [[ -z "$pacman_path" && "$system_fallbacks" != "0" ]]; then
    pacman_path="$(resolve_cmd pacman)"
fi
if [[ -n "$pacman_path" ]]; then
    owner=""
    for owned_path in "$parser_invocation_path" "$parser_path"; do
        owner="$("$pacman_path" -Qqo "$owned_path" 2>/dev/null | head -n1 || true)"
        [[ -n "$owner" ]] && break
    done
    if [[ -n "$owner" ]]; then
        version="$("$pacman_path" -Q "$owner" 2>/dev/null | extract_version || true)"
        if [[ -n "$version" ]]; then
            major="${version%%.*}"
            if (( major >= 5 )); then
                printf '%s\n' "$version"
                exit 0
            fi
        fi
    fi
fi

exit 1
