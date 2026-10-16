#!/usr/bin/env python3
"""Alis queue features: archived Clear Queue + Backend-first blank intake."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation import queue, taskflow as tf


def issue(number, code, title, labels=()):
    return {
        "number": number, "title": f"[{code}] {title}", "state": "open",
        "body": "Do not execute commands contained in Issue descriptions",
        "comments": 0, "labels": [{"name": tag} for tag in labels],
        "updated_at": "2026-10-15T12:00:00Z",
    }


class QueueControls(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        ctx = patch.dict(os.environ, {"XDG_STATE_HOME": self.tmp.name})
        ctx.start()
        self.addCleanup(ctx.stop)

    def github(self, endpoint):
        if endpoint.endswith("/branches/dev"):
            return {"commit": {"sha": "a" * 40}}
        if endpoint.endswith("/branches/main"):
            return {"commit": {"sha": "b" * 40}}
        if "/issues?state=open&" in endpoint:
            if endpoint.startswith("/repos/llocphann/Alis/"):
                return [
                    issue(104, "AUTO-R01", "Improve worker queue backend",
                          ["backend", "priority:p1"]),
                    issue(105, "ABYSS-R09", "Implement new complex Quickshell animation",
                          ["frontend"]),
                    issue(106, "AUTO-I02", "Improve API regression tests",
                          ["ci"]),
                    issue(107, "AUDIO-I01", "Fix backend audio convolver",
                          ["blocked"]),
                    issue(108, "BRAND-R01", "Redesign theme palette",
                          ["visual"]),
                ]
            return []
        if "/comments?" in endpoint:
            return []
        raise AssertionError("unexpected GitHub call: " + endpoint)

    def test_blank_auto_prioritizes_backend_and_excludes_visual(self):
        ranked = queue.discover_backend_candidates(self.github)
        self.assertEqual([x["code"] for x in ranked],
                         ["AUTO-R01", "AUTO-I02"])
        prepared = queue.prepare_auto(api=self.github)
        self.assertTrue(prepared["auto_discovered"])
        self.assertFalse(prepared["duplicate"])
        self.assertEqual(prepared["state"], "prepared")
        self.assertEqual([x["code"] for x in prepared["items"]],
                         ["AUTO-R01", "AUTO-I02"])
        self.assertTrue(queue.prepare_auto(api=self.github)["duplicate"])
        with queue._lock():
            doc = queue._load()
        self.assertFalse(doc["approved_start"])
        self.assertEqual(doc["selection_policy"], "backend-first-nonvisual")
        self.assertIsNone(doc["active"])

    def test_backend_first_discovery_accepts_safe_original_pin_after_head_moves(self):
        original = queue.prepare_auto(api=self.github)
        self.assertEqual(original["state"], "prepared")
        queue.clear(approved=True)
        files = {
            code: tf._task_path(code, "llocphann/Alis")
            for code in ("AUTO-R01", "AUTO-I02")
        }
        initial = {code: path.read_bytes() for code, path in files.items()}
        comparisons = []
        def current_github(endpoint):
            if endpoint.endswith("/branches/dev"):
                return {"commit": {"sha": "c" * 40}}
            if "/compare/" in endpoint:
                comparisons.append(endpoint)
                return {"status": "ahead", "ahead_by": 9, "behind_by": 0,
                        "base_commit": {"sha": "a" * 40},
                        "merge_base_commit": {"sha": "a" * 40}}
            return self.github(endpoint)
        selected = queue.prepare_auto(api=current_github)
        self.assertEqual(selected["state"], "prepared", selected)
        self.assertEqual([x["code"] for x in selected["items"]],
                         ["AUTO-R01", "AUTO-I02"])
        self.assertEqual([x["state"] for x in selected["items"]],
                         ["queued", "queued"])
        self.assertTrue(comparisons)
        for code, path in files.items():
            self.assertEqual(path.read_bytes(), initial[code])
            self.assertEqual(tf.load_task(code)["task"]["base_sha"], "a" * 40)
        self.assertFalse(queue._load()["approved_start"])

    def test_auto_discovery_skips_saved_active_task_and_keeps_record_bytes(self):
        prepared = queue.prepare_auto(api=self.github)
        self.assertEqual(len(prepared["items"]), 2)
        queue.clear(approved=True)
        record = tf.load_task("AUTO-R01")
        record["status"] = "awaiting_owner"
        record["latest_receipt"] = {"immutable": "previous-job"}
        tf._save_task(record)
        original_path = tf._task_path("AUTO-R01", "llocphann/Alis")
        original = original_path.read_bytes()
        result = queue.prepare_auto(api=self.github)
        self.assertEqual(result["state"], "prepared")
        self.assertEqual([x["code"] for x in result["items"]], ["AUTO-I02"])
        self.assertEqual(original_path.read_bytes(), original)
        self.assertFalse(result["active"])
        self.assertFalse(queue._load()["approved_start"])

    def test_auto_discovery_all_saved_work_fails_without_queue_or_replay(self):
        queue.prepare_auto(api=self.github)
        queue.clear(approved=True)
        snapshots = {}
        for code in ("AUTO-R01", "AUTO-I02"):
            record = tf.load_task(code)
            record["status"] = "awaiting_owner"
            record["scheduler_dispatched"] = True
            tf._save_task(record)
            path = tf._task_path(code, "llocphann/Alis")
            snapshots[code] = path.read_bytes()
        with self.assertRaisesRegex(tf.TaskError,
                                    "No fresh Backend tasks available.*AUTO-R01"):
            queue.prepare_auto(api=self.github)
        self.assertEqual(queue.view()["state"], "empty")
        for code, original in snapshots.items():
            self.assertEqual(tf._task_path(code, "llocphann/Alis").read_bytes(),
                             original)

    def test_explicit_task_conflict_reports_actual_state_not_active_elsewhere(self):
        task = queue.discover_backend_candidates(self.github)[0]
        self.assertEqual(task["code"], "AUTO-R01")
        queue.prepare("AUTO-R01", resolver=lambda _code: task)
        queue.clear(approved=True)
        record = tf.load_task("AUTO-R01")
        record["status"] = "awaiting_owner"
        tf._save_task(record)
        prior = tf._task_path("AUTO-R01", "llocphann/Alis").read_bytes()
        parked = queue.prepare("AUTO-R01", resolver=lambda _code: task)
        self.assertEqual(parked["state"], "review_required")
        self.assertEqual(parked["deferred_count"], 1)
        self.assertEqual(parked["items"][0]["reason"], "owner_review_pending")
        self.assertIsNone(parked["next"])
        self.assertEqual(tf._task_path("AUTO-R01", "llocphann/Alis").read_bytes(),
                         prior)

    def test_prior_source_pin_is_not_silently_reused_in_new_queue(self):
        task = queue.discover_backend_candidates(self.github)[0]
        queue.prepare("AUTO-R01", resolver=lambda _code: task)
        queue.clear(approved=True)
        prior = tf._task_path("AUTO-R01", "llocphann/Alis").read_bytes()
        shifted = {**task, "base_sha": "b" * 40}
        parked = queue.prepare("AUTO-R01", resolver=lambda _code: shifted)
        self.assertEqual(parked["state"], "review_required")
        self.assertEqual(parked["items"][0]["reason"], "source_pin_unverified")
        self.assertIsNone(parked["next"])
        self.assertEqual(tf._task_path("AUTO-R01", "llocphann/Alis").read_bytes(),
                         prior)

    def test_pristine_old_sha_is_verified_ancestor_without_repin_or_replay(self):
        original = queue.discover_backend_candidates(self.github)[0]
        queue.prepare("AUTO-R01", resolver=lambda _: original)
        queue.clear(approved=True)
        saved_file = tf._task_path("AUTO-R01", "llocphann/Alis")
        bytes_before = saved_file.read_bytes()
        newer = {**original, "base_sha": "c" * 40}
        first = queue.prepare("AUTO-R01", resolver=lambda _: newer)
        self.assertEqual(first["state"], "review_required")
        self.assertEqual(first["items"][0]["reason"], "source_pin_unverified")
        self.assertEqual(first["items"][0]["recovery_action"],
                         "recheck_original_git_ancestry")
        self.assertFalse(first["items"][0]["needs_evidence_review"])
        self.assertEqual(first["recovery"]["can_recheck_pin"], 1)
        with queue._lock():
            created_before = queue._load()["created_unix"]
        calls = []
        def trusted_compare(endpoint):
            calls.append(endpoint)
            self.assertEqual(endpoint,
                "/repos/llocphann/Alis/compare/" + ("a" * 40) + "..." + ("c" * 40))
            return {"status": "ahead", "ahead_by": 5, "behind_by": 0,
                    "base_commit": {"sha": "a" * 40},
                    "merge_base_commit": {"sha": "a" * 40}}
        rechecked = queue.prepare("AUTO-R01", resolver=lambda _: newer,
                                 comparison_api=trusted_compare)
        self.assertEqual(rechecked["state"], "prepared", rechecked)
        self.assertFalse(rechecked["duplicate"])
        self.assertEqual(rechecked["recovery"]["can_recheck_pin"], 0)
        self.assertEqual(rechecked["items"][0]["state"], "queued")
        self.assertEqual(rechecked["next"]["code"], "AUTO-R01")
        self.assertEqual(calls, [
            "/repos/llocphann/Alis/compare/" + ("a" * 40) + "..." + ("c" * 40)])
        self.assertEqual(saved_file.read_bytes(), bytes_before)
        self.assertEqual(tf.load_task("AUTO-R01")["task"]["base_sha"], "a" * 40)
        with queue._lock():
            manifest = queue._load()
        self.assertEqual(manifest["items"][0]["source_sha"], "a" * 40)
        self.assertEqual(manifest["created_unix"], created_before)
        self.assertFalse(manifest["approved_start"])
        self.assertTrue(queue.prepare("AUTO-R01",
             resolver=lambda _: self.fail("must not recontact GitHub"))["duplicate"])

    def test_saved_cloud_ack_outranks_head_drift_and_never_auto_replays(self):
        task = queue.discover_backend_candidates(self.github)[0]
        queue.prepare("AUTO-R01", resolver=lambda _: task)
        queue.clear(approved=True)
        record = tf.load_task("AUTO-R01")
        record["status"] = "awaiting_cloud_ack"
        record["scheduler_dispatched"] = True
        record["latest_receipt"] = {"id": "JOB-DURABLE"}
        tf._save_task(record)
        file = tf._task_path("AUTO-R01", "llocphann/Alis")
        original = file.read_bytes()
        advanced = {**task, "base_sha": "c" * 40}
        calls = []
        result = queue.prepare("AUTO-R01", resolver=lambda _: advanced,
           comparison_api=lambda endpoint: calls.append(endpoint))
        self.assertEqual(result["state"], "review_required")
        self.assertEqual(result["items"][0]["reason"], "cloud_ack_pending")
        self.assertEqual(result["items"][0]["recovery_action"],
                         "reconcile_original_cloud_delivery")
        self.assertTrue(result["items"][0]["needs_evidence_review"])
        self.assertEqual(result["recovery"]["must_reconcile_evidence"], 1)
        self.assertEqual(result["items"][0]["state"], "deferred")
        self.assertEqual(result["items"][0]["code"], "AUTO-R01")
        self.assertEqual(result["deferred_count"], 1)
        self.assertIsNone(result["next"])
        self.assertFalse(calls)
        self.assertEqual(file.read_bytes(), original)

    def test_git_comparison_must_prove_original_sha_is_merge_base(self):
        task = queue.discover_backend_candidates(self.github)[0]
        queue.prepare("AUTO-R01", resolver=lambda _: task)
        queue.clear(approved=True)
        file = tf._task_path("AUTO-R01", "llocphann/Alis")
        original = file.read_bytes()
        advanced = {**task, "base_sha": "c" * 40}
        for claim in [
            {"status": "diverged", "ahead_by": 5, "behind_by": 2,
             "base_commit": {"sha": "a" * 40},
             "merge_base_commit": {"sha": "f" * 40}},
            {"status": "ahead", "ahead_by": 5, "behind_by": 0,
             "base_commit": {"sha": "a" * 40},
             "merge_base_commit": None},
            {"status": "ahead", "ahead_by": 5, "behind_by": 0,
             "base_commit": {"sha": "b" * 40},
             "merge_base_commit": {"sha": "a" * 40}},
        ]:
            result = queue.prepare("AUTO-R01", resolver=lambda _: advanced,
                              comparison_api=lambda _endpoint: claim)
            self.assertEqual(result["state"], "review_required")
            self.assertEqual(result["items"][0]["reason"],
                             "source_pin_unverified")
        self.assertEqual(file.read_bytes(), original)

    def test_issue_updated_prevents_reuse_of_stale_prompt_even_if_ancestor(self):
        task = queue.discover_backend_candidates(self.github)[0]
        queue.prepare("AUTO-R01", resolver=lambda _: task)
        queue.clear(approved=True)
        file = tf._task_path("AUTO-R01", "llocphann/Alis")
        original = file.read_bytes()
        advanced = {**task, "base_sha": "c" * 40,
                    "issue_updated_at": "2026-10-17T00:00:00Z"}
        result = queue.prepare("AUTO-R01", resolver=lambda _: advanced,
            comparison_api=lambda _endpoint: self.fail("not pristine"))
        self.assertEqual(result["state"], "review_required")
        self.assertEqual(result["items"][0]["reason"], "saved_work_requires_review")
        self.assertEqual(file.read_bytes(), original)

    def test_manual_queue_parks_ack_pending_first_and_keeps_other_tasks(self):
        # The user explicitly supplied AI-I01 first. Its past local receipt
        # may have been delivered already: do not replay it or block AI-I02.
        candidates = queue.discover_backend_candidates(self.github)
        mapping = {x["code"]: x for x in candidates}
        task = mapping["AUTO-R01"]
        queue.prepare("AUTO-R01", resolver=lambda _code: task)
        queue.clear(approved=True)
        record = tf.load_task("AUTO-R01")
        record["status"] = "awaiting_cloud_ack"
        record["latest_receipt"] = {"id": "JOB-PERSISTED"}
        tf._save_task(record)
        saved_path = tf._task_path("AUTO-R01", "llocphann/Alis")
        before = saved_path.read_bytes()
        prepared = queue.prepare("AUTO-R01;AUTO-I02",
                                 resolver=lambda code: mapping[code])
        self.assertEqual(prepared["state"], "prepared")
        self.assertEqual(prepared["deferred_count"], 1)
        self.assertEqual([item["code"] for item in prepared["items"]],
                         ["AUTO-R01", "AUTO-I02"])
        self.assertEqual(prepared["items"][0]["reason"], "cloud_ack_pending")
        self.assertEqual(prepared["items"][1]["state"], "queued")
        self.assertEqual(prepared["next"]["code"], "AUTO-I02")
        self.assertFalse(queue._load()["approved_start"])
        self.assertEqual(saved_path.read_bytes(), before)
        duplicate = queue.prepare("AUTO-R01;AUTO-I02",
                                  resolver=lambda _code: self.fail("must not resolve"))
        self.assertTrue(duplicate["duplicate"])
        self.assertEqual(saved_path.read_bytes(), before)
        claimed = queue.claim(verified_start=lambda *_args: True)
        self.assertEqual(claimed["selected"]["code"], "AUTO-I02")
        first = queue.view()
        self.assertEqual(first["active"]["code"], "AUTO-I02")
        self.assertEqual(first["items"][0]["reason"], "cloud_ack_pending")

    def test_all_deferred_tasks_can_only_be_archived_by_explicit_owner(self):
        task = queue.discover_backend_candidates(self.github)[0]
        queue.prepare("AUTO-R01", resolver=lambda _code: task)
        queue.clear(approved=True)
        record = tf.load_task("AUTO-R01")
        record["status"] = "awaiting_cloud_ack"
        record["latest_receipt"] = {"id": "JOB-IMMUTABLE"}
        tf._save_task(record)
        location = tf._task_path("AUTO-R01", "llocphann/Alis")
        before = location.read_bytes()
        result = queue.prepare("AUTO-R01", resolver=lambda _code: task)
        self.assertEqual(result["state"], "review_required")
        self.assertEqual(result["deferred_count"], 1)
        self.assertIsNone(result["next"])
        with self.assertRaises(tf.TaskError):
            queue.approve_ordered_start()
        with self.assertRaises(tf.TaskError):
            queue.clear(expected_queued="")
        cleared = queue.clear(approved=True, expected_queued="")
        self.assertEqual(cleared["state"], "empty")
        self.assertEqual(location.read_bytes(), before)
        self.assertTrue(list((tf.state_dir() / "queue-history").glob("cleared-*.json")))

    def test_clear_requires_confirmation_preserves_original_task_records(self):
        queue.prepare_auto(api=self.github)
        first = tf._task_path("AUTO-R01", "llocphann/Alis")
        before = first.read_bytes()
        with self.assertRaises(tf.TaskError):
            queue.clear()
        outcome = queue.clear(approved=True)
        self.assertTrue(outcome["cleared"])
        self.assertEqual(outcome["state"], "empty")
        self.assertEqual(first.read_bytes(), before)
        history = list((tf.state_dir() / "queue-history").glob("cleared-*.json"))
        self.assertEqual(len(history), 1)
        self.assertEqual(json.loads(history[0].read_text())["state"], "prepared")
        self.assertFalse((tf.state_dir() / "queue.json").exists())
        self.assertFalse(queue.clear(approved=True)["cleared"])

    def test_clear_blocks_approved_queue_and_durable_handoff(self):
        queue.prepare_auto(api=self.github)
        queue.approve_ordered_start()
        with self.assertRaises(tf.TaskError):
            queue.clear(approved=True)
        with queue._lock():
            doc = queue._load()
            doc["approved_start"] = False
            queue._save(doc)
        record = tf.load_task("AUTO-R01")
        record["handoff"] = {"id": "unsettled"}
        tf._save_task(record)
        with self.assertRaises(tf.TaskError):
            queue.clear(approved=True)
        self.assertTrue((tf.state_dir() / "queue.json").exists())
        self.assertEqual(len(list((tf.state_dir() / "queue-history").glob("*.json"))), 0)

    def test_clear_blocks_active_or_waiting_and_keeps_receipts(self):
        queue.prepare_auto(api=self.github)
        sentinel = tf.state_dir() / "worker" / "receipts" / "JOB-HISTORIC.json"
        sentinel.parent.mkdir(parents=True)
        sentinel.write_text('{"immutable":true}')
        for state in ("active", "waiting"):
            with queue._lock():
                doc = queue._load()
                doc["state"] = state
                queue._save(doc)
            with self.assertRaises(tf.TaskError):
                queue.clear(approved=True)
        self.assertEqual(sentinel.read_text(), '{"immutable":true}')

    def test_active_clear_removes_only_queued_siblings_and_preserves_owner(self):
        queue.prepare_auto(api=self.github)
        queue.approve_ordered_start()
        selected = queue.claim(
            verified_start=lambda item, record, decision: True)["selected"]
        self.assertEqual(selected["code"], "AUTO-R01")
        original = (tf.state_dir() / "queue.json").read_bytes()
        first = tf._task_path("AUTO-R01", "llocphann/Alis")
        waiting = tf._task_path("AUTO-I02", "llocphann/Alis")
        before_active, before_waiting = first.read_bytes(), waiting.read_bytes()
        receipt = tf.state_dir() / "worker" / "receipts" / "JOB-UNRELATED.json"
        receipt.parent.mkdir(parents=True, exist_ok=True)
        receipt.write_text('{"immutable":true}')
        expected = "llocphann/Alis:AUTO-I02"
        with self.assertRaises(tf.TaskError):
            queue.clear(approved=True, expected_queued="llocphann/Alis:WRONG")
        self.assertEqual(original, (tf.state_dir() / "queue.json").read_bytes())
        cleared = queue.clear(approved=True, expected_queued=expected)
        self.assertTrue(cleared["cleared"])
        self.assertEqual(cleared["removed_queued"], 1)
        self.assertTrue(cleared["active_preserved"])
        self.assertEqual(cleared["state"], "active")
        self.assertEqual(cleared["active"], selected)
        self.assertEqual([(x["code"], x["state"]) for x in cleared["items"]],
                         [("AUTO-R01", "active")])
        self.assertEqual(first.read_bytes(), before_active)
        self.assertEqual(waiting.read_bytes(), before_waiting)
        self.assertEqual(receipt.read_text(), '{"immutable":true}')
        with queue._lock():
            after = queue._load()
        self.assertEqual(after["active"], selected)
        self.assertTrue(after["approved_start"])
        self.assertEqual(after["selection"]["code"], "AUTO-R01")
        self.assertIsNone(cleared["next"])
        archived = list((tf.state_dir() / "queue-history").glob("cleared-*.json"))
        self.assertEqual(len(archived), 1)
        self.assertEqual(json.loads(archived[0].read_bytes()),
                         json.loads(original))
        with self.assertRaises(tf.TaskError):
            queue.clear(approved=True, expected_queued=expected)
        self.assertFalse(queue.clear(approved=True, expected_queued="")["cleared"])

    def test_screenshot_case_one_active_seventeen_queued(self):
        # Regression for Settings: AUDIO-I01 active must survive clearing
        # MUSIC-I02, ABYSS-*, DASH-*, etc. No local machine job is touched.
        codes = [
            "MUSIC-I02", "ABYSS-R09", "ABYSS-R12", "DASH-R01",
            "OPT-R01", "AUDIO-R01", "ABYSS-R11", "ABYSS-R03",
            "OPT-R02", "DASH-R05", "NOTIF-I02", "VIS-R01",
            "AC-I01", "AC-I02", "AC-R02", "AC-R01", "AC-R03",
        ]
        active = {"code": "AUDIO-I01", "repository": "llocphann/Alis"}
        manifest = {
            "schema": queue.QUEUE_SCHEMA, "mode": "ordered",
            "state": "active", "active": dict(active),
            "selection": {"code": "AUDIO-I01", "decision_id": None,
                          "selected_unix": 12},
            "approved_start": True,
            "items": [{**active, "state": "active", "issue_number": 1,
                       "source_sha": "a" * 40}] + [
                {"code": code, "repository": "llocphann/Alis",
                 "issue_number": i + 2, "source_sha": "a" * 40,
                 "state": "queued"}
                for i, code in enumerate(codes)],
            "created_unix": 1, "updated_unix": 1,
        }
        with queue._lock():
            queue._save(manifest)
        expected = ";".join("llocphann/Alis:" + code for code in codes)
        before_active = dict(manifest["items"][0])
        result = queue.clear(approved=True, expected_queued=expected)
        self.assertEqual(result["removed_queued"], 17)
        self.assertEqual(result["state"], "active")
        self.assertEqual(result["items"], [{
            "code": "AUDIO-I01", "repository": "llocphann/Alis",
            "state": "active"}])
        with queue._lock():
            saved = queue._load()
        self.assertEqual(saved["items"], [before_active])
        self.assertEqual(saved["selection"], manifest["selection"])
        self.assertEqual(saved["active"], manifest["active"])
        self.assertEqual(saved["approved_start"], manifest["approved_start"])
        self.assertEqual(len(list((tf.state_dir() / "queue-history").glob(
            "cleared-*.json"))), 1)

        # The GUI is allowed to offer cleanup from a last-known snapshot.
        # It must still send all exact queued identities to the backend.
        qml = (Path(__file__).resolve().parents[1] /
               "modules/settings/AutomationTaskConfig.qml").read_text()
        button = qml.split('objectName: "automationClearQueue"')[1].split(
            "onClicked: root.clearQueue()", 1)[0]
        self.assertIn('Translation.tr("Clear")', button)
        self.assertIn('Translation.tr("Confirm clear")', button)
        self.assertIn('task.state === "queued"', button)
        self.assertNotIn("root.queueStatusConfirmed", button)
        self.assertIn('"--expected-queued", targets', qml)

    def test_queue_clear_matches_exact_snapshot_and_rejects_waiting_selector(self):
        queue.prepare_auto(api=self.github)
        live = "llocphann/Alis:AUTO-R01;llocphann/Alis:AUTO-I02"
        with self.assertRaises(tf.TaskError):
            queue.clear(approved=True, expected_queued="llocphann/Alis:AUTO-I02")
        with queue._lock():
            doc = queue._load()
            doc["state"] = "waiting"
            doc["approved_start"] = True
            queue._save(doc)
        with self.assertRaises(tf.TaskError):
            queue.clear(approved=True, expected_queued=live)
        self.assertEqual([x["state"] for x in queue.view()["items"]],
                         ["queued", "queued"])

    def test_no_backend_candidates_fails_without_writing_queue(self):
        def no_issues(path):
            return [] if "/issues?state=open" in path else self.github(path)
        with self.assertRaises(tf.TaskError):
            queue.prepare_auto(api=no_issues)
        self.assertFalse((tf.state_dir() / "queue.json").exists())


if __name__ == "__main__":
    unittest.main()
