# Output-monitor capture qualification

The owner heard crackle during UI operations in the 18:30:48–18:31:13 capture on 2026-10-13 (Asia/Ho_Chi_Minh). Local Music and browser playback are affected with a non-Flat EQ/DSP preset even when visible Spectrum/CAVA is disabled. Reported triggers include Sidebar Right, Dashboard, Overview, Dock, Media Popup, and other Popups/Edgebars.

This capture is MIXED_SOURCE: the installed shell changed to 4848d5ae4 at 18:30:51, inside the sample interval. It cannot isolate a stable-source Popup cause or establish hardware versus software causation. Output monitors only were recorded; no microphone. Only numerical metrics are retained here; personal PCM is excluded. Absence of large derivative spikes, NaNs or sustained full-scale clipping does not exclude the reported audible fault.

An earlier command monitor followed a stale owner PID and is INVALID_FOR_DSP_EXEC_OBSERVATION; its zero command count is not evidence of zero writes. Earlier passive EQ tests and stable preset hashes provide narrower observations only. Native timeline samples showed UI event-loop/frame stalls, but no causal DSP/PipeWire fix or resource improvement has been established.

Next investigation must capture a stable installed source and current owner PID, correlate UI operations with the audible report and DSP command/graph events, and preserve the existing preset, routing and volume. AUDIO-I01 remains unresolved.
