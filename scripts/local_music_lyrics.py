#!/usr/bin/env python3
"""Read local sidecar lyrics for the Hadalis MPD Music tab."""
from __future__ import annotations
import hashlib
import json
import os
import re
import sys
from pathlib import Path

STAMP_RE = re.compile(r"\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]")
OFFSET_RE = re.compile(r"^\[offset:([+-]?\d+)\]$", re.IGNORECASE)
META_RE = re.compile(r"^\[(?:ar|al|ti|by|re|ve|length):", re.IGNORECASE)

def candidates(track: Path) -> list[Path]:
    fallback_dir = Path(
        os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local" / "share")
    ) / "alis" / "lyrics"
    digest = hashlib.sha1(str(track).encode("utf-8", "replace")).hexdigest()[:12]
    result = [
        track.with_suffix(".lrc"),
        Path(str(track) + ".lrc"),
        track.with_suffix(".txt"),
        Path(str(track) + ".txt"),
        fallback_dir / f"{track.stem}-{digest}.lrc",
        fallback_dir / f"{track.stem}-{digest}.txt",
    ]
    seen: set[str] = set()
    unique: list[Path] = []
    for path in result:
        key = str(path)
        if key not in seen:
            seen.add(key)
            unique.append(path)
    return unique

def stamp_seconds(minutes: str, seconds: str, fraction: str | None) -> float:
    value = int(minutes) * 60 + int(seconds)
    if fraction:
        value += int(fraction) / (10 ** len(fraction))
    return float(value)

def parse_lrc(text: str) -> tuple[list[dict[str, object]], bool]:
    offset_ms = 0
    timed: list[dict[str, object]] = []
    plain: list[dict[str, object]] = []
    for raw in text.splitlines():
        line = raw.strip("\ufeff\r\n")
        if not line.strip():
            continue
        offset_match = OFFSET_RE.match(line.strip())
        if offset_match:
            offset_ms = int(offset_match.group(1))
            continue
        if META_RE.match(line.strip()):
            continue
        stamps = list(STAMP_RE.finditer(line))
        lyric = STAMP_RE.sub("", line).strip()
        if stamps:
            for match in stamps:
                timed.append({
                    "time": stamp_seconds(match.group(1), match.group(2), match.group(3)),
                    "text": lyric or "♪",
                })
        elif lyric:
            plain.append({"time": -1.0, "text": lyric})
    if timed:
        offset = offset_ms / 1000.0
        for item in timed:
            item["time"] = max(0.0, float(item["time"]) + offset)
        timed.sort(key=lambda item: float(item["time"]))
        return timed, True
    return plain, False

def load(track_text: str) -> dict[str, object]:
    if "://" in track_text:
        return {"status": "not_found", "path": "", "synced": False, "lines": []}
    track = Path(track_text).expanduser()
    for path in candidates(track):
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8-sig", errors="replace")
        except OSError as exc:
            return {"status": "error", "path": str(path), "synced": False,
                    "lines": [], "error": str(exc)}
        lines, synced = parse_lrc(text)
        if lines:
            return {"status": "ok", "path": str(path.resolve()),
                    "synced": synced, "lines": lines}
    return {"status": "not_found", "path": "", "synced": False, "lines": []}

def main() -> int:
    if len(sys.argv) != 2:
        return 2
    print(json.dumps(load(sys.argv[1]), ensure_ascii=False, separators=(",", ":")))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
