#!/usr/bin/env python3
"""Recover by identity without resubmitting after crashes or transport failure."""
import json
from unittest.mock import patch
from automation_test_helpers import environment, profile, Transport, daemon, control, store


def main():
    with environment():
        pid=profile();t=Transport();t.uncertain=True
        with patch.object(daemon,'native_command',side_effect=t):
            daemon.tick(100)
            p=t.pending(pid);uid=p['user_message_id'];assert p['phase']=='dispatching'
            t.down=True
            for now in (200,400,800,1200,1600):daemon.tick(now)
            assert t.count('submit')==1
            assert store.read_snapshot()[1]['profiles'][pid]['desired']=='run'
            # Restart has only the persisted JSON receipt; no selected UI needed.
            t.down=False;t.reply(pid,'HADALIS_CHECKPOINT:{"phase":"test","summary":"diagnosed","next":"validate","evidence_ids":[]}\nHADALIS_LOOP:CONTINUE')
            daemon.tick(2000)
            item=store.read_snapshot()[1]['profiles'][pid]
            assert item['pending'] is None and item['iterations']==1 and item['prompts_sent']==1
            assert item['checkpoint']['phase']=='test'
            assert t.count('submit')==1
            daemon.tick(2002)
            assert t.count('submit')==2 and t.pending(pid)['user_message_id']!=uid
    with environment():
        pid=profile('Legacy');other=profile('Independent')
        legacy={'response_action_count':3,'prepared_at_unix':100,'kind':'initial','counted':True}
        def old(c,s):
            s['engine_version']=1;s['owner_id']=pid
            s['profiles'][pid].update(pending=legacy,run_active=False,active_project_name='Hadalis Cloud')
        store.change_state(old);t=Transport()
        def native(op,**kwargs):
            if op=='adopt':raise RuntimeError('identity remains ambiguous')
            return t(op,**kwargs)
        with patch.object(daemon,'native_command',side_effect=native):daemon.tick(102)
        state=store.read_snapshot()[1]
        assert state['engine_version']==2 and state['owner_id'] is None
        assert state['profiles'][pid]['pending']['response_action_count']==3
        assert state['profiles'][other]['pending']
        assert (store.state_dir()/'migration-v1.json').exists()
    with environment():
        pid=profile();t=Transport()
        with patch.object(daemon,'native_command',side_effect=t):
            daemon.tick(100);t.reply(pid,'HADALIS_LOOP:DONE')
            pending=t.pending(pid)
            receipt={'conversation_id':pending['conversation_id'],'user_message_id':pending['user_message_id'],
                'response':{'message_id':'finished','text':'HADALIS_LOOP:DONE'},'at_unix':102}
            # Simulate crash after receipt fsync, before manager state commit.
            store._write(store.state_dir()/'responses'/pid/(pending['user_message_id']+'.json'),receipt)
            t.down=True;daemon.tick(102)
            item=store.read_snapshot()[1]['profiles'][pid]
            assert item['status']=='completed' and item['iterations']==1
            assert t.count('poll')==0 and t.count('submit')==1
            daemon.tick(104);assert store.read_snapshot()[1]['profiles'][pid]['iterations']==1
    for last_action,expected in (("resume","run"),("pause","paused"),("stop","paused")):
        with environment():
            pid=profile('Paused v1');t=Transport()
            def paused(c,s):
                s.update(engine_version=1,owner_id=pid)
                s['profiles'][pid].update(desired='paused',poll_errors=4,last_error='v1 DOM timeout',pending={'prepared_at_unix':100,'kind':'initial','counted':True})
                store.event(s,pid,last_action)
            store.change_state(paused)
            with patch.object(daemon,'native_command',side_effect=RuntimeError('legacy identity unresolved')):daemon.tick(102)
            assert store.read_snapshot()[1]['profiles'][pid]['desired']==expected
            assert t.count('submit')==0
    print('PASS: ambiguous submission, automatic backoff/recovery, safe v1 migration including evidenced automatic error pause, explicit Pause/Stop precedence, fsynced response receipt')

if __name__=='__main__':main()
