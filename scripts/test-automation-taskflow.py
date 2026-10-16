#!/usr/bin/env python3
"""Offline focused tests for AUTO-R01; no network or local agent required."""
from __future__ import annotations
import json
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation import taskflow, credentials, rotation, lifecycle, queue, activity, managed_tasks
from automation.manager import model as legacy_model, store as legacy_store, control as legacy_control

TASK = {
    "code": "AUTO-R01", "repository": "llocphann/Alis",
    "issue_number": 104, "branch": "dev", "base_sha": "a" * 40,
    "issue_updated_at": "2026-10-15T00:00:00Z",
    "issue_url": "https://github.com/llocphann/Alis/issues/104"
}

def api(endpoint):
    if endpoint.startswith("/search/issues?"):
        if "Alis-Companion" in endpoint or "Alis-Intergration" in endpoint:
            return {"total_count": 0, "items": []}
        return {"total_count": 1, "items": [{"number": 104, "title": "[AUTO-R01] Task flow"}]}
    if endpoint.endswith("/issues/104"):
        return {"number": 104, "title": "[AUTO-R01] Task flow", "state": "open",
                "comments": 1, "updated_at": "2026-10-15T00:00:00Z",
                "body": "A fixture issue"}
    if endpoint.endswith("/branches/dev"):
        return {"commit": {"sha": "a" * 40}}
    if endpoint.endswith("/comments?per_page=100"):
        return [{"id": 5, "body": "Fixture comment"}]
    raise AssertionError(endpoint)


class TaskflowTests(unittest.TestCase):
    def test_github_app_mention_is_first_in_all_cloudbot_prompt_phases(self):
        from automation.chat_bridge.protocol import (
            GITHUB_APP_MENTION, GITHUB_MENTION, cloud_github_prompt,
            prompt_has_required_github_mention)
        self.assertEqual(
            GITHUB_APP_MENTION,
            "[$github](app://connector_76869538009648d5b282a4bb21c3d157)")
        prepared = taskflow.internal_prompt(TASK)
        self.assertTrue(prepared.startswith(GITHUB_APP_MENTION+"\n\n"))
        self.assertEqual(prepared.count(GITHUB_APP_MENTION),1)
        self.assertTrue(prompt_has_required_github_mention(prepared))
        self.assertEqual(cloud_github_prompt(prepared),prepared)
        self.assertTrue(prompt_has_required_github_mention(
            GITHUB_MENTION+"\n\nlegacy prompt"))
        fake = {
            "task": TASK,
            "cloud_prompt": prepared,
            "unresolved": False,
            "latest_receipt": None,
            "handoff": None,
            "rotation": None,
        }
        profile={
            "id": managed_tasks.profile_id(TASK["repository"],TASK["code"]),
            "description": "taskflow:"+TASK["repository"]+":"+TASK["code"],
        }
        with patch.object(taskflow,"load_task",return_value=fake):
            for phase in ("initial","continuation","rotation"):
                prompt=managed_tasks.prompt(profile,phase)
                self.assertTrue(prompt.startswith(GITHUB_APP_MENTION+"\n\n"),phase)
                self.assertEqual(prompt.count(GITHUB_APP_MENTION),1,phase)
                self.assertTrue(prompt_has_required_github_mention(prompt),phase)
                self.assertIn("ALIS_LOOP:CONNECTOR_BLOCKED GITHUB",prompt)
        with patch.object(managed_tasks.queue,"cloud_selection_prompt",
                          return_value="Approved queue fixture"):
            for phase in ("initial","continuation","rotation"):
                prompt=managed_tasks.selector_prompt(phase)
                self.assertTrue(prompt.startswith(GITHUB_APP_MENTION+"\n\n"),phase)
                self.assertEqual(prompt.count(GITHUB_APP_MENTION),1,phase)
                self.assertIn("ALIS_LOOP:CONNECTOR_BLOCKED GITHUB",prompt)


    def test_bulk_intake_queries_open_issues_only_and_pins_each_repo_once(self):
        requests = []
        def listing(endpoint):
            requests.append(endpoint)
            if "/issues?state=open&per_page=100&page=1" in endpoint:
                if "/Alis-Companion/" in endpoint:
                    return [{"number": 4, "title": "[AC-I01] Canonical Companion",
                             "state": "open", "comments": 0, "body": "Companion work"}]
                if "/Alis-Intergration/" in endpoint:
                    return []
                return [
                    {"number": 81, "title": "[AUDIO-I01] Audio crackle",
                     "state": "open", "comments": 0, "body": "Audio work"},
                    {"number": 89, "title": "[AC-I01] Archived old task",
                     "state": "closed", "comments": 0},
                    {"number": 80, "title": "[MUSIC-I02] Local music",
                     "state": "open", "comments": 0},
                    {"number": 50, "title": "[AC-I01] Pull request",
                     "state": "open", "pull_request": {"url": "pr"}, "comments": 0},
                ]
            if "/branches/" in endpoint:
                return {"commit": {"sha": "a" * 40}}
            raise AssertionError(endpoint)
        codes = ["AUDIO-I01", "MUSIC-I02", "AC-I01"]
        tasks = taskflow.resolve_batch(codes, api=listing)
        self.assertEqual([t["code"] for t in tasks], codes)
        self.assertEqual(tasks[-1]["repository"], "llocphann/Alis-Companion")
        self.assertEqual(tasks[-1]["issue_number"], 4)
        self.assertEqual(len(requests), 5)  # Three lists + two pinned branches.
        self.assertFalse(any("/search/issues" in x for x in requests))
        self.assertFalse(any("/issues/81" in x for x in requests))
        with self.assertRaisesRegex(taskflow.TaskError, "No matching open Issue"):
            taskflow.resolve_batch(["ABYSS-R99"], api=listing)

    def test_queue_default_resolver_uses_one_batch(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"XDG_STATE_HOME": tmp}), \
             patch.object(taskflow, "resolve_batch", return_value=[TASK]) as bulk:
            prepared = queue.prepare("AUTO-R01")
            self.assertEqual(prepared["items"][0]["code"], "AUTO-R01")
            bulk.assert_called_once_with(["AUTO-R01"])

    def test_github_errors_identify_rate_limit_vs_offline_without_secrets(self):
        from urllib.error import HTTPError, URLError
        with patch.dict("os.environ", {"GH_TOKEN": "", "GITHUB_TOKEN": ""}), \
             patch.object(credentials, "status", return_value={"saved": False}):
            limited = HTTPError("https://api.github.com", 403, "rate limited",
                                {"X-RateLimit-Remaining": "0"}, None)
            with patch.object(taskflow, "urlopen", side_effect=limited), \
                 self.assertRaisesRegex(taskflow.TaskError, "rate limit reached"):
                taskflow._github("/repos/llocphann/Alis/issues/81")
            with patch.object(taskflow, "urlopen", side_effect=URLError("DNS failure")), \
                 self.assertRaisesRegex(taskflow.TaskError, "Cannot reach api.github.com"):
                taskflow._github("/repos/llocphann/Alis/issues/81")

    def test_cleanup_settings_contract(self):
        qml = (Path(__file__).resolve().parents[1] /
               "modules/settings/AutomationTaskConfig.qml").read_text()
        self.assertIn("Preview cleanup", qml)
        self.assertIn("Clean now", qml)
        self.assertIn("root.inspectCleanup(true)", qml)
        self.assertIn("cleanupProcess", qml)

    def test_existing_active_queue_is_read_without_requerying_github(self):
        other = {**TASK, "code": "MUSIC-I02", "issue_number": 80}
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {
                "XDG_STATE_HOME": tmp}):
            queue.prepare("AUTO-R01; MUSIC-I02",
                          resolver=lambda code: TASK if code == "AUTO-R01" else other)
            queue.claim(verified_start=lambda *args: True)
            with patch.object(taskflow, "resolve_batch",
                              side_effect=AssertionError("GitHub should not be queried")) as bulk:
                same = queue.prepare("AUTO-R01; MUSIC-I02")
                self.assertTrue(same["duplicate"])
                self.assertEqual(same["state"], "active")
                self.assertEqual(same["active"]["code"], "AUTO-R01")
                with self.assertRaisesRegex(taskflow.TaskError, "unfinished queue"):
                    queue.prepare("MUSIC-I02; AUTO-R01")
                bulk.assert_not_called()

    def test_cli_import_failure_is_structured_without_private_traceback(self):
        import shutil
        # Only the isolated frontend is installed; its automation/ Python
        # dependencies are deliberately absent. This must return one JSON
        # error instead of exit 1 with empty stdout.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            script = root / "scripts/alis-automation-task.py"
            script.parent.mkdir(parents=True)
            shutil.copy2(Path(__file__).resolve().parents[1] /
                         "scripts/alis-automation-task.py", script)
            result = subprocess.run(
                [sys.executable, "-I", str(script), "queue-status"],
                cwd=root, text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stderr, "")
            reply = json.loads(result.stdout)
            self.assertFalse(reply["ok"])
            self.assertIn("runtime import failed", reply["error"])
            self.assertNotIn("Traceback", result.stdout)

    def test_queue_ui_does_not_show_stale_prepared_success_on_error(self):
        qml = (Path(__file__).resolve().parents[1] /
               "modules/settings/AutomationTaskConfig.qml").read_text()
        self.assertIn("property bool queueStatusConfirmed: false", qml)
        self.assertIn('root.statusText = ""', qml)
        self.assertIn('root.errorText = String(error)', qml)
        self.assertIn('root.queueStatusConfirmed && !!root.queueSnapshot', qml)
        self.assertIn("Last known queue only", qml)
        self.assertIn('objectName: "automationRefreshQueue"', qml)
        self.assertIn("Queue already active", qml)

    def test_queue_parse_validation_and_no_partial_queue_on_missing_issue(self):
        self.assertEqual(queue.parse_codes("AUTO-R01; ABYSS-R09"),
                         ["AUTO-R01", "ABYSS-R09"])
        for raw in ("", "AUTO-R01;", "AUTO-R01; AUTO-R01", "AUTO-R01; rm -rf /",
                    "AUTO-R01;" * 30):
            with self.assertRaises(taskflow.TaskError):
                queue.parse_codes(raw)
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"XDG_STATE_HOME": tmp}):
            with self.assertRaisesRegex(taskflow.TaskError, "missing"):
                queue.prepare("AUTO-R01; ABYSS-R09", resolver=lambda code:
                    TASK if code == "AUTO-R01" else
                    (_ for _ in ()).throw(taskflow.TaskError("missing")))
            self.assertEqual(queue.view()["state"], "empty")

    def test_ordered_queue_serial_claim_and_owner_separated(self):
        other = {**TASK, "code": "ABYSS-R09", "issue_number": 139,
                 "issue_url": "https://github.com/llocphann/Alis/issues/139"}
        resolver = lambda code: TASK if code == "AUTO-R01" else other
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"XDG_STATE_HOME": tmp}):
            prepared = queue.prepare("AUTO-R01; ABYSS-R09", resolver=resolver)
            self.assertEqual([x["code"] for x in prepared["items"]],
                             ["AUTO-R01", "ABYSS-R09"])
            self.assertEqual(prepared["mode"], "ordered")
            self.assertEqual(prepared["next"]["code"], "AUTO-R01")
            self.assertTrue(queue.prepare("AUTO-R01; ABYSS-R09", resolver=resolver)["duplicate"])
            with self.assertRaisesRegex(taskflow.TaskError, "unfinished"):
                queue.prepare("ABYSS-R09; AUTO-R01", resolver=resolver)
            with self.assertRaisesRegex(taskflow.TaskError, "AUTO-F01"):
                queue.claim()
            with self.assertRaisesRegex(taskflow.TaskError, "cannot skip"):
                queue.claim(verified_start=lambda *args: True, choice="ABYSS-R09")
            with self.assertRaisesRegex(taskflow.TaskError, "did not authorize"):
                queue.claim(verified_start=lambda *args: False)
            first = queue.claim(verified_start=lambda *args: True)
            self.assertEqual(first["selected"]["code"], "AUTO-R01")
            with self.assertRaisesRegex(taskflow.TaskError, "not ready"):
                queue.claim(verified_start=lambda *args: True)
            with self.assertRaisesRegex(taskflow.TaskError, "AUTO-F01"):
                queue.advance()
            with self.assertRaisesRegex(taskflow.TaskError, "still awaiting"):
                queue.advance(verify_completion=lambda record: True)
            record = taskflow.load_task("AUTO-R01")
            record["status"] = "awaiting_owner"
            record["delivery_acknowledged_unix"] = 10
            taskflow._save_task(record)
            with self.assertRaisesRegex(taskflow.TaskError, "rejected"):
                queue.advance(verify_completion=lambda record: False)
            advanced = queue.advance(verify_completion=lambda record: True)
            self.assertEqual(advanced["state"], "waiting")
            self.assertEqual(advanced["next"]["code"], "ABYSS-R09")
            self.assertEqual(advanced["items"][0]["state"], "awaiting_owner")
            second = queue.claim(verified_start=lambda *args: True)
            self.assertEqual(second["selected"]["code"], "ABYSS-R09")
            record = taskflow.load_task("ABYSS-R09")
            record["status"] = "completed"
            record["delivery_acknowledged_unix"] = 10
            taskflow._save_task(record)
            self.assertEqual(queue.advance(verify_completion=lambda record: True)["state"], "finished")
            self.assertEqual(len(list((taskflow.state_dir()/"tasks"/"Alis").glob("*.json"))), 2)

    def test_cloud_queue_choice_needs_authenticated_decision(self):
        other = {**TASK, "code": "ABYSS-R09", "issue_number": 139}
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"XDG_STATE_HOME": tmp}):
            prepared = queue.prepare("AUTO-R01; ABYSS-R09", mode="cloud",
                resolver=lambda c: TASK if c == "AUTO-R01" else other)
            self.assertTrue(prepared["cloud_selection_required"])
            self.assertIsNone(prepared["next"])
            prompt = queue.cloud_selection_prompt()
            self.assertIn("AUTO-R01", prompt)
            self.assertIn("ABYSS-R09", prompt)
            self.assertIn("untrusted input", prompt)
            self.assertIn("evidence-based rationale", prompt)
            with self.assertRaisesRegex(taskflow.TaskError, "decision ID"):
                queue.claim(verified_start=lambda *args: True, choice="ABYSS-R09")
            with self.assertRaisesRegex(taskflow.TaskError, "not in pending"):
                queue.claim(verified_start=lambda *args: True,
                            choice="NOTREAL-R99", decision_id="decision:001")
            chosen = queue.claim(verified_start=lambda selected, record, decision_id:
                selected["code"] == "ABYSS-R09" and decision_id == "cloud-choice:0001",
                choice="ABYSS-R09", decision_id="cloud-choice:0001")
            self.assertEqual(chosen["selected"]["code"], "ABYSS-R09")
            self.assertEqual(queue.view()["active"]["code"], "ABYSS-R09")
            self.assertEqual(queue.view()["items"][0]["state"], "queued")

    def test_activity_log_redaction_and_bounded_events(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"XDG_STATE_HOME": tmp}):
            taskflow.intake(taskflow.resolve("AUTO-R01", api))
            record = taskflow.load_task("AUTO-R01")
            self.assertEqual(record["activity"][0]["kind"], "task_prepared")
            record["status"] = "handoff_ready"
            taskflow._save_task(record)
            token = "ghp_" + "A" * 25
            taskflow.append_report("AUTO-R01", "diagnostic", "Bearer ghp_"+"A"*25+" "+token)
            events = activity.read("AUTO-R01")
            self.assertEqual(events["events"][-1]["kind"], "handoff_ready")
            self.assertIn("[REDACTED]", events["logs"][0]["text"])
            self.assertNotIn(token, events["logs"][0]["text"])
            for i in range(90):
                activity.append_event(record, "status", "event "+str(i), now=i)
            self.assertEqual(len(record["activity"]), activity.EVENT_LIMIT)
            self.assertLessEqual(len(activity.redact("X" * 10000)), activity.BODY_LIMIT)

    def test_diagnostics_read_bounded_local_receipt_without_file_sprawl(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"XDG_STATE_HOME": tmp}):
            taskflow.intake(taskflow.resolve("AUTO-R01", api))
            summary = taskflow.load_task("AUTO-R01")
            job = "JOB-" + "b" * 24
            summary["latest_receipt"] = {"id": job, "sha256": "c" * 64,
                                         "source_sha": TASK["base_sha"],
                                         "state": "failed", "finished_unix": 1000}
            taskflow._save_task(summary)
            target = taskflow.state_dir() / "receipts" / (job + ".json")
            target.parent.mkdir(parents=True)
            token = "ghp_" + "z" * 25
            taskflow._atomic_json(target, {
                "id": job, "sha256": "c" * 64,
                "source_sha": TASK["base_sha"], "state": "failed",
                "steps": [{"argv": ["python3", "scripts/test-fail.py"],
                           "exit_code": 1, "output_excerpt": "failed token "+token}]})
            logs = activity.read("AUTO-R01")["logs"]
            self.assertTrue(any(x["kind"] == "local_test" for x in logs))
            self.assertTrue(any("exit=1" in x["text"] for x in logs))
            self.assertNotIn(token, repr(logs))
            self.assertIn("[REDACTED]", repr(logs))
            self.assertEqual(len(list((taskflow.state_dir() / "tasks" / "Alis").glob("*.json"))), 1)

    def test_queue_activity_logs_settings_contract(self):
        qml = (Path(__file__).resolve().parents[1] /
               "modules/settings/AutomationTaskConfig.qml").read_text()
        self.assertIn("automationCloudSelectToggle", qml)
        self.assertIn("queue-prepare", qml)
        self.assertIn("automationActivityLog", qml)
        self.assertIn("automationDiagnosticLog", qml)
        self.assertIn("Task codes separated by ;", qml)
        self.assertEqual(qml.count("Component.onCompleted:"), 1)
        self.assertNotIn("automationRotationPrompt", qml)
        self.assertNotIn("prepareProcess", qml)

    def test_new_automation_project_defaults_to_automatic_alis_without_rebinding_existing(self):
        self.assertEqual(legacy_model.DEFAULT_PROJECT, "Automatic Alis")
        self.assertEqual(legacy_model.default_profile()["project_name"], "Automatic Alis")
        self.assertEqual(legacy_model.new_profile("New")["project_name"], "Automatic Alis")
        # Explicitly saved targets in old installations remain untouched.
        legacy = legacy_model.default_profile()
        legacy["project_name"] = "Hadalis Cloud"
        old_config, warnings = legacy_model.normalize_config({
            "version": 1, "maintenance": {},
            "profiles": [legacy],
        })
        self.assertEqual(old_config["profiles"][0]["project_name"], "Hadalis Cloud")
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {
                "XDG_STATE_HOME": tmp + "/state",
                "XDG_CONFIG_HOME": tmp + "/config"}):
            taskflow.intake(taskflow.resolve("AUTO-R01", api))
            pid = managed_tasks._ensure_profile("llocphann/Alis", "AUTO-R01")
            config, _, _ = legacy_store.read_snapshot()
            task_profile = next(p for p in config["profiles"] if p["id"] == pid)
            self.assertEqual(task_profile["project_name"], "Automatic Alis")
            def retain_selected_project(config, state):
                next(p for p in config["profiles"] if p["id"] == pid)["project_name"] = "Hadalis Cloud"
            legacy_store.change(retain_selected_project)
            self.assertEqual(managed_tasks._ensure_profile("llocphann/Alis", "AUTO-R01"), pid)
            config, _, _ = legacy_store.read_snapshot()
            self.assertEqual(next(p for p in config["profiles"]
                                  if p["id"] == pid)["project_name"], "Hadalis Cloud")
            self.assertEqual(managed_tasks._ensure_selector(), managed_tasks.SELECTOR_ID)
            config, _, _ = legacy_store.read_snapshot()
            selector = next(p for p in config["profiles"]
                            if p["id"] == managed_tasks.SELECTOR_ID)
            self.assertEqual(selector["project_name"], "Automatic Alis")
            def preserve_selector(config, state):
                next(p for p in config["profiles"]
                     if p["id"] == managed_tasks.SELECTOR_ID)["project_name"] = "Other Project"
            legacy_store.change(preserve_selector)
            managed_tasks._ensure_selector()
            config, _, _ = legacy_store.read_snapshot()
            selector = next(p for p in config["profiles"]
                            if p["id"] == managed_tasks.SELECTOR_ID)
            self.assertEqual(selector["project_name"], "Other Project")

    def test_restored_scheduler_defaults_stopped_without_legacy_replay(self):
        profile = legacy_model.default_profile()
        self.assertFalse(profile["enabled"])
        self.assertEqual(profile["mode"], "manual")
        with tempfile.TemporaryDirectory() as tmp, patch.object(
                legacy_store, "state_dir", return_value=Path(tmp)):
            state = legacy_store.default_state(legacy_model.default_config())
            self.assertEqual(state["profiles"][profile["id"]]["desired"], "stopped")
            # A saved connector block is deliberately retained as paused;
            # this fixture must never read the owner's real legacy state.
            (Path(tmp) / "chat-bridge.json").write_text(json.dumps({
                "state": "connector_blocked"}))
            blocked = legacy_store.default_state(legacy_model.default_config())
            restored = blocked["profiles"][profile["id"]]
            self.assertEqual(restored["desired"], "paused")
            self.assertEqual(restored["status"], "connector_blocked")
            self.assertEqual(restored["loop_state"], "connector_blocked")

    def test_unattested_transport_blocks_queue_start_without_state_mutation(self):
        # Real production must leave the owner's pending queue intact even
        # after a user presses Start. Synthetic success fixtures are isolated
        # in other tests by explicitly patching the attestation gate.
        readiness = managed_tasks.transport_gate.readiness()
        self.assertFalse(readiness["transport_ready"])
        self.assertFalse(readiness["unattended_submission_authorized"])
        self.assertFalse(readiness["server_final_receipt_verified"])
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {
                "XDG_STATE_HOME": tmp + "/state",
                "XDG_CONFIG_HOME": tmp + "/config"}):
            queue.prepare("AUTO-R01", resolver=lambda _: TASK)
            before = queue._load()
            config_before, state_before, _ = legacy_store.read_snapshot()
            with patch.object(legacy_control, "service_states",
                              side_effect=AssertionError("NO_SERVICE_CALL")):
                with self.assertRaisesRegex(taskflow.TaskError,
                                            "CHATGPT_PROJECT_SERVER_RECEIPT_UNATTESTED"):
                    managed_tasks.start_ordered_queue(approved=True)
            self.assertEqual(before, queue._load())
            self.assertFalse(queue._load()["approved_start"])
            self.assertEqual(config_before, legacy_store.read_snapshot()[0])
            self.assertEqual(state_before, legacy_store.read_snapshot()[1])
            self.assertEqual(managed_tasks.reconcile_once()["state"], "prepared")
            self.assertEqual(queue._load(), before)
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {
                "XDG_STATE_HOME": tmp + "/state",
                "XDG_CONFIG_HOME": tmp + "/config"}):
            queue.prepare("AUTO-R01", mode="cloud", resolver=lambda _: TASK)
            before = queue._load()
            with patch.object(legacy_control, "service_states",
                              side_effect=AssertionError("NO_SERVICE_CALL")):
                with self.assertRaisesRegex(taskflow.TaskError,
                                            "CHATGPT_PROJECT_SERVER_RECEIPT_UNATTESTED"):
                    managed_tasks.start_cloud_queue(approved=True)
            self.assertEqual(queue._load(), before)
            self.assertEqual(managed_tasks.reconcile_once()["state"], "prepared")
            self.assertEqual(queue._load(), before)

    @patch.object(managed_tasks.transport_gate, "require_ready", return_value=None)
    def test_ordered_queue_launch_and_native_receipt_advances_without_second_scheduler(self, _simulated_verified_transport):
        other = {**TASK, "code": "ABYSS-R09", "issue_number": 191}
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {
                "XDG_STATE_HOME": tmp + "/state", "XDG_CONFIG_HOME": tmp + "/config"}):
            queue.prepare("AUTO-R01; ABYSS-R09", resolver=lambda c:
                          TASK if c == "AUTO-R01" else other)
            with self.assertRaisesRegex(taskflow.TaskError, "approval"):
                managed_tasks.start_ordered_queue()
            self.assertEqual(queue.view()["state"], "prepared")
            service_states = {"bridge": {"state": "inactive"},
                              "worker": {"state": "inactive"}}
            with patch.object(legacy_control, "service_states", return_value=service_states), \
                 patch.object(legacy_control, "profile_action", return_value={"ok": True}) as start:
                result = managed_tasks.start_ordered_queue(approved=True)
            self.assertEqual(result["task"]["code"], "AUTO-R01")
            start.assert_called_once_with("start", result["profile_id"])
            self.assertEqual(queue.view()["active"]["code"], "AUTO-R01")
            self.assertTrue(queue._load()["approved_start"])
            config, runtime, issues = legacy_store.read_snapshot()
            profile = next(p for p in config["profiles"] if p["id"] == result["profile_id"])
            self.assertEqual(managed_tasks.reference(profile), ("llocphann/Alis", "AUTO-R01"))
            self.assertEqual(profile["prompt"], "Taskflow dynamic initial prompt")
            self.assertIn("AUTO-R01", legacy_model.effective_prompt(profile, "initial"))
            self.assertNotIn(TASK["issue_url"], profile["prompt"])
            self.assertIn("ALIS_LOOP", legacy_model.effective_prompt(profile, "continuation"))
            self.assertEqual(managed_tasks.reconcile_once()["state"], "active")
            def completed(config, state):
                item = state["profiles"][result["profile_id"]]
                item.update(status="completed", last_success="DONE",
                            pending=None, job_id=None,
                            response_message_id="answer-uuid",
                            session={"conversation_id": "verified-chat",
                                     "project_id": "verified-project"})
            legacy_store.change(completed)
            switched = managed_tasks.reconcile_once()
            self.assertEqual(switched["state"], "scheduled")
            self.assertEqual(switched["selected"]["code"], "ABYSS-R09")
            first = taskflow.load_task("AUTO-R01")
            self.assertEqual(first["status"], "awaiting_owner")
            self.assertEqual(first["delivery"]["message_id"], "answer-uuid")
            self.assertEqual(queue.view()["items"][0]["state"], "awaiting_owner")
            second_id = managed_tasks.profile_id("llocphann/Alis", "ABYSS-R09")
            _, state, _ = legacy_store.read_snapshot()
            self.assertEqual(state["profiles"][second_id]["desired"], "run")
            self.assertEqual(state["profiles"][second_id]["request"], "initial")
            self.assertEqual(managed_tasks.reconcile_once()["state"], "active")
            # The next task can run, but the first Issue is not owner-verified.
            self.assertNotEqual(first["status"], "completed")

    @patch.object(managed_tasks.transport_gate, "require_ready", return_value=None)
    def test_cloud_choice_uses_native_assistant_receipt_and_serially_reselects(self, _simulated_verified_transport):
        other = {**TASK, "code": "ABYSS-R09", "issue_number": 151}
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {
                "XDG_STATE_HOME": tmp + "/state", "XDG_CONFIG_HOME": tmp + "/config"}):
            queue.prepare("AUTO-R01; ABYSS-R09", mode="cloud",
                          resolver=lambda c: TASK if c == "AUTO-R01" else other)
            with patch.object(legacy_control, "service_states", return_value={
                    "bridge": {"state": "inactive"},
                    "worker": {"state": "inactive"}}), \
                 patch.object(legacy_control, "profile_action", return_value={"ok": True}):
                started = managed_tasks.start_cloud_queue(approved=True)
            self.assertEqual(started["profile_id"], managed_tasks.SELECTOR_ID)
            self.assertEqual(queue.view()["state"], "prepared")
            _, runtime, _ = legacy_store.read_snapshot()
            selector_profile = next(p for p in legacy_store.read_snapshot()[0]["profiles"]
                                    if p["id"] == managed_tasks.SELECTOR_ID)
            self.assertIn("ALIS_TASK_CHOICE", legacy_model.effective_prompt(selector_profile, "initial"))
            def finished(message_id, conversation="chat-selector-1"):
                def update(c, state):
                    item = state["profiles"][managed_tasks.SELECTOR_ID]
                    item.update(status="completed", last_success="DONE", desired="stopped",
                                pending=None, job_id=None, run_active=False,
                                response_message_id=message_id,
                                session={"conversation_id": conversation, "project_id": "project"})
                legacy_store.change(update)
            def receipt(message_id, code, conversation="chat-selector-1"):
                import json
                folder = legacy_store.state_dir() / "responses" / managed_tasks.SELECTOR_ID
                folder.mkdir(parents=True, exist_ok=True)
                legacy_store._write(folder / ("user-"+message_id+".json"), {
                    "conversation_id": conversation,
                    "response": {"message_id": message_id,
                                 "text": "Evidence reviewed.\nALIS_TASK_CHOICE: " + code +
                                         "\nALIS_LOOP:DONE"}})
            finished("assistant-message-0001")
            with self.assertRaisesRegex(taskflow.TaskError, "receipt"):
                managed_tasks.reconcile_once()
            self.assertEqual(queue.view()["state"], "prepared")
            receipt("assistant-message-0001", "ABYSS-R09")
            accepted = managed_tasks.reconcile_once()
            self.assertEqual(accepted["state"], "task_scheduled")
            self.assertEqual(queue.view()["active"]["code"], "ABYSS-R09")
            selected_pid = managed_tasks.profile_id("llocphann/Alis", "ABYSS-R09")
            def complete_selected(c, state):
                item = state["profiles"][selected_pid]
                item.update(status="completed", last_success="DONE", pending=None, job_id=None,
                            response_message_id="answer-0002", run_active=False,
                            session={"conversation_id": "chat-work", "project_id": "project"})
            legacy_store.change(complete_selected)
            advanced = managed_tasks.reconcile_once()
            self.assertEqual(advanced["state"], "selecting")
            self.assertEqual(queue.view()["state"], "waiting")
            _, runtime, _ = legacy_store.read_snapshot()
            self.assertEqual(runtime["profiles"][managed_tasks.SELECTOR_ID]["request"], "new")
            self.assertEqual(runtime["profiles"][managed_tasks.SELECTOR_ID]["desired"], "run")
            # The consumed decision cannot be replayed while awaiting new chat.
            self.assertEqual(managed_tasks.reconcile_once()["state"], "selecting")
            finished("assistant-message-0003", "chat-selector-2")
            receipt("assistant-message-0003", "AUTO-R01", "chat-selector-2")
            self.assertEqual(managed_tasks.reconcile_once()["selected"]["code"], "AUTO-R01")
            self.assertEqual(queue.view()["items"][0]["state"], "active")
            self.assertEqual(queue.view()["items"][1]["state"], "awaiting_owner")

    @patch.object(managed_tasks.transport_gate, "require_ready", return_value=None)
    def test_cloud_choice_rejects_missing_or_multiple_choices(self, _simulated_verified_transport):
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {
                "XDG_STATE_HOME": tmp + "/state", "XDG_CONFIG_HOME": tmp + "/config"}):
            queue.prepare("AUTO-R01", mode="cloud", resolver=lambda _: TASK)
            queue.approve_cloud_start()
            managed_tasks._ensure_selector()
            def finish(c, state):
                item = state["profiles"][managed_tasks.SELECTOR_ID]
                item.update(status="completed", last_success="DONE",
                            response_message_id="assistant-result-id",
                            session={"conversation_id": "chat-c", "project_id": "p"})
            legacy_store.change(finish)
            folder = legacy_store.state_dir() / "responses" / managed_tasks.SELECTOR_ID
            folder.mkdir(parents=True)
            for text in ("HADALIS_TASK_CHOICE: AUTO-R01\nHADALIS_TASK_CHOICE: AUTO-R01\nHADALIS_LOOP:DONE",
                         "HADALIS_TASK_CHOICE: NOTHERE-R99\nHADALIS_LOOP:DONE"):
                legacy_store._write(folder / "receipt.json", {
                    "conversation_id": "chat-c",
                    "response": {"message_id": "assistant-result-id", "text": text}})
                if text.count("HADALIS_TASK_CHOICE") > 1:
                    with self.assertRaisesRegex(taskflow.TaskError, "ambiguous"):
                        managed_tasks.reconcile_once()
                else:
                    with self.assertRaisesRegex(taskflow.TaskError, "pending tasks"):
                        managed_tasks.reconcile_once()
            self.assertEqual(queue.view()["state"], "prepared")

    def test_legacy_restore_gate_parks_unresolved_without_replaying(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {
                "XDG_STATE_HOME": tmp + "/state", "XDG_CONFIG_HOME": tmp + "/config"}):
            def previous(c, state):
                pid = c["profiles"][0]["id"]
                c["profiles"][0]["enabled"] = True
                state["profiles"][pid].update(desired="run", status="thinking",
                    pending={"user_message_id": "old-message", "phase": "dispatching"})
            legacy_store.change(previous)
            result = managed_tasks.quarantine_legacy_profiles_once()
            self.assertEqual(result["paused"], 1)
            pid = legacy_model.DEFAULT_ID
            _, state, _ = legacy_store.read_snapshot()
            self.assertEqual(state["profiles"][pid]["desired"], "paused")
            self.assertEqual(state["profiles"][pid]["pending"]["user_message_id"], "old-message")
            def approved(c, state):
                state["profiles"][pid]["desired"] = "run"
            legacy_store.change(approved)
            self.assertTrue(managed_tasks.quarantine_legacy_profiles_once()["already_gated"])
            self.assertEqual(legacy_store.read_snapshot()[1]["profiles"][pid]["desired"], "run")

    @patch.object(managed_tasks.transport_gate, "require_ready", return_value=None)
    def test_ordered_queue_refuses_dispatch_with_missing_worker_service(self, _simulated_verified_transport):
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {
                "XDG_STATE_HOME": tmp + "/state", "XDG_CONFIG_HOME": tmp + "/config"}):
            queue.prepare("AUTO-R01", resolver=lambda _: TASK)
            with patch.object(legacy_control, "service_states", return_value={
                    "bridge": {"state": "inactive"},
                    "worker": {"state": "unavailable"}}):
                with self.assertRaisesRegex(taskflow.TaskError, "backend not installed"):
                    managed_tasks.start_ordered_queue(approved=True)
            self.assertEqual(queue.view()["state"], "prepared")

    def test_settings_waits_for_stream_finished_before_parsing_cli_json(self):
        qml = (Path(__file__).resolve().parents[1] /
               "modules/settings/AutomationTaskConfig.qml").read_text()
        self.assertIn("onStreamFinished: root._automationStdoutClosed", qml)
        self.assertIn("root._finishAutomationWhenReady(name)", qml)
        self.assertIn("if (!entry || !entry.exited || !entry.closed)", qml)
        self.assertIn("Automation helper returned no output", qml)
        self.assertIn("Backend status unknown", qml)
        self.assertIn("GitHub token status unknown", qml)
        self.assertIn("root.backendStatusKnown && !root.backendInstalled", qml)
        self.assertIn("root.backendTransportReady = report.transport_ready === true", qml)
        self.assertIn("&& report.unattended_submission_authorized === true", qml)
        self.assertIn("&& ((root.backendTransportReady", qml)
        self.assertIn("root.uiQueueStartAvailable", qml)
        self.assertIn("root.uiQueueStartConfirmation", qml)
        self.assertIn('"start-ui-queue", "--approve", "--accept-ui-only-receipts"', qml)
        self.assertIn("automatic ChatGPT submission not authorized", qml)
        self.assertIn("CHATGPT_PROJECT_SERVER_RECEIPT_UNATTESTED", qml)
        self.assertIn("Automation modules missing from installed Alis; update runtime", qml)
        self.assertEqual(qml.count("onStreamFinished: root._automationStdoutClosed"), 9)
        self.assertEqual(qml.count("JSON.parse("), 1)
        for process in ("queueProcess", "githubStatusProcess", "backendStatusProcess",
                        "taskStatusProcess", "activityProcess", "cleanupProcess"):
            self.assertIn("root._automationExited(\"" + process + "\"", qml)
            self.assertIn("root._handle_" + process + "(entry.exitCode)", qml)

    def test_packaged_automation_runtime_imports_from_installed_layout(self):
        """Regression for QML installed while its Python package was omitted.

        Materialize only files *listed by the real runtime payload policy* to
        emulate a fresh package. Never copy source-only code outside manifest.
        """
        import os
        import shutil
        import subprocess
        root = Path(__file__).resolve().parents[1]
        payload = subprocess.run(
            ["python3", str(root / "sdata/lib/runtime-payload.py"),
             "list", "--root", str(root)],
            capture_output=True, text=True, check=True, timeout=30,
        )
        paths = set(payload.stdout.splitlines())
        required = {
            "scripts/alis-automation-task.py",
            "scripts/install-hadalis-automation.py",
            "automation/__init__.py",
            "automation/taskflow.py",
            "automation/credentials.py",
            "automation/queue.py",
            "automation/managed_tasks.py",
            "automation/lifecycle.py",
            "automation/rotation.py",
            "automation/activity.py",
            "automation/manager/__init__.py",
            "automation/manager/control.py",
            "automation/manager/store.py",
            "automation/manager/model.py",
            "automation/chat_bridge/__init__.py",
            "automation/chat_bridge/controller.py",
            "automation/worker/__init__.py",
            "automation/worker/runner.py",
        }
        self.assertEqual(required - paths, set(), "missing packaged Automation modules")
        self.assertNotIn("scripts/test-automation-taskflow.py", paths)
        self.assertNotIn("automation/__pycache__/taskflow.cpython-312.pyc", paths)
        with tempfile.TemporaryDirectory() as tmp:
            installed = Path(tmp) / "installed"
            for name in paths:
                if name.startswith("automation/") and name.endswith(".py"):
                    dest = installed / name
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(root / name, dest)
            script = installed / "scripts/alis-automation-task.py"
            script.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(root / "scripts/alis-automation-task.py", script)
            env = dict(os.environ, XDG_STATE_HOME=tmp + "/state",
                       XDG_CONFIG_HOME=tmp + "/config", PYTHONPATH="")
            for action in [
                ["queue-status"],
                ["github-token-status", "llocphann/Alis"],
                ["backend-status"],
            ]:
                proc = subprocess.run(
                    ["python3", "-I", str(script), *action],
                    cwd=installed, env=env, capture_output=True, text=True,
                    check=False, timeout=15,
                )
                self.assertEqual(proc.returncode, 0,
                                 str(action) + ": " + proc.stderr[-700:])
                self.assertFalse(proc.stderr.strip(), action)
                self.assertTrue(json.loads(proc.stdout)["ok"], action)

    def test_qml_cli_json_contract_in_real_subprocess(self):
        """Every read-only Settings action must produce exactly one JSON object.

        Catches import failures and stdout-empty errors masked by JSON.parse.
        """
        import subprocess
        import os
        root = Path(__file__).resolve().parents[1]
        cli = root / "scripts/alis-automation-task.py"
        with tempfile.TemporaryDirectory() as tmp:
            env = dict(os.environ, XDG_STATE_HOME=tmp + "/state",
                       XDG_CONFIG_HOME=tmp + "/config")
            for command in [
                ["queue-status"],
                ["github-token-status", "llocphann/Alis"],
                ["backend-status"],
                ["cleanup"],
            ]:
                completed = subprocess.run(
                    ["python3", str(cli), *command], cwd=root, env=env,
                    capture_output=True, text=True, timeout=12, check=False)
                self.assertEqual(completed.returncode, 0,
                                 f"{command}: {completed.stderr[:500]}")
                self.assertFalse(completed.stderr.strip(), command)
                data = json.loads(completed.stdout)
                self.assertTrue(data["ok"], command)
                self.assertEqual(len(completed.stdout.splitlines()), 1, command)
            failed = subprocess.run(["python3", str(cli),
                                      "queue-prepare", "INVALID!", "--mode", "ordered"],
                                     cwd=root, env=env, capture_output=True,
                                     text=True, timeout=10, check=False)
            self.assertNotEqual(failed.returncode, 0)
            self.assertFalse(failed.stderr.strip())
            self.assertFalse(json.loads(failed.stdout)["ok"])

    def test_lookup_code_and_exact_reference(self):
        task = taskflow.resolve("AUTO-R01", api)
        self.assertEqual(task["repository"], "llocphann/Alis")
        self.assertEqual(task["comments"][0]["id"], 5)
        self.assertEqual(taskflow.resolve("llocphann/Alis#104", api)["code"], "AUTO-R01")
        self.assertIn("untrusted data", taskflow.internal_prompt(task))

    def test_reject_ambiguous_and_absent(self):
        def ambiguous(endpoint):
            if endpoint.startswith("/search/issues?"):
                return {"total_count": 1, "items": [{"number": 104, "title": "[AUTO-R01] Duplicate"}]}
            return api(endpoint)
        with self.assertRaisesRegex(taskflow.TaskError, "Ambiguous"):
            taskflow.resolve("AUTO-R01", ambiguous)
        with self.assertRaisesRegex(taskflow.TaskError, "No matching"):
            taskflow.resolve("BRAND-F99", lambda e: {"total_count": 0, "items": []})
        with self.assertRaises(taskflow.TaskError):
            taskflow.resolve("other/repo#123", api)

    def test_prepare_is_durable_and_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"XDG_STATE_HOME": tmp}):
            task = taskflow.resolve("AUTO-R01", api)
            first = taskflow.intake(task)
            second = taskflow.intake(task)
            self.assertFalse(first["duplicate"])
            self.assertTrue(second["duplicate"])
            path = Path(tmp) / "hadalis-automation/taskflow/tasks/Alis/AUTO-R01.json"
            persisted = json.loads(path.read_text())
            self.assertEqual(persisted["status"], "prepared")
            self.assertEqual(persisted["schema"], taskflow.TASK_SCHEMA)
            self.assertEqual(list(path.parent.glob("AUTO-R01*.json")), [path])
            self.assertFalse(persisted["scheduler_dispatched"])

    def test_bundle_allowlist_hash_and_continuation(self):
        payload = {"schema": "alis.local-handoff.v1", "task": TASK,
                   "commands": [["python3", "scripts/test-automation-taskflow.py"]],
                   "next_prompt": "Continue from verified test receipt JOB-1.",
                   "checkpoint": "Cloudbot authored"}
        bundle = taskflow.package(payload)
        self.assertEqual(taskflow.verify(bundle), bundle)
        self.assertEqual(taskflow.continuation(bundle, {"sha256": bundle["sha256"], "state": "passed"}),
                         payload["next_prompt"])
        with self.assertRaises(taskflow.TaskError):
            taskflow.continuation(bundle, {"sha256": bundle["sha256"], "state": "started"})
        corrupted = dict(bundle)
        corrupted["sha256"] = "0" * 64
        with self.assertRaisesRegex(taskflow.TaskError, "integrity"):
            taskflow.verify(corrupted)
        payload["commands"] = [["bash", "-c", "touch /tmp/danger"]]
        with self.assertRaisesRegex(taskflow.TaskError, "Unapproved"):
            taskflow.package(payload)

    def test_execution_pin_keeps_intake_identity_and_authentic_receipt(self):
        from automation import lifecycle
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"XDG_STATE_HOME": tmp + "/state"}):
            checkout = Path(tmp) / "checkout"
            subprocess.run(["git", "init", "-q", str(checkout)], check=True)
            def commit(message):
                subprocess.run(["git", "-C", str(checkout), "-c", "user.name=Fixture",
                                "-c", "user.email=fixture@example.invalid", "commit",
                                "--allow-empty", "-qm", message], check=True)
                return subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
            base = commit("intake")
            implementation = commit("implementation")
            task = {**TASK, "base_sha": base}
            taskflow.intake(task)
            payload = {"schema": "alis.local-handoff.v1", "task": task,
                       "execution_sha": implementation, "commands": [["git", "diff", "--check"]],
                       "checkpoint": "fixture", "next_prompt": "Continue after this exact implementation was tested."}
            bundle = taskflow.package(payload)
            legacy = taskflow.package({k: v for k, v in payload.items() if k != "execution_sha"})
            self.assertNotEqual(bundle["sha256"], legacy["sha256"])
            taskflow.save_handoff(task["code"], bundle)
            receipt = taskflow.run_task(task["code"], checkout, approved=True)
            self.assertEqual(receipt["source_sha"], implementation)
            record = taskflow.load_task(task["code"])
            self.assertEqual(record["task"]["base_sha"], base)
            self.assertEqual(lifecycle._verified_local_receipt(record), bundle)
            record["latest_receipt"]["source_sha"] = base
            with self.assertRaises(taskflow.TaskError):
                lifecycle._verified_local_receipt(record)
            bad = taskflow.package({**payload, "task": {**task, "base_sha": "0" * 40}})
            with patch.object(taskflow, "_bounded_test") as child:
                with self.assertRaisesRegex(taskflow.TaskError, "descended"):
                    taskflow.run_local(bad, checkout, approved=True)
                child.assert_not_called()
            for invalid in [None, {}, "main", "0" * 40 + "\n"]:
                with self.assertRaises(taskflow.TaskError):
                    taskflow.package({**payload, "execution_sha": invalid})

    def test_previous_partial_intake_is_quarantined(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"XDG_STATE_HOME": tmp}):
            task = taskflow.resolve("AUTO-R01", api)
            first = taskflow.intake(task)
            file = Path(tmp) / "hadalis-automation/taskflow/tasks/Alis/AUTO-R01.json"
            file.write_text("{incomplete")
            with self.assertRaisesRegex(taskflow.TaskError, "incomplete"):
                taskflow.intake(task)

    def test_redaction_and_bounded_subprocess(self):
        with tempfile.TemporaryDirectory() as tmp:
            # This test runs the allowlisted child implementation with a harmless
            # python command, not from any Issue or generated manifest.
            test = taskflow._bounded_test(["python3", "-c", "print('ghp_' + 'a'*32)"], Path(tmp))
            self.assertEqual(test["exit_code"], 0)
            self.assertIn("[REDACTED]", test["output_excerpt"])
            self.assertNotIn("ghp_", test["output_excerpt"])

    def test_receipt_roundtrip_and_no_reexecution(self):
        with tempfile.TemporaryDirectory() as tmp:
            checkout = Path(tmp) / "checkout"
            checkout.mkdir()
            subprocess.run(["git", "init", "-q", str(checkout)], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(["git", "-C", str(checkout), "-c", "user.name=Fixture",
                            "-c", "user.email=fixture@example.invalid",
                            "commit", "--allow-empty", "-qm", "fixture"], check=True)
            sha = subprocess.check_output(["git", "-C", str(checkout),
                                           "rev-parse", "HEAD"], text=True).strip()
            task = {**TASK, "base_sha": sha}
            payload = {"schema": "alis.local-handoff.v1", "task": task,
                       "commands": [["git", "diff", "--check"]],
                       "next_prompt": "Cloudbot: continue with verified receipt.",
                       "checkpoint": "fixture"}
            bundle = taskflow.package(payload)
            with patch.dict("os.environ", {"XDG_STATE_HOME": str(Path(tmp) / "state")}):
                first = taskflow.run_local(bundle, checkout, approved=True)
                self.assertEqual(first["state"], "passed")
                self.assertEqual(first["steps"][0]["exit_code"], 0)
                self.assertTrue(first["continuation_ready"])
                second = taskflow.run_local(bundle, checkout, approved=True)
                self.assertTrue(second["already_recorded"])
                self.assertFalse(second["replayed"])
                self.assertEqual(taskflow.continuation(bundle, first),
                                 payload["next_prompt"])

    def test_single_task_file_embeds_prompts_scripts_and_reports(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"XDG_STATE_HOME": tmp}):
            task = taskflow.resolve("AUTO-R01", api)
            taskflow.intake(task)
            payload = {"schema": "alis.local-handoff.v1", "task": task,
                       "commands": [["git", "diff", "--check"]],
                       "next_prompt": "Cloudbot continues from acknowledged local receipt.",
                       "checkpoint": "Fixture checkpoint",
                       "scripts": [{"name": "fixture.py", "content": "print('draft')",
                                    "purpose": "Review only, never execute directly"}]}
            bundle = taskflow.package(payload)
            saved = taskflow.save_handoff("AUTO-R01", bundle)
            self.assertFalse(saved["duplicate"])
            record = taskflow.load_task("AUTO-R01")
            self.assertEqual(record["handoff"]["payload"]["scripts"][0]["content"], "print('draft')")
            self.assertEqual(record["handoff"]["payload"]["next_prompt"], payload["next_prompt"])
            self.assertTrue(taskflow.save_handoff("AUTO-R01", bundle)["duplicate"])
            path = Path(saved["task_file"])
            self.assertEqual(len(list(path.parent.glob("*.json"))), 1)
            for n in range(20):
                taskflow.append_report("AUTO-R01", "test", "log "+str(n), now=100+n)
            self.assertEqual(len(taskflow.load_task("AUTO-R01")["reports"]), taskflow.REPORT_LIMIT)
            self.assertEqual(taskflow.cleanup(dry_run=False, now=100000)["deleted_task_files"], 0)
            self.assertTrue(path.exists())

    def test_retention_guards_and_acknowledged_cleanup(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"XDG_STATE_HOME": tmp}):
            task = taskflow.resolve("AUTO-R01", api)
            taskflow.intake(task)
            path = Path(tmp) / "hadalis-automation/taskflow/tasks/Alis/AUTO-R01.json"
            record = taskflow.load_task("AUTO-R01")
            record["status"] = "retired"
            record["delivery_acknowledged_unix"] = 1000
            record["handoff"] = taskflow.package({
                "schema": "alis.local-handoff.v1", "task": task,
                "commands": [["git", "diff", "--check"]],
                "next_prompt": "Continue only after acknowledged receipt.",
                "checkpoint": "",
            })
            record["reports"] = [{"at_unix": 1000, "kind": "test", "text": "report"}]
            taskflow._save_task(record)
            self.assertEqual(taskflow.cleanup(now=1000+taskflow.DETAIL_TTL+1)["retired_payloads"], 1)
            self.assertTrue(taskflow.load_task("AUTO-R01")["cloud_prompt"])
            self.assertEqual(taskflow.cleanup(dry_run=False, now=1000+taskflow.DETAIL_TTL+1)["retired_payloads"], 1)
            retained = taskflow.load_task("AUTO-R01")
            self.assertIsNone(retained["cloud_prompt"])
            self.assertIsNone(retained["handoff"])
            self.assertEqual(retained["reports"], [])
            self.assertTrue(retained["retired_handoff"]["id"].startswith("JOB-"))
            retained["unresolved"] = True
            taskflow._save_task(retained)
            self.assertEqual(taskflow.cleanup(dry_run=False, now=1000+taskflow.TERMINAL_TTL+1)["deleted_task_files"], 0)
            retained["unresolved"] = False
            taskflow._save_task(retained)
            self.assertEqual(taskflow.cleanup(dry_run=False, now=1000+taskflow.TERMINAL_TTL+1)["deleted_task_files"], 1)
            self.assertFalse(path.exists())

    def test_acked_receipt_compacts_without_losing_replay_guard(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"XDG_STATE_HOME": tmp}):
            task = taskflow.resolve("AUTO-R01", api)
            taskflow.intake(task)
            record = taskflow.load_task("AUTO-R01")
            record["status"] = "completed"
            record["delivery_acknowledged_unix"] = 1000
            job_id = "JOB-" + "a" * 24
            digest = "c" * 64
            record["latest_receipt"] = {"id": job_id, "sha256": digest,
                                        "state": "passed", "source_sha": task["base_sha"]}
            taskflow._save_task(record)
            receipt_dir = Path(tmp) / "hadalis-automation/taskflow/receipts"
            receipt_dir.mkdir(parents=True)
            path = receipt_dir / (job_id + ".json")
            original = {"id": job_id, "sha256": digest, "state": "passed",
                        "source_sha": task["base_sha"],
                        "steps": [{"argv": ["git", "diff", "--check"],
                                   "exit_code": 0, "output_excerpt": "old report body"}]}
            taskflow._atomic_json(path, original)
            preview = taskflow.cleanup(now=1000+taskflow.DETAIL_TTL+1)
            self.assertEqual(preview["compacted_receipts"], 1)
            self.assertIn("output_excerpt", json.loads(path.read_text())["steps"][0])
            done = taskflow.cleanup(dry_run=False, now=1000+taskflow.DETAIL_TTL+1)
            self.assertEqual(done["compacted_receipts"], 1)
            after = json.loads(path.read_text())
            self.assertEqual(after["id"], job_id)
            self.assertEqual(after["sha256"], digest)
            self.assertNotIn("output_excerpt", after["steps"][0])
            self.assertEqual(len(after["steps"][0]["output_sha256"]), 64)
            self.assertEqual(taskflow.cleanup(dry_run=False, now=1000+taskflow.DETAIL_TTL+1)["compacted_receipts"], 0)

    def test_untrusted_inline_script_cannot_execute_directly(self):
        task = dict(TASK)
        payload = {"schema": "alis.local-handoff.v1", "task": task,
                   "commands": [["git", "diff", "--check"]],
                   "next_prompt": "Continue after local receipt is confirmed.",
                   "checkpoint": "", "scripts": [{"name": "../escape.sh", "content": "echo unsafe", "purpose": "bad"}]}
        with self.assertRaisesRegex(taskflow.TaskError, "script draft"):
            taskflow.package(payload)
        payload["scripts"][0]["name"] = "only-review.sh"
        bundle = taskflow.package(payload)
        self.assertEqual(taskflow.verify(bundle), bundle)
        payload["commands"] = [["bash", "only-review.sh"]]
        with self.assertRaisesRegex(taskflow.TaskError, "Unapproved"):
            taskflow.package(payload)


    def test_github_keyring_stdin_and_scoped_credential_helper(self):
        from unittest.mock import Mock
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"XDG_STATE_HOME": tmp}):
            fake = Mock(return_value=type("Done", (), {"returncode": 0, "stdout": "", "stderr": ""})())
            with patch.object(credentials.shutil, "which", return_value="/usr/bin/secret-tool"), \
                 patch.object(credentials.subprocess, "run", fake):
                saved = credentials.save("llocphann/Alis", "ghp_example123")
                self.assertTrue(saved["saved"])
                self.assertEqual(fake.call_args.kwargs["input"], "ghp_example123")
                self.assertNotIn("ghp_example123", str(fake.call_args.args))
                marker = credentials._metadata_path().read_text()
                self.assertNotIn("ghp_example123", marker)
                self.assertTrue(credentials.status("llocphann/Alis")["saved"])
                credentials.clear("llocphann/Alis")
                self.assertFalse(credentials.status("llocphann/Alis")["saved"])
            with self.assertRaisesRegex(credentials.CredentialError, "one nonempty"):
                credentials.save("llocphann/Alis", "token\nbad")
            with self.assertRaises(credentials.CredentialError):
                credentials.save("other/repo", "token")
            with patch.object(credentials, "_lookup", return_value="ghp_for_git_only"):
                self.assertEqual(credentials.git_helper("llocphann/Alis", "get",
                    "protocol=https\nhost=github.com\npath=other/repo\n"), "")
                result = credentials.git_helper("llocphann/Alis", "get",
                    "protocol=https\nhost=github.com\npath=llocphann/Alis.git\n")
                self.assertIn("password=ghp_for_git_only", result)
                self.assertEqual(credentials.git_helper("llocphann/Alis", "store",
                    "protocol=https\nhost=github.com\npath=llocphann/Alis\n"), "")

    def test_token_and_rotation_settings_exposed_without_prompt_fields(self):
        qml = (Path(__file__).resolve().parents[1] /
               "modules/settings/AutomationTaskConfig.qml").read_text()
        self.assertIn("automationGithubToken", qml)
        self.assertIn("TextInput.Password", qml)
        self.assertIn("githubSecretProcess.write(root.pendingSecretInput)", qml)
        self.assertIn("Chat rollover", qml)
        self.assertNotIn("automationRotationPrompt", qml)
        self.assertNotIn("automationContinuationPrompt", qml)
        cli = (Path(__file__).resolve().parents[1] /
               "scripts/alis-automation-task.py").read_text()
        self.assertIn("sys.stdin.read(513)", cli)
        self.assertIn("github-token-save", cli)

    def test_task_intake_reads_scoped_token_without_exposing_secret(self):
        import io
        requests = []
        class Response:
            def __enter__(self):
                return io.BytesIO(b'{"ok":true}')
            def __exit__(self, *args):
                return False
        def capture(request, timeout):
            requests.append(request)
            return Response()
        with patch.dict("os.environ", {"GH_TOKEN": "", "GITHUB_TOKEN": ""}), \
             patch.object(credentials, "status", return_value={"saved": True}), \
             patch.object(credentials, "_lookup", return_value="ghp_from_secret_service"), \
             patch.object(taskflow, "urlopen", side_effect=capture):
            result = taskflow._github("/repos/llocphann/Alis/issues/104")
        self.assertTrue(result["ok"])
        self.assertEqual(len(requests), 1)
        self.assertEqual(requests[0].get_header("Authorization"), "Bearer ghp_from_secret_service")
        self.assertNotIn("ghp_from_secret_service", requests[0].full_url)

    def test_rotation_requires_authenticated_limit_and_exact_new_chat(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"XDG_STATE_HOME": tmp}):
            task = taskflow.resolve("AUTO-R01", api)
            taskflow.intake(task)
            with self.assertRaisesRegex(taskflow.TaskError, "AUTO-F01"):
                rotation.bind_managed_chat("AUTO-R01", "chat-original", "msg-start")
            with self.assertRaisesRegex(taskflow.TaskError, "did not confirm"):
                rotation.bind_managed_chat("AUTO-R01", "chat-original", "msg-start",
                                           verify_session=lambda *args: False)
            self.assertTrue(rotation.bind_managed_chat("AUTO-R01", "chat-original", "msg-start",
                      verify_session=lambda cid, mid, prompt: (
                          prompt.startswith("[$github](app://connector_76869538009648d5b282a4bb21c3d157)")
                          and "You are the Cloudbot reasoning agent." in prompt))["ok"])
            self.assertTrue(rotation.bind_managed_chat("AUTO-R01", "chat-original", "msg-start",
                      verify_session=lambda *args: False)["duplicate"])
            record = taskflow.load_task("AUTO-R01")
            record["status"] = "cloud_continuing"
            taskflow._save_task(record)
            signal = {"kind": "context_window_exhausted",
                      "conversation_id": "chat-original", "message_id": "msg-limit"}
            with self.assertRaisesRegex(taskflow.TaskError, "AUTO-F01"):
                rotation.observe_chat_limit("AUTO-R01", signal)
            with self.assertRaisesRegex(taskflow.TaskError, "not verified"):
                rotation.observe_chat_limit("AUTO-R01", signal, verify_limit=lambda *args: False)
            invalid = {**signal, "kind": "guess_from_prompt_count"}
            with self.assertRaisesRegex(taskflow.TaskError, "Unrecognized"):
                rotation.observe_chat_limit("AUTO-R01", invalid, verify_limit=lambda *args: True)
            accepted = rotation.observe_chat_limit("AUTO-R01", signal, verify_limit=lambda *args: True)
            self.assertEqual(accepted["status"], "rotation_pending")
            self.assertTrue(rotation.observe_chat_limit("AUTO-R01", signal,
                               verify_limit=lambda *args: False)["duplicate"])
            saved = taskflow.load_task("AUTO-R01")
            self.assertIn("AUTO-R01", saved["rotation"]["resume_prompt"])
            with self.assertRaisesRegex(taskflow.TaskError, "AUTO-F01"):
                rotation.acknowledge_chat_rotation("AUTO-R01", "chat-next", "msg-next")
            with self.assertRaisesRegex(taskflow.TaskError, "not authenticated"):
                rotation.acknowledge_chat_rotation("AUTO-R01", "chat-next", "msg-next",
                                                   verify_new_chat=lambda *args: False)
            rec = rotation.acknowledge_chat_rotation("AUTO-R01", "chat-next", "msg-next",
                verify_new_chat=lambda cid, mid, prompt, previous:
                    previous == "chat-original" and cid == "chat-next"
                    and mid == "msg-next" and "AUTO-R01" in prompt)
            self.assertEqual(rec["status"], "cloud_continuing")
            done = taskflow.load_task("AUTO-R01")
            self.assertIsNone(done["rotation"])
            self.assertEqual(done["managed_chat"]["conversation_id"], "chat-next")
            self.assertTrue(rotation.acknowledge_chat_rotation("AUTO-R01",
                     "chat-next", "msg-next", verify_new_chat=lambda *args: False)["duplicate"])
            signal2 = {"kind": "context_window_near_limit",
                       "conversation_id": "chat-next", "message_id": "msg-limit2"}
            self.assertEqual(rotation.observe_chat_limit("AUTO-R01", signal2,
                           verify_limit=lambda *args: True)["status"], "rotation_pending")
            record = taskflow.load_task("AUTO-R01")
            self.assertIsNotNone(record["rotation"]["resume_prompt"])

    def test_rotation_blocks_unresolved_local_receipts(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"XDG_STATE_HOME": tmp}):
            taskflow.intake(taskflow.resolve("AUTO-R01", api))
            rotation.bind_managed_chat("AUTO-R01", "chat-a", "msg-a",
                 verify_session=lambda *args: True)
            signal = {"kind": "conversation_turn_limit",
                      "conversation_id": "chat-a", "message_id": "msg-b"}
            with self.assertRaisesRegex(taskflow.TaskError, "Unacknowledged"):
                rotation.observe_chat_limit("AUTO-R01", signal, verify_limit=lambda *args: True)
            record = taskflow.load_task("AUTO-R01")
            record["status"] = "cloud_continuing"
            record["unresolved"] = True
            taskflow._save_task(record)
            with self.assertRaisesRegex(taskflow.TaskError, "Unacknowledged"):
                rotation.observe_chat_limit("AUTO-R01", signal, verify_limit=lambda *args: True)

    def test_cloud_delivery_reconciliation_and_owner_review(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"XDG_STATE_HOME": tmp}):
            task = taskflow.resolve("AUTO-R01", api)
            taskflow.intake(task)
            rotation.bind_managed_chat("AUTO-R01", "chat-1", "start-1",
                                       verify_session=lambda *args: True)
            payload = {"schema": "alis.local-handoff.v1", "task": task,
                       "commands": [["git", "diff", "--check"]],
                       "next_prompt": "Continue Cloudbot from pinned local receipt.",
                       "checkpoint": "checked output"}
            bundle = taskflow.package(payload)
            taskflow.save_handoff("AUTO-R01", bundle)
            record = taskflow.load_task("AUTO-R01")
            record["status"] = "awaiting_cloud_ack"
            record["latest_receipt"] = {"id": bundle["id"], "sha256": bundle["sha256"],
                                        "source_sha": task["base_sha"], "state": "passed"}
            taskflow._save_task(record)
            folder = taskflow.state_dir() / "receipts"
            folder.mkdir(mode=0o700, exist_ok=True)
            taskflow._atomic_json(folder / (bundle["id"] + ".json"), {
                "id": bundle["id"], "sha256": bundle["sha256"],
                "source_sha": task["base_sha"], "state": "passed", "steps": []})
            with self.assertRaisesRegex(taskflow.TaskError, "AUTO-F01"):
                lifecycle.acknowledge_cloud_delivery("AUTO-R01", "chat-1", "msg-next")
            with self.assertRaisesRegex(taskflow.TaskError, "unverified"):
                lifecycle.acknowledge_cloud_delivery(
                    "AUTO-R01", "chat-1", "msg-next", verify_transport=lambda *args: False)
            observed = []
            def verified(cid, mid, prompt):
                observed.append((cid, mid, prompt))
                return (cid == "chat-1" and mid == "msg-next"
                        and prompt == payload["next_prompt"])
            ack = lifecycle.acknowledge_cloud_delivery("AUTO-R01", "chat-1",
                                   "msg-next", verify_transport=verified)
            self.assertEqual(ack["status"], "cloud_continuing")
            self.assertTrue(lifecycle.acknowledge_cloud_delivery(
                "AUTO-R01", "chat-1", "msg-next", verify_transport=verified)["duplicate"])
            self.assertEqual(len(observed), 1)
            with self.assertRaisesRegex(taskflow.TaskError, "Different message"):
                lifecycle.acknowledge_cloud_delivery("AUTO-R01", "chat-1", "other",
                                                      verify_transport=verified)
            self.assertEqual(lifecycle.status("AUTO-R01")["status"], "cloud_continuing")
            self.assertNotIn("cloud_prompt", lifecycle.status("AUTO-R01"))
            with self.assertRaisesRegex(taskflow.TaskError, "verifier unavailable"):
                lifecycle.awaiting_owner_verification("AUTO-R01")
            with self.assertRaisesRegex(taskflow.TaskError, "not verified"):
                lifecycle.awaiting_owner_verification(
                    "AUTO-R01", verify_cloud_completion=lambda record: False)
            self.assertEqual(lifecycle.awaiting_owner_verification(
                "AUTO-R01", verify_cloud_completion=lambda record: True)["status"],
                "awaiting_owner")
            self.assertGreater(taskflow.cleanup(now=int(__import__("time").time()) +
                                               taskflow.TERMINAL_TTL+5)["preserved_unresolved"], 0)
            with self.assertRaisesRegex(taskflow.TaskError, "approval"):
                lifecycle.owner_verified("AUTO-R01")
            self.assertEqual(lifecycle.owner_verified("AUTO-R01", approval=True)["status"], "completed")
            done = taskflow.load_task("AUTO-R01")
            self.assertGreaterEqual(done["terminal_unix"], done["delivery_acknowledged_unix"])
            self.assertEqual(taskflow.cleanup(now=done["terminal_unix"] +
                                                taskflow.DETAIL_TTL - 1)["retired_payloads"], 0)

    def test_handoff_idempotency_keeps_pending_receipt(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"XDG_STATE_HOME": tmp}):
            task = taskflow.resolve("AUTO-R01", api)
            taskflow.intake(task)
            bundle = taskflow.package({"schema": "alis.local-handoff.v1", "task": task,
                                      "commands": [["git", "diff", "--check"]],
                                      "next_prompt": "Continue Cloudbot after persisted local receipt.",
                                      "checkpoint": "safe"})
            self.assertFalse(taskflow.save_handoff("AUTO-R01", bundle)["duplicate"])
            state = taskflow.load_task("AUTO-R01")
            state["status"] = "awaiting_cloud_ack"
            taskflow._save_task(state)
            self.assertTrue(taskflow.save_handoff("AUTO-R01", bundle)["duplicate"])
            self.assertEqual(taskflow.load_task("AUTO-R01")["status"], "awaiting_cloud_ack")

    def test_no_execution_without_approval_or_pinned_source(self):
        bundle = taskflow.package({"schema": "alis.local-handoff.v1", "task": TASK,
                                   "commands": [["git", "diff", "--check"]],
                                   "next_prompt": "Continue after local test evidence.", "checkpoint": ""})
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(taskflow.TaskError, "approval"):
                taskflow.run_local(bundle, Path(tmp), approved=False)
            with self.assertRaisesRegex(taskflow.TaskError, "git checkout"):
                taskflow.run_local(bundle, Path(tmp), approved=True)


if __name__ == "__main__":
    unittest.main()
