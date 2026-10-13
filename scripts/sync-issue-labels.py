#!/usr/bin/env python3
"""Sync only Alis custom Issue label colors; keep GitHub default labels intact."""
import json
import os
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
            return json.load(response)
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
