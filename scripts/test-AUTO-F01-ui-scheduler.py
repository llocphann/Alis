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
from automation.chat_bridge import ui_scheduler, runtime
from automation.manager import daemon, model, store
from automation import queue, managed_tasks, taskflow as tf
import json

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

    def uncertain_original(self):
        def sent(_command, prompt, **_kwargs):
            from automation.chat_bridge.send_journal import prepare_send
            prepare_send(store.state_dir(), "rotate-send", prompt)
            raise RuntimeError("crashed after single Send")
        self.assertEqual(ui_scheduler.ui_tick(ID, desktop=sent), "ui_reconciliation_required")

    def observed_original(self, _command, prompt, **_kwargs):
        import hashlib
        self.assertEqual(_command, "observe-submitted")
        return {"completed": True, "attestation": "local-ui-user-turn-v1",
                "prompt_sha256": hashlib.sha256(prompt.encode()).hexdigest(),
                "ui_target_key": KEY, "ui_chat_label": "Observed test chat",
                "response": {"text": "Source milestone only.\nALIS_LOOP:CONTINUE",
                             "extractionSignal": "submitted-user-turn-assistant"}}

    def test_reconcile_original_never_resends_or_resumes_and_counts_once(self):
        self.uncertain_original()
        self.assertEqual(ui_scheduler.reconcile_pending(ID, observer=self.observed_original),
                         "ui_reconciled_CONTINUE")
        item = self.item()
        self.assertEqual(item["desired"], "paused")
        self.assertIsNone(item["pending"])
        self.assertEqual(item["prompts_sent"], 1)
        self.assertEqual(item["session"]["ui_target_key"], KEY)
        self.assertFalse((store.state_dir() / "ui-send-journal/pending.json").exists())
        with self.assertRaises(RuntimeError):
            ui_scheduler.reconcile_pending(ID, observer=self.observed_original)
        self.assertEqual(self.item()["prompts_sent"], 1)

    def test_reconcile_changed_config_uses_durable_original_input(self):
        self.uncertain_original()
        original = self.item()["pending"]["prompt"]
        store.change(lambda c, s: c["profiles"][0].update(prompt="changed owner prompt"))
        def observed(command, prompt, **kwargs):
            self.assertEqual(prompt, original)
            return self.observed_original(command, prompt, **kwargs)
        self.assertEqual(ui_scheduler.reconcile_pending(ID, observer=observed), "ui_reconciled_CONTINUE")

    def test_reconcile_tampered_input_preserves_original_journal(self):
        self.uncertain_original()
        store.change_state(lambda c, s: s["profiles"][ID]["pending"].update(prompt="changed input"))
        with self.assertRaises(RuntimeError), patch.object(runtime, "desktop") as observed:
            ui_scheduler.reconcile_pending(ID)
        observed.assert_not_called()
        self.assertTrue((store.state_dir() / "ui-send-journal/pending.json").exists())

    def test_reconcile_wrong_receipt_preserves_original_pending(self):
        self.uncertain_original()
        original = self.item()["pending"]
        for field, value in [("attestation", "native"), ("prompt_sha256", "0" * 64),
                             ("ui_target_key", "title")]:
            def wrong(*args, **kwargs):
                return {**self.observed_original(*args, **kwargs), field: value}
            with self.assertRaises(RuntimeError):
                ui_scheduler.reconcile_pending(ID, observer=wrong)
            self.assertEqual(self.item()["pending"], original)
            self.assertEqual(self.item()["prompts_sent"], 0)

    def test_reconcile_in_progress_retains_intent(self):
        self.uncertain_original()
        self.assertEqual(ui_scheduler.reconcile_pending(ID, observer=lambda *_a, **_kw:
                         {"completed": False}), "original_turn_in_progress")
        self.assertIsNotNone(self.item()["pending"])
        self.assertTrue((store.state_dir() / "ui-send-journal/pending.json").exists())

    def test_reconcile_excludes_another_live_manager(self):
        import fcntl
        self.uncertain_original()
        with runtime.lock_path().open("a+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertEqual(ui_scheduler.reconcile_pending(ID), "manager_busy")
        self.assertIsNotNone(self.item()["pending"])

    def test_initial_continuation_uses_same_chat_pin_and_done_stops(self):
        sent = []
        def ui(command, prompt, **kwargs):
            sent.append((command, kwargs.get("target_key")))
            if len(sent) == 1:
                self.assertIs(kwargs.get("new_chat_unowned"), True)
            else:
                self.assertFalse(kwargs.get("new_chat_unowned", False))
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

    def test_stalled_job_recovers_by_polling_same_id_after_restart(self):
        self.assertEqual(ui_scheduler.ui_tick(
            ID, now=1000, desktop=lambda *_a, **_k: reply(
                "ALIS_LOOP:WAIT_RESULT JOB-UNCHANGED")), "WAIT_RESULT")
        self.assertEqual(self.item()["job_id"], "JOB-UNCHANGED")
        # State is persisted across repeated manager ticks; missing receipt
        # never triggers a second worker submission or another ChatGPT send.
        with patch.object(daemon, "job_result", return_value=None):
            self.assertEqual(ui_scheduler.ui_tick(ID, now=1185,
                    desktop=lambda *_a, **_k: self.fail("no send")),
                    "waiting_result")
        current = self.item()
        self.assertEqual(current["job_id"], "JOB-UNCHANGED")
        self.assertEqual(current["status"], "waiting_result_stalled")
        self.assertEqual(current["next_job_poll_at_unix"], 1225)
        with patch.object(daemon, "job_result", return_value=None):
            self.assertEqual(ui_scheduler.ui_tick(ID, now=1224,
                    desktop=lambda *_a, **_k: self.fail("no send")),
                    "waiting_result")
        self.assertEqual(self.item()["job_id"], "JOB-UNCHANGED")
        owned = {"job": "JOB-UNCHANGED", "profile_id": ID,
                 "status": "passed", "input_sha256": "a" * 64,
                 "actions": []}
        with patch.object(daemon, "job_result", return_value=owned):
            self.assertEqual(ui_scheduler.ui_tick(ID, now=1225,
                    desktop=lambda *_a, **_k: self.fail("no send")),
                    "waiting_result")
        self.assertIsNone(self.item()["job_id"])
        self.assertEqual(self.item()["last_job_id"], "JOB-UNCHANGED")
        self.assertEqual(self.item()["last_result"], "passed")

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


    def _queue_fixture(self, *, state="prepared", approved=False,
                       source_sha="a" * 40):
        pid = managed_tasks.profile_id("llocphann/Alis", "AI-I01")
        def register(config, runtime):
            owner = model.new_profile("AI-I01")
            owner.update(
                id=pid, name="AI-I01",
                description="taskflow:llocphann/Alis:AI-I01",
                enabled=True, project_name=model.DEFAULT_PROJECT)
            config["profiles"].append(owner)
            item = store.profile_state()
            item.update(desired="run", request="new")
            runtime["profiles"][pid] = item
            # The standalone default generic profile should never send.
            config["profiles"][0]["enabled"] = False
            runtime["profiles"][ID].update(desired="stopped")
        store.change(register)
        manifest = {
            "schema": queue.QUEUE_SCHEMA, "mode": "ordered",
            "state": state, "approved_start": approved,
            "active": {"repository": "llocphann/Alis", "code": "AI-I01"}
                if state == "active" else None,
            "items": [{
                "repository": "llocphann/Alis", "code": "AI-I01",
                "source_sha": source_sha,
                "state": "active" if state == "active" else "queued",
            }],
        }
        with queue._lock():
            queue._save(manifest)
        record = {
            "status": "prepared", "unresolved": False,
            "task": {"base_sha": "a" * 40, "issue_url": "https://github.com/llocphann/Alis/issues/1"},
            "cloud_prompt": "Implement task AI-I01 on dev safely",
        }
        return pid, record

    def test_queue_mode_never_starts_prepared_queue(self):
        _, task = self._queue_fixture()
        before = queue.view()
        with patch.object(tf, "load_task", return_value=task):
            result = ui_scheduler.queue_tick(
                now=200, desktop=lambda *_a, **_k: self.fail("send"))
        self.assertEqual(result, "queue_idle")
        self.assertEqual(queue.view(), before)

    def test_ui_followup_requires_authentic_local_receipt(self):
        from automation import lifecycle
        _, task = self._queue_fixture(state="active", approved=True)
        task["status"] = "awaiting_cloud_ack"
        with patch.object(tf, "load_task", return_value=task):
            self.assertEqual(ui_scheduler.queue_tick(desktop=lambda *_a, **_k: self.fail("send")),
                             "ALIS_UI_QUEUE_LOCAL_RECEIPT_REQUIRES_REVIEW")
            with patch.object(lifecycle, "_verified_local_receipt", return_value={}) as gate:
                self.assertEqual(ui_scheduler.queue_tick(desktop=lambda *_a, **_k: reply("ALIS_LOOP:DONE")), "DONE")
                gate.assert_called_once_with(task)
            with self.assertRaises(tf.TaskError):
                managed_tasks.reconcile_ui_once()
            self.assertEqual(queue.view()["state"], "active")

    def test_queue_mode_requires_approved_exact_identity_and_sha(self):
        pid, task = self._queue_fixture(state="active", approved=False)
        with patch.object(tf, "load_task", return_value=task):
            self.assertEqual(ui_scheduler.queue_tick(
                now=200, desktop=lambda *_a, **_k: self.fail("send")),
                "ALIS_UI_QUEUE_NOT_AUTHORIZED")
        with queue._lock():
            doc = queue._load()
            doc["approved_start"] = True
            queue._save(doc)
        with patch.object(tf, "load_task", return_value=task):
            self.assertEqual(ui_scheduler.queue_tick(
                now=200, desktop=lambda *_a, **_k: reply("ALIS_LOOP:DONE")),
                "DONE")
        self.assertEqual(store.read_snapshot()[1]["profiles"][pid]["status"],
                         "completed")
        self.assertEqual(queue.view()["state"], "active")
        self.assertIsNotNone(queue.view()["active"])

    def test_queue_mode_stale_sha_and_stop_race_never_submit(self):
        _, task = self._queue_fixture(state="active", approved=True)
        task["task"]["base_sha"] = "b" * 40
        with patch.object(tf, "load_task", return_value=task):
            self.assertEqual(ui_scheduler.queue_tick(
                now=200, desktop=lambda *_a, **_k: self.fail("send")),
                "ALIS_UI_QUEUE_TASK_CHANGED")
        task["task"]["base_sha"] = "a" * 40
        original = ui_scheduler.ui_tick
        def stop_before_intent(*a, **kw):
            with queue._lock():
                doc = queue._load()
                doc["approved_start"] = False
                doc["state"] = "stopping"
                doc["stop_requested"] = True
                queue._save(doc)
            return original(*a, **kw)
        with patch.object(tf, "load_task", return_value=task), \
             patch.object(ui_scheduler, "ui_tick", side_effect=stop_before_intent):
            self.assertEqual(ui_scheduler.queue_tick(
                now=200, desktop=lambda *_a, **_k: self.fail("send")),
                "ALIS_UI_QUEUE_STOPPED_BEFORE_SUBMISSION")
        pid = managed_tasks.profile_id("llocphann/Alis", "AI-I01")
        self.assertIsNone(store.read_snapshot()[1]["profiles"][pid]["pending"])


    def test_ui_queue_start_requires_exact_owner_and_separate_receipt_consent(self):
        pid, task = self._queue_fixture()
        def reset(_config, state):
            state["profiles"][pid].update(desired="stopped", request=None)
        store.change_state(reset)
        report = {
            "queue_state": "prepared",
            "taskflow_profile_present": True,
            "installed_service_mode": "ui_queue_mode",
            "service_state": "active",
            "preflight_blockers": [
                "SCHEDULER_CUTOVER_NOT_READY",
                "UI_QUEUE_OWNER_ACCEPTANCE_REQUIRED",
            ],
        }
        from automation.chat_bridge import ui_preflight
        with patch.object(tf, "load_task", return_value=task), \
             patch.object(ui_preflight, "check_prepared_queue", return_value=report):
            for kw in (
                {},
                {"approved": True},
                {"approved": True, "accept_ui_only_receipts": True,
                 "expected_first": "llocphann/Alis:AI-I02"},
            ):
                with self.assertRaises(tf.TaskError):
                    managed_tasks.start_ui_queue(**kw)
                self.assertEqual(queue.view()["state"], "prepared")
            started = managed_tasks.start_ui_queue(
                approved=True, accept_ui_only_receipts=True,
                expected_first="llocphann/Alis:AI-I01")
            self.assertEqual(started["state"], "scheduled")
            self.assertEqual(started["owner_acceptance"], "local-ui-only")
            self.assertFalse(started["service_modified"])
            self.assertEqual(queue.view()["state"], "active")
            self.assertTrue(store.read_snapshot()[1]["profiles"][pid]["desired"]
                            == "run")
            with self.assertRaises(tf.TaskError):
                managed_tasks.start_ui_queue(
                    approved=True, accept_ui_only_receipts=True,
                    expected_first="llocphann/Alis:AI-I01")

    def test_ui_start_rejects_stale_confirmation_with_identical_first_task(self):
        pid, task = self._queue_fixture()
        store.change_state(lambda _c, state:
            state["profiles"][pid].update(desired="stopped", request=None))
        from automation.chat_bridge import ui_preflight
        report = {
            "queue_state": "prepared",
            "taskflow_profile_present": True,
            "installed_service_mode": "ui_queue_mode",
            "service_state": "active",
            "preflight_blockers": [
                "SCHEDULER_CUTOVER_NOT_READY",
                "UI_QUEUE_OWNER_ACCEPTANCE_REQUIRED",
            ],
        }
        old_id = queue.view()["snapshot_id"]
        with queue._lock():
            newer = queue._load()
            newer["created_unix"] = 98765
            queue._save(newer)
        new_id = queue.view()["snapshot_id"]
        self.assertNotEqual(old_id, new_id)
        with patch.object(tf, "load_task", return_value=task), \\
             patch.object(ui_preflight, "check_prepared_queue", return_value=report):
            with self.assertRaisesRegex(tf.TaskError, "snapshot changed"):
                managed_tasks.start_ui_queue(
                    approved=True, accept_ui_only_receipts=True,
                    expected_first="llocphann/Alis:AI-I01",
                    expected_snapshot_id=old_id)
            self.assertEqual(queue.view()["state"], "prepared")
            self.assertFalse(queue._load()["approved_start"])
            self.assertEqual(store.read_snapshot()[1]["profiles"][pid]["desired"],
                             "stopped")
            result = managed_tasks.start_ui_queue(
                approved=True, accept_ui_only_receipts=True,
                expected_first="llocphann/Alis:AI-I01",
                expected_snapshot_id=new_id)
        self.assertEqual(result["state"], "scheduled")
        qml = (Path(__file__).resolve().parents[1] /
               "modules/settings/AutomationTaskConfig.qml").read_text()
        self.assertIn('"--expected-snapshot-id", snapshotId', qml)
        self.assertIn("uiQueueStartSnapshotId", qml)

    def test_ui_start_rechecks_manifest_before_persisting_approval(self):
        pid, task = self._queue_fixture()
        store.change_state(lambda _c, state:
            state["profiles"][pid].update(desired="stopped", request=None))
        from automation.chat_bridge import ui_preflight
        report = {
            "queue_state": "prepared",
            "taskflow_profile_present": True,
            "installed_service_mode": "ui_queue_mode",
            "service_state": "active",
            "preflight_blockers": [
                "SCHEDULER_CUTOVER_NOT_READY",
                "UI_QUEUE_OWNER_ACCEPTANCE_REQUIRED",
            ],
        }
        original = queue.approve_ordered_start
        def change_between_validation_and_approval(**kwargs):
            with queue._lock():
                changed = queue._load()
                changed["created_unix"] = 12345
                queue._save(changed)
            return original(**kwargs)
        with patch.object(tf, "load_task", return_value=task), \\
             patch.object(ui_preflight, "check_prepared_queue", return_value=report), \\
             patch.object(queue, "approve_ordered_start",
                          side_effect=change_between_validation_and_approval):
            with self.assertRaisesRegex(tf.TaskError, "Queue changed"):
                managed_tasks.start_ui_queue(
                    approved=True, accept_ui_only_receipts=True,
                    expected_first="llocphann/Alis:AI-I01")
        self.assertEqual(queue.view()["state"], "prepared")
        self.assertFalse(queue._load()["approved_start"])
        self.assertEqual(store.read_snapshot()[1]["profiles"][pid]["desired"],
                         "stopped")

    def test_ui_done_receipt_advances_only_exact_local_evidence(self):
        pid, task = self._queue_fixture(state="active", approved=True)
        def save(updated):
            if updated is not task:
                task.clear()
                task.update(updated)
        with patch.object(tf, "load_task", return_value=task), \
             patch.object(tf, "_save_task", side_effect=save):
            self.assertEqual(ui_scheduler.queue_tick(
                now=200, desktop=lambda *_a, **_k: reply("ALIS_LOOP:DONE")),
                "DONE")
            self.assertEqual(ui_scheduler.queue_tick(now=201),
                             "queue_completed_pending_reconciliation")
            outcome = managed_tasks.reconcile_ui_once()
            self.assertEqual(outcome["state"], "finished")
            self.assertEqual(queue.view()["state"], "finished")
            self.assertEqual(task["status"], "awaiting_owner")
            self.assertEqual(task["delivery"]["attestation"], "local-ui-only")
            self.assertIsNone(task["delivery"]["conversation_id"])
            self.assertFalse(task["unresolved"])
            self.assertTrue(task["delivery_acknowledged_unix"])
            self.assertEqual(task["delivery"]["transport"], "alis-ui-once")
            self.assertIsNone(store.read_snapshot()[1]["profiles"][pid]["pending"])

    def test_ui_done_tampered_receipt_blocks_next_task(self):
        pid, task = self._queue_fixture(state="active", approved=True)
        with patch.object(tf, "load_task", return_value=task):
            self.assertEqual(ui_scheduler.queue_tick(
                now=200, desktop=lambda *_a, **_k: reply("ALIS_LOOP:DONE")),
                "DONE")
            attempt = store.read_snapshot()[1]["profiles"][pid][
                "last_ui_response_attempt"]
            path = store.state_dir() / "ui-responses" / pid / (attempt + ".json")
            payload = json.loads(path.read_text())
            payload["directive"] = "CONTINUE"
            path.write_text(json.dumps(payload))
            with self.assertRaises(tf.TaskError):
                managed_tasks.reconcile_ui_once()
            self.assertEqual(queue.view()["state"], "active")
            self.assertEqual(task["status"], "prepared")


if __name__ == "__main__":
    main()
