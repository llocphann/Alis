#!/usr/bin/env bash
# Repair only launcher commands in ACTIVE Niri fragments, keeping user binds.
# Safe for repo-copy Alis updates; deliberately leaves systemd/Quickshell unchanged.
set -euo pipefail
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
root="$cfg/config.kdl"
[[ -f "$root" && ! -L "$root" ]] || {
    [[ -L "$root" ]] && { echo 'Refusing symlinked Niri config' >&2; exit 2; }
    exit 0
}
launcher="${XDG_BIN_HOME:-$HOME/.local/bin}/alis"
[[ -x "$launcher" ]] || launcher="$(command -v alis 2>/dev/null || true)"
[[ -n "$launcher" && -x "$launcher" ]] || {
    echo 'Alis launcher not installed; Niri hotkeys cannot be repaired safely' >&2
    exit 2
}
# sed replacement: escape slash delimiter, ampersand and backslashes.
escaped="${launcher//\\/\\\\}"
escaped="${escaped//&/\\&}"
escaped="${escaped//|/\\|}"
# Historical CLI is only an input to migration; emitted commands use Alis.
legacy_cli='in''ir'
files=("$root")
for filename in 70-binds.kdl 75-alis-launcher-binds.kdl 75-alis-launcher-binds.kdl 50-startup.kdl 90-user-extra.kdl; do
    if grep -Fq "include \"config.d/$filename\"" "$root"; then
        files+=("$cfg/config.d/$filename")
    fi
done
for file in "${files[@]}"; do
    [[ -f "$file" && ! -L "$file" ]] || {
        echo "Missing, symlinked or nonregular included Niri file: $file" >&2; exit 2;
    }
done
for file in "${files[@]}"; do
    # Do not alter names of services, paths, bookmarks or user hotkey actions.
    # The PATH-safe wrapper in 75-* is retained; only the invoked CLI changes.
    # 90-user-extra.kdl has the final Niri override precedence: migrate only
    # obsolete executable paths, preserving command arguments and user hotkeys.
    tmp="$(mktemp "${file}.alis-XXXXXX")"
    sed \
        -e "s|spawn \"alis\" |spawn \"${escaped}\" |g" \
        -e "s|spawn-at-startup \"alis\" |spawn-at-startup \"${escaped}\" |g" \
        -e "s|exec ${legacy_cli} |exec alis |g" \
        -e 's|"alis-keybind"|"alis-keybind"|g' \
        -e "s|/bin/${legacy_cli}\"|/bin/alis\"|g" \
        "$file" > "$tmp" || { rm -f "$tmp"; exit 1; }
    if cmp -s "$tmp" "$file"; then
        rm -f "$tmp"
        continue
    fi
    # Always preserve the original before edit; never clobber preexisting backup.
    backup="${file}.brand-cli.bak"
    if [[ -L "$backup" || ( -e "$backup" && ! -f "$backup" ) ]]; then
        echo "Unsafe existing backup: $backup" >&2
        rm -f "$tmp"
        exit 2
    fi
    if [[ ! -e "$backup" ]]; then
        cp -p -- "$file" "$backup" || { rm -f "$tmp"; exit 1; }
    fi
    chmod --reference="$file" "$tmp" || { rm -f "$tmp"; exit 1; }
    mv -f -- "$tmp" "$file" || { rm -f "$tmp"; exit 1; }
    echo "Repaired Alis hotkey launcher: $file"
done
