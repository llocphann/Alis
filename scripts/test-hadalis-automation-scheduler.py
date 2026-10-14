#!/usr/bin/env python3
"""True simultaneous profile dispatch and isolated WAIT_RESULT/Pause/Stop."""
import threading
import time
from types import SimpleNamespace
from unittest.mock import patch
from automation_test_helpers import environment, profile, Transport, daemon, control, store


def main():
    with environment():
        a,b=profile('A'),profile('B')
        transport=Transport();transport.barrier=threading.Barrier(2)
        with patch.object(daemon,'native_command',side_effect=transport):
            daemon.tick(100)
            state=store.read_snapshot()[1]
            assert transport.peak==2
            assert state['owner_id'] is None
            assert state['profiles'][a]['pending']['user_message_id']!=state['profiles'][b]['pending']['user_message_id']
            assert state['profiles'][a]['session']['conversation_id']!=state['profiles'][b]['session']['conversation_id']
            control.profile_action('pause',a)
            assert store.read_snapshot()[1]['profiles'][b]['desired']=='run'
            transport.reply(a);transport.reply(b,'HADALIS_LOOP:WAIT_RESULT JOB-B')
            daemon.tick(102)
            assert store.read_snapshot()[1]['profiles'][a]['status']=='paused'
            assert store.read_snapshot()[1]['profiles'][b]['status']=='waiting_result'
            c=profile('C');transport.barrier=None
            # B's job wait neither stops nor queues C behind a global owner.
            with patch.object(daemon,'job_result',return_value=None): daemon.tick(104)
            assert transport.pending(c)
            assert store.read_snapshot()[1]['profiles'][b]['job_id']=='JOB-B'
            control.profile_action('stop',c)
            assert store.read_snapshot()[1]['profiles'][b]['desired']=='run'
    with environment():
        entered,release=threading.Event(),threading.Event()
        def git(args,**kwargs):
            if args[1]=='fetch':
                entered.set();assert release.wait(5)
                return SimpleNamespace(returncode=0)
            return SimpleNamespace(returncode=1)
        with patch.object(daemon.subprocess,'run',side_effect=git):
            first=threading.Thread(target=daemon.job_result,args=('JOB-network-A',))
            first.start()
            try:
                assert entered.wait(5)
                began=time.monotonic()
                assert daemon.job_result('JOB-network-B') is None
                assert time.monotonic()-began<1, 'another job must not occupy a transport slot waiting for Git'
            finally:release.set();first.join(5)
            assert not first.is_alive()
    print('PASS: simultaneous isolated sessions, Pause/Stop, WAIT_RESULT and nonblocking shared Git observation')

if __name__=='__main__':main()
