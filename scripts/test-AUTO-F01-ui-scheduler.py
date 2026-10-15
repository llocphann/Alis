#!/usr/bin/env python3
"""Offline Alis UI/native exclusive scheduler regression; never opens Desktop."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import tempfile
from unittest import TestCase, main
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation.chat_bridge import ui_scheduler
from automation.manager import daemon, model, store

KEY = "a" * 64
OTHER_KEY = "b" * 64
ID = model.DEFAULT_ID


def prepared():
    def start(config, state):
        profile = config["profiles"][0]
        assert profile["id"] == ID
        profile["enabled"] = True
        profile["project_name"] = model.DEFAULT_PROJECT
        item = state["profiles"][ID]
        item["desired"] = "run"
        item["request"] = "new"
        item["next_run_at_unix"] = 0
    store.change(start)


def reply(marker: str, key: str = KEY) -> dict:
    return {"response": {"text": marker}, "ui_target_key": key}


class UiSchedulerTests(TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        env = patch.dict(os.environ, {
            "XDG_CONFIG_HOME": self.temp.name + "/config",
            "XDG_STATE_HOME": self.temp.name + "/state",
            "ALIS_CHATGPT_PROJECT": model.DEFAULT_PROJECT,
        })
        env.start()
        self.addCleanup(env.stop)
        prepared()

    def item(self):
        return store.read_snapshot()[1]["profiles"][ID]

    def test_initial_continuation_uses_same_chat_pin_and_done_stops(self):
        sent = []
        def ui(command, prompt, **kwargs):
            sent.append((command, kwargs.get("target_key")))
            self.assertIn("llocphann/Alis", prompt)
            return reply("ALIS_LOOP:CONTINUE" if len(sent) == 1
                         else "ALIS_LOOP:DONE")
        self.assertEqual(ui_scheduler.ui_tick(ID, now=200, desktop=ui),
                         "CONTINUE")
        self.assertEqual(self.item()["session"]["ui_target_key"], KEY)
        self.assertEqual(ui_scheduler.ui_tick(ID, now=202, desktop=ui), "DONE")
        self.assertEqual(sent, [("rotate-send", None), ("send", KEY)])
        self.assertIsNone(self.item()["pending"])
        self.assertEqual(self.item()["status"], "completed")
        self.assertEqual(self.item()["desired"], "stopped")
        self.assertEqual(ui_scheduler.ui_tick(ID, now=204, desktop=ui), "idle")
        self.assertEqual(len(sent), 2)

    def test_failed_send_keeps_private_pending_and_cannot_replay(self):
        count = [0]
        def uncertain(*_args, **_kw):
            count[0] += 1
            raise TimeoutError("UI ambiguous")
        self.assertEqual(ui_scheduler.ui_tick(ID, now=200, desktop=uncertain),
                         "ui_reconciliation_required")
        self.assertEqual(count[0], 1)
        item = self.item()
        self.assertEqual(item["status"], "ui_reconciliation_required")
        self.assertEqual(item["pending"]["transport"],
                         ui_scheduler.UI_TRANSPORT)
        self.assertEqual(item["desired"], "paused")
        self.assertEqual(ui_scheduler.ui_tick(ID, now=201, desktop=uncertain),
                         "ui_reconciliation_required")
        self.assertEqual(count[0], 1)

    def test_wrong_selected_chat_after_send_quarantines(self):
        self.assertEqual(ui_scheduler.ui_tick(
            ID, now=200, desktop=lambda *_a, **_k: reply(
                "ALIS_LOOP:CONTINUE")), "CONTINUE")
        self.assertEqual(ui_scheduler.ui_tick(
            ID, now=202, desktop=lambda *_a, **_k: reply(
                "ALIS_LOOP:CONTINUE", OTHER_KEY)),
            "ui_reconciliation_required")
        self.assertEqual(self.item()["desired"], "paused")
        self.assertIsNotNone(self.item()["pending"])

    def test_foreign_pending_profile_blocks_before_ui_attempt(self):
        def add(config, state):
            profile = model.new_profile("Other owner")
            config["profiles"].append(profile)
            state["profiles"][profile["id"]] = store.profile_state()
            state["profiles"][profile["id"]]["desired"] = "run"
        store.change(add)
        called = []
        self.assertEqual(ui_scheduler.ui_tick(
            ID, now=200, desktop=lambda *_a, **_k: called.append(1)),
            "ALIS_UI_ANOTHER_PROFILE_UNSETTLED")
        self.assertEqual(called, [])
        self.assertIsNone(self.item()["pending"])

    def test_wait_result_accepts_only_owned_settled_receipt(self):
        self.assertEqual(ui_scheduler.ui_tick(
            ID, now=200, desktop=lambda *_a, **_k: reply(
                "ALIS_LOOP:WAIT_RESULT JOB-UNIQUE")), "WAIT_RESULT")
        self.assertEqual(self.item()["job_id"], "JOB-UNIQUE")
        foreign = {"job": "JOB-UNIQUE", "profile_id": "other-profile",
                   "status": "passed", "input_sha256": "a" * 64,
                   "actions": []}
        with patch.object(daemon, "job_result", return_value=foreign):
            self.assertEqual(ui_scheduler.ui_tick(
                ID, now=202, desktop=lambda *_a, **_k: self.fail("send")),
                "ui_reconciliation_required")
        self.assertEqual(self.item()["job_id"], "JOB-UNIQUE")
        self.assertEqual(self.item()["desired"], "paused")

    def test_wait_result_stays_observational_then_uses_owned_receipt(self):
        self.assertEqual(ui_scheduler.ui_tick(
            ID, now=200, desktop=lambda *_a, **_k: reply(
                "ALIS_LOOP:WAIT_RESULT JOB-OWNED")), "WAIT_RESULT")
        owned = {"job": "JOB-OWNED", "profile_id": ID,
                 "status": "failed", "input_sha256": "a" * 64,
                 "actions": []}
        with patch.object(daemon, "job_result", return_value=None):
            self.assertEqual(ui_scheduler.ui_tick(ID, now=202),
                             "waiting_result")
        self.assertEqual(self.item()["job_id"], "JOB-OWNED")
        with patch.object(daemon, "job_result", return_value=owned):
            self.assertEqual(ui_scheduler.ui_tick(ID, now=215),
                             "waiting_result")
        self.assertIsNone(self.item()["job_id"])
        self.assertEqual(self.item()["last_job_id"], "JOB-OWNED")
        self.assertEqual(self.item()["last_result"], "failed")
        self.assertEqual(self.item()["request"], "continuation")

    def test_wrong_project_does_not_mutate_state(self):
        with patch.dict(os.environ, {"ALIS_CHATGPT_PROJECT": "Different"}):
            self.assertEqual(ui_scheduler.ui_tick(
                ID, now=200, desktop=lambda *_a, **_k: self.fail("send")),
                "ALIS_UI_PROJECT_CONFIG_MISMATCH")
        self.assertIsNone(self.item()["pending"])

    def test_native_transport_cannot_adopt_ui_session_or_pending(self):
        def prepare_ui(config, state):
            state["profiles"][ID]["session"] = {
                "transport": ui_scheduler.UI_TRANSPORT,
                "ui_target_key": KEY}
        store.change_state(prepare_ui)
        with patch.object(daemon, "native_command",
                          side_effect=AssertionError("native sent")):
            daemon._step_session(ID, 200)
        item = self.item()
        self.assertEqual(item["status"], "ui_transport_requires_review")
        self.assertEqual(item["desired"], "paused")
        self.assertEqual(item["session"]["ui_target_key"], KEY)

    def test_no_implicit_start_without_explicit_enabled_profile(self):
        store.change(lambda config, state:
            config["profiles"][0].update(enabled=False))
        self.assertEqual(ui_scheduler.ui_tick(
            ID, now=200, desktop=lambda *_a, **_k: self.fail("send")), "idle")


    def test_disabled_stopped_old_native_pending_is_preserved_during_new_ui_turn(self):
        original = {"user_message_id": "DO_NOT_REVEAL",
                    "prepared_at_unix": 1}
        def add_old(config, state):
            old = model.new_profile("Old native")
            old["enabled"] = False
            config["profiles"].append(old)
            item = store.profile_state()
            item.update(
                desired="stopped", status="stopping",
                pending=dict(original),
                session={"conversation_id": "OLD_PRIVATE_CONVERSATION"},
                run_active=True,
            )
            state["profiles"][old["id"]] = item
            return old["id"]
        legacy_id = store.change(add_old)
        calls = []
        result = ui_scheduler.ui_tick(
            ID, now=200,
            desktop=lambda *_args, **_kw: (
                calls.append("once") or reply("ALIS_LOOP:DONE")))
        self.assertEqual(result, "DONE")
        self.assertEqual(calls, ["once"])
        original_after = store.read_snapshot()[1]["profiles"][legacy_id]
        self.assertEqual(original_after["pending"], original)
        self.assertTrue(original_after["run_active"])
        self.assertEqual(original_after["session"]["conversation_id"],
                         "OLD_PRIVATE_CONVERSATION")
        self.assertEqual(original_after["desired"], "stopped")

    def test_disabled_pending_with_local_job_is_not_isolated(self):
        def add_old(config, state):
            old = model.new_profile("Old native")
            old["enabled"] = False
            config["profiles"].append(old)
            item = store.profile_state()
            item.update(
                desired="stopped", pending={"user_message_id": "old"},
                session={"conversation_id": "old"}, run_active=True,
                job_id="JOB-PENDING")
            state["profiles"][old["id"]] = item
        store.change(add_old)
        self.assertEqual(ui_scheduler.ui_tick(
            ID, now=200, desktop=lambda *_a, **_k: self.fail("send")),
            "ALIS_UI_ANOTHER_PROFILE_UNSETTLED")


if __name__ == "__main__":
    main()
