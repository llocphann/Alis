#!/usr/bin/env bash
# Publish a staged generated file without waking watchers when bytes are unchanged.
# The staged file should live on the same filesystem as the destination so mv is atomic.
publish_if_changed() {
    local staged="${1:?staged file is required}"
    local destination="${2:?destination file is required}"

    [[ -s "$staged" ]] || return 1

    # Do not preserve a symlink destination: the old mv behavior replaced it with
    # a regular generated file, and keeping that behavior avoids redirecting writes.
    if [[ -f "$destination" && ! -L "$destination" ]] && cmp -s -- "$staged" "$destination"; then
        rm -f -- "$staged"
        return 0
    fi

    local parent
    parent="$(dirname -- "$destination")" || return 1
    mkdir -p -- "$parent" || return 1
    mv -f -- "$staged" "$destination"
}
