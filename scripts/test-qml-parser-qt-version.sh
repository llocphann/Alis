#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$repo_root/scripts/lib/qml-parser-qt-version.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"

fail() {
    printf 'FAIL: qml parser Qt version detection: %s\n' "$1" >&2
    exit 1
}

write_cmd() {
    local name="$1" body="$2"
    cat > "$tmp/bin/$name" <<EOF
#!/usr/bin/env bash
$body
EOF
    chmod +x "$tmp/bin/$name"
}

write_cmd qmlformat 'printf "%s\n" "qmlformat 1.0"'
write_cmd qtpaths6 '[[ "${1:-}" == "--qt-version" ]] && printf "%s\n" "6.8.3"'
write_cmd qtpaths 'exit 1'
write_cmd qmake6 'exit 1'
write_cmd qmake 'exit 1'
write_cmd qml6 'exit 1'
write_cmd qml 'exit 1'
write_cmd pacman 'exit 1'

detect_version() {
    ALIS_QML_VERSION_SYSTEM_FALLBACKS=0 \
        PATH="$tmp/bin:/usr/bin:/bin" \
        bash "$helper" "$tmp/bin/qmlformat"
}

version="$(detect_version)"
[[ "$version" == "6.8.3" ]] || fail "qtpaths6 fallback returned '$version'"

write_cmd qtpaths6 'exit 1'
write_cmd qmake6 '[[ "${1:-}" == "-query" && "${2:-}" == "QT_VERSION" ]] && printf "%s\n" "6.9.1"'
version="$(detect_version)"
[[ "$version" == "6.9.1" ]] || fail "qmake6 fallback returned '$version'"

write_cmd qmake6 'exit 1'
write_cmd qml 'printf "%s\n" "Qml Runtime 6.10.2"'
version="$(detect_version)"
[[ "$version" == "6.10.2" ]] || fail "qml runtime fallback returned '$version'"

write_cmd qml 'exit 1'
write_cmd qmlformat 'printf "%s\n" "qmlformat 6.4.2"'
version="$(detect_version)"
[[ "$version" == "6.4.2" ]] || fail "direct Qt-like qmlformat version returned '$version'"

write_cmd qmlformat 'printf "%s\n" "qmlformat 1.0"'
write_cmd pacman 'if [[ "${1:-}" == "-Qqo" ]]; then printf "%s\n" "qt6-declarative"; exit 0; fi
if [[ "${1:-}" == "-Q" && "${2:-}" == "qt6-declarative" ]]; then printf "%s\n" "qt6-declarative 6.11.2-2"; exit 0; fi
exit 1'
version="$(detect_version)"
[[ "$version" == "6.11.2" ]] || fail "pacman package fallback returned '$version'"

write_cmd pacman 'exit 1'
if detect_version >/dev/null 2>&1; then
    fail 'tool-local qmlformat 1.0 was incorrectly accepted as a Qt version'
fi

printf 'PASS: qml parser detection distinguishes qmlformat tool version from Qt runtime\n'
