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
            # An old completed job is still safe to prune from Git's tip:
            # the stale signal cannot authorize execution again.
            far_future=signal["updated_unix"]+handoff.MAX_LIFETIME+300
            with self.assertRaises(ValueError):
                handoff.validate_signal(ready,now=far_future)
            self.assertTrue(handoff.retire_after_receipt(
                ready,{"job":JOB_ID,"input_sha256":handoff.job_digest(raw),
                       "status":"passed"},now=far_future))
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

    def test_only_exact_settled_opt_in_jobs_are_auto_retired(self):
        job,raw,signal=fixture()
        valid={"job":JOB_ID,"input_sha256":handoff.job_digest(raw),
               "status":"passed"}
        self.assertTrue(handoff.retire_opt_in_job(raw,valid))
        self.assertFalse(handoff.retire_opt_in_job(raw,{**valid,"status":"indeterminate"}))
        self.assertFalse(handoff.retire_opt_in_job(raw,{**valid,"job":"JOB-OTHER"}))
        self.assertFalse(handoff.retire_opt_in_job(raw,{**valid,"input_sha256":"f"*64}))
        self.assertFalse(handoff.retire_opt_in_job(
            json.dumps({k:v for k,v in job.items() if k!="handoff"}),valid))
        self.assertFalse(handoff.retire_opt_in_job("not JSON",valid))
        self.assertFalse(handoff.retire_opt_in_job(
            json.dumps({**job,"handoff":{"unexpected":"yes"}}),valid))
        self.assertFalse(handoff.retire_opt_in_job(
            json.dumps({**job,"handoff":[]}),valid))

    def test_untrusted_json_type_errors_are_categorical(self):
        job,raw,signal=fixture()
        for altered in (
            {**signal,"status":["DONE"]},
            {**signal,"status":{"value":"DONE"}},
            {**signal,"run_id":[]},
            {**signal,"run_id":{"id":RUN_ID}},
            {**signal,"schema":[]},
            {**signal,"base_sha":[]},
        ):
            with self.assertRaises(ValueError):
                handoff.validate_signal(json.dumps(altered))
            self.assertFalse(handoff.retire_after_receipt(
                json.dumps(altered),{"job":JOB_ID,
                    "input_sha256":handoff.job_digest(raw),
                    "status":"passed"}))

    def test_publication_recovers_already_present_receipt_and_retires_only_matching_active(self):
        # All git interactions are synthetic. No GitHub writes, no real
        # checkout, no worker execution and no real credentials.
        from types import SimpleNamespace
        from unittest.mock import patch
        job,raw,signal=fixture()
        signal["status"]="DONE"
        local={"job":JOB_ID,"input_sha256":handoff.job_digest(raw),
               "status":"passed","actions":[],"profile_id":None}
        remote_result={k:local[k] for k in ("job","input_sha256","status")}
        for exists,match in ((False,True),(True,True),(True,False)):
            with self.subTest(exists=exists,match=match):
                with tempfile.TemporaryDirectory() as tmp:
                    state=Path(tmp)
                    actions=[]
                    active_signal={**signal}
                    if not match:active_signal["job_id"]="JOB-OTHER"
                    def fake_git(*args,**kwargs):
                        if args==("rev-parse","origin/dev"):
                            return SimpleNamespace(returncode=0,
                                                   stdout=BASE+"\n",stderr="")
                        raise AssertionError("unexpected git query "+str(args))
                    def fake_run(argv,*,cwd=None,timeout=None,env=None):
                        actions.append(tuple(argv))
                        if argv[:3]==["git","clone","--shared"]:
                            checkout=Path(argv[-1])
                            checkout.mkdir(parents=True)
                        elif argv[:3]==["git","checkout","--detach"]:
                            checkout=Path(cwd)
                            active=checkout/handoff.PATH
                            active.parent.mkdir(parents=True)
                            active.write_text(json.dumps(active_signal))
                            if match:
                                pending=checkout/worker.QUEUE/(JOB_ID+".json")
                                pending.parent.mkdir(parents=True)
                                pending.write_text(raw)
                            if exists:
                                result=checkout/worker.RESULTS/(JOB_ID+".json")
                                result.parent.mkdir(parents=True)
                                result.write_text(json.dumps(remote_result))
                        return SimpleNamespace(returncode=0,stdout="",stderr="")
                    with (patch.object(worker,"state_root",return_value=state),
                          patch.object(worker,"remote_url",return_value="https://github.com/llocphann/Alis.git"),
                          patch.object(worker,"fetch_dev"),
                          patch.object(worker,"result_exists",return_value=exists),
                          patch.object(worker,"remote_text",return_value=json.dumps(remote_result)),
                          patch.object(worker,"git",side_effect=fake_git),
                          patch.object(worker,"run",side_effect=fake_run)):
                        worker.publish(JOB_ID,local)
                    stage=[a for a in actions if a[:3]==("git","add","--")]
                    pushed=[a for a in actions if a[:2]==("git","push")]
                    if exists and not match:
                        self.assertEqual(stage,[])
                        self.assertEqual(pushed,[])
                    elif exists:
                        self.assertEqual(stage,[("git","add","--",handoff.PATH,
                            worker.QUEUE+"/"+JOB_ID+".json")])
                        self.assertEqual(len(pushed),1)
                    else:
                        self.assertEqual(stage,[("git","add","--",
                                worker.RESULTS+"/"+JOB_ID+".json",handoff.PATH,
                                worker.QUEUE+"/"+JOB_ID+".json")])
                        self.assertEqual(len(pushed),1)
        with tempfile.TemporaryDirectory() as tmp:
            state=Path(tmp)
            conflicting={**remote_result,"input_sha256":"0"*64}
            with (patch.object(worker,"state_root",return_value=state),
                  patch.object(worker,"remote_url",return_value="https://github.com/llocphann/Alis.git"),
                  patch.object(worker,"fetch_dev"),
                  patch.object(worker,"result_exists",return_value=True),
                  patch.object(worker,"remote_text",return_value=json.dumps(conflicting)),
                  patch.object(worker,"run",side_effect=AssertionError("no git writes"))):
                with self.assertRaisesRegex(RuntimeError,"identity conflict"):
                    worker.publish(JOB_ID,local)

    def test_owner_digest_confirmation_required_before_local_approval(self):
        import contextlib
        import importlib.util
        import io
        from unittest.mock import patch
        from types import ModuleType
        cli=Path(__file__).resolve().parent/"AUTO-F01-github-handoff.py"
        spec=importlib.util.spec_from_file_location("auto_f01_approval_cli",cli)
        module=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        job,raw,signal=fixture()
        sha=handoff.job_digest(raw)
        with tempfile.TemporaryDirectory() as tmp:
            state=Path(tmp)
            with (patch.object(module,"inspect",return_value=(signal,job,raw)),
                  patch.object(module.worker,"state_root",return_value=state),
                  patch.object(module.worker,"load_receipt",return_value=None)):
                with self.assertRaisesRegex(ValueError,"approved job digest"):
                    module.main(["approve",JOB_ID,"--owner-approved",
                                 "--expected-sha256","0"*64])
                self.assertFalse(handoff.approval_path(state,JOB_ID).exists())
                out=io.StringIO()
                with contextlib.redirect_stdout(out):
                    self.assertEqual(module.main(["status",JOB_ID]),0)
                status=json.loads(out.getvalue())
                self.assertEqual(status["job_sha256"],sha)
                self.assertEqual(status["action_kinds"],["exec"])
                self.assertEqual(status["action_count"],1)
                self.assertFalse(status["dispatch_ready"])
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(module.main(["approve",JOB_ID,
                        "--owner-approved","--expected-sha256",sha]),0)
                self.assertTrue(handoff.approval_matches(state,job,raw))
    def test_doctor_requires_fresh_installed_handoff_worker(self):
        import importlib.util
        cli=Path(__file__).resolve().parent/"AUTO-F01-github-handoff.py"
        spec=importlib.util.spec_from_file_location("auto_f01_worker_doctor",cli)
        module=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        at=int(time.time())
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            installed={"worker_service_active":True,
                       "worker_unit_matches_checkout":True,
                       "worker_process_matches_checkout":True}
            with (patch.object(worker,"state_root",return_value=root),
                  patch.object(module,"installed_worker_info",return_value=installed)):
                self.assertFalse(module.running_worker_status(now=at)[
                    "worker_supports_github_handoff"])
                heartbeat=root/"pool.json"
                heartbeat.write_text(json.dumps({
                    "heartbeat_at_unix":at,
                    "github_handoff_contract":handoff.SCHEMA
                }))
                self.assertTrue(module.running_worker_status(now=at)[
                    "worker_supports_github_handoff"])
                assert module.running_worker_status(now=at)["diagnosis"]=="RUNNING_WORKER_HANDOFF_CONTRACT_OBSERVED"
                with patch.object(module,"installed_worker_info",return_value={
                        **installed,"worker_process_matches_checkout":False}):
                    report=module.running_worker_status(now=at)
                    self.assertFalse(report["worker_supports_github_handoff"])
                    self.assertEqual(report["diagnosis"],"WORKER_HANDOFF_MARKER_SOURCE_UNVERIFIED")
                self.assertFalse(module.running_worker_status(now=at)[
                    "managed_chat_transport_ready"])
                heartbeat.write_text(json.dumps({
                    "heartbeat_at_unix":at-100,
                    "github_handoff_contract":handoff.SCHEMA
                }))
                self.assertFalse(module.running_worker_status(now=at)[
                    "worker_supports_github_handoff"])
                heartbeat.write_text(json.dumps({
                    "heartbeat_at_unix":at,
                    "github_handoff_contract":"legacy-v0"
                }))
                self.assertFalse(module.running_worker_status(now=at)[
                    "worker_supports_github_handoff"])
                self.assertEqual(module.running_worker_status(now=at)["diagnosis"],
                                 "RUNNING_WORKER_OLDER_CODE_MAY_REQUIRE_CONTROLLED_RESTART")
                heartbeat.unlink()
                heartbeat.symlink_to(root/"untrusted")
                self.assertFalse(module.running_worker_status(now=at)[
                    "worker_supports_github_handoff"])



    def test_receipt_aware_restart_preflight_fails_closed(self):
        import importlib.util
        cli=Path(__file__).resolve().parent/"AUTO-F01-github-handoff.py"
        spec=importlib.util.spec_from_file_location("auto_f01_restart_preflight",cli)
        module=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        at=int(time.time())
        unit={"worker_service_active":True,
              "worker_unit_matches_checkout":True,
              "worker_process_matches_checkout":True}
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            with (patch.object(module.worker,"state_root",return_value=root),
                  patch.object(module,"installed_worker_info",return_value=unit)):
                heartbeat=root/"pool.json"
                heartbeat.write_text(json.dumps({
                    "heartbeat_at_unix":at,"github_handoff_contract":"legacy",
                    "running":[],"publishing":False}))
                report=module.running_worker_status(now=at)
                self.assertTrue(report["worker_restart_preflight_clear"])
                self.assertFalse(report["worker_restart_authorized"])
                self.assertTrue(report["worker_receipt_inventory_complete"])
                receipts=root/"receipts"
                receipts.mkdir()
                local=receipts/"JOB-no-retry.json"
                for phase in ("preparing","executing","finished","publishing"):
                    local.write_text(json.dumps({"phase":phase}))
                    report=module.running_worker_status(now=at)
                    self.assertFalse(report["worker_restart_preflight_clear"],phase)
                    self.assertTrue(report["worker_unsettled_receipts_present"])
                local.write_text(json.dumps({"phase":"published"}))
                report=module.running_worker_status(now=at)
                self.assertTrue(report["worker_restart_preflight_clear"])
                local.write_text("{")
                self.assertFalse(module.running_worker_status(now=at)[
                    "worker_receipt_inventory_complete"])
                local.unlink()
                local.symlink_to(root/"untrusted.json")
                self.assertFalse(module.running_worker_status(now=at)[
                    "worker_restart_preflight_clear"])
                local.unlink()
                for running,publishing in ((["JOB-active"],False),
                                           ([],True),(None,None)):
                    heartbeat.write_text(json.dumps({
                        "heartbeat_at_unix":at,"github_handoff_contract":"legacy",
                        "running":running,"publishing":publishing}))
                    self.assertFalse(module.running_worker_status(now=at)[
                        "worker_restart_preflight_clear"])
                heartbeat.write_text(json.dumps({
                    "heartbeat_at_unix":at-100,"github_handoff_contract":"legacy",
                    "running":[],"publishing":False}))
                self.assertFalse(module.running_worker_status(now=at)[
                    "worker_restart_preflight_clear"])

    def test_receipt_inventory_reports_only_categorical_blockers(self):
        import importlib.util
        cli=Path(__file__).resolve().parent/"AUTO-F01-github-handoff.py"
        spec=importlib.util.spec_from_file_location("auto_f01_receipt_categorizer",cli)
        module=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            with patch.object(module.worker,"state_root",return_value=root):
                empty=module.pending_receipt_health()
                self.assertTrue(empty["worker_receipt_inventory_complete"])
                self.assertEqual(empty["worker_receipt_count_capped"],0)
                folder=root/"receipts"
                folder.mkdir()
                private=folder/"JOB-private-123.json"
                private.write_text(json.dumps({"phase":"published",
                                               "token":"SECRET-DO-NOT-EMIT"}))
                report=module.pending_receipt_health()
                self.assertTrue(report["worker_receipt_inventory_complete"])
                self.assertEqual(report["worker_receipt_phase_counts"]["published"],1)
                self.assertNotIn("SECRET-DO-NOT-EMIT",json.dumps(report))
                self.assertNotIn("JOB-private-123",json.dumps(report))
                private.write_text(json.dumps({"phase":"finished"}))
                report=module.pending_receipt_health()
                self.assertTrue(report["worker_unsettled_receipts_present"])
                self.assertEqual(report["worker_receipt_phase_counts"]["finished"],1)
                self.assertIsNone(report["worker_receipt_inventory_blocker"])
                tests=[
                    ('{"phase":"historical-v0"}',
                     "RECEIPT_ENTRY_UNKNOWN_OR_LEGACY_PHASE"),
                    ('{"phase":{} }',"RECEIPT_ENTRY_UNKNOWN_OR_LEGACY_PHASE"),
                    ('{"phase":"published"',"RECEIPT_ENTRY_INVALID_JSON"),
                    ('[]',"RECEIPT_ENTRY_NOT_OBJECT"),
                    ('x'*65537,"RECEIPT_ENTRY_SIZE_LIMIT_EXCEEDED"),
                ]
                for raw,expected in tests:
                    private.write_text(raw)
                    report=module.pending_receipt_health()
                    self.assertFalse(report["worker_receipt_inventory_complete"])
                    self.assertIsNone(report["worker_unsettled_receipts_present"])
                    self.assertEqual(report["worker_receipt_inventory_blocker"],expected)
                    self.assertNotIn("JOB-private-123",json.dumps(report))
                private.unlink()
                other=folder/"private-debug.tmp"
                other.write_text("some important data; do not delete")
                report=module.pending_receipt_health()
                self.assertEqual(report["worker_receipt_inventory_blocker"],
                                 "RECEIPT_ENTRY_UNEXPECTED_FILENAME")
                self.assertTrue(other.exists(),"doctor must be read-only")
                other.unlink()
                private.symlink_to(root/"private-unreadable")
                report=module.pending_receipt_health()
                self.assertEqual(report["worker_receipt_inventory_blocker"],
                                 "RECEIPT_ENTRY_SYMLINK")
                private.unlink()
                folder.rmdir()
                folder.symlink_to(root/"private-unreadable")
                report=module.pending_receipt_health()
                self.assertEqual(report["worker_receipt_inventory_blocker"],
                                 "UNSAFE_RECEIPT_DIRECTORY_SYMLINK")
                self.assertFalse(report["worker_receipt_inventory_complete"])

    def test_doctor_checks_real_unit_process_without_printing_pid_paths(self):
        import importlib.util
        import os
        from types import SimpleNamespace
        cli=Path(__file__).resolve().parent/"AUTO-F01-github-handoff.py"
        spec=importlib.util.spec_from_file_location("auto_f01_worker_doctor_proc",cli)
        module=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        root=Path(__file__).resolve().parents[1]
        script=(root/"automation"/"worker"/"daemon.py").resolve()
        sample=SimpleNamespace(returncode=0,stdout=(
            "ActiveState=active\nMainPID=41341\nWorkingDirectory="+str(root)+"\n"))
        command=b"/usr/bin/python3\x00"+os.fsencode(str(script))+b"\x00"
        with (patch.object(module.subprocess,"run",return_value=sample),
              patch.object(Path,"read_bytes",return_value=command),
              patch.object(module.os,"readlink",return_value=str(root))):
            details=module.installed_worker_info()
            self.assertEqual(details,{
                "worker_service_active":True,
                "worker_unit_matches_checkout":True,
                "worker_process_matches_checkout":True})
            self.assertNotIn("41341",json.dumps(details))
            self.assertNotIn(str(root),json.dumps(details))
        with (patch.object(module.subprocess,"run",return_value=sample),
              patch.object(Path,"read_bytes",return_value=command),
              patch.object(module.os,"readlink",return_value="/tmp/other-checkout")):
            details=module.installed_worker_info()
            self.assertFalse(details["worker_process_matches_checkout"])
        bad=SimpleNamespace(returncode=1,stdout="",stderr="PRIVATE-CREDENTIAL")
        with patch.object(module.subprocess,"run",return_value=bad):
            self.assertFalse(module.installed_worker_info()["worker_service_active"])

    def test_stale_unstarted_manifest_prunes_once_without_touching_receipts(self):
        from types import SimpleNamespace
        from automation.manager import credentials
        job,raw,signal=fixture()
        at=signal["updated_unix"]+3600+handoff.EXPIRED_GRACE+10
        with tempfile.TemporaryDirectory() as sample_root:
            with self.assertRaisesRegex(handoff.HandoffWait,"expired"):
                handoff.ready(json.dumps(signal),job,raw,Path(sample_root),now=at)
        self.assertEqual(handoff.expired_for_retirement(json.dumps(signal),now=at),JOB_ID)
        self.assertIsNone(handoff.expired_for_retirement(json.dumps(signal),
                                                         now=signal["expires_unix"]))
        cases=("expired_unstarted","pending_receipt","control_changed","push_failed")
        for case in cases:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp); actions=[]
                approval=handoff.approval_path(root,JOB_ID)
                approval.parent.mkdir()
                approval.write_text(json.dumps(handoff.approval_payload(job,raw)))
                receipt_file=root/"receipts"/(JOB_ID+".json")
                if case=="pending_receipt":
                    receipt_file.parent.mkdir()
                    receipt_file.write_text(json.dumps(
                        {"job":JOB_ID,"phase":"executing"}))
                def git(*args,**kw):
                    if args==("rev-parse","origin/dev"):
                        return SimpleNamespace(returncode=0,
                            stdout=BASE+"\n",stderr="")
                    raise AssertionError("unexpected git query")
                def run(argv,*,cwd=None,timeout=None,env=None):
                    actions.append(tuple(argv))
                    if argv[:3]==["git","clone","--shared"]:
                        Path(argv[-1]).mkdir(parents=True)
                    if argv[:3]==["git","checkout","--detach"]:
                        active=Path(cwd)/handoff.PATH
                        active.parent.mkdir(parents=True)
                        source={**signal,"run_id":str(uuid.uuid4())} if case=="control_changed" else signal
                        active.write_text(json.dumps(source))
                    exit_code=1 if case=="push_failed" and "push" in argv else 0
                    return SimpleNamespace(returncode=exit_code,stdout="",stderr="")
                with (patch.object(worker,"state_root",return_value=root),
                      patch.object(worker,"fetch_dev"),
                      patch.object(worker,"remote_text",return_value=json.dumps(signal)),
                      patch.object(worker,"remote_url",return_value="https://github.com/llocphann/Alis.git"),
                      patch.object(worker,"git",side_effect=git),
                      patch.object(worker,"run",side_effect=run),
                      patch.object(credentials,"status",return_value={"github":{}})):
                    if case=="push_failed":
                        with self.assertRaisesRegex(RuntimeError,"cleanup push failed"):
                            worker.prune_expired_handoff(now=at)
                    else:
                        result=worker.prune_expired_handoff(now=at)
                        expect={
                            "expired_unstarted":"expired_unstarted_handoff_pruned",
                            "pending_receipt":"unresolved_receipt_preserved",
                            "control_changed":"control_changed_or_receipt"}
                        self.assertEqual(result,expect[case])
                did_push=any("push" in argv for argv in actions)
                self.assertEqual(did_push,case in ("expired_unstarted","push_failed"))
                self.assertEqual(approval.exists(),case!="expired_unstarted")
                if case=="pending_receipt":
                    self.assertEqual(json.loads(
                        receipt_file.read_text())["phase"],"executing")
                else:
                    self.assertFalse(receipt_file.exists())


if __name__=="__main__":
    unittest.main()
