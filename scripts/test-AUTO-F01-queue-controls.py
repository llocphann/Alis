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

    def test_active_clear_removes_only_queued_siblings_and_preserves_owner(self):
        queue.prepare_auto(api=self.github)
        queue.approve_ordered_start()
        selected = queue.claim(
            verified_start=lambda item, record, decision: True)["selected"]
        self.assertEqual(selected["code"], "AUTO-R01")
        original = (tf.state_dir() / "queue.json").read_bytes()
        first = tf._task_path("AUTO-R01", "llocphann/Alis")
        waiting = tf._task_path("AUTO-I02", "llocphann/Alis")
        before_active, before_waiting = first.read_bytes(), waiting.read_bytes()
        receipt = tf.state_dir() / "worker" / "receipts" / "JOB-UNRELATED.json"
        receipt.parent.mkdir(parents=True, exist_ok=True)
        receipt.write_text('{"immutable":true}')
        expected = "llocphann/Alis:AUTO-I02"
        with self.assertRaises(tf.TaskError):
            queue.clear(approved=True, expected_queued="llocphann/Alis:WRONG")
        self.assertEqual(original, (tf.state_dir() / "queue.json").read_bytes())
        cleared = queue.clear(approved=True, expected_queued=expected)
        self.assertTrue(cleared["cleared"])
        self.assertEqual(cleared["removed_queued"], 1)
        self.assertTrue(cleared["active_preserved"])
        self.assertEqual(cleared["state"], "active")
        self.assertEqual(cleared["active"], selected)
        self.assertEqual([(x["code"], x["state"]) for x in cleared["items"]],
                         [("AUTO-R01", "active")])
        self.assertEqual(first.read_bytes(), before_active)
        self.assertEqual(waiting.read_bytes(), before_waiting)
        self.assertEqual(receipt.read_text(), '{"immutable":true}')
        with queue._lock():
            after = queue._load()
        self.assertEqual(after["active"], selected)
        self.assertTrue(after["approved_start"])
        self.assertEqual(after["selection"]["code"], "AUTO-R01")
        self.assertIsNone(cleared["next"])
        archived = list((tf.state_dir() / "queue-history").glob("cleared-*.json"))
        self.assertEqual(len(archived), 1)
        self.assertEqual(json.loads(archived[0].read_bytes()),
                         json.loads(original))
        with self.assertRaises(tf.TaskError):
            queue.clear(approved=True, expected_queued=expected)
        self.assertFalse(queue.clear(approved=True, expected_queued="")["cleared"])

    def test_screenshot_case_one_active_seventeen_queued(self):
        # Regression for Settings: AUDIO-I01 active must survive clearing
        # MUSIC-I02, ABYSS-*, DASH-*, etc. No local machine job is touched.
        codes = [
            "MUSIC-I02", "ABYSS-R09", "ABYSS-R12", "DASH-R01",
            "OPT-R01", "AUDIO-R01", "ABYSS-R11", "ABYSS-R03",
            "OPT-R02", "DASH-R05", "NOTIF-I02", "VIS-R01",
            "AC-I01", "AC-I02", "AC-R02", "AC-R01", "AC-R03",
        ]
        active = {"code": "AUDIO-I01", "repository": "llocphann/Alis"}
        manifest = {
            "schema": queue.QUEUE_SCHEMA, "mode": "ordered",
            "state": "active", "active": dict(active),
            "selection": {"code": "AUDIO-I01", "decision_id": None,
                          "selected_unix": 12},
            "approved_start": True,
            "items": [{**active, "state": "active", "issue_number": 1,
                       "source_sha": "a" * 40}] + [
                {"code": code, "repository": "llocphann/Alis",
                 "issue_number": i + 2, "source_sha": "a" * 40,
                 "state": "queued"}
                for i, code in enumerate(codes)],
            "created_unix": 1, "updated_unix": 1,
        }
        with queue._lock():
            queue._save(manifest)
        expected = ";".join("llocphann/Alis:" + code for code in codes)
        before_active = dict(manifest["items"][0])
        result = queue.clear(approved=True, expected_queued=expected)
        self.assertEqual(result["removed_queued"], 17)
        self.assertEqual(result["state"], "active")
        self.assertEqual(result["items"], [{
            "code": "AUDIO-I01", "repository": "llocphann/Alis",
            "state": "active"}])
        with queue._lock():
            saved = queue._load()
        self.assertEqual(saved["items"], [before_active])
        self.assertEqual(saved["selection"], manifest["selection"])
        self.assertEqual(saved["active"], manifest["active"])
        self.assertEqual(saved["approved_start"], manifest["approved_start"])
        self.assertEqual(len(list((tf.state_dir() / "queue-history").glob(
            "cleared-*.json"))), 1)

        # The GUI is allowed to offer cleanup from a last-known snapshot.
        # It must still send all exact queued identities to the backend.
        qml = (Path(__file__).resolve().parents[1] /
               "modules/settings/AutomationTaskConfig.qml").read_text()
        button = qml.split('objectName: "automationClearQueue"')[1].split(
            "onClicked: root.clearQueue()", 1)[0]
        self.assertIn('Translation.tr("Clear")', button)
        self.assertIn('Translation.tr("Confirm clear")', button)
        self.assertIn('task.state === "queued"', button)
        self.assertNotIn("root.queueStatusConfirmed", button)
        self.assertIn('"--expected-queued", targets', qml)

    def test_queue_clear_matches_exact_snapshot_and_rejects_waiting_selector(self):
        queue.prepare_auto(api=self.github)
        live = "llocphann/Alis:AUTO-R01;llocphann/Alis:AUTO-I02"
        with self.assertRaises(tf.TaskError):
            queue.clear(approved=True, expected_queued="llocphann/Alis:AUTO-I02")
        with queue._lock():
            doc = queue._load()
            doc["state"] = "waiting"
            doc["approved_start"] = True
            queue._save(doc)
        with self.assertRaises(tf.TaskError):
            queue.clear(approved=True, expected_queued=live)
        self.assertEqual([x["state"] for x in queue.view()["items"]],
                         ["queued", "queued"])

    def test_no_backend_candidates_fails_without_writing_queue(self):
        def no_issues(path):
            return [] if "/issues?state=open" in path else self.github(path)
        with self.assertRaises(tf.TaskError):
            queue.prepare_auto(api=no_issues)
        self.assertFalse((tf.state_dir() / "queue.json").exists())


if __name__ == "__main__":
    unittest.main()
