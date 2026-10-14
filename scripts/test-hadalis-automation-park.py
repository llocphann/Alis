#!/usr/bin/env python3
"""Legacy parking state is preserved; isolation requires no navigation handover."""
from unittest.mock import patch
from automation_test_helpers import environment, profile, Transport, daemon, control, store


def main():
    with environment():
        old,new=profile('Old'),profile('New')
        pending={'response_action_count':3,'kind':'initial','prepared_at_unix':90,'counted':True}
        def parked(c,s):
            s['profiles'][old].update(desired='stopped',parked_pending=True,pending=pending,
                active_project_name='Hadalis Cloud',status='parked_unresolved')
        store.change_state(parked);t=Transport()
        def native(op,**kw):
            if op=='adopt':raise RuntimeError('original identity remains unavailable')
            return t(op,**kw)
        with patch.object(daemon,'native_command',side_effect=native):daemon.tick(100)
        state=store.read_snapshot()[1]
        assert state['profiles'][old]['pending']['response_action_count']==3
        assert state['profiles'][old]['desired']=='stopped'
        assert state['profiles'][new]['pending']
        before=store.read_snapshot()[1]
        try:control.request_park_unresolved(old)
        except ValueError as exc:assert 'independently' in str(exc)
        else:raise AssertionError('park endpoint must not discard/release a session')
        assert store.read_snapshot()[1]==before
    print('PASS: parked v1 state is preserved, independent progress without UI handover')

if __name__=='__main__':main()
