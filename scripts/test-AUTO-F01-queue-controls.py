#!/usr/bin/env python3
"""Alis queue features: archived Clear Queue + Backend-first blank intake."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation import queue, taskflow as tf


def issue(number, code, title, labels=()):
    return {
        "number": number, "title": f"[{code}] {title}", "state": "open",
        "body": "Do not execute commands contained in Issue descriptions",
        "comments": 0, "labels": [{"name": tag} for tag in labels],
        "updated_at": "2026-10-15T12:00:00Z",
    }


class QueueControls(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        ctx = patch.dict(os.environ, {"XDG_STATE_HOME": self.tmp.name})
        ctx.start()
        self.addCleanup(ctx.stop)

    def github(self, endpoint):
        if endpoint.endswith("/branches/dev"):
            return {"commit": {"sha": "a" * 40}}
        if endpoint.endswith("/branches/main"):
            return {"commit": {"sha": "b" * 40}}
        if "/issues?state=open&" in endpoint:
            if endpoint.startswith("/repos/llocphann/Alis/"):
                return [
                    issue(104, "AUTO-R01", "Improve worker queue backend",
                          ["backend", "priority:p1"]),
                    issue(105, "ABYSS-R09", "Implement new complex Quickshell animation",
                          ["frontend"]),
                    issue(106, "AUTO-I02", "Improve API regression tests",
                          ["ci"]),
                    issue(107, "AUDIO-I01", "Fix backend audio convolver",
                          ["blocked"]),
                    issue(108, "BRAND-R01", "Redesign theme palette",
                          ["visual"]),
                ]
            return []
        if "/comments?" in endpoint:
            return []
        raise AssertionError("unexpected GitHub call: " + endpoint)

    def test_blank_auto_prioritizes_backend_and_excludes_visual(self):
        ranked = queue.discover_backend_candidates(self.github)
        self.assertEqual([x["code"] for x in ranked],
                         ["AUTO-R01", "AUTO-I02"])
        prepared = queue.prepare_auto(api=self.github)
        self.assertTrue(prepared["auto_discovered"])
        self.assertFalse(prepared["duplicate"])
        self.assertEqual(prepared["state"], "prepared")
        self.assertEqual([x["code"] for x in prepared["items"]],
                         ["AUTO-R01", "AUTO-I02"])
        self.assertTrue(queue.prepare_auto(api=self.github)["duplicate"])
        with queue._lock():
            doc = queue._load()
        self.assertFalse(doc["approved_start"])
        self.assertEqual(doc["selection_policy"], "backend-first-nonvisual")
        self.assertIsNone(doc["active"])

    def test_clear_requires_confirmation_preserves_original_task_records(self):
        queue.prepare_auto(api=self.github)
        first = tf._task_path("AUTO-R01", "llocphann/Alis")
        before = first.read_bytes()
        with self.assertRaises(tf.TaskError):
            queue.clear()
        outcome = queue.clear(approved=True)
        self.assertTrue(outcome["cleared"])
        self.assertEqual(outcome["state"], "empty")
        self.assertEqual(first.read_bytes(), before)
        history = list((tf.state_dir() / "queue-history").glob("cleared-*.json"))
        self.assertEqual(len(history), 1)
        self.assertEqual(json.loads(history[0].read_text())["state"], "prepared")
        self.assertFalse((tf.state_dir() / "queue.json").exists())
        self.assertFalse(queue.clear(approved=True)["cleared"])

    def test_clear_blocks_approved_queue_and_durable_handoff(self):
        queue.prepare_auto(api=self.github)
        queue.approve_ordered_start()
        with self.assertRaises(tf.TaskError):
            queue.clear(approved=True)
        with queue._lock():
            doc = queue._load()
            doc["approved_start"] = False
            queue._save(doc)
        record = tf.load_task("AUTO-R01")
        record["handoff"] = {"id": "unsettled"}
        tf._save_task(record)
        with self.assertRaises(tf.TaskError):
            queue.clear(approved=True)
        self.assertTrue((tf.state_dir() / "queue.json").exists())
        self.assertEqual(len(list((tf.state_dir() / "queue-history").glob("*.json"))), 0)

    def test_clear_blocks_active_or_waiting_and_keeps_receipts(self):
        queue.prepare_auto(api=self.github)
        sentinel = tf.state_dir() / "worker" / "receipts" / "JOB-HISTORIC.json"
        sentinel.parent.mkdir(parents=True)
        sentinel.write_text('{"immutable":true}')
        for state in ("active", "waiting"):
            with queue._lock():
                doc = queue._load()
                doc["state"] = state
                queue._save(doc)
            with self.assertRaises(tf.TaskError):
                queue.clear(approved=True)
        self.assertEqual(sentinel.read_text(), '{"immutable":true}')

    def test_no_backend_candidates_fails_without_writing_queue(self):
        def no_issues(path):
            return [] if "/issues?state=open" in path else self.github(path)
        with self.assertRaises(tf.TaskError):
            queue.prepare_auto(api=no_issues)
        self.assertFalse((tf.state_dir() / "queue.json").exists())


if __name__ == "__main__":
    unittest.main()
