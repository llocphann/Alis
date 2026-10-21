#!/usr/bin/env python3
"""Read-only history view: collapse identical text, never edit the database."""

from collections import defaultdict
import argparse
import hashlib
import os
import re
import selectors
import signal
import subprocess
import sys
import time


def read_command(argv, deadline, *, fingerprint=False):
    """Bound each owned child and its output without retaining decoded text."""
    if time.monotonic() >= deadline:
        return None
    try:
        process = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    except OSError:
        return None
    chunks = []
    digest = hashlib.sha256()
    size = 0
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not selector.select(remaining):
                    return None
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk:
                    break
                size += len(chunk)
                if size > 8 * 1024 * 1024:
                    return None
                if fingerprint:
                    digest.update(chunk)
                else:
                    chunks.append(chunk)
        remaining = deadline - time.monotonic()
        if remaining <= 0 or process.wait(timeout=remaining) != 0:
            return None
        return (size, digest.digest()) if fingerprint else b"".join(chunks)
    except (OSError, subprocess.TimeoutExpired):
        return None
    finally:
        process.stdout.close()
        if process.poll() is None:
            process.kill()
        process.wait()


def unique_text_rows(rows, decode):
    # Previews are only a cheap candidate index. Whitespace and 100-character
    # truncation can make DIFFERENT payloads look identical; decode before hiding.
    candidates = defaultdict(list)
    for index, row in enumerate(rows):
        ident, separator, preview = row.partition("\t")
        if (separator and ident.isascii() and ident.isdigit()
                and not re.search(r"\[\[\s*binary data\b", preview, re.IGNORECASE)):
            candidates[preview].append((index, ident))
    hidden = set()
    for group in candidates.values():
        if len(group) < 2:
            continue
        seen = set()
        for index, ident in group:
            key = decode(ident)
            # Unavailable, changed, oversized or slow entries stay visible.
            if key is None:
                continue
            if key in seen:
                hidden.add(index)
            else:
                seen.add(key)
    return [row for index, row in enumerate(rows) if index not in hidden]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", default="cliphist")
    parser.add_argument("--limit", type=int, default=400)
    args = parser.parse_args()
    if not 0 <= args.limit <= 10000:
        parser.error("limit must be between 0 and 10000")
    deadline = time.monotonic() + 8
    data = read_command([args.binary, "list"], min(deadline, time.monotonic() + 4))
    if data is None:
        print("clipboard-history: history read failed", file=sys.stderr)
        return 1
    rows = data.decode("utf-8", "replace").split("\n")
    if rows and rows[-1] == "":
        rows.pop()
    rows = rows[:args.limit]

    def decode(ident):
        return read_command([args.binary, "decode", ident],
                            min(deadline, time.monotonic() + 1), fingerprint=True)

    result = unique_text_rows(rows, decode)
    if result:
        sys.stdout.write("\n".join(result) + "\n")
    return 0


if __name__ == "__main__":
    # Let the active child's finally block run when Quickshell closes its read.
    def terminate(_signum, _frame):
        raise SystemExit(143)
    signal.signal(signal.SIGTERM, terminate)
    raise SystemExit(main())
