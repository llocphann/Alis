#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE_DISPATCH="$SCRIPT_DIR/../native-dispatch"

# Thumbnailing can read gigabytes of image data. Prefer Alis's native Rust
# thumbgen (alis-theme --thumbgen) so core runtime requires neither Python
# .venv nor pygobject/GnomeDesktop nor ImageMagick.
if [[ -x "$NATIVE_DISPATCH" ]]; then
    if [[ -z "${ALIS_THUMBGEN_SCOPED:-}" ]] && command -v systemd-run >/dev/null 2>&1; then
        exec systemd-run --user --scope --quiet --collect \
            --property="Description=Alis wallpaper thumbnails" \
            --setenv=ALIS_THUMBGEN_SCOPED=1 \
            -- "$NATIVE_DISPATCH" thumbgen "$@"
    fi
    exec "$NATIVE_DISPATCH" thumbgen "$@"
fi

if [[ -n "${ALIS_VENV:-}" ]]; then
    _ii_venv="$(eval echo "$ALIS_VENV")"
elif [[ -n "${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-}" ]]; then
    _ii_venv="$(eval echo "$ILLOGICAL_IMPULSE_VIRTUAL_ENV")"
else
    _ii_venv="$HOME/.local/state/quickshell/.venv"
fi
source "$_ii_venv/bin/activate" 2>/dev/null || true

if [[ -z "${ALIS_THUMBGEN_SCOPED:-}" ]] && command -v systemd-run >/dev/null 2>&1; then
    exec systemd-run --user --scope --quiet --collect \
        --property="Description=Alis wallpaper thumbnails" \
        --setenv=ALIS_THUMBGEN_SCOPED=1 \
        --setenv=GIO_USE_VFS=local \
        -- "$_ii_venv/bin/python3" "$SCRIPT_DIR/thumbgen.py" "$@"
fi

exec env GIO_USE_VFS=local "$_ii_venv/bin/python3" "$SCRIPT_DIR/thumbgen.py" "$@"
