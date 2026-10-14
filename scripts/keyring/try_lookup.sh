#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try the canonical Alis namespace first. Existing upstream secrets remain
# readable without copying, deleting or exposing their plaintext in logs.
data=$(secret-tool lookup 'application' 'alis' 2>/dev/null)
if [[ -z "$data" ]]; then
    data=$(secret-tool lookup 'application' 'illogical-impulse' 2>/dev/null)
fi
if [[ -z "$data" ]]; then
    if "${SCRIPT_DIR}/is_unlocked.sh"; then
        echo 'not found'
        exit 1
    else
        echo 'locked'
        exit 2
    fi
fi
echo "$data"
