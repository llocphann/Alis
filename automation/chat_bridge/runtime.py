#!/usr/bin/env python3
from __future__ import annotations

import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from typing import Any

from automation.chat_bridge.controller import BridgeAction, BridgeState, transition
from automation.chat_bridge.protocol import (
    CONTINUATION_PROMPT,
    ROTATION_BOOTSTRAP_PROMPT,
    parse_loop_directive,
)

ROOT = Path(__file__).resolve().parents[2]
DESKTOP_CLI = ROOT / "automation" / "chat_bridge" / "desktop_cli.mjs"
INITIAL_PROMPT_FILE = ROOT / "automation" / "chat_bridge" / "INITIAL_PROMPT.md"
RESULTS_DIR = "automation/results"
POLL_SECONDS = float(os.environ.get("HADALIS_RESULT_POLL_SECONDS", "10"))
DESKTOP_TIMEOUT_SECONDS = float(
    os.environ.get("HADALIS_DESKTOP_TIMEOUT_SECONDS", "720")
)

CONTINUOUS_RESEARCH = os.environ.get(
    "HADALIS_CONTINUOUS_RESEARCH", "0"
).strip().lower() in {"1", "true", "yes", "on"}


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
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=ROOT,
        input=input_text,
        text=True,
        capture_output=True,
        check=False,
        timeout=timeout,
    )


def desktop(command: str, prompt: str | None = None) -> dict[str, Any]:
    result = run(
        ["node", str(DESKTOP_CLI), command],
        input_text=prompt,
        timeout=DESKTOP_TIMEOUT_SECONDS,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"desktop bridge failed ({result.returncode}): {result.stderr.strip()}"
        )
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            f"desktop bridge returned invalid JSON: {result.stdout[:1000]!r}"
        ) from exc


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
    path = f"{RESULTS_DIR}/{job_id}.json"
    result = run(
        ["git", "cat-file", "-e", f"origin/dev:{path}"],
        timeout=30,
    )
    return result.returncode == 0


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

    if action is BridgeAction.STOP and continuous_research:
        # In continuous research mode, DONE means only that the current turn
        # has no more work. Keep the service alive and ask ChatGPT for the next
        # research step instead of terminating the autonomous loop.
        save_state(BridgeState.READY)
        return False, "send", CONTINUATION_PROMPT

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
                "No completed assistant HADALIS_LOOP response found" in message
                or "No HADALIS_LOOP marker found near completed assistant response" in message
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
        description="Deterministic Hadalis ChatGPT Desktop loop controller"
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
                "another hadalis-chat-bridge instance is already running"
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
