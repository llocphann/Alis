#!/usr/bin/env bash
if [[ -v MOCK_NEW || -v MOCK_OLD ]]; then
    exit 0
fi
locked_state=$(timeout 2s busctl --user get-property org.freedesktop.secrets \
    /org/freedesktop/secrets/collection/login \
    org.freedesktop.Secret.Collection Locked 2>/dev/null)
if [[ "${locked_state}" == "b false" ]]; then
    echo 'Keyring is unlocked' >&2
    exit 0
else
    echo 'Keyring is locked' >&2
    exit 1
fi
