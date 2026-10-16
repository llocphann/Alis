#!/usr/bin/env python3
"""Offline exact original-delivery recovery; no live Desktop or worker."""
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation.chat_bridge import runtime, ui_scheduler, send_journal
from automation.manager import store, model
from automation import queue

ID = model.DEFAULT_ID
KEY = "a" * 64


class InterruptedTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        env = patch.dict(os.environ, {"XDG_STATE_HOME": self.temp.name + "/state",
            "XDG_CONFIG_HOME": self.temp.name + "/config", "ALIS_CHATGPT_PROJECT": model.DEFAULT_PROJECT})
        env.start(); self.addCleanup(env.stop)
        def enable(c, s):
            c["profiles"][0]["enabled"] = True
            s["profiles"][ID].update(desired="run", request="new")
        store.change(enable)
        def uncertain(command, prompt, **kwargs):
            send_journal.prepare_send(store.state_dir(), command, prompt)
            raise RuntimeError("interrupted after original Send")
        self.assertEqual(ui_scheduler.ui_tick(ID, desktop=uncertain), "ui_reconciliation_required")
        def stopped(c, s):
            s["profiles"][ID].update(desired="stopped", run_active=False,
                session={"transport": ui_scheduler.UI_TRANSPORT, "ui_target_key": KEY})
        store.change_state(stopped)
        self.journal = store.state_dir() / "ui-send-journal/pending.json"
        self.queue = queue._queue_path()
        self.queue.parent.mkdir(parents=True, exist_ok=True)
        self.queue.write_text('{"new_queue":"must remain unchanged"}\n')

    def item(self):
        return store.read_snapshot()[1]["profiles"][ID]

    def observed(self, command, prompt, **kwargs):
        self.assertEqual(command, "observe-submitted")
        self.assertEqual(kwargs["target_key"], KEY)
        return {"completed": False, "delivery_observed": True, "idle_observed": True,
            "attestation": "local-ui-user-turn-v1", "prompt_sha256": hashlib.sha256(prompt.encode()).hexdigest(),
            "ui_target_key": KEY, "response": {"text": "Partial source report; no completion accepted.",
                "markerCount": 0, "extractionSignal": "submitted-user-turn-assistant"}}

    def test_observed_interruption_is_delivery_not_success_and_never_advances_queue(self):
        original = self.queue.read_bytes()
        self.assertEqual(ui_scheduler.reconcile_interrupted_pending(ID, approved=True,
            observer=self.observed), "ui_interrupted_delivered")
        item = self.item()
        self.assertIsNone(item["pending"])
        self.assertEqual(item["desired"], "stopped")
        self.assertEqual(item["prompts_sent"], 1)
        self.assertEqual(item["iterations"], 0)
        self.assertEqual(item["last_success"], "")
        self.assertEqual(self.queue.read_bytes(), original)
        saved = list((self.journal.parent / "interrupted").glob("*.json"))
        self.assertEqual(len(saved), 1)
        record = json.loads(saved[0].read_text())
        self.assertTrue(record["delivery_acknowledged"])
        self.assertFalse(record["completion_acknowledged"])
        self.assertNotIn("Partial source report", saved[0].read_text())
        self.assertFalse(self.journal.exists())

    def test_approval_and_explicit_stopped_state_required(self):
        with self.assertRaises(RuntimeError):
            ui_scheduler.reconcile_interrupted_pending(ID, observer=self.observed)
        store.change_state(lambda c, s: s["profiles"][ID].update(desired="paused"))
        with self.assertRaises(RuntimeError):
            ui_scheduler.reconcile_interrupted_pending(ID, approved=True, observer=self.observed)
        self.assertTrue(self.journal.exists())

    def test_ambiguous_or_complete_receipts_cannot_clear_original(self):
        for field, value in [("completed", True), ("delivery_observed", False),
                ("idle_observed", False), ("prompt_sha256", "0" * 64),
                ("ui_target_key", "b" * 64), ("attestation", "native")]:
            with self.subTest(field=field):
                def wrong(*args, **kwargs):
                    return {**self.observed(*args, **kwargs), field: value}
                with self.assertRaises(RuntimeError):
                    ui_scheduler.reconcile_interrupted_pending(ID, approved=True, observer=wrong)
                self.assertTrue(self.journal.exists())
                self.assertIsNotNone(self.item()["pending"])
                self.assertEqual(self.item()["prompts_sent"], 0)

    def test_interrupted_cleanup_recovers_without_observation_or_double_count(self):
        with patch.object(send_journal, "acknowledge_interrupted", side_effect=RuntimeError("power loss")):
            with self.assertRaises(RuntimeError):
                ui_scheduler.reconcile_interrupted_pending(ID, approved=True, observer=self.observed)
        self.assertIsNone(self.item()["pending"])
        self.assertTrue(self.journal.exists())
        for _ in range(2):
            self.assertEqual(ui_scheduler.reconcile_interrupted_pending(ID, approved=True,
                observer=lambda *_a, **_k: self.fail("must not observe/send again")),
                "ui_interrupted_already_recorded")
        self.assertEqual(self.item()["prompts_sent"], 1)
        self.assertEqual(self.item()["iterations"], 0)
        self.assertFalse(self.journal.exists())

    def test_malformed_journal_identity_rejected_before_state_retirement(self):
        record = json.loads(self.journal.read_text()); record["id"] = "bad"
        self.journal.write_text(json.dumps(record))
        with self.assertRaises((RuntimeError, ValueError)):
            ui_scheduler.reconcile_interrupted_pending(ID, approved=True, observer=self.observed)
        self.assertIsNotNone(self.item()["pending"])
        self.assertEqual(self.item()["prompts_sent"], 0)


if __name__ == "__main__":
    unittest.main()
