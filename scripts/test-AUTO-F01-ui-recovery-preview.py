#!/usr/bin/env python3
"""Read-only recovery preflight never promotes an original UI send."""
from __future__ import annotations
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation import managed_tasks
from automation.chat_bridge import ui_recovery_preview

REPO = "llocphann/Alis"
CODE = "NOTES-F01"
ATTEMPT = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
JID = "11111111-2222-3333-4444-555555555555"
PROMPT = "[$github](app://connector_76869538009648d5b282a4bb21c3d157)\n\nOriginal diagnostic pending\nAlis UI request token: " + ATTEMPT + "\n"
DIGEST = hashlib.sha256(PROMPT.encode("utf-8")).hexdigest()


class RecoveryPreview(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.TemporaryDirectory()
        self.addCleanup(self.home.cleanup)
        root = Path(self.home.name) / "ui-send-journal"
        root.mkdir()
        self.path = root / "pending.json"
        pid = managed_tasks.profile_id(REPO, CODE)
        self.manifest = {
            "mode": "ordered", "state": "stopping",
            "active": {"repository": REPO, "code": CODE},
            "stop_requested": True, "approved_start": False,
            "items": [{"repository": REPO, "code": CODE, "state": "active"}],
        }
        self.config = {"profiles": [
            {"id": pid, "description": f"taskflow:{REPO}:{CODE}"}]}
        self.state = {"profiles": {pid: {
            "desired": "stopped", "status": "ui_reconciliation_required",
            "run_active": False, "job_id": None,
            "session": {"ui_target_key": "f" * 64,
                        "local_run_id": "PRIVATE_CONVERSATION_ID"},
            "pending": {
                "transport": "alis-ui-once", "attempt_id": ATTEMPT,
                "kind": "continuation", "prompt": PROMPT,
                "prompt_sha256": DIGEST, "PRIVATE_SECRET": "NEVER_PRINT",
            },
        }}}
        self.journal = {"schema": "alis.chat-ui-send.v1",
                        "phase": "attempted",
                        "id": JID, "prompt_sha256": DIGEST,
                        "command": "send"}
        self.write_journal()

    def write_journal(self):
        self.path.write_text(json.dumps(self.journal), encoding="utf-8")

    def inspect(self):
        return ui_recovery_preview.preview(
            self.manifest, self.config, self.state, self.path)

    def test_matching_original_is_candidate_not_accepted_receipt(self):
        before = self.path.read_bytes()
        original = json.dumps((self.manifest, self.config, self.state),
                              sort_keys=True)
        result = self.inspect()
        self.assertTrue(result["read_only_observation_candidate"])
        self.assertTrue(result["ui_pending"])
        self.assertTrue(result["original_prompt_integrity"])
        self.assertTrue(result["first_turn_anchor_present"])
        self.assertEqual(result["original_journal"], "matching_attempt")
        self.assertEqual(result["phase"], "original_observation_candidate")
        self.assertTrue(result["owner_confirmation_required"])
        self.assertFalse(result["send_or_queue_start_authorized"])
        self.assertEqual(self.path.read_bytes(), before)
        self.assertEqual(json.dumps((self.manifest, self.config, self.state),
                                    sort_keys=True), original)
        visible = json.dumps(result)
        for private in (ATTEMPT, JID, PROMPT, DIGEST,
                        "PRIVATE_CONVERSATION_ID", "NEVER_PRINT", "profile-"):
            self.assertNotIn(private, visible)

    def test_no_authority_if_not_paused_and_revoked(self):
        for state in ("active", "prepared", "waiting", "finished", "review_required"):
            self.manifest["state"] = state
            self.assertFalse(self.inspect()["read_only_observation_candidate"])
        self.manifest["state"] = "stopping"
        for field, unsafe in (("stop_requested", False),
                               ("approved_start", True),
                               ("active", None)):
            prior = self.manifest[field]
            self.manifest[field] = unsafe
            self.assertFalse(self.inspect()["read_only_observation_candidate"])
            self.manifest[field] = prior
        pid = next(iter(self.state["profiles"]))
        for key, value in (("desired", "run"),
                           ("job_id", "JOB-NOT-COMPLETE"),
                           ("run_active", True)):
            original = self.state["profiles"][pid][key]
            self.state["profiles"][pid][key] = value
            self.assertFalse(self.inspect()["read_only_observation_candidate"])
            self.state["profiles"][pid][key] = original

    def test_prompt_identity_and_journal_fail_closed(self):
        pid = next(iter(self.state["profiles"]))
        pending = self.state["profiles"][pid]["pending"]
        for key, value in (
            ("prompt", PROMPT.replace(ATTEMPT, "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")),
            ("prompt", PROMPT + "later text"),
            ("prompt", PROMPT + "\nAlis UI request token: " + ATTEMPT + "\n"),
            ("prompt_sha256", "0" * 64),
            ("attempt_id", "INVALID-ATTEMPT"),
            ("transport", "native"),
        ):
            original = pending[key]
            pending[key] = value
            self.assertFalse(self.inspect()["read_only_observation_candidate"])
            pending[key] = original
        for field, value in (("phase", "prepared"),
                             ("command", "rotate-send"),
                             ("prompt_sha256", "a" * 64),
                             ("id", "NOT-A-UUID")):
            original = self.journal[field]
            self.journal[field] = value
            self.write_journal()
            self.assertEqual(self.inspect()["reason"],
                             "ORIGINAL_JOURNAL_UNVERIFIED")
            self.journal[field] = original
        self.write_journal()
        self.path.unlink()
        self.assertEqual(self.inspect()["original_journal"], "retired_evidence_unverified")
        self.path.symlink_to(Path(self.home.name) / "private.json")
        self.assertEqual(self.inspect()["original_journal"], "unsafe_path")

    def test_uniquely_archived_legacy_send_is_read_only_candidate(self):
        pid = next(iter(self.state["profiles"]))
        self.state["profiles"][pid]["pending"]["prepared_at_unix"] = 12
        self.path.unlink()
        archive = self.path.parent / "observed"
        archive.mkdir()
        old = archive / (JID + ".json")
        old.write_text(json.dumps({**self.journal, "at_unix": 13}))
        private_response = self.path.parent.parent / "ui-responses" / pid
        private_response.mkdir(parents=True)
        response_path = private_response / (ATTEMPT + ".json")
        response_path.write_text(json.dumps({
            "transport": "alis-ui-once", "attempt_id": ATTEMPT,
            "response": "Complete original assistant text", "at_unix": 14}))
        original_record = old.read_bytes()
        original_response = response_path.read_bytes()
        report = self.inspect()
        self.assertEqual(report["original_journal"], "unique_retired_attempt")
        self.assertEqual(report["phase"], "retired_original_observation_candidate")
        self.assertTrue(report["read_only_observation_candidate"])
        self.assertEqual(report["reason"],
                         "LIVE_UI_AND_RETIRED_RESPONSE_COMPARISON_REQUIRED")
        self.assertFalse(report["send_or_queue_start_authorized"])
        self.assertEqual(old.read_bytes(), original_record)
        self.assertEqual(response_path.read_bytes(), original_response)
        self.assertFalse(self.path.exists())
        self.assertNotIn("Complete original assistant text", json.dumps(report))

        second_id = "66666666-7777-8888-9999-aaaaaaaaaaaa"
        (archive / (second_id + ".json")).write_text(json.dumps({
            **self.journal, "id": second_id, "at_unix": 13}))
        self.assertEqual(self.inspect()["original_journal"], "archive_ambiguous")
        self.assertFalse(self.inspect()["read_only_observation_candidate"])
        (archive / (second_id + ".json")).unlink()
        response_path.write_text(json.dumps({
            "transport": "alis-ui-once", "attempt_id": ATTEMPT,
            "response": "Complete original assistant text", "at_unix": 11}))
        self.assertEqual(self.inspect()["original_journal"],
                         "retired_evidence_unverified")
        response_path.write_text(json.dumps({
            "transport": "alis-ui-once", "attempt_id": ATTEMPT,
            "response": "Complete original assistant text", "at_unix": 14}))
        old.rename(archive / "different-id.json")
        self.assertEqual(self.inspect()["original_journal"], "archive_review_required")

    def test_interrupted_and_not_sent_journals_do_not_authorize_retry(self):
        pid = next(iter(self.state["profiles"]))
        self.state["profiles"][pid]["pending"]["prepared_at_unix"] = 12
        self.path.unlink()
        interrupted = self.path.parent / "interrupted"
        interrupted.mkdir()
        observed_path = interrupted / (JID + ".json")
        observed_path.write_text(json.dumps({
            **self.journal, "at_unix": 13,
            "outcome": "interrupted_delivered",
            "proof_sha256": "a" * 64,
            "delivery_acknowledged": True,
            "completion_acknowledged": False,
        }))
        report = self.inspect()
        self.assertEqual(report["original_journal"],
                         "original_interrupted_delivery")
        self.assertFalse(report["read_only_observation_candidate"])
        self.assertFalse(report["send_or_queue_start_authorized"])
        self.assertTrue(report["owner_confirmation_required"])

        # Distinct journal IDs, even for a matching prompt, cannot be
        # silently combined into a terminal or a retry permission.
        not_sent = self.path.parent / "not-sent"
        not_sent.mkdir()
        second_jid = "66666666-7777-8888-9999-aaaaaaaaaaaa"
        secondary = not_sent / (second_jid + ".json")
        secondary.write_text(json.dumps({
            **self.journal, "id": second_jid, "at_unix": 13,
            "outcome": "not_sent",
            "evidence": "owner-confirmed-not-sent",
            "delivery_acknowledged": False,
        }))
        self.assertEqual(self.inspect()["original_journal"],
                         "tombstone_conflict")
        secondary.unlink()
        observed_path.unlink()
        self.assertEqual(self.inspect()["original_journal"],
                         "retired_evidence_unverified")
        secondary.write_text(json.dumps({
            **self.journal, "id": second_jid, "at_unix": 13,
            "outcome": "not_sent",
            "evidence": "owner-confirmed-not-sent",
            "delivery_acknowledged": False,
        }))
        self.assertEqual(self.inspect()["original_journal"],
                         "original_confirmed_not_sent")
        self.assertFalse(self.inspect()["read_only_observation_candidate"])
        secondary.write_text(json.dumps({
            **self.journal, "id": second_jid, "at_unix": 13,
            "outcome": "not_sent", "evidence": "unverified",
            "delivery_acknowledged": False,
        }))
        self.assertEqual(self.inspect()["original_journal"],
                         "tombstone_review_required")
        secondary.unlink()
        secondary.symlink_to(self.path.parent / "missing.json")
        self.assertEqual(self.inspect()["original_journal"],
                         "tombstone_review_required")

    def test_observed_archive_and_interrupted_tombstone_conflict(self):
        pid = next(iter(self.state["profiles"]))
        self.state["profiles"][pid]["pending"]["prepared_at_unix"] = 12
        self.path.unlink()
        observed = self.path.parent / "observed"
        observed.mkdir()
        observed_file = observed / (JID + ".json")
        observed_file.write_text(json.dumps({**self.journal, "at_unix": 13}))
        response_dir = self.path.parent.parent / "ui-responses" / pid
        response_dir.mkdir(parents=True)
        (response_dir / (ATTEMPT + ".json")).write_text(json.dumps({
            "transport": "alis-ui-once", "attempt_id": ATTEMPT,
            "response": "Original response", "at_unix": 14}))
        self.assertEqual(self.inspect()["original_journal"],
                         "unique_retired_attempt")
        interrupted = self.path.parent / "interrupted"
        interrupted.mkdir()
        second_id = "66666666-7777-8888-9999-aaaaaaaaaaaa"
        (interrupted / (second_id + ".json")).write_text(json.dumps({
            **self.journal, "id": second_id, "at_unix": 13,
            "outcome": "interrupted_delivered",
            "proof_sha256": "a" * 64,
            "delivery_acknowledged": True,
            "completion_acknowledged": False}))
        report = self.inspect()
        self.assertEqual(report["original_journal"], "tombstone_conflict")
        self.assertFalse(report["read_only_observation_candidate"])
        self.assertFalse(report["send_or_queue_start_authorized"])
        self.assertEqual(report["reason"], "ORIGINAL_JOURNAL_UNVERIFIED")
        self.assertTrue(observed_file.is_file())
        self.assertFalse(self.path.exists())
        # Even a DIFFERENT journal ID with a matching SHA is conflicting.
        self.assertNotIn("Original response", json.dumps(report))

    def test_corrupt_private_state_is_redacted_and_fails_closed(self):
        self.manifest["state"] = "SECRET_PRIVATE_DATA_IN_STATE"
        result = self.inspect()
        self.assertEqual(result["queue_state"], "invalid")
        self.assertNotIn("SECRET_PRIVATE_DATA", json.dumps(result))
        self.manifest["state"] = "stopping"
        pid = next(iter(self.state["profiles"]))
        record = self.state["profiles"][pid]
        old_session = record["session"]
        record["session"] = "SECRET_PRIVATE_CHAT_SESSION"
        result = self.inspect()
        self.assertEqual(result["reason"], "FIRST_TURN_ANCHOR_MISSING")
        self.assertFalse(result["read_only_observation_candidate"])
        self.assertNotIn("SECRET_PRIVATE_CHAT", json.dumps(result))
        record["session"] = old_session
        previous = self.config["profiles"]
        self.config["profiles"] = [None, {"id": pid}]
        result = self.inspect()
        self.assertEqual(result["reason"], "ORIGINAL_PROFILE_MISSING")
        self.assertFalse(result["read_only_observation_candidate"])
        self.config["profiles"] = previous

    def test_missing_retired_evidence_and_symlink_fail_closed(self):
        self.state["profiles"][next(iter(self.state["profiles"]))]["pending"][
            "prepared_at_unix"] = 12
        self.path.unlink()
        self.assertEqual(self.inspect()["original_journal"],
                         "retired_evidence_unverified")
        # Missing original response must fail before archive traversal.
        folder = self.path.parent / "observed"
        folder.mkdir()
        (folder / (JID + ".json")).symlink_to(self.path.parent / "outside.json")
        self.assertEqual(self.inspect()["original_journal"],
                         "retired_evidence_unverified")
        pid = next(iter(self.state["profiles"]))
        receipt = self.path.parent.parent / "ui-responses" / pid
        receipt.mkdir(parents=True)
        (receipt / (ATTEMPT + ".json")).write_text(json.dumps({
            "transport": "alis-ui-once", "attempt_id": ATTEMPT,
            "response": "Original final", "at_unix": 14}))
        self.assertEqual(self.inspect()["original_journal"], "archive_review_required")
        self.assertFalse(self.inspect()["read_only_observation_candidate"])

    def test_fresh_queue_is_not_recovery_candidate(self):
        self.assertFalse(ui_recovery_preview.preview(
            None, self.config, self.state, self.path)["read_only_observation_candidate"])
        bad = copy.deepcopy(self.manifest)
        bad["items"][0]["state"] = "awaiting_owner"
        self.assertEqual(ui_recovery_preview.preview(
            bad, self.config, self.state, self.path)["reason"],
            "QUEUE_ACTIVE_MEMBER_UNVERIFIED")


if __name__ == "__main__":
    unittest.main()
