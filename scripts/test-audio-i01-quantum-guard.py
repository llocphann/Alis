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

    for case, props in [({}, EXPECTED), ({ENV_NAME: "0"}, None), ({ENV_NAME: "1"}, EXPECTED)]:
        result = invoke(case)
        assert result.returncode == 37, (case, result.stderr)
        record = json.loads(result.stdout)
        assert record["args"] == argv[1:] and not sentinel.exists(), record
        assert record["props"] == props, (case, record)
        assert record["other"] == "intact" and record["quantum"] is None and record["latency"] is None

    for owner_override in ("PIPEWIRE_PROPS", "PIPEWIRE_QUANTUM", "PIPEWIRE_LATENCY"):
        for value in ("", "1024/48000"):
            result = invoke({ENV_NAME: "1", owner_override: value})
            assert result.returncode == 37, (owner_override, result.stderr)
            record = json.loads(result.stdout)
            assert record["props"] == (value if owner_override == "PIPEWIRE_PROPS" else None), record
            assert record["quantum"] == (value if owner_override == "PIPEWIRE_QUANTUM" else None), record
            assert record["latency"] == (value if owner_override == "PIPEWIRE_LATENCY" else None), record
            assert "starting without Alis quantum lock" in result.stderr

    missing = subprocess.run(["/usr/bin/bash", str(WRAPPER)], capture_output=True, text=True)
    assert missing.returncode == 64
    no_binary = subprocess.run(
        ["/usr/bin/bash", str(WRAPPER), "does-not-exist"],
        env=env | {ENV_NAME: "1"}, capture_output=True, text=True, timeout=5,
    )
    assert no_binary.returncode == 127

# Every Alis quick-toggle settings action must route through the same guarded
# singleton launcher as the normal native EasyEffects toggle.
for path in [
    "modules/common/models/quickToggles/EasyEffectsToggle.qml",
    "modules/sidebarRight/quickToggles/classicStyle/EasyEffectsToggle.qml",
    "modules/sidebarRight/quickToggles/androidStyle/AndroidEasyEffectsToggle.qml",
]:
    surface = (ROOT / path).read_text()
    assert "EasyEffects.openSettings()" in surface, path
    assert "flatpak run com.github.wwmm.easyeffects; or easyeffects" not in surface, path

qml = QML.read_text()
assert 'function openSettings()' in qml
assert qml.count('Quickshell.env("ALIS_AUDIO_I01_LOCK_QUANTUM") !== "0"') == 2
assert '"/audio/easyeffects-quantum-guard.sh"' in qml
assert 'Quickshell.execDetached(["/usr/bin/env", "easyeffects", "--service-mode"])' in qml
assert 'Quickshell.execDetached(["/usr/bin/env", "flatpak", "run", "com.github.wwmm.easyeffects", "--service-mode"])' in qml
print("AUDIO_I01_LOCK_PASS native default-on; explicit opt-out; owner PipeWire overrides preserved; argv literal; no DSP/PipeWire process")
