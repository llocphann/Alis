#!/usr/bin/env python3
"""Read local sidecar lyrics for the Hadalis MPD Music tab (with word-level timing & prosody)."""
from __future__ import annotations
import hashlib
import json
import os
import re
import sys
from pathlib import Path

STAMP_RE = re.compile(r"\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]")
INLINE_WORD_STAMP_RE = re.compile(r"<(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?>")
OFFSET_RE = re.compile(r"^\[offset:([+-]?\d+)\]$", re.IGNORECASE)
META_RE = re.compile(r"^\[(?:ar|al|ti|by|re|ve|length):", re.IGNORECASE)
CREDIT_LINE_RE = re.compile(
    r"^\s*(?:(?:作词|作曲|编曲|制作人|混音|母带|录音|统筹|出品|发行|监制|和声|吉他|贝斯|鼓|弦乐|词|曲|プロデューサー|作詞|作曲|編曲|Lyrics\s*by|Composed\s*by|Produced\s*by|Arranged\s*by)\s*[:：]|\[(?:Verse|Chorus|Hook|Bridge|Intro|Outro|Pre-Chorus|Interlude|Instrumental|Solo|Guitar\s*Solo)[^\]]*\]\s*$)",
    re.IGNORECASE,
)

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


def prosodic_word_weight(word: str, index: int, total: int) -> tuple[float, float]:
    stripped = word.strip()
    core = re.sub(r"^[^\w]+|[^\w]+$", "", stripped)
    char_len = max(1, len(core))
    weight = max(0.75, char_len ** 0.72)

    lower = core.lower()
    if lower in {"a", "an", "the", "to", "in", "on", "of", "at", "is", "it", "và", "là", "của", "cho", "với", "như"}:
        weight *= 0.72

    if REPEAT_VOWEL_RE.search(core) or REPEAT_SONORANT_RE.search(core) or "~" in stripped:
        weight += 1.55
    elif LONG_DIPHTHONG_RE.search(core):
        weight += 0.42

    if lower in VIBRATO_VOCAL_SET:
        weight += 0.85

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
) -> dict[str, object]:
    duration = max(0.04, end - start)
    stripped = word_text.strip()
    core = re.sub(r"^[^\w]+|[^\w]+$", "", stripped)
    lower = core.lower()
    rel_dur = duration / max(0.16, avg_duration)

    vibrato = 0.0
    sustain = 0.0
    rise = 0.0
    fall = 0.0

    if "~" in stripped or "…" in stripped or ".." in stripped:
        vibrato = 1.0
    elif REPEAT_VOWEL_RE.search(core) or REPEAT_SONORANT_RE.search(core):
        vibrato = 0.95
    elif lower in VIBRATO_VOCAL_SET:
        vibrato = 0.90
    elif duration >= 0.72 and OPEN_TAIL_RE.search(core):
        vibrato = min(0.88, 0.45 + (duration - 0.60) * 0.75)

    if duration >= 0.48 or rel_dur >= 1.32:
        sustain = min(1.0, max((duration - 0.34) / 0.80, (rel_dur - 1.10) / 1.05))
    if index == total - 1 and duration >= 0.40:
        sustain = max(sustain, min(0.95, duration / 0.82))
    if LONG_DIPHTHONG_RE.search(core) and duration >= 0.36:
        sustain = max(sustain, 0.58)

    if stripped.endswith(("!", "?", "?!", "!?")):
        rise = 0.95
    elif len(core) >= 2 and core.isupper():
        rise = 0.90
    if lower in RISE_KEYWORDS:
        rise = max(rise, 0.82)
    if any(ch in VI_RISING_CHARS for ch in lower):
        rise = max(rise, 0.68 if rel_dur >= 1.0 else 0.50)
    pos_ratio = (index + 0.5) / max(1, total)
    if 0.40 <= pos_ratio <= 0.85 and rel_dur >= 1.18 and not any(ch in VI_FALLING_CHARS for ch in lower):
        rise = max(rise, min(0.80, 0.45 + (rel_dur - 1.0) * 0.45))

    if lower in FALL_KEYWORDS:
        fall = 0.82
    if any(ch in VI_FALLING_CHARS for ch in lower) and rise < 0.65:
        fall = max(fall, 0.72 if index >= total - 2 else 0.52)
    if index == total - 1 and stripped.endswith((".", ",", ";", "…", "..")) and not stripped.endswith(("!", "?")):
        fall = max(fall, 0.68)
    elif index == total - 1 and rise < 0.45 and vibrato < 0.55 and sustain < 0.65:
        fall = max(fall, 0.54)

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


def parse_inline_words(raw_lyric: str, line_start: float, line_end: float, offset_sec: float) -> list[dict[str, object]]:
    matches = list(INLINE_WORD_STAMP_RE.finditer(raw_lyric))
    if not matches:
        return []

    timed_segments: list[tuple[float, str]] = []
    prefix = raw_lyric[:matches[0].start()].strip()
    if prefix:
        timed_segments.append((line_start, prefix))

    for idx, m in enumerate(matches):
        stamp_t = max(0.0, round(stamp_seconds(m.group(1), m.group(2), m.group(3)) + offset_sec, 3))
        seg_start = m.end()
        seg_end = matches[idx + 1].start() if idx + 1 < len(matches) else len(raw_lyric)
        seg_text = raw_lyric[seg_start:seg_end].strip()
        timed_segments.append((stamp_t, seg_text))

    raw_words: list[tuple[float, float, str]] = []
    for idx, (seg_t, seg_text) in enumerate(timed_segments):
        if not seg_text:
            continue
        has_explicit_end = idx + 1 < len(timed_segments) and not timed_segments[idx + 1][1]
        next_t = timed_segments[idx + 1][0] if idx + 1 < len(timed_segments) else line_end
        if next_t <= seg_t:
            next_t = max(seg_t + 0.18, line_end if idx + 1 == len(timed_segments) else seg_t + 0.28)
        sub_words = seg_text.split()
        if len(sub_words) == 1:
            w_str = sub_words[0]
            if not has_explicit_end:
                char_count = max(1, len(re.sub(r"[^\w]+", "", w_str)))
                clause_pause = w_str.endswith((",", ";", ":", ".", "?", "!", "…"))
                max_natural = max(0.32, 0.18 + char_count * 0.055) if clause_pause else max(0.55, 0.28 + char_count * 0.075)
                if (next_t - seg_t) > max_natural * 1.35:
                    next_t = seg_t + max_natural
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
    return max(0.95, min(6.2, 0.28 + len(tokens) * 0.24 + chars * 0.036))


def synthesize_prosodic_words(clean_text: str, line_start: float, line_end: float) -> list[dict[str, object]]:
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
        raw_lyric = STAMP_RE.sub("", line).strip()
        clean_lyric = re.sub(r"\s+", " ", INLINE_WORD_STAMP_RE.sub(" ", raw_lyric)).strip()
        if clean_lyric and CREDIT_LINE_RE.match(clean_lyric):
            continue
        if stamps:
            for match in stamps:
                timed.append({
                    "time": stamp_seconds(match.group(1), match.group(2), match.group(3)),
                    "text": clean_lyric or "♪",
                    "_raw_lyric": raw_lyric,
                })
        elif clean_lyric:
            plain.append({"time": -1.0, "text": clean_lyric, "words": []})
    if timed:
        offset = offset_ms / 1000.0
        for item in timed:
            item["time"] = max(0.0, float(item["time"]) + offset)
        timed.sort(key=lambda item: float(item["time"]))
        n_lines = len(timed)
        for i, item in enumerate(timed):
            line_start = float(item["time"])
            next_start = line_start + 4.2
            for j in range(i + 1, n_lines):
                cand_next = float(timed[j]["time"])
                if cand_next > line_start + 0.05:
                    next_start = cand_next
                    break
            gap = max(0.35, next_start - line_start)
            est_max = _estimated_line_vocal_span(str(item["text"])) * 1.15
            vocal_window = min(max(0.35, gap - 0.06), min(est_max, gap * 0.88))
            line_end = round(line_start + vocal_window, 3)
            raw_lyric = str(item.pop("_raw_lyric", ""))
            words = parse_inline_words(raw_lyric, line_start, line_end, offset)
            if words:
                line_end = round(max(line_end, float(words[-1]["end"])), 3)
            else:
                words = synthesize_prosodic_words(str(item["text"]), line_start, line_end)
            item["endTime"] = line_end
            item["words"] = words
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
            return {
                "status": "ok",
                "path": str(path.resolve()),
                "synced": synced,
                "wordSynced": bool(INLINE_WORD_STAMP_RE.search(text)),
                "lines": lines,
            }
    return {"status": "not_found", "path": "", "synced": False, "wordSynced": False, "lines": []}


def main() -> int:
    if len(sys.argv) != 2:
        return 2
    print(json.dumps(load(sys.argv[1]), ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
