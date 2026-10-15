"""AUTO-F01 authenticated ChatGPT Project transport production gate.

Installed systemd health, a successful UI/CDP smoke test, locally selected
Project labels, static renderer bundle signatures and client-supplied flags
must never enable an unattended ChatGPT task. This gate is intentionally
constant until an audited, supported server-identity and durable receipt
implementation is integrated and independently accepted. No environment
variable, token or settings switch bypasses it.
"""
from __future__ import annotations

from . import taskflow as tf

BLOCKER = "CHATGPT_PROJECT_SERVER_RECEIPT_UNATTESTED"


def readiness() -> dict:
    """Non-sensitive, deterministic status for Settings and local control."""
    return {
        "transport_ready": False,
        "transport_status": "blocked",
        "transport_blocker": BLOCKER,
        "server_project_verified": False,
        "server_conversation_verified": False,
        "server_user_message_verified": False,
        "server_final_receipt_verified": False,
        "unattended_submission_authorized": False,
    }


def require_ready() -> None:
    """Pre-mutation gate for starting/claiming queues and scheduling work."""
    raise tf.TaskError(
        "AUTO-F01 managed ChatGPT transport unavailable: " + BLOCKER
    )
