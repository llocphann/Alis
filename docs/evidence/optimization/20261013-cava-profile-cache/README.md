# Frequency factor reuse — local Qt evidence

Source: `3dbcf3690e6321ba4efe2fc594ad3960cbab56f4`, tested in a clean detached local clone. Tests exited 0: 4,122,728 exact QV4 numeric/publication/cache checks over 4,536 cases; full component 55,138 checks and 16 strictly identical RGBA image pairs (32 captures) on local Niri/OpenGL. Capture focus was restored; no owner source install or preference change.

The vector is bounded to one current sample count per visualizer, keyed by profile, stereo, count and clamped strength. Published levels retain alternating buffer identity, notification counts and arithmetic. Numeric input includes non-finite samples and configuration transitions. GPU cases exercise bar/fill/line/ribbon, four origins, radius, opacity, profile and stereo.

Six alternating AB/BA pairs per profile, 6,000 calls/pair, 128 samples, smoothing 2. Median **hot-path processing wall time in ms**:

| Profile | Before | Cached |
| --- | --- | --- |
| flat | 89.0 | 88.0 |
| bass | 390.5 | 99.5 |
| vocal | 625.0 | 99.0 |
| treble | 734.0 | 98.0 |
| smile | 864.5 | 99.0 |

These are QV4 processing measurements, not whole-shell CPU/GPU/RAM or FPS percentages. Numeric tests omit scene delegates; GPU tests use the complete production component. The independent owner observation is an unmatched 10-second baseline at installed `6959ad11a`, not an A/B result. Full canonical, installed integration, multi-output and owner acceptance remain distinct.

Retained fixture failures: the first all-combinations full-scene test was stopped because its synchronous delegate churn overwhelmed the harness; a second fixture tried to replace a read-only QML method and failed. Final fixtures instrument only a private copied method and execute numeric parity without delegate churn, then validate complete rendered components separately. Neither failure is reported as a source PASS.
