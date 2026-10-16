#!/usr/bin/env python3
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from typing import Any

from automation.chat_bridge.controller import BridgeAction, BridgeState, transition
from automation.chat_bridge.send_journal import prepare_send, acknowledge_completed, acknowledge_not_sent
from automation.chat_bridge.protocol import (
    CONTINUATION_PROMPT,
    ROTATION_BOOTSTRAP_PROMPT,
    parse_loop_directive,
)

ROOT = Path(__file__).resolve().parents[2]
DESKTOP_CLI = ROOT / "automation" / "chat_bridge" / "desktop_cli.mjs"
INITIAL_PROMPT_FILE = ROOT / "automation" / "chat_bridge" / "INITIAL_PROMPT.md"
RESULTS_DIR = "automation/results"
POLL_SECONDS = float(os.environ.get("ALIS_RESULT_POLL_SECONDS", os.environ.get("HADALIS_RESULT_POLL_SECONDS", "10")))
DESKTOP_TIMEOUT_SECONDS = float(
    os.environ.get("ALIS_DESKTOP_TIMEOUT_SECONDS", os.environ.get("HADALIS_DESKTOP_TIMEOUT_SECONDS", "720"))
)

CONTINUOUS_RESEARCH = os.environ.get("ALIS_CONTINUOUS_RESEARCH", os.environ.get(
    "HADALIS_CONTINUOUS_RESEARCH", "0"
)).strip().lower() in {"1", "true", "yes", "on"}


def state_root() -> Path:
    base = Path(
        os.environ.get(
            "XDG_STATE_HOME",
            str(Path.home() / ".local" / "state"),
        )
    )
    path = base / "hadalis-automation"
    path.mkdir(parents=True, exist_ok=True)
    return path


def state_path() -> Path:
    return state_root() / "chat-bridge.json"


def lock_path() -> Path:
    return state_root() / "chat-bridge.lock"


def clear_state() -> None:
    path = state_path()
    try:
        path.unlink()
    except FileNotFoundError:
        pass


def save_state(state: BridgeState, job_id: str | None = None) -> None:
    payload = {
        "state": state.value,
        "job_id": job_id,
        "updated_at_unix": int(time.time()),
    }
    path = state_path()
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def load_state() -> tuple[BridgeState, str | None] | None:
    path = state_path()
    if not path.exists():
        return None

    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        state = BridgeState(payload["state"])
        job_id = payload.get("job_id")
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"invalid bridge state file: {path}") from exc

    if job_id is not None and not isinstance(job_id, str):
        raise RuntimeError(f"invalid bridge job id in state file: {path}")

    return state, job_id


def run(
    argv: list[str],
    *,
    input_text: str | None = None,
    timeout: float | None = None,
    extra_env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=ROOT,
        input=input_text,
        text=True,
        capture_output=True,
        check=False,
        timeout=timeout,
        env={**os.environ, **(extra_env or {})},
    )


class UiNotSent(RuntimeError):
    """Exact CLI receipt proves a normal failure before its single Send."""
    def __init__(self, code: str, digest: str):
        super().__init__(code)
        self.prompt_sha256 = digest


def desktop(command: str, prompt: str | None = None,
            target_key: str | None = None,
            new_chat_unowned: bool = False,
            owner_chat_reset: bool = False,
            chat_label: str | None = None,
            defer_acknowledgement: bool = False) -> dict[str, Any]:
    # A one-shot intent is fsynced before ANY Desktop UI mutation.
    # A crash, ambiguous click, timeout or incomplete response keeps the
    # pending tombstone: never silently send a duplicate after a restart.
    if new_chat_unowned and command != "rotate-send":
        raise ValueError("Unowned navigation applies only to an initial new chat")
    if owner_chat_reset and (not new_chat_unowned or command != "rotate-send"):
        raise ValueError("ALIS_UI_RESET_REQUIRES_NEW_CHAT")
    extra_env = {}
    surface = state_root() / "ui-window.json"
    if surface.exists() or surface.is_symlink():
        try:
            if surface.is_symlink() or surface.stat().st_size > 2048:
                raise ValueError("Unsafe window pin")
            data = json.loads(surface.read_text())
            target = data.get("target_id") if isinstance(data, dict) else None
            if (not isinstance(data, dict) or data.get("schema") != "alis.ui-window.v1"
                    or not isinstance(target, str) or len(target) != 32
                    or any(c not in "0123456789abcdefABCDEF" for c in target)):
                raise ValueError("Invalid window pin")
        except (OSError, ValueError):
            raise UiNotSent("ALIS_UI_WINDOW_TARGET_INVALID", hashlib.sha256((prompt or "").encode()).hexdigest())
        extra_env["ALIS_CHATGPT_UI_TARGET_ID"] = target
    if chat_label is not None:
        if ("ALIS_CHATGPT_UI_TARGET_ID" not in extra_env
                or not isinstance(chat_label, str) or not chat_label.strip()
                or len(chat_label) > 250 or any(ord(c) < 32 for c in chat_label)):
            raise ValueError("ALIS_UI_RESUME_BINDING_REQUIRED")
        extra_env["ALIS_UI_RESUME_CHAT_LABEL"] = chat_label
    intent = (prepare_send(state_root(), command, prompt)
              if command in {"send", "rotate-send"} else None)
    if target_key is not None and (command not in {"send", "observe-submitted"} or len(target_key) != 64
            or any(c not in "0123456789abcdef" for c in target_key)):
        raise ValueError("ALIS_UI_TARGET_ARGUMENT_INVALID")
    argv = ["node", str(DESKTOP_CLI), command]
    if new_chat_unowned:
        argv.append("--owner-chat-reset" if owner_chat_reset
                    else "--unowned-previous-chat")
    if target_key is not None:
        argv.append(target_key)
    result = run(
        argv,
        input_text=prompt,
        timeout=DESKTOP_TIMEOUT_SECONDS,
        extra_env={**extra_env, **({"ALIS_UI_ATTEMPT_ID": intent[1]} if intent else {})},
    )
    if result.returncode != 0:
        if intent and result.returncode == 1 and len(result.stdout) <= 4096:
            try:
                failure = json.loads(result.stdout)
            except ValueError:
                failure = None
            digest = hashlib.sha256(prompt.encode()).hexdigest()
            if (isinstance(failure, dict)
                    and set(failure) == {"schema", "attempt_id", "prompt_sha256",
                                         "send_attempted", "code"}
                    and failure["schema"] == "alis.ui-dispatch-failure.v1"
                    and failure["attempt_id"] == intent[1]
                    and failure["prompt_sha256"] == digest
                    and failure["send_attempted"] is False
                    and isinstance(failure["code"], str)
                    and failure["code"] in {"ALIS_UI_GITHUB_PICKER_UNAVAILABLE",
                                             "ALIS_UI_GITHUB_MENTION_UNVERIFIED",
                                             "ALIS_UI_PRE_SEND_FAILED"}):
                acknowledge_not_sent(*intent, digest,
                                     evidence="desktop-pre-send-receipt")
                raise UiNotSent(failure["code"], digest)
        # Never surface raw stderr: it can contain private UI context.
        raise RuntimeError("ALIS_UI_SEND_UNCERTAIN_NO_RETRY" if intent else
                           "Alis Desktop observation failed")
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        raise RuntimeError("Alis Desktop response invalid; no send retry") from None
    if intent is not None:
        # Only a complete response permits the NEXT distinct send.
        # This is UI observation, not server-side managed-chat attestation.
        parse_loop_directive(extract_response_text(payload))
        if defer_acknowledgement:
            # The UI manager must commit its bound result before retiring
            # the send journal. A crash between the two remains recoverable.
            payload["ui_send_intent"] = {
                "id": intent[1], "command": command,
                "prompt_sha256": hashlib.sha256(prompt.encode()).hexdigest(),
            }
        else:
            acknowledge_completed(*intent)
    return payload


def extract_response_text(payload: dict[str, Any]) -> str:
    response = payload.get("response")
    if not isinstance(response, dict):
        raise RuntimeError("desktop bridge response object is missing")
    text = response.get("text")
    if not isinstance(text, str) or not text.strip():
        raise RuntimeError("desktop bridge response text is missing")
    return text


def git_fetch_dev() -> None:
    result = run(["git", "fetch", "origin", "dev"], timeout=120)
    if result.returncode != 0:
        raise RuntimeError(f"git fetch origin dev failed: {result.stderr.strip()}")


def result_exists(job_id: str) -> bool:
    # Only a structurally settled receipt for this EXACT job can release a
    # WAIT_RESULT. A pending job or DONE signal is never a worker result.
    if not job_id.startswith("JOB-") or not all(
            c.isalnum() or c in "._-" for c in job_id):
        raise ValueError("invalid Alis job identity")
    path = f"{RESULTS_DIR}/{job_id}.json"
    result = run(["git", "show", f"origin/dev:{path}"], timeout=30)
    if result.returncode != 0:
        return False
    if len(result.stdout) > 65536:
        raise RuntimeError("Alis job result exceeds public metadata bound")
    try:
        payload = json.loads(result.stdout)
    except ValueError:
        raise RuntimeError("Alis job result invalid JSON") from None
    digest = payload.get("input_sha256") if isinstance(payload, dict) else None
    if (not isinstance(payload, dict) or payload.get("job") != job_id
            or not isinstance(digest, str) or len(digest) != 64
            or any(ch not in "0123456789abcdef" for ch in digest)
            or payload.get("status") not in
            {"passed", "failed", "cancelled", "indeterminate"}):
        raise RuntimeError("Alis job result identity/status mismatch")
    return True


def wait_for_result(job_id: str) -> None:
    save_state(BridgeState.WAIT_LOCAL, job_id)
    while True:
        git_fetch_dev()
        if result_exists(job_id):
            return
        time.sleep(POLL_SECONDS)


def resolve_directive(
    response_text: str,
) -> tuple[BridgeState, BridgeAction, str | None]:
    directive = parse_loop_directive(response_text)
    outcome = transition(BridgeState.READY, directive)
    return outcome.state, outcome.action, outcome.job_id


def process_response(
    response_text: str,
    *,
    continuous_research: bool = CONTINUOUS_RESEARCH,
) -> tuple[bool, str | None, str | None]:
    state, action, job_id = resolve_directive(response_text)

    save_state(state, job_id)

    if action is BridgeAction.STOP:
        return True, None, None

    if action is BridgeAction.WAIT_CONNECTOR:
        print(
            "GitHub connector is blocked. Reconnect it, then restart "
            "hadalis-chat-bridge.service.",
            file=sys.stderr,
        )
        raise SystemExit(75)

    if action is BridgeAction.WAIT_RESULT:
        assert job_id is not None
        wait_for_result(job_id)
        return False, "send", CONTINUATION_PROMPT

    if action is BridgeAction.SEND_CONTINUATION:
        return False, "send", CONTINUATION_PROMPT

    if action is BridgeAction.ROTATE_CHAT:
        return False, "rotate-send", ROTATION_BOOTSTRAP_PROMPT

    raise AssertionError(f"unhandled bridge action: {action}")


def attach_until_marker() -> dict[str, Any]:
    while True:
        try:
            return desktop("await-current")
        except RuntimeError as exc:
            message = str(exc)
            retryable = (
                "No completed assistant ALIS_LOOP response found" in message
                or "No ALIS_LOOP marker found near completed assistant response" in message
            )
            if not retryable:
                raise
            time.sleep(2)


def initial_prompt(path: Path = INITIAL_PROMPT_FILE) -> str:
    prompt = path.read_text(encoding="utf-8")
    if not prompt.strip():
        raise RuntimeError(f"initial prompt is empty: {path}")
    return prompt


def bootstrap_payload() -> dict[str, Any] | None:
    previous = load_state()

    if previous is None:
        save_state(BridgeState.READY)
        return desktop("rotate-send", initial_prompt())

    state, job_id = previous

    if state is BridgeState.DONE:
        if CONTINUOUS_RESEARCH:
            save_state(BridgeState.READY)
            return desktop("rotate-send", initial_prompt())
        return None

    if state is BridgeState.CONNECTOR_BLOCKED:
        save_state(BridgeState.READY)
        return desktop("send", CONTINUATION_PROMPT)

    if state is BridgeState.WAIT_LOCAL and job_id is not None:
        wait_for_result(job_id)
        return desktop("send", CONTINUATION_PROMPT)

    return attach_until_marker()


def run_loop(payload: dict[str, Any]) -> int:
    while True:
        response_text = extract_response_text(payload)
        done, command, prompt = process_response(response_text)
        if done:
            save_state(BridgeState.DONE)
            return 0

        assert command is not None
        assert prompt is not None
        payload = desktop(command, prompt)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Deterministic Alis ChatGPT Desktop loop controller"
    )
    parser.add_argument(
        "--initial-prompt-file",
        type=Path,
        help="Explicitly start a new autonomous session with this prompt.",
    )
    parser.add_argument(
        "--bootstrap",
        action="store_true",
        help=(
            "Start the tracked initial prompt only when no session state exists; "
            "otherwise resume deterministically."
        ),
    )
    parser.add_argument(
        "--reset-state",
        action="store_true",
        help="Delete persisted bridge session state and exit.",
    )
    args = parser.parse_args()

    with lock_path().open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise SystemExit(
                "another Alis Chat Bridge instance is already running"
            ) from exc

        if args.reset_state:
            clear_state()
            return 0

        if args.initial_prompt_file is not None:
            save_state(BridgeState.READY)
            payload = desktop(
                "rotate-send",
                initial_prompt(args.initial_prompt_file),
            )
        elif args.bootstrap:
            payload = bootstrap_payload()
            if payload is None:
                return 0
        else:
            payload = attach_until_marker()

        return run_loop(payload)


if __name__ == "__main__":
    raise SystemExit(main())
