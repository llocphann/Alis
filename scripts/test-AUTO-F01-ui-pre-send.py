#!/usr/bin/env python3
"""Offline typed pre-Send failure receipts; no Desktop, services or owner state."""
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
from unittest import TestCase, main
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation.chat_bridge import runtime, ui_scheduler
from automation.chat_bridge.send_journal import prepare_send, acknowledge_not_sent
from automation.manager import model, store


class PreSendTests(TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        env = patch.dict(os.environ, {
            "XDG_CONFIG_HOME": self.tmp.name + "/config",
            "XDG_STATE_HOME": self.tmp.name + "/state",
            "ALIS_CHATGPT_PROJECT": model.DEFAULT_PROJECT,
        })
        env.start(); self.addCleanup(env.stop)

    def response(self, prompt, kwargs, **changes):
        return {"schema": "alis.ui-dispatch-failure.v1",
                "attempt_id": kwargs["extra_env"]["ALIS_UI_ATTEMPT_ID"],
                "prompt_sha256": hashlib.sha256(prompt.encode()).hexdigest(),
                "send_attempted": False, "code": "ALIS_UI_GITHUB_PICKER_UNAVAILABLE",
                **changes}

    def test_exact_child_receipt_archives_unsent_without_delivery(self):
        def child(_argv, **kwargs):
            return SimpleNamespace(returncode=1, stderr="",
                stdout=json.dumps(self.response(kwargs["input_text"], kwargs)))
        with patch.object(runtime, "run", side_effect=child) as called:
            with self.assertRaises(runtime.UiNotSent):
                runtime.desktop("send", "private owner task")
        self.assertEqual(called.call_count, 1)
        journal = runtime.state_root() / "ui-send-journal"
        self.assertFalse((journal / "pending.json").exists())
        records = list((journal / "not-sent").glob("*.json"))
        self.assertEqual(len(records), 1)
        saved = json.loads(records[0].read_text())
        self.assertEqual(saved["outcome"], "not_sent")
        self.assertIs(saved["delivery_acknowledged"], False)
        self.assertNotIn("private owner task", records[0].read_text())
        self.assertFalse((journal / "observed").exists())

    def test_invalid_window_pin_cannot_prepare_or_invoke_ui(self):
        surface = runtime.state_root() / "ui-window.json"
        for value in ["not json", "[]", "null", '{}', json.dumps({
                "schema": "alis.ui-window.v1", "target_id": "a" * 32 + "\n"})]:
            surface.write_text(value)
            with patch.object(runtime, "run") as child:
                with self.assertRaises(runtime.UiNotSent):
                    runtime.desktop("send", "private owner task")
                child.assert_not_called()
                self.assertFalse((runtime.state_root() / "ui-send-journal/pending.json").exists())

    def test_window_pin_is_passed_to_child_with_attempt_identity(self):
        (runtime.state_root() / "ui-window.json").write_text(json.dumps({
            "schema": "alis.ui-window.v1", "target_id": "b" * 32}))
        def child(_argv, **kwargs):
            self.assertEqual(kwargs["extra_env"]["ALIS_CHATGPT_UI_TARGET_ID"], "b" * 32)
            return SimpleNamespace(returncode=1, stderr="", stdout=json.dumps(
                self.response(kwargs["input_text"], kwargs)))
        with patch.object(runtime, "run", side_effect=child):
            with self.assertRaises(runtime.UiNotSent):
                runtime.desktop("send", "owner task")

    def test_wrong_or_uncertain_receipt_keeps_no_replay_intent(self):
        cases = [{"attempt_id": "other"}, {"prompt_sha256": "0" * 64},
                 {"send_attempted": True}, {"send_attempted": "false"},
                 {"extra": "untrusted"}, {"code": "unknown"}, {"code": {}}]
        for index, changes in enumerate(cases):
            with self.subTest(changes=changes), patch.dict(os.environ, {
                    "XDG_STATE_HOME": self.tmp.name + "/bad-" + str(index)}):
                def child(_argv, **kwargs):
                    return SimpleNamespace(returncode=1, stderr="",
                        stdout=json.dumps(self.response(kwargs["input_text"], kwargs, **changes)))
                with patch.object(runtime, "run", side_effect=child) as called:
                    with self.assertRaises(RuntimeError) as error:
                        runtime.desktop("send", "same task")
                    self.assertNotIsInstance(error.exception, runtime.UiNotSent)
                    with self.assertRaisesRegex(RuntimeError, "RECONCILIATION_REQUIRED"):
                        runtime.desktop("send", "same task")
                    self.assertEqual(called.call_count, 1)
                self.assertTrue((runtime.state_root() / "ui-send-journal/pending.json").exists())

    def test_owner_reconciliation_requires_exact_attempt_hash_and_evidence(self):
        pending, attempt = prepare_send(runtime.state_root(), "send", "own draft")
        digest = hashlib.sha256(b"own draft").hexdigest()
        for identity, sha, evidence in [("other", digest, "owner-confirmed-not-sent"),
                (attempt, "0" * 64, "owner-confirmed-not-sent"),
                (attempt, digest, "inferred-from-missing-response")]:
            with self.assertRaises((RuntimeError, ValueError)):
                acknowledge_not_sent(pending, identity, sha, evidence=evidence)
            self.assertTrue(pending.exists())
        acknowledge_not_sent(pending, attempt, digest, evidence="owner-confirmed-not-sent")
        self.assertFalse(pending.exists())
        saved = json.loads((pending.parent / "not-sent" / (attempt + ".json")).read_text())
        self.assertEqual(saved["evidence"], "owner-confirmed-not-sent")
        self.assertIs(saved["delivery_acknowledged"], False)

    def test_bounded_auto_retry_only_proven_pre_send_failure(self):
        def enable(config, state):
            config["profiles"][0]["enabled"] = True
            state["profiles"][model.DEFAULT_ID].update(desired="run", request="new")
        store.change(enable)
        attempted = []
        def failed(_command, prompt, **kwargs):
            attempted.append(_command)
            raise runtime.UiNotSent("ALIS_UI_GITHUB_PICKER_UNAVAILABLE",
                                    hashlib.sha256(prompt.encode()).hexdigest())
        now = 1000
        self.assertEqual(ui_scheduler.ui_tick(model.DEFAULT_ID, now=now, desktop=failed),
                         "ui_retry_wait")
        item = store.read_snapshot()[1]["profiles"][model.DEFAULT_ID]
        self.assertIsNone(item["pending"])
        self.assertEqual(item["desired"], "run")
        self.assertEqual(item["ui_pre_send_failures"], 1)
        self.assertEqual(item["next_run_at_unix"], 1005)
        self.assertEqual(item["prompts_sent"], 0)
        self.assertEqual(item["iterations"], 0)
        self.assertEqual(ui_scheduler.ui_tick(model.DEFAULT_ID, now=1004,
                                             desktop=failed), "scheduled")
        self.assertEqual(len(attempted), 1)
        self.assertEqual(ui_scheduler.ui_tick(model.DEFAULT_ID, now=1005,
                                             desktop=failed), "ui_retry_wait")
        self.assertEqual(store.read_snapshot()[1]["profiles"][model.DEFAULT_ID]
                         ["next_run_at_unix"], 1020)
        self.assertEqual(ui_scheduler.ui_tick(model.DEFAULT_ID, now=1019,
                                             desktop=failed), "scheduled")
        self.assertEqual(ui_scheduler.ui_tick(model.DEFAULT_ID, now=1020,
                                             desktop=failed), "ui_composition_failed")
        item = store.read_snapshot()[1]["profiles"][model.DEFAULT_ID]
        self.assertEqual(item["desired"], "paused")
        self.assertEqual(item["ui_pre_send_failures"], 3)
        self.assertEqual(item["prompts_sent"], 0)
        self.assertEqual(item["iterations"], 0)
        self.assertEqual(len(attempted), 3)
        self.assertEqual(ui_scheduler.ui_tick(model.DEFAULT_ID, desktop=failed), "idle")

    def test_pending_send_journal_disables_automatic_retry(self):
        def enable(config,state):
            config["profiles"][0]["enabled"] = True
            state["profiles"][model.DEFAULT_ID].update(desired="run", request="new")
        store.change(enable)
        journal = store.state_dir() / "ui-send-journal" / "pending.json"
        journal.parent.mkdir(parents=True, exist_ok=True)
        journal.write_text('{"schema":"alis.chat-ui-send.v1"}')
        def failed(_command,prompt,**kwargs):
            raise runtime.UiNotSent("ALIS_UI_PRE_SEND_FAILED",
                                    hashlib.sha256(prompt.encode()).hexdigest())
        self.assertEqual(ui_scheduler.ui_tick(model.DEFAULT_ID,
                         now=3000, desktop=failed), "ALIS_UI_SEND_UNCERTAIN_RECONCILIATION_REQUIRED")
        self.assertEqual(store.read_snapshot()[1]["profiles"]
                         [model.DEFAULT_ID]["prompts_sent"], 0)
        self.assertTrue(journal.exists())


if __name__ == "__main__":
    main()
