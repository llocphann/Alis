#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import os
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from automation.chat_bridge.controller import (  # noqa: E402
    BridgeAction,
    BridgeState,
    transition,
)
from automation.chat_bridge.runtime import (  # noqa: E402
    clear_state,
    load_state,
    process_response,
    save_state,
)
from automation.chat_bridge.protocol import (  # noqa: E402
    CONTINUATION_PROMPT,
    GITHUB_MENTION,
    ROTATION_BOOTSTRAP_PROMPT,
    DirectiveKind,
    ProtocolError,
    parse_loop_directive,
    prompt_has_required_github_mention,
)


def expect_protocol_error(text: str) -> None:
    try:
        parse_loop_directive(text)
    except ProtocolError:
        return
    raise AssertionError(f"expected ProtocolError for {text!r}")


def main() -> None:
    assert prompt_has_required_github_mention(CONTINUATION_PROMPT)
    assert prompt_has_required_github_mention(ROTATION_BOOTSTRAP_PROMPT)
    assert CONTINUATION_PROMPT.splitlines()[0] == GITHUB_MENTION
    assert ROTATION_BOOTSTRAP_PROMPT.splitlines()[0] == GITHUB_MENTION
    assert "fetch the current dev head" in CONTINUATION_PROMPT.casefold()
    assert "strict-lossless optimization research" in CONTINUATION_PROMPT.casefold()
    assert "do not stop after one round" in CONTINUATION_PROMPT.casefold()
    assert "do not switch to work mode" in CONTINUATION_PROMPT.casefold()
    assert "do not switch to work mode" in ROTATION_BOOTSTRAP_PROMPT.casefold()
    assert "HADALIS_LOOP:CONNECTOR_BLOCKED GITHUB" in CONTINUATION_PROMPT

    wait = parse_loop_directive("notes\nHADALIS_LOOP:WAIT_RESULT JOB-000127\n")
    assert wait.kind is DirectiveKind.WAIT_RESULT
    assert wait.argument == "JOB-000127"
    wait_transition = transition(BridgeState.READY, wait)
    assert wait_transition.state is BridgeState.WAIT_LOCAL
    assert wait_transition.action is BridgeAction.WAIT_RESULT
    assert wait_transition.job_id == "JOB-000127"

    cont = parse_loop_directive("HADALIS_LOOP:CONTINUE")
    assert transition(BridgeState.WAIT_LOCAL, cont).action is BridgeAction.SEND_CONTINUATION

    rotate = parse_loop_directive("HADALIS_LOOP:ROTATE")
    assert transition(BridgeState.READY, rotate).state is BridgeState.ROTATE_PENDING

    blocked = parse_loop_directive("HADALIS_LOOP:CONNECTOR_BLOCKED GITHUB")
    blocked_transition = transition(BridgeState.READY, blocked)
    assert blocked_transition.state is BridgeState.CONNECTOR_BLOCKED
    assert blocked_transition.action is BridgeAction.WAIT_CONNECTOR

    done = parse_loop_directive("HADALIS_LOOP:DONE")
    assert transition(BridgeState.READY, done).state is BridgeState.DONE

    expect_protocol_error("")
    expect_protocol_error("HADALIS_LOOP:WAIT_RESULT")
    expect_protocol_error("HADALIS_LOOP:WAIT_RESULT ../../escape")
    expect_protocol_error("HADALIS_LOOP:CONTINUE unexpected")
    expect_protocol_error("HADALIS_LOOP:CONNECTOR_BLOCKED OTHER")
    expect_protocol_error("HADALIS_LOOP:CONTINUE\nHADALIS_LOOP:DONE")

    try:
        transition(BridgeState.DONE, cont)
    except ValueError:
        pass
    else:
        raise AssertionError("DONE must remain terminal")

    old_state_home = os.environ.get("XDG_STATE_HOME")
    try:
        with tempfile.TemporaryDirectory() as tmp:
            os.environ["XDG_STATE_HOME"] = tmp
            assert load_state() is None
            save_state(BridgeState.WAIT_LOCAL, "JOB-000127")
            assert load_state() == (BridgeState.WAIT_LOCAL, "JOB-000127")
            save_state(BridgeState.DONE)
            assert load_state() == (BridgeState.DONE, None)

            done, command, prompt = process_response(
                "HADALIS_LOOP:DONE",
                continuous_research=True,
            )
            assert done is False
            assert command == "send"
            assert prompt == CONTINUATION_PROMPT
            assert load_state() == (BridgeState.READY, None)

            clear_state()
            assert load_state() is None
    finally:
        if old_state_home is None:
            os.environ.pop("XDG_STATE_HOME", None)
        else:
            os.environ["XDG_STATE_HOME"] = old_state_home

    print("PASS: Hadalis chat-bridge protocol, state, and deterministic transitions")


if __name__ == "__main__":
    main()
