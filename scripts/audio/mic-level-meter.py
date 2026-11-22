#!/usr/bin/env python3
"""Live PipeWire microphone RMS/peak level meter for Alis Quick Actions."""
from __future__ import annotations

import argparse
import array
import math
import os
import shutil
import signal
import subprocess
import sys
from typing import Mapping, Sequence

DEFAULT_RATE = 16000
DEFAULT_FPS = 30
DEFAULT_FLOOR_DB = -54.0


def amplitude_to_norm(amp: float, floor_db: float = DEFAULT_FLOOR_DB) -> float:
    """Map linear normalized amplitude [0, 1] to perceptually uniform dB [0, 1]."""
    if amp <= 1e-6 or floor_db >= 0.0:
        return 0.0
    db = 20.0 * math.log10(amp)
    if db <= floor_db:
        return 0.0
    norm = (db - floor_db) / (-floor_db)
    return max(0.0, min(1.0, norm))


def compute_chunk_metrics(
    samples: Sequence[int], floor_db: float = DEFAULT_FLOOR_DB
) -> tuple[float, float]:
    """Return (instant_level, instant_peak) in [0, 1] for signed 16-bit PCM samples."""
    count = len(samples)
    if count == 0:
        return (0.0, 0.0)

    sample_peak = max(abs(min(samples)), abs(max(samples))) / 32768.0
    sum_sq = 0
    for s in samples:
        sum_sq += s * s
    rms = math.sqrt(sum_sq / count) / 32768.0

    rms_norm = amplitude_to_norm(rms, floor_db)
    peak_norm = amplitude_to_norm(sample_peak, floor_db)
    level_norm = min(1.0, 0.70 * rms_norm + 0.30 * peak_norm)
    return (level_norm, peak_norm)


class MicMeterState:
    """Asymmetric RMS level follower with peak-hold and linear decay."""

    def __init__(
        self,
        hold_seconds: float = 0.55,
        decay_per_second: float = 0.55,
        attack_alpha: float = 0.65,
        release_alpha: float = 0.24,
        floor_db: float = DEFAULT_FLOOR_DB,
    ) -> None:
        self.hold_seconds = hold_seconds
        self.decay_per_second = decay_per_second
        self.attack_alpha = attack_alpha
        self.release_alpha = release_alpha
        self.floor_db = floor_db
        self.level: float = 0.0
        self.peak: float = 0.0
        self._hold_remaining: float = 0.0

    def step(self, samples: Sequence[int], dt: float) -> tuple[float, float]:
        dt = max(0.0, float(dt))
        instant_level, instant_peak = compute_chunk_metrics(samples, self.floor_db)

        alpha = self.attack_alpha if instant_level >= self.level else self.release_alpha
        self.level = self.level + alpha * (instant_level - self.level)
        if self.level < 0.005:
            self.level = 0.0

        candidate_peak = max(instant_peak, self.level)
        if candidate_peak >= self.peak:
            self.peak = min(1.0, candidate_peak)
            self._hold_remaining = self.hold_seconds
        else:
            self._hold_remaining = max(0.0, self._hold_remaining - dt)
            if self._hold_remaining <= 0.0:
                self.peak = max(self.level, self.peak - self.decay_per_second * dt)
            if self.peak < 0.005:
                self.peak = 0.0

        return (self.level, self.peak)


def build_capture_command(
    rate: int, env: Mapping[str, str] | None = None
) -> tuple[list[str], dict[str, str]]:
    """Build capture argv and child environment without perturbing PipeWire quantum."""
    child_env = dict(os.environ if env is None else env)
    if shutil.which("pw-cat"):
        if "PIPEWIRE_PROPS" not in child_env and "PIPEWIRE_LATENCY" not in child_env:
            child_env["PIPEWIRE_PROPS"] = "{ node.latency = null }"
        cmd = [
            "pw-cat",
            "--record",
            "--raw",
            "--rate",
            str(rate),
            "--channels",
            "1",
            "--format",
            "s16",
            "-P",
            '{ node.name = "alis-mic-meter" application.name = "alis-mic-meter" media.name = "Alis Mic Meter" }',
            "-",
        ]
        return (cmd, child_env)

    if shutil.which("parec"):
        cmd = [
            "parec",
            "--record",
            "--raw",
            "--device=@DEFAULT_SOURCE@",
            f"--rate={rate}",
            "--channels=1",
            "--format=s16le",
            "--client-name=alis-mic-meter",
            "--stream-name=alis-mic-meter",
        ]
        return (cmd, child_env)

    raise RuntimeError("Neither pw-cat nor parec is available")


def _terminate_process(proc: subprocess.Popen[bytes] | None) -> None:
    if proc is None:
        return
    if proc.poll() is None:
        try:
            proc.terminate()
            proc.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=1.0)
        except OSError:
            pass
    else:
        try:
            proc.wait(timeout=0.1)
        except (OSError, subprocess.TimeoutExpired):
            pass


def run_meter(rate: int, fps: int, floor_db: float) -> int:
    rate = max(8000, min(96000, int(rate)))
    fps = max(10, min(60, int(fps)))
    chunk_samples = max(160, round(rate / fps))
    chunk_bytes = chunk_samples * 2
    dt = chunk_samples / float(rate)

    cmd, child_env = build_capture_command(rate)
    state = MicMeterState(floor_db=floor_db)
    stop_requested = False
    proc: subprocess.Popen[bytes] | None = None

    def _handle_signal(_signum: int, _frame: object) -> None:
        nonlocal stop_requested
        stop_requested = True
        if proc is not None and proc.poll() is None:
            try:
                proc.terminate()
            except OSError:
                pass

    signal.signal(signal.SIGTERM, _handle_signal)
    signal.signal(signal.SIGINT, _handle_signal)

    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=child_env,
        )
        assert proc.stdout is not None

        while not stop_requested:
            buf = bytearray()
            while len(buf) < chunk_bytes and not stop_requested:
                piece = proc.stdout.read(chunk_bytes - len(buf))
                if not piece:
                    break
                buf.extend(piece)

            if len(buf) < chunk_bytes:
                break

            arr = array.array("h")
            arr.frombytes(buf)
            if sys.byteorder != "little":
                arr.byteswap()

            level, peak = state.step(arr, dt)
            try:
                sys.stdout.write(f"{level:.3f} {peak:.3f}\n")
                sys.stdout.flush()
            except BrokenPipeError:
                try:
                    devnull = os.open(os.devnull, os.O_WRONLY)
                    os.dup2(devnull, sys.stdout.fileno())
                    os.close(devnull)
                except OSError:
                    pass
                break
    finally:
        if proc is not None and proc.stdout is not None:
            try:
                proc.stdout.close()
            except OSError:
                pass
        _terminate_process(proc)

    if stop_requested:
        return 0
    return 0 if (proc is not None and (proc.returncode or 0) == 0) else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Live PipeWire microphone level meter")
    parser.add_argument("--rate", type=int, default=DEFAULT_RATE)
    parser.add_argument("--fps", type=int, default=DEFAULT_FPS)
    parser.add_argument("--floor-db", type=float, default=DEFAULT_FLOOR_DB)
    args = parser.parse_args()
    try:
        return run_meter(args.rate, args.fps, args.floor_db)
    except RuntimeError as exc:
        sys.stderr.write(f"{exc}\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
