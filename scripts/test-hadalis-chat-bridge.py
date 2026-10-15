#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import json
from types import SimpleNamespace
from unittest.mock import patch
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
from automation.chat_bridge import runtime
from automation.chat_bridge.send_journal import prepare_send, acknowledge_completed
from automation.chat_bridge.runtime import (  # noqa: E402
    clear_state,
    load_state,
    process_response,
    save_state,
)
from automation.chat_bridge.protocol import (  # noqa: E402
    CONTINUATION_PROMPT,
    GITHUB_APP_MENTION,
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
    assert CONTINUATION_PROMPT.splitlines()[0] == GITHUB_APP_MENTION
    assert ROTATION_BOOTSTRAP_PROMPT.splitlines()[0] == GITHUB_APP_MENTION
    assert "fetch the current dev head" in CONTINUATION_PROMPT.casefold()
    assert "active alis automation task" in CONTINUATION_PROMPT.casefold()
    assert "exact job-id receipt" in CONTINUATION_PROMPT.casefold()
    assert "do not switch to work mode" in CONTINUATION_PROMPT.casefold()
    assert "do not switch to work mode" in ROTATION_BOOTSTRAP_PROMPT.casefold()
    assert "ALIS_LOOP:CONNECTOR_BLOCKED GITHUB" in CONTINUATION_PROMPT

    wait = parse_loop_directive("notes\nALIS_LOOP:WAIT_RESULT JOB-000127\n")
    # Migration: accept old saved markers without generating new ones.
    assert parse_loop_directive("HADALIS_LOOP:CONTINUE").kind is DirectiveKind.CONTINUE
    assert wait.kind is DirectiveKind.WAIT_RESULT
    assert wait.argument == "JOB-000127"
    wait_transition = transition(BridgeState.READY, wait)
    assert wait_transition.state is BridgeState.WAIT_LOCAL
    assert wait_transition.action is BridgeAction.WAIT_RESULT
    assert wait_transition.job_id == "JOB-000127"

    cont = parse_loop_directive("ALIS_LOOP:CONTINUE")
    assert transition(BridgeState.WAIT_LOCAL, cont).action is BridgeAction.SEND_CONTINUATION

    rotate = parse_loop_directive("ALIS_LOOP:ROTATE")
    assert transition(BridgeState.READY, rotate).state is BridgeState.ROTATE_PENDING

    blocked = parse_loop_directive("ALIS_LOOP:CONNECTOR_BLOCKED GITHUB")
    blocked_transition = transition(BridgeState.READY, blocked)
    assert blocked_transition.state is BridgeState.CONNECTOR_BLOCKED
    assert blocked_transition.action is BridgeAction.WAIT_CONNECTOR

    done = parse_loop_directive("ALIS_LOOP:DONE")
    assert transition(BridgeState.READY, done).state is BridgeState.DONE

    expect_protocol_error("")
    expect_protocol_error("ALIS_LOOP:WAIT_RESULT")
    expect_protocol_error("ALIS_LOOP:WAIT_RESULT ../../escape")
    expect_protocol_error("ALIS_LOOP:CONTINUE unexpected")
    expect_protocol_error("ALIS_LOOP:CONNECTOR_BLOCKED OTHER")
    expect_protocol_error("ALIS_LOOP:CONTINUE\nALIS_LOOP:DONE")
    expect_protocol_error("ALIS_LOOP:CONTINUE\nHADALIS_LOOP:DONE")

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
                "ALIS_LOOP:DONE",
                continuous_research=True,
            )
            assert done is True and command is None and prompt is None
            assert load_state() == (BridgeState.DONE, None)

            # One UI attempt is durable before any subprocess invocation.
            state = runtime.state_root()
            intent, identity = prepare_send(state, "send", "private-test-prompt")
            record = json.loads(intent.read_text())
            assert record["schema"] == "alis.chat-ui-send.v1"
            assert record["prompt_sha256"] and "private-test-prompt" not in intent.read_text()
            try:
                prepare_send(state, "send", "private-test-prompt")
            except RuntimeError as error:
                assert "RECONCILIATION_REQUIRED" in str(error)
            else:
                raise AssertionError("unsettled UI send must block every retry")
            acknowledge_completed(intent, identity)
            assert not intent.exists()
            assert (state / "ui-send-journal" / "observed" /
                    (identity + ".json")).exists()

            # A timeout after send may have taken effect. Repeated startup
            # or process retry MUST NOT invoke a second Desktop subprocess.
            with patch.object(runtime, "run", side_effect=TimeoutError("uncertain")) as invoked:
                try:
                    runtime.desktop("send", "one-shot")
                except TimeoutError:
                    pass
                else:
                    raise AssertionError("simulated UI timeout was accepted")
                assert invoked.call_count == 1
                try:
                    runtime.desktop("send", "one-shot")
                except RuntimeError as error:
                    assert "RECONCILIATION_REQUIRED" in str(error)
                else:
                    raise AssertionError("ambiguous send was replayed")
                assert invoked.call_count == 1

            clear_state()
            assert load_state() is None
    finally:
        if old_state_home is None:
            os.environ.pop("XDG_STATE_HOME", None)
        else:
            os.environ["XDG_STATE_HOME"] = old_state_home

    # Successful read-only/synthetic completion retires ONE send intent; it
    # never grants native server-verified transport readiness.
    with tempfile.TemporaryDirectory() as tmp:
        with patch.dict(os.environ, {"XDG_STATE_HOME": tmp}):
            response = json.dumps({"response": {"text": "ALIS_LOOP:CONTINUE"},
                                   "generation": {"done": True}})
            with patch.object(runtime, "run", return_value=SimpleNamespace(
                    returncode=0, stdout=response, stderr="")) as invoked:
                result = runtime.desktop("send", "one distinct Alis turn")
            assert result["response"]["text"] == "ALIS_LOOP:CONTINUE"
            assert invoked.call_count == 1
            journal = runtime.state_root() / "ui-send-journal"
            assert not (journal / "pending.json").exists()
            assert len(list((journal / "observed").glob("*.json"))) == 1

    # WAIT_RESULT must bind a settled public GitHub receipt to exact job
    # identity and SHA-256, not a same-path placeholder or DONE signal.
    good = {"job": "JOB-000127", "status": "passed",
            "input_sha256": "a" * 64, "actions": []}
    with patch.object(runtime, "run", return_value=SimpleNamespace(
            returncode=0, stdout=json.dumps(good), stderr="")):
        assert runtime.result_exists("JOB-000127")
    for bad in ({**good, "job": "JOB-OTHER"},
                {**good, "input_sha256": "invalid"},
                {**good, "status": "preparing"}):
        with patch.object(runtime, "run", return_value=SimpleNamespace(
                returncode=0, stdout=json.dumps(bad), stderr="")):
            try:
                runtime.result_exists("JOB-000127")
            except RuntimeError:
                pass
            else:
                raise AssertionError("foreign/unfinished GitHub result accepted")

    print("PASS: Alis chat-bridge protocol, state, and deterministic transitions")


if __name__ == "__main__":
    main()
