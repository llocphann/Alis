#!/usr/bin/env python3
"""Exact-content history view, failure bounds and real private QML refresh."""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(os.environ.get("ALIS_CLIPBOARD_HISTORY_TEST_ROOT", ROOT)).resolve()
spec = importlib.util.spec_from_file_location("history", ROOT / "scripts/clipboard-history.py")
history = importlib.util.module_from_spec(spec)
spec.loader.exec_module(history)


def fingerprint(payload):
    return len(payload), hashlib.sha256(payload).digest()


def policies():
    decoded = {"9": b"same", "8": b"same", "7": b"different",
               "6": b"line", "5": b"line\n"}
    calls = []

    def decode(ident):
        calls.append(ident)
        return fingerprint(decoded[ident]) if ident in decoded else None

    rows = ["9\tmatching preview", "8\tmatching preview", "7\tmatching preview",
            "6\tline", "5\tline", "4\t[[ binary data png 20x20 ]]",
            "3\t[[ binary data png 20x20 ]]", "2\tunknown", "1\tunknown"]
    expected = [row for row in rows if not row.startswith("8\t")]
    assert history.unique_text_rows(rows, decode) == expected
    assert calls == ["9", "8", "7", "6", "5", "2", "1"]
    assert history.unique_text_rows([], decode) == []
    assert history.unique_text_rows(["invalid", "invalid"], decode) == ["invalid", "invalid"]
    # A single preview never launches a decoder; images never do either.
    assert history.unique_text_rows(["20\tunique"], lambda _: 1 / 0) == ["20\tunique"]
    assert history.read_command([sys.executable, "-c", "import sys;sys.exit(1)"], time.monotonic()+2) is None
    assert history.read_command([sys.executable, "-c", "print('synthetic')"], time.monotonic()+2) == b"synthetic\n"
    assert history.read_command([sys.executable, "-c", "import time;time.sleep(5)"], time.monotonic()+.1) is None
    assert history.read_command([sys.executable, "-c", "import sys;sys.stdout.buffer.write(b'x'*9000000)"], time.monotonic()+2, fingerprint=True) is None
    print("PASS: 9 history policies, exact bytes, preview collisions, image retention and bounded failure")


def native():
    if not shutil.which("qs") or not shutil.which("cliphist"):
        print("SKIP: private QML history needs Quickshell and cliphist")
        return
    with tempfile.TemporaryDirectory(prefix="alis-clip-history-") as tmp:
        p = Path(tmp)
        for name in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
            (p/name).symlink_to(SOURCE/name)
        config = p/"config/alis"
        config.mkdir(parents=True)
        data = json.loads((SOURCE/"defaults/config.json").read_text())
        data["clipboard"] = {"pinned": ["synthetic pin A", "synthetic pin B"]}
        (config/"config.json").write_text(json.dumps(data))
        env = {k: v for k, v in os.environ.items() if not k.startswith("CLIPHIST_")}
        env.update(QT_QPA_PLATFORM="offscreen", QSG_RHI_BACKEND="software",
                   XDG_CONFIG_HOME=str(p/"config"), XDG_STATE_HOME=str(p/"state"),
                   XDG_CACHE_HOME=str(p/"cache"), XDG_DATA_HOME=str(p/"data"),
                   CLIPHIST_MAX_DEDUPE_SEARCH="0")
        for key in ["QS_CONFIG_NAME", "QS_CONFIG_PATH", "QS_MANIFEST"]:
            env.pop(key, None)
        # Retain old repeated text IDs with interleaved distinct copies, like a
        # history whose duplicates outlived the backend's limited search window.
        for i in range(8):
            for payload in [b"synthetic repeated copy", f"synthetic distinct {i}".encode()]:
                subprocess.run(["cliphist", "store"], input=payload, env=env, check=True, capture_output=True)
        for payload in [b"q"*140+b"one", b"q"*140+b"two", b"trailing line", b"trailing line\n"]:
            subprocess.run(["cliphist", "store"], input=payload, env=env, check=True, capture_output=True)

        def raw():
            return subprocess.check_output(["cliphist", "list"], env=env)

        before = raw()
        expected, seen, original = [], set(), {}
        for row in before.decode().splitlines():
            ident = row.split("\t", 1)[0]
            payload = subprocess.check_output(["cliphist", "decode", ident], env=env)
            original[ident] = payload
            if payload not in seen:
                expected.append(row)
                seen.add(payload)
        assert len(original) == 20 and len(expected) == 13
        (p/"expected.json").write_text(json.dumps(expected))
        (p/"shell.qml").write_text(r'''
import QtQuick
import Quickshell
import qs.modules.common
import qs.services.deferred
ShellRoot {
 id: root
 property int ticks: 0
 property int updates: 0
 property var expected: JSON.parse(Quickshell.env("CLIP_HISTORY_EXPECTED"))
 Component.onCompleted: Quickshell.watchFiles = false
 Connections { target: Cliphist; function onEntriesChanged() { root.updates++ } }
 Timer {
  interval: 30; repeat: true; running: true
  onTriggered: {
   if (!Config.ready) return
   root.ticks++
   if (root.ticks < 15) Cliphist.refresh()
   if (root.ticks < 90) return
   const actual = Array.from(Cliphist.entries)
   if (JSON.stringify(actual) !== JSON.stringify(root.expected))
    console.error("CLIP_HISTORY_FAIL", "rows", actual.length, "expected", root.expected.length)
   else if (root.updates !== 1 || Config.options.clipboard.pinned.length !== 2)
    console.error("CLIP_HISTORY_FAIL", "refresh identity or pins", root.updates)
   else console.info("CLIP_HISTORY_PASS", actual.length, "unique rows, 14 refresh requests, pins retained")
   Qt.quit()
  }
 }
}
''')
        env["CLIP_HISTORY_EXPECTED"] = json.dumps(expected)
        result = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(p), "--no-color"],
                                env=env, capture_output=True, text=True, timeout=15)
        output = result.stdout+result.stderr
        if os.environ.get("ALIS_CLIPBOARD_HISTORY_TEST_LOG"):
            Path(os.environ["ALIS_CLIPBOARD_HISTORY_TEST_LOG"]).write_text(output)
        assert raw() == before, "history IDs/order changed during read-only refresh"
        for ident, payload in original.items():
            assert subprocess.check_output(["cliphist", "decode", ident], env=env) == payload
        bad = ["CLIP_HISTORY_FAIL", "ReferenceError:", "TypeError:", "Binding loop", "unavailable"]
        if result.returncode or "CLIP_HISTORY_PASS" not in output or any(x in output for x in bad):
            print(output)
            raise SystemExit(1)
        for line in output.splitlines():
            if "CLIP_HISTORY_PASS" in line:
                print(line)
        print("PASS: 20 raw entries and all payloads unchanged; 7 exact repeats hidden, 2 colliding long previews and distinct trailing newline retained")


if __name__ == "__main__":
    policies()
    native()
