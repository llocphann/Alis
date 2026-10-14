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
from automation import taskflow

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
