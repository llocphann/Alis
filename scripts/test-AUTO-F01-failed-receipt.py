#!/usr/bin/env python3
"""A real isolated failed job may reach Cloudbot diagnostics, never completion."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import uuid
from unittest import TestCase, main
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from automation import taskflow as tf, managed_tasks, queue, lifecycle
from automation.manager import store
from automation.chat_bridge import ui_scheduler


class FailedReceiptTests(TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.folder=Path(self.tmp.name)
        env=patch.dict(os.environ,{'XDG_CONFIG_HOME':str(self.folder/'config'),
                                   'XDG_STATE_HOME':str(self.folder/'state'),
                                   'ALIS_CHATGPT_PROJECT':'Automatic Alis'})
        env.start();self.addCleanup(env.stop)
        checkout=self.folder/'checkout';checkout.mkdir()
        self.checkout=checkout
        (checkout/'scripts').mkdir()
        (checkout/'scripts/test-private-fail.py').write_text('raise SystemExit(7)\n')
        subprocess.run(['git','init','-q',str(checkout)],check=True)
        subprocess.run(['git','-C',str(checkout),'add','.'],check=True)
        subprocess.run(['git','-C',str(checkout),'-c','user.name=Fixture','-c','user.email=fixture@example.invalid',
                        'commit','-qm','private failure fixture'],check=True)
        self.sha=subprocess.check_output(['git','-C',str(checkout),'rev-parse','HEAD'],text=True).strip()
        task={'repository':'llocphann/Alis','code':'AUTO-R01','issue_number':104,
              'issue_url':'https://github.com/llocphann/Alis/issues/104','title':'[AUTO-R01] fixture',
              'body':'Private test only','issue_updated_at':'2026-10-16T00:00:00Z',
              'comments':[],'branch':'dev','base_sha':self.sha}
        tf.intake(task);self.pid=managed_tasks._ensure_profile('llocphann/Alis','AUTO-R01')
        self.bundle=tf.package({'schema':'alis.local-handoff.v1','task':task,
            'commands':[['git','diff','--check'],['python3','scripts/test-private-fail.py'],
                        ['python3','scripts/test-unrun.py']],
            'checkpoint':'private','next_prompt':'Cloudbot-authored instruction: inspect the exact receipt and repair.'})
        tf.save_handoff('AUTO-R01',self.bundle)
        self.receipt=tf.run_task('AUTO-R01',checkout,approved=True)
        assert self.receipt['state']=='failed' and len(self.receipt['steps'])==2
        queue._save({'schema':queue.QUEUE_SCHEMA,'mode':'ordered','state':'active','approved_start':True,
            'active':{'repository':'llocphann/Alis','code':'AUTO-R01'},
            'items':[{'repository':'llocphann/Alis','code':'AUTO-R01','source_sha':self.sha,'state':'active'}]})
        store.change_state(lambda c,s:s['profiles'][self.pid].update(desired='run',request='initial'))

    def record(self):return tf.load_task('AUTO-R01')

    def test_failed_receipt_is_explicit_diagnostic_opt_in(self):
        record=self.record()
        with self.assertRaises(tf.TaskError):lifecycle._verified_local_receipt(record)
        with self.assertRaises(tf.TaskError):lifecycle._verified_local_receipt(record,allow_failed="true")
        self.assertEqual(lifecycle._verified_local_receipt(record,allow_failed=True),self.bundle)
        profile=next(p for p in store.read_snapshot()[0]['profiles'] if p['id']==self.pid)
        prompt=managed_tasks.prompt(profile,'continuation')
        self.assertIn(self.bundle['id'],prompt);self.assertIn(self.bundle['sha256'],prompt)
        self.assertIn('receipt FAILED',prompt);self.assertIn('Cloudbot-authored instruction',prompt)
        self.assertEqual(self.record()['status'],'needs_review')

    def test_ui_diagnostic_receives_failure_without_replay_or_queue_advance(self):
        def observed(command,prompt,**kwargs):
            self.assertIn('receipt FAILED',prompt)
            return {'ui_target_key':'a'*64,'response':{'text':'Repair pending.\nALIS_LOOP:CONTINUE'}}
        # Initial task text remains the original intake; failed follow-up is
        # specifically a continuation of its existing UI conversation.
        store.change_state(lambda c,s:s['profiles'][self.pid].update(request='continuation',session={
            'transport':'alis-ui-once','project_name':'Automatic Alis','ui_target_key':'a'*64}))
        with patch.object(tf,'run_local',side_effect=AssertionError('No job replay')):
            self.assertEqual(ui_scheduler.queue_tick(desktop=observed),'CONTINUE')
        self.assertEqual(queue.view()['state'],'active')
        self.assertEqual(self.record()['status'],'needs_review')
        self.assertEqual(self.receipt['steps'][-1]['exit_code'],7)

    def test_done_cannot_promote_failed_local_receipt(self):
        self.assertEqual(ui_scheduler.queue_tick(desktop=lambda *a,**kw:{
            'ui_target_key':'a'*64,'response':{'text':'ALIS_LOOP:DONE'}}),'DONE')
        with self.assertRaises(tf.TaskError):managed_tasks.reconcile_ui_once()
        self.assertEqual(queue.view()['state'],'active');self.assertEqual(self.record()['status'],'needs_review')

    def test_unknown_timeout_or_false_failure_stays_blocked(self):
        path=tf.state_dir()/'receipts'/(self.bundle['id']+'.json')
        for changes in [{'exit_code':None,'error':'timeout'},{'exit_code':0},{'argv':['python3','scripts/test-other.py']}]:
            receipt=json.loads(json.dumps(self.receipt));receipt['steps'][-1].update(changes)
            tf._atomic_json(path,receipt)
            with self.assertRaises(tf.TaskError):lifecycle._verified_local_receipt(self.record(),allow_failed=True)
            with patch.object(tf,'run_local',side_effect=AssertionError('No replay')):
                self.assertEqual(ui_scheduler.queue_tick(desktop=lambda *a,**kw:self.fail('No Send')),
                                 'ALIS_UI_QUEUE_LOCAL_RECEIPT_REQUIRES_REVIEW')

    def test_foreign_execution_sha_stays_blocked(self):
        record=self.record();record['latest_receipt']['source_sha']='b'*40;tf._save_task(record)
        with self.assertRaises(tf.TaskError):lifecycle._verified_local_receipt(record,allow_failed=True)
        self.assertEqual(ui_scheduler.queue_tick(desktop=lambda *a,**kw:self.fail('No Send')),
                         'ALIS_UI_QUEUE_LOCAL_RECEIPT_REQUIRES_REVIEW')

    def prepare_ui_review_and_repair(self):
        from automation.chat_bridge.send_journal import prepare_send, acknowledge_completed
        attempt=str(uuid.uuid4())
        text='Reviewed failed job '+self.bundle['id']+' digest '+self.bundle['sha256']+' source '+self.sha+'\nALIS_LOOP:CONTINUE'
        journal,jid=prepare_send(store.state_dir(),'send','Controller failure summary '+self.bundle['id'])
        intent=json.loads(journal.read_text())
        acknowledge_completed(journal,jid)
        store._write(store.state_dir()/'ui-responses'/self.pid/(attempt+'.json'),{
            'transport':'alis-ui-once','attempt_id':attempt,'directive':'CONTINUE','response':text,
            'ui_target_key':'a'*64,'at_unix':int(time.time()),
            'ui_send_intent':{k:intent[k] for k in ['id','command','prompt_sha256']}})
        store.change_state(lambda c,s:s['profiles'][self.pid].update(desired='paused',status='paused',
            run_active=False,pending=None,last_success='CONTINUE',last_ui_response_attempt=attempt,
            session={'transport':'alis-ui-once','project_name':'Automatic Alis','ui_target_key':'a'*64}))
        subprocess.run(['git','-C',str(self.checkout),'-c','user.name=Fixture','-c','user.email=fixture@example.invalid',
                        'commit','--allow-empty','-qm','new reviewed source fixture'],check=True)
        newsha=subprocess.check_output(['git','-C',str(self.checkout),'rev-parse','HEAD'],text=True).strip()
        repair=tf.package({**self.bundle['payload'],'execution_sha':newsha})
        return attempt,repair

    def save_repair(self,attempt,repair,**changes):
        args={'approved':True,'expected_job_id':self.bundle['id'],
              'expected_response_attempt':attempt,'expected_snapshot_id':queue.view()['snapshot_id'],**changes}
        return managed_tasks.save_reviewed_ui_repair_handoff('AUTO-R01',repair,**args)

    def test_reviewed_repair_preserves_failed_plan_and_never_runs_or_advances(self):
        attempt,repair=self.prepare_ui_review_and_repair();before=queue.view()
        with patch.object(tf,'run_local',side_effect=AssertionError('No execution during handoff')):
            self.assertFalse(self.save_repair(attempt,repair)['duplicate'])
            self.assertTrue(self.save_repair(attempt,repair)['duplicate'])
        record=self.record();self.assertEqual(record['handoff'],repair)
        self.assertIsNone(record['latest_receipt']);self.assertEqual(record['status'],'handoff_ready')
        self.assertEqual(record['failed_handoff_reviews'][0]['handoff'],self.bundle)
        self.assertEqual(record['failed_handoff_reviews'][0]['receipt']['state'],'failed')
        self.assertEqual(record['failed_handoff_reviews'][0]['ui_review']['attestation'],'local-ui-only')
        self.assertEqual(queue.view(),before)
        old=json.loads((tf.state_dir()/'receipts'/(self.bundle['id']+'.json')).read_text())
        self.assertEqual(old['state'],'failed');self.assertEqual(old['steps'][-1]['exit_code'],7)

    def test_repair_rejects_missing_approval_stale_snapshot_and_unreviewed_identity(self):
        attempt,repair=self.prepare_ui_review_and_repair();before=self.record()
        for changes in [{'approved':False},{'expected_snapshot_id':'b'*64},
                        {'expected_job_id':'JOB-'+'b'*24},{'expected_response_attempt':str(uuid.uuid4())}]:
            with self.assertRaises(tf.TaskError):self.save_repair(attempt,repair,**changes)
            self.assertEqual(self.record(),before)
        path=store.state_dir()/'ui-responses'/self.pid/(attempt+'.json')
        packet=json.loads(path.read_text());packet['response']=packet['response'].replace(self.bundle['sha256'],'b'*64)
        store._write(path,packet)
        with self.assertRaisesRegex(tf.TaskError,'exact failed job'):self.save_repair(attempt,repair)
        self.assertEqual(self.record(),before)

    def test_repair_rejects_pending_turn_same_source_and_native_target(self):
        attempt,repair=self.prepare_ui_review_and_repair()
        with self.assertRaisesRegex(tf.TaskError,'new source'):self.save_repair(attempt,self.bundle)
        store.change_state(lambda c,s:s['profiles'][self.pid].update(pending={'transport':'alis-ui-once'}))
        with self.assertRaises(tf.TaskError):self.save_repair(attempt,repair)
        store.change_state(lambda c,s:s['profiles'][self.pid].update(pending=None,
            session={'transport':'native','conversation_id':'private-native'}))
        with self.assertRaises(RuntimeError):self.save_repair(attempt,repair)
        self.assertEqual(self.record()['handoff'],self.bundle)


if __name__=='__main__':main()
