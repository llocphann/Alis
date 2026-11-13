#!/usr/bin/env python3
"""Multi-source word-level & line-level synchronized lyrics fetcher (Dux 2.0 style) for Alis.

Supports two modes:
1. Online streaming mode (default, used by LyricsService.qml):
   lyrics.py <title> <artist> <album> <duration> [request_id]
   -> Fetches lyrics in memory only (does NOT save .lrc files to disk) and
      emits {"status": "ok", "synced": bool, "wordSynced": bool, "lines": [{"t": float, "endTime": float, "text": str, "words": [...]}, ...]}.

2. Local music download mode (--save-lrc, used by LocalMusic.qml):
   lyrics.py --save-lrc <audio_path> <title> <artist> [duration] [album]
   -> Fetches lyrics for a local track, saves <audio_stem>.lrc next to the
      local audio file (or ~/.local/share/alis/lyrics/ if read-only), and
      emits {"status": "ok", "path": str, "synced": bool, "wordSynced": bool, "lines": [{"time": float, "endTime": float, "text": str, "words": [...]}, ...]}.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import zlib

LRCLIB_API = "https://lrclib.net/api"
NETEASE_SEARCH_API = "https://music.163.com/api/search/get"
NETEASE_LYRIC_API = "https://music.163.com/api/song/lyric"
KUGOU_SEARCH_API = "http://lyrics.kugou.com/search"
KUGOU_MOBILE_SEARCH_API = "http://mobilecdn.kugou.com/api/v3/search/song"
KUGOU_DOWNLOAD_API = "http://lyrics.kugou.com/download"
KUGOU_KRC_KEY = (64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105)
TIMEOUT = 10
REQUEST_DELAY = 0.2
USER_AGENT = "Alis/2.30 (https://github.com/llocphann/Alis)"

STAMP = re.compile(r"\[(\d{1,3}):(\d{2}(?:[.:]\d{1,3})?)\]")
INLINE_WORD_STAMP = re.compile(r"<(\d{1,3}):(\d{2}(?:[.:]\d{1,3})?)>")
YRC_LINE_RE = re.compile(r"^\[(\d+),(\d+)\](.+)$")
YRC_WORD_RE = re.compile(r"\((\d+),(\d+),\d+\)([^\(]*)")
KLYRIC_LINE_RE = re.compile(r"^\[(\d+),(\d+)\](.+)$")
KLYRIC_WORD_RE = re.compile(r"<(\d+),(\d+),\d+>([^<]*)")
OFFSET_RE = re.compile(r"^\s*\[offset\s*:\s*([+-]?\d+)\s*\]\s*$", re.IGNORECASE)
METADATA_RE = re.compile(r"^\s*\[[a-z]{2,8}\s*:.*\]\s*$", re.IGNORECASE)
CREDIT_SECTION_HEADER_RE = re.compile(
    r"^\s*\[(?:Verse|Chorus|Hook|Bridge|Intro|Outro|Pre-Chorus|Interlude|Instrumental|Solo|Guitar\s*Solo)[^\]]*\]\s*$",
    re.IGNORECASE,
)
LATIN_CREDIT_PREFIXES = {
    "lyricsby", "lyricist", "writtenby", "composedby", "composer", "musicby",
    "producedby", "producer", "arrangedby", "arranger", "mixedby", "mixing",
    "masteredby", "mastering", "recordedby", "vocalsby", "publishedby",
    "copyright", "artist", "artists", "album", "title", "songtitle", "songstitle",
    "singer", "vocal", "vocals", "guitar", "bass", "drums", "piano", "keyboard",
    "strings", "editor", "subtitles", "transcribedby", "syncedby", "lrcby",
    "sángtác", "lời", "nhạc", "hoàâm", "hòaâm", "phốikhí",
    "biêntập", "thựchiện", "casĩ", "trìnhbày", "biểudiễn", "thuâm",
}


def _is_cjk_char(ch: str) -> bool:
    code = ord(ch)
    return (
        0x4E00 <= code <= 0x9FFF
        or 0x3400 <= code <= 0x4DBF
        or 0x3040 <= code <= 0x30FF
        or 0xAC00 <= code <= 0xD7AF
    )


def _has_cjk(text: str) -> bool:
    return any(_is_cjk_char(ch) for ch in text)


def is_credit_or_header_line(text: str) -> bool:
    cleaned = re.sub(r"<[^>]+>|\[[^\]]+\]", " ", text or "")
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    if not cleaned:
        return False
    if CREDIT_SECTION_HEADER_RE.match((text or "").strip()):
        return True
    m = re.match(r"^([^:：]{1,28})\s*[:：]\s*(.+)$", cleaned)
    if not m:
        return False
    head = m.group(1)
    compact_head = re.sub(r"\s+", "", head).strip()
    if not compact_head:
        return False
    if 1 <= len(compact_head) <= 12 and all(
        _is_cjk_char(ch) or ch in "/・·&" for ch in compact_head
    ):
        return True
    if compact_head.lower() in LATIN_CREDIT_PREFIXES:
        return True
    return False

NOISE_PATTERNS = [
    r"^\s*\d{1,3}\s*(?:[-._]\s+|\)\s*)",
    r"\(\s*(?:official|lyric|lyrics|music|audio|video|mv|visualizer|remaster(?:ed)?|deluxe|expanded|full\s+moon|single\s+version|album\s+version|original\s+score|original\s+soundtrack|reveal\s+edition|explicit|bonus\s+track|hd|4k|hq|\d{4})[^)]*\)",
    r"\[\s*(?:official|lyric|lyrics|music|audio|video|mv|visualizer|remaster(?:ed)?|deluxe|expanded|explicit|hd|4k|hq|\d{4}|[^\]]*歌詞[^\]]*)[^\]]*\]",
    r"\(\s*(?:feat\.?|ft\.?|prod\.?)[^)]*\)",
    r"\[\s*(?:feat\.?|ft\.?|prod\.?)[^\]]*\]",
    r"\b(?:official\s+(?:music\s+)?video|official\s+audio|lyric\s+video|lyrics\s+video|m/v|mv)\b",
]
ARTIST_NOISE_RE = re.compile(r"\s*-\s*topic$|\bvevo$", re.IGNORECASE)
VERSION_MODIFIER_RE = re.compile(
    r"\b(live|remix|acoustic|instrumental|karaoke|cover|radio\s+edit|sped\s+up|slowed)\b|伴奏|纯音乐|翻唱",
    re.IGNORECASE,
)

# Prosody / vocal expression patterns for living word animations
REPEAT_VOWEL_RE = re.compile(
    r"([aăâeêioôơuưyáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ])\1+",
    re.IGNORECASE,
)
REPEAT_SONORANT_RE = re.compile(r"([mnhlrw])\1{2,}", re.IGNORECASE)
VIBRATO_VOCAL_SET = {
    "oh", "ooh", "oooh", "ah", "aah", "aaah", "uh", "huh", "mmm", "mmmm",
    "hm", "hmm", "hmmm", "la", "lala", "lalala", "na", "nana", "nanana",
    "da", "dada", "whoa", "woah", "yeah", "yea", "yay", "ha", "hah", "hey",
    "ơ", "hơ", "ư", "hư", "à", "ơi", "hơi", "ố", "á", "hà", "nà", "ờ",
}
LONG_DIPHTHONG_RE = re.compile(
    r"(?:ươi|ươu|oai|oay|uôi|uây|iêu|yêu|uya|ai|ay|ao|au|âu|êu|iu|ui|ee|oo|ea|ou|ow|igh|ay|ey)",
    re.IGNORECASE,
)
OPEN_TAIL_RE = re.compile(
    r"[aăâeêioôơuưyáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵmnhw~…]$",
    re.IGNORECASE,
)
VI_RISING_CHARS = set("áắấéếíóốớúứýảẩểỉỏổởủửỷãẫễĩõỗỡũữỹ")
VI_FALLING_CHARS = set("àằầèềìòồờùừỳạặậẹệịọộợụựỵ")
RISE_KEYWORDS = {
    "high", "sky", "fly", "cry", "why", "shine", "fire", "light", "rise",
    "up", "love", "heart", "soul", "scream", "shout", "burn", "dream",
    "free", "alive", "forever", "sun", "star", "heaven", "cao", "bay",
    "sáng", "cháy", "yêu", "thương", "vời", "trời", "mơ", "say", "vang",
    "lên", "bừng", "rực", "hát", "vươn",
}
FALL_KEYWORDS = {
    "down", "fall", "fade", "slow", "low", "gone", "away", "sleep", "deep",
    "night", "dark", "cold", "quiet", "whisper", "end", "alone", "shadow",
    "rain", "tears", "buồn", "rơi", "tàn", "phai", "xa", "chìm", "đêm",
    "lặng", "thầm", "sâu", "cuối", "thôi", "rồi", "xuống", "nhòa", "khóc",
}


def emit(payload: dict, request_id: str = "") -> None:
    if request_id:
        payload["requestId"] = request_id
    try:
        sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        return


def get_json(url: str, data: bytes | None = None, extra_headers: dict | None = None, timeout: float = TIMEOUT):
    headers = {"User-Agent": USER_AGENT}
    if extra_headers:
        headers.update(extra_headers)
    request = urllib.request.Request(url, data=data, headers=headers)
    try:
        response = urllib.request.urlopen(request, timeout=timeout)
    except urllib.error.HTTPError as exc:
        if exc.code != 429:
            raise
        retry_after = float(exc.headers.get("Retry-After", "1"))
        time.sleep(max(0.0, min(retry_after, 3.0)))
        response = urllib.request.urlopen(request, timeout=timeout)
    with response:
        return json.loads(response.read().decode("utf-8", "replace"))


def clean_title(title: str) -> str:
    cleaned = (title or "").strip()
    cleaned = re.sub(r"^\s*\d{1,3}\s*(?:[-._]\s+|\)\s*)", "", cleaned)
    for pattern in NOISE_PATTERNS:
        cleaned = re.sub(pattern, " ", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" -–—|")
    return cleaned or (title or "").strip()


def clean_artist(artist: str) -> str:
    cleaned = ARTIST_NOISE_RE.sub("", artist or "").strip()
    cleaned = re.sub(r"\s*(?:feat\.?|ft\.?|&|,|;|/|x)\s+.*$", "", cleaned, flags=re.IGNORECASE).strip()
    cleaned = re.sub(r"[\s._·•\-–—]+$", "", cleaned).strip()
    return cleaned or (artist or "").strip()


def split_artist_title(title: str, artist: str) -> tuple[str, str]:
    c_title = clean_title(title)
    c_artist = clean_artist(artist)
    for sep in (" - ", " – ", " — "):
        if sep in c_title:
            left, right = c_title.split(sep, 1)
            left = clean_title(left.strip())
            right = clean_title(right.strip())
            if left and right:
                if not c_artist:
                    return right, clean_artist(left)
                if normalize(left) == normalize(c_artist) or normalize(c_artist) in normalize(left):
                    return right, c_artist
                if normalize(right) == normalize(c_artist) or normalize(c_artist) in normalize(right):
                    return left, c_artist
    return c_title, c_artist


def format_lrc_Time(seconds: float, inline: bool = False) -> str:
    sec = max(0.0, float(seconds))
    minutes = int(sec // 60)
    rem = sec - minutes * 60
    if inline:
        return f"<{minutes:02d}:{rem:06.3f}>"
    return f"[{minutes:02d}:{rem:06.3f}]"


def convert_netease_yrc_to_enhanced_lrc(yrc_text: str) -> str:
    """Convert NetEase verbatim YRC format into Enhanced LRC with <mm:ss.xxx> word tags."""
    out_lines: list[str] = []
    for raw in (yrc_text or "").splitlines():
        line = raw.strip()
        if not line or line.startswith("{"):
            continue
        m = YRC_LINE_RE.match(line)
        if not m:
            continue
        line_start_ms = int(m.group(1))
        line_dur_ms = int(m.group(2))
        body = m.group(3)
        tokens = list(YRC_WORD_RE.finditer(body))
        if not tokens:
            continue

        grouped: list[tuple[float, float, str]] = []
        for tok in tokens:
            w_start = int(tok.group(1)) / 1000.0
            w_dur = max(0.02, int(tok.group(2)) / 1000.0)
            w_end = w_start + w_dur
            piece = tok.group(3)
            if not piece:
                continue
            # Merge sub-word pieces (including contractions with ' or ’) when neither piece has CJK
            if (
                grouped
                and not grouped[-1][2].endswith((" ", "\t"))
                and not piece.startswith((" ", "\t"))
                and not _has_cjk(grouped[-1][2].strip())
                and not _has_cjk(piece.strip())
            ):
                prev_start, _prev_end, prev_text = grouped[-1]
                grouped[-1] = (prev_start, w_end, prev_text + piece)
            else:
                grouped.append((w_start, w_end, piece))

        full_line_text = " ".join(p.strip() for _, _, p in grouped if p.strip()).strip()
        if not full_line_text or is_credit_or_header_line(full_line_text):
            continue

        parts: list[str] = [format_lrc_Time(line_start_ms / 1000.0, inline=False)]
        clean_grouped = [(ws, we, p.strip()) for ws, we, p in grouped if p.strip()]
        if not clean_grouped:
            continue
        last_end = clean_grouped[-1][1]
        for idx_g, (w_start, w_end, clean_piece) in enumerate(clean_grouped):
            next_ws = clean_grouped[idx_g + 1][0] if idx_g + 1 < len(clean_grouped) else w_end
            if idx_g + 1 < len(clean_grouped) and (next_ws - w_end) > 0.025:
                parts.append(f"{format_lrc_Time(w_start, inline=True)}{clean_piece}{format_lrc_Time(w_end, inline=True)} ")
            else:
                parts.append(f"{format_lrc_Time(w_start, inline=True)}{clean_piece} ")
            last_end = w_end
        parts.append(format_lrc_Time(last_end, inline=True))
        out_lines.append("".join(parts).strip())
    return "\n".join(out_lines)


def convert_netease_klyric_to_enhanced_lrc(klyric_text: str) -> str:
    """Convert NetEase klyric or Kugou KRC format into Enhanced LRC with <mm:ss.xxx> word tags."""
    out_lines: list[str] = []
    for raw in (klyric_text or "").splitlines():
        line = raw.strip()
        if not line or line.startswith("{"):
            continue
        m = KLYRIC_LINE_RE.match(line)
        if not m:
            continue
        line_start_ms = int(m.group(1))
        line_dur_ms = int(m.group(2))
        body = m.group(3)
        tokens = list(KLYRIC_WORD_RE.finditer(body))
        if not tokens:
            continue
        grouped: list[tuple[float, float, str]] = []
        for tok in tokens:
            rel_start_ms = int(tok.group(1))
            w_dur_ms = max(20, int(tok.group(2)))
            piece = tok.group(3)
            if not piece:
                continue
            w_start = (line_start_ms + rel_start_ms) / 1000.0
            w_end = w_start + w_dur_ms / 1000.0
            if (
                grouped
                and not grouped[-1][2].endswith((" ", "\t"))
                and not piece.startswith((" ", "\t"))
                and not _has_cjk(grouped[-1][2].strip())
                and not _has_cjk(piece.strip())
            ):
                prev_start, _prev_end, prev_text = grouped[-1]
                grouped[-1] = (prev_start, w_end, prev_text + piece)
            else:
                grouped.append((w_start, w_end, piece))

        clean_grouped = [(ws, we, p.strip()) for ws, we, p in grouped if p.strip()]
        if not clean_grouped:
            continue
        full_line_text = " ".join(p for _, _, p in clean_grouped).strip()
        if not full_line_text or is_credit_or_header_line(full_line_text):
            continue

        parts: list[str] = [format_lrc_Time(line_start_ms / 1000.0, inline=False)]
        last_end = clean_grouped[-1][1]
        for idx_k, (w_start, w_end, piece) in enumerate(clean_grouped):
            next_ws = clean_grouped[idx_k + 1][0] if idx_k + 1 < len(clean_grouped) else w_end
            if idx_k + 1 < len(clean_grouped) and (next_ws - w_end) > 0.025:
                parts.append(f"{format_lrc_Time(w_start, inline=True)}{piece}{format_lrc_Time(w_end, inline=True)} ")
            else:
                parts.append(f"{format_lrc_Time(w_start, inline=True)}{piece} ")
            last_end = w_end
        parts.append(format_lrc_Time(last_end, inline=True))
        out_lines.append("".join(parts).strip())
    return "\n".join(out_lines)


def prosodic_word_weight(word: str, index: int, total: int) -> tuple[float, float]:
    """Return (vocal_weight, post_pause_seconds) for natural singing cadence."""
    stripped = word.strip()
    core = re.sub(r"^[^\w]+|[^\w]+$", "", stripped)
    char_len = max(1, len(core))
    weight = max(0.75, char_len ** 0.72)

    # Short function words are sung faster
    lower = core.lower()
    if lower in {"a", "an", "the", "to", "in", "on", "of", "at", "is", "it", "và", "là", "của", "cho", "với", "như"}:
        weight *= 0.72

    # Elongated vowels / melisma / diphthongs
    if REPEAT_VOWEL_RE.search(core) or REPEAT_SONORANT_RE.search(core) or "~" in stripped:
        weight += 1.55
    elif LONG_DIPHTHONG_RE.search(core):
        weight += 0.42

    if lower in VIBRATO_VOCAL_SET:
        weight += 0.85

    # Punctuation pauses & phrase-final sustain
    post_pause = 0.0
    if stripped.endswith(("...", "…", "~")):
        weight += 0.75
        post_pause = 0.16
    elif stripped.endswith(("!", "?", ".")):
        weight += 0.50
        post_pause = 0.14
    elif stripped.endswith((",", ";", ":", "—", "-")):
        weight += 0.32
        post_pause = 0.09

    # Final word of a lyric line is naturally sustained by singers
    if index == total - 1:
        weight += 0.70
        post_pause = 0.0

    return weight, post_pause


def classify_word_expression(
    word_text: str,
    start: float,
    end: float,
    index: int,
    total: int,
    avg_duration: float,
) -> dict:
    """Analyze a word's timing and phonetic structure for vocal expression effects:
    - vibrato (ngân nga): wave oscillation / melisma / humming
    - sustain (kéo dài): horizontal stretch + luminous sustain bar
    - rise (lên giọng): upward pitch float + crescendo scale boost
    - fall (xuống giọng): gentle downward pitch glide + soft decrescendo
    """
    duration = max(0.04, end - start)
    stripped = word_text.strip()
    core = re.sub(r"^[^\w]+|[^\w]+$", "", stripped)
    lower = core.lower()
    rel_dur = duration / max(0.16, avg_duration)

    vibrato = 0.0
    sustain = 0.0
    rise = 0.0
    fall = 0.0

    # 1. Vibrato / Ngân nga detection
    if "~" in stripped or "…" in stripped or ".." in stripped:
        vibrato = 1.0
    elif REPEAT_VOWEL_RE.search(core) or REPEAT_SONORANT_RE.search(core):
        vibrato = 0.95
    elif lower in VIBRATO_VOCAL_SET:
        vibrato = 0.90
    elif duration >= 0.72 and OPEN_TAIL_RE.search(core):
        vibrato = min(0.88, 0.45 + (duration - 0.60) * 0.75)

    # 2. Sustain / Kéo dài detection
    if duration >= 0.48 or rel_dur >= 1.32:
        sustain = min(1.0, max((duration - 0.34) / 0.80, (rel_dur - 1.10) / 1.05))
    if index == total - 1 and duration >= 0.40:
        sustain = max(sustain, min(0.95, duration / 0.82))
    if LONG_DIPHTHONG_RE.search(core) and duration >= 0.36:
        sustain = max(sustain, 0.58)

    # 3. Rise / Lên giọng detection
    if stripped.endswith(("!", "?", "?!", "!?")):
        rise = 0.95
    elif len(core) >= 2 and core.isupper():
        rise = 0.90
    if lower in RISE_KEYWORDS:
        rise = max(rise, 0.82)
    if any(ch in VI_RISING_CHARS for ch in lower):
        rise = max(rise, 0.68 if rel_dur >= 1.0 else 0.50)
    # Phrase climax position (middle-to-late emphatic word)
    pos_ratio = (index + 0.5) / max(1, total)
    if 0.40 <= pos_ratio <= 0.85 and rel_dur >= 1.18 and not any(ch in VI_FALLING_CHARS for ch in lower):
        rise = max(rise, min(0.80, 0.45 + (rel_dur - 1.0) * 0.45))

    # 4. Fall / Xuống giọng detection
    if lower in FALL_KEYWORDS:
        fall = 0.82
    if any(ch in VI_FALLING_CHARS for ch in lower) and rise < 0.65:
        fall = max(fall, 0.72 if index >= total - 2 else 0.52)
    if index == total - 1 and stripped.endswith((".", ",", ";", "…", "..")) and not stripped.endswith(("!", "?")):
        fall = max(fall, 0.68)
    elif index == total - 1 and rise < 0.45 and vibrato < 0.55 and sustain < 0.65:
        fall = max(fall, 0.54)

    # Pick primary effect while preserving multi-dimensional expression weights
    candidates = [
        ("vibrato", vibrato),
        ("rise", rise),
        ("sustain", sustain),
        ("fall", fall),
    ]
    best_effect, best_score = max(candidates, key=lambda item: item[1])
    if best_score < 0.45:
        best_effect = "normal"
        intensity = min(0.75, max(0.30, rel_dur * 0.45))
    else:
        intensity = min(1.0, max(0.45, best_score))

    return {
        "text": stripped,
        "start": round(start, 3),
        "end": round(end, 3),
        "duration": round(duration, 3),
        "effect": best_effect,
        "intensity": round(intensity, 2),
        "sustain": round(sustain, 2),
        "rise": round(rise, 2),
        "fall": round(fall, 2),
        "vibrato": round(vibrato, 2),
    }


def parse_inline_words(raw_lyric: str, line_start: float, line_end: float, offset_seconds: float) -> list[dict]:
    """Parse Enhanced LRC inline <mm:ss.xx> word timestamps if present."""
    matches = list(INLINE_WORD_STAMP.finditer(raw_lyric))
    if not matches:
        return []

    timed_segments: list[tuple[float, str]] = []
    # Check if there is text before the first inline stamp
    prefix = raw_lyric[:matches[0].start()].strip()
    if prefix:
        timed_segments.append((line_start, prefix))

    for idx, m in enumerate(matches):
        minutes = int(m.group(1))
        seconds = float(m.group(2).replace(":", "."))
        stamp_t = max(0.0, round(minutes * 60 + seconds - offset_seconds, 3))
        seg_start = m.end()
        seg_end = matches[idx + 1].start() if idx + 1 < len(matches) else len(raw_lyric)
        seg_text = raw_lyric[seg_start:seg_end].strip()
        timed_segments.append((stamp_t, seg_text))

    # Expand segments that contain multiple whitespace-separated words
    raw_words: list[tuple[float, float, str]] = []
    for idx, (seg_t, seg_text) in enumerate(timed_segments):
        if not seg_text:
            continue
        is_last_seg = not any(t_txt for _, t_txt in timed_segments[idx + 1:])
        next_t = timed_segments[idx + 1][0] if idx + 1 < len(timed_segments) else line_end
        if next_t <= seg_t:
            next_t = max(seg_t + 0.18, line_end if idx + 1 == len(timed_segments) else seg_t + 0.28)
        sub_words = seg_text.split()
        if len(sub_words) == 1:
            w_str = sub_words[0]
            if is_last_seg and (next_t - seg_t) > 2.4:
                char_count = max(1, len(re.sub(r"[^\w]+", "", w_str)))
                next_t = seg_t + min(2.2, max(0.85, 0.35 + char_count * 0.11))
            raw_words.append((seg_t, next_t, w_str))
        else:
            weights = [prosodic_word_weight(w, i, len(sub_words))[0] for i, w in enumerate(sub_words)]
            total_w = sum(weights) or 1.0
            span = max(0.08 * len(sub_words), next_t - seg_t)
            cursor = seg_t
            for w_str, w_val in zip(sub_words, weights):
                w_dur = span * (w_val / total_w)
                raw_words.append((cursor, cursor + w_dur, w_str))
                cursor += w_dur

    if not raw_words:
        return []

    total = len(raw_words)
    avg_dur = sum(max(0.04, e - s) for s, e, _ in raw_words) / max(1, total)
    return [
        classify_word_expression(w_text, w_start, w_end, i, total, avg_dur)
        for i, (w_start, w_end, w_text) in enumerate(raw_words)
    ]


def _estimated_line_vocal_span(clean_text: str) -> float:
    tokens = [w for w in (clean_text or "").split() if w.strip()]
    if not tokens or clean_text.strip() == "♪":
        return 1.2
    chars = len(re.sub(r"[^\w]+", "", clean_text))
    return max(1.25, min(8.5, 0.42 + len(tokens) * 0.40 + chars * 0.05))


def synthesize_prosodic_words(clean_text: str, line_start: float, line_end: float) -> list[dict]:
    """Synthesize natural singing word timestamps from line start/end and vocal prosody."""
    tokens = [w for w in (clean_text or "").split() if w.strip()]
    if not tokens or clean_text.strip() == "♪":
        return []

    total = len(tokens)
    total_span = max(0.25, line_end - line_start)
    weights_and_pauses = [prosodic_word_weight(w, i, total) for i, w in enumerate(tokens)]
    total_weight = sum(w for w, _ in weights_and_pauses) or 1.0
    raw_pauses = sum(p for _, p in weights_and_pauses)
    pause_scale = min(1.0, (total_span * 0.22) / raw_pauses) if raw_pauses > 0 else 0.0
    vocal_span = max(0.15, total_span - raw_pauses * pause_scale)

    raw_words: list[tuple[float, float, str]] = []
    cursor = line_start
    for w_text, (w_val, p_val) in zip(tokens, weights_and_pauses):
        w_dur = vocal_span * (w_val / total_weight)
        w_start = cursor
        w_end = cursor + w_dur
        raw_words.append((w_start, w_end, w_text))
        cursor = w_end + p_val * pause_scale

    avg_dur = vocal_span / max(1, total)
    return [
        classify_word_expression(w_text, w_start, w_end, i, total, avg_dur)
        for i, (w_start, w_end, w_text) in enumerate(raw_words)
    ]


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
        if METADATA_RE.match(raw):
            continue
        stamps = list(STAMP.finditer(raw))
        if not stamps:
            continue
        raw_lyric = raw[stamps[-1].end():].strip()
        clean_lyric = re.sub(r"\s+", " ", INLINE_WORD_STAMP.sub(" ", raw_lyric)).strip()
        if clean_lyric and is_credit_or_header_line(clean_lyric):
            continue
        for stamp in stamps:
            minutes = int(stamp.group(1))
            seconds = float(stamp.group(2).replace(":", "."))
            timestamp = max(0.0, round(minutes * 60 + seconds - offset_seconds, 3))
            out.append({
                key_name: timestamp,
                "text": clean_lyric,
                "_raw_lyric": raw_lyric,
            })
    out.sort(key=lambda line: line[key_name])

    # Enrich each line with endTime and word-level timing + vocal expression metadata
    n_lines = len(out)
    for i, item in enumerate(out):
        line_start = float(item[key_name])
        next_start = line_start + 4.2
        for j in range(i + 1, n_lines):
            cand_next = float(out[j][key_name])
            if cand_next > line_start + 0.05:
                next_start = cand_next
                break
        gap = max(0.35, next_start - line_start)
        est_max = _estimated_line_vocal_span(item["text"]) * 1.15
        vocal_window = min(max(0.35, gap - 0.06), min(est_max, gap * 0.88))
        line_end = round(line_start + vocal_window, 3)
        raw_lyric = item.pop("_raw_lyric", "")
        words = parse_inline_words(raw_lyric, line_start, line_end, offset_seconds)
        if words:
            line_end = round(max(line_end, words[-1]["end"]), 3)
        else:
            words = synthesize_prosodic_words(item["text"], line_start, line_end)
        item["endTime"] = line_end
        item["words"] = words

    return out


def parse_plain(plain: str, duration: float | None = None, key_name: str = "t") -> list[dict]:
    raw_lines = [
        line.strip()
        for line in (plain or "").splitlines()
        if line.strip() and not METADATA_RE.match(line) and not is_credit_or_header_line(line)
    ]
    if not raw_lines:
        return []
    step = (float(duration) / max(len(raw_lines), 1)) if (duration and duration > 0) else 0.0
    out: list[dict] = []
    for i, text in enumerate(raw_lines):
        if step > 0:
            line_start = round(i * step, 3)
            line_end = round(line_start + max(0.5, step * 0.9), 3)
            words = synthesize_prosodic_words(text, line_start, line_end)
        else:
            line_start = None
            line_end = 0.0
            words = []
        out.append({
            key_name: line_start,
            "endTime": line_end,
            "text": text,
            "words": words,
        })
    return out


_LATIN_TRANS = str.maketrans("đĐłŁøØ", "dDlLoO")


def fold_ascii(value: str) -> str:
    """Fold Latin/Vietnamese diacritics for ASCII-tag comparisons without altering CJK/kana."""
    folded = unicodedata.normalize("NFKD", (value or "").translate(_LATIN_TRANS))
    return "".join(ch for ch in folded if not (0x0300 <= ord(ch) <= 0x036F))


def normalize(value: str) -> str:
    folded = fold_ascii(value).lower()
    return re.sub(r"\s+", " ", re.sub(r"[^\w\s]", " ", folded)).strip()


TITLE_STOPWORDS = {
    "the", "and", "for", "you", "with", "from", "into", "out", "are", "was",
    "not", "all", "can", "one", "this", "that", "your", "our",
}


def has_mismatched_version_modifier(wanted_title: str, cand_title: str) -> bool:
    wanted_mods = {m.lower() for m in VERSION_MODIFIER_RE.findall(wanted_title or "")}
    cand_mods = {m.lower() for m in VERSION_MODIFIER_RE.findall(cand_title or "")}
    for mod in ("live", "remix", "instrumental", "karaoke", "cover", "8-bit"):
        if mod in cand_mods and mod not in wanted_mods:
            return True
    if any(k in (cand_title or "") for k in ("伴奏", "纯音乐", "翻唱")) and not any(
        k in (wanted_title or "") for k in ("伴奏", "纯音乐", "翻唱")
    ):
        return True
    return False


def overlaps(wanted: str, got: str) -> bool:
    wanted_n = normalize(clean_title(wanted)) or normalize(wanted)
    got_n = normalize(clean_title(got)) or normalize(got)
    if not wanted_n or not got_n:
        return False
    if wanted_n == got_n:
        return True
    w_words = wanted_n.split()
    g_words = got_n.split()
    if len(w_words) == 1 and len(g_words) == 1:
        return w_words[0] == g_words[0]
    if wanted_n in got_n or got_n in wanted_n:
        shorter = min(len(wanted_n), len(got_n))
        longer = max(len(wanted_n), len(got_n))
        if shorter >= 4 and (shorter / max(1, longer)) >= 0.45:
            return True
    w_sig = {w for w in w_words if w not in TITLE_STOPWORDS and len(w) >= 2} or set(w_words)
    g_sig = {w for w in g_words if w not in TITLE_STOPWORDS and len(w) >= 2} or set(g_words)
    common = w_sig & g_sig
    if not common:
        return False
    return (len(common) / max(1, len(w_sig))) >= 0.6 and (len(common) / max(1, len(g_sig))) >= 0.5


def artist_overlaps(wanted_artist: str, got_artist: str) -> bool:
    if not wanted_artist or not got_artist:
        return True
    w_norm = normalize(wanted_artist)
    g_norm = normalize(got_artist)
    if not w_norm or not g_norm:
        return True
    if w_norm == g_norm or w_norm in g_norm or g_norm in w_norm:
        return True
    w_parts = [
        normalize(p)
        for p in re.split(r"(?:feat\.?|ft\.?|&|,|;|/|\bx\b)", wanted_artist, flags=re.IGNORECASE)
        if normalize(p)
    ]
    g_parts = [
        normalize(p)
        for p in re.split(r"(?:feat\.?|ft\.?|&|,|;|/|\bx\b)", got_artist, flags=re.IGNORECASE)
        if normalize(p)
    ]
    for wp in w_parts:
        for gp in g_parts:
            if wp == gp or (len(wp) >= 4 and wp in gp) or (len(gp) >= 4 and gp in wp):
                return True
    return False


def score_candidate(candidate: dict, title: str, artist: str, duration: float | None) -> float:
    cand_title = str(candidate.get("trackName") or candidate.get("name") or "")
    cand_artist = str(candidate.get("artistName") or "")
    c_title, c_artist = split_artist_title(title, artist)
    if has_mismatched_version_modifier(title, cand_title):
        return -1.0
    if not (overlaps(title, cand_title) or overlaps(c_title, cand_title)):
        return -1.0
    if (artist or c_artist) and cand_artist:
        if not (artist_overlaps(artist, cand_artist) or artist_overlaps(c_artist, cand_artist)):
            return -1.0

    score = 0.0
    if normalize(clean_title(title)) == normalize(clean_title(cand_title)) or normalize(c_title) == normalize(clean_title(cand_title)):
        score += 45.0
    elif overlaps(c_title, cand_title):
        score += 25.0

    if (artist or c_artist) and cand_artist:
        if normalize(clean_artist(artist)) == normalize(clean_artist(cand_artist)) or normalize(c_artist) == normalize(clean_artist(cand_artist)):
            score += 35.0
        elif artist_overlaps(artist, cand_artist) or artist_overlaps(c_artist, cand_artist):
            score += 22.0

    if duration and duration > 0:
        cand_dur = candidate.get("duration")
        try:
            diff = abs(float(cand_dur) - float(duration))
            if diff <= 1.5:
                score += 35.0
            elif diff <= 3.5:
                score += 25.0
            elif diff <= 8.0:
                score += 12.0
            elif diff <= 18.0:
                score += 2.0
            elif diff > 25.0:
                return -1.0
            else:
                score -= 15.0
        except (TypeError, ValueError):
            pass

    synced_text = str(candidate.get("syncedLyrics") or "")
    if synced_text:
        score += 30.0
        if INLINE_WORD_STAMP.search(synced_text):
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
    if album and duration and (artist or c_artist):
        attempts.append(
            f"{LRCLIB_API}/get?track_name={q(c_title or title)}&artist_name={q(c_artist or artist)}&album_name={q(album)}&duration={int(round(duration))}"
        )
    if c_artist or artist:
        attempts.append(f"{LRCLIB_API}/search?track_name={q(c_title or title)}&artist_name={q(c_artist or artist)}")
    if (c_title != title or c_artist != artist) and title:
        if artist:
            attempts.append(f"{LRCLIB_API}/search?track_name={q(title)}&artist_name={q(artist)}")
        attempts.append(f"{LRCLIB_API}/search?q={q((c_title + ' ' + c_artist).strip())}")
    attempts.append(f"{LRCLIB_API}/search?q={q(((c_title or title) + ' ' + (c_artist or artist)).strip())}")

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


def fetch_from_netease(
    title: str,
    artist: str,
    duration: float | None,
    verbatim_only: bool = False,
    timeout: float = TIMEOUT,
) -> tuple[str, bool, bool]:
    """Fetch lyrics from NetEase Cloud Music (supports YRC/klyric verbatim word sync + LRC).

    Returns (raw_lrc_text, is_synced, is_word_synced).
    """
    c_title, c_artist = split_artist_title(title, artist)
    queries: list[str] = []
    if c_title and c_artist:
        queries.append(f"{c_title} {c_artist}".strip())
    if title and artist and f"{title} {artist}".strip() not in queries:
        queries.append(f"{clean_title(title)} {artist}".strip())
    if c_title and c_title not in queries:
        queries.append(c_title)
    if not queries:
        return "", False, False

    headers = {
        "Referer": "https://music.163.com",
        "Content-Type": "application/x-www-form-urlencoded",
    }

    scored_songs: list[tuple[float, float, dict]] = []
    seen_ids: set[int] = set()

    for q_idx, query in enumerate(queries[:2]):
        if q_idx > 0 and scored_songs:
            break
        form = urllib.parse.urlencode({"s": query, "type": 1, "offset": 0, "limit": 12}).encode("utf-8")
        try:
            search_data = get_json(NETEASE_SEARCH_API, data=form, extra_headers=headers, timeout=timeout)
        except Exception:
            continue
        songs = ((search_data or {}).get("result") or {}).get("songs") or []
        if not isinstance(songs, list):
            continue

        for song in songs:
            if not isinstance(song, dict):
                continue
            song_id = song.get("id")
            if not song_id or int(song_id) in seen_ids:
                continue
            seen_ids.add(int(song_id))
            song_name = str(song.get("name") or "")
            artists = song.get("artists") or []
            artist_names = ", ".join(str(a.get("name") or "") for a in artists if isinstance(a, dict))
            if has_mismatched_version_modifier(title, song_name):
                continue
            if not (overlaps(title, song_name) or overlaps(c_title, song_name)):
                continue
            if (artist or c_artist) and artist_names:
                if not (artist_overlaps(artist, artist_names) or artist_overlaps(c_artist, artist_names)):
                    continue

            dur_diff = 0.0
            s_score = 0.0
            if normalize(clean_title(song_name)) == normalize(c_title):
                s_score += 45.0
            else:
                s_score += 22.0
            if (artist or c_artist) and artist_names:
                if normalize(clean_artist(artist_names)) == normalize(c_artist):
                    s_score += 35.0
                else:
                    s_score += 20.0

            if duration and duration > 0 and song.get("duration"):
                try:
                    song_dur = float(song["duration"]) / 1000.0
                    dur_diff = abs(song_dur - float(duration))
                    if dur_diff > 22.0:
                        continue
                    if dur_diff <= 1.5:
                        s_score += 45.0
                    elif dur_diff <= 3.5:
                        s_score += 32.0
                    elif dur_diff <= 7.0:
                        s_score += 15.0
                    elif dur_diff <= 14.0:
                        s_score += 2.0
                    else:
                        s_score -= 12.0
                except (TypeError, ValueError):
                    pass

            scored_songs.append((s_score, dur_diff, song))

    scored_songs.sort(key=lambda item: (-item[0], item[1]))
    best_line_lrc = ""

    for _s_score, dur_diff, song in scored_songs[:5]:
        song_id = int(song["id"])
        try:
            lyric_url = f"{NETEASE_LYRIC_API}?id={song_id}&yv=1&lv=1&kv=1&tv=-1"
            lyric_data = get_json(
                lyric_url,
                extra_headers={"Referer": "https://music.163.com"},
                timeout=timeout,
            )
        except Exception:
            continue

        # 1. Prefer NetEase YRC verbatim word-synced lyrics (when duration is reasonably close)
        yrc_raw = (((lyric_data or {}).get("yrc") or {}).get("lyric") or "").strip()
        if yrc_raw and dur_diff <= 14.0:
            enhanced = convert_netease_yrc_to_enhanced_lrc(yrc_raw)
            if enhanced and parse_lrc(enhanced):
                return enhanced, True, True

        # 2. Check NetEase klyric word-synced format
        klyric_raw = (((lyric_data or {}).get("klyric") or {}).get("lyric") or "").strip()
        if klyric_raw and dur_diff <= 14.0:
            enhanced = convert_netease_klyric_to_enhanced_lrc(klyric_raw)
            if enhanced and parse_lrc(enhanced):
                return enhanced, True, True

        if not verbatim_only and not best_line_lrc and dur_diff <= 12.0:
            lrc_text = (((lyric_data or {}).get("lrc") or {}).get("lyric") or "").strip()
            if lrc_text and parse_lrc(lrc_text):
                best_line_lrc = lrc_text

    if best_line_lrc:
        return best_line_lrc, True, bool(INLINE_WORD_STAMP.search(best_line_lrc))

    return "", False, False


def decode_kugou_krc(raw_b64: str) -> str:
    """Decode base64 + XOR + zlib compressed Kugou KRC verbatim word lyrics."""
    if not raw_b64:
        return ""
    data = bytearray(base64.b64decode(raw_b64))
    if len(data) <= 4:
        return ""
    payload = data[4:]
    for i in range(len(payload)):
        payload[i] ^= KUGOU_KRC_KEY[i % 16]
    return zlib.decompress(bytes(payload)).decode("utf-8", "replace")


def fetch_from_kugou(
    title: str,
    artist: str,
    duration: float | None,
    timeout: float = 4.5,
) -> tuple[str, bool, bool]:
    """Fetch verbatim word-synced KRC lyrics from Kugou Music."""
    c_title, c_artist = split_artist_title(title, artist)
    if not c_title:
        return "", False, False
    keyword = f"{c_artist} - {c_title}".strip(" -") if c_artist else c_title
    dur_ms = int(round(float(duration) * 1000)) if (duration and duration > 0) else ""
    search_url = f"{KUGOU_SEARCH_API}?" + urllib.parse.urlencode({
        "ver": 1,
        "man": "yes",
        "client": "pc",
        "keyword": keyword,
        "duration": dur_ms,
        "hash": "",
    })
    try:
        data = get_json(search_url, timeout=timeout)
    except Exception:
        return "", False, False

    candidates = (data or {}).get("candidates") or []
    if not isinstance(candidates, list) or not candidates:
        candidates = []

    if not candidates:
        # 2-step mobile search -> hash lookup fallback when direct KRC keyword search misses.
        mobile_url = f"{KUGOU_MOBILE_SEARCH_API}?" + urllib.parse.urlencode({
            "format": "json",
            "keyword": keyword,
            "page": 1,
            "pagesize": 8,
            "showtype": 1,
        })
        try:
            mobile_data = get_json(mobile_url, timeout=min(timeout, 3.5))
            info_list = ((mobile_data or {}).get("data") or {}).get("info") or []
        except Exception:
            info_list = []
        hash_hits: list[tuple[str, int]] = []
        for item in info_list:
            if not isinstance(item, dict):
                continue
            item_hash = str(item.get("hash") or "").strip()
            item_song = str(item.get("songname") or item.get("filename") or "")
            item_singer = str(item.get("singername") or "")
            if not item_hash:
                continue
            if has_mismatched_version_modifier(title, item_song):
                continue
            if not (overlaps(title, item_song) or overlaps(c_title, item_song)):
                continue
            if (artist or c_artist) and item_singer:
                if not (artist_overlaps(artist, item_singer) or artist_overlaps(c_artist, item_singer)):
                    continue
            item_dur_ms = int(round(float(item.get("duration") or 0) * 1000)) or (int(dur_ms) if dur_ms else 0)
            hash_hits.append((item_hash, item_dur_ms))
            if len(hash_hits) >= 2:
                break
        for item_hash, item_dur_ms in hash_hits:
            hash_url = f"{KUGOU_SEARCH_API}?" + urllib.parse.urlencode({
                "ver": 1,
                "man": "yes",
                "client": "pc",
                "keyword": keyword,
                "duration": item_dur_ms or "",
                "hash": item_hash,
            })
            try:
                h_data = get_json(hash_url, timeout=min(timeout, 3.5))
                h_cands = (h_data or {}).get("candidates") or []
                if isinstance(h_cands, list):
                    candidates.extend(h_cands)
            except Exception:
                continue

    if not isinstance(candidates, list) or not candidates:
        return "", False, False

    scored: list[tuple[float, dict]] = []
    for cand in candidates:
        if not isinstance(cand, dict):
            continue
        cand_id = cand.get("id")
        accesskey = cand.get("accesskey")
        cand_song = str(cand.get("song") or "")
        cand_singer = str(cand.get("singer") or "")
        if not cand_id or not accesskey:
            continue
        if has_mismatched_version_modifier(title, cand_song):
            continue
        if not (overlaps(title, cand_song) or overlaps(c_title, cand_song)):
            continue
        if (artist or c_artist) and cand_singer:
            if not (artist_overlaps(artist, cand_singer) or artist_overlaps(c_artist, cand_singer)):
                continue

        s_score = float(cand.get("score") or 0) * 0.4
        if normalize(clean_title(cand_song)) == normalize(c_title):
            s_score += 40.0
        if (artist or c_artist) and cand_singer and normalize(clean_artist(cand_singer)) == normalize(c_artist):
            s_score += 35.0
        if duration and duration > 0 and cand.get("duration"):
            try:
                cand_dur = float(cand["duration"]) / 1000.0
                diff = abs(cand_dur - float(duration))
                if diff > 16.0:
                    continue
                if diff <= 1.5:
                    s_score += 45.0
                elif diff <= 3.5:
                    s_score += 30.0
                elif diff <= 8.0:
                    s_score += 12.0
            except (TypeError, ValueError):
                pass
        scored.append((s_score, cand))

    scored.sort(key=lambda item: item[0], reverse=True)
    for _score, cand in scored[:3]:
        dl_url = f"{KUGOU_DOWNLOAD_API}?" + urllib.parse.urlencode({
            "ver": 1,
            "client": "pc",
            "id": cand["id"],
            "accesskey": cand["accesskey"],
            "fmt": "krc",
            "charset": "utf8",
        })
        try:
            dl_data = get_json(dl_url, timeout=timeout)
            krc_text = decode_kugou_krc(str((dl_data or {}).get("content") or ""))
        except Exception:
            continue
        if not krc_text:
            continue
        enhanced = convert_netease_klyric_to_enhanced_lrc(krc_text)
        if enhanced:
            # Strip Kugou title banner on the first line if it just repeats title/artist at t < 5s
            lines_raw = enhanced.splitlines()
            if len(lines_raw) > 2:
                first_clean = normalize(INLINE_WORD_STAMP.sub(" ", STAMP.sub(" ", lines_raw[0])))
                if first_clean and (
                    first_clean == normalize(c_title)
                    or first_clean == normalize(f"{c_artist} {c_title}")
                    or first_clean == normalize(f"{c_title} {c_artist}")
                ):
                    lines_raw = lines_raw[1:]
                    enhanced = "\n".join(lines_raw)
            if parse_lrc(enhanced):
                return enhanced, True, True

    return "", False, False


def _shift_lrc_timestamps(lrc_text: str, delta_sec: float) -> str:
    if abs(delta_sec) < 0.05:
        return lrc_text

    def _shift_line_stamp(m: re.Match) -> str:
        t = int(m.group(1)) * 60.0 + float(m.group(2).replace(":", "."))
        return format_lrc_Time(max(0.0, t + delta_sec), inline=False)

    def _shift_word_stamp(m: re.Match) -> str:
        t = int(m.group(1)) * 60.0 + float(m.group(2).replace(":", "."))
        return format_lrc_Time(max(0.0, t + delta_sec), inline=True)

    shifted_lines: list[str] = []
    for raw in (lrc_text or "").splitlines():
        line = STAMP.sub(_shift_line_stamp, raw)
        line = INLINE_WORD_STAMP.sub(_shift_word_stamp, line)
        shifted_lines.append(line)
    return "\n".join(shifted_lines)


def align_word_lrc_to_reference(word_lrc: str, ref_lrc: str) -> tuple[str, bool]:
    """Compare word-synced LRC against a duration-accurate reference LRC (embedded or LRCLIB).

    Returns (aligned_word_lrc, is_compatible).
    - If matching lines have a consistent lead-in offset (IQR <= 0.75s, 0.12s <= |median| <= 8.0s),
      shifts all word & line timestamps by +median_offset so Qobuz/Tidal/YouTube Music intros align.
    - If matching lines diverge strongly (IQR > 2.2s and |median| > 2.5s), marks incompatible.
    """
    if not word_lrc or not ref_lrc:
        return word_lrc, True
    word_lines = parse_lrc(word_lrc, key_name="t")
    ref_lines = parse_lrc(ref_lrc, key_name="t")
    if len(word_lines) < 4 or len(ref_lines) < 4:
        return word_lrc, True

    ref_by_text: dict[str, list[float]] = {}
    for item in ref_lines:
        norm = normalize(str(item.get("text") or ""))
        if len(norm) >= 4:
            ref_by_text.setdefault(norm, []).append(float(item["t"]))

    diffs: list[float] = []
    for item in word_lines:
        norm = normalize(str(item.get("text") or ""))
        if len(norm) < 4 or norm not in ref_by_text:
            continue
        w_t = float(item["t"])
        best_r_t = min(ref_by_text[norm], key=lambda rt: abs(rt - w_t))
        if abs(best_r_t - w_t) <= 12.0:
            diffs.append(best_r_t - w_t)

    if len(diffs) < 4:
        return word_lrc, True

    diffs.sort()
    n = len(diffs)
    median_diff = diffs[n // 2] if n % 2 == 1 else 0.5 * (diffs[n // 2 - 1] + diffs[n // 2])
    q1 = diffs[n // 4]
    q3 = diffs[(3 * n) // 4]
    iqr = q3 - q1

    if iqr > 2.4 and abs(median_diff) > 2.5:
        return word_lrc, False

    if iqr <= 0.75 and 0.12 <= abs(median_diff) <= 8.0:
        return _shift_lrc_timestamps(word_lrc, median_diff), True

    return word_lrc, True


def extract_local_audio_info(audio_path: str) -> dict[str, object]:
    """Read exact duration, tags, and embedded LYRICS from local FLAC/MP3/M4A via ffprobe."""
    info: dict[str, object] = {
        "duration": None,
        "title": "",
        "artist": "",
        "album": "",
        "embedded_lyrics": "",
        "embedded_synced": False,
    }
    if not audio_path or "://" in audio_path:
        return info
    path = Path(os.path.expanduser(audio_path))
    if not path.is_file():
        return info

    try:
        out = subprocess.check_output(
            [
                "ffprobe",
                "-v",
                "quiet",
                "-show_entries",
                "format=duration:format_tags",
                "-of",
                "json",
                str(path),
            ],
            text=True,
            timeout=2.5,
        )
        fmt = (json.loads(out) or {}).get("format") or {}
        if fmt.get("duration"):
            info["duration"] = float(fmt["duration"])
        tags = fmt.get("tags") or {}
        if isinstance(tags, dict):
            lower_tags = {str(k).lower(): str(v) for k, v in tags.items() if v is not None}
            info["title"] = lower_tags.get("title", "").strip()
            info["artist"] = (
                lower_tags.get("artist")
                or lower_tags.get("album_artist")
                or lower_tags.get("albumartist")
                or ""
            ).strip()
            info["album"] = lower_tags.get("album", "").strip()
            for k, v in lower_tags.items():
                if "lyric" in k and v.strip():
                    emb = v.strip()
                    info["embedded_lyrics"] = emb
                    info["embedded_synced"] = bool(STAMP.search(emb))
                    break
    except Exception:
        pass

    # Infer fallback artist/title from file path (/Music/<Lang>/<Artist>/<Album>/<Track> - <Title>.ext)
    if not info["artist"]:
        parent_name = path.parent.name
        grandparent_name = path.parent.parent.name if path.parent.parent else ""
        skip_folders = {"music", "mp3", "en", "vn", "cn", "jp", "fr", "de", "soundtrack", "[standalone recordings]"}
        if grandparent_name and grandparent_name.lower() not in skip_folders:
            info["artist"] = grandparent_name
        elif parent_name and parent_name.lower() not in skip_folders:
            info["artist"] = parent_name

    return info


def find_lyrics_raw(
    title: str,
    artist: str,
    album: str,
    duration: float | None,
    embedded_lyrics: str = "",
    embedded_synced: bool = False,
) -> tuple[str, bool]:
    last_error: Exception | None = None
    try:
        raw_text, is_synced = fetch_from_lrclib(title, artist, album, duration)
    except Exception as exc:
        last_error = exc
        raw_text, is_synced = "", False

    # Reference synced LRC for exact Qobuz/Tidal/YouTube Music intro offset verification
    ref_synced_lrc = ""
    if embedded_lyrics and embedded_synced:
        ref_synced_lrc = embedded_lyrics
    elif raw_text and is_synced:
        ref_synced_lrc = raw_text

    # 1. If LRCLIB or embedded lyrics already contain word-level Enhanced LRC (<mm:ss.xx>), use immediately
    if raw_text and is_synced and INLINE_WORD_STAMP.search(raw_text):
        return raw_text, True
    if embedded_lyrics and embedded_synced and INLINE_WORD_STAMP.search(embedded_lyrics):
        return embedded_lyrics, True

    # 2. Try NetEase for verbatim word-level (YRC/klyric) or fallback synced LRC
    word_timeout = 4.0 if ref_synced_lrc else TIMEOUT
    synced_netease, netease_is_synced, netease_word_synced = fetch_from_netease(
        title,
        artist,
        duration,
        verbatim_only=bool(ref_synced_lrc),
        timeout=word_timeout,
    )
    if synced_netease and netease_word_synced:
        aligned, ok = align_word_lrc_to_reference(synced_netease, ref_synced_lrc)
        if ok:
            return aligned, True

    # 3. Try Kugou KRC for verbatim word-level lyrics
    synced_kugou, _kugou_synced, kugou_word_synced = fetch_from_kugou(
        title,
        artist,
        duration,
        timeout=word_timeout,
    )
    if synced_kugou and kugou_word_synced:
        aligned, ok = align_word_lrc_to_reference(synced_kugou, ref_synced_lrc)
        if ok:
            return aligned, True

    # 4. Fall back to embedded synced LRC, LRCLIB synced LRC, or NetEase line-synced LRC
    if embedded_lyrics and embedded_synced:
        return embedded_lyrics, True

    if raw_text and is_synced:
        return raw_text, True

    if synced_netease and netease_is_synced:
        return synced_netease, True

    if embedded_lyrics:
        return embedded_lyrics, False

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


def strip_credit_lines_from_lrc(raw_text: str) -> str:
    kept: list[str] = []
    for raw in (raw_text or "").splitlines():
        stamps = list(STAMP.finditer(raw))
        lyric_part = raw[stamps[-1].end():].strip() if stamps else raw.strip()
        if lyric_part and is_credit_or_header_line(lyric_part):
            continue
        kept.append(raw)
    return "\n".join(kept)


def save_lrc_for_local_track(audio_path: str, raw_text: str, is_synced: bool) -> str:
    clean_raw = strip_credit_lines_from_lrc(raw_text)
    track = Path(os.path.expanduser(audio_path))
    suffix = ".lrc" if is_synced else ".txt"
    target = track.with_suffix(suffix)
    try:
        target.write_text(clean_raw.rstrip() + "\n", encoding="utf-8")
        return str(target)
    except OSError:
        fallback_dir = Path(
            os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local" / "share")
        ) / "alis" / "lyrics"
        fallback_dir.mkdir(parents=True, exist_ok=True)
        digest = hashlib.sha1(str(track).encode("utf-8", "replace")).hexdigest()[:12]
        fallback = fallback_dir / f"{track.stem}-{digest}{suffix}"
        fallback.write_text(clean_raw.rstrip() + "\n", encoding="utf-8")
        return str(fallback)


def run_save_lrc_mode(args: list[str], upgrade_only: bool = False) -> None:
    audio_path = args[0].strip() if len(args) > 0 else ""
    title = args[1].strip() if len(args) > 1 else ""
    artist = args[2].strip() if len(args) > 2 else ""
    duration_str = args[3].strip() if len(args) > 3 else ""
    album = args[4].strip() if len(args) > 4 else ""

    if not audio_path:
        emit({"status": "not_found", "path": "", "synced": False, "wordSynced": False, "lines": []})
        return

    try:
        duration = float(duration_str) if duration_str else None
    except ValueError:
        duration = None

    audio_info = extract_local_audio_info(audio_path)
    if audio_info.get("duration"):
        duration = float(audio_info["duration"])
    if not title and audio_info.get("title"):
        title = str(audio_info["title"])
    if not artist and audio_info.get("artist"):
        artist = str(audio_info["artist"])
    if not album and audio_info.get("album"):
        album = str(audio_info["album"])

    if not title:
        emit({"status": "not_found", "path": "", "synced": False, "wordSynced": False, "lines": []})
        return

    track = Path(os.path.expanduser(audio_path))
    fallback_dir = Path(
        os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local" / "share")
    ) / "alis" / "lyrics"
    digest = hashlib.sha1(str(track).encode("utf-8", "replace")).hexdigest()[:12]
    existing_lrc = ""
    for cand_lrc in (track.with_suffix(".lrc"), fallback_dir / f"{track.stem}-{digest}.lrc"):
        if cand_lrc.is_file():
            try:
                existing_lrc = cand_lrc.read_text(encoding="utf-8-sig", errors="replace")
                if existing_lrc:
                    break
            except OSError:
                existing_lrc = ""

    existing_is_synced = bool((existing_lrc and STAMP.search(existing_lrc)) or audio_info.get("embedded_synced"))
    ref_lrc = existing_lrc if (existing_lrc and STAMP.search(existing_lrc)) else (
        str(audio_info.get("embedded_lyrics") or "") if audio_info.get("embedded_synced") else ""
    )

    try:
        if upgrade_only:
            raw_text, is_synced, is_word_synced = fetch_from_netease(
                title, artist, duration, verbatim_only=True, timeout=5.0
            )
            if raw_text and is_word_synced:
                raw_text, ok = align_word_lrc_to_reference(raw_text, ref_lrc)
                if not ok:
                    raw_text, is_word_synced = "", False
            if not (raw_text and is_word_synced):
                raw_text, is_synced, is_word_synced = fetch_from_kugou(
                    title, artist, duration, timeout=5.0
                )
                if raw_text and is_word_synced:
                    raw_text, ok = align_word_lrc_to_reference(raw_text, ref_lrc)
                    if not ok:
                        raw_text, is_word_synced = "", False
            if not (raw_text and is_word_synced) and not existing_is_synced:
                # Track only had unsynced .txt or unsynced embedded lyrics: upgrade
                # to synced line-level/word-level .lrc when online sources find one.
                cand_raw, cand_synced = find_lyrics_raw(
                    title,
                    artist,
                    album,
                    duration,
                    embedded_lyrics=str(audio_info.get("embedded_lyrics") or ""),
                    embedded_synced=bool(audio_info.get("embedded_synced")),
                )
                if cand_raw and cand_synced:
                    raw_text, is_synced = cand_raw, True
                    is_word_synced = bool(INLINE_WORD_STAMP.search(raw_text))
            if not (raw_text and is_synced and (is_word_synced or not existing_is_synced)):
                emit({"status": "not_found", "path": "", "synced": False, "wordSynced": False, "lines": []})
                return
        else:
            raw_text, is_synced = find_lyrics_raw(
                title,
                artist,
                album,
                duration,
                embedded_lyrics=str(audio_info.get("embedded_lyrics") or ""),
                embedded_synced=bool(audio_info.get("embedded_synced")),
            )
    except Exception as exc:
        emit({"status": "error", "message": str(exc), "path": "", "synced": False, "wordSynced": False, "lines": []})
        return

    if not raw_text:
        emit({"status": "not_found", "path": "", "synced": False, "wordSynced": False, "lines": []})
        return

    if is_synced:
        lines = parse_lrc(raw_text, key_name="time")
    else:
        lines = parse_plain(raw_text, duration=duration, key_name="time")

    if not lines:
        emit({"status": "not_found", "path": "", "synced": False, "wordSynced": False, "lines": []})
        return

    saved_path = save_lrc_for_local_track(audio_path, raw_text, is_synced)
    emit({
        "status": "ok",
        "path": saved_path,
        "synced": is_synced,
        "wordSynced": bool(INLINE_WORD_STAMP.search(raw_text)),
        "lines": lines,
    })


def main() -> None:
    args = sys.argv[1:]
    if args and args[0] in ("--save-lrc", "--upgrade-word-sync"):
        run_save_lrc_mode(args[1:], upgrade_only=(args[0] == "--upgrade-word-sync"))
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
        {
            "status": "ok",
            "synced": is_synced,
            "wordSynced": bool(INLINE_WORD_STAMP.search(raw_text)),
            "lines": lines,
        }
        if lines
        else {"status": "not_found"},
        request_id,
    )


if __name__ == "__main__":
    main()
