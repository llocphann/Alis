#!/usr/bin/env python3
"""Read-only preflight never activates Alis UI mode or leaks identifiers."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation.chat_bridge import ui_preflight
from automation.manager import model, store
from automation import managed_tasks, queue, taskflow as tf


class Preflight(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        env = patch.dict(os.environ, {
            "XDG_CONFIG_HOME": self.temp.name + "/config",
            "XDG_STATE_HOME": self.temp.name + "/state",
        })
        env.start()
        self.addCleanup(env.stop)
        self.profile = model.default_profile()
        self.profile["enabled"] = True
        self.config = {"version": 1, "profiles": [self.profile]}
        self.state = {"profiles": {self.profile["id"]: store.profile_state()}}
        self.id = self.profile["id"]

    def view(self, **kwargs):
        return ui_preflight.examine(
            self.config, self.state, self.id,
            service_state=kwargs.get("service_state", "inactive"),
            service_mode=kwargs.get("service_mode", "native_mode"),
            journal_pending=kwargs.get("journal_pending", False))

    def test_clean_inactive_service_is_preflight_only(self):
        result = self.view()
        self.assertTrue(result["mode_change_preflight_clear"])
        self.assertFalse(result["submission_authorized"])
        self.assertFalse(result["service_modified"])
        self.assertFalse(result["ui_target_identity_checked"])
        self.assertNotIn(self.id, json.dumps(result))

    def test_active_native_scheduler_blocks_switch(self):
        result = self.view(service_state="active")
        self.assertFalse(result["mode_change_preflight_clear"])
        self.assertIn("NATIVE_SCHEDULER_ACTIVE", result["preflight_blockers"])

    def test_unsure_or_running_ui_also_blocks(self):
        for active, mode in (("active", "ui_mode"), ("unknown", "unknown"),
                             ("activating", "native_mode")):
            self.assertFalse(self.view(service_state=active,
                                       service_mode=mode)["mode_change_preflight_clear"])

    def test_all_unsettled_receipts_and_sessions_block(self):
        self.state["profiles"][self.id]["pending"] = {"user_message_id": "native"}
        self.assertIn("NATIVE_SESSION_REQUIRES_REVIEW", self.view()["preflight_blockers"])
        self.state["profiles"][self.id]["pending"] = None
        self.state["profiles"][self.id]["session"] = {"conversation_id": "hidden"}
        self.assertIn("NATIVE_SESSION_REQUIRES_REVIEW", self.view()["preflight_blockers"])
        self.state["profiles"][self.id]["session"] = None
        self.assertIn("UI_JOURNAL_UNRESOLVED",
                      self.view(journal_pending=True)["preflight_blockers"])
        self.state["profiles"][self.id]["pending"] = {"transport": "alis-ui-once"}
        self.assertIn("ORIGINAL_SEND_UNRESOLVED", self.view()["preflight_blockers"])

    def test_profile_scheduled_or_waiting_blocks_cutover(self):
        self.state["profiles"][self.id]["desired"] = "run"
        self.assertIn("PROFILE_SCHEDULED_REQUIRES_EXPLICIT_STOP",
                      self.view()["preflight_blockers"])
        self.state["profiles"][self.id]["desired"] = "stopped"
        self.state["profiles"][self.id]["job_id"] = "JOB-EXISTING"
        self.assertIn("PROFILE_WAITING_ON_JOB", self.view()["preflight_blockers"])
        self.state["profiles"][self.id]["job_id"] = None
        self.state["profiles"][self.id]["run_active"] = True
        self.assertIn("PROFILE_SCHEDULED_REQUIRES_EXPLICIT_STOP",
                      self.view()["preflight_blockers"])

    def test_foreign_profile_and_unconfigured_block(self):
        self.state["profiles"]["other"] = {"desired": "run"}
        self.assertIn("FOREIGN_PROFILE_UNSETTLED", self.view()["preflight_blockers"])
        self.profile["enabled"] = False
        self.assertIn("PROFILE_NOT_ENABLED", self.view()["preflight_blockers"])

    def test_read_only_on_uninitialized_filesystem(self):
        original_state = store.state_dir()
        original_config = store.config_path()
        before = list(Path(self.temp.name).rglob("*"))
        with patch.object(ui_preflight, "_unit_state", return_value=("inactive", "native_mode")):
            result = ui_preflight.check(self.id)
        after = list(Path(self.temp.name).rglob("*"))
        self.assertFalse(result["profile_enabled"])
        self.assertEqual(before, after)
        self.assertFalse(original_state.exists())
        self.assertFalse(original_config.exists())

    def test_unit_parser_exposes_no_argv_or_credential(self):
        sample = "LoadState=loaded\nActiveState=inactive\nExecStart={ path=/usr/bin/python3 ; argv[]=/usr/bin/python3 -m automation.manager.daemon --ui-loop-profile sensitiveID ; }\n"
        with patch.object(ui_preflight.subprocess, "run",
                          return_value=SimpleNamespace(returncode=0, stdout=sample)):
            self.assertEqual(ui_preflight._unit_state(), ("inactive", "ui_mode"))


    def _write_queue_fixture(self, *, state="prepared"):
        from automation import queue
        path = store.state_dir() / "taskflow" / "queue.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        manifest = {
            "schema": queue.QUEUE_SCHEMA, "mode": "ordered",
            "state": state, "approved_start": False, "active": None,
            "items": [{
                "code": "AI-I01", "repository": "llocphann/Alis",
                "issue_number": 1, "source_sha": "a" * 40,
                "state": "queued",
            }],
        }
        path.write_text(json.dumps(manifest))
        return path

    def test_prepared_queue_has_own_profile_not_generic_profile(self):
        self._write_queue_fixture()
        config_path = store.config_path()
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text(json.dumps(self.config))
        state_path = store.state_path()
        state_path.write_text(json.dumps(self.state))
        before = sorted(str(p) for p in Path(self.temp.name).rglob("*"))
        with patch.object(ui_preflight, "_unit_state",
                          return_value=("inactive", "native_mode")):
            report = ui_preflight.check_prepared_queue()
        after = sorted(str(p) for p in Path(self.temp.name).rglob("*"))
        self.assertEqual(before, after)
        self.assertEqual(report["queue_state"], "prepared")
        self.assertEqual(report["queue_item_count"], 1)
        self.assertEqual(report["first_task_code"], "AI-I01")
        self.assertFalse(report["taskflow_profile_present"])
        self.assertIn("TASKFLOW_PROFILE_NOT_MATERIALIZED",
                      report["preflight_blockers"])
        self.assertIn("UI_TASK_QUEUE_INTEGRATION_NOT_ACCEPTED",
                      report["preflight_blockers"])
        self.assertFalse(report["queue_ui_admission_available"])
        self.assertFalse(report["submission_authorized"])
        self.assertNotIn(self.id, json.dumps(report))

    def test_queue_readiness_blocks_foreign_pending_even_if_stopped(self):
        self._write_queue_fixture()
        self.state["profiles"][self.id].update(
            desired="stopped", pending={"user_message_id": "secret"},
            session={"conversation_id": "secret"}, run_active=True)
        config_path = store.config_path()
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text(json.dumps(self.config))
        store.state_path().write_text(json.dumps(self.state))
        with patch.object(ui_preflight, "_unit_state",
                          return_value=("active", "native_mode")):
            report = ui_preflight.check_prepared_queue()
        self.assertIn("FOREIGN_PROFILE_UNSETTLED",
                      report["preflight_blockers"])
        self.assertIn("NATIVE_SESSION_REQUIRES_REVIEW",
                      report["preflight_blockers"])
        self.assertIn("SCHEDULER_CUTOVER_NOT_READY",
                      report["preflight_blockers"])
        self.assertNotIn("secret", json.dumps(report))
        self.assertFalse(report["submission_authorized"])

    def test_queue_diagnosis_does_not_create_missing_directories(self):
        before = list(Path(self.temp.name).rglob("*"))
        with patch.object(ui_preflight, "_unit_state",
                          return_value=("inactive", "native_mode")):
            report = ui_preflight.check_prepared_queue()
        self.assertEqual(before, list(Path(self.temp.name).rglob("*")))
        self.assertIn("NO_PREPARED_QUEUE", report["preflight_blockers"])

    def test_queue_diagnosis_rejects_symlink_manifest(self):
        path = store.state_dir() / "taskflow" / "queue.json"
        path.parent.mkdir(parents=True)
        target = path.parent / "private.json"
        target.write_text('{"private":"DO_NOT_REVEAL"}')
        path.symlink_to(target)
        report = ui_preflight.check_prepared_queue()
        self.assertEqual(report["preflight_blockers"], ["LOCAL_STATE_UNREADABLE"])
        self.assertNotIn("DO_NOT_REVEAL", json.dumps(report))


    def test_queue_diagnosis_fail_closed_on_untrusted_status_fields(self):
        path = self._write_queue_fixture()
        for field in ("mode", "state"):
            for bad in (["secret"], {"sensitive": "DO_NOT_REVEAL"}):
                content = json.loads(path.read_text())
                content[field] = bad
                path.write_text(json.dumps(content))
                report = ui_preflight.check_prepared_queue()
                self.assertEqual(report["preflight_blockers"],
                                 ["QUEUE_MANIFEST_INVALID"])
                self.assertNotIn("DO_NOT_REVEAL", json.dumps(report))
                self.assertFalse(report["submission_authorized"])
        # This remains an inspection tool, not a repair or an admission tool.


    def test_ui_queue_start_button_has_safe_staging_and_mode_diagnosis(self):
        qml = (Path(__file__).resolve().parents[1] /
               "modules/settings/AutomationTaskConfig.qml").read_text()
        cli = (Path(__file__).resolve().parents[1] /
               "scripts/alis-automation-task.py").read_text()
        self.assertIn('objectName: "automationStageUiQueue"', qml)
        self.assertIn("function stageUiQueue()", qml)
        self.assertIn('"queue-stage-ui", "--approve", "--expected-first", identity', qml)
        self.assertIn('"--expected-snapshot-id", snapshotId', qml)
        self.assertIn('uiQueueStageAvailable = report.ui_queue_stage_available === true', qml)
        self.assertIn('root.uiQueueServiceMode === "native_mode"', qml)
        self.assertIn("root.refreshBackendStatus", qml)
        self.assertIn('"ui_queue_stage_available": ui_stage_ready', cli)
        self.assertIn('"ui_queue_service_mode": ui_check.get("installed_service_mode")', cli)

    def test_owner_stops_only_unsent_legacy_default_without_touching_queue(self):
        original = self._write_queue_fixture()
        item = self.state["profiles"][self.id]
        item.update(desired="run", status="scheduled",
                    session={"conversation_id": "PRESERVE_PRIVATE_NATIVE"},
                    checkpoint={"original": "DO_NOT_ERASE"},
                    pending=None, job_id=None, run_active=False)
        config_path = store.config_path()
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text(json.dumps(self.config))
        store.state_path().write_text(json.dumps(self.state))
        snapshot = queue.view()["snapshot_id"]
        queue_bytes = original.read_bytes()
        with patch.object(ui_preflight, "_unit_state",
                          return_value=("active", "ui_queue_mode")):
            before = ui_preflight.check_prepared_queue()
            self.assertTrue(before["idle_default_stop_available"])
            self.assertIn("FOREIGN_PROFILE_UNSETTLED",
                          before["preflight_blockers"])
            with self.assertRaisesRegex(tf.TaskError, "approval"):
                managed_tasks.stop_idle_legacy_default_for_ui_queue(
                    expected_snapshot_id=snapshot)
            with self.assertRaisesRegex(tf.TaskError, "Queue changed"):
                managed_tasks.stop_idle_legacy_default_for_ui_queue(
                    approved=True, expected_snapshot_id="f" * 64)
            result = managed_tasks.stop_idle_legacy_default_for_ui_queue(
                approved=True, expected_snapshot_id=snapshot)
            after = ui_preflight.check_prepared_queue()
        self.assertEqual(result["state"], "legacy_idle_stopped")
        self.assertFalse(result["new_message_sent"])
        self.assertFalse(result["service_modified"])
        self.assertEqual(original.read_bytes(), queue_bytes)
        self.assertFalse(queue._load()["approved_start"])
        self.assertFalse(after["idle_default_stop_available"])
        self.assertNotIn("FOREIGN_PROFILE_UNSETTLED", after["preflight_blockers"])
        self.assertNotIn("NATIVE_SESSION_REQUIRES_REVIEW", after["preflight_blockers"])
        saved = store.read_snapshot()[1]["profiles"][self.id]
        self.assertEqual(saved["desired"], "stopped")
        self.assertEqual(saved["checkpoint"], {"original": "DO_NOT_ERASE"})
        self.assertEqual(saved["session"]["conversation_id"], "PRESERVE_PRIVATE_NATIVE")

    def test_pending_or_running_legacy_default_cannot_be_stopped_by_ui_queue(self):
        self._write_queue_fixture()
        item = self.state["profiles"][self.id]
        item.update(desired="run", status="scheduled",
                    pending={"phase": "dispatching", "id": "DO_NOT_RESEND"},
                    session={"conversation_id": "HISTORICAL"})
        config_path = store.config_path()
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text(json.dumps(self.config))
        store.state_path().write_text(json.dumps(self.state))
        snapshot = queue.view()["snapshot_id"]
        previous = store.state_path().read_bytes()
        with patch.object(ui_preflight, "_unit_state",
                          return_value=("active", "ui_queue_mode")):
            self.assertFalse(
                ui_preflight.check_prepared_queue()["idle_default_stop_available"])
            with self.assertRaisesRegex(tf.TaskError, "blocked"):
                managed_tasks.stop_idle_legacy_default_for_ui_queue(
                    approved=True, expected_snapshot_id=snapshot)
        self.assertEqual(store.state_path().read_bytes(), previous)
        self.assertEqual(queue.view()["snapshot_id"], snapshot)

    def test_idle_legacy_stop_button_requires_owner_and_readiness(self):
        qml = (Path(__file__).resolve().parents[1] /
               "modules/settings/AutomationTaskConfig.qml").read_text()
        cli = (Path(__file__).resolve().parents[1] /
               "scripts/alis-automation-task.py").read_text()
        self.assertIn('objectName: "automationStopIdleLegacy"', qml)
        self.assertIn("function stopIdleLegacyForUiQueue()", qml)
        self.assertIn('"queue-stop-idle-legacy", "--approve"', qml)
        self.assertIn("uiQueueIdleLegacyStopConfirmation", qml)
        self.assertIn("queue-stop-idle-legacy", cli)
        self.assertIn("stop_idle_legacy_default_for_ui_queue(", cli)

    def test_ui_queue_staging_requires_idle_native_and_exact_owner(self):
        path = self._write_queue_fixture()
        self.config["profiles"][0]["enabled"] = True
        config_path = store.config_path()
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text(json.dumps(self.config))
        store.state_path().write_text(json.dumps(self.state))
        original = path.read_bytes()
        task = {"status": "prepared", "task": {"base_sha": "a" * 40},
                "unresolved": False, "scheduler_dispatched": False,
                "handoff": None, "latest_receipt": None}
        exact = "llocphann/Alis:AI-I01"
        with patch.object(ui_preflight, "_unit_state",
                          return_value=("inactive", "native_mode")), \
             patch.object(managed_tasks.tf, "load_task",
                          return_value=task):
            with self.assertRaises(tf.TaskError):
                managed_tasks.stage_ui_queue(expected_first=exact)
            with self.assertRaises(tf.TaskError):
                managed_tasks.stage_ui_queue(
                    approved=True, expected_first="llocphann/Alis:AI-I02")
            self.assertEqual(len(store.read_snapshot()[0]["profiles"]), 1)
            staged = managed_tasks.stage_ui_queue(
                approved=True, expected_first=exact)
            self.assertEqual(staged["state"], "profile_staged")
            self.assertFalse(staged["start_approved"])
            self.assertFalse(staged["submission_authorized"])
            self.assertFalse(staged["service_modified"])
            self.assertTrue(staged["queue_unchanged"])
            self.assertEqual(path.read_bytes(), original)
            profiles, runtime, _ = store.read_snapshot()
            staged_profile = next(
                p for p in profiles["profiles"] if p["id"] == staged["profile_id"])
            self.assertEqual(managed_tasks.reference(staged_profile),
                             ("llocphann/Alis", "AI-I01"))
            self.assertTrue(staged_profile["enabled"])
            self.assertEqual(runtime["profiles"][staged["profile_id"]]["desired"],
                             "stopped")
            self.assertIsNone(runtime["profiles"][staged["profile_id"]]["pending"])
            again = managed_tasks.stage_ui_queue(
                approved=True, expected_first=exact)
            self.assertEqual(again["profile_id"], staged["profile_id"])
            self.assertEqual(path.read_bytes(), original)

    def test_ui_queue_active_daemon_allows_idle_staging_but_not_start(self):
        original_queue = self._write_queue_fixture()
        config_path = store.config_path()
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text(json.dumps(self.config))
        store.state_path().write_text(json.dumps(self.state))
        saved_queue = original_queue.read_bytes()
        task = {"status": "prepared", "task": {"base_sha": "a" * 40},
                "unresolved": False, "scheduler_dispatched": False,
                "handoff": None, "latest_receipt": None}
        first = "llocphann/Alis:AI-I01"
        original_snapshot = queue.view()["snapshot_id"]
        with patch.object(ui_preflight, "_unit_state",
                          return_value=("active", "ui_queue_mode")), \
             patch.object(managed_tasks.tf, "load_task", return_value=task):
            with self.assertRaisesRegex(tf.TaskError, "changed"):
                managed_tasks.stage_ui_queue(
                    approved=True, expected_first=first,
                    expected_snapshot_id="f" * 64)
            self.assertEqual(len(store.read_snapshot()[0]["profiles"]), 1)
            staged = managed_tasks.stage_ui_queue(
                approved=True, expected_first=first,
                expected_snapshot_id=original_snapshot)
            self.assertEqual(staged["state"], "profile_staged")
            self.assertFalse(staged["start_approved"])
            self.assertFalse(staged["submission_authorized"])
            self.assertTrue(staged["queue_unchanged"])
            # A running UI Queue service is not permission to schedule.
            after = ui_preflight.check_prepared_queue()
            self.assertTrue(after["taskflow_profile_present"])
            self.assertFalse(after["submission_authorized"])
            self.assertEqual(set(after["preflight_blockers"]), {
                "SCHEDULER_CUTOVER_NOT_READY",
                "UI_QUEUE_OWNER_ACCEPTANCE_REQUIRED",
            })
        self.assertEqual(original_queue.read_bytes(), saved_queue)
        config, runtime, _ = store.read_snapshot()
        self.assertEqual(runtime["profiles"][staged["profile_id"]]["desired"],
                         "stopped")
        self.assertIsNone(runtime["profiles"][staged["profile_id"]]["pending"])
        self.assertFalse(queue._load()["approved_start"])
        # Already-started/sent UI state must not be mistaken for an idle,
        # idempotently staged profile on a later owner click.
        store.change_state(lambda _config, state:
            state["profiles"][staged["profile_id"]].update(
                desired="run", pending={"transport": "alis-ui-once",
                                        "attempt_id": "ORIGINAL_UNRESOLVED"}))
        with patch.object(ui_preflight, "_unit_state",
                          return_value=("active", "ui_queue_mode")), \
             patch.object(managed_tasks.tf, "load_task", return_value=task):
            blocked = ui_preflight.check_prepared_queue()
            self.assertIn("TASKFLOW_PROFILE_NOT_IDLE", blocked["preflight_blockers"])
            self.assertFalse(blocked["submission_authorized"])
            with self.assertRaisesRegex(tf.TaskError, "reconciliation"):
                managed_tasks.stage_ui_queue(
                    approved=True, expected_first=first,
                    expected_snapshot_id=original_snapshot)
        self.assertEqual(original_queue.read_bytes(), saved_queue)
        self.assertEqual(store.read_snapshot()[1]["profiles"]
                         [staged["profile_id"]]["pending"]["attempt_id"],
                         "ORIGINAL_UNRESOLVED")

    def test_ui_queue_staging_preserves_old_pending_and_active_native_service(self):
        path = self._write_queue_fixture()
        config_path = store.config_path()
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text(json.dumps(self.config))
        self.state["profiles"][self.id].update(
            desired="stopped", pending={"user_message_id": "keep"},
            session={"conversation_id": "keep"}, run_active=True)
        store.state_path().write_text(json.dumps(self.state))
        original = path.read_bytes()
        for service in (("active", "native_mode"), ("inactive", "native_mode")):
            with patch.object(ui_preflight, "_unit_state",
                              return_value=service), \
                 patch.object(managed_tasks, "_ensure_profile",
                              side_effect=AssertionError("must not stage")):
                with self.assertRaises(tf.TaskError):
                    managed_tasks.stage_ui_queue(
                        approved=True, expected_first="llocphann/Alis:AI-I01")
        self.assertEqual(path.read_bytes(), original)
        self.assertEqual(
            json.loads(store.state_path().read_text())["profiles"][self.id]["pending"],
            {"user_message_id": "keep"})


    def test_disabled_stopped_native_pending_is_preserved_not_a_new_ui_owner(self):
        legacy = model.new_profile("Old native")
        legacy["enabled"] = False
        self.config["profiles"].append(legacy)
        original = store.profile_state()
        original.update(desired="stopped", pending={
            "user_message_id": "DO_NOT_REVEAL",
            "phase": "dispatching",
        }, session={"conversation_id": "DO_NOT_REVEAL"},
            run_active=True)
        self.state["profiles"][legacy["id"]] = original
        snapshot = json.dumps(original, sort_keys=True)
        report = self.view()
        self.assertTrue(report["mode_change_preflight_clear"])
        self.assertTrue(report["legacy_native_pending_retained"])
        self.assertFalse(report["foreign_work_unsettled"])
        self.assertFalse(report["native_session_unsettled"])
        self.assertFalse(report["submission_authorized"])
        self.assertNotIn("DO_NOT_REVEAL", json.dumps(report))
        self.assertEqual(json.dumps(original, sort_keys=True), snapshot)
        # An enabled legacy profile, a job, or a running desired state
        # must block, even if it retains the same stopped-era pending.
        for mutation in (
            lambda: legacy.update(enabled=True),
            lambda: original.update(job_id="JOB-STILL-ACTIVE"),
            lambda: original.update(desired="run"),
        ):
            legacy["enabled"] = False
            original.update(job_id=None, desired="stopped")
            mutation()
            self.assertIn("FOREIGN_PROFILE_UNSETTLED",
                          self.view()["preflight_blockers"])

    def test_historical_native_session_without_pending_never_blocks_new_ui_task(self):
        self._write_queue_fixture()
        historical = self.config["profiles"][0]
        historical["enabled"] = True
        original = self.state["profiles"][self.id]
        original.update(desired="stopped", status="idle",
                        session={"conversation_id": "PRIVATE_HISTORICAL_CHAT"},
                        pending=None, job_id=None, run_active=False)
        old_bytes = json.dumps(original, sort_keys=True)
        config_path = store.config_path()
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text(json.dumps(self.config))
        store.state_path().write_text(json.dumps(self.state))
        with patch.object(ui_preflight, "_unit_state",
                          return_value=("active", "ui_queue_mode")):
            report = ui_preflight.check_prepared_queue()
        self.assertEqual(report["queue_state"], "prepared")
        self.assertEqual(report["historical_native_session_count"], 1)
        self.assertEqual(report["native_unsettled_count"], 0)
        self.assertEqual(report["foreign_running_count"], 0)
        self.assertNotIn("NATIVE_SESSION_REQUIRES_REVIEW", report["preflight_blockers"])
        self.assertNotIn("FOREIGN_PROFILE_UNSETTLED", report["preflight_blockers"])
        self.assertNotIn("PRIVATE_HISTORICAL_CHAT", json.dumps(report))
        self.assertEqual(json.dumps(original, sort_keys=True), old_bytes)
        self.assertFalse(report["submission_authorized"])

        # An unsettled native pending, job, running state, or uncertain
        # status MUST still block; never translate an ID into send approval.
        original["pending"] = {"id": "DO_NOT_RESEND"}
        with patch.object(ui_preflight, "_unit_state",
                          return_value=("active", "ui_queue_mode")):
            store.state_path().write_text(json.dumps(self.state))
            blocked = ui_preflight.check_prepared_queue()
            self.assertIn("NATIVE_SESSION_REQUIRES_REVIEW",
                          blocked["preflight_blockers"])
            self.assertIn("FOREIGN_PROFILE_UNSETTLED",
                          blocked["preflight_blockers"])
        original["pending"] = None
        for mutate in (
            lambda: original.update(job_id="JOB-PRESERVED"),
            lambda: original.update(desired="run", job_id=None),
            lambda: original.update(desired="stopped", run_active=True),
            lambda: original.update(run_active=False, status="stopping"),
        ):
            original.update(desired="stopped", status="idle",
                            job_id=None, run_active=False)
            mutate()
            self.assertFalse(ui_preflight.inert_native_session_history(
                self.config, self.id, original))
        self.assertTrue(ui_preflight.has_unresolved_native_transport({
            "pending": {"transport": "alis-ui-once"},
            "session": {"conversation_id": "native-historical"}}))

    def test_ui_preflight_historical_foreign_session_does_not_block_cutover(self):
        legacy = model.new_profile("Past native")
        self.config["profiles"].append(legacy)
        old = store.profile_state()
        old.update(desired="stopped", status="completed",
                   session={"conversation_id": "OLD_PRIVATE"})
        self.state["profiles"][legacy["id"]] = old
        preview = self.view()
        self.assertFalse(preview["native_session_unsettled"])
        self.assertFalse(preview["foreign_work_unsettled"])
        self.assertTrue(preview["mode_change_preflight_clear"])
        self.assertNotIn("OLD_PRIVATE", json.dumps(preview))

    def test_prepared_queue_stage_with_only_retained_disabled_native_pending(self):
        path = self._write_queue_fixture()
        legacy = self.config["profiles"][0]
        legacy["enabled"] = False
        self.state["profiles"][self.id].update(
            desired="stopped", pending={"user_message_id": "KEEP"},
            session={"conversation_id": "KEEP"}, run_active=True)
        original_legacy = json.dumps(self.state["profiles"][self.id],
                                     sort_keys=True)
        config_path = store.config_path()
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text(json.dumps(self.config))
        store.state_path().write_text(json.dumps(self.state))
        original_queue = path.read_bytes()
        task = {"status": "prepared", "task": {"base_sha": "a" * 40},
                "unresolved": False, "scheduler_dispatched": False,
                "handoff": None, "latest_receipt": None}
        with patch.object(ui_preflight, "_unit_state",
                          return_value=("inactive", "native_mode")), \
             patch.object(managed_tasks.tf, "load_task", return_value=task):
            preflight = ui_preflight.check_prepared_queue()
            self.assertTrue(preflight["legacy_native_pending_retained"])
            self.assertNotIn("FOREIGN_PROFILE_UNSETTLED",
                             preflight["preflight_blockers"])
            self.assertNotIn("NATIVE_SESSION_REQUIRES_REVIEW",
                             preflight["preflight_blockers"])
            staged = managed_tasks.stage_ui_queue(
                approved=True, expected_first="llocphann/Alis:AI-I01")
            self.assertEqual(staged["state"], "profile_staged")
        self.assertEqual(path.read_bytes(), original_queue)
        after = json.loads(store.state_path().read_text())
        self.assertEqual(json.dumps(after["profiles"][self.id], sort_keys=True),
                         original_legacy)


if __name__ == "__main__":
    unittest.main()
