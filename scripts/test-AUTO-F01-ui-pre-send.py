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

    def test_scheduler_pauses_unsent_with_no_success_or_delivery_counter(self):
        def enable(config, state):
            config["profiles"][0]["enabled"] = True
            state["profiles"][model.DEFAULT_ID].update(desired="run", request="new")
        store.change(enable)
        def failed(_command, prompt, **kwargs):
            raise runtime.UiNotSent("ALIS_UI_GITHUB_PICKER_UNAVAILABLE",
                                    hashlib.sha256(prompt.encode()).hexdigest())
        self.assertEqual(ui_scheduler.ui_tick(model.DEFAULT_ID, desktop=failed), "ui_composition_failed")
        item = store.read_snapshot()[1]["profiles"][model.DEFAULT_ID]
        self.assertIsNone(item["pending"])
        self.assertEqual(item["desired"], "paused")
        self.assertEqual(item["prompts_sent"], 0)
        self.assertEqual(item["iterations"], 0)
        self.assertEqual(ui_scheduler.ui_tick(model.DEFAULT_ID, desktop=failed), "idle")


if __name__ == "__main__":
    main()
