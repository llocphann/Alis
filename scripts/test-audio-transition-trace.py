#!/usr/bin/env python3
"""Offline parser/privacy regression and fake-tool end-to-end coverage. No audio session."""
import argparse
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("collect-audio-transition-trace.py")
spec = importlib.util.spec_from_file_location("audio_trace", SCRIPT)
trace = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trace)
SECRET = "PRIVATE-title-device-https://site.invalid/?token=secret"


def node(key=10, serial=100, client=2, **extra):
    return {"id": key, "type": "PipeWire:Interface:Node", "info": {
        "state": "running", "props": {"object.serial": serial, "client.id": client,
        "media.class": "Stream/Output/Audio", "node.name": SECRET, "media.name": SECRET, **extra}}}


def client(binary="firefox", key=2):
    return {"id": key, "type": "PipeWire:Interface:Client", "info": {
        "props": {"application.process.binary": binary, "application.name": SECRET}}}


def link():
    return {"id": 30, "type": "PipeWire:Interface:Link", "info": {
        "output-node-id": 10, "input-node-id": 20, "props": {"object.serial": 300, "node.name": SECRET}}}


HEADER = " ".join(trace.Top.HEADER)


class ParserTests(unittest.TestCase):
    def setUp(self):
        self.output = io.StringIO()
        self.writer = trace.Writer(self.output)
        self.graph = trace.Graph(self.writer)
        self.graph.update([node(), client(), link()])
        self.top = trace.Top(self.graph, self.writer)

    def records(self):
        return [json.loads(line) for line in self.output.getvalue().splitlines()]

    def frame(self, errors=30, state="R", quantum=1024, key=10):
        self.top.line(HEADER)
        self.top.line(f"{state} {key} {quantum} 48000 1us 2us 0.1 0.1 {errors} F32LE {SECRET}")
        self.top.finish()
        return self.records()[-1]

    def test_privacy_and_partial_graph_lifetime(self):
        self.assertEqual(self.records()[0]["category"], "browser")
        self.graph.update([{"id": 10, "info": {"state": "idle"}}])
        self.assertEqual(self.records()[-1]["serial"], 100)
        self.assertEqual(self.records()[-1]["state"], "idle")
        self.graph.update([{"id": 30, "info": None}])
        self.assertEqual(self.records()[-1]["event"], "removed")
        self.assertNotIn(SECRET, self.output.getvalue())
        for binary, expected in [("mpd", "local"), ("cava", "cava"), ("easyeffects", "dsp"), (SECRET, "other")]:
            self.graph.update([client(binary), node()])
            self.assertEqual(self.records()[-1]["category"], expected)
        self.graph.update([client("not-firefox"), node(**{"application.process.binary": "firefox"})])
        self.assertEqual(self.records()[-1]["category"], "other", "node-supplied binary must not override client classification")
        self.assertNotIn(SECRET, repr(self.graph.objects))

    def test_requested_latency_and_boolean_sanitization(self):
        for raw, expected in [("512/48000", [512, 48000]), ("0/48000", [0, 48000]),
                              ("1/0", None), ("4294967296/48000", None), (SECRET, None), ({"private": SECRET}, None)]:
            self.graph.update([node(**{"node.latency": raw, "node.passive": "true", "node.always-process": "false",
                                      "node.driver": True, "node.driver-id": "20"})])
            event = self.records()[-1]
            self.assertEqual(event["requested_latency"], expected)
            self.assertIs(event["passive"], True)
            self.assertIs(event["always_process"], False)
            self.assertIs(event["node_driver"], True)
            self.assertEqual(event["driver_id"], 20)
        self.graph.update([node(**{"node.passive": SECRET, "node.driver-id": SECRET})])
        self.assertIsNone(self.records()[-1]["passive"])
        self.assertIsNone(self.records()[-1]["driver_id"])
        self.assertNotIn(SECRET, repr(self.graph.objects))

    def test_malformed_types_are_sanitized_failures(self):
        for value in (None, [], {}, 123):
            for item in ({"id": 10, "type": value}, node(**{"media.class": value}),
                         client(value),
                         {"id": 10, "info": {"state": value}}):
                with self.assertRaises(trace.TraceError):
                    self.graph.update([item])
        for value in (None, [], 123):
            with self.assertRaises(trace.TraceError):
                self.graph.update([{"id": 10, "info": {"props": value}}])

    def test_mature_deltas_reset_missing_and_reused_identity(self):
        self.assertTrue(self.frame()["warmup"])
        self.assertEqual(self.frame()["samples"][0]["counter_status"], "baseline")
        self.assertEqual(self.frame(32)["samples"][0]["err_delta"], 2)
        reset = self.frame(1)["samples"][0]
        self.assertEqual((reset["counter_status"], reset["err_delta"]), ("reset", None))
        self.assertEqual(self.frame(1)["samples"][0]["err_delta"], 0)
        self.assertEqual(self.frame(state="C", quantum=0)["samples"], [])
        self.assertEqual(self.frame(key=99)["samples"], [])
        self.graph.update([{"id": 10, "info": None}, node(serial=200)])
        fresh = self.frame(50)["samples"][0]
        self.assertEqual((fresh["serial"], fresh["err_delta"]), (200, None))
        self.top.line(HEADER)
        self.top.line(f"R 10 1024 48000 1us 2us 0.1 0.1 50 F32LE {SECRET}")
        self.graph.update([{"id": 10, "info": None}, node(serial=201)])
        self.top.finish()
        self.assertEqual(self.records()[-1]["samples"], [], "reuse inside frame must be rejected")
        self.assertIsNone(self.frame(51)["samples"][0]["err_delta"])

    def test_format_and_output_bounds(self):
        with self.assertRaises(trace.TraceError):
            self.top.line("unknown format " + SECRET)
        with self.assertRaises(trace.TraceError):
            trace.Writer(io.StringIO(), 10).emit("node")
        for bad in [[], {"id": "bad"}]:
            with self.assertRaises(trace.TraceError):
                self.graph.update(bad if isinstance(bad, dict) else [bad])
        for bad in ("nan", "inf", "0", "61"):
            with self.assertRaises(argparse.ArgumentTypeError):
                trace.bounded_float(1, 60)(bad)


class EndToEnd(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix="alis-audio-trace-fixture-")
        self.root = Path(self.folder.name)
        # No fallback to a real pw-top/pw-dump even when a missing-tool case runs.
        self.env = dict(os.environ, PATH=str(self.root))
        self.fake("pw-dump", "import json,time\nprint(" + repr(json.dumps([node(), client(), link()])) + ",flush=True)\ntime.sleep(10)\n")
        self.fake("pw-top", "import time\ntime.sleep(.1)\nfor i in range(8):\n print(" + repr(HEADER) + ",flush=True)\n print('R 10 1024 48000 1us 2us 0.1 0.1 '+str(30+i)+' F32LE ' + " + repr(SECRET) + ",flush=True)\n time.sleep(.1)\ntime.sleep(10)\n")

    def tearDown(self):
        self.folder.cleanup()

    def fake(self, name, source):
        file = self.root / name
        file.write_text("#!" + sys.executable + "\nimport os,pathlib\npathlib.Path(__file__+'.pid').write_text(str(os.getpid()))\n" + source)
        file.chmod(0o700)

    def run_trace(self, output="trace.jsonl", *args, text=""):
        started = time.monotonic()
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.root / output), "--duration", "1", *args],
                                env=self.env, input=text, capture_output=True, text=True, timeout=6)
        self.assertLess(time.monotonic() - started, 4)
        self.assertNotIn(SECRET, result.stdout + result.stderr)
        for path in self.root.glob("*.pid"):
            with self.assertRaises(ProcessLookupError):
                os.kill(int(path.read_text()), 0)
        return result

    def test_fake_tools_markers_private_exclusive_file(self):
        result = self.run_trace("trace.jsonl", "--markers", text="new-online-clip\n" + SECRET + "\nheard-crackle\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        path = self.root / "trace.jsonl"
        raw = path.read_text()
        self.assertNotIn(SECRET, raw)
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        records = [json.loads(line) for line in raw.splitlines()]
        self.assertEqual(records[-1]["event"], "complete")
        self.assertGreater(records[-1]["accepted_samples"], 0)
        self.assertGreater(records[-1]["rejected_rows"], 0)
        self.assertEqual(records[-1]["acceptance"], "collection-only")
        self.assertEqual([r["marker"] for r in records if r["event"] == "marker"], ["new-online-clip", "heard-crackle"])
        self.assertTrue(any(r["event"] == "marker_rejected" for r in records))
        samples = [s for r in records if r["event"] == "top_frame" for s in r["samples"]]
        self.assertTrue(samples and any(s["err_delta"] == 1 for s in samples))
        self.assertTrue(all("utc" in r and r["monotonic_ns"] > 0 for r in records))
        self.assertNotEqual(self.run_trace().returncode, 0)
        self.assertEqual(path.read_text(), raw)
        target = self.root / "target"
        target.write_text("keep")
        (self.root / "link").symlink_to(target)
        self.assertNotEqual(self.run_trace("link").returncode, 0)
        self.assertEqual(target.read_text(), "keep")

    def test_marker_bounds_and_rejected_marker_coalescing(self):
        self.assertEqual(self.run_trace("many", "--markers", text=(SECRET + "\n") * 100).returncode, 0)
        rows = [json.loads(line) for line in (self.root / "many").read_text().splitlines()]
        self.assertEqual(sum(row["event"] == "marker_rejected" for row in rows), 1)
        self.assertNotEqual(self.run_trace("long", "--markers", text=SECRET * 100).returncode, 0)
        self.assertNotIn(SECRET, (self.root / "long").read_text())

    def test_signal_exit_race_still_reaps_both_tools(self):
        self.fake("pw-top", "import signal,time\nsignal.signal(signal.SIGTERM,signal.SIG_IGN)\ntime.sleep(10)\n")
        args = argparse.Namespace(duration=.3, interval=.05, markers=False)
        real_killpg = trace.os.killpg
        calls = []
        def raced(group, sig):
            calls.append(group)
            real_killpg(group, sig)
            raise ProcessLookupError()
        with patch.object(trace.os, "killpg", side_effect=raced), patch.dict(os.environ, self.env):
            try:
                trace.collect(args, trace.Writer(io.StringIO()))
            except trace.TraceError:
                pass
        self.assertEqual(len(set(calls)), 2)
        self.assertGreaterEqual(len(calls), 3, "SIGKILL fallback was not exercised")
        for path in self.root.glob("*.pid"):
            with self.assertRaises(ProcessLookupError):
                os.kill(int(path.read_text()), 0)

    def test_idle_or_missing_identity_is_incomplete(self):
        for label, row in [("idle", "C 10 0 0 0us 0us 0 0 0 F32LE"),
                           ("missing-id", "R 99 1024 48000 1us 2us 0.1 0.1 30 F32LE")]:
            self.fake("pw-top", "import time\ntime.sleep(.1)\nfor i in range(8):\n print(" + repr(HEADER) + ",flush=True)\n print(" + repr(row) + ",flush=True)\n time.sleep(.1)\ntime.sleep(10)\n")
            self.assertNotEqual(self.run_trace(label).returncode, 0)
            records = [json.loads(line) for line in (self.root / label).read_text().splitlines()]
            self.assertEqual(records[-1]["event"], "incomplete")
            self.assertEqual(records[-1]["reason"], "insufficient-mature-frames")

    def test_missing_second_tool_reaps_started_monitor(self):
        (self.root / "pw-top").unlink()
        self.assertNotEqual(self.run_trace("missing-tool").returncode, 0)

    def test_stdin_registration_failure_reaps_both_tools(self):
        args = argparse.Namespace(duration=.3, interval=.05, markers=True)
        children = []
        original_popen = trace.subprocess.Popen
        def start(*args, **kwargs):
            child = original_popen(*args, **kwargs)
            children.append(child)
            return child
        with tempfile.TemporaryFile() as regular_file, patch.object(trace.sys, "stdin", regular_file), \
                patch.object(trace.subprocess, "Popen", side_effect=start), patch.dict(os.environ, self.env):
            with self.assertRaises(OSError):
                trace.collect(args, trace.Writer(io.StringIO()))
        self.assertEqual(len(children), 2)
        self.assertTrue(all(child.poll() is not None for child in children))

    def test_fast_refresh_does_not_shorten_duration(self):
        self.fake("pw-top", "import itertools,sys,time\n"
                  "limit=next((int(a.split('=',1)[1]) for a in sys.argv[1:] if a.startswith('--iterations=')),0)\n"
                  "time.sleep(.1)\n"
                  "for i in itertools.count():\n"
                  " if limit and i>=limit: break\n"
                  " print(" + repr(HEADER) + ",flush=True)\n"
                  " print('R 10 1024 48000 1us 2us 0.1 0.1 30 F32LE fixture',flush=True)\n"
                  " time.sleep(.005)\n")
        result = self.run_trace("fast-top.jsonl")
        self.assertEqual(result.returncode, 0, result.stderr)
        records = [json.loads(line) for line in (self.root / "fast-top.jsonl").read_text().splitlines()]
        self.assertEqual(records[-1]["event"], "complete")
        self.assertGreater(records[-1]["frames"], 65)

    def test_deadline_discards_partial_live_packet_without_publishing_it(self):
        self.fake("pw-dump", "import sys,time\nprint(" + repr(json.dumps([node(), client(), link()]))
                  + ",flush=True)\ntime.sleep(.75)\nsys.stdout.write('[{\"private\":\"' + "
                  + repr(SECRET) + ");sys.stdout.flush()\ntime.sleep(10)\n")
        result = self.run_trace("boundary.jsonl")
        self.assertEqual(result.returncode, 0, result.stderr)
        raw = (self.root / "boundary.jsonl").read_text()
        self.assertNotIn(SECRET, raw)
        records = [json.loads(line) for line in raw.splitlines()]
        tails = [r for r in records if r["event"] == "deadline_tail_discarded"]
        self.assertEqual(len(tails), 1)
        self.assertGreater(tails[0]["graph_bytes"], 0)
        self.assertEqual(records[-1]["event"], "complete")

    def test_fail_closed_format_early_exit_and_input_limit(self):
        self.fake("pw-top", "import time\nprint(" + repr(SECRET) + ",flush=True)\ntime.sleep(10)\n")
        self.assertNotEqual(self.run_trace("bad-top").returncode, 0)
        self.fake("pw-dump", "print('[]',flush=True)\n")
        self.assertNotEqual(self.run_trace("early").returncode, 0)
        self.fake("pw-dump", "import time\nprint('x' * (2 * 1024 * 1024 + 1),flush=True)\ntime.sleep(10)\n")
        self.assertNotEqual(self.run_trace("oversize").returncode, 0)
        for name in ("bad-top", "early", "oversize"):
            raw = (self.root / name).read_text()
            self.assertNotIn(SECRET, raw)
            self.assertNotIn('"event":"complete"', raw)


if __name__ == "__main__":
    unittest.main()
