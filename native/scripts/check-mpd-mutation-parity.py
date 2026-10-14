#!/usr/bin/env python3
"""Stateful isolated parity checks for MPD status and mutating commands.

The script starts a tiny MPD-protocol server on loopback for each case and runs
both the Python fallback and Rust compatibility CLI against independent copies.
The status fixture covers current/queue metadata serialization exactly. No real
MPD database, queue, playback state, or stored playlist is touched.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shlex
import socket
import subprocess
import sys
import tempfile
import threading
from typing import Any

REPO = Path(__file__).resolve().parents[2]
PYTHON = REPO / "scripts" / "local_music_mpd.py"


class FakeMpd:
    def __init__(self, reject_bad_seek: bool = False, status_fixture: bool = False):
        self.reject_bad_seek = reject_bad_seek
        self.status_fixture = status_fixture
        self.queue: list[str] = (
            [
                "Fixture Artist/Fixture Album/01 - Alpha.flac",
                "Fixture Artist/Fixture Album/02 - Beta.flac",
            ]
            if status_fixture
            else []
        )
        self.playlists: dict[str, list[str]] = {}
        self.state = "stop"
        self.song = 0
        self.elapsed = 0.0
        self.commands: list[str] = []
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(1)
        self.port = self.listener.getsockname()[1]
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.error: BaseException | None = None

    def start(self) -> None:
        self.thread.start()

    def finish(self) -> dict[str, Any]:
        self.thread.join(timeout=3)
        self.listener.close()
        if self.thread.is_alive():
            raise AssertionError("fake MPD server did not stop")
        if self.error is not None:
            raise self.error
        return {
            "queue": self.queue,
            "playlists": self.playlists,
            "state": self.state,
            "song": self.song,
            "elapsed": self.elapsed,
        }

    def _track_lines(self, uri: str, position: int) -> list[str]:
        title = "Alpha" if position == 0 else "Beta"
        return [
            f"file: {uri}",
            "Last-Modified: 2026-01-02T03:04:05Z",
            "Artist: Fixture Artist",
            "AlbumArtist: Fixture Album Artist",
            "Album: Fixture Album",
            f"Title: {title}",
            f"Track: {position + 1}/2",
            "Disc: 1/1",
            "Genre: Fixture Genre",
            "Date: 2026",
            "duration: 123.456",
            f"Pos: {position}",
            f"Id: {101 + position}",
        ]

    def _reply_for(self, command: str) -> tuple[bool, list[str]]:
        self.commands.append(command)
        parts = shlex.split(command)
        if not parts:
            return True, []
        name, args = parts[0], parts[1:]
        if self.status_fixture and name == "config":
            return True, ["music_directory: /music"]
        if self.status_fixture and name == "status":
            return True, [
                "volume: 72",
                "repeat: 0",
                "random: 0",
                "single: 0",
                "consume: 0",
                "playlist: 42",
                f"playlistlength: {len(self.queue)}",
                "state: play",
                f"song: {self.song}",
                f"songid: {101 + self.song}",
                "elapsed: 12.345",
                "duration: 123.456",
                "bitrate: 921",
                "audio: 44100:24:2",
            ]
        if self.status_fixture and name == "currentsong":
            if not self.queue:
                return True, []
            return True, self._track_lines(self.queue[self.song], self.song)
        if self.status_fixture and name == "playlistinfo":
            lines: list[str] = []
            for position, uri in enumerate(self.queue):
                lines.extend(self._track_lines(uri, position))
            return True, lines
        if name == "clear":
            self.queue.clear()
            self.song = 0
        elif name == "add":
            self.queue.append(args[0])
        elif name == "play":
            if args:
                self.song = int(args[0])
            self.state = "play"
        elif name == "pause":
            self.state = "pause" if not args or args[0] != "0" else "play"
        elif name == "seekcur":
            if self.reject_bad_seek and args and args[0] == "bad":
                return False, ["ACK [2@0] {seekcur} bad time"]
            self.elapsed = float(args[0])
        elif name == "playlistadd":
            self.playlists.setdefault(args[0], []).append(args[1])
        elif name == "listplaylists":
            return True, [f"playlist: {key}" for key in self.playlists]
        else:
            raise AssertionError(f"unexpected fake MPD command: {command}")
        return True, []

    def _serve(self) -> None:
        try:
            conn, _ = self.listener.accept()
            with conn, conn.makefile("rwb", buffering=0) as stream:
                stream.write(b"OK MPD 0.23.15\n")
                while True:
                    raw = stream.readline()
                    if not raw:
                        break
                    line = raw.decode().rstrip("\r\n")
                    if line == "command_list_begin":
                        batch: list[str] = []
                        while True:
                            raw = stream.readline()
                            if not raw:
                                raise AssertionError("truncated MPD command list")
                            item = raw.decode().rstrip("\r\n")
                            if item == "command_list_end":
                                break
                            batch.append(item)
                        for item in batch:
                            ok, response = self._reply_for(item)
                            if not ok:
                                stream.write((response[0] + "\n").encode())
                                break
                        else:
                            stream.write(b"OK\n")
                        continue

                    ok, response = self._reply_for(line)
                    for item in response:
                        stream.write((item + "\n").encode())
                    if ok:
                        stream.write(b"OK\n")
        except BaseException as error:
            self.error = error


def run_backend(
    kind: str,
    rust_binary: Path,
    mode: str,
    tail: list[str],
    reject_bad_seek=False,
    status_fixture=False,
):
    server = FakeMpd(
        reject_bad_seek=reject_bad_seek,
        status_fixture=status_fixture,
    )
    server.start()
    common = [mode, "127.0.0.1", str(server.port), *tail]
    argv = (
        [sys.executable, str(PYTHON), *common]
        if kind == "python"
        else [str(rust_binary), "--compat", *common]
    )
    with tempfile.TemporaryDirectory(prefix="hadalis-mpd-parity-cache.") as cache:
        result = subprocess.run(
            argv,
            text=True,
            capture_output=True,
            env={**os.environ, "XDG_CACHE_HOME": cache},
        )
    state = server.finish()
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise AssertionError(
            f"{kind} {mode} returned non-JSON stdout {result.stdout!r}; stderr={result.stderr!r}"
        ) from error
    return result.returncode, payload, state, server.commands


def check_case(
    rust_binary: Path,
    label: str,
    mode: str,
    tail: list[str],
    reject_bad_seek=False,
    status_fixture=False,
):
    py = run_backend(
        "python", rust_binary, mode, tail, reject_bad_seek, status_fixture
    )
    rs = run_backend(
        "rust", rust_binary, mode, tail, reject_bad_seek, status_fixture
    )
    if py[:3] != rs[:3]:
        raise AssertionError(
            f"{label} parity mismatch\n"
            f"python rc/json/state={py[:3]!r}\n"
            f"rust   rc/json/state={rs[:3]!r}\n"
            f"python commands={py[3]!r}\nrust commands={rs[3]!r}"
        )
    print(f"PASS MPD isolated: {label}")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check-mpd-mutation-parity.py /path/to/alis-mpdd", file=sys.stderr)
        return 64
    rust_binary = Path(sys.argv[1]).resolve()
    if not rust_binary.is_file():
        print(f"Rust binary not found: {rust_binary}", file=sys.stderr)
        return 2

    check_case(
        rust_binary,
        "status/current/queue serialization",
        "status",
        [""],
        status_fixture=True,
    )
    check_case(
        rust_binary,
        "queue replace + play index",
        "queue",
        ["1", '["z.flac","a.flac","z.flac"]'],
    )
    check_case(
        rust_binary,
        "playlist order/trim/stable dedup",
        "playlist-add",
        [" Mix ", '[" z.flac ","a.flac","z.flac"," b.flac "]'],
    )
    check_case(rust_binary, "playback play", "command", ["play", "[]"])
    check_case(rust_binary, "playback pause", "command", ["pause", '["1"]'])
    check_case(rust_binary, "seek", "command", ["seekcur", '["42.5"]'])
    check_case(
        rust_binary,
        "ACK error propagation",
        "command",
        ["seekcur", '["bad"]'],
        reject_bad_seek=True,
    )

    print("PASS: MPD status/mutation parity uses isolated loopback services only")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
