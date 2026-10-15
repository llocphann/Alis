#!/usr/bin/env python3
"""Child-only CAVA environment defaults; no actual audio process is invoked."""
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "scripts/cava/run.sh"
DEFAULT_PROPS = "{ node.latency = null }"

with tempfile.TemporaryDirectory(prefix="alis-cava-wrapper-") as name:
    folder = Path(name)
    binary = folder / "bin"
    binary.mkdir()
    fake = binary / "cava"
    fake.write_text("#!" + sys.executable + "\n" + '''
import json, os, signal, sys
print(json.dumps({
    "pid": os.getpid(), "argv": sys.argv[1:],
    "props": os.environ.get("PIPEWIRE_PROPS"),
    "latency": os.environ.get("PIPEWIRE_LATENCY"),
    "unrelated": os.environ.get("CAVA_UNRELATED_SETTING"),
}), flush=True)
if os.environ.get("CAVA_TEST_MODE") == "wait":
    while True: signal.pause()
raise SystemExit(int(os.environ.get("CAVA_TEST_EXIT", "37")))
''')
    fake.chmod(0o700)
    base = dict(os.environ, PATH=str(binary), CAVA_UNRELATED_SETTING="preserved")
    base.pop("PIPEWIRE_PROPS", None)
    base.pop("PIPEWIRE_LATENCY", None)
    base.pop("CAVA_TEST_MODE", None)
    base.pop("CAVA_TEST_EXIT", None)
    sentinel = folder / "must-not-exist"
    args = ["-p", str(folder / "config with spaces.ini"), "$(touch " + str(sentinel) + ")", "line1\nline2"]
    cases = [
        ({}, DEFAULT_PROPS, None),
        ({"PIPEWIRE_PROPS": ""}, "", None),
        ({"PIPEWIRE_PROPS": "{ node.latency = 1024/48000 }"}, "{ node.latency = 1024/48000 }", None),
        ({"PIPEWIRE_LATENCY": ""}, None, ""),
        ({"PIPEWIRE_LATENCY": "1024/48000"}, None, "1024/48000"),
        ({"PIPEWIRE_PROPS": "", "PIPEWIRE_LATENCY": ""}, "", ""),
        ({"PIPEWIRE_PROPS": "custom", "PIPEWIRE_LATENCY": "512/48000"}, "custom", "512/48000"),
    ]
    for overrides, props, latency in cases:
        process = subprocess.Popen(
            ["/usr/bin/bash", str(WRAPPER), *args], env=base | overrides,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        try:
            stdout, stderr = process.communicate(timeout=5)
        except BaseException:
            process.kill()
            process.wait(timeout=3)
            raise
        assert process.returncode == 37, (overrides, process.returncode, stderr)
        record = json.loads(stdout)
        assert record["pid"] == process.pid, "wrapper forked instead of exec"
        assert record["argv"] == args and not sentinel.exists(), record
        assert record["props"] == props and record["latency"] == latency, (overrides, record)
        assert record["unrelated"] == "preserved", record

    # An exec wrapper preserves native signal termination and exposes the real
    # analyzer PID to Quickshell instead of retaining a supervising shell.
    process = subprocess.Popen(
        ["/usr/bin/bash", str(WRAPPER)], env=base | {"CAVA_TEST_MODE": "wait"},
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            assert selector.select(timeout=5), "fake analyzer did not start"
        record = json.loads(process.stdout.readline())
        assert record["pid"] == process.pid, record
        process.send_signal(signal.SIGTERM)
        assert process.wait(timeout=3) == -signal.SIGTERM
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=3)
        process.stdout.close()
        process.stderr.close()

    absent = folder / "empty-path"
    absent.mkdir()
    result = subprocess.run(
        ["/usr/bin/bash", str(WRAPPER)], env=base | {"PATH": str(absent)},
        capture_output=True, text=True, timeout=5,
    )
    assert result.returncode == 127, result

print("CAVA_RUN_PASS child-only defaults; explicit/empty overrides; literal argv; exec PID; exit/signal; missing optional executable")
