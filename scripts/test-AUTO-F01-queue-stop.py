#!/usr/bin/env python3
"""Offline Stop Queue: revoke auto-scheduling; preserve local worker evidence."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation import queue, managed_tasks, taskflow as tf


class QueueStopTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        env = patch.dict(os.environ, {"XDG_STATE_HOME": self.temp.name})
        env.start()
        self.addCleanup(env.stop)
        active = {"code": "AUDIO-I01", "repository": "llocphann/Alis"}
        manifest = {
            "schema": queue.QUEUE_SCHEMA, "mode": "ordered",
            "state": "active", "active": dict(active),
            "selection": {"code": active["code"], "decision_id": None,
                          "selected_unix": 123},
            "approved_start": True, "created_unix": 123, "updated_unix": 123,
            "items": [
                {**active, "state": "active", "source_sha": "a" * 40,
                 "issue_number": 100},
                {"code": "MUSIC-I02", "repository": "llocphann/Alis",
                 "state": "queued", "source_sha": "a" * 40,
                 "issue_number": 101}
            ],
        }
        with queue._lock():
            queue._save(manifest)
        self.active = active
        self.identity = "llocphann/Alis:AUDIO-I01"
        self.owner = managed_tasks.profile_id(**{
            "repository": active["repository"], "code": active["code"]})
        self.state = {"profiles": {self.owner: {
            "desired": "run", "pending": {"delivery": "uncertain"},
            "job_id": "JOB-HISTORICAL", "session": {"inflight": True},
        }}}
        self.config = {"profiles": [{"id": self.owner}]}

    def test_stop_rejects_unapproved_or_stale_identity(self):
        before = queue.view()
        with self.assertRaises(tf.TaskError):
            queue.request_stop(expected_active=self.identity)
        with self.assertRaises(tf.TaskError):
            queue.request_stop(approved=True,
                               expected_active="llocphann/Alis:OTHER")
        self.assertEqual(queue.view(), before)

    def test_stop_preserves_ongoing_job_then_clear_archives_queue(self):
        def fake_action(action, profile_id):
            self.assertEqual((action, profile_id), ("stop", self.owner))
            self.state["profiles"][self.owner]["desired"] = "stopped"
            return {"ok": True}
        with patch.object(managed_tasks.store, "read_snapshot",
                          side_effect=lambda: (self.config, self.state, [])), \
             patch.object(managed_tasks.control, "profile_action",
                          side_effect=fake_action) as called:
            result = managed_tasks.stop_queue(
                approved=True, expected_active=self.identity)
        self.assertEqual(called.call_count, 1)
        self.assertTrue(result["stop_confirmed"])
        self.assertEqual(result["state"], "stopped")
        self.assertFalse(result["worker_cancelled"])
        self.assertEqual(self.state["profiles"][self.owner]["job_id"],
                         "JOB-HISTORICAL")
        self.assertEqual(self.state["profiles"][self.owner]["pending"],
                         {"delivery": "uncertain"})
        self.assertEqual(queue.view()["active"], self.active)
        cleared = queue.clear(
            approved=True, expected_queued="llocphann/Alis:MUSIC-I02")
        self.assertTrue(cleared["cleared"])
        self.assertEqual(cleared["state"], "empty")
        self.assertEqual(queue.view()["state"], "empty")
        archives = list((tf.state_dir() / "queue-history").glob("cleared-*.json"))
        self.assertEqual(len(archives), 1)
        previous = json.loads(archives[0].read_text())
        self.assertEqual(previous["state"], "stopped")
        self.assertEqual(previous["active"], self.active)
        self.assertEqual(previous["items"][0]["state"], "active")

    def test_stop_manager_failure_requires_reconciliation_not_fake_success(self):
        with patch.object(managed_tasks.store, "read_snapshot",
                          return_value=(self.config, self.state, [])), \
             patch.object(managed_tasks.control, "profile_action",
                          side_effect=RuntimeError("offline")) as called:
            result = managed_tasks.stop_queue(
                approved=True, expected_active=self.identity)
        self.assertEqual(called.call_count, 1)
        self.assertTrue(result["needs_reconciliation"])
        self.assertFalse(result["stop_confirmed"])
        self.assertEqual(queue.view()["state"], "stopping")
        # The orphaned manager leaves the ACTIVE item intact. The owner
        # can still remove ONLY queued siblings, never erase the uncertain
        # active job or claim it was stopped.
        result = queue.clear(
            approved=True, expected_queued="llocphann/Alis:MUSIC-I02")
        self.assertTrue(result["cleared"])
        self.assertEqual(result["state"], "stopping")
        self.assertEqual(result["removed_queued"], 1)
        self.assertTrue(result["active_preserved"])
        self.assertEqual(result["active"], self.active)
        self.assertEqual(self.state["profiles"][self.owner]["desired"], "run")
        with queue._lock():
            snapshot = queue._load()
        self.assertFalse(snapshot["approved_start"])
        self.assertEqual(len(snapshot["items"]), 1)
        self.assertEqual(snapshot["items"][0]["state"], "active")

    def test_orphaned_queue_is_stopped_without_lying_about_worker(self):
        # Queue source can survive a deleted/migrated profile. No native
        # profile exists to dispatch new steps, and approved_start has been
        # revoked. Do not deadlock cleanup forever waiting for absent owner.
        with patch.object(managed_tasks.store, "read_snapshot",
                          return_value=({"profiles": []}, {"profiles": {}}, [])), \
             patch.object(managed_tasks.control, "profile_action",
                          side_effect=AssertionError("cannot stop absent profile")):
            result = managed_tasks.stop_queue(
                approved=True, expected_active=self.identity)
        self.assertTrue(result["stop_confirmed"])
        self.assertFalse(result["profile_stop_confirmed"])
        self.assertFalse(result["worker_cancelled"])
        self.assertTrue(result["needs_reconciliation"])
        self.assertEqual(queue.view()["state"], "stopped")
        cleared = queue.clear(
            approved=True, expected_queued="llocphann/Alis:MUSIC-I02")
        self.assertTrue(cleared["cleared"])
        self.assertEqual(queue.view()["state"], "empty")
        archive = list((tf.state_dir() / "queue-history").glob("cleared-*.json"))
        self.assertEqual(len(archive), 1)
        self.assertEqual(json.loads(archive[0].read_text())["active"],
                         self.active)

    def test_stop_ui_and_credential_hooks_are_available(self):
        qml = (Path(__file__).resolve().parents[1] /
               "modules/settings/AutomationTaskConfig.qml").read_text()
        self.assertIn('objectName: "automationStopQueue"', qml)
        self.assertIn('"queue-stop", "--approve", "--expected-active", identity', qml)
        self.assertIn('["finished", "cancelled", "stopped", "review_required"]', qml)
        self.assertIn('objectName: "automationSudoSave"', qml)
        self.assertIn('objectName: "automationSudoClear"', qml)
        # Stop and archived-queue acknowledgments must remain visible after
        # the UI's immediate queue-status refresh (not silently reset to "").
        self.assertIn('result.state === "stopping"', qml)
        self.assertIn('result.state === "stopped"', qml)
        self.assertIn('Queue archived · task records and in-flight receipts preserved', qml)
        # Backend installation and verified ChatGPT submission are separate.
        # A healthy installed service must not turn into queue Start authority.
        self.assertIn('automatic ChatGPT submission not authorized', qml)
        self.assertIn('CHATGPT_PROJECT_SERVER_RECEIPT_UNATTESTED', qml)
        self.assertIn('root.backendTransportReady = report.transport_ready === true', qml)


if __name__ == "__main__":
    unittest.main()
