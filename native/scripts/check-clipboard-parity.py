#!/usr/bin/env python3
"""Deterministic Python/Rust clipboard filter parity corpus.

All samples are passed on stdin with --filter; cliphist is never invoked and no
real clipboard selection/history is read or mutated.
"""

from __future__ import annotations

from pathlib import Path
import subprocess
import sys

REPO = Path(__file__).resolve().parents[2]
PYTHON_FILTER = REPO / "scripts" / "clipboard-store.py"

CASES: list[tuple[str, bytes]] = [
    ("plain-trailing-newline", "hello π 世界\n".encode()),
    ("plain-literal-html", b"source <div>must stay literal</div>\n"),
    ("plain-nul", b"alpha\x00beta\n"),
    (
        "firefox-blocks",
        b'<meta http-equiv="content-type" content="text/html; charset=utf-8">'
        b"<div>Hello&nbsp;Hadalis</div><div>Rust<br>Next</div>",
    ),
    (
        "chromium-fragment",
        b"<!--StartFragment--><p>One<br>Two</p>"
        b"<style>.bad{display:none}</style><script>bad()</script>"
        b"<blockquote>Three &amp; Four</blockquote><!--EndFragment-->",
    ),
    (
        "image-only",
        b'<!--StartFragment--><img alt="x" src="https://example.test/a.png">'
        b"<!--EndFragment-->",
    ),
    (
        "entities-unicode",
        '<meta http-equiv="content-type" content="text/html; charset=utf-8">'
        "<div>&lt;tag&gt; &amp; &#x1F642; café</div>".encode(),
    ),
    (
        "lossy-invalid-utf8",
        b'<meta http-equiv="content-type" content="text/html; charset=utf-8">'
        b"<div>A\xffB</div>",
    ),
    (
        "empty-after-sanitize",
        b"<!--StartFragment--><script>only()</script><!--EndFragment-->",
    ),
]

# Exercise payload sizes large enough to reveal accidental quadratic behavior or
# truncation while staying cheap enough for every hosted/local qualification.
CASES.extend(
    [
        (
            "large-plain-unicode",
            ("Hadalis clipboard 🙂 世界 — line\n" * 16384).encode(),
        ),
        (
            "large-browser-html",
            (
                '<meta http-equiv="content-type" content="text/html; charset=utf-8">'
                + "<div>Hadalis&nbsp;🙂 &amp; 世界<br>Rust</div>" * 4096
            ).encode(),
        ),
    ]
)


def run(argv: list[str], payload: bytes) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(argv, input=payload, capture_output=True)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check-clipboard-parity.py /path/to/alis-native", file=sys.stderr)
        return 64
    rust = Path(sys.argv[1]).resolve()
    if not rust.is_file():
        print(f"Rust binary not found: {rust}", file=sys.stderr)
        return 2

    for name, payload in CASES:
        py = run([sys.executable, str(PYTHON_FILTER), "--filter"], payload)
        rs = run([str(rust), "clipboard-filter", "--filter"], payload)
        if py.returncode != rs.returncode or py.stdout != rs.stdout:
            print(f"FAIL clipboard corpus: {name}", file=sys.stderr)
            print(f"python rc={py.returncode} stdout={py.stdout!r}", file=sys.stderr)
            print(f"rust   rc={rs.returncode} stdout={rs.stdout!r}", file=sys.stderr)
            return 1
        print(f"PASS clipboard corpus: {name}")

    print("PASS: clipboard corpus parity is stdin-only and non-destructive")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
