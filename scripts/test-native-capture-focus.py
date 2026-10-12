#!/usr/bin/env python3
"""Capture-only focus must own its target and respect the user on restoration."""
from unittest.mock import patch
import native_test_session as session

checks = 0
with patch.object(session, "_host_query", side_effect=[{"id": 22}, [{"id": 11}]]), patch.object(session.subprocess, "run") as run:
    session._restore_capture_focus("niri", (11, 22), {})
    assert run.call_count == 1 and run.call_args.args[0][-1] == "11"
    checks += 1
with patch.object(session, "_host_query", return_value={"id": 33}), patch.object(session.subprocess, "run") as run:
    session._restore_capture_focus("niri", (11, 22), {})
    assert not run.called, "user's new focus must not be stolen"
    checks += 1
with patch.object(session, "_host_query", side_effect=[{"id": 22}, [{"id": 33}]]), patch.object(session.subprocess, "run") as run:
    session._restore_capture_focus("niri", (11, 22), {})
    assert not run.called, "closed previous target must not be replaced with another"
    checks += 1
with patch.object(session, "_host_query", return_value=None), patch.object(session.subprocess, "run") as run:
    try:
        session._focus_for_capture("niri", 55, {})
    except RuntimeError:
        pass
    else:
        raise AssertionError("capture without a restorable target must be refused")
    assert not run.called
    checks += 1
with patch.object(session, "_host_query", side_effect=[{"id": 11}, [{"id": 33, "pid": 88}, {"id": 22, "pid": 55}]]), patch.object(session.subprocess, "run") as run:
    assert session._focus_for_capture("niri", 55, {}) == (11, 22)
    assert run.call_args.args[0][-1] == "22", "only the private Niri PID may receive capture focus"
    checks += 1
print(f"PASS: {checks} capture focus ownership/restore/refusal checks (simulated protocol)")
