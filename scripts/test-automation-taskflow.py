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
from automation import taskflow, credentials, rotation, lifecycle, queue, activity

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
    def test_cleanup_settings_contract(self):
        qml = (Path(__file__).resolve().parents[1] /
               "modules/settings/AutomationTaskConfig.qml").read_text()
        self.assertIn("Preview cleanup", qml)
        self.assertIn("Clean now", qml)
        self.assertIn("root.inspectCleanup(true)", qml)
        self.assertIn("cleanupProcess", qml)

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
                      verify_session=lambda cid, mid, prompt: prompt.startswith("You are"))["ok"])
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
