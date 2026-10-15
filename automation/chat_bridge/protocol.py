from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import re

GITHUB_MENTION = "[@GitHub](plugin://github@openai-curated-remote)"
# ChatGPT consumer GitHub app reference requested by the owner. Keep the
# legacy rich-mention token separate: a literal app link does not prove that
# ChatGPT Desktop resolved/connected the GitHub app.
GITHUB_APP_MENTION = "[$github](app://connector_76869538009648d5b282a4bb21c3d157)"


def cloud_github_prompt(body: str) -> str:
    """Exactly one owner-selected app link at the top of a Cloudbot prompt.

    Existing task bundles may already contain this prefix. Normalize them at
    runtime without touching persisted task files or changing authority.
    """
    if not isinstance(body,str) or not body.strip():
        raise ValueError("Cloudbot prompt body missing")
    objective=body.lstrip()
    for mention in (GITHUB_APP_MENTION,GITHUB_MENTION):
        if objective.startswith(mention):
            objective=objective[len(mention):].lstrip("\r\n")
            break
    return GITHUB_APP_MENTION + "\n\n" + objective


# Alis is the only current product name. The older marker is read-only
# compatibility for already-saved conversations, not the emitted protocol.
LOOP_PREFIX = "ALIS_LOOP"
LEGACY_LOOP_PREFIX = "HADALIS_LOOP"
REPOSITORY = "llocphann/Alis"
BRANCH = "dev"

CONTINUATION_PROMPT = f"""{GITHUB_APP_MENTION}

Continue the active Alis Automation task in this ChatGPT conversation.
Repository: {REPOSITORY}
Branch: {BRANCH}

GitHub is authoritative for job IDs, handoffs and durable worker results.
Fetch the CURRENT dev HEAD; inspect the task Issue and saved checkpoint.
After WAIT_RESULT, read the EXACT JOB-ID receipt from automation/results,
check its source SHA and outcome before deciding what to do next.
Never infer execution from a pending job or DONE handoff. Do not reuse a job
ID, replay uncertain effects or automatically grant local execution approval.
Keep credentials and raw machine evidence private.

ChatGPT is the reasoning agent. Alis Chat Bridge handles deterministic
Desktop continuation and Localbot handles SHA-pinned execution. Preserve the
owner's current objective and restrictions. Do not switch to Work mode.

End with exactly one canonical directive:
- ALIS_LOOP:WAIT_RESULT JOB-... only for an approved, pinned job;
- ALIS_LOOP:CONTINUE when the next research/development step can proceed;
- ALIS_LOOP:ROTATE only after saving a checkpoint;
- ALIS_LOOP:DONE when the assigned task is finished or explicitly stopped;
- ALIS_LOOP:CONNECTOR_BLOCKED GITHUB if GitHub is unavailable.

Do not ask the owner to type "continue" for an authorized workflow.
"""

ROTATION_BOOTSTRAP_PROMPT = f"""{GITHUB_APP_MENTION}

Resume the existing Alis Automation task from its durable checkpoint.
Repository: {REPOSITORY}
Branch: {BRANCH}

Verify GitHub access, fetch CURRENT dev HEAD, inspect the exact task Issue,
prior job receipts, checkpoint and concurrent commits. Continue ONLY the
previously authorized objective. Never replay uncertain commands, assume
pending work has approval, or expose local private evidence.
Stay in this ChatGPT conversation. Do not switch to Work mode.
End with one ALIS_LOOP directive (WAIT_RESULT JOB-..., CONTINUE, ROTATE,
DONE or CONNECTOR_BLOCKED GITHUB).
"""


class DirectiveKind(str, Enum):
    WAIT_RESULT = "WAIT_RESULT"
    CONTINUE = "CONTINUE"
    ROTATE = "ROTATE"
    DONE = "DONE"
    CONNECTOR_BLOCKED = "CONNECTOR_BLOCKED"


@dataclass(frozen=True)
class LoopDirective:
    kind: DirectiveKind
    argument: str | None = None


class ProtocolError(ValueError):
    pass


_JOB_ID_RE = re.compile(r"^JOB-[A-Za-z0-9._-]+$")


_MARKER_RE = re.compile(
    r"^(?:ALIS|HADALIS)_LOOP:(WAIT_RESULT|CONTINUE|ROTATE|DONE|CONNECTOR_BLOCKED)"
    r"(?:[ \t]+([A-Za-z0-9._/-]+))?[ \t]*$"
)


def parse_loop_directive(response_text: str) -> LoopDirective:
    """Parse exactly one Alis or legacy loop marker from a completed assistant response."""
    matches: list[LoopDirective] = []

    for raw_line in response_text.splitlines():
        line = raw_line.strip()
        match = _MARKER_RE.fullmatch(line)
        if match is None:
            continue

        kind = DirectiveKind(match.group(1))
        argument = match.group(2)

        if kind is DirectiveKind.WAIT_RESULT:
            if not argument or _JOB_ID_RE.fullmatch(argument) is None:
                raise ProtocolError("WAIT_RESULT requires a safe JOB-* id")
        elif kind is DirectiveKind.CONNECTOR_BLOCKED:
            if argument != "GITHUB":
                raise ProtocolError("CONNECTOR_BLOCKED requires GITHUB")
        elif argument is not None:
            raise ProtocolError(f"{kind.value} does not accept an argument")

        matches.append(LoopDirective(kind=kind, argument=argument))

    if not matches:
        raise ProtocolError("assistant response contains no ALIS_LOOP marker")
    if len(matches) != 1:
        raise ProtocolError("assistant response must contain exactly one ALIS_LOOP marker")

    return matches[0]


def prompt_has_required_github_mention(prompt: str) -> bool:
    """The connector mention must be the first non-empty line of every autonomous prompt."""
    first = next((line.strip() for line in prompt.splitlines() if line.strip()), "")
    return first in {GITHUB_MENTION, GITHUB_APP_MENTION}
