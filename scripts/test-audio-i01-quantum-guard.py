#!/usr/bin/env python3
"""AUDIO-I01: fake-executable contract; never starts EasyEffects or PipeWire."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "scripts/audio/easyeffects-quantum-guard.sh"
QML = ROOT / "services/deferred/EasyEffects.qml"
ENV_NAME = "ALIS_AUDIO_I01_LOCK_QUANTUM"
EXPECTED = "{ node.lock-quantum = true }"

with tempfile.TemporaryDirectory(prefix="alis-audio-i01-lock-") as name:
    folder = Path(name)
    bin_dir = folder / "bin"
    bin_dir.mkdir()
    fake = bin_dir / "easyeffects"
    fake.write_text("#!" + sys.executable + "\n" + '''
import json, os, sys
print(json.dumps({
    "pid": os.getpid(), "args": sys.argv[1:],
    "props": os.environ.get("PIPEWIRE_PROPS"),
    "quantum": os.environ.get("PIPEWIRE_QUANTUM"),
    "latency": os.environ.get("PIPEWIRE_LATENCY"),
    "other": os.environ.get("ALIS_TEST_UNRELATED"),
}), flush=True)
raise SystemExit(37)
''')
    fake.chmod(0o700)
    env = dict(os.environ)
    for key in (ENV_NAME, "PIPEWIRE_PROPS", "PIPEWIRE_QUANTUM", "PIPEWIRE_LATENCY"):
        env.pop(key, None)
    env.update(PATH=str(bin_dir) + os.pathsep + env["PATH"], ALIS_TEST_UNRELATED="intact")
    sentinel = folder / "should-not-exist"
    argv = ["easyeffects", "--service-mode", "$(touch " + str(sentinel) + ")"]

    def invoke(extra):
        return subprocess.run(
            ["/usr/bin/bash", str(WRAPPER), *argv],
            env=env | extra, capture_output=True, text=True, timeout=5,
        )

    for case, props in [({}, None), ({ENV_NAME: "0"}, None), ({ENV_NAME: "1"}, EXPECTED)]:
        result = invoke(case)
        assert result.returncode == 37, (case, result.stderr)
        record = json.loads(result.stdout)
        assert record["args"] == argv[1:] and not sentinel.exists(), record
        assert record["props"] == props, (case, record)
        assert record["other"] == "intact" and record["quantum"] is None and record["latency"] is None

    for owner_override in ("PIPEWIRE_PROPS", "PIPEWIRE_QUANTUM", "PIPEWIRE_LATENCY"):
        for value in ("", "1024/48000"):
            result = invoke({ENV_NAME: "1", owner_override: value})
            assert result.returncode == 78 and not result.stdout, (owner_override, result)
            assert "refusing quantum-lock probe" in result.stderr

    missing = subprocess.run(["/usr/bin/bash", str(WRAPPER)], capture_output=True, text=True)
    assert missing.returncode == 64
    no_binary = subprocess.run(
        ["/usr/bin/bash", str(WRAPPER), "does-not-exist"],
        env=env | {ENV_NAME: "1"}, capture_output=True, text=True, timeout=5,
    )
    assert no_binary.returncode == 127

qml = QML.read_text()
assert 'Quickshell.env("ALIS_AUDIO_I01_LOCK_QUANTUM") === "1"' in qml
assert '"/audio/easyeffects-quantum-guard.sh"' in qml
assert 'Quickshell.execDetached(["/usr/bin/env", "easyeffects", "--service-mode"])' in qml
assert 'Quickshell.execDetached(["/usr/bin/env", "flatpak", "run", "com.github.wwmm.easyeffects", "--service-mode"])' in qml
print("AUDIO_I01_LOCK_PASS default unchanged; native opt-in; environment conflicts fail closed; argv literal; no DSP/PipeWire process")
