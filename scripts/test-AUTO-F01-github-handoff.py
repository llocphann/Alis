#!/usr/bin/env python3
"""Offline no-CDP/no-network GitHub DONE handoff & existing worker regression."""
from __future__ import annotations

import json
import sys
import tempfile
import time
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation import github_handoff as handoff
from automation.worker import daemon as worker

JOB_ID="JOB-AUTO-F01-demo"
BASE="a"*40
COMMIT="b"*40
RUN_ID="10000000-0000-4000-8000-000000000001"
TASK="AUTO-F01"
JOB_PATH=worker.QUEUE+"/"+JOB_ID+".json"

def fixture():
    job={"id":JOB_ID,"base_sha":BASE,"actions":[{"exec":{"argv":["true"]}}],
         "handoff":{"task_code":TASK,"run_id":RUN_ID}}
    raw=json.dumps(job,sort_keys=True,separators=(",",":"))
    now=int(time.time())
    signal={"schema":handoff.SCHEMA,"task_code":TASK,"run_id":RUN_ID,
            "job_id":JOB_ID,"base_sha":BASE,
            "job_sha256":handoff.job_digest(raw),"status":"PREPARING",
            "updated_unix":now,"expires_unix":now+3600}
    return job,raw,signal

class GitHubHandoffTests(unittest.TestCase):
    def test_state_machine_and_digest_bound_owner_approval(self):
        job,raw,signal=fixture()
        self.assertEqual(worker.validate_job(JOB_PATH,raw),job)
        with tempfile.TemporaryDirectory() as tmp:
            state=Path(tmp)
            early=json.dumps(signal)
            with self.assertRaisesRegex(handoff.HandoffWait,"not DONE"):
                handoff.ready(early,job,raw,state)
            signal["status"]="DONE"
            ready=json.dumps(signal)
            with self.assertRaisesRegex(handoff.HandoffWait,"owner approval"):
                handoff.ready(ready,job,raw,state)
            payload=handoff.approval_payload(job,raw)
            path=handoff.approval_path(state,JOB_ID)
            path.parent.mkdir()
            path.write_text(json.dumps(payload))
            self.assertTrue(handoff.ready(ready,job,raw,state)["ready"])
            self.assertTrue(handoff.retire_after_receipt(
                ready,{"job":JOB_ID,"input_sha256":handoff.job_digest(raw),
                       "status":"passed"}))
            self.assertFalse(handoff.retire_after_receipt(
                early,{"job":JOB_ID,"input_sha256":handoff.job_digest(raw),
                       "status":"passed"}))
            self.assertFalse(handoff.retire_after_receipt(
                ready,{"job":"JOB-OTHER","input_sha256":handoff.job_digest(raw),
                       "status":"passed"}))
            self.assertFalse(handoff.retire_after_receipt(
                ready,{"job":JOB_ID,"input_sha256":handoff.job_digest(raw),
                       "status":"indeterminate"}))
            self.assertFalse(handoff.retire_after_receipt(
                ready,{"job":JOB_ID,"input_sha256":"f"*64,"status":"failed"}))
            bad={**signal,"job_sha256":"f"*64}
            with self.assertRaisesRegex(ValueError,"does not match"):
                handoff.ready(json.dumps(bad),job,raw,state)
            bad={**signal,"run_id":str(uuid.uuid4())}
            with self.assertRaisesRegex(ValueError,"does not match"):
                handoff.ready(json.dumps(bad),job,raw,state)
            bad={**signal,"expires_unix":signal["updated_unix"]+1}
            with self.assertRaises(handoff.HandoffWait):
                handoff.ready(json.dumps(bad),job,raw,state,
                              now=signal["updated_unix"]+2)
            path.write_text(json.dumps({**payload,"job_sha256":"0"*64}))
            with self.assertRaises(handoff.HandoffWait):
                handoff.ready(ready,job,raw,state)

    def test_schema_rejects_unknown_fields_and_replays(self):
        job,raw,signal=fixture()
        for altered in (
            {**signal,"extra":"PRIVATE_TOKEN"},
            {**signal,"status":"DONE; rm -rf"},
            {**signal,"updated_unix":"now"},
            {**signal,"expires_unix":signal["updated_unix"]+90000},
            {**signal,"run_id":"untrusted"},
        ):
            with self.assertRaises(ValueError):
                handoff.validate_signal(json.dumps(altered))
        with self.assertRaises(ValueError):
            handoff.validate_signal("x"*3000)
        for broken in ({**job,"handoff":{"task_code":TASK,"run_id":"bad"}},
                       {**job,"handoff":{"task_code":"../bad","run_id":RUN_ID}},
                       {**job,"handoff":{"task_code":TASK,"run_id":RUN_ID,"other":"x"}}):
            with self.assertRaises(ValueError):
                worker.validate_job(JOB_PATH,json.dumps(broken))

    def test_worker_waits_without_receipt_then_executes_once_after_done(self):
        job,raw,signal=fixture()
        with tempfile.TemporaryDirectory() as tmp:
            state=Path(tmp)
            def text(path,*,ref="origin/dev"):
                if path==JOB_PATH:
                    self.assertEqual(ref,COMMIT)
                    return raw
                if path==handoff.PATH:
                    return json.dumps(signal)
                raise AssertionError(path)
            calls=[]
            def execute(data,sha):
                calls.append((data["id"],sha))
                return {"job":data["id"],"status":"passed",
                        "input_sha256":handoff.job_digest(raw),
                        "actions":[],"finished_at_unix":int(time.time())}
            with (patch.object(worker,"state_root",return_value=state),
                  patch.object(worker,"introducing_commit",return_value=COMMIT),
                  patch.object(worker,"remote_text",side_effect=text),
                  patch.object(worker,"first_parent",return_value=BASE),
                  patch.object(worker,"execute",side_effect=execute)):
                self.assertIsNone(worker.process_job(JOB_PATH,publish_now=False))
                self.assertIsNone(worker.load_receipt(JOB_ID))
                self.assertEqual(calls,[])
                signal["status"]="DONE"
                self.assertIsNone(worker.process_job(JOB_PATH,publish_now=False))
                self.assertIsNone(worker.load_receipt(JOB_ID))
                self.assertEqual(calls,[])
                target=handoff.approval_path(state,JOB_ID)
                target.parent.mkdir(exist_ok=True)
                target.write_text(json.dumps(handoff.approval_payload(job,raw)))
                result=worker.process_job(JOB_PATH,publish_now=False)
                self.assertEqual(result,(JOB_ID,"passed"))
                self.assertEqual(calls,[(JOB_ID,COMMIT)])
                self.assertEqual(worker.load_receipt(JOB_ID)["phase"],"finished")
                self.assertEqual(worker.process_job(JOB_PATH,publish_now=False),
                                 (JOB_ID,"passed"))
                self.assertEqual(calls,[(JOB_ID,COMMIT)])
                # No reprovision after a failed/bad/expired signal.
                worker.save_receipt(JOB_ID,{**worker.load_receipt(JOB_ID),
                                          "phase":"published"})
                self.assertIsNone(worker.process_job(JOB_PATH,publish_now=False))
                worker.cleanup(startup=False)
                self.assertFalse(target.exists())
                self.assertTrue(worker.load_receipt(JOB_ID))

if __name__=="__main__":
    unittest.main()
