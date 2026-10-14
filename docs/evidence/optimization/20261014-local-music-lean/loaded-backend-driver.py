#!/usr/bin/env python3
"""Read-only snapshot parity on a private MPD endpoint, including real RPC.

Optional baselines compare default/full bytes against earlier implementations.
--benchmark records alternating full/lean helper CPU/RSS and stdout bytes; it
does not measure the owner library, entire shell or live desktop performance.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shlex
import socket
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]


def measured_run(cmd, env):
    # wait4 gives per-helper CPU and peak RSS, without an external time utility
    # or cumulative child high-water marks from earlier runs.
    with tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as errors:
        start = time.monotonic()
        proc = subprocess.Popen(cmd, env=env, stdout=output, stderr=errors)
        samples = []
        while True:
            try:
                # Linux wait4 RSS can include the parent's inherited pre-exec
                # high-water mark. Sample only after argv identifies this helper.
                proc_root = Path("/proc") / str(proc.pid)
                actual = proc_root.joinpath("cmdline").read_bytes().rstrip(b"\0").split(b"\0")
                if actual == [os.fsencode(arg) for arg in cmd]:
                    values = dict(line.split(":", 1) for line in proc_root.joinpath("smaps_rollup").read_text().splitlines() if ":" in line)
                    samples.append({key: int(values[key].split()[0]) for key in ["Rss", "Pss"]})
            except (OSError, KeyError, ValueError):
                pass
            pid, status, usage = os.wait4(proc.pid, os.WNOHANG)
            if pid:
                proc.returncode = os.waitstatus_to_exitcode(status)
                break
            if time.monotonic() - start > 90:
                proc.kill()
                _, status, _ = os.wait4(proc.pid, 0)
                proc.returncode = os.waitstatus_to_exitcode(status)
                raise TimeoutError("Private snapshot helper exceeded 90 seconds")
            time.sleep(.002)
        elapsed = time.monotonic() - start
        output.seek(0)
        errors.seek(0)
        return subprocess.CompletedProcess(cmd, proc.returncode, output.read(), errors.read()), {
            "elapsed_seconds": elapsed, "user_seconds": usage.ru_utime,
            "system_seconds": usage.ru_stime, "wait4_max_rss_kib": usage.ru_maxrss,
            "post_exec_samples": len(samples),
            "post_exec_rss_peak_kib": max((value["Rss"] for value in samples), default=0),
            "post_exec_pss_peak_kib": max((value["Pss"] for value in samples), default=0),
        }


class LibraryServer:
    def __init__(self, root: Path, size: int):
        self.root = root
        self.records = []
        for index in range(size):
            folder = f"Album Ω {index // 12:05d}"
            directory = root / folder
            directory.mkdir(exist_ok=True)
            (directory / "cover.png").touch()
            self.records.append([
                f"file: {folder}/{index:05d}.flac", f"Title: Song {index:05d} ♫",
                "Artist: Artist ß", "Artist: Secondary", "AlbumArtist: Artist ß",
                f"Album: {folder}", "Genre: Jazz", "Genre: Fusion", "Date: 2026",
                f"Track: {index % 12 + 1}/12", "Disc: 1/1", "duration: 123.456",
            ])
        self.library = [line for record in self.records for line in record]
        self.playlist = [line for record in self.records[:3] for line in record]
        self.commands = []
        self.errors = []
        self.clients = []
        self.connections = []
        self.stop = threading.Event()
        self.listener = socket.socket()
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(8)
        self.listener.settimeout(.1)
        self.port = self.listener.getsockname()[1]
        self.thread = threading.Thread(target=self.accept, daemon=True)
        self.thread.start()

    def reply(self, command):
        name, *args = shlex.split(command)
        self.commands.append(command)
        if name == "config":
            return ["music_directory: " + str(self.root)]
        if name == "listallinfo":
            return self.library
        if name == "listplaylists":
            return ["playlist: B List", "playlist: a List", "playlist: Broken"]
        if name == "listplaylistinfo":
            return ["ACK [50@0] {listplaylistinfo} Not found"] if args == ["Broken"] else self.playlist
        if name == "status":
            return ["state: pause", "volume: 67", "random: 1", "repeat: 1", "single: 0",
                    f"playlistlength: {min(len(self.records), 3)}", "song: 0", "elapsed: 12.345", "duration: 123.456"]
        if name == "currentsong":
            return self.records[0] if self.records else []
        if name == "playlistinfo":
            return self.playlist
        if name in ("readpicture", "albumart"):
            return ["ACK [50@0] {readpicture} No art"]
        raise AssertionError("Unexpected or mutating MPD command: " + command)

    def serve(self, conn):
        try:
            with conn, conn.makefile("rwb", buffering=0) as stream:
                stream.write(b"OK MPD 0.24.15\n")
                while not self.stop.is_set():
                    raw = stream.readline()
                    if not raw:
                        break
                    command = raw.decode().strip()
                    if command.startswith("idle "):
                        # Only the private daemon owns this pending idle socket.
                        self.stop.wait()
                        break
                    lines = self.reply(command)
                    suffix = "" if lines and lines[-1].startswith("ACK ") else "OK\n"
                    stream.write(("\n".join(lines) + ("\n" if lines else "") + suffix).encode())
        except (BrokenPipeError, ConnectionResetError):
            pass
        except BaseException as error:
            self.errors.append(str(error))

    def accept(self):
        while not self.stop.is_set():
            try:
                conn, _ = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            self.connections.append(conn)
            thread = threading.Thread(target=self.serve, args=(conn,), daemon=True)
            self.clients.append(thread)
            thread.start()

    def close(self):
        self.stop.set()
        self.listener.close()
        for conn in self.connections:
            try:
                conn.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        self.thread.join(timeout=1)
        for thread in self.clients:
            thread.join(timeout=1)
        assert not self.errors, self.errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rust-binary", type=Path, default=ROOT / "native/target/release/alis-mpdd")
    parser.add_argument("--baseline-python", type=Path)
    parser.add_argument("--baseline-rust", type=Path)
    parser.add_argument("--benchmark", action="store_true")
    parser.add_argument("--report-dir", type=Path)
    args = parser.parse_args()
    assert os.access(args.rust_binary, os.X_OK), "Build alis-mpdd first (no backend is silently skipped)"
    rows = []
    checks = 0
    with tempfile.TemporaryDirectory(prefix="alis-lean-mpd-") as name:
        tmp = Path(name)
        env = {**os.environ, **{key: str(tmp / key) for key in
               ("XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_RUNTIME_DIR")}}
        out = args.report_dir or tmp / "report"
        out.mkdir(parents=True, exist_ok=True)
        for size in [0, 1, 15, 96] + ([10000] if args.benchmark else []):
            music = tmp / f"music-{size}"
            music.mkdir()
            server = LibraryServer(music, size)
            sock = tmp / f"daemon-{size}.sock"
            daemon = None

            def run(label, prefix, lean=False, timed=False, suffix=None, legacy=False):
                nonlocal checks
                cmd = [*prefix, "snapshot", "127.0.0.1", str(server.port), str(music)]
                if lean:
                    cmd.append("--lean")
                log = out / f"{size}-{label}{suffix or ''}"
                start = len(server.commands)
                if timed:
                    result, metrics = measured_run(cmd, env)
                else:
                    result = subprocess.run(cmd, env=env, capture_output=True, timeout=90)
                assert result.returncode == 0, (cmd, result.returncode, result.stderr.decode())
                payload = json.loads(result.stdout)
                assert ("folders" not in payload) == (lean and not legacy), (label, lean, payload.keys())
                assert len(payload["tracks"]) == size
                checks += 3
                commands = server.commands[start:]
                if timed:
                    rows.append({"size": size, "label": label, "lean": lean,
                                 "stdout_bytes": len(result.stdout), **metrics})
                return payload, commands, result.stdout

            try:
                py = [sys.executable, str(ROOT / "scripts/local_music_mpd.py")]
                rs = [str(args.rust_binary), "--compat"]
                full = run("python-full", py)
                lean = run("python-lean", py, True)
                assert lean[0] == {k: v for k, v in full[0].items() if k != "folders"}
                assert lean[1] == full[1], "Lean changed external MPD command order"
                rust_full = run("rust-full", rs)
                rust_lean = run("rust-lean", rs, True)
                assert rust_full[0] == full[0], "Default/full backend parity"
                assert rust_lean[0] == lean[0], "Lean backend data parity"
                assert rust_lean[1] == rust_full[1], "Lean changed native MPD command order"
                for label, path, prefix in [("baseline-python", args.baseline_python, [sys.executable]),
                                             ("baseline-rust", args.baseline_rust, [])]:
                    if path:
                        before = run(label, [*prefix, str(path)] + (["--compat"] if not prefix else []))
                        actual = full if prefix else rust_full
                        assert before == actual, "Full snapshot changed vs frozen previous implementation"
                        # Older helpers ignore the trailing hint and still return
                        # the complete compatible payload, so upgrades stay safe.
                        hinted = run(label + "-hinted", [*prefix, str(path)] + (["--compat"] if not prefix else []), True, legacy=True)
                        assert hinted == before
                        checks += 2
                daemon = subprocess.Popen([str(args.rust_binary), "--host", "127.0.0.1", "--port", str(server.port),
                                           "--music-root", str(music), "--socket", str(sock)], env=env,
                                          stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                deadline = time.monotonic() + 5
                while not sock.exists():
                    assert time.monotonic() < deadline and daemon.poll() is None, "Private daemon did not start"
                    time.sleep(.01)
                rpc = [str(args.rust_binary), "--client-compat", "--socket", str(sock)]
                assert run("rpc-full", rpc)[0] == full[0]
                assert run("rpc-lean", rpc, True)[0] == lean[0]
                assert run("rpc-full-again", rpc)[0] == full[0], "Lean request poisoned later full requests"
                checks += 7
                if size == 10000:
                    for round in range(4):
                        order = [False, True] if round % 2 == 0 else [True, False]
                        for label, prefix in [("python", py), ("rust", rs)]:
                            for lean_mode in order:
                                payload = run(label, prefix, lean_mode, True, f"-{round}-{'lean' if lean_mode else 'full'}")
                                expected = (lean if lean_mode else full) if label == "python" else (rust_lean if lean_mode else rust_full)
                                assert payload[:2] == expected[:2]
            finally:
                if daemon:
                    daemon.terminate()
                    daemon.communicate(timeout=5)
                server.close()
        report = {"checks": checks, "scope": "Private synthetic library; no owner MPD, routes, volume, playback or config touched",
                  "measurements": rows}
        (out / "result.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"LEAN_SNAPSHOT_PASS {checks} checks: full/default compatibility, Python/Rust/direct/RPC, identical MPD read commands")


if __name__ == "__main__":
    main()
