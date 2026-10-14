from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import uuid

from automation.chat_bridge.protocol import (
    CONTINUATION_PROMPT, GITHUB_MENTION, ROTATION_BOOTSTRAP_PROMPT,
)

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ID = "strict-lossless-research"
MODES = {"manual", "continuous", "interval", "duration", "iterations"}
LIMIT_ACTIONS = {"stop", "pause", "rotate"}
MAX_PROFILES = 64
GENERIC_PROMPT = "Carry out this profile's objective step by step. Set the objective here before starting.\n"
CUSTOM_CONTINUATION_PROMPT = "Continue this profile's objective from its latest checkpoint and local evidence. Finish with one HADALIS_LOOP directive.\n"
CUSTOM_ROTATION_PROMPT = "Resume this profile's objective from its durable checkpoint in this fresh managed conversation.\n"

# The settings page advertises these as pending until a semantic Desktop action
# exists. Storing preferences does not imply that a chat is archived or deleted.
MAINTENANCE_DEFAULTS = {
    "archive_completed": True,
    "delete_completed": False,
    "archive_old": False,
    "cleanup_abandoned": False,
    "recover_stuck_generation": False,
    "recover_stale_composer": False,
}

PROFILE_DEFAULTS = {
    "description": "",
    "project_name": "Hadalis Cloud",
    "enabled": False,
    "requires_github": True,
    "stop_on_done": False,  # Preserve v1 continuous-loop semantics on import.
    "mode": "manual",
    "interval_seconds": 3600,
    "duration_seconds": 3600,
    "duration_action": "stop",
    "iteration_limit": 0,
    "prompt_limit": 0,
    "rotate_after_iterations": 0,
    "rotate_after_seconds": 0,
    "max_failures": 3,
    "max_poll_errors": 3,
    "retry_delay_seconds": 30,
    "archive_completed": True,
    "delete_completed": False,
    "continuation_prompt": CONTINUATION_PROMPT,
    "rotation_prompt": ROTATION_BOOTSTRAP_PROMPT,
}

INTEGER_LIMITS = {
    "interval_seconds": (60, 86400 * 30),
    "duration_seconds": (60, 86400 * 30),
    "iteration_limit": (0, 1000000),
    "prompt_limit": (0, 1000000),
    "rotate_after_iterations": (0, 1000000),
    "rotate_after_seconds": (0, 86400 * 30),
    "max_failures": (0, 100),
    "max_poll_errors": (0, 100),
    "retry_delay_seconds": (1, 3600),
}


def default_prompt() -> str:
    return (ROOT / "automation/chat_bridge/INITIAL_PROMPT.md").read_text(encoding="utf-8")


def default_profile() -> dict:
    profile = deepcopy(PROFILE_DEFAULTS)
    profile.update({
        "id": DEFAULT_ID,
        "name": "Strict-lossless optimization research",
        "description": "Continuous Hadalis research on current dev",
        "enabled": True,
        "mode": "continuous",
        "prompt": default_prompt(),
    })
    return profile


def default_config() -> dict:
    return {"version": 1, "maintenance": deepcopy(MAINTENANCE_DEFAULTS),
            "profiles": [default_profile()]}


def _string(value: object, field: str, *, allow_empty: bool = False) -> str:
    if not isinstance(value, str) or (not allow_empty and not value.strip()) or len(value) > 100000:
        raise ValueError(f"invalid {field}")
    return value


def validate_profile(raw: object, *, defaults: dict | None = None) -> dict:
    if not isinstance(raw, dict):
        raise ValueError("profile must be an object")
    base = deepcopy(PROFILE_DEFAULTS if defaults is None else defaults)
    profile = {key: raw.get(key, base.get(key)) for key in (*PROFILE_DEFAULTS, "id", "name", "prompt")}
    profile["id"] = _string(profile["id"], "id")
    if len(profile["id"]) > 80 or any(ch not in "abcdefghijklmnopqrstuvwxyz0123456789-" for ch in profile["id"]):
        raise ValueError("invalid id")
    profile["name"] = _string(profile["name"], "name")
    if len(profile["name"]) > 100:
        raise ValueError("name too long")
    profile["description"] = _string(profile["description"], "description", allow_empty=True)
    if len(profile["description"]) > 1000:
        raise ValueError("description too long")
    profile["project_name"] = _string(profile["project_name"], "project_name")
    if len(profile["project_name"]) > 80 or any(ch not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._-" for ch in profile["project_name"]):
        raise ValueError("project name must use letters, numbers, spaces, dots, hyphens or underscores")
    for key in ("enabled", "requires_github", "stop_on_done", "archive_completed", "delete_completed"):
        if type(profile[key]) is not bool:
            raise ValueError(f"invalid {key}")
    for key in ("prompt", "continuation_prompt", "rotation_prompt"):
        profile[key] = _string(profile[key], key)
    if profile["mode"] not in MODES:
        raise ValueError("invalid mode")
    if profile["duration_action"] not in LIMIT_ACTIONS:
        raise ValueError("invalid duration_action")
    for key, (minimum, maximum) in INTEGER_LIMITS.items():
        value = profile[key]
        if type(value) is not int or not minimum <= value <= maximum:
            raise ValueError(f"invalid {key}")
    if profile["mode"] == "iterations" and profile["iteration_limit"] < 1:
        raise ValueError("iterations mode needs an iteration limit")
    if profile["delete_completed"] and profile["archive_completed"]:
        raise ValueError("archive and delete are mutually exclusive")
    return profile


def normalize_config(raw: object) -> tuple[dict, list[str]]:
    """Load old/missing fields conservatively; quarantine malformed profiles."""
    if not isinstance(raw, dict):
        raise ValueError("configuration must be an object")
    if raw.get("version", 1) != 1:
        raise ValueError("unsupported automation configuration version")
    maintenance = deepcopy(MAINTENANCE_DEFAULTS)
    incoming = raw.get("maintenance", {})
    if not isinstance(incoming, dict):
        incoming = {}
    for key in maintenance:
        if type(incoming.get(key)) is bool:
            maintenance[key] = incoming[key]
    if maintenance["archive_completed"] and maintenance["delete_completed"]:
        maintenance["delete_completed"] = False
    profiles = []
    issues = []
    seen = set()
    source = raw.get("profiles", [default_profile()])
    if not isinstance(source, list):
        source = [default_profile()]
        issues.append("invalid profile list; using default")
    for index, item in enumerate(source[:MAX_PROFILES]):
        try:
            defaults = default_profile() if isinstance(item, dict) and item.get("id") == DEFAULT_ID else None
            profile = validate_profile(item, defaults=defaults)
            if profile["id"] in seen:
                raise ValueError("duplicate id")
            seen.add(profile["id"])
            profiles.append(profile)
        except ValueError as exc:
            issues.append(f"profile {index + 1}: {exc}")
    if len(source) > MAX_PROFILES:
        issues.append("profile count exceeds limit")
    if not profiles and source:
        profiles = [default_profile()]
        profiles[0]["enabled"] = False
        issues.append("no valid profiles; default is disabled")
    return {"version": 1, "maintenance": maintenance, "profiles": profiles}, issues


def update_profile(profile: dict, changes: object, *, confirm_delete: bool = False) -> dict:
    if not isinstance(changes, dict) or not changes:
        raise ValueError("changes must be a nonempty object")
    allowed = set(PROFILE_DEFAULTS) | {"name", "prompt"}
    if set(changes) - allowed:
        raise ValueError("unknown or immutable profile field")
    if changes.get("delete_completed") is True and not confirm_delete:
        raise ValueError("delete requires explicit confirmation")
    merged = {**profile, **changes}
    return validate_profile(merged, defaults=default_profile() if profile["id"] == DEFAULT_ID else None)


def new_profile(name: str, *, copy: dict | None = None) -> dict:
    source = deepcopy(copy if copy is not None else default_profile())
    source.update({"id": "profile-" + uuid.uuid4().hex[:16], "name": name,
                   "enabled": False, "mode": "manual", "delete_completed": False})
    if copy is None:
        source["prompt"] = GENERIC_PROMPT
        source["stop_on_done"] = True
        source["continuation_prompt"] = CUSTOM_CONTINUATION_PROMPT
        source["rotation_prompt"] = CUSTOM_ROTATION_PROMPT
    return validate_profile(source)


SAFETY_PREAMBLE = """ChatGPT is the only reasoning agent. Local services are deterministic transport and execution only.
Stay in this ChatGPT conversation. Do not switch to Work mode or hand off to Work mode.
Use only HADALIS_LOOP:CONTINUE, WAIT_RESULT JOB-..., ROTATE, DONE, or CONNECTOR_BLOCKED GITHUB as the final directive.
Work through the objective: observe, gather evidence, diagnose, change, test, inspect, recover and iterate as needed.
For debugging, collect bounded diagnostics before drawing conclusions. Cite evidence IDs, source SHA, timestamps and exit status for each conclusion. Do not infer a failure cause from symptoms alone.
Emit each machine-debug conclusion as HADALIS_DIAGNOSIS:{"conclusion":"...","evidence_ids":["JOB-...:0"]}. Cite observed worker evidence; unsupported diagnoses cannot trigger further actions. Collect new diagnostics when evidence is missing.
After a confirmed generation failure, a distinct recovery turn may be scheduled. Inspect existing Git changes and job receipts first; never re-execute an indeterminate action or reuse an existing job ID for new execution.
Dispatch explicit SHA-pinned jobs using automation/queue/pending. Workers can collect diagnostics while Quickshell is down. Raw logs/config/screenshots remain private locally; only bounded sanitized observations and provenance may be shared with this managed chat, never raw machine data in Git results.
Jobs support exec argv, diagnostics checks (services/processes/journal/git/resources/runtime/hardware/config/crashes/screenshot), allowlisted privileged service actions and validated shell_deploy. Include this profile's ID in profile_id. Use resource leases only for shared mutable resources. The worker uses an isolated pinned clone: normal code commits should be made through GitHub after fetching current dev, with local jobs for tests/evidence. Deploy risky shell changes only through shell_deploy, which requires canonical validation and rollback. Read automation/worker/README.md for schemas before dispatch.
Use WAIT_RESULT to await a job, then inspect its result and evidence before deciding the next step. Privileged actions use the typed allowlist broker, a clear reason and system authentication; never put passwords or credentials in a prompt, config, job, argv or log.
Before ROTATE, optionally emit one HADALIS_CHECKPOINT:{"phase":"...","summary":"...","next":"...","evidence_ids":[]} line. Preserve checkpoints for long tasks, testing and recovery.
"""
REPOSITORY_PREAMBLE = """GitHub is the authoritative source of truth for llocphann/Hadalis dev.
Explicitly use the GitHub connector, verify repository access and fetch current dev before each repository audit or write. Read AGENTS.md. If unavailable, emit HADALIS_LOOP:CONNECTOR_BLOCKED GITHUB and stop.
"""


def effective_prompt(profile: dict, kind: str) -> str:
    """Keep the legacy prompt exact; wrap edits with mandatory transport rules."""
    field = {"initial": "prompt", "continuation": "continuation_prompt",
             "rotation": "rotation_prompt"}[kind]
    prompt = profile[field]
    legacy = {"initial": default_prompt(), "continuation": CONTINUATION_PROMPT,
              "rotation": ROTATION_BOOTSTRAP_PROMPT}[kind]
    if profile["id"] == DEFAULT_ID and prompt == legacy:
        return prompt
    body = prompt
    if body.lstrip().startswith(GITHUB_MENTION):
        body = body.lstrip()[len(GITHUB_MENTION):].lstrip("\r\n")
    if kind == "rotation":
        objective = profile["prompt"].lstrip()
        if objective.startswith(GITHUB_MENTION):
            objective = objective[len(GITHUB_MENTION):].lstrip("\r\n")
        body += "\n\nProfile objective:\n" + objective
    prefix = GITHUB_MENTION + "\n\n" + REPOSITORY_PREAMBLE if profile["requires_github"] else ""
    return prefix + SAFETY_PREAMBLE + "\n" + body


def limit_decision(profile: dict, runtime: dict, now: int) -> str | None:
    """Evaluate only counters observed by this controller at turn boundaries."""
    started = runtime.get("started_at_unix") or now
    elapsed = max(0, now - started)
    run_iterations = runtime.get("iterations", 0) - runtime.get("run_start_iterations", 0)
    run_prompts = runtime.get("prompts_sent", 0) - runtime.get("run_start_prompts", 0)
    if profile["iteration_limit"] and run_iterations >= profile["iteration_limit"]:
        return "stop"
    if profile["prompt_limit"] and run_prompts >= profile["prompt_limit"]:
        return "stop"
    if profile["mode"] == "duration" and elapsed >= profile["duration_seconds"]:
        return profile["duration_action"]
    if profile["rotate_after_iterations"] and runtime.get("chat_iterations", 0) >= profile["rotate_after_iterations"]:
        return "rotate"
    chat_started = runtime.get("chat_started_at_unix") or now
    if profile["rotate_after_seconds"] and now - chat_started >= profile["rotate_after_seconds"]:
        return "rotate"
    return None


def choose_profile(config: dict, state: dict, now: int) -> str | None:
    """One owner, deterministic due time then stable profile order."""
    owner = state.get("owner_id")
    if owner:
        return owner
    candidates = []
    for index, profile in enumerate(config["profiles"]):
        if not profile["enabled"]:
            continue
        status = state.get("profiles", {}).get(profile["id"], {})
        if status.get("desired") != "run":
            continue
        due = status.get("next_run_at_unix") or 0
        if due <= now:
            candidates.append((due, index, profile["id"]))
    return min(candidates)[2] if candidates else None
