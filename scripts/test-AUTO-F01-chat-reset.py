#!/usr/bin/env python3
"""Owner-approved Automation chat reset: no job replay or altered queue."""
import copy
import os
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation import queue, taskflow as tf, managed_tasks
from automation.manager import store, model
from automation.chat_bridge import ui_scheduler

CODE = "AI-I01"
REPO = "llocphann/Alis"
IDENT = REPO + ":" + CODE
SOURCE_SHA = "a" * 40
UI_KEY = "b" * 64
NEW_KEY = "c" * 64
ATTEMPT = "11111111-1111-4111-8111-111111111111"

class ChatResetTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        ctx = patch.dict(os.environ, {
            "XDG_CONFIG_HOME": self.tmp.name + "/config",
            "XDG_STATE_HOME": self.tmp.name + "/state",
            "ALIS_CHATGPT_PROJECT": model.DEFAULT_PROJECT,
        })
        ctx.start()
        self.addCleanup(ctx.stop)
        self.pid = managed_tasks.profile_id(REPO, CODE)
        self.record = {"status": "prepared",
                       "unresolved": False, "rotation": None,
                       "task": {"base_sha": SOURCE_SHA,
                                "issue_url": "https://github.com/llocphann/Alis/issues/1"}}
        self.loader = patch.object(tf, "load_task", return_value=self.record)
        self.loader.start()
        self.addCleanup(self.loader.stop)
        profile = model.new_profile("Alis taskflow")
        profile.update(id=self.pid,
                       description="taskflow:" + IDENT,
                       enabled=True, project_name=model.DEFAULT_PROJECT)
        profile = model.validate_profile(profile)
        def setup(config, state):
            config["profiles"].append(profile)
            entry = store.profile_state()
            entry.update(desired="run", request="continuation",
                         status="continuing", run_active=True,
                         session={"transport": ui_scheduler.UI_TRANSPORT,
                                  "ui_target_key": UI_KEY,
                                  "project_name": model.DEFAULT_PROJECT},
                         last_ui_response_attempt=ATTEMPT,
                         last_success="CONTINUE")
            state["profiles"][self.pid] = entry
        store.change(setup)
        self.manifest = {
            "schema": queue.QUEUE_SCHEMA, "mode": "ordered",
            "state": "active", "active": {"code": CODE, "repository": REPO},
            "approved_start": True,
            "selection": {"code": CODE, "decision_id": None, "selected_unix": 1},
            "items": [
                {"code": CODE, "repository": REPO, "state": "active",
                 "source_sha": SOURCE_SHA, "issue_number": 1},
                {"code": "AI-I02", "repository": REPO, "state": "queued",
                 "source_sha": SOURCE_SHA, "issue_number": 2}
            ], "created_unix": 1, "updated_unix": 1
        }
        with queue._lock():
            queue._save(self.manifest)
        self.receipt_path = store.state_dir() / "ui-responses" / self.pid / (ATTEMPT + ".json")
        store._write(self.receipt_path, {
            "transport": ui_scheduler.UI_TRANSPORT,
            "attempt_id": ATTEMPT, "directive": "CONTINUE",
            "response": "ALIS_LOOP:CONTINUE",
        })

    def entry(self):
        return store.read_snapshot()[1]["profiles"][self.pid]

    def request(self, **kwargs):
        return managed_tasks.request_ui_chat_reset(
            expected_active=IDENT, approved=True, **kwargs)

    def test_owner_reset_dispatches_new_prompt_once_and_preserves_evidence(self):
        before_queue = queue.view()
        before_receipt = self.receipt_path.read_bytes()
        previous = copy.deepcopy(self.entry())
        result = self.request()
        self.assertEqual(result["state"], "reset_scheduled")
        self.assertFalse(result["new_message_sent"])
        self.assertEqual(queue.view(), before_queue)
        self.assertEqual(self.receipt_path.read_bytes(), before_receipt)
        self.assertEqual(self.entry()["request"], "manual_reset")
        self.assertEqual(self.entry()["session"], previous["session"])
        self.assertEqual(self.entry()["checkpoint"], previous["checkpoint"])
        with self.assertRaises(tf.TaskError):
            self.request()
        sent=[]
        def ui(command, prompt, **kwargs):
            sent.append((command, kwargs))
            self.assertIn("OWNER-APPROVED CHAT RESET", prompt)
            self.assertIn("AI-I01", prompt)
            self.assertEqual(kwargs.get("owner_chat_reset"), True)
            self.assertEqual(kwargs.get("new_chat_unowned"), True)
            self.assertIsNone(kwargs.get("target_key"))
            return {"response": {"text": "ALIS_LOOP:CONTINUE"},
                    "ui_target_key": NEW_KEY}
        self.assertEqual(ui_scheduler.ui_tick(
            self.pid, now=int(__import__("time").time()) + 2, desktop=ui),
            "CONTINUE")
        self.assertEqual(len(sent), 1)
        self.assertEqual(self.entry()["session"]["ui_target_key"], NEW_KEY)
        self.assertIsNone(self.entry()["pending"])
        self.assertEqual(self.entry()["last_ui_response_attempt"] != ATTEMPT, True)
        self.assertEqual(self.receipt_path.read_bytes(), before_receipt)
        self.assertEqual(queue.view(), before_queue)

    def test_pending_job_and_uncertain_receipts_block_reset(self):
        for field, value in [
            ("pending", {"transport": ui_scheduler.UI_TRANSPORT}),
            ("job_id", "JOB-UNSETTLED"),
            ("session", None),
            ("desired", "paused"),
            ("request", "rotation"),
        ]:
            original = self.entry()
            store.change_state(lambda c,s: s["profiles"][self.pid].update({field: value}))
            before = self.entry()
            with self.assertRaises(tf.TaskError):
                self.request()
            self.assertEqual(self.entry(), before)
            store.change_state(lambda c,s: s["profiles"][self.pid].update({field: original[field]}))
        self.receipt_path.unlink()
        with self.assertRaises(tf.TaskError):
            self.request()

    def test_awaiting_owner_or_mismatched_receipt_never_resets(self):
        self.record["status"] = "awaiting_owner"
        before = self.entry()
        with self.assertRaises(tf.TaskError):
            self.request()
        self.assertEqual(self.entry(), before)
        self.record["status"] = "prepared"
        store._write(self.receipt_path, {
            "transport": ui_scheduler.UI_TRANSPORT,
            "attempt_id": ATTEMPT,
            "directive": "WAIT_RESULT", "response": "ALIS_LOOP:WAIT_RESULT JOB-OLD"})
        with self.assertRaises(tf.TaskError):
            self.request()
        self.assertEqual(self.entry(), before)

    def test_stale_queue_identity_or_no_approval_does_not_mutate(self):
        before = self.entry()
        with self.assertRaises(tf.TaskError):
            managed_tasks.request_ui_chat_reset(expected_active=IDENT)
        with self.assertRaises(tf.TaskError):
            managed_tasks.request_ui_chat_reset(
                approved=True, expected_active=REPO + ":AI-I02")
        self.assertEqual(self.entry(), before)
        with queue._lock():
            q = queue._load()
            q["state"] = "stopping"
            queue._save(q)
        with self.assertRaises(tf.TaskError):
            self.request()
        self.assertEqual(self.entry(), before)

if __name__ == "__main__":
    unittest.main()
