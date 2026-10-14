#!/usr/bin/env python3
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from urllib.parse import urlparse
from urllib.request import urlopen

CDP_URL = os.environ.get(
    "HADALIS_CHATGPT_CDP_URL",
    "http://127.0.0.1:9222",
).rstrip("/")
CHATGPT_BIN = os.environ.get("HADALIS_CHATGPT_BIN") or shutil.which("chatgpt")
START_TIMEOUT = float(os.environ.get("HADALIS_CHATGPT_START_TIMEOUT_SECONDS", "30"))
POLL_SECONDS = float(os.environ.get("HADALIS_CHATGPT_HOST_POLL_SECONDS", "2"))
MAX_MISSES = int(os.environ.get("HADALIS_CHATGPT_HOST_MAX_MISSES", "3"))


def cdp_parts() -> tuple[str, int]:
    parsed = urlparse(CDP_URL)
    if (
        parsed.scheme != "http"
        or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}
    ):
        raise RuntimeError("HADALIS_CHATGPT_CDP_URL must use loopback HTTP")
    return parsed.hostname, parsed.port or 80


def cdp_healthy() -> bool:
    try:
        with urlopen(f"{CDP_URL}/json/version", timeout=1.5) as response:
            payload = json.load(response)
    except Exception:
        return False

    websocket = payload.get("webSocketDebuggerUrl")
    return isinstance(websocket, str) and websocket.startswith(
        ("ws://127.0.0.1:", "ws://localhost:")
    )


def launch_command() -> list[str]:
    if not CHATGPT_BIN:
        raise RuntimeError("chatgpt executable not found")
    _host, port = cdp_parts()
    return [
        str(Path(CHATGPT_BIN)),
        "--remote-debugging-address=127.0.0.1",
        f"--remote-debugging-port={port}",
    ]


def wait_for_cdp(child: subprocess.Popen[bytes] | None) -> bool:
    deadline = time.monotonic() + START_TIMEOUT

    while time.monotonic() < deadline:
        if cdp_healthy():
            return True
        if child is not None and child.poll() not in (None, 0):
            return False
        time.sleep(0.25)

    return cdp_healthy()


def supervise() -> int:
    cdp_parts()

    child: subprocess.Popen[bytes] | None = None

    if not cdp_healthy():
        child = subprocess.Popen(
            launch_command(),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        if not wait_for_cdp(child):
            if child.poll() == 0:
                print(
                    "ChatGPT is already running without the required localhost "
                    "CDP endpoint. Close that instance once, then restart "
                    "hadalis-chatgpt.service.",
                    file=sys.stderr,
                )
                return 76
            return 1

    misses = 0
    while True:
        time.sleep(POLL_SECONDS)

        if cdp_healthy():
            misses = 0
            continue

        misses += 1
        if misses >= MAX_MISSES:
            return 1


def main() -> int:
    try:
        return supervise()
    except KeyboardInterrupt:
        return 0
    except Exception as exc:
        print(f"hadalis ChatGPT host error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
