#!/usr/bin/env python3
"""Sync only Alis custom Issue label colors; keep GitHub default labels intact."""
import json
import os
import re
import sys
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
palette = json.loads((ROOT / ".github/issue-label-palette.json").read_text(encoding="utf-8"))
for name, item in palette.items():
    assert (name.startswith(("area:", "status:", "complexity:"))
            and len(item["color"]) == 6 and all(c in "0123456789ABCDEFabcdef" for c in item["color"]))
assert "complexity:high" in palette
assert {"status:blocked", "status:deferred", "status:awaiting-owner"} <= set(palette)

token = os.environ.get("GITHUB_TOKEN")
repo = os.environ.get("GITHUB_REPOSITORY")
if not token or not repo:
    raise SystemExit("GITHUB_TOKEN and GITHUB_REPOSITORY are required")
base = f"https://api.github.com/repos/{repo}"
headers = {
    "Accept": "application/vnd.github+json",
    "Authorization": f"Bearer {token}",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "alis-issue-label-palette",
}
def api(method, path, payload=None):
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    request = Request(base + path, data=data, headers=headers, method=method)
    try:
        with urlopen(request, timeout=30) as response:
            return None if response.status == 204 else json.load(response)
    except HTTPError as exc:
        # Never print tokens, body content, or other private data.
        raise RuntimeError(f"{method} {path}: GitHub HTTP {exc.code}") from exc

existing = {}
page = 1
while True:
    entries = api("GET", f"/labels?per_page=100&page={page}")
    for label in entries:
        existing[label["name"]] = label
    if len(entries) < 100:
        break
    page += 1

created = updated = unchanged = 0
for name, item in palette.items():
    color, description = item["color"], item["description"]
    current = existing.get(name)
    if current is None:
        api("POST", "/labels", {"name": name, "color": color, "description": description})
        created += 1
    elif current["color"].lower() != color.lower() or (current.get("description") or "") != description:
        api("PATCH", "/labels/" + quote(name, safe=""), {"color": color, "description": description})
        updated += 1
    else:
        unchanged += 1
print(f"ALIS_ISSUE_LABEL_COLORS_PASS created={created} updated={updated} unchanged={unchanged} total={len(palette)}")

# Explicit opt-in migration: preserve area/status/other user tags, replace only
# redundant legacy type:* labels with GitHub built-ins, and tag complex work.
if "--migrate" in sys.argv:
    complex_issue_numbers = {
        27, 30, 31, 32, 36, 40, 41, 42, 43, 45, 49, 57, 58, 59,
        63, 64, 65, 66, 67, 72, 73, 74, 80, 81, 83, 88, 89, 90,
        91, 92, 93, 94, 95, 99, 100,
    }
    def desired_labels(issue):
        labels = [item["name"] for item in issue.get("labels", [])]
        prefix = re.match(r"^\[[A-Z]+-([FRI])\d+\]", issue["title"])
        if issue["number"] == 97:
            kind = "documentation"
        elif prefix:
            kind = "bug" if prefix.group(1) == "I" else "enhancement"
        elif "type:bug" in labels:
            kind = "bug"
        elif "type:feature" in labels or "type:rework" in labels:
            kind = "enhancement"
        else:
            return None
        result = [x for x in labels if not x.startswith("type:")]
        if kind not in result:
            result.append(kind)
        if issue["number"] in complex_issue_numbers and "complexity:high" not in result:
            result.append("complexity:high")
        return result

    changed = skipped = 0
    all_issues = []
    page = 1
    while True:
        page_items = api("GET", f"/issues?state=all&per_page=100&page={page}")
        all_issues.extend(page_items)
        if len(page_items) < 100:
            break
        page += 1
    for issue in all_issues:
        if "pull_request" in issue:
            continue
        labels = desired_labels(issue)
        if labels is None:
            skipped += 1
        elif set(labels) != {item["name"] for item in issue["labels"]}:
            api("PATCH", f"/issues/{issue['number']}", {"labels": labels})
            changed += 1

    # Old gray type:* labels are redundant. Remove the repository label entry
    # only when no Issue/PR references it in the freshly queried API snapshot.
    removed = []
    for name in ("type:bug", "type:feature", "type:rework"):
        still_used = any(
            name in {tag["name"] for tag in issue.get("labels", [])}
            for issue in all_issues if "pull_request" in issue
        )
        if name in existing and not still_used:
            api("DELETE", "/labels/" + quote(name, safe=""))
            removed.append(name)
    print(f"ALIS_ISSUE_LABEL_MIGRATION_PASS changed={changed} skipped={skipped} "
          f"scanned={len(all_issues)} obsolete_removed={','.join(removed)}")
