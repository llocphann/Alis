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
            path = Path(tmp) / "hadalis-automation/taskflow" / (first["intake_id"] + ".json")
            persisted = json.loads(path.read_text())
            self.assertEqual(persisted["status"], "prepared")
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
            file = Path(tmp) / "hadalis-automation/taskflow" / (first["intake_id"] + ".json")
            file.write_text("{incomplete")
            with self.assertRaisesRegex(taskflow.TaskError, "Incomplete"):
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
