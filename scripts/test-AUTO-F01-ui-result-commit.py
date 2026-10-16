#!/usr/bin/env python3
"""Private offline replicas of Pause/Stop during UI completion and crash recovery."""
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import time
from types import SimpleNamespace
from unittest import TestCase, main
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation.chat_bridge import runtime, ui_scheduler
from automation.chat_bridge.send_journal import prepare_send, acknowledge_completed
from automation.manager import control, model, store

ID = model.DEFAULT_ID
KEY = "a" * 64
TEXT = "Only the current response completed.\nALIS_LOOP:CONTINUE"


class ResultCommitTests(TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        env = patch.dict(os.environ, {
            "XDG_CONFIG_HOME": self.tmp.name + "/config",
            "XDG_STATE_HOME": self.tmp.name + "/state",
            "ALIS_CHATGPT_PROJECT": model.DEFAULT_PROJECT,
        })
        env.start(); self.addCleanup(env.stop)
        def enable(c, s):
            c["profiles"][0]["enabled"] = True
            s["profiles"][ID].update(desired="run", request="new")
        store.change(enable)

    def item(self):
        return store.read_snapshot()[1]["profiles"][ID]

    def payload(self, prompt):
        return {"completed": True, "attestation": "local-ui-user-turn-v1",
                "prompt_sha256": hashlib.sha256(prompt.encode()).hexdigest(),
                "ui_target_key": KEY, "ui_chat_label": "Private test chat",
                "response": {"text": TEXT, "extractionSignal": "submitted-user-turn-assistant"}}

    def child(self, argv, **kwargs):
        control.profile_action(self.action, ID)
        return SimpleNamespace(returncode=0, stdout=json.dumps(self.payload(kwargs["input_text"])), stderr="")

    def test_pause_and_stop_accept_current_result_once_without_resuming(self):
        self.action = "pause"
        with patch.object(runtime, "run", side_effect=self.child) as called:
            self.assertEqual(ui_scheduler.ui_tick(ID, now=200), "CONTINUE")
        row = self.item()
        self.assertEqual(called.call_count, 1)
        self.assertEqual((row["desired"], row["status"]), ("paused", "paused"))
        self.assertEqual((row["prompts_sent"], row["iterations"]), (1, 1))
        self.assertIsNone(row["pending"])
        self.assertFalse((store.state_dir()/"ui-send-journal/pending.json").exists())
        with patch.object(runtime, "run") as called:
            self.assertEqual(ui_scheduler.ui_tick(ID), "idle")
            called.assert_not_called()

    def test_stop_during_result_remains_stopped(self):
        self.action = "stop"
        with patch.object(runtime, "run", side_effect=self.child):
            self.assertEqual(ui_scheduler.ui_tick(ID, now=200), "CONTINUE")
        row = self.item()
        self.assertEqual((row["desired"], row["status"]), ("stopped", "idle"))
        self.assertEqual(row["prompts_sent"], 1)
        self.assertFalse(row["run_active"])

    def test_distinct_continuations_have_unique_durable_full_input(self):
        prompts = []
        def ui(command, prompt, **kwargs):
            pending = self.item()["pending"]
            self.assertIn("Alis UI request token: " + pending["attempt_id"], prompt)
            self.assertEqual(hashlib.sha256(prompt.encode()).hexdigest(), pending["prompt_sha256"])
            prompts.append(prompt)
            return self.payload(prompt)
        for now in [200, 202, 204]:
            self.assertEqual(ui_scheduler.ui_tick(ID, now=now, desktop=ui), "CONTINUE")
        self.assertEqual(len(set(prompts)), 3)
        self.assertEqual(prompts[1].rsplit("\nAlis UI request token: ", 1)[0],
                         prompts[2].rsplit("\nAlis UI request token: ", 1)[0])

    def test_response_commit_precedes_retirement_and_cleanup_recovers_without_ui(self):
        self.action = "pause"
        def fail_after_commit(*args):
            self.assertIsNone(self.item()["pending"])
            self.assertEqual(self.item()["prompts_sent"], 1)
            raise OSError("simulated crash before journal retirement")
        with patch.object(runtime, "run", side_effect=self.child), \
                patch.object(runtime, "acknowledge_completed", side_effect=fail_after_commit):
            self.assertEqual(ui_scheduler.ui_tick(ID, now=200), "ui_reconciliation_required")
        with patch.object(runtime, "desktop", side_effect=AssertionError("No second UI operation")):
            self.assertEqual(ui_scheduler.reconcile_pending(ID), "ui_committed_journal_retired")
        self.assertEqual((self.item()["prompts_sent"], self.item()["iterations"]), (1, 1))
        self.assertEqual(self.item()["status"], "paused")
        self.assertFalse((store.state_dir()/"ui-send-journal/pending.json").exists())

    def test_changed_immutable_intent_never_retires_send_journal(self):
        def changed(argv, **kwargs):
            control.profile_action("pause", ID)
            store.change_state(lambda c, s: s["profiles"][ID]["pending"].update(prompt="foreign input"))
            return SimpleNamespace(returncode=0, stdout=json.dumps(self.payload(kwargs["input_text"])), stderr="")
        with patch.object(runtime, "run", side_effect=changed):
            self.assertEqual(ui_scheduler.ui_tick(ID, now=200), "owner_changed_after_response")
        self.assertEqual(self.item()["prompts_sent"], 0)
        self.assertTrue((store.state_dir()/"ui-send-journal/pending.json").exists())

    def test_committed_cleanup_rejects_foreign_journal_without_ui_or_recount(self):
        self.action = "pause"
        with patch.object(runtime, "run", side_effect=self.child), \
                patch.object(runtime, "acknowledge_completed", side_effect=OSError("interrupted cleanup")):
            self.assertEqual(ui_scheduler.ui_tick(ID, now=200), "ui_reconciliation_required")
        path = store.state_dir()/"ui-send-journal/pending.json"
        journal = json.loads(path.read_text()); journal["prompt_sha256"] = "b" * 64
        store._write(path, journal)
        with patch.object(runtime, "desktop") as ui:
            with self.assertRaisesRegex(RuntimeError, "COMMITTED_RECEIPT_MISMATCH"):
                ui_scheduler.reconcile_pending(ID)
            ui.assert_not_called()
        self.assertTrue(path.exists())
        self.assertEqual(self.item()["prompts_sent"], 1)

    def legacy_completed_but_pending(self):
        def old_runtime(command, prompt, **kwargs):
            path, attempt = prepare_send(store.state_dir(), command, prompt)
            control.profile_action("pause", ID)
            row = self.item()
            store._write(store.state_dir()/"ui-responses"/ID/(row["pending"]["attempt_id"]+".json"), {
                "transport": ui_scheduler.UI_TRANSPORT, "attempt_id": row["pending"]["attempt_id"],
                "directive": "CONTINUE", "response": TEXT, "at_unix": int(time.time())})
            acknowledge_completed(path, attempt)
            raise RuntimeError("legacy runtime retired before manager committed")
        self.assertEqual(ui_scheduler.ui_tick(ID, desktop=old_runtime), "ui_reconciliation_required")
        self.assertIsNotNone(self.item()["pending"])
        self.assertFalse((store.state_dir()/"ui-send-journal/pending.json").exists())

    def test_legacy_retired_result_requires_fresh_identical_original_without_resend(self):
        self.legacy_completed_but_pending()
        def observe(command, prompt, **kwargs):
            self.assertEqual(command, "observe-submitted")
            return self.payload(prompt)
        self.assertEqual(ui_scheduler.reconcile_pending(ID, observer=observe), "ui_reconciled_CONTINUE")
        self.assertEqual((self.item()["prompts_sent"], self.item()["iterations"]), (1, 1))
        self.assertEqual(self.item()["desired"], "paused")
        self.assertIsNone(self.item()["pending"])

    def test_retired_response_must_bind_exact_archived_journal_if_present(self):
        self.legacy_completed_but_pending()
        archive = store.state_dir() / "ui-send-journal" / "observed"
        record = json.loads(next(archive.glob("*.json")).read_text())
        pending = self.item()["pending"]
        response_path = (store.state_dir() / "ui-responses" / ID /
                         (pending["attempt_id"] + ".json"))
        response = json.loads(response_path.read_text())
        proper = {"id": record["id"], "command": record["command"],
                  "prompt_sha256": record["prompt_sha256"]}
        for invalid in (
            {"id": "66666666-7777-8888-9999-aaaaaaaaaaaa",
             "command": proper["command"], "prompt_sha256": proper["prompt_sha256"]},
            {**proper, "command": "rotate-send"},
            {**proper, "prompt_sha256": "f" * 64},
            {**proper, "untrusted_field": True},
            None,
        ):
            store._write(response_path, {**response, "ui_send_intent": invalid})
            with patch.object(runtime, "desktop") as ui:
                try:
                    result = ui_scheduler.reconcile_pending(ID)
                except RuntimeError as error:
                    self.assertIn("LEGACY_RESPONSE_MISMATCH", str(error),
                                  msg=repr(invalid))
                else:
                    self.fail("Unrejected retired intent " + repr(invalid)
                              + "; result=" + repr(result))
                ui.assert_not_called()
            self.assertEqual(self.item()["prompts_sent"], 0)
            self.assertIsNotNone(self.item()["pending"])
            self.assertFalse((store.state_dir() / "ui-send-journal" / "pending.json").exists())
        store._write(response_path, {**response, "ui_send_intent": proper})
        def observe(command, prompt, **kwargs):
            self.assertEqual(command, "observe-submitted")
            return self.payload(prompt)
        self.assertEqual(ui_scheduler.reconcile_pending(ID, observer=observe),
                         "ui_reconciled_CONTINUE")
        self.assertEqual(self.item()["prompts_sent"], 1)
        self.assertIsNone(self.item()["pending"])

    def test_legacy_changed_or_missing_response_cannot_infer_completion(self):
        self.legacy_completed_but_pending()
        def changed(command, prompt, **kwargs):
            p = self.payload(prompt); p["response"]["text"] += "\nDifferent reply"
            return p
        with self.assertRaisesRegex(RuntimeError, "LEGACY_RESPONSE_MISMATCH"):
            ui_scheduler.reconcile_pending(ID, observer=changed)
        self.assertEqual(self.item()["prompts_sent"], 0)
        response = store.state_dir()/"ui-responses"/ID/(self.item()["pending"]["attempt_id"]+".json")
        response.unlink()
        with patch.object(runtime, "desktop") as ui:
            with self.assertRaises(RuntimeError):
                ui_scheduler.reconcile_pending(ID)
            ui.assert_not_called()
        self.assertIsNotNone(self.item()["pending"])

    def test_legacy_duplicate_archived_intents_are_ambiguous(self):
        self.legacy_completed_but_pending()
        archive = store.state_dir()/"ui-send-journal/observed"
        first = json.loads(next(archive.glob("*.json")).read_text())
        first["id"] = "9877b330-2e84-487e-adfb-a5f565a4b578"
        store._write(archive/(first["id"]+".json"), first)
        with patch.object(runtime, "desktop") as ui:
            with self.assertRaises(RuntimeError):
                ui_scheduler.reconcile_pending(ID)
            ui.assert_not_called()
        self.assertEqual(self.item()["prompts_sent"], 0)


if __name__ == "__main__":
    main()
