"""Local evidence sanitization; public results contain metadata, never raw data."""
import re

SECRET_KEY = re.compile(r"password|passwd|credential|secret|token|api.?key|authorization|cookie",re.I)


def redact(text: str) -> str:
    text=re.sub(r'''(?i)(authorization\s*[:=]\s*(?:bearer\s+)?|(?:password|passwd|token|secret|api[_-]?key|cookie)\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;]+)''',r"\1[REDACTED]",text)
    text=re.sub(r"\b(?:sk-[A-Za-z0-9_-]{12,}|gh[pousr]_[A-Za-z0-9_]{15,})\b","[REDACTED]",text)
    text=re.sub(r"https?://[^\s/@:]+:[^\s/@]+@","https://[REDACTED]@",text)
    return text


def scrub(value):
    if isinstance(value,dict):return {k:"[REDACTED]" if SECRET_KEY.search(k) else scrub(v) for k,v in value.items()}
    if isinstance(value,list):return [scrub(x) for x in value]
    if isinstance(value,str):return redact(value)
    return value


def public_result(payload: dict) -> dict:
    """Strict allowlist, not heuristic log redaction. This is the Git boundary."""
    keys=("job","profile_id","base_sha","job_commit","input_sha256","status","started_at_unix","finished_at_unix")
    result={k:payload[k] for k in keys if k in payload}
    safe=("index","kind","exit_code","timed_out","cancelled","error_code","evidence_id","source_sha","observed_at_unix","command_sha256",
          "stdout_bytes","stderr_bytes","stdout_sha256","stderr_sha256","stdout_truncated","stderr_truncated","evidence_sha256")
    result["actions"]=[{k:a[k] for k in safe if k in a} for a in payload.get("actions",[])]
    result["evidence_location"]="Private local evidence; raw output is not published"
    if payload.get("recovery_required"):result["recovery_required"]=True
    return result


def chat_result(payload):
    """Allowlisted local-to-managed-chat projection, never raw machine output."""
    result=public_result(payload)
    fields={"check","exit_code","error_codes","unit","active","dirty_count","load","disk_free_bytes","available"}
    for source,target in zip(payload.get("actions",[]),result["actions"]):
        if source.get("safe_observations"):
            target["observations"]=[{k:v for k,v in item.items() if k in fields}
                                    for item in source["safe_observations"][:48]]
    return result
