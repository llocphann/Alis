from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import re

GITHUB_MENTION = "[@GitHub](plugin://github@openai-curated-remote)"
REPOSITORY = "llocphann/Hadalis"
BRANCH = "dev"

CONTINUATION_PROMPT = f"""\
{GITHUB_MENTION}

Continue Hadalis strict-lossless optimization research autonomously.

Repository: {REPOSITORY}
Branch: {BRANCH}

GitHub is the authoritative source of truth.
Do NOT switch to Work mode and do NOT hand off to Work mode. Stay in this ChatGPT conversation and use the GitHub connector plus deterministic local jobs only.

At the start of this turn:
1. Explicitly use the GitHub connector and verify access to {REPOSITORY}.
2. Fetch the CURRENT {BRANCH} HEAD; never rely on a remembered SHA.
3. Read AGENTS.md and the newest tail of docs/CROSS_REPO_OPTIMIZATION_HANDOFF.md.
4. Read the newest local execution result when this turn follows WAIT_RESULT.
5. Audit intervening commits since the newest research checkpoint.
6. Search the handoff before promoting any candidate.
7. Continue the next highest-value STRICT-LOSSLESS optimization research step.

Research only unless the user explicitly authorizes implementation.
Do not modify runtime/product code.
Only docs/CROSS_REPO_OPTIMIZATION_HANDOFF.md may be updated for research findings.

Do not stop after one round. If a round is complete, re-fetch HEAD and continue into the next unexplored area.

Use exactly one loop directive:
- WAIT_RESULT only for one explicit deterministic local job;
- CONTINUE when research can proceed now;
- ROTATE before context rollover after persisting the exact research checkpoint;
- if the connector is unavailable, emit exactly:
  HADALIS_LOOP:CONNECTOR_BLOCKED GITHUB

The DONE directive is reserved only for an explicit user request to stop/disable continuous research. Do not use DONE just because a round finished or no obvious candidate was found.

Do not ask the user to type "continue".
Perform the next research step now.
"""

ROTATION_BOOTSTRAP_PROMPT = f"""\
{GITHUB_MENTION}

Resume continuous Hadalis strict-lossless optimization research.

Repository: {REPOSITORY}
Branch: {BRANCH}

Do NOT switch to Work mode and do NOT hand off to Work mode. Stay in this ChatGPT conversation and use the GitHub connector plus deterministic local jobs only.

First verify GitHub connector access and fetch the CURRENT {BRANCH} HEAD.
Then read:
1. AGENTS.md
2. docs/CROSS_REPO_OPTIMIZATION_HANDOFF.md, especially its newest tail
3. the newest research commit and all intervening commits

Resume exactly from the durable handoff checkpoint.
Research only unless the user explicitly authorized implementation.
Do not modify runtime/product code.
Search the handoff for duplicate/already/superseded/closed findings before promotion.

Continue automatically across research rounds. Use CONTINUE for more research, WAIT_RESULT for one deterministic local job, and ROTATE again before context rollover.
The DONE directive is reserved only for an explicit user request to stop/disable continuous research.

If GitHub connector access is unavailable, emit exactly:
HADALIS_LOOP:CONNECTOR_BLOCKED GITHUB

Do not ask the user to continue.
Perform the next research step now.
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
    r"^HADALIS_LOOP:(WAIT_RESULT|CONTINUE|ROTATE|DONE|CONNECTOR_BLOCKED)"
    r"(?:[ \t]+([A-Za-z0-9._/-]+))?[ \t]*$"
)


def parse_loop_directive(response_text: str) -> LoopDirective:
    """Parse exactly one Hadalis loop marker from a completed assistant response."""
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
        raise ProtocolError("assistant response contains no HADALIS_LOOP marker")
    if len(matches) != 1:
        raise ProtocolError("assistant response must contain exactly one HADALIS_LOOP marker")

    return matches[0]


def prompt_has_required_github_mention(prompt: str) -> bool:
    """The connector mention must be the first non-empty line of every autonomous prompt."""
    first = next((line.strip() for line in prompt.splitlines() if line.strip()), "")
    return first == GITHUB_MENTION
