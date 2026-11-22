#!/usr/bin/env python3
"""Unit tests for the PipeWire microphone RMS/peak-hold helper."""
from __future__ import annotations

import importlib.util
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "audio" / "mic-level-meter.py"

spec = importlib.util.spec_from_file_location("mic_level_meter", MODULE_PATH)
assert spec is not None and spec.loader is not None
mic_meter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mic_meter)


def main() -> None:
    # 1. Empty / silence returns (0.0, 0.0)
    assert mic_meter.compute_chunk_metrics([]) == (0.0, 0.0)
    assert mic_meter.compute_chunk_metrics([0] * 512) == (0.0, 0.0)

    state = mic_meter.MicMeterState()
    assert state.step([0] * 512, 1.0 / 30.0) == (0.0, 0.0)

    # 2. Speech-range PCM produces monotonic dB-scaled level & peak
    low_level, low_peak = mic_meter.compute_chunk_metrics([400, -400] * 256)
    mid_level, mid_peak = mic_meter.compute_chunk_metrics([3200, -3200] * 256)
    loud_level, loud_peak = mic_meter.compute_chunk_metrics([16000, -16000] * 256)
    assert 0.0 < low_level < mid_level < loud_level < 1.0
    assert 0.0 < low_peak < mid_peak < loud_peak < 1.0

    # 3. Full-scale clipping reaches 1.0
    clip_level, clip_peak = mic_meter.compute_chunk_metrics([-32768, -32768] * 256)
    assert clip_level == 1.0
    assert clip_peak == 1.0
    near_clip_level, near_clip_peak = mic_meter.compute_chunk_metrics([32767, -32768] * 256)
    assert near_clip_level > 0.999
    assert near_clip_peak == 1.0

    # 4. Peak hold stays elevated across frames within hold_seconds, then smoothly decays
    state = mic_meter.MicMeterState(hold_seconds=0.30, decay_per_second=0.50)
    dt = 0.05
    level_burst, peak_burst = state.step([16384, -16384] * 256, dt)
    assert level_burst > 0.5 and peak_burst > 0.8

    # Still within 0.30s hold window (5 * 0.05 = 0.25s < 0.30s)
    held_peaks = []
    for _ in range(5):
        _, pk = state.step([0] * 512, dt)
        held_peaks.append(pk)
    assert all(abs(pk - peak_burst) < 1e-9 for pk in held_peaks), (
        f"Peak decayed prematurely during hold window: {held_peaks} vs {peak_burst}"
    )

    # Past hold window: step once to expire remaining 0.05s, then verify smooth decay
    decayed_peaks = []
    for _ in range(8):
        _, pk = state.step([0] * 512, dt)
        decayed_peaks.append(pk)
    assert decayed_peaks[1] < peak_burst
    assert decayed_peaks[-1] < decayed_peaks[1]
    for _ in range(40):
        lvl, pk = state.step([0] * 512, dt)
    assert lvl == 0.0 and pk == 0.0

    # 5. build_capture_command uses "alis-mic-meter" identity and sets PIPEWIRE_PROPS safely
    with mock.patch.object(
        mic_meter.shutil,
        "which",
        side_effect=lambda name: f"/usr/bin/{name}" if name == "pw-cat" else None,
    ):
        cmd, env = mic_meter.build_capture_command(16000, env={})
        assert cmd[0] == "pw-cat"
        assert "alis-mic-meter" in " ".join(cmd)
        assert env.get("PIPEWIRE_PROPS") == "{ node.latency = null }"

        _, preserved_props = mic_meter.build_capture_command(
            16000, env={"PIPEWIRE_PROPS": "{ node.latency = 256/48000 }"}
        )
        assert preserved_props["PIPEWIRE_PROPS"] == "{ node.latency = 256/48000 }"

        _, preserved_latency = mic_meter.build_capture_command(
            16000, env={"PIPEWIRE_LATENCY": "128/48000"}
        )
        assert "PIPEWIRE_PROPS" not in preserved_latency

    with mock.patch.object(
        mic_meter.shutil,
        "which",
        side_effect=lambda name: f"/usr/bin/{name}" if name == "parec" else None,
    ):
        cmd, _ = mic_meter.build_capture_command(16000, env={})
        assert cmd[0] == "parec"
        assert "--client-name=alis-mic-meter" in cmd
        assert "--stream-name=alis-mic-meter" in cmd

    print("mic-level-meter unit tests: ok")


if __name__ == "__main__":
    main()
