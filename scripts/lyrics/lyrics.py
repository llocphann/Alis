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
INLINE_WORD_STAMP = re.compile(r"<(\d{1,3}):(\d{2}(?:[.:]\d{1,3})?)>")
YRC_LINE_RE = re.compile(r"^\[(\d+),(\d+)\](.+)$")
YRC_WORD_RE = re.compile(r"\((\d+),(\d+),\d+\)([^\(]*)")
KLYRIC_LINE_RE = re.compile(r"^\[(\d+),(\d+)\](.+)$")
KLYRIC_WORD_RE = re.compile(r"<(\d+),(\d+),\d+>([^<]*)")
OFFSET_RE = re.compile(r"^\s*\[offset\s*:\s*([+-]?\d+)\s*\]\s*$", re.IGNORECASE)
METADATA_RE = re.compile(r"^\s*\[[a-z]{2,8}\s*:.*\]\s*$", re.IGNORECASE)
CREDIT_LINE_RE = re.compile(
    r"^\s*(?:(?:作词|作曲|编曲|制作人|混音|母带|录音|统筹|出品|发行|监制|和声|吉他|贝斯|鼓|弦乐|词|曲|プロデューサー|作詞|作曲|編曲|Lyrics\s*by|Composed\s*by|Produced\s*by|Arranged\s*by)\s*[:：]|\[(?:Verse|Chorus|Hook|Bridge|Intro|Outro|Pre-Chorus|Interlude|Instrumental|Solo|Guitar\s*Solo)[^\]]*\]\s*$)",
    re.IGNORECASE,
)


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

NOISE_PATTERNS = [
    r"\(\s*(?:official|lyric|lyrics|music|audio|video|mv|visualizer|live|remaster(?:ed)?|hd|4k|hq)[^)]*\)",
    r"\[\s*(?:official|lyric|lyrics|music|audio|video|mv|visualizer|live|remaster(?:ed)?|hd|4k|hq)[^\]]*\]",
    r"\(\s*(?:feat\.?|ft\.?|prod\.?)[^)]*\)",
    r"\[\s*(?:feat\.?|ft\.?|prod\.?)[^\]]*\]",
    r"\b(?:official\s+(?:music\s+)?video|official\s+audio|lyric\s+video|lyrics\s+video|m/v|mv)\b",
]
ARTIST_NOISE_RE = re.compile(r"\s*-\s*topic$|\bvevo$", re.IGNORECASE)

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
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()


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
        if not full_line_text or CREDIT_LINE_RE.match(full_line_text):
            continue

        parts: list[str] = [format_lrc_Time(line_start_ms / 1000.0, inline=False)]
        last_end = (line_start_ms + line_dur_ms) / 1000.0
        for w_start, w_end, piece in grouped:
            clean_piece = piece.strip()
            if not clean_piece:
                continue
            parts.append(f"{format_lrc_Time(w_start, inline=True)}{clean_piece} ")
            last_end = max(last_end, w_end)
        parts.append(format_lrc_Time(last_end, inline=True))
        out_lines.append("".join(parts).strip())
    return "\n".join(out_lines)


def convert_netease_klyric_to_enhanced_lrc(klyric_text: str) -> str:
    """Convert NetEase klyric format into Enhanced LRC with <mm:ss.xxx> word tags."""
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
        parts: list[str] = [format_lrc_Time(line_start_ms / 1000.0, inline=False)]
        last_end = (line_start_ms + line_dur_ms) / 1000.0
        for tok in tokens:
            rel_start_ms = int(tok.group(1))
            w_dur_ms = max(20, int(tok.group(2)))
            piece = tok.group(3).strip()
            if not piece:
                continue
            w_start = (line_start_ms + rel_start_ms) / 1000.0
            w_end = w_start + w_dur_ms / 1000.0
            parts.append(f"{format_lrc_Time(w_start, inline=True)}{piece} ")
            last_end = max(last_end, w_end)
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
        next_t = timed_segments[idx + 1][0] if idx + 1 < len(timed_segments) else line_end
        if next_t <= seg_t:
            next_t = max(seg_t + 0.18, line_end if idx + 1 == len(timed_segments) else seg_t + 0.28)
        sub_words = seg_text.split()
        if len(sub_words) == 1:
            raw_words.append((seg_t, next_t, sub_words[0]))
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
        if clean_lyric and CREDIT_LINE_RE.match(clean_lyric):
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
        # Active singing window within the inter-line gap
        vocal_window = min(max(0.35, gap - 0.06), max(1.4, min(8.5, gap * 0.92)))
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
        if line.strip() and not METADATA_RE.match(line)
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

    synced_text = str(candidate.get("syncedLyrics") or "")
    if synced_text:
        score += 30.0
        if INLINE_WORD_STAMP.search(synced_text):
            score += 25.0
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
    query = f"{c_title} {c_artist}".strip()
    if not query:
        return "", False, False

    form = urllib.parse.urlencode({"s": query, "type": 1, "offset": 0, "limit": 6}).encode("utf-8")
    headers = {
        "Referer": "https://music.163.com",
        "Content-Type": "application/x-www-form-urlencoded",
    }
    try:
        search_data = get_json(NETEASE_SEARCH_API, data=form, extra_headers=headers, timeout=timeout)
    except Exception:
        return "", False, False

    songs = ((search_data or {}).get("result") or {}).get("songs") or []
    if not isinstance(songs, list):
        return "", False, False

    best_line_lrc = ""

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
            lyric_url = f"{NETEASE_LYRIC_API}?id={int(song_id)}&yv=1&lv=1&kv=1&tv=-1"
            lyric_data = get_json(
                lyric_url,
                extra_headers={"Referer": "https://music.163.com"},
                timeout=timeout,
            )
        except Exception:
            continue

        # 1. Prefer NetEase YRC verbatim word-synced lyrics
        yrc_raw = (((lyric_data or {}).get("yrc") or {}).get("lyric") or "").strip()
        if yrc_raw:
            enhanced = convert_netease_yrc_to_enhanced_lrc(yrc_raw)
            if enhanced and parse_lrc(enhanced):
                return enhanced, True, True

        # 2. Check NetEase klyric word-synced format
        klyric_raw = (((lyric_data or {}).get("klyric") or {}).get("lyric") or "").strip()
        if klyric_raw:
            enhanced = convert_netease_klyric_to_enhanced_lrc(klyric_raw)
            if enhanced and parse_lrc(enhanced):
                return enhanced, True, True

        if not verbatim_only and not best_line_lrc:
            lrc_text = (((lyric_data or {}).get("lrc") or {}).get("lyric") or "").strip()
            if lrc_text and parse_lrc(lrc_text):
                best_line_lrc = lrc_text
                break

    if best_line_lrc:
        return best_line_lrc, True, bool(INLINE_WORD_STAMP.search(best_line_lrc))

    return "", False, False


def find_lyrics_raw(title: str, artist: str, album: str, duration: float | None) -> tuple[str, bool]:
    last_error: Exception | None = None
    try:
        raw_text, is_synced = fetch_from_lrclib(title, artist, album, duration)
    except Exception as exc:
        last_error = exc
        raw_text, is_synced = "", False

    # If LRCLIB already returned word-level Enhanced LRC (<mm:ss.xx>), use it immediately
    if raw_text and is_synced and INLINE_WORD_STAMP.search(raw_text):
        return raw_text, True

    # Try NetEase to see if verbatim word-level (YRC/klyric) or fallback synced LRC is available
    netease_timeout = 3.5 if (raw_text and is_synced) else TIMEOUT
    synced_netease, netease_is_synced, netease_word_synced = fetch_from_netease(
        title,
        artist,
        duration,
        verbatim_only=bool(raw_text and is_synced),
        timeout=netease_timeout,
    )
    if synced_netease and netease_word_synced:
        return synced_netease, True

    if raw_text and is_synced:
        return raw_text, True

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


def run_save_lrc_mode(args: list[str], upgrade_only: bool = False) -> None:
    audio_path = args[0].strip() if len(args) > 0 else ""
    title = args[1].strip() if len(args) > 1 else ""
    artist = args[2].strip() if len(args) > 2 else ""
    duration_str = args[3].strip() if len(args) > 3 else ""
    album = args[4].strip() if len(args) > 4 else ""

    if not audio_path or not title:
        emit({"status": "not_found", "path": "", "synced": False, "wordSynced": False, "lines": []})
        return

    try:
        duration = float(duration_str) if duration_str else None
    except ValueError:
        duration = None

    try:
        if upgrade_only:
            raw_text, is_synced, is_word_synced = fetch_from_netease(
                title, artist, duration, verbatim_only=True, timeout=5.0
            )
            if not (raw_text and is_word_synced):
                emit({"status": "not_found", "path": "", "synced": False, "wordSynced": False, "lines": []})
                return
        else:
            raw_text, is_synced = find_lyrics_raw(title, artist, album, duration)
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
