#!/usr/bin/env python3
"""Multi-source synchronized lyrics fetcher (Dux 2.0 style) for Alis.

Supports two modes:
1. Online streaming mode (default, used by LyricsService.qml):
   lyrics.py <title> <artist> <album> <duration> [request_id]
   -> Fetches lyrics in memory only (does NOT save .lrc files to disk) and
      emits {"status": "ok", "synced": bool, "lines": [{"t": float, "text": str}, ...]}.

2. Local music download mode (--save-lrc, used by LocalMusic.qml):
   lyrics.py --save-lrc <audio_path> <title> <artist> [duration] [album]
   -> Fetches lyrics for a local track, saves <audio_stem>.lrc next to the
      local audio file (or ~/.local/share/alis/lyrics/ if read-only), and
      emits {"status": "ok", "path": str, "synced": bool, "lines": [{"time": float, "text": str}, ...]}.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

LRCLIB_API = "https://lrclib.net/api"
NETEASE_SEARCH_API = "https://music.163.com/api/search/get"
NETEASE_LYRIC_API = "https://music.163.com/api/song/lyric"
TIMEOUT = 10
REQUEST_DELAY = 0.2
USER_AGENT = "Alis/2.30 (https://github.com/llocphann/Alis)"

STAMP = re.compile(r"\[(\d{1,3}):(\d{2}(?:[.:]\d{1,3})?)\]")
OFFSET_RE = re.compile(r"^\s*\[offset\s*:\s*([+-]?\d+)\s*\]\s*$", re.IGNORECASE)
METADATA_RE = re.compile(r"^\s*\[[a-z]{2,8}\s*:.*\]\s*$", re.IGNORECASE)

NOISE_PATTERNS = [
    r"\(\s*(?:official|lyric|lyrics|music|audio|video|mv|visualizer|live|remaster(?:ed)?|hd|4k|hq)[^)]*\)",
    r"\[\s*(?:official|lyric|lyrics|music|audio|video|mv|visualizer|live|remaster(?:ed)?|hd|4k|hq)[^\]]*\]",
    r"\(\s*(?:feat\.?|ft\.?|prod\.?)[^)]*\)",
    r"\[\s*(?:feat\.?|ft\.?|prod\.?)[^\]]*\]",
    r"\b(?:official\s+(?:music\s+)?video|official\s+audio|lyric\s+video|lyrics\s+video|m/v|mv)\b",
]
ARTIST_NOISE_RE = re.compile(r"\s*-\s*topic$|\bvevo$", re.IGNORECASE)


def emit(payload: dict, request_id: str = "") -> None:
    if request_id:
        payload["requestId"] = request_id
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def get_json(url: str, data: bytes | None = None, extra_headers: dict | None = None):
    headers = {"User-Agent": USER_AGENT}
    if extra_headers:
        headers.update(extra_headers)
    request = urllib.request.Request(url, data=data, headers=headers)
    try:
        response = urllib.request.urlopen(request, timeout=TIMEOUT)
    except urllib.error.HTTPError as exc:
        if exc.code != 429:
            raise
        retry_after = float(exc.headers.get("Retry-After", "1"))
        time.sleep(max(0.0, min(retry_after, 3.0)))
        response = urllib.request.urlopen(request, timeout=TIMEOUT)
    with response:
        return json.loads(response.read().decode("utf-8", "replace"))


def clean_title(title: str) -> str:
    cleaned = title or ""
    for pattern in NOISE_PATTERNS:
        cleaned = re.sub(pattern, " ", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" -–—|")
    return cleaned or (title or "").strip()


def clean_artist(artist: str) -> str:
    cleaned = ARTIST_NOISE_RE.sub("", artist or "").strip()
    cleaned = re.sub(r"\s*(?:feat\.?|ft\.?|&|,|x)\s+.*$", "", cleaned, flags=re.IGNORECASE).strip()
    return cleaned or (artist or "").strip()


def split_artist_title(title: str, artist: str) -> tuple[str, str]:
    c_title = clean_title(title)
    c_artist = clean_artist(artist)
    for sep in (" - ", " – ", " — "):
        if sep in c_title:
            left, right = c_title.split(sep, 1)
            left, right = left.strip(), right.strip()
            if left and right:
                if not c_artist or normalize(left) == normalize(c_artist):
                    return right, (c_artist or left)
                if normalize(right) == normalize(c_artist):
                    return left, c_artist
    return c_title, c_artist


def parse_lrc(lrc: str, key_name: str = "t") -> list[dict]:
    out: list[dict] = []
    offset_seconds = 0.0
    for raw in (lrc or "").splitlines():
        offset_match = OFFSET_RE.match(raw)
        if offset_match:
            try:
                offset_seconds = int(offset_match.group(1)) / 1000.0
            except ValueError:
                offset_seconds = 0.0
            continue
        stamps = list(STAMP.finditer(raw))
        if not stamps:
            continue
        text = raw[stamps[-1].end():].strip()
        for stamp in stamps:
            minutes = int(stamp.group(1))
            seconds = float(stamp.group(2).replace(":", "."))
            timestamp = max(0.0, round(minutes * 60 + seconds - offset_seconds, 3))
            out.append({key_name: timestamp, "text": text})
    out.sort(key=lambda line: line[key_name])
    return out


def parse_plain(plain: str, duration: float | None = None, key_name: str = "t") -> list[dict]:
    raw_lines = [
        line.strip()
        for line in (plain or "").splitlines()
        if line.strip() and not METADATA_RE.match(line)
    ]
    if not raw_lines:
        return []
    step = (float(duration) / max(len(raw_lines), 1)) if (duration and duration > 0) else 0.0
    return [
        {key_name: round(i * step, 3) if step > 0 else None, "text": text}
        for i, text in enumerate(raw_lines)
    ]


def normalize(value: str) -> str:
    return re.sub(r"[^\w\s]", " ", (value or "").lower()).strip()


def overlaps(wanted: str, got: str) -> bool:
    wanted_n, got_n = normalize(wanted), normalize(got)
    if not wanted_n or not got_n:
        return False
    if wanted_n in got_n or got_n in wanted_n:
        return True
    wanted_words = {w for w in wanted_n.split() if len(w) > 2}
    if not wanted_words:
        wanted_words = set(wanted_n.split())
    return bool(wanted_words & set(got_n.split()))


def score_candidate(candidate: dict, title: str, artist: str, duration: float | None) -> float:
    cand_title = str(candidate.get("trackName") or candidate.get("name") or "")
    cand_artist = str(candidate.get("artistName") or "")
    if not overlaps(title, cand_title):
        return -1.0
    if artist and cand_artist and not overlaps(artist, cand_artist):
        c_title, c_artist = split_artist_title(title, artist)
        if not (overlaps(c_title, cand_title) and (not c_artist or overlaps(c_artist, cand_artist))):
            return -1.0

    score = 0.0
    if normalize(title) == normalize(cand_title):
        score += 40.0
    elif overlaps(title, cand_title):
        score += 25.0

    if artist and cand_artist:
        if normalize(artist) == normalize(cand_artist):
            score += 35.0
        elif overlaps(artist, cand_artist):
            score += 20.0

    if duration and duration > 0:
        cand_dur = candidate.get("duration")
        try:
            diff = abs(float(cand_dur) - float(duration))
            if diff <= 3:
                score += 20.0
            elif diff <= 12:
                score += 10.0
            elif diff > 45:
                score -= 15.0
        except (TypeError, ValueError):
            pass

    if candidate.get("syncedLyrics"):
        score += 30.0
    elif candidate.get("plainLyrics"):
        score += 5.0
    else:
        return -1.0

    return score


def fetch_from_lrclib(title: str, artist: str, album: str, duration: float | None) -> tuple[str, bool]:
    """Return (raw_lyrics_text, is_synced) from LRCLIB."""
    q = urllib.parse.quote
    c_title, c_artist = split_artist_title(title, artist)

    attempts: list[str] = []
    if album and duration and artist:
        attempts.append(
            f"{LRCLIB_API}/get?track_name={q(title)}&artist_name={q(artist)}&album_name={q(album)}&duration={int(duration)}"
        )
    if artist:
        attempts.append(f"{LRCLIB_API}/search?track_name={q(title)}&artist_name={q(artist)}")
    if (c_title != title or c_artist != artist) and c_title:
        if c_artist:
            attempts.append(f"{LRCLIB_API}/search?track_name={q(c_title)}&artist_name={q(c_artist)}")
        attempts.append(f"{LRCLIB_API}/search?q={q((c_title + ' ' + c_artist).strip())}")
    attempts.append(f"{LRCLIB_API}/search?q={q((title + ' ' + artist).strip())}")

    # Deduplicate URLs while preserving order
    seen_urls: set[str] = set()
    unique_attempts = [u for u in attempts if not (u in seen_urls or seen_urls.add(u))]

    had_response = False
    last_error: Exception | None = None
    best_plain = ""

    for index, url in enumerate(unique_attempts):
        if index > 0:
            time.sleep(REQUEST_DELAY)
        try:
            payload = get_json(url)
            had_response = True
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                had_response = True
                continue
            last_error = exc
            continue
        except (urllib.error.URLError, ValueError, OSError) as exc:
            last_error = exc
            continue

        candidates = payload if isinstance(payload, list) else [payload]
        scored: list[tuple[float, dict]] = []
        for candidate in candidates:
            if not isinstance(candidate, dict):
                continue
            s = max(
                score_candidate(candidate, title, artist, duration),
                score_candidate(candidate, c_title, c_artist, duration),
            )
            if s > 0:
                scored.append((s, candidate))

        scored.sort(key=lambda item: item[0], reverse=True)
        for _score, candidate in scored:
            synced = (candidate.get("syncedLyrics") or "").strip()
            if synced and parse_lrc(synced):
                return synced, True
            plain = (candidate.get("plainLyrics") or "").strip()
            if plain and not best_plain:
                best_plain = plain

    if best_plain:
        return best_plain, False

    if not had_response and last_error is not None:
        raise last_error
    return "", False


def fetch_from_netease(title: str, artist: str, duration: float | None) -> tuple[str, bool]:
    """Fallback LRC provider using NetEase Cloud Music public search/lyric API."""
    c_title, c_artist = split_artist_title(title, artist)
    query = f"{c_title} {c_artist}".strip()
    if not query:
        return "", False

    form = urllib.parse.urlencode({"s": query, "type": 1, "offset": 0, "limit": 6}).encode("utf-8")
    headers = {
        "Referer": "https://music.163.com",
        "Content-Type": "application/x-www-form-urlencoded",
    }
    try:
        search_data = get_json(NETEASE_SEARCH_API, data=form, extra_headers=headers)
    except Exception:
        return "", False

    songs = ((search_data or {}).get("result") or {}).get("songs") or []
    if not isinstance(songs, list):
        return "", False

    for song in songs:
        if not isinstance(song, dict):
            continue
        song_id = song.get("id")
        song_name = str(song.get("name") or "")
        artists = song.get("artists") or []
        artist_names = " ".join(str(a.get("name") or "") for a in artists if isinstance(a, dict))
        if not song_id:
            continue
        if not (overlaps(title, song_name) or overlaps(c_title, song_name)):
            continue
        if c_artist and artist_names and not (overlaps(artist, artist_names) or overlaps(c_artist, artist_names)):
            continue
        if duration and duration > 0 and song.get("duration"):
            try:
                song_dur = float(song["duration"]) / 1000.0
                if abs(song_dur - float(duration)) > 35:
                    continue
            except (TypeError, ValueError):
                pass

        try:
            lyric_url = f"{NETEASE_LYRIC_API}?id={int(song_id)}&lv=1&kv=1&tv=-1"
            lyric_data = get_json(lyric_url, extra_headers={"Referer": "https://music.163.com"})
        except Exception:
            continue

        lrc_text = (((lyric_data or {}).get("lrc") or {}).get("lyric") or "").strip()
        if lrc_text and parse_lrc(lrc_text):
            return lrc_text, True

    return "", False


def find_lyrics_raw(title: str, artist: str, album: str, duration: float | None) -> tuple[str, bool]:
    last_error: Exception | None = None
    try:
        raw_text, is_synced = fetch_from_lrclib(title, artist, album, duration)
        if raw_text and is_synced:
            return raw_text, True
    except Exception as exc:
        last_error = exc
        raw_text, is_synced = "", False

    synced_netease, netease_is_synced = fetch_from_netease(title, artist, duration)
    if synced_netease and netease_is_synced:
        return synced_netease, True

    if raw_text:
        return raw_text, is_synced

    if last_error is not None:
        raise last_error
    return "", False


def find_lyrics(title: str, artist: str, album: str, duration: float | None) -> list[dict]:
    raw_text, is_synced = find_lyrics_raw(title, artist, album, duration)
    if not raw_text:
        return []
    if is_synced:
        return parse_lrc(raw_text, key_name="t")
    return parse_plain(raw_text, duration=duration, key_name="t")


def save_lrc_for_local_track(audio_path: str, raw_text: str, is_synced: bool) -> str:
    track = Path(os.path.expanduser(audio_path))
    suffix = ".lrc" if is_synced else ".txt"
    target = track.with_suffix(suffix)
    try:
        target.write_text(raw_text.rstrip() + "\n", encoding="utf-8")
        return str(target)
    except OSError:
        fallback_dir = Path(
            os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local" / "share")
        ) / "alis" / "lyrics"
        fallback_dir.mkdir(parents=True, exist_ok=True)
        digest = hashlib.sha1(str(track).encode("utf-8", "replace")).hexdigest()[:12]
        fallback = fallback_dir / f"{track.stem}-{digest}{suffix}"
        fallback.write_text(raw_text.rstrip() + "\n", encoding="utf-8")
        return str(fallback)


def run_save_lrc_mode(args: list[str]) -> None:
    audio_path = args[0].strip() if len(args) > 0 else ""
    title = args[1].strip() if len(args) > 1 else ""
    artist = args[2].strip() if len(args) > 2 else ""
    duration_str = args[3].strip() if len(args) > 3 else ""
    album = args[4].strip() if len(args) > 4 else ""

    if not audio_path or not title:
        emit({"status": "not_found", "path": "", "synced": False, "lines": []})
        return

    try:
        duration = float(duration_str) if duration_str else None
    except ValueError:
        duration = None

    try:
        raw_text, is_synced = find_lyrics_raw(title, artist, album, duration)
    except Exception as exc:
        emit({"status": "error", "message": str(exc), "path": "", "synced": False, "lines": []})
        return

    if not raw_text:
        emit({"status": "not_found", "path": "", "synced": False, "lines": []})
        return

    if is_synced:
        lines = parse_lrc(raw_text, key_name="time")
    else:
        lines = parse_plain(raw_text, duration=None, key_name="time")

    if not lines:
        emit({"status": "not_found", "path": "", "synced": False, "lines": []})
        return

    saved_path = save_lrc_for_local_track(audio_path, raw_text, is_synced)
    emit({
        "status": "ok",
        "path": saved_path,
        "synced": is_synced,
        "lines": lines,
    })


def main() -> None:
    args = sys.argv[1:]
    if args and args[0] == "--save-lrc":
        run_save_lrc_mode(args[1:])
        return

    title = args[0].strip() if len(args) > 0 else ""
    artist = args[1].strip() if len(args) > 1 else ""
    album = args[2].strip() if len(args) > 2 else ""
    request_id = args[4].strip() if len(args) > 4 else ""

    if not title:
        emit({"status": "no_info"}, request_id)
        return

    try:
        duration = float(args[3]) if len(args) > 3 and args[3] else None
    except ValueError:
        duration = None

    try:
        raw_text, is_synced = find_lyrics_raw(title, artist, album, duration)
    except Exception as exc:
        emit({"status": "error", "message": str(exc)}, request_id)
        return

    if not raw_text:
        emit({"status": "not_found"}, request_id)
        return

    lines = (
        parse_lrc(raw_text, key_name="t")
        if is_synced
        else parse_plain(raw_text, duration=duration or 180.0, key_name="t")
    )
    emit(
        {"status": "ok", "synced": is_synced, "lines": lines}
        if lines
        else {"status": "not_found"},
        request_id,
    )


if __name__ == "__main__":
    main()
