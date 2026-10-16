#!/usr/bin/env python3
"""A real isolated failed job may reach Cloudbot diagnostics, never completion."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
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


if __name__=='__main__':main()
