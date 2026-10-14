from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from .protocol import DirectiveKind, LoopDirective


class BridgeState(str, Enum):
    READY = "ready"
    WAIT_LOCAL = "wait_local"
    CONNECTOR_BLOCKED = "connector_blocked"
    ROTATE_PENDING = "rotate_pending"
    DONE = "done"


class BridgeAction(str, Enum):
    SEND_CONTINUATION = "send_continuation"
    WAIT_RESULT = "wait_result"
    WAIT_CONNECTOR = "wait_connector"
    ROTATE_CHAT = "rotate_chat"
    STOP = "stop"


@dataclass(frozen=True)
class Transition:
    state: BridgeState
    action: BridgeAction
    job_id: str | None = None


def transition(current: BridgeState, directive: LoopDirective) -> Transition:
    """Apply a machine-readable ChatGPT directive without semantic interpretation."""
    if current is BridgeState.DONE:
        raise ValueError("DONE is terminal")

    if directive.kind is DirectiveKind.WAIT_RESULT:
        return Transition(
            state=BridgeState.WAIT_LOCAL,
            action=BridgeAction.WAIT_RESULT,
            job_id=directive.argument,
        )
    if directive.kind is DirectiveKind.CONTINUE:
        return Transition(
            state=BridgeState.READY,
            action=BridgeAction.SEND_CONTINUATION,
        )
    if directive.kind is DirectiveKind.ROTATE:
        return Transition(
            state=BridgeState.ROTATE_PENDING,
            action=BridgeAction.ROTATE_CHAT,
        )
    if directive.kind is DirectiveKind.CONNECTOR_BLOCKED:
        return Transition(
            state=BridgeState.CONNECTOR_BLOCKED,
            action=BridgeAction.WAIT_CONNECTOR,
        )
    if directive.kind is DirectiveKind.DONE:
        return Transition(
            state=BridgeState.DONE,
            action=BridgeAction.STOP,
        )

    raise AssertionError(f"unhandled directive: {directive.kind}")
